package com.diffuse.android.domain

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

object SnapshotJson {
    val codec = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
        prettyPrint = true
        allowStructuredMapKeys = false
    }

    fun decodeSnapshot(text: String): Snapshot = runCatching {
        codec.decodeFromString<SnapshotEnvelope>(text).snapshot
    }.getOrElse {
        codec.decodeFromString<Snapshot>(text)
    }

    fun encodeSnapshot(snapshot: Snapshot): String = codec.encodeToString(SnapshotEnvelope(snapshot = snapshot))
    fun encodeDiff(diff: DiffResult): String = codec.encodeToString(DiffEnvelope(diff = diff, exportedAt = diff.generatedAt))
    fun now(): String = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
    fun instant(text: String): Instant = Instant.parse(text)
}

@Serializable
enum class PrivacyClassification(val rank: Int) {
    @SerialName("public") PUBLIC(0),
    @SerialName("local") LOCAL(1),
    @SerialName("sensitive") SENSITIVE(2),
    @SerialName("restricted") RESTRICTED(3),
}

@Serializable
enum class RedactionPolicy {
    @SerialName("none") NONE,
    @SerialName("standard") STANDARD,
    @SerialName("strict") STRICT;

    fun redacts(value: PrivacyClassification): Boolean = value.rank >= when (this) {
        NONE -> PrivacyClassification.RESTRICTED.rank
        STANDARD -> PrivacyClassification.SENSITIVE.rank
        STRICT -> PrivacyClassification.LOCAL.rank
    }
}

@Serializable
enum class ChangeSeverity(val rank: Int) {
    @SerialName("informational") INFORMATIONAL(0),
    @SerialName("notable") NOTABLE(1),
    @SerialName("significant") SIGNIFICANT(2),
    @SerialName("critical") CRITICAL(3);

    fun escalated() = entries[(rank + 1).coerceAtMost(3)]
    fun deescalated() = entries[(rank - 1).coerceAtLeast(0)]
}

@Serializable
enum class ChangeKind {
    @SerialName("added") ADDED,
    @SerialName("removed") REMOVED,
    @SerialName("modified") MODIFIED,
    @SerialName("unchanged") UNCHANGED,
}

@Serializable
enum class CollectionStatus {
    @SerialName("collected") COLLECTED,
    @SerialName("partial") PARTIAL,
    @SerialName("unavailable") UNAVAILABLE,
    @SerialName("unsupported") UNSUPPORTED,
    @SerialName("permissionRequired") PERMISSION_REQUIRED,
    @SerialName("timedOut") TIMED_OUT,
    @SerialName("failed") FAILED,
    @SerialName("skipped") SKIPPED;

    val hasData get() = this == COLLECTED || this == PARTIAL
    val isProblem get() = this in setOf(PARTIAL, UNAVAILABLE, PERMISSION_REQUIRED, TIMED_OUT, FAILED)
    val displayName get() = when (this) {
        COLLECTED -> "Collected"
        PARTIAL -> "Partial"
        UNAVAILABLE -> "Unavailable"
        UNSUPPORTED -> "Not supported"
        PERMISSION_REQUIRED -> "Permission required"
        TIMED_OUT -> "Timed out"
        FAILED -> "Failed"
        SKIPPED -> "Skipped"
    }
}

@Serializable
enum class PropertyUnit {
    @SerialName("none") NONE,
    @SerialName("bytes") BYTES,
    @SerialName("seconds") SECONDS,
    @SerialName("percent") PERCENT,
    @SerialName("count") COUNT,
    @SerialName("hertz") HERTZ,
    @SerialName("celsius") CELSIUS,
    @SerialName("pixels") PIXELS,
    @SerialName("path") PATH,
    @SerialName("version") VERSION,
    @SerialName("timestamp") TIMESTAMP,
}

@Serializable(with = ComparisonRuleSerializer::class)
data class ComparisonRule(val kind: Kind, val tolerance: Double? = null) {
    enum class Kind { EXACT, CASE_INSENSITIVE, PATH_NORMALIZED, SEMANTIC_VERSION, NUMERIC, RELATIVE, UNORDERED, IGNORED }

