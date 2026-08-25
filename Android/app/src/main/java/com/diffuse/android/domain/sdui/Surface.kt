package com.diffuse.android.domain.sdui

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * A named screen region this app is willing to have described by data rather
 * than by code.
 *
 * Snapshots, the diff engine, and every privacy decision stay in code — a
 * payload cannot reach them. Surfaces cover *content*: help text, onboarding,
 * an announcement. The parts you would otherwise ship a build to change.
 *
 * Every surface has a hand-written native fallback. A payload that is missing,
 * malformed, or built for a newer app renders nothing, and the user sees what
 * the app always shipped with.
 */
@JvmInline
value class SurfaceId(val raw: String) {
    override fun toString(): String = raw

    companion object {
        val HELP = SurfaceId("help")
    }
}

/**
 * Open rather than an enum: a build that has never heard of a type must still
 * parse the payload and skip that node, which a sealed type cannot express.
 */
@JvmInline
value class SurfaceNodeType(val raw: String) {
    override fun toString(): String = raw

    companion object {
        val HEADING = SurfaceNodeType("heading")
        val PARAGRAPH = SurfaceNodeType("paragraph")
        val BULLETS = SurfaceNodeType("bullets")
        val CALLOUT = SurfaceNodeType("callout")
        val BUTTON = SurfaceNodeType("button")
        val DIVIDER = SurfaceNodeType("divider")
        val GROUP = SurfaceNodeType("group")

        val ALL: Set<SurfaceNodeType> = setOf(HEADING, PARAGRAPH, BULLETS, CALLOUT, BUTTON, DIVIDER, GROUP)
    }
}

/** A small closed union rather than `Any`, which cannot be checked or compared. */
@Serializable(with = SurfaceValueSerializer::class)
sealed interface SurfaceValue {
    data class Text(val value: String) : SurfaceValue
    data class Number(val value: Double) : SurfaceValue
    data class Flag(val value: Boolean) : SurfaceValue
    data class Items(val values: List<SurfaceValue>) : SurfaceValue

    val stringValue: String? get() = (this as? Text)?.value
    val intValue: Int? get() = (this as? Number)?.value?.toInt()
    val boolValue: Boolean? get() = (this as? Flag)?.value
    val stringListValue: List<String>? get() = (this as? Items)?.values?.mapNotNull { it.stringValue }
}

/**
 * Reads a JSON scalar or array into the union.
 *
 * Booleans are checked before numbers on purpose: a permissive numeric path
 * would read `true` as `1` and silently turn a flag into a count.
 */
object SurfaceValueSerializer : KSerializer<SurfaceValue> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("SurfaceValue", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): SurfaceValue {
        val input = decoder as? JsonDecoder
            ?: throw SerializationException("Surface values can only be read from JSON.")
        return fromElement(input.decodeJsonElement())
            ?: throw SerializationException("A surface value must be a string, number, boolean, or list.")
    }

    override fun serialize(encoder: Encoder, value: SurfaceValue) {
        val output = encoder as? JsonEncoder
            ?: throw SerializationException("Surface values can only be written as JSON.")
        output.encodeJsonElement(toElement(value))
    }

    fun fromElement(element: JsonElement): SurfaceValue? = when (element) {
        is JsonArray -> SurfaceValue.Items(element.mapNotNull { fromElement(it) })
        is JsonPrimitive -> when {
            element.isString -> SurfaceValue.Text(element.content)
            element.booleanOrNull != null -> SurfaceValue.Flag(element.boolean())
            element.longOrNull != null -> SurfaceValue.Number(element.longOrNull!!.toDouble())
            element.doubleOrNull != null -> SurfaceValue.Number(element.doubleOrNull!!)
            else -> null
        }
        else -> null
    }

    private fun JsonPrimitive.boolean(): Boolean = booleanOrNull ?: false

    private fun toElement(value: SurfaceValue): JsonElement = when (value) {
        is SurfaceValue.Text -> JsonPrimitive(value.value)
        is SurfaceValue.Number -> JsonPrimitive(value.value)
        is SurfaceValue.Flag -> JsonPrimitive(value.value)
        is SurfaceValue.Items -> JsonArray(value.values.map { toElement(it) })
    }
}

/**
 * A named intent the host resolves against a handler map.
 *
 * Actions are names, never code: a payload can ask for "capture" but cannot
 * describe how to capture, which is what stops data becoming execution.
 */
@Serializable
data class SurfaceAction(
    val name: String,
    val parameters: Map<String, SurfaceValue> = emptyMap()
)

@Serializable
data class SurfaceNode(
    val id: String,
    val type: String,
    val properties: Map<String, SurfaceValue> = emptyMap(),
    val children: List<SurfaceNode> = emptyList(),
    val action: SurfaceAction? = null
) {
    val nodeType: SurfaceNodeType get() = SurfaceNodeType(type)

    fun string(key: String): String? = properties[key]?.stringValue

    val flattened: List<SurfaceNode> get() = listOf(this) + children.flatMap { it.flattened }
}

@Serializable
data class Surface(
    val id: String,
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val minimumAppVersion: String? = null,
    val revision: String? = null,
    val nodes: List<SurfaceNode> = emptyList()
) {
    val surfaceId: SurfaceId get() = SurfaceId(id)

    val flattenedNodes: List<SurfaceNode> get() = nodes.flatMap { it.flattened }

    val actionNames: Set<String> get() = flattenedNodes.mapNotNull { it.action?.name }.toSet()

    companion object {
        /** Bumped only for a breaking change to the node contract. */
        const val CURRENT_SCHEMA_VERSION = 1
    }
}

/** Thrown when a payload is not a surface at all. */
class SurfaceDecodingException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Decodes the same JSON contract the Apple clients read. */
object SurfaceDecoder {
    /**
     * Unknown keys are ignored rather than fatal: a newer publisher adding a
     * field must not break an older build that cannot use it yet.
     */
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = false
    }

    fun decode(text: String): Surface = try {
        json.decodeFromString(Surface.serializer(), text)
    } catch (error: SerializationException) {
        throw SurfaceDecodingException("Surface JSON could not be parsed.", error)
    } catch (error: IllegalArgumentException) {
        throw SurfaceDecodingException("Surface JSON could not be parsed.", error)
    }

    fun encode(surface: Surface): String = json.encodeToString(Surface.serializer(), surface)
}
