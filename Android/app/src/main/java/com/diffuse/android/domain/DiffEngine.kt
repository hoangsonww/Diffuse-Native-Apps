package com.diffuse.android.domain

import java.time.Duration
import java.time.Instant
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class DiffOptions(
    val minimumSeverity: ChangeSeverity = ChangeSeverity.INFORMATIONAL,
    val includeUnchanged: Boolean = false,
    val includeStatusChanges: Boolean = true,
    val includeChildren: Boolean = true,
    val correlationWindowSeconds: Double = 300.0,
    val minimumClusterSize: Int = 2,
    val excludedCapabilities: Set<String> = emptySet(),
    val includedCapabilities: Set<String>? = null,
) {
    fun allows(id: String) = id !in excludedCapabilities && (includedCapabilities == null || id in includedCapabilities)
    companion object {
        val Default = DiffOptions()
        val SignificantOnly = DiffOptions(minimumSeverity = ChangeSeverity.SIGNIFICANT)
    }
}

private data class SemanticVersion(
    val major: Int,
    val minor: Int,
    val patch: Int,
    val prerelease: List<String>,
    val build: List<String>,
) : Comparable<SemanticVersion> {
    override fun compareTo(other: SemanticVersion): Int {
        compareValues(major, other.major).takeIf { it != 0 }?.let { return it }
        compareValues(minor, other.minor).takeIf { it != 0 }?.let { return it }
        compareValues(patch, other.patch).takeIf { it != 0 }?.let { return it }
        if (prerelease.isEmpty() && other.prerelease.isNotEmpty()) return 1
        if (prerelease.isNotEmpty() && other.prerelease.isEmpty()) return -1
        for ((left, right) in prerelease.zip(other.prerelease)) {
            if (left == right) continue
            val leftNumber = left.toIntOrNull()
            val rightNumber = right.toIntOrNull()
            return when {
                leftNumber != null && rightNumber != null -> leftNumber.compareTo(rightNumber)
                leftNumber != null -> -1
                rightNumber != null -> 1
                else -> left.compareTo(right)
            }
        }
        return prerelease.size.compareTo(other.prerelease.size)
    }

    fun transition(other: SemanticVersion): VersionTransition = when {
        compareTo(other) == 0 -> VersionTransition.UNCHANGED
        other < this -> VersionTransition.DOWNGRADE
        other.major != major -> VersionTransition.MAJOR
        other.minor != minor -> VersionTransition.MINOR
        other.patch != patch -> VersionTransition.PATCH
        else -> VersionTransition.PRERELEASE
    }

    companion object {
        fun parse(input: String): SemanticVersion? {
            var text = input.trim().removePrefix("v").removePrefix("V")
            if (text.isEmpty()) return null
            val buildSplit = text.split('+', limit = 2)
            text = buildSplit[0]
            val build = buildSplit.getOrNull(1)?.split('.') ?: emptyList()
            val prereleaseSplit = text.split('-', limit = 2)
            val prerelease = prereleaseSplit.getOrNull(1)?.split('.') ?: emptyList()
            val parts = prereleaseSplit[0].split('.')
            val major = parts.firstOrNull()?.toIntOrNull() ?: return null
            return SemanticVersion(major, parts.getOrNull(1)?.toIntOrNull() ?: 0, parts.getOrNull(2)?.toIntOrNull() ?: 0, prerelease, build)
        }
    }
}

private enum class VersionTransition { MAJOR, MINOR, PATCH, PRERELEASE, UNCHANGED, DOWNGRADE }
private data class ComparisonOutcome(
    val areEqual: Boolean,
    val confidence: Double = 1.0,
    val versionTransition: VersionTransition? = null,
    val relativeMagnitude: Double? = null,
)

