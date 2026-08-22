package com.diffuse.android.domain

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.time.Duration
import java.time.Instant

class FileSnapshotStore(private val root: File) {
    private val snapshots = File(root, "snapshots")

    init { snapshots.mkdirs() }

    suspend fun save(snapshot: Snapshot) = processMutex.withLock { withContext(Dispatchers.IO) {
        val target = file(snapshot.id)
        check(!target.exists()) { "Snapshot ${snapshot.id} already exists" }
        atomicWrite(target, SnapshotJson.encodeSnapshot(snapshot))
    } }

    suspend fun load(id: String): Snapshot? = processMutex.withLock { withContext(Dispatchers.IO) {
        file(id).takeIf(File::isFile)?.readText()?.let(SnapshotJson::decodeSnapshot)
    } }

    suspend fun all(): List<Snapshot> = processMutex.withLock { withContext(Dispatchers.IO) {
        snapshots.listFiles { file -> file.extension == "json" }.orEmpty().mapNotNull { file ->
            runCatching { SnapshotJson.decodeSnapshot(file.readText()) }.getOrNull()
        }.sortedWith(compareByDescending<Snapshot> { Instant.parse(it.capturedAt) }.thenByDescending { it.id })
    } }

    suspend fun summaries(): List<SnapshotSummary> = all().map { snapshot -> SnapshotSummary.from(snapshot, file(snapshot.id).length()) }

    suspend fun annotate(id: String, label: String? = null, pinned: Boolean? = null) = processMutex.withLock { withContext(Dispatchers.IO) {
        val target = file(id)
        val snapshot = target.takeIf(File::isFile)?.readText()?.let(SnapshotJson::decodeSnapshot) ?: return@withContext
        atomicWrite(target, SnapshotJson.encodeSnapshot(snapshot.copy(label = label ?: snapshot.label, isPinned = pinned ?: snapshot.isPinned)))
    } }

    suspend fun setLabel(id: String, label: String?) = processMutex.withLock { withContext(Dispatchers.IO) {
        val target = file(id)
        val snapshot = target.takeIf(File::isFile)?.readText()?.let(SnapshotJson::decodeSnapshot) ?: return@withContext
        atomicWrite(target, SnapshotJson.encodeSnapshot(snapshot.copy(label = label)))
    } }

    suspend fun delete(id: String) = processMutex.withLock { withContext(Dispatchers.IO) { file(id).delete() } }
    suspend fun deleteAll() = processMutex.withLock { withContext(Dispatchers.IO) { snapshots.listFiles().orEmpty().forEach(File::delete) } }
    suspend fun size(): Long = withContext(Dispatchers.IO) { snapshots.listFiles().orEmpty().sumOf(File::length) }

    private fun file(id: String) = File(snapshots, "${id.replace(Regex("[^A-Za-z0-9._-]"), "_")}.json")
    private fun atomicWrite(target: File, text: String) {
        val temporary = File(target.parentFile, ".${target.name}.tmp")
        temporary.writeText(text)
        if (!temporary.renameTo(target)) {
            temporary.copyTo(target, overwrite = true)
            temporary.delete()
        }
    }

    private companion object {
        val processMutex = Mutex()
    }
}

@Serializable
data class RetentionPolicy(
    val days: Int = 90,
    val maximumBytes: Long? = 1_073_741_824,
    val maximumCount: Int? = null,
    val protectsPinned: Boolean = true,
    val protectsLabelled: Boolean = true,
)

object RetentionPlanner {
    fun plan(summaries: List<SnapshotSummary>, policy: RetentionPolicy, now: Instant = Instant.now()): List<String> {
        if (summaries.isEmpty()) return emptyList()
        val ordered = summaries.sortedWith(compareByDescending<SnapshotSummary> { Instant.parse(it.capturedAt) }.thenBy { it.id })
        val newest = ordered.first().id
        val protected = summaries.filter { (policy.protectsPinned && it.isPinned) || (policy.protectsLabelled && !it.label.isNullOrBlank()) }.mapTo(mutableSetOf()) { it.id }
        val candidates = ordered.filter { it.id !in protected }
        val deleted = mutableSetOf<String>()
        if (policy.days > 0) candidates.filter { it.id != newest && Duration.between(Instant.parse(it.capturedAt), now).toDays() > policy.days }.forEach { deleted += it.id }
        policy.maximumCount?.let { maximum ->
            candidates.filter { it.id !in deleted }.drop(maximum.coerceAtLeast(0)).forEach { deleted += it.id }
            deleted -= newest
        }
        policy.maximumBytes?.let { maximum ->
            var bytes = 0L
            candidates.filter { it.id !in deleted }.forEach { summary ->
                if (summary.id == newest) bytes += summary.approximateBytes
                else if (bytes + summary.approximateBytes > maximum) deleted += summary.id
                else bytes += summary.approximateBytes
            }
        }
        deleted -= newest
        return deleted.toList()
    }
}
