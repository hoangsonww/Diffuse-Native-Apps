package com.diffuse.android.core

import com.diffuse.android.collectors.AndroidCollector
import com.diffuse.android.collectors.CapabilityMetadata
import com.diffuse.android.domain.CollectionStatus
import com.diffuse.android.domain.Diagnostic
import com.diffuse.android.domain.Snapshot
import com.diffuse.android.domain.SnapshotSection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.withTimeout

data class PlannedCollector(
    val metadata: CapabilityMetadata,
    val collectorID: String,
    val collect: suspend () -> SnapshotSection,
)

class CaptureCoordinator(private val timeoutMillis: Long = 5_000) {
    suspend fun collect(plans: List<PlannedCollector>, capturedAt: String): List<SnapshotSection> = supervisorScope {
        plans.map { plan -> async(Dispatchers.Default) { collectIsolated(plan, capturedAt) } }.map { it.await() }
    }

    private suspend fun collectIsolated(plan: PlannedCollector, capturedAt: String): SnapshotSection {
        val started = System.nanoTime()
        return try {
            val result = withTimeout(timeoutMillis) { plan.collect() }
            result.copy(duration = (System.nanoTime() - started) / 1_000_000_000.0)
        } catch (_: kotlinx.coroutines.TimeoutCancellationException) {
            SnapshotSection(
                plan.metadata.id, plan.collectorID, "1.0.0", capturedAt,
                duration = (System.nanoTime() - started) / 1_000_000_000.0,
                status = CollectionStatus.TIMED_OUT, schema = plan.metadata.schema,
                diagnostics = listOf(Diagnostic(Diagnostic.Level.WARNING, "The collector exceeded its deadline.")),
            )
        } catch (error: Throwable) {
            SnapshotSection(
                plan.metadata.id, plan.collectorID, "1.0.0", capturedAt,
                duration = (System.nanoTime() - started) / 1_000_000_000.0,
                status = CollectionStatus.FAILED, schema = plan.metadata.schema,
                diagnostics = listOf(Diagnostic(Diagnostic.Level.ERROR, error.message ?: "Collector failed")),
            )
        }
    }
}

object CapturePersistence {
    fun shouldPersist(origin: Snapshot.Origin, skipIfUnchanged: Boolean, changeCount: Int): Boolean {
        val automatic = origin == Snapshot.Origin.SCHEDULED || origin == Snapshot.Origin.TRIGGERED
        return !automatic || !skipIfUnchanged || changeCount > 0
    }
}

object SkippedSections {
    fun create(collectors: List<AndroidCollector>, capturedAt: String): List<SnapshotSection> = collectors.map { collector ->
        SnapshotSection(
            collector.metadata.id, "${collector.metadata.id}.disabled", "1.0.0", capturedAt,
            status = CollectionStatus.SKIPPED, schema = collector.metadata.schema,
        )
    }
}
