package com.diffuse.android.core

import android.content.Context
import com.diffuse.android.BuildConfig
import com.diffuse.android.collectors.AndroidCapabilityRegistry
import com.diffuse.android.collectors.AndroidDeviceIdentityProvider
import com.diffuse.android.domain.ChangeSeverity
import com.diffuse.android.domain.DiffEngine
import com.diffuse.android.domain.DiffResult
import com.diffuse.android.domain.FileSnapshotStore
import com.diffuse.android.domain.Privacy
import com.diffuse.android.domain.RedactionPolicy
import com.diffuse.android.domain.ReportRenderer
import com.diffuse.android.domain.RetentionPlanner
import com.diffuse.android.domain.SearchIndex
import com.diffuse.android.domain.SearchResult
import com.diffuse.android.domain.Snapshot
import com.diffuse.android.domain.SnapshotJson
import com.diffuse.android.domain.SnapshotMetadata
import com.diffuse.android.domain.SnapshotSection
import com.diffuse.android.domain.SnapshotSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.util.UUID

data class CaptureOutcome(val snapshot: Snapshot, val persisted: Boolean, val problems: List<SnapshotSection>)
data class Overview(val latest: SnapshotSummary?, val diff: DiffResult?, val topChanges: List<com.diffuse.android.domain.Change>)

class DiffuseService(private val context: Context) {
    val preferences = AndroidPreferences(context)
    val registry = AndroidCapabilityRegistry()
    private val store = FileSnapshotStore(File(context.filesDir, "diffuse"))
    private val engine = DiffEngine()
    private val coordinator = CaptureCoordinator()
    private val identityProvider = AndroidDeviceIdentityProvider(context)

    suspend fun summaries(): List<SnapshotSummary> = store.summaries()
    suspend fun snapshots(): List<Snapshot> = store.all()
    suspend fun snapshot(id: String): Snapshot? = store.load(id)
    suspend fun storageSize(): Long = store.size()
    suspend fun search(query: String): List<SearchResult> = withContext(Dispatchers.Default) {
        SearchIndex.search(store.all(), query)
    }

    suspend fun capture(
        origin: Snapshot.Origin = Snapshot.Origin.MANUAL,
        skipIfUnchanged: Boolean = false,
    ): CaptureOutcome {
        val capturedAt = SnapshotJson.now()
        val started = System.nanoTime()
        val enabled = registry.collectors.filter { preferences.isEnabled(it.metadata.id, it.metadata.enabledByDefault) }
        val skipped = registry.collectors.filterNot { it in enabled }.map { it.metadata.id }
        val plans = enabled.map { collector ->
            PlannedCollector(collector.metadata, collector.collectorID) { collector.collect(context, capturedAt) }
        }
        val collected = coordinator.collect(plans, capturedAt)
        val placeholders = SkippedSections.create(registry.collectors.filterNot { it in enabled }, capturedAt)
        val snapshot = Snapshot(
            id = UUID.randomUUID().toString().uppercase(),
            capturedAt = capturedAt,
            platform = "Android",
            device = identityProvider.current(),
            origin = origin,
            sections = (collected + placeholders).sortedBy { it.capability },
            metadata = SnapshotMetadata(
                BuildConfig.VERSION_NAME,
                (System.nanoTime() - started) / 1_000_000_000.0,
                RedactionPolicy.NONE,
                skipped.sorted(),
            ),
        )
        val changeCount = if (skipIfUnchanged) store.all().firstOrNull()?.let { engine.diff(it, snapshot).summary.totalChanges } ?: 1 else 1
        val shouldPersist = CapturePersistence.shouldPersist(origin, skipIfUnchanged, changeCount)
        if (shouldPersist) {
            store.save(snapshot)
            applyRetention()
        }
        return CaptureOutcome(snapshot, shouldPersist, snapshot.sections.filter { it.status.isProblem })
    }

    suspend fun overview(): Overview {
        val summaries = store.summaries()
        val diff = if (summaries.size >= 2) diff(summaries[1].id, summaries[0].id) else null
        return Overview(summaries.firstOrNull(), diff, diff?.changes.orEmpty().take(5))
    }

    suspend fun diff(base: String, target: String): DiffResult? {
        val left = store.load(base) ?: return null
        val right = store.load(target) ?: return null
        return if (Instant.parse(left.capturedAt) <= Instant.parse(right.capturedAt)) engine.diff(left, right) else engine.diff(right, left)
    }

    suspend fun annotate(id: String, label: String? = null, pinned: Boolean? = null) = store.annotate(id, label, pinned)
    suspend fun setLabel(id: String, label: String?) = store.setLabel(id, label)
    suspend fun delete(id: String) = store.delete(id)
    suspend fun deleteAll() = store.deleteAll()

    suspend fun exportSnapshot(id: String, policy: RedactionPolicy = preferences.redaction): String? =
        store.load(id)?.let { SnapshotJson.encodeSnapshot(Privacy.redact(it, policy)) }

    suspend fun exportReport(base: String, target: String, policy: RedactionPolicy = preferences.redaction): String? {
        val left = store.load(base) ?: return null
        val right = store.load(target) ?: return null
        val (redactedLeft, redactedRight) = Privacy.redactPair(left, right, policy)
        val diff = engine.diff(redactedLeft, redactedRight)
        return ReportRenderer.markdown(diff, ChangeSeverity.INFORMATIONAL)
    }

    suspend fun importSnapshot(text: String): Snapshot {
        require(text.length <= 10_000_000) { "Snapshot files must be 10 MB or smaller" }
        val decoded = SnapshotJson.decodeSnapshot(text)
        require(decoded.schemaVersion == 1) { "Unsupported snapshot schema ${decoded.schemaVersion}" }
        require(decoded.sections.map { it.capability }.distinct().size == decoded.sections.size) { "Snapshot capability IDs must be unique" }
        val imported = decoded.copy(
            id = UUID.randomUUID().toString().uppercase(),
            origin = Snapshot.Origin.IMPORTED,
            tags = decoded.tags + "imported",
        )
        store.save(imported)
        applyRetention()
        return imported
    }

    private suspend fun applyRetention() {
        val summaries = store.summaries()
        RetentionPlanner.plan(summaries, preferences.retentionPolicy).forEach { store.delete(it) }
    }
}
