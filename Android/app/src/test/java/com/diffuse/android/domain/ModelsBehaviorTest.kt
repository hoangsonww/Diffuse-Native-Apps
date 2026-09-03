package com.diffuse.android.domain

import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelsBehaviorTest {
    @Test
    fun redactionPoliciesAreMonotonicAcrossEveryClassification() {
        val classifications = PrivacyClassification.entries
        val none = classifications.filter(RedactionPolicy.NONE::redacts)
        val standard = classifications.filter(RedactionPolicy.STANDARD::redacts)
        val strict = classifications.filter(RedactionPolicy.STRICT::redacts)

        assertEquals(listOf(PrivacyClassification.RESTRICTED), none)
        assertEquals(listOf(PrivacyClassification.SENSITIVE, PrivacyClassification.RESTRICTED), standard)
        assertEquals(listOf(PrivacyClassification.LOCAL, PrivacyClassification.SENSITIVE, PrivacyClassification.RESTRICTED), strict)
        assertTrue(standard.containsAll(none))
        assertTrue(strict.containsAll(standard))
    }

    @Test
    fun severityEscalationAndDeescalationClampAtBounds() {
        assertEquals(ChangeSeverity.INFORMATIONAL, ChangeSeverity.INFORMATIONAL.deescalated())
        assertEquals(ChangeSeverity.NOTABLE, ChangeSeverity.INFORMATIONAL.escalated())
        assertEquals(ChangeSeverity.SIGNIFICANT, ChangeSeverity.CRITICAL.deescalated())
        assertEquals(ChangeSeverity.CRITICAL, ChangeSeverity.CRITICAL.escalated())
    }

    @Test
    fun collectionStatusFlagsAndNamesCoverEveryStatus() {
        assertEquals(setOf(CollectionStatus.COLLECTED, CollectionStatus.PARTIAL), CollectionStatus.entries.filter { it.hasData }.toSet())
        assertEquals(
            setOf(CollectionStatus.PARTIAL, CollectionStatus.UNAVAILABLE, CollectionStatus.PERMISSION_REQUIRED, CollectionStatus.TIMED_OUT, CollectionStatus.FAILED),
            CollectionStatus.entries.filter { it.isProblem }.toSet(),
        )
        assertEquals(CollectionStatus.entries.size, CollectionStatus.entries.map { it.displayName }.distinct().size)
        assertEquals("Not supported", CollectionStatus.UNSUPPORTED.displayName)
    }

    @Test
    fun everyComparisonRuleRoundTripsThroughItsTravellingJsonShape() {
        val rules = listOf(
            ComparisonRule.Exact,
            ComparisonRule.CaseInsensitive,
            ComparisonRule.PathNormalized,
            ComparisonRule.SemanticVersion,
            ComparisonRule.numeric(2.5),
            ComparisonRule.relative(0.1),
            ComparisonRule.Unordered,
            ComparisonRule.Ignored,
        )
        rules.forEach { rule ->
            val encoded = SnapshotJson.codec.encodeToString(ComparisonRuleSerializer, rule)
            assertEquals(rule, SnapshotJson.codec.decodeFromString(ComparisonRuleSerializer, encoded))
        }
    }

    @Test
    fun invalidComparisonRuleShapesAreRejected() {
        assertThrows(SerializationException::class.java) {
            SnapshotJson.codec.decodeFromString(ComparisonRuleSerializer, "{}")
        }
        assertThrows(SerializationException::class.java) {
            SnapshotJson.codec.decodeFromString(ComparisonRuleSerializer, "{\"futureRule\":{}}")
        }
    }

    @Test
    fun entityIdentitiesNormalizeWhitespacePathsScopesAndOrdering() {
        val identity = EntityIdentity.create("Disk", "  My\u00a0  Volume  ", " User Scope ")
        assertEquals("my volume", identity.value)
        assertEquals("user scope", identity.scope)
        assertEquals("Disk:user-scope_my-volume", identity.token)
        assertEquals("c:/users/me", EntityIdentity.normalizePath(" C:\\Users\\Me/// "))
        assertTrue(EntityIdentity("a", "z") < EntityIdentity("b", "a"))
    }

    @Test
    fun propertyValuesExposeTypedRepresentations() {
        assertEquals("hello", PropertyValue.string("hello").text())
        assertEquals(42.0, PropertyValue.integer(42).number()!!, 0.0)
        assertEquals(1.0, PropertyValue.boolean(true).number()!!, 0.0)
        assertEquals(0.0, PropertyValue.boolean(false).number()!!, 0.0)
        assertNull(PropertyValue.string("42").number())
        assertNull(PropertyValue.integer(42).text())
        assertTrue(PropertyValue.Absent.isAbsent)
    }

    @Test
    fun propertyFormattingCoversUnitsListsAndCompactPaths() {
        assertEquals("On", PropertyValue.boolean(true).formatted())
        assertEquals("Off", PropertyValue.boolean(false).formatted())
        assertEquals("999 bytes", PropertyValue.bytes(999).formatted())
        assertEquals("1.5 KB", PropertyValue.bytes(1_500).formatted())
        assertEquals("25%", PropertyValue.percentage(0.25).formatted())
        assertEquals("500 ms", PropertyValue.duration(0.5).formatted())
        assertEquals("45 s", PropertyValue.duration(45.0).formatted())
        assertEquals("2 min", PropertyValue.duration(120.0).formatted())
        assertEquals("1 hr 1 min", PropertyValue.duration(3_660.0).formatted())
        assertEquals("1.23", PropertyValue.double(1.234).formatted())
        assertEquals("file.txt", PropertyValue.path("/tmp/file.txt").formatted(compact = true))
        assertEquals("—", PropertyValue.Absent.formatted())

        val list = PropertyValue.list((1L..5L).map(PropertyValue::integer))
        assertEquals(5, list.list()?.size)
        assertEquals("1, 2, 3 +2 more", list.formatted(compact = true))
        assertEquals("1 2 3 4 5", list.searchText())
    }

    @Test
    fun entityFlatteningSearchAndAbsentPropertiesAreRecursive() {
        val child = testEntity("child", "Nested Adapter", mapOf("value" to PropertyValue.string("ethernet")), tags = setOf("wired"))
        val parent = testEntity("parent", "Network", children = listOf(child))

        assertEquals(listOf(parent, child), parent.flattened())
        assertTrue(child.searchText().contains("nested adapter"))
        assertTrue(child.searchText().contains("ethernet"))
        assertTrue(child.searchText().contains("wired"))
        assertTrue(parent.property("missing").isAbsent)
    }

    @Test
    fun travellingSchemaReturnsDeclaredAndSafeFallbackDescriptors() {
        val declared = testDescriptor("displayName", privacy = PrivacyClassification.SENSITIVE)
        val attribute = testDescriptor("count", severity = ChangeSeverity.INFORMATIONAL)
        val schema = testSchema(properties = listOf(declared), attributes = listOf(attribute))

        assertEquals(declared, schema.descriptor("item", "displayName"))
        assertEquals(attribute, schema.attribute("count"))
        val fallback = schema.descriptor("future-kind", "futureValue")
        assertEquals("Future Value", fallback.displayName)
        assertEquals(PrivacyClassification.LOCAL, fallback.privacy)
        assertNull(schema.kind("future-kind"))
    }

    @Test
    fun snapshotSummaryCountsNestedEntitiesAndProblems() {
        val child = testEntity("child")
        val collected = testSection(entities = listOf(testEntity(children = listOf(child))))
        val failedSchema = testSchema("failed")
        val failed = testSection(schema = failedSchema, status = CollectionStatus.FAILED, entities = emptyList())
        val snapshot = testSnapshot(sections = listOf(collected, failed), pinned = true, label = "Before update")

        val summary = SnapshotSummary.from(snapshot, bytes = 321)
        assertEquals(2, summary.sectionCount)
        assertEquals(2, summary.entityCount)
        assertTrue(summary.hasProblems)
        assertTrue(summary.isPinned)
        assertEquals(321, summary.approximateBytes)
        assertEquals(snapshot.reference().id, summary.id)
    }

    @Test
    fun snapshotCodingAcceptsEnvelopeLegacyShapeAndUnknownFields() {
        val snapshot = testSnapshot(label = "Before")
        val envelope = SnapshotJson.encodeSnapshot(snapshot)
        assertEquals(snapshot, SnapshotJson.decodeSnapshot(envelope))

        val legacy = SnapshotJson.codec.encodeToString(snapshot)
        assertEquals(snapshot, SnapshotJson.decodeSnapshot(legacy))

        val withUnknownField = envelope.replaceFirst("{", "{\n  \"futureEnvelopeField\": true,")
        assertEquals(snapshot, SnapshotJson.decodeSnapshot(withUnknownField))
        assertEquals(snapshot.capturedAt, SnapshotJson.instant(snapshot.capturedAt).toString())
    }

    @Test
    fun compactDoubleSerializerUsesIntegersOnlyWhenLossless() {
        val json = Json
        assertEquals("2", json.encodeToString(CompactDoubleSerializer, 2.0))
        assertEquals("2.5", json.encodeToString(CompactDoubleSerializer, 2.5))
        assertEquals(2.0, json.decodeFromString(CompactDoubleSerializer, "2"), 0.0)
    }

    @Test
    fun humanizedNamesHandleDotsUnderscoresAndCamelCase() {
        assertEquals("Os version Number", "os.version_Number".humanized())
        assertFalse("already human".humanized().isBlank())
    }
}