private object ValueComparator {
    fun compare(before: PropertyValue, after: PropertyValue, rule: ComparisonRule): ComparisonOutcome {
        if (rule.kind == ComparisonRule.Kind.IGNORED) return ComparisonOutcome(true)
        if (before.isAbsent || after.isAbsent) return ComparisonOutcome(before.isAbsent == after.isAbsent)
        return when (rule.kind) {
            ComparisonRule.Kind.EXACT -> ComparisonOutcome(before == after)
            ComparisonRule.Kind.CASE_INSENSITIVE -> {
                val left = before.text(); val right = after.text()
                ComparisonOutcome(if (left != null && right != null) left.trim().equals(right.trim(), true) else before == after)
            }
            ComparisonRule.Kind.PATH_NORMALIZED -> {
                val left = before.text(); val right = after.text()
                ComparisonOutcome(if (left != null && right != null) EntityIdentity.normalizePath(left) == EntityIdentity.normalizePath(right) else before == after)
            }
            ComparisonRule.Kind.SEMANTIC_VERSION -> {
                val left = before.text()?.let(SemanticVersion::parse)
                val right = after.text()?.let(SemanticVersion::parse)
                if (left == null || right == null) ComparisonOutcome(before == after)
                else if (left.compareTo(right) == 0) ComparisonOutcome(true)
                else ComparisonOutcome(false, versionTransition = left.transition(right))
            }
            ComparisonRule.Kind.NUMERIC -> compareNumeric(before, after, rule.tolerance ?: 0.0, false)
            ComparisonRule.Kind.RELATIVE -> compareNumeric(before, after, rule.tolerance ?: 0.0, true)
            ComparisonRule.Kind.UNORDERED -> {
                val left = before.list(); val right = after.list()
                ComparisonOutcome(if (left != null && right != null) left.map { it.searchText() }.sorted() == right.map { it.searchText() }.sorted() else before == after)
            }
            ComparisonRule.Kind.IGNORED -> ComparisonOutcome(true)
        }
    }

    private fun numeric(value: PropertyValue): Double? = if (value.type == "date") {
        value.value?.let { runCatching { Instant.parse(it.toString().trim('"')).toEpochMilli() / 1000.0 }.getOrNull() }
    } else value.number()

    private fun compareNumeric(before: PropertyValue, after: PropertyValue, tolerance: Double, relative: Boolean): ComparisonOutcome {
        val left = numeric(before); val right = numeric(after)
        if (left == null || right == null) return ComparisonOutcome(before == after)
        val delta = abs(right - left)
        val scale = max(abs(left), abs(right))
        val magnitude = if (scale > 0) delta / scale else if (delta > 0) 1.0 else 0.0
        val threshold = if (relative) tolerance * scale else tolerance
        if (delta <= threshold) return ComparisonOutcome(true)
        val confidence = if (threshold > 0) min(1.0, 0.5 + 0.25 * (delta / threshold - 1.0)) else 1.0
        return ComparisonOutcome(false, confidence, relativeMagnitude = magnitude)
    }
}

class DiffEngine(private val options: DiffOptions = DiffOptions.Default) {
    fun diff(base: Snapshot, target: Snapshot): DiffResult {
        val capabilities = (base.sections.map { it.capability } + target.sections.map { it.capability }).distinct().filter(options::allows)
        val asymmetric = mutableListOf<String>()
        val sections = capabilities.mapNotNull { capability ->
            val before = base.section(capability)
            val after = target.section(capability)
            if (before == null || after == null) asymmetric += capability
            diffSection(before, after, target.capturedAt)
        }
        val changes = sections.flatMap { it.changes }
        val reportable = changes.filter { it.kind != ChangeKind.UNCHANGED }
        val summary = DiffSummary(
            totalChanges = reportable.size,
            countsBySeverity = reportable.groupingBy { it.severity }.eachCount(),
            countsByKind = reportable.groupingBy { it.kind }.eachCount(),
            changedSections = sections.count { section -> section.changes.any { it.kind != ChangeKind.UNCHANGED } },
            comparedSections = sections.size,
            asymmetricSections = asymmetric.sorted(),
            elapsed = Duration.between(Instant.parse(base.capturedAt), Instant.parse(target.capturedAt)).toMillis() / 1000.0,
        )
        return DiffResult(base.reference(), target.reference(), target.capturedAt, summary, sections, cluster(reportable))
    }

