package com.diffuse.android.core

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import com.diffuse.android.domain.DeviceIdentity
import com.diffuse.android.domain.EntityIdentity
import com.diffuse.android.domain.EntityKindDescriptor
import com.diffuse.android.domain.PrivacyClassification
import com.diffuse.android.domain.PropertyDescriptor
import com.diffuse.android.domain.PropertyValue
import com.diffuse.android.domain.RedactionPolicy
import com.diffuse.android.domain.SectionSchema
import com.diffuse.android.domain.Snapshot
import com.diffuse.android.domain.SnapshotEntity
import com.diffuse.android.domain.SnapshotJson
import com.diffuse.android.domain.SnapshotSection
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

class DiffuseServiceInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun resetLibrary() {
        File(context.filesDir, "diffuse").deleteRecursively()
        context.getSharedPreferences("diffuse.preferences", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun capturePersistsEveryEnabledCollectorAndBuildsAnOverview() = runBlocking {
        val service = DiffuseService(context)
        val first = service.capture()
        val second = service.capture()

        assertTrue(first.persisted)
        assertTrue(second.persisted)
        assertEquals(service.registry.collectors.size, first.snapshot.sections.size)
        assertEquals(service.registry.collectors.map { it.metadata.id }.toSet(), first.snapshot.sections.map { it.capability }.toSet())
        assertEquals(2, service.summaries().size)
        assertNotNull(service.overview().latest)
        assertNotNull(service.overview().diff)
        assertTrue(service.search("network").any { it.capability?.startsWith("network.") == true })
        assertTrue(service.storageSize() > 0)
    }

    @Test
    fun disabledCapabilityTravelsAsSkippedAndIsRecordedInMetadata() = runBlocking {
        val service = DiffuseService(context)
        val disabled = service.registry.collectors.first().metadata.id
        service.preferences.setEnabled(disabled, false)

        val snapshot = service.capture().snapshot
        assertEquals(listOf(disabled), snapshot.metadata.skippedCapabilities)
        assertEquals(com.diffuse.android.domain.CollectionStatus.SKIPPED, snapshot.section(disabled)?.status)
    }

    @Test
    fun importAllocatesLocalIdentityAndPreservesUnknownCapability() = runBlocking {
        val service = DiffuseService(context)
        val source = snapshot("external", "before")

        val imported = service.importSnapshot(SnapshotJson.encodeSnapshot(source))

        assertNotEquals(source.id, imported.id)
        assertEquals(Snapshot.Origin.IMPORTED, imported.origin)
        assertTrue("imported" in imported.tags)
        assertNotNull(service.snapshot(imported.id)?.section("android.future"))
    }

    @Test
    fun importRejectsUnsupportedSchemasAndDuplicateCapabilities() {
        val service = DiffuseService(context)
        val unsupported = snapshot("unsupported", "value").copy(schemaVersion = 2)
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { service.importSnapshot(SnapshotJson.encodeSnapshot(unsupported)) }
        }

        val valid = snapshot("duplicate", "value")
        val duplicate = valid.copy(sections = valid.sections + valid.sections.single())
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { service.importSnapshot(SnapshotJson.encodeSnapshot(duplicate)) }
        }
    }

    @Test
    fun exportsApplyConfiguredRedactionAndReportsCompareImportedSnapshots() = runBlocking {
        val service = DiffuseService(context)
        service.preferences.redaction = RedactionPolicy.STANDARD
        val first = service.importSnapshot(SnapshotJson.encodeSnapshot(snapshot("first", "secret-one", "2026-08-19T12:00:00Z")))
        val second = service.importSnapshot(SnapshotJson.encodeSnapshot(snapshot("second", "secret-two", "2026-08-19T13:00:00Z")))

        val exported = SnapshotJson.decodeSnapshot(requireNotNull(service.exportSnapshot(first.id)))
        assertEquals("‹redacted›", exported.sections.single().entities.single().property("secret").text())
        assertEquals(RedactionPolicy.STANDARD, exported.metadata.appliedRedaction)

        val report = requireNotNull(service.exportReport(first.id, second.id))
        assertTrue(report.contains("Diffuse report"))
        assertFalse(report.contains("secret-one"))
        assertFalse(report.contains("secret-two"))
    }

    @Test
    fun annotationSearchDeleteAndDeleteAllFormACompleteLibraryFlow() = runBlocking {
        val service = DiffuseService(context)
        val first = service.importSnapshot(SnapshotJson.encodeSnapshot(snapshot("first", "alpha")))
        val second = service.importSnapshot(SnapshotJson.encodeSnapshot(snapshot("second", "beta", "2026-08-19T13:00:00Z")))

        service.annotate(first.id, label = "Before update", pinned = true)
        assertEquals("Before update", service.snapshot(first.id)?.label)
        assertTrue(service.snapshot(first.id)?.isPinned == true)
        assertEquals(first.id, service.search("before update").single().snapshotID)

        service.delete(second.id)
        assertEquals(listOf(first.id), service.summaries().map { it.id })
        service.deleteAll()
        assertTrue(service.summaries().isEmpty())
    }

    private fun snapshot(id: String, value: String, at: String = "2026-08-19T12:00:00Z"): Snapshot {
        val descriptor = PropertyDescriptor("secret", "Secret", privacy = PrivacyClassification.SENSITIVE, isPrimary = true)
        val schema = SectionSchema(
            "android.future",
            "Future Android",
            "An unknown travelling capability",
            "test",
            "science",
            PrivacyClassification.LOCAL,
            listOf(EntityKindDescriptor("item", "Item", properties = listOf(descriptor))),
        )
        val section = SnapshotSection(
            schema.capability,
            "test.future",
            "1.0.0",
            at,
            schema = schema,
            entities = listOf(
                SnapshotEntity(
                    EntityIdentity.create("item", "one"),
                    "Secret item",
                    properties = mapOf("secret" to PropertyValue.string(value)),
                ),
            ),
        )
        return Snapshot(
            id,
            capturedAt = at,
            platform = "Android",
            device = DeviceIdentity("external", "Pixel", "Pixel", "Android", "14", "arm64"),
            sections = listOf(section),
        )
    }
}
