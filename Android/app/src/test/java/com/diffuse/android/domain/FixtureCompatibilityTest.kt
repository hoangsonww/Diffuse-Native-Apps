package com.diffuse.android.domain

import kotlinx.serialization.json.Json
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class FixtureCompatibilityTest {
    private val root = File(requireNotNull(System.getProperty("diffuse.fixtures")))

    @Test
    fun allSwiftSnapshotsDecodeAndSelfDiffEmpty() {
        val files = File(root, "snapshots").listFiles { file -> file.extension == "json" }.orEmpty()
        assertEquals(5, files.size)
        files.forEach { file ->
            val snapshot = SnapshotJson.decodeSnapshot(file.readText())
            assertEquals(1, snapshot.schemaVersion)
            assertTrue(snapshot.sections.isNotEmpty())
            assertEquals(0, DiffEngine().diff(snapshot, snapshot).summary.totalChanges)
            assertEquals(snapshot, SnapshotJson.decodeSnapshot(SnapshotJson.encodeSnapshot(snapshot)))
        }
    }

    @Test
    fun KotlinDiffMatchesEverySwiftGoldenFixture() {
        val macBase = snapshot("mac-baseline")
        val macAfter = snapshot("mac-after-workday")
        val permission = snapshot("mac-permission-problem")
        val iosBase = snapshot("ios-baseline")
        val iosAfter = snapshot("ios-afternoon")
        val cases = listOf(
            Triple("mac-workday", macBase to macAfter, DiffOptions.Default),
            Triple("mac-workday-significant", macBase to macAfter, DiffOptions.SignificantOnly),
            Triple("mac-permission-loss", macAfter to permission, DiffOptions.Default),
            Triple("ios-day", iosBase to iosAfter, DiffOptions.Default),
        )
        cases.forEach { (name, pair, options) ->
            val actual = SnapshotJson.codec.parseToJsonElement(SnapshotJson.encodeDiff(DiffEngine(options).diff(pair.first, pair.second)))
            val expected = SnapshotJson.codec.parseToJsonElement(File(root, "diffs/$name.expected.json").readText())
            assertEquals("Golden diff mismatch: $name", expected, actual)
        }
    }

    @Test
    fun AndroidPlatformAndUnknownCapabilityFlowsThroughEveryGenericLayer() = runTest {
        val base = snapshot("ios-baseline")
        val schema = SectionSchema(
            "android.future", "Future Android observation", "Unknown to Apple builds", "system", "android",
            PrivacyClassification.LOCAL,
            listOf(EntityKindDescriptor("future", "Observation", properties = listOf(PropertyDescriptor("value", "Value")))),
        )
        val section = SnapshotSection(
            schema.capability, "android.future", "1.0.0", base.capturedAt, schema = schema,
            entities = listOf(SnapshotEntity(EntityIdentity.create("future", "one"), "One", properties = mapOf("value" to PropertyValue.string("ready")))),
        )
        val android = base.copy(id = "android-test", platform = "Android", sections = base.sections + section)
        val decoded = SnapshotJson.decodeSnapshot(SnapshotJson.encodeSnapshot(android))
        assertEquals("Android", decoded.platform)
        assertNotNull(decoded.section("android.future"))

        val changedSection = section.copy(
            collectedAt = "2026-08-19T16:00:00Z",
            entities = listOf(SnapshotEntity(EntityIdentity.create("future", "one"), "One", properties = mapOf("value" to PropertyValue.string("changed")))),
        )
        val changed = android.copy(id = "android-changed", capturedAt = "2026-08-19T16:00:00Z", sections = base.sections + changedSection)
        val diff = DiffEngine().diff(android, changed)
        assertEquals(1, diff.summary.totalChanges)
        assertTrue(ReportRenderer.markdown(diff).contains("Future Android observation"))
        assertTrue(SearchIndex.search(listOf(android), "ready").any { it.capability == "android.future" })
        assertEquals("‹redacted›", Privacy.redact(android, RedactionPolicy.STRICT).section("android.future")?.entities?.first()?.displayName)

        val directory = Files.createTempDirectory("diffuse-unknown-capability").toFile()
        try {
            val store = FileSnapshotStore(directory)
            store.save(android)
            assertNotNull(store.load(android.id)?.section("android.future"))
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun snapshot(name: String) = SnapshotJson.decodeSnapshot(File(root, "snapshots/$name.json").readText())
}