    companion object {
        val Exact = ComparisonRule(Kind.EXACT)
        val CaseInsensitive = ComparisonRule(Kind.CASE_INSENSITIVE)
        val PathNormalized = ComparisonRule(Kind.PATH_NORMALIZED)
        val SemanticVersion = ComparisonRule(Kind.SEMANTIC_VERSION)
        fun numeric(tolerance: Double) = ComparisonRule(Kind.NUMERIC, tolerance)
        fun relative(tolerance: Double) = ComparisonRule(Kind.RELATIVE, tolerance)
        val Unordered = ComparisonRule(Kind.UNORDERED)
        val Ignored = ComparisonRule(Kind.IGNORED)
    }
}

object ComparisonRuleSerializer : KSerializer<ComparisonRule> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("ComparisonRule", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): ComparisonRule {
        val objectValue = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val (key, payload) = objectValue.entries.firstOrNull() ?: throw SerializationException("Empty comparison rule")
        return when (key) {
            "exact" -> ComparisonRule.Exact
            "caseInsensitive" -> ComparisonRule.CaseInsensitive
            "pathNormalized" -> ComparisonRule.PathNormalized
            "semanticVersion" -> ComparisonRule.SemanticVersion
            "numeric" -> ComparisonRule.numeric(payload.jsonObject["tolerance"]!!.jsonPrimitive.double)
            "relative" -> ComparisonRule.relative(payload.jsonObject["tolerance"]!!.jsonPrimitive.double)
            "unordered" -> ComparisonRule.Unordered
            "ignored" -> ComparisonRule.Ignored
            else -> throw SerializationException("Unknown comparison rule $key")
        }
    }

    override fun serialize(encoder: Encoder, value: ComparisonRule) {
        val name = when (value.kind) {
            ComparisonRule.Kind.EXACT -> "exact"
            ComparisonRule.Kind.CASE_INSENSITIVE -> "caseInsensitive"
            ComparisonRule.Kind.PATH_NORMALIZED -> "pathNormalized"
            ComparisonRule.Kind.SEMANTIC_VERSION -> "semanticVersion"
            ComparisonRule.Kind.NUMERIC -> "numeric"
            ComparisonRule.Kind.RELATIVE -> "relative"
            ComparisonRule.Kind.UNORDERED -> "unordered"
            ComparisonRule.Kind.IGNORED -> "ignored"
        }
        val payload = if (value.tolerance == null) JsonObject(emptyMap())
        else JsonObject(mapOf("tolerance" to JsonPrimitive(value.tolerance)))
        (encoder as JsonEncoder).encodeJsonElement(JsonObject(mapOf(name to payload)))
    }
}

object CompactDoubleSerializer : KSerializer<Double> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("CompactDouble", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): Double = decoder.decodeDouble()

    override fun serialize(encoder: Encoder, value: Double) {
        if (value.isFinite() && value % 1.0 == 0.0 && value in Long.MIN_VALUE.toDouble()..Long.MAX_VALUE.toDouble()) {
            encoder.encodeLong(value.toLong())
        } else {
            encoder.encodeDouble(value)
        }
    }
}

@Serializable
data class PropertyDescriptor(
    val key: String,
    val displayName: String,
    val summary: String? = null,
    val unit: PropertyUnit = PropertyUnit.NONE,
    val comparison: ComparisonRule = ComparisonRule.Exact,
    val severity: ChangeSeverity = ChangeSeverity.NOTABLE,
    val privacy: PrivacyClassification = PrivacyClassification.PUBLIC,
    val isPrimary: Boolean = false,
    val displayOrder: Int = 0,
)

@Serializable
data class EntityKindDescriptor(
    val kind: String,
    val singularName: String,
    val pluralName: String = "${singularName}s",
    val symbol: String = "circle.grid.2x2",
    val summary: String? = null,
    val additionSeverity: ChangeSeverity = ChangeSeverity.NOTABLE,
    val removalSeverity: ChangeSeverity = ChangeSeverity.SIGNIFICANT,
    val properties: List<PropertyDescriptor> = emptyList(),
)