class ComparisonPairOrderingTest {
    private fun summary(id: String, capturedAt: String) = SnapshotSummary(
        id = id,
        capturedAt = capturedAt,
        platform = "android",
        deviceName = "Pixel",
        origin = Snapshot.Origin.MANUAL,
        sectionCount = 1,
        entityCount = 1,
        hasProblems = false,
    )

    private val older = summary("older", "2026-08-24T09:00:00Z")
    private val newer = summary("newer", "2026-08-25T09:00:00Z")
    private val all = listOf(newer, older)

    @Test
    fun aPairChosenNewestFirstIsStillDiffedOldestToNewest() {
        // Tapping down a newest-first list picks the newer one first. Diffing in
        // that order would report every addition as a removal.
        val ordered = SnapshotSummary.orderByCaptureTime(listOf("newer", "older"), all)

        assertEquals("older" to "newer", ordered)
    }

    @Test
    fun aPairChosenOldestFirstKeepsItsOrder() {
        assertEquals("older" to "newer", SnapshotSummary.orderByCaptureTime(listOf("older", "newer"), all))
    }

    @Test
    fun anIncompletePairHasNoOrdering() {
        assertNull(SnapshotSummary.orderByCaptureTime(emptyList(), all))
        assertNull(SnapshotSummary.orderByCaptureTime(listOf("older"), all))
        assertNull(SnapshotSummary.orderByCaptureTime(listOf("a", "b", "c"), all))
    }

