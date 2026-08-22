package com.diffuse.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DiffEngineBehaviorTest {
    @Test
    fun selfDiffIsEmptyAndRecordsUnchangedEntities() {
        val snapshot = testSnapshot()
        val diff = DiffEngine().diff(snapshot, snapshot)

        assertEquals(0, diff.summary.totalChanges)
        assertEquals(1, diff.summary.comparedSections)
        assertEquals(1, diff.sectionDiffs.single().unchangedEntityCount)
        assertTrue(diff.changes.isEmpty())
    }

    @Test
    fun exactRuleReportsChangedPropertyAndElapsedTime() {
        val (base, target) = changedSnapshot()
        val diff = DiffEngine().diff(base, target)

        val change = diff.changes.single()
        assertEquals(ChangeKind.MODIFIED, change.kind)
        assertEquals("value", change.property?.key)
        assertEquals("before", change.property?.before?.text())
        assertEquals("after", change.property?.after?.text())
        assertEquals(300.0, diff.summary.elapsed, 0.0)
    }

    @Test
    fun caseInsensitiveAndNormalizedPathRulesIgnoreEquivalentValues() {
        val casePair = changedSnapshot(
            PropertyValue.string("  ANDROID "),
            PropertyValue.string("android"),
            testDescriptor(comparison = ComparisonRule.CaseInsensitive),
        )
        assertEquals(0, DiffEngine().diff(casePair.first, casePair.second).summary.totalChanges)

        val pathPair = changedSnapshot(
            PropertyValue.path("C:\\Users\\Me\\"),
            PropertyValue.path("c:/users/me"),
            testDescriptor(comparison = ComparisonRule.PathNormalized),
        )
        assertEquals(0, DiffEngine().diff(pathPair.first, pathPair.second).summary.totalChanges)
    }

    @Test
    fun unorderedRuleIgnoresOrderButDetectsMembershipChanges() {
        val descriptor = testDescriptor(comparison = ComparisonRule.Unordered)
        val reordered = changedSnapshot(
            PropertyValue.list(listOf(PropertyValue.string("wifi"), PropertyValue.string("vpn"))),
            PropertyValue.list(listOf(PropertyValue.string("vpn"), PropertyValue.string("wifi"))),
            descriptor,
        )
        assertEquals(0, DiffEngine().diff(reordered.first, reordered.second).summary.totalChanges)

        val changed = changedSnapshot(
            PropertyValue.list(listOf(PropertyValue.string("wifi"))),
            PropertyValue.list(listOf(PropertyValue.string("ethernet"))),
            descriptor,
        )
        assertEquals(1, DiffEngine().diff(changed.first, changed.second).summary.totalChanges)
    }

    @Test
    fun ignoredRuleNeverReportsAPropertyChange() {
        val pair = changedSnapshot(
            PropertyValue.date("2026-08-19T00:00:00Z"),
            PropertyValue.date("2026-08-20T00:00:00Z"),
            testDescriptor(comparison = ComparisonRule.Ignored),
        )
        assertEquals(0, DiffEngine().diff(pair.first, pair.second).summary.totalChanges)
    }

    @Test
    fun numericToleranceIncludesBoundaryAndReportsBeyondIt() {
        val descriptor = testDescriptor(comparison = ComparisonRule.numeric(2.0))
        val boundary = changedSnapshot(PropertyValue.double(10.0), PropertyValue.double(12.0), descriptor)
        assertEquals(0, DiffEngine().diff(boundary.first, boundary.second).summary.totalChanges)

        val beyond = changedSnapshot(PropertyValue.double(10.0), PropertyValue.double(12.1), descriptor)
        val change = DiffEngine().diff(beyond.first, beyond.second).changes.single()
        assertTrue(change.confidence in 0.5..1.0)
        assertNotNull(change.detail)
    }

    @Test
    fun numericDateRuleComparesInstantSeconds() {
        val descriptor = testDescriptor(comparison = ComparisonRule.numeric(120.0))
        val within = changedSnapshot(
            PropertyValue.date("2026-08-19T12:00:00Z"),
            PropertyValue.date("2026-08-19T12:02:00Z"),
            descriptor,
        )
        assertEquals(0, DiffEngine().diff(within.first, within.second).summary.totalChanges)

        val beyond = changedSnapshot(
            PropertyValue.date("2026-08-19T12:00:00Z"),
            PropertyValue.date("2026-08-19T12:02:01Z"),
            descriptor,
        )
        assertEquals(1, DiffEngine().diff(beyond.first, beyond.second).summary.totalChanges)
    }

    @Test
    fun relativeRuleUsesScaleAndEscalatesLargeChanges() {
        val descriptor = testDescriptor(comparison = ComparisonRule.relative(0.1), severity = ChangeSeverity.NOTABLE)
        val within = changedSnapshot(PropertyValue.bytes(100), PropertyValue.bytes(110), descriptor)
        assertEquals(0, DiffEngine().diff(within.first, within.second).summary.totalChanges)

        val beyond = changedSnapshot(PropertyValue.bytes(100), PropertyValue.bytes(200), descriptor)
        assertEquals(ChangeSeverity.SIGNIFICANT, DiffEngine().diff(beyond.first, beyond.second).changes.single().severity)
    }

    @Test
    fun semanticVersionsApplyTransitionSeverityRules() {
        val descriptor = testDescriptor(comparison = ComparisonRule.SemanticVersion, severity = ChangeSeverity.NOTABLE)
        fun severity(before: String, after: String) = DiffEngine().diff(
            changedSnapshot(PropertyValue.version(before), PropertyValue.version(after), descriptor).let { it.first },
            changedSnapshot(PropertyValue.version(before), PropertyValue.version(after), descriptor).let { it.second },
        ).changes.single().severity

        assertEquals(ChangeSeverity.SIGNIFICANT, severity("1.2.3", "2.0.0"))
        assertEquals(ChangeSeverity.NOTABLE, severity("1.2.3", "1.3.0"))
        assertEquals(ChangeSeverity.INFORMATIONAL, severity("1.2.3", "1.2.4"))
        assertEquals(ChangeSeverity.INFORMATIONAL, severity("1.2.3-alpha.1", "1.2.3-alpha.2"))
        assertEquals(ChangeSeverity.SIGNIFICANT, severity("2.0.0", "1.9.0"))
    }

    @Test
    fun semanticVersionsIgnoreBuildMetadataAndAcceptVPrefix() {
        val descriptor = testDescriptor(comparison = ComparisonRule.SemanticVersion)
        val pair = changedSnapshot(PropertyValue.version("v1.2.3+4"), PropertyValue.version("V1.2.3+99"), descriptor)
        assertEquals(0, DiffEngine().diff(pair.first, pair.second).summary.totalChanges)
    }

    @Test
    fun invalidSemanticVersionsFallBackToExactComparison() {
        val descriptor = testDescriptor(comparison = ComparisonRule.SemanticVersion)
        val same = changedSnapshot(PropertyValue.version("preview"), PropertyValue.version("preview"), descriptor)
        assertEquals(0, DiffEngine().diff(same.first, same.second).summary.totalChanges)
        val changed = changedSnapshot(PropertyValue.version("preview"), PropertyValue.version("release"), descriptor)
        assertEquals(1, DiffEngine().diff(changed.first, changed.second).summary.totalChanges)
    }

    @Test
    fun addingAndRemovingValuesEscalatesDescriptorSeverity() {
        val descriptor = testDescriptor(severity = ChangeSeverity.NOTABLE)
        val added = changedSnapshot(PropertyValue.Absent, PropertyValue.string("new"), descriptor)
        val removed = changedSnapshot(PropertyValue.string("old"), PropertyValue.Absent, descriptor)
        assertEquals(ChangeSeverity.SIGNIFICANT, DiffEngine().diff(added.first, added.second).changes.single().severity)
        assertEquals(ChangeSeverity.SIGNIFICANT, DiffEngine().diff(removed.first, removed.second).changes.single().severity)
    }

    @Test
    fun entityAdditionRemovalAndUnchangedUseSchemaSeverities() {
        val schema = testSchema(additionSeverity = ChangeSeverity.INFORMATIONAL, removalSeverity = ChangeSeverity.CRITICAL)
        val empty = testSnapshot(sections = listOf(testSection(schema = schema, entities = emptyList())))
        val populated = testSnapshot(id = "target", at = TARGET_TIME, sections = listOf(testSection(schema = schema, at = TARGET_TIME)))

        assertEquals(ChangeSeverity.INFORMATIONAL, DiffEngine().diff(empty, populated).changes.single().severity)
        assertEquals(ChangeSeverity.CRITICAL, DiffEngine().diff(populated, empty.copy(id = "later", capturedAt = TARGET_TIME)).changes.single().severity)

        val unchanged = DiffEngine(DiffOptions(includeUnchanged = true)).diff(populated, populated).changes.single()
        assertEquals(ChangeKind.UNCHANGED, unchanged.kind)
        assertEquals(ChangeSeverity.INFORMATIONAL, unchanged.severity)
    }

    @Test
    fun displayNameChangesAreReportedUnlessAPropertyAlreadyDescribesThem() {
        val schema = testSchema()
        val before = testSnapshot(sections = listOf(testSection(schema = schema, entities = listOf(testEntity(name = "Old name")))))
        val after = testSnapshot(
            id = "target",
            at = TARGET_TIME,
            sections = listOf(testSection(schema = schema, at = TARGET_TIME, entities = listOf(testEntity(name = "New name")))),
        )
        val change = DiffEngine().diff(before, after).changes.single()
        assertEquals("__displayName", change.property?.key)
        assertEquals("Old name", change.property?.before?.text())
        assertEquals("New name", change.property?.after?.text())
    }

    @Test
    fun attributesUseSchemaRulesAndFutureAttributeFallbacks() {
        val attribute = testDescriptor("count", comparison = ComparisonRule.numeric(1.0), severity = ChangeSeverity.SIGNIFICANT)
        val schema = testSchema(attributes = listOf(attribute))
        val base = testSnapshot(sections = listOf(testSection(schema = schema, attributes = mapOf("count" to PropertyValue.integer(1)))))
        val within = testSnapshot(id = "within", at = TARGET_TIME, sections = listOf(testSection(schema = schema, at = TARGET_TIME, attributes = mapOf("count" to PropertyValue.integer(2)))))
        assertEquals(0, DiffEngine().diff(base, within).summary.totalChanges)

        val changed = within.copy(
            id = "changed",
            sections = listOf(testSection(schema = schema, at = TARGET_TIME, attributes = mapOf("count" to PropertyValue.integer(3), "future" to PropertyValue.string("yes")))),
        )
        val changes = DiffEngine().diff(base, changed).changes
        assertEquals(setOf("count", "future"), changes.mapNotNull { it.property?.key }.toSet())
    }

    @Test
    fun statusChangesHavePurposefulSeverityAndCanBeDisabled() {
        val schema = testSchema()
        val collected = testSnapshot(sections = listOf(testSection(schema = schema)))
        val permission = testSnapshot(id = "permission", at = TARGET_TIME, sections = listOf(testSection(schema = schema, at = TARGET_TIME, status = CollectionStatus.PERMISSION_REQUIRED, entities = emptyList())))
        val change = DiffEngine().diff(collected, permission).changes.single()
        assertEquals(ChangeSeverity.SIGNIFICANT, change.severity)
        assertTrue(change.detail.orEmpty().contains("could not read"))

        val ignored = DiffEngine(DiffOptions(includeStatusChanges = false)).diff(collected, permission)
        assertEquals(0, ignored.summary.totalChanges)
    }

    @Test
    fun newlyAvailableDataComparesEntitiesAfterStatusRecovery() {
        val schema = testSchema()
        val unavailable = testSnapshot(sections = listOf(testSection(schema = schema, status = CollectionStatus.UNAVAILABLE, entities = emptyList())))
        val recovered = testSnapshot(id = "recovered", at = TARGET_TIME, sections = listOf(testSection(schema = schema, at = TARGET_TIME)))
        val diff = DiffEngine().diff(unavailable, recovered)
        assertEquals(2, diff.summary.totalChanges)
        assertTrue(diff.changes.any { it.property?.key == "__status" })
        assertTrue(diff.changes.any { it.kind == ChangeKind.ADDED })
    }

    @Test
    fun sectionPresenceIsAsymmetricAndCapabilityFiltersAreApplied() {
        val extraSchema = testSchema("extra")
        val base = testSnapshot(sections = emptyList())
        val target = testSnapshot(id = "target", at = TARGET_TIME, sections = listOf(testSection(schema = extraSchema, at = TARGET_TIME)))
        val diff = DiffEngine().diff(base, target)
        assertEquals(listOf("extra"), diff.summary.asymmetricSections)
        assertEquals(ChangeKind.ADDED, diff.changes.single().kind)

        assertEquals(0, DiffEngine(DiffOptions(excludedCapabilities = setOf("extra"))).diff(base, target).summary.comparedSections)
        assertEquals(0, DiffEngine(DiffOptions(includedCapabilities = setOf("other"))).diff(base, target).summary.comparedSections)
        assertTrue(DiffOptions(includedCapabilities = setOf("extra")).allows("extra"))
        assertFalse(DiffOptions(excludedCapabilities = setOf("extra")).allows("extra"))
    }

    @Test
    fun severityFilterRemovesLowerPriorityChanges() {
        val low = testDescriptor("low", severity = ChangeSeverity.INFORMATIONAL)
        val high = testDescriptor("high", severity = ChangeSeverity.CRITICAL)
        val schema = testSchema(properties = listOf(low, high))
        val baseEntity = testEntity(properties = mapOf("low" to PropertyValue.string("a"), "high" to PropertyValue.string("a")))
        val targetEntity = testEntity(properties = mapOf("low" to PropertyValue.string("b"), "high" to PropertyValue.string("b")))
        val base = testSnapshot(sections = listOf(testSection(schema = schema, entities = listOf(baseEntity))))
        val target = testSnapshot(id = "target", at = TARGET_TIME, sections = listOf(testSection(schema = schema, at = TARGET_TIME, entities = listOf(targetEntity))))

        val diff = DiffEngine(DiffOptions.SignificantOnly).diff(base, target)
        assertEquals(listOf("high"), diff.changes.mapNotNull { it.property?.key })
    }

    @Test
    fun childEntitiesCanBeIncludedOrIgnored() {
        val schema = testSchema()
        val childBefore = testEntity("child", properties = mapOf("value" to PropertyValue.string("a")))
        val childAfter = testEntity("child", properties = mapOf("value" to PropertyValue.string("b")))
        val base = testSnapshot(sections = listOf(testSection(schema = schema, entities = listOf(testEntity(children = listOf(childBefore))))))
        val target = testSnapshot(id = "target", at = TARGET_TIME, sections = listOf(testSection(schema = schema, at = TARGET_TIME, entities = listOf(testEntity(children = listOf(childAfter))))))

        assertEquals(1, DiffEngine().diff(base, target).summary.totalChanges)
        assertEquals(0, DiffEngine(DiffOptions(includeChildren = false)).diff(base, target).summary.totalChanges)
    }

    @Test
    fun nearbyChangesClusterWhileSeparatedChangesDoNot() {
        val schemaA = testSchema("a")
        val schemaB = testSchema("b")
        val base = testSnapshot(sections = listOf(testSection(schemaA), testSection(schemaB)))
        val target = testSnapshot(
            id = "target",
            at = TARGET_TIME,
            sections = listOf(
                testSection(schemaA, at = "2026-08-19T12:05:00Z", entities = listOf(testEntity(properties = mapOf("value" to PropertyValue.string("after"))))),
                testSection(schemaB, at = "2026-08-19T12:05:30Z", entities = listOf(testEntity(properties = mapOf("value" to PropertyValue.string("after"))))),
            ),
        )
        val clustered = DiffEngine(DiffOptions(correlationWindowSeconds = 60.0, minimumClusterSize = 2)).diff(base, target)
        assertEquals(1, clustered.clusters.size)
        assertEquals(setOf("a", "b"), clustered.clusters.single().capabilities.toSet())

        val unclustered = DiffEngine(DiffOptions(correlationWindowSeconds = 10.0, minimumClusterSize = 2)).diff(base, target)
        assertTrue(unclustered.clusters.isEmpty())
        assertTrue(DiffEngine(DiffOptions(correlationWindowSeconds = 0.0)).diff(base, target).clusters.isEmpty())
    }
}