@Serializable
data class SectionSchema(
    val capability: String,
    val displayName: String,
    val summary: String,
    val category: String,
    val symbol: String,
    val privacy: PrivacyClassification = PrivacyClassification.LOCAL,
    val entityKinds: List<EntityKindDescriptor> = emptyList(),
    val attributes: List<PropertyDescriptor> = emptyList(),
    val displayOrder: Int = 0,
) {
    fun kind(kind: String) = entityKinds.firstOrNull { it.kind == kind }
    fun descriptor(kind: String, key: String) = this.kind(kind)?.properties?.firstOrNull { it.key == key }
        ?: PropertyDescriptor(key, key.humanized(), privacy = PrivacyClassification.LOCAL)
    fun attribute(key: String) = attributes.firstOrNull { it.key == key }
}

@Serializable
data class EntityIdentity(val kind: String, val value: String, val scope: String? = null) : Comparable<EntityIdentity> {
    val token: String get() = buildString {
        append(kind)
        append(':')
        if (scope != null) append(scope).append('/')
        append(value)
    }.replace('/', '_').replace(' ', '-')

    override fun compareTo(other: EntityIdentity): Int = compareValuesBy(this, other, { it.kind }, { it.scope ?: "" }, { it.value })

    companion object {
        fun create(kind: String, value: String, scope: String? = null) = EntityIdentity(kind, normalize(value), scope?.let(::normalize))
        fun normalize(value: String) = value.trim().replace('\u00a0', ' ').split(Regex(" +")).joinToString(" ").lowercase()
        fun normalizePath(value: String): String {
            var result = value.trim().replace('\\', '/')
            while (result.length > 1 && result.endsWith('/')) result = result.dropLast(1)
            return normalize(result)
        }
    }
}

@Serializable
data class PropertyValue(val type: String, val value: JsonElement? = null) {
    val isAbsent get() = type == "absent"
    fun text(): String? = when (type) {
        "string", "identifier", "path", "version" -> value?.jsonPrimitive?.content
        else -> null
    }
    fun number(): Double? = when (type) {
        "integer", "double", "bytes", "duration", "percentage", "date" -> value?.jsonPrimitive?.doubleOrNull
        "boolean" -> value?.jsonPrimitive?.booleanOrNull?.let { if (it) 1.0 else 0.0 }
        else -> null
    }
    fun list(): List<PropertyValue>? = if (type == "list") value?.let {
        SnapshotJson.codec.decodeFromJsonElement<List<PropertyValue>>(it)
    } else null
    fun searchText(): String = when (type) {
        "absent" -> ""
        "list" -> list().orEmpty().joinToString(" ") { it.searchText() }
        else -> value?.jsonPrimitive?.content.orEmpty()
    }
    fun formatted(compact: Boolean = false): String = when (type) {
        "boolean" -> if (value?.jsonPrimitive?.booleanOrNull == true) "On" else "Off"
        "bytes" -> formatBytes(value?.jsonPrimitive?.longOrNull ?: 0)
        "percentage" -> "${((value?.jsonPrimitive?.doubleOrNull ?: 0.0) * 100).formatNumber(1)}%"
        "duration" -> formatDuration(value?.jsonPrimitive?.doubleOrNull ?: 0.0)
        "double" -> (value?.jsonPrimitive?.doubleOrNull ?: 0.0).formatNumber(2)
        "path" -> if (compact) value?.jsonPrimitive?.content?.substringAfterLast('/') ?: "—" else value?.jsonPrimitive?.content ?: "—"
        "list" -> list().orEmpty().let { values ->
            val shown = if (compact) values.take(3) else values
            shown.joinToString(", ") { it.formatted(compact) } + if (compact && values.size > 3) " +${values.size - 3} more" else ""
        }
        "absent" -> "—"
        else -> value?.jsonPrimitive?.content ?: "—"
    }

    companion object {
        fun string(value: String) = PropertyValue("string", JsonPrimitive(value))
        fun integer(value: Long) = PropertyValue("integer", JsonPrimitive(value))
        fun double(value: Double) = PropertyValue("double", JsonPrimitive(value))
        fun boolean(value: Boolean) = PropertyValue("boolean", JsonPrimitive(value))
        fun bytes(value: Long) = PropertyValue("bytes", JsonPrimitive(value))
        fun duration(value: Double) = PropertyValue("duration", JsonPrimitive(value))
        fun percentage(value: Double) = PropertyValue("percentage", JsonPrimitive(value))
        fun date(value: String) = PropertyValue("date", JsonPrimitive(value))
        fun version(value: String) = PropertyValue("version", JsonPrimitive(value))
        fun identifier(value: String) = PropertyValue("identifier", JsonPrimitive(value))
        fun path(value: String) = PropertyValue("path", JsonPrimitive(value))
        fun list(value: List<PropertyValue>) = PropertyValue("list", SnapshotJson.codec.encodeToJsonElement(value))
        val Absent = PropertyValue("absent", null)
    }
}

