package com.diffuse.android.domain

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant

class PrivacyRetentionStorageTest {
    @Test
    fun redactionIsCopyAndRestrictedNeverExports() {
        val descriptor = PropertyDescriptor("secret", "Secret", privacy = PrivacyClassification.RESTRICTED, isPrimary = true)
        val schema = SectionSchema(
            "test", "Test", "Test", "system", "lock", PrivacyClassification.LOCAL,
            listOf(EntityKindDescriptor("item", "Item", properties = listOf(descriptor))),
        )
        val section = SnapshotSection(
            "test", "test", "1.0.0", "2026-08-19T00:00:00Z", schema = schema,
            entities = listOf(SnapshotEntity(EntityIdentity.create("item", "one"), "Secret name", properties = mapOf("secret" to PropertyValue.string("token")))),
        )
        val original = snapshot("one", "2026-08-19T00:00:00Z", listOf(section))
        val redacted = Privacy.redact(original, RedactionPolicy.NONE)
        assertEquals("token", original.sections[0].entities[0].property("secret").text())
        assertEquals("‹redacted›", redacted.sections[0].entities[0].property("secret").text())
        assertEquals("‹redacted›", redacted.sections[0].entities[0].displayName)
        assertEquals("‹redacted›", redacted.device.id)
        assertEquals("Phone", redacted.device.name)

        val standard = Privacy.redact(original.copy(device = original.device.copy(name = "My Pixel")), RedactionPolicy.STANDARD)
        assertEquals("‹redacted›", standard.device.id)
        assertEquals("‹redacted›", standard.device.name)

        val strictSource = original.copy(label = "Before work", note = "VPN details", tags = setOf("work"))
        val strict = Privacy.redact(strictSource, RedactionPolicy.STRICT)
        assertEquals("‹redacted›", strict.label)
        assertEquals("‹redacted›", strict.note)
        assertTrue(strict.tags.isEmpty())
        assertTrue(strict.sections[0].entities[0].identity.value.startsWith("redacted-"))

        val (left, right) = Privacy.redactPair(strictSource, strictSource.copy(id = "two"), RedactionPolicy.STRICT)
        assertEquals(left.sections[0].entities[0].identity, right.sections[0].entities[0].identity)
    }

    @Test
    fun newestPinnedAndLabelledAreProtected() {
        val summaries = listOf(
            summary("new", "2026-08-19T04:00:00Z"),
            summary("old", "2026-01-01T00:00:00Z"),
            summary("pinned", "2026-01-02T00:00:00Z", pinned = true),
            summary("labelled", "2026-01-03T00:00:00Z", label = "Before update"),
        )
        val deleted = RetentionPlanner.plan(summaries, RetentionPolicy(days = 30), Instant.parse("2026-08-20T00:00:00Z"))
        assertEquals(listOf("old"), deleted)
        assertFalse("new" in deleted)
        assertFalse("pinned" in deleted)
        assertFalse("labelled" in deleted)
    }

    @Test
    fun newestConsumesCountQuotaButPinnedDoesNot() {
        val summaries = listOf(
            summary("new", "2026-08-19T04:00:00Z"),
            summary("pinned", "2026-08-19T03:00:00Z", pinned = true),
            summary("old", "2026-08-19T02:00:00Z"),
        )
        assertEquals(
            listOf("old"),
            RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = null, maximumCount = 1)),
        )
    }

    @Test
    fun newestConsumesByteQuotaAndAlwaysSurvives() {
        val summaries = listOf(
            summary("new", "2026-08-19T04:00:00Z", bytes = 100),
            summary("old", "2026-08-19T03:00:00Z", bytes = 75),
        )
        assertEquals(listOf("old"), RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = 150)))
        assertTrue(RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = 1)).let { "new" !in it })
    }

    @Test
    fun equalTimestampsUseIdentifierTieBreakForNewestAndQuotaOrder() {
        val summaries = listOf(
            summary("z", "2026-08-19T04:00:00Z"),
            summary("a", "2026-08-19T04:00:00Z"),
        )
        assertEquals(
            listOf("z"),
            RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = null, maximumCount = 0)),
        )
    }

    @Test
    fun redactionAliasesNeverUseTheLossyDisplayTokenAsIdentity() {
        val schema = SectionSchema("paths", "Paths", "Paths", "test", "folder", PrivacyClassification.SENSITIVE)
        val entities = listOf(
            SnapshotEntity(EntityIdentity("path", "a/b"), "Slash"),
            SnapshotEntity(EntityIdentity("path", "a_b"), "Underscore"),
        )
        val source = snapshot(
            "paths", "2026-08-19T00:00:00Z",
            listOf(SnapshotSection("paths", "test", "1.0.0", "2026-08-19T00:00:00Z", schema = schema, entities = entities)),
        )
        val redacted = Privacy.redact(source, RedactionPolicy.STANDARD)
        assertEquals(2, redacted.sections.single().entities.map { it.identity }.distinct().size)
    }

    @Test
    fun fileStoreSavesAnnotatesAndDeletes() = runTest {
        val directory = Files.createTempDirectory("diffuse-android-test").toFile()
        try {
            val store = FileSnapshotStore(directory)
            store.save(snapshot("one", "2026-08-19T00:00:00Z"))
            assertEquals(1, store.summaries().size)
            store.annotate("one", label = "Before")
            assertEquals("Before", store.load("one")?.label)
            store.delete("one")
            assertTrue(store.summaries().isEmpty())
        } finally { directory.deleteRecursively() }
    }

    private fun snapshot(id: String, at: String, sections: List<SnapshotSection> = emptyList()) = Snapshot(
        id = id, capturedAt = at, platform = "Android",
        device = DeviceIdentity("install", "Phone", "model", "Android", "17.0.0", "arm64-v8a"),
        sections = sections,
    )

    private fun summary(id: String, at: String, pinned: Boolean = false, label: String? = null, bytes: Long = 100) = SnapshotSummary(
        id, at, "Android", "Phone", Snapshot.Origin.MANUAL, label, pinned, emptySet(), 1, 1, false, bytes,
    )
}
