package com.diffuse.android.core

import com.diffuse.android.collectors.CapabilityMetadata
import com.diffuse.android.collectors.AndroidCapabilityRegistry
import com.diffuse.android.domain.CollectionStatus
import com.diffuse.android.domain.Diagnostic
import com.diffuse.android.domain.PrivacyClassification
import com.diffuse.android.domain.SectionSchema
import com.diffuse.android.domain.Snapshot
import com.diffuse.android.domain.SnapshotSection
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureCoordinatorTest {
    @Test
    fun failuresAndTimeoutsAreIsolatedFromSuccessfulCollectors() = runTest {
        val good = plan("good") { section("good") }
        val failed = plan("failed") { error("collector broke") }
        val slow = plan("slow") { delay(100); section("slow") }

        val sections = CaptureCoordinator(timeoutMillis = 20).collect(listOf(good, failed, slow), capturedAt)

        assertEquals(CollectionStatus.COLLECTED, sections[0].status)
        assertEquals(CollectionStatus.FAILED, sections[1].status)
        assertEquals("collector broke", sections[1].diagnostics.single().message)
        assertEquals(CollectionStatus.TIMED_OUT, sections[2].status)
    }

    @Test
    fun persistencePolicySkipsOnlyUnchangedAutomaticCaptures() {
        assertTrue(CapturePersistence.shouldPersist(Snapshot.Origin.MANUAL, true, 0))
        assertTrue(CapturePersistence.shouldPersist(Snapshot.Origin.SCHEDULED, false, 0))
        assertTrue(CapturePersistence.shouldPersist(Snapshot.Origin.TRIGGERED, true, 1))
        assertFalse(CapturePersistence.shouldPersist(Snapshot.Origin.SCHEDULED, true, 0))
    }

    @Test
    fun disabledCollectorsBecomeSchemaCarryingSkippedSections() {
        val collector = AndroidCapabilityRegistry().collectors.first()
        val section = SkippedSections.create(listOf(collector), capturedAt).single()
        assertEquals(CollectionStatus.SKIPPED, section.status)
        assertEquals(collector.metadata.id, section.capability)
        assertEquals(collector.metadata.schema, section.schema)
    }

    @Test
    fun emptyCollectionPlanReturnsImmediatelyWithoutSections() = runTest {
        assertTrue(CaptureCoordinator().collect(emptyList(), capturedAt).isEmpty())
    }

    @Test
    fun concurrentCollectorsPreservePlanOrder() = runTest {
        val slow = plan("slow") { delay(30); section("slow") }
        val fast = plan("fast") { section("fast") }

        val sections = CaptureCoordinator(timeoutMillis = 1_000).collect(listOf(slow, fast), capturedAt)

        assertEquals(listOf("slow", "fast"), sections.map { it.capability })
        assertTrue(sections.all { it.duration >= 0.0 })
    }

    @Test
    fun failureWithoutAMessageGetsAStableDiagnostic() = runTest {
        val failed = plan("failed") { throw RuntimeException() }
        val section = CaptureCoordinator().collect(listOf(failed), capturedAt).single()

        assertEquals(CollectionStatus.FAILED, section.status)
        assertEquals(Diagnostic.Level.ERROR, section.diagnostics.single().level)
        assertEquals("Collector failed", section.diagnostics.single().message)
    }

    @Test
    fun timeoutCarriesDeclaredCollectorIdentitySchemaAndWarning() = runTest {
        val slow = plan("slow") { delay(100); section("slow") }
        val section = CaptureCoordinator(timeoutMillis = 10).collect(listOf(slow), capturedAt).single()

        assertEquals("slow", section.capability)
        assertEquals("test.slow", section.collector)
        assertEquals(schema("slow"), section.schema)
        assertEquals(Diagnostic.Level.WARNING, section.diagnostics.single().level)
        assertTrue(section.diagnostics.single().message.contains("deadline"))
    }

    @Test
    fun persistenceMatrixCoversEveryOrigin() {
        Snapshot.Origin.entries.forEach { origin ->
            val automatic = origin == Snapshot.Origin.SCHEDULED || origin == Snapshot.Origin.TRIGGERED
            assertEquals(!automatic, CapturePersistence.shouldPersist(origin, skipIfUnchanged = true, changeCount = 0))
            assertTrue(CapturePersistence.shouldPersist(origin, skipIfUnchanged = false, changeCount = 0))
            assertTrue(CapturePersistence.shouldPersist(origin, skipIfUnchanged = true, changeCount = 1))
        }
    }

    @Test
    fun skippedSectionsPreserveRegistryOrderAndUseDisabledCollectorIds() {
        val collectors = AndroidCapabilityRegistry().collectors.take(3)
        val sections = SkippedSections.create(collectors, capturedAt)

        assertEquals(collectors.map { it.metadata.id }, sections.map { it.capability })
        assertEquals(collectors.map { "${it.metadata.id}.disabled" }, sections.map { it.collector })
        assertTrue(sections.all { it.status == CollectionStatus.SKIPPED && it.collectedAt == capturedAt })
    }

    private fun plan(id: String, collect: suspend () -> SnapshotSection): PlannedCollector {
        val schema = schema(id)
        return PlannedCollector(
            CapabilityMetadata(id, id, id, "Collects $id", PrivacyClassification.PUBLIC, schema),
            "test.$id",
            collect,
        )
    }

    private fun section(id: String) = SnapshotSection(id, "test.$id", "1.0.0", capturedAt, schema = schema(id))
    private fun schema(id: String) = SectionSchema(id, id, id, "test", "circle")

    private companion object {
        const val capturedAt = "2026-08-19T12:00:00Z"
    }
}