@Serializable
data class SnapshotEntity(
    val identity: EntityIdentity,
    val displayName: String,
    val subtitle: String? = null,
    val properties: Map<String, PropertyValue> = emptyMap(),
    val children: List<SnapshotEntity> = emptyList(),
    val tags: Set<String> = emptySet(),
) {
    val kind get() = identity.kind
    fun property(key: String) = properties[key] ?: PropertyValue.Absent
    fun flattened(): List<SnapshotEntity> = listOf(this) + children.flatMap { it.flattened() }
    fun searchText(): String = buildList {
        add(displayName); add(identity.value); subtitle?.let(::add); addAll(tags)
        properties.toSortedMap().values.forEach { add(it.searchText()) }
    }.joinToString(" ").lowercase()
}

@Serializable
data class Diagnostic(val level: Level, val message: String, val detail: String? = null) {
    @Serializable enum class Level { @SerialName("info") INFO, @SerialName("warning") WARNING, @SerialName("error") ERROR }
}

@Serializable
data class SnapshotSection(
    val capability: String,
    val collector: String,
    val collectorVersion: String,
    val collectedAt: String,
    val duration: Double = 0.0,
    val status: CollectionStatus = CollectionStatus.COLLECTED,
    val schema: SectionSchema,
    val entities: List<SnapshotEntity> = emptyList(),
    val attributes: Map<String, PropertyValue> = emptyMap(),
    val diagnostics: List<Diagnostic> = emptyList(),
) {
    val entityCount get() = entities.sumOf { it.flattened().size }
}

@Serializable
data class DeviceIdentity(
    val id: String,
    val name: String,
    val model: String,
    val systemName: String,
    val systemVersion: String,
    val architecture: String,
)

@Serializable
data class SnapshotMetadata(
    val appVersion: String = "1.0.0",
    val collectionDuration: Double = 0.0,
    val appliedRedaction: RedactionPolicy = RedactionPolicy.NONE,
    val skippedCapabilities: List<String> = emptyList(),
)

@Serializable
data class Snapshot(
    val id: String,
    val schemaVersion: Int = 1,
    val capturedAt: String,
    val platform: String,
    val device: DeviceIdentity,
    val origin: Origin = Origin.MANUAL,
    val label: String? = null,
    val note: String? = null,
    val isPinned: Boolean = false,
    val tags: Set<String> = emptySet(),
    val sections: List<SnapshotSection> = emptyList(),
    val metadata: SnapshotMetadata = SnapshotMetadata(),
) {
    @Serializable enum class Origin {
        @SerialName("manual") MANUAL,
        @SerialName("scheduled") SCHEDULED,
        @SerialName("triggered") TRIGGERED,
        @SerialName("imported") IMPORTED,
        @SerialName("synthetic") SYNTHETIC,
    }

    fun section(id: String) = sections.firstOrNull { it.capability == id }
    fun reference() = SnapshotReference(id, capturedAt, label, platform, device.name, origin)
}

@Serializable
data class SnapshotEnvelope(
    val format: String = "diffuse.snapshot",
    val schemaVersion: Int = 1,
    val exportedAt: String = SnapshotJson.now(),
    val snapshot: Snapshot,
) {
    constructor(snapshot: Snapshot) : this(exportedAt = snapshot.capturedAt, snapshot = snapshot)
}

@Serializable
data class SnapshotReference(
    val id: String,
    val capturedAt: String,
    val label: String? = null,
    val platform: String,
    val deviceName: String,
    val origin: Snapshot.Origin,
)

@Serializable
data class SnapshotSummary(
    val id: String,
    val capturedAt: String,
    val platform: String,
    val deviceName: String,
    val origin: Snapshot.Origin,
    val label: String? = null,
    val isPinned: Boolean = false,
    val tags: Set<String> = emptySet(),
    val sectionCount: Int,
    val entityCount: Int,
    val hasProblems: Boolean,
    val approximateBytes: Long = 0,
) {
    companion object {
        fun from(snapshot: Snapshot, bytes: Long = 0) = SnapshotSummary(
            snapshot.id, snapshot.capturedAt, snapshot.platform, snapshot.device.name, snapshot.origin,
            snapshot.label, snapshot.isPinned, snapshot.tags, snapshot.sections.size,
            snapshot.sections.sumOf { it.entityCount }, snapshot.sections.any { it.status.isProblem }, bytes,
        )
    }
}