    private fun diffSection(base: SnapshotSection?, target: SnapshotSection?, fallbackDate: String): SectionDiff? {
        val schema = target?.schema ?: base?.schema ?: return null
        val capability = target?.capability ?: base?.capability ?: return null
        val observedAt = target?.collectedAt ?: fallbackDate
        val changes = mutableListOf<Change>()
        var unchanged = 0
        when {
            base == null && target != null -> changes += sectionPresence(ChangeKind.ADDED, capability, schema, target.collectedAt)
            base != null && target == null -> changes += sectionPresence(ChangeKind.REMOVED, capability, schema, fallbackDate)
            base != null && target != null -> {
                if (options.includeStatusChanges && base.status != target.status) changes += statusChange(capability, schema, base.status, target.status, observedAt)
                if ((base.status.hasData && target.status.hasData) || (!base.status.hasData && target.status.hasData)) {
                    val result = diffEntities(capability, schema, base, target, observedAt)
                    changes += result.first
                    unchanged = result.second
                }
            }
        }
        val filtered = changes.filter { it.kind == ChangeKind.UNCHANGED || it.severity.rank >= options.minimumSeverity.rank }.sortedWith(changePresentationOrder)
        return SectionDiff(capability, schema.displayName, schema.category, schema.symbol, base?.status, target?.status, filtered, unchanged)
    }

    private fun normalize(section: SnapshotSection): Map<EntityIdentity, SnapshotEntity> {
        val result = linkedMapOf<EntityIdentity, SnapshotEntity>()
        val candidates = if (options.includeChildren) section.entities.flatMap { it.flattened() } else section.entities
        candidates.forEach { entity ->
            result.putIfAbsent(entity.identity, entity.copy(
                properties = entity.properties.filterValues { !it.isAbsent },
                children = if (options.includeChildren) emptyList() else entity.children,
            ))
        }
        return result
    }

    private fun diffEntities(
        capability: String,
        schema: SectionSchema,
        base: SnapshotSection,
        target: SnapshotSection,
        observedAt: String,
    ): Pair<List<Change>, Int> {
        val before = normalize(base)
        val after = normalize(target)
        val changes = mutableListOf<Change>()
        (after.keys - before.keys).sorted().forEach { changes += entityChange(ChangeKind.ADDED, capability, schema, after.getValue(it), observedAt) }
        (before.keys - after.keys).sorted().forEach { changes += entityChange(ChangeKind.REMOVED, capability, schema, before.getValue(it), observedAt) }
        var unchanged = 0
        (before.keys intersect after.keys).sorted().forEach { identity ->
            val entityChanges = diffProperties(capability, schema, before.getValue(identity), after.getValue(identity), observedAt)
            if (entityChanges.isEmpty()) {
                unchanged++
                if (options.includeUnchanged) changes += entityChange(ChangeKind.UNCHANGED, capability, schema, after.getValue(identity), observedAt)
            } else changes += entityChanges
        }
        changes += diffAttributes(capability, schema, base.attributes.filterValues { !it.isAbsent }, target.attributes.filterValues { !it.isAbsent }, observedAt)
        return changes to unchanged
    }

    private fun diffProperties(capability: String, schema: SectionSchema, before: SnapshotEntity, after: SnapshotEntity, observedAt: String): List<Change> {
        val changes = mutableListOf<Change>()
        (before.properties.keys + after.properties.keys).sorted().distinct().forEach { key ->
            val descriptor = schema.descriptor(after.kind, key)
            val old = before.property(key); val new = after.property(key)
            val outcome = ValueComparator.compare(old, new, descriptor.comparison)
            if (!outcome.areEqual) changes += propertyChange(capability, schema, after, descriptor, old, new, outcome, observedAt)
        }
        val oldName = before.displayName.trim(); val newName = after.displayName.trim()
        if (oldName != newName && changes.none { it.property?.before?.text() == oldName && it.property.after.text() == newName }) {
            val descriptor = PropertyDescriptor("__displayName", "Name", severity = ChangeSeverity.NOTABLE, privacy = schema.privacy, isPrimary = true)
            changes.add(0, propertyChange(capability, schema, after, descriptor, PropertyValue.string(oldName), PropertyValue.string(newName), ComparisonOutcome(false), observedAt))
        }
        return changes
    }

