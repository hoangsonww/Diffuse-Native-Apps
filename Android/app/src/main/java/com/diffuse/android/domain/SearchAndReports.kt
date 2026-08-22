package com.diffuse.android.domain

import java.time.Duration
import java.time.Instant

data class SearchResult(val snapshotID: String, val title: String, val detail: String, val capability: String? = null)

object SearchIndex {
    fun search(snapshots: List<Snapshot>, query: String): List<SearchResult> {
        val terms = query.trim().lowercase().split(Regex("\\s+")).filter(String::isNotEmpty)
        if (terms.isEmpty()) return emptyList()
        val output = mutableListOf<SearchResult>()
        snapshots.forEach { snapshot ->
            val snapshotText = listOf(snapshot.label.orEmpty(), snapshot.note.orEmpty(), snapshot.device.name, snapshot.platform, snapshot.tags.joinToString(" ")).joinToString(" ").lowercase()
            if (terms.all(snapshotText::contains)) output += SearchResult(snapshot.id, snapshot.label ?: snapshot.capturedAt, snapshot.device.name)
            snapshot.sections.forEach { section ->
                val sectionText = listOf(
                    section.schema.displayName,
                    section.schema.summary,
                    section.capability,
                    section.schema.category,
                    section.status.displayName,
                ).joinToString(" ").lowercase()
                if (terms.all(sectionText::contains)) {
                    output += SearchResult(snapshot.id, section.schema.displayName, section.status.displayName, section.capability)
                }
                section.entities.flatMap { it.flattened() }.forEach { entity ->
                    val text = "$sectionText ${entity.searchText()}"
                    if (terms.all(text::contains)) output += SearchResult(snapshot.id, entity.displayName, section.schema.displayName, section.capability)
                }
            }
        }
        return output.distinctBy { listOf(it.snapshotID, it.title, it.capability) }.take(100)
    }
}

object ReportRenderer {
    fun markdown(diff: DiffResult, minimum: ChangeSeverity = ChangeSeverity.INFORMATIONAL): String = buildString {
        appendLine("# Diffuse report")
        appendLine()
        appendLine("**${diff.summary.totalChanges} change${if (diff.summary.totalChanges == 1) "" else "s"}** between ${diff.base.label ?: diff.base.capturedAt} and ${diff.target.label ?: diff.target.capturedAt}.")
        appendLine()
        diff.sectionDiffs.forEach { section ->
            val changes = section.changes.filter { it.severity.rank >= minimum.rank && it.kind != ChangeKind.UNCHANGED }
            if (changes.isNotEmpty()) {
                appendLine("## ${section.displayName}")
                appendLine()
                changes.forEach { appendLine("- **${it.severity.name.lowercase().replaceFirstChar(Char::uppercase)}:** ${it.summary}") }
                appendLine()
            }
        }
        appendLine("_Generated locally by Diffuse. No data left this device as part of report generation._")
    }

    fun elapsedText(base: String, target: String): String {
        val seconds = Duration.between(Instant.parse(base), Instant.parse(target)).seconds
        return when { seconds < 60 -> "${seconds}s"; seconds < 3600 -> "${seconds / 60}m"; else -> "${seconds / 3600}h" }
    }
}