@Serializable
data class PropertyChange(
    val key: String,
    val displayName: String,
    val unit: PropertyUnit = PropertyUnit.NONE,
    val before: PropertyValue,
    val after: PropertyValue,
)

@Serializable
data class EntityReference(
    val identity: EntityIdentity,
    val displayName: String,
    val subtitle: String? = null,
    val symbol: String,
)

@Serializable
data class Change(
    val id: String,
    val kind: ChangeKind,
    val capability: String,
    val sectionName: String,
    val category: String,
    val entity: EntityReference,
    val property: PropertyChange? = null,
    val severity: ChangeSeverity,
    @Serializable(with = CompactDoubleSerializer::class)
    val confidence: Double = 1.0,
    val privacy: PrivacyClassification = PrivacyClassification.LOCAL,
    val observedAt: String,
    val summary: String,
    val detail: String? = null,
) {
    val searchText get() = listOf(sectionName, entity.displayName, entity.subtitle.orEmpty(), summary, detail.orEmpty(), capability, property?.displayName.orEmpty()).joinToString(" ").lowercase()
}

@Serializable
data class DiffSummary(
    val totalChanges: Int,
    val countsBySeverity: Map<ChangeSeverity, Int>,
    val countsByKind: Map<ChangeKind, Int>,
    val changedSections: Int,
    val comparedSections: Int,
    val asymmetricSections: List<String>,
    @Serializable(with = CompactDoubleSerializer::class)
    val elapsed: Double,
)

@Serializable
data class SectionDiff(
    val capability: String,
    val displayName: String,
    val category: String,
    val symbol: String,
    val baseStatus: CollectionStatus? = null,
    val targetStatus: CollectionStatus? = null,
    val changes: List<Change>,
    val unchangedEntityCount: Int,
)

@Serializable
data class ChangeCluster(
    val id: String,
    val start: String,
    val end: String,
    val changeIDs: List<String>,
    val peakSeverity: ChangeSeverity,
    val capabilities: List<String>,
)

@Serializable
data class DiffResult(
    val base: SnapshotReference,
    val target: SnapshotReference,
    val generatedAt: String,
    val summary: DiffSummary,
    val sectionDiffs: List<SectionDiff>,
    val clusters: List<ChangeCluster>,
) {
    val changes get() = sectionDiffs.flatMap { it.changes }.sortedWith(changePresentationOrder)
}

@Serializable
data class DiffEnvelope(
    val format: String = "diffuse.diff",
    val schemaVersion: Int = 1,
    val exportedAt: String,
    val diff: DiffResult,
)

val changePresentationOrder = compareByDescending<Change> { it.severity.rank }
    .thenBy { it.category }
    .thenBy { it.capability }
    .thenBy { it.entity.identity }
    .thenBy { it.id }

fun String.humanized(): String = replace('_', ' ').replace('.', ' ')
    .replace(Regex("(?<=[a-z])(?=[A-Z])"), " ")
    .replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }

private fun Double.formatNumber(maxFraction: Int): String {
    val text = String.format(Locale.US, "%.${maxFraction}f", this)
    return if ('.' in text) text.trimEnd('0').trimEnd('.') else text
}

private fun formatBytes(bytes: Long): String {
    if (abs(bytes) < 1000) return "$bytes bytes"
    val units = listOf("bytes", "KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unit = 0
    while (abs(value) >= 1000 && unit < units.lastIndex) { value /= 1000; unit++ }
    return "${value.formatNumber(1)} ${units[unit]}"
}

private fun formatDuration(seconds: Double): String = when {
    seconds < 1 -> "${(seconds * 1000).formatNumber(0)} ms"
    seconds < 60 -> "${seconds.formatNumber(1)} s"
    seconds < 3600 -> "${(seconds / 60).toInt()} min"
    else -> "${(seconds / 3600).toInt()} hr ${((seconds % 3600) / 60).toInt()} min"
}