    private fun diffAttributes(capability: String, schema: SectionSchema, before: Map<String, PropertyValue>, after: Map<String, PropertyValue>, observedAt: String): List<Change> {
        val identity = EntityIdentity.create("__section", capability)
        val carrier = SnapshotEntity(identity, schema.displayName, "Section totals")
        return (before.keys + after.keys).sorted().distinct().mapNotNull { key ->
            val descriptor = schema.attribute(key) ?: PropertyDescriptor(key, key.humanized(), severity = ChangeSeverity.INFORMATIONAL, privacy = schema.privacy)
            val old = before[key] ?: PropertyValue.Absent; val new = after[key] ?: PropertyValue.Absent
            val outcome = ValueComparator.compare(old, new, descriptor.comparison)
            if (outcome.areEqual) null else propertyChange(capability, schema, carrier, descriptor, old, new, outcome, observedAt)
        }
    }

    private fun propertyChange(
        capability: String, schema: SectionSchema, entity: SnapshotEntity, descriptor: PropertyDescriptor,
        before: PropertyValue, after: PropertyValue, outcome: ComparisonOutcome, observedAt: String,
    ): Change {
        var severity = descriptor.severity
        if (before.isAbsent != after.isAbsent) severity = severity.escalated()
        severity = when (outcome.versionTransition) {
            VersionTransition.MAJOR, VersionTransition.DOWNGRADE -> severity.escalated()
            VersionTransition.PATCH, VersionTransition.PRERELEASE -> severity.deescalated()
            else -> severity
        }
        severity = when {
            outcome.confidence < 0.7 -> severity.deescalated()
            (outcome.relativeMagnitude ?: 0.0) >= 0.25 -> severity.escalated()
            else -> severity
        }
        val transition = PropertyChange(descriptor.key, descriptor.displayName, descriptor.unit, before, after)
        val detailParts = buildList {
            descriptor.summary?.let(::add)
            outcome.versionTransition?.takeIf { it != VersionTransition.UNCHANGED }?.let { add("Semantic version change: ${it.name.lowercase()}.") }
            if (outcome.confidence < 1) add("Close to the noise threshold for this property (${(outcome.confidence * 100).toInt()}% confidence).")
        }
        val summary = if (descriptor.isPrimary) "${entity.displayName} ${before.formatted(true)} → ${after.formatted(true)}"
        else "${entity.displayName} · ${descriptor.displayName} ${before.formatted(true)} → ${after.formatted(true)}"
        val privacy = if (schema.privacy == PrivacyClassification.RESTRICTED) PrivacyClassification.RESTRICTED else descriptor.privacy
        return Change(
            id = "$capability#${entity.identity.token}#${descriptor.key}#modified",
            kind = ChangeKind.MODIFIED,
            capability = capability,
            sectionName = schema.displayName,
            category = schema.category,
            entity = reference(entity, schema.kind(entity.kind)),
            property = transition,
            severity = severity,
            confidence = outcome.confidence,
            privacy = privacy,
            observedAt = observedAt,
            summary = summary,
            detail = detailParts.takeIf { it.isNotEmpty() }?.joinToString(" "),
        )
    }

    private fun entityChange(kind: ChangeKind, capability: String, schema: SectionSchema, entity: SnapshotEntity, observedAt: String): Change {
        val descriptor = schema.kind(entity.kind)
        val severity = when (kind) {
            ChangeKind.ADDED -> descriptor?.additionSeverity ?: ChangeSeverity.NOTABLE
            ChangeKind.REMOVED -> descriptor?.removalSeverity ?: ChangeSeverity.SIGNIFICANT
            ChangeKind.MODIFIED -> ChangeSeverity.NOTABLE
            ChangeKind.UNCHANGED -> ChangeSeverity.INFORMATIONAL
        }
        val summary = "${entity.displayName} ${when (kind) { ChangeKind.ADDED -> "added"; ChangeKind.REMOVED -> "removed"; ChangeKind.MODIFIED -> "changed"; ChangeKind.UNCHANGED -> "unchanged" }}"
        val primary = descriptor?.properties.orEmpty().filter { it.isPrimary }.mapNotNull { property ->
            entity.property(property.key).takeUnless { it.isAbsent }?.let { "${property.displayName} ${it.formatted(true)}" }
        }
        val noun = descriptor?.singularName ?: entity.kind.humanized()
        return Change(
            "$capability#${entity.identity.token}#${kind.name.lowercase()}", kind, capability, schema.displayName, schema.category,
            reference(entity, descriptor), severity = severity, privacy = schema.privacy, observedAt = observedAt, summary = summary,
            detail = if (primary.isEmpty()) noun else "$noun — ${primary.joinToString(", ")}",
        )
    }

