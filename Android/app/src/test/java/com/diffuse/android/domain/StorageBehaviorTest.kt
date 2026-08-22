package com.diffuse.android.domain

import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files

class StorageBehaviorTest {
    private lateinit var directory: File
    private lateinit var store: FileSnapshotStore

    @Before
    fun createStore() {
        directory = Files.createTempDirectory("diffuse-storage-test").toFile()
        store = FileSnapshotStore(directory)
    }

    @After
    fun removeStore() {
        directory.deleteRecursively()
    }

    @Test
    fun snapshotsRoundTripAndDuplicateIdentifiersAreRejected() = runTest {
        val snapshot = testSnapshot(label = "Before", pinned = true)
        store.save(snapshot)
        assertEquals(snapshot, store.load(snapshot.id))

        assertThrows(IllegalStateException::class.java) { runTest { store.save(snapshot) } }
    }

    @Test
    fun missingSnapshotsReturnNullAndMutationsAreNoOps() = runTest {
        assertNull(store.load("missing"))
        store.annotate("missing", label = "Ignored", pinned = true)
        store.setLabel("missing", "Ignored")
        store.delete("missing")
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun pathUnsafeIdentifiersAreSanitizedWithoutChangingStoredIdentity() = runTest {
        val snapshot = testSnapshot(id = "folder/../unsafe:id")
        store.save(snapshot)

        assertEquals(snapshot, store.load(snapshot.id))
        val files = File(directory, "snapshots").listFiles().orEmpty()
        assertEquals(1, files.size)
        assertFalse(files.single().name.contains('/'))
        assertFalse(files.single().name.contains(':'))
    }

    @Test
    fun allSortsNewestFirstAndUsesDescendingIdentifierForTies() = runTest {
        store.save(testSnapshot(id = "a", at = BASE_TIME))
        store.save(testSnapshot(id = "z", at = BASE_TIME))
        store.save(testSnapshot(id = "later", at = TARGET_TIME))

        assertEquals(listOf("later", "z", "a"), store.all().map { it.id })
    }

    @Test
    fun corruptAndUnrelatedFilesDoNotPoisonTheLibrary() = runTest {
        store.save(testSnapshot(id = "valid"))
        File(directory, "snapshots/corrupt.json").writeText("not json")
        File(directory, "snapshots/readme.txt").writeText("ignored")

        assertEquals(listOf("valid"), store.all().map { it.id })
        assertEquals(3, File(directory, "snapshots").listFiles().orEmpty().size)
    }

    @Test
    fun summariesIncludeOnDiskBytesAndDerivedCounts() = runTest {
        val child = testEntity("child")
        store.save(testSnapshot(sections = listOf(testSection(entities = listOf(testEntity(children = listOf(child)))))))

        val summary = store.summaries().single()
        assertEquals(2, summary.entityCount)
        assertEquals(1, summary.sectionCount)
        assertTrue(summary.approximateBytes > 0)
        assertEquals(summary.approximateBytes, store.size())
    }

    @Test
    fun annotateCanUpdateOneFieldWithoutDiscardingTheOther() = runTest {
        store.save(testSnapshot(id = "one", label = "Original", pinned = false))
        store.annotate("one", pinned = true)
        assertEquals("Original", store.load("one")?.label)
        assertTrue(store.load("one")?.isPinned == true)

        store.annotate("one", label = "Renamed")
        assertEquals("Renamed", store.load("one")?.label)
        assertTrue(store.load("one")?.isPinned == true)
    }

    @Test
    fun setLabelCanExplicitlyClearALabel() = runTest {
        store.save(testSnapshot(id = "one", label = "Temporary"))
        store.setLabel("one", null)
        assertNull(store.load("one")?.label)
    }

    @Test
    fun deleteRemovesOneSnapshotAndDeleteAllRemovesTheRest() = runTest {
        store.save(testSnapshot(id = "one"))
        store.save(testSnapshot(id = "two", at = TARGET_TIME))
        store.delete("one")
        assertEquals(listOf("two"), store.all().map { it.id })

        store.deleteAll()
        assertTrue(store.all().isEmpty())
        assertEquals(0, store.size())
    }
}
