package com.diffuse.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchAndReportsBehaviorTest {
    @Test
    fun blankQueriesReturnNoResults() {
        assertTrue(SearchIndex.search(listOf(testSnapshot()), "   \n  ").isEmpty())
    }

    @Test
    fun snapshotMetadataSearchIsCaseInsensitiveAndRequiresEveryTerm() {
        val snapshot = testSnapshot(label = "Before Flight", note = "Office VPN", tags = setOf("travel"))
        val results = SearchIndex.search(listOf(snapshot), "BEFORE vpn")

        assertEquals(1, results.size)
        assertEquals(snapshot.id, results.single().snapshotID)
        assertEquals("Before Flight", results.single().title)
        assertFalse(SearchIndex.search(listOf(snapshot), "before ethernet").isNotEmpty())
    }

    @Test
    fun entitySearchIncludesSectionNamesIdentitySubtitleTagsAndProperties() {
        val entity = SnapshotEntity(
            EntityIdentity.create("item", "wlan0"),
            "Wireless adapter",
            "Primary interface",
            properties = mapOf("address" to PropertyValue.string("192.0.2.1")),
            tags = setOf("active"),
        )
        val schema = testSchema("network.interfaces", properties = listOf(testDescriptor("address")))
        val snapshot = testSnapshot(sections = listOf(testSection(schema, entities = listOf(entity))))

        listOf("network wlan0", "primary interface", "192.0.2.1", "wireless active").forEach { query ->
            val results = SearchIndex.search(listOf(snapshot), query)
            assertEquals("Unexpected result count for query: $query", 1, results.size)
            val result = results.single()
            assertEquals("network.interfaces", result.capability)
            assertEquals("Wireless adapter", result.title)
        }
    }

    @Test
    fun nestedEntitiesAreSearchable() {
        val child = testEntity("child", "Nested USB adapter", mapOf("value" to PropertyValue.string("connected")))
        val snapshot = testSnapshot(sections = listOf(testSection(entities = listOf(testEntity(children = listOf(child))))))
        assertEquals("Nested USB adapter", SearchIndex.search(listOf(snapshot), "usb connected").single().title)
    }

    @Test
    fun emptyUnavailableAndFutureSectionsRemainSearchableByTravellingSchema() {
        val schema = testSchema("android.future.network", properties = emptyList())
        val section = testSection(schema, status = CollectionStatus.UNAVAILABLE, entities = emptyList())
        val result = SearchIndex.search(listOf(testSnapshot(sections = listOf(section))), "future network unavailable").single()

        assertEquals("Android future network", result.title)
        assertEquals("Unavailable", result.detail)
        assertEquals("android.future.network", result.capability)
    }

    @Test
    fun duplicateResultsAreRemovedAndOutputIsCapped() {
        val repeated = (1..120).map { index ->
            testSnapshot(id = "snapshot-$index", label = "Matching snapshot $index")
        }
        assertEquals(100, SearchIndex.search(repeated, "matching").size)

        val duplicateEntities = testSnapshot(sections = listOf(testSection(entities = listOf(testEntity(), testEntity()))))
        assertEquals(1, SearchIndex.search(listOf(duplicateEntities), "one before").size)
    }

    @Test
    fun reportUsesLabelsPluralizationAndLocalOnlyFooter() {
        val (base, target) = changedSnapshot()
        val diff = DiffEngine().diff(base.copy(label = "Before"), target.copy(label = "After"))
        val report = ReportRenderer.markdown(diff)

        assertTrue(report.startsWith("# Diffuse report"))
        assertTrue(report.contains("**1 change** between Before and After."))
        assertTrue(report.contains("## Test capability"))
        assertTrue(report.contains("**Notable:**"))
        assertTrue(report.contains("No data left this device"))
    }

    @Test
    fun reportFiltersBySeverityAndNeverPrintsUnchangedRows() {
        val low = testDescriptor("low", severity = ChangeSeverity.INFORMATIONAL)
        val high = testDescriptor("high", severity = ChangeSeverity.CRITICAL)
        val schema = testSchema(properties = listOf(low, high))
        val base = testSnapshot(sections = listOf(testSection(schema, entities = listOf(testEntity(properties = mapOf("low" to PropertyValue.string("a"), "high" to PropertyValue.string("a")))))))
        val target = testSnapshot(id = "target", at = TARGET_TIME, sections = listOf(testSection(schema, at = TARGET_TIME, entities = listOf(testEntity(properties = mapOf("low" to PropertyValue.string("b"), "high" to PropertyValue.string("b")))))))
        val diff = DiffEngine(DiffOptions(includeUnchanged = true)).diff(base, target)

        val report = ReportRenderer.markdown(diff, ChangeSeverity.SIGNIFICANT)
        assertTrue(report.contains("High"))
        assertFalse(report.contains("Low"))
        assertFalse(report.contains("unchanged"))
    }

    @Test
    fun emptyReportStillExplainsThatGenerationWasLocal() {
        val snapshot = testSnapshot()
        val report = ReportRenderer.markdown(DiffEngine().diff(snapshot, snapshot))
        assertTrue(report.contains("**0 changes**"))
        assertTrue(report.endsWith("report generation._\n"))
    }

    @Test
    fun elapsedTextUsesSecondsMinutesAndHoursAtBoundaries() {
        val base = "2026-08-19T12:00:00Z"
        assertEquals("59s", ReportRenderer.elapsedText(base, "2026-08-19T12:00:59Z"))
        assertEquals("1m", ReportRenderer.elapsedText(base, "2026-08-19T12:01:00Z"))
        assertEquals("59m", ReportRenderer.elapsedText(base, "2026-08-19T12:59:59Z"))
        assertEquals("1h", ReportRenderer.elapsedText(base, "2026-08-19T13:00:00Z"))
    }
}