    private fun statusChange(capability: String, schema: SectionSchema, before: CollectionStatus, after: CollectionStatus, observedAt: String): Change {
        val identity = EntityIdentity.create("__section", capability)
        val property = PropertyChange("__status", "Collection status", before = PropertyValue.string(before.displayName), after = PropertyValue.string(after.displayName))
        val severity = when {
            after == CollectionStatus.PERMISSION_REQUIRED && before != after -> ChangeSeverity.SIGNIFICANT
            before.hasData && !after.hasData -> ChangeSeverity.NOTABLE
            else -> ChangeSeverity.INFORMATIONAL
        }
        return Change(
            "$capability#${identity.token}#__status#modified", ChangeKind.MODIFIED, capability, schema.displayName, schema.category,
            EntityReference(identity, schema.displayName, "Collection status", schema.symbol), property, severity,
            privacy = PrivacyClassification.PUBLIC, observedAt = observedAt,
            summary = "${schema.displayName} ${before.displayName.lowercase()} → ${after.displayName.lowercase()}",
            detail = if (after.isProblem) "Diffuse could not read this section in the later snapshot, so its contents are not compared." else null,
        )
    }

    private fun sectionPresence(kind: ChangeKind, capability: String, schema: SectionSchema, observedAt: String): Change {
        val identity = EntityIdentity.create("__section", capability)
        val added = kind == ChangeKind.ADDED
        return Change(
            "$capability#${identity.token}#${kind.name.lowercase()}", kind, capability, schema.displayName, schema.category,
            EntityReference(identity, schema.displayName, schema.summary, schema.symbol),
            severity = if (added) ChangeSeverity.INFORMATIONAL else ChangeSeverity.NOTABLE,
            privacy = PrivacyClassification.PUBLIC, observedAt = observedAt,
            summary = if (added) "${schema.displayName} is now being collected" else "${schema.displayName} is no longer being collected",
            detail = if (added) "This capability appeared between the two snapshots, so there is nothing to compare it against yet."
            else "This capability was present in the earlier snapshot but absent from the later one.",
        )
    }

    private fun reference(entity: SnapshotEntity, descriptor: EntityKindDescriptor?) = EntityReference(
        entity.identity, entity.displayName, entity.subtitle, descriptor?.symbol ?: "circle.grid.2x2",
    )

    private fun cluster(changes: List<Change>): List<ChangeCluster> {
        if (options.correlationWindowSeconds <= 0 || options.minimumClusterSize <= 0 || changes.isEmpty()) return emptyList()
        val ordered = changes.sortedWith(compareBy<Change>({ Instant.parse(it.observedAt) }, { it.id }))
        val groups = mutableListOf<MutableList<Change>>()
        ordered.forEach { change ->
            val current = groups.lastOrNull()
            if (current == null || Duration.between(Instant.parse(current.last().observedAt), Instant.parse(change.observedAt)).toMillis() / 1000.0 > options.correlationWindowSeconds) {
                groups += mutableListOf(change)
            } else current += change
        }
        return groups.filter { it.size >= options.minimumClusterSize }.map { group ->
            val start = group.first().observedAt; val end = group.last().observedAt
            ChangeCluster(
                "cluster:$start..$end#${group.size}", start, end, group.map { it.id }.sorted(),
                group.maxBy { it.severity.rank }.severity, group.map { it.capability }.distinct(),
            )
        }
    }
}