    @Test
    fun anUnknownSnapshotHasNoOrdering() {
        // A selection can outlive the snapshot it names, if the other device
        // deleted it between a refresh and a tap.
        assertNull(SnapshotSummary.orderByCaptureTime(listOf("older", "ghost"), all))
        assertNull(SnapshotSummary.orderByCaptureTime(listOf("ghost", "older"), all))
    }

    @Test
    fun instantsAreComparedAsMomentsRatherThanAsStrings() {
        // ISO_INSTANT omits the fractional part when it is zero, so
        // "…:30Z" sorts *after* "…:30.123Z" as text while being earlier in time.
        // Comparing the strings would put these the wrong way round.
        val whole = summary("whole", "2026-08-24T09:00:30Z")
        val fractional = summary("fractional", "2026-08-24T09:00:30.123Z")
        val pair = listOf(fractional, whole)

        assertTrue("the text comparison this guards against", "2026-08-24T09:00:30Z" > "2026-08-24T09:00:30.123Z")
        assertEquals("whole" to "fractional", SnapshotSummary.orderByCaptureTime(listOf("fractional", "whole"), pair))
    }

    @Test
    fun anUnparseableTimestampFallsBackToTheOrderGiven() {
        // Imported or hand-edited data can carry something that is not an
        // instant. That must not crash the comparison; it degrades to the
        // order the pair arrived in.
        val broken = summary("broken", "not-a-timestamp")
        val pair = listOf(older, broken)

        assertEquals("older" to "broken", SnapshotSummary.orderByCaptureTime(listOf("older", "broken"), pair))
    }
}
