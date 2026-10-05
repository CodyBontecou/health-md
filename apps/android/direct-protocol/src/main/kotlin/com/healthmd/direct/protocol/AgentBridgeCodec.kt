package com.healthmd.direct.protocol

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.Locale
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.SerialKind
import kotlinx.serialization.descriptors.StructureKind
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Stable, health-free failure. Never retain a decoder exception or rejected input as a cause. */
class AgentBridgeException(val code: AgentBridgeErrorCode) : IllegalArgumentException(code.name.lowercase(Locale.ROOT))

internal object AgentBridgeChecks {
    fun require(condition: Boolean, code: AgentBridgeErrorCode = AgentBridgeErrorCode.INVALID_REQUEST) {
        if (!condition) throw AgentBridgeException(code)
    }

    fun text(value: String, minimum: Int, maximum: Int, pattern: String? = null) {
        require(value.codePointCount(0, value.length) in minimum..maximum)
        var i = 0
        while (i < value.length) {
            val c = value[i++]
            if (c.isHighSurrogate()) {
                require(i < value.length && value[i].isLowSurrogate())
                i++
            } else require(!c.isLowSurrogate())
        }
        if (pattern != null) require(Regex(pattern).matches(value))
    }
}

/** Pure codec only. JSON/grant digests do not establish stored approval or native authority. */
object AgentBridgeCodec {
    @OptIn(ExperimentalSerializationApi::class)
    internal val json = Json {
        ignoreUnknownKeys = false
        encodeDefaults = false
        explicitNulls = true
        isLenient = false
        coerceInputValues = false
    }

    fun decode(bytes: ByteArray): AgentBridgeDocument = sanitized {
        decodeTree(AgentBridgeRawJson.parse(bytes))
    }

    fun encode(document: AgentBridgeDocument): ByteArray = sanitized {
        val tree = tree(document)
        // Recheck native constructors (including potentially mutable collections) like received bytes.
        decodeTree(tree)
        boundedCanonical(tree)
    }

    /** Generic-codec agreement only, not typed document conformance or authorization. */
    fun canonicalize(bytes: ByteArray): ByteArray = sanitized {
        boundedCanonical(AgentBridgeRawJson.parse(bytes))
    }

    fun fingerprint(document: AgentBridgeDocument): String = sha256(encode(document))

    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    internal fun tree(document: AgentBridgeDocument): JsonObject =
        json.encodeToJsonElement(AgentBridgeDocumentSerializer, document).jsonObject

    internal fun <T> tree(serializer: SerializationStrategy<T>, value: T): JsonElement =
        json.encodeToJsonElement(serializer, value)

    internal fun digest(value: JsonElement): String = sha256(canonical(value))

    private fun decodeTree(element: JsonElement): AgentBridgeDocument {
        rejectExplicitNulls(element)
        val document = json.decodeFromJsonElement(AgentBridgeDocumentSerializer, element)
        AgentBridgeValidation.validate(document)
        return document
    }

    /** V4 never routes through the old highest-version application selector. */
    fun decodeEnvelope(bytes: ByteArray, negotiation: AgentBridgeNegotiation): AgentBridgeMessage = sanitized {
        AgentBridgeChecks.require(negotiation.agentExtension, AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val root = AgentBridgeRawJson.parse(bytes).jsonObject
        AgentBridgeChecks.require(root.keys == setOf("protocol_version", "type", "payload"))
        val version = root.getValue("protocol_version") as? JsonPrimitive
        AgentBridgeChecks.require(version != null && !version.isString && version.content == "4")
        val type = root.getValue("type") as? JsonPrimitive
        AgentBridgeChecks.require(type != null && type.isString)
        val schema = wireSchemas[type!!.content] ?: throw AgentBridgeException(
            if (type.content in setOf("projection_request", "projection_response")) AgentBridgeErrorCode.INVALID_REQUEST
            else AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY,
        )
        val payload = root.getValue("payload").jsonObject
        AgentBridgeChecks.require(payload["schema"] == JsonPrimitive(schema))
        AgentBridgeMessage(type.content, decodeTree(payload))
    }

    fun encodeEnvelope(message: AgentBridgeMessage, negotiation: AgentBridgeNegotiation): ByteArray = sanitized {
        AgentBridgeChecks.require(negotiation.agentExtension, AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val schema = wireSchemas[message.type] ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        AgentBridgeChecks.require(message.payload.schema == schema)
        val payload = AgentBridgeRawJson.parse(encode(message.payload))
        boundedCanonical(JsonObject(mapOf(
            "protocol_version" to JsonPrimitive(4), "type" to JsonPrimitive(message.type), "payload" to payload,
        )))
    }

    // Unsupported controls are deliberately absent, not forwarded as an untyped payload.
    private val wireSchemas = mapOf(
        "discovery_request" to "healthmd.agent_discovery_request",
        "discovery_response" to "healthmd.agent_discovery",
        "plan_request" to "healthmd.agent_plan_request",
        "plan_response" to "healthmd.agent_export_plan",
        "approval_request" to "healthmd.agent_approval_request",
        "approval_response" to "healthmd.agent_approval",
        "execute_request" to "healthmd.agent_execute_request",
        "execution_receipt" to "healthmd.agent_execution_receipt",
        "cancel_request" to "healthmd.agent_cancel_request",
        "resume_request" to "healthmd.agent_resume_request",
        "artifact_manifest" to "healthmd.agent_artifact_manifest",
        "commit_receipt" to "healthmd.agent_commit_receipt",
        "query_request" to "healthmd.source_query_request",
        "query_response" to "healthmd.source_query_response",
        "query_cancel" to "healthmd.source_query_cancel",
        "query_cancelled" to "healthmd.source_query_cancelled",
        "rejected" to "healthmd.agent_error",
    )

    private fun rejectExplicitNulls(value: JsonElement, member: String? = null) {
        when (value) {
            JsonNull -> AgentBridgeChecks.require(member == "source_offset_seconds")
            is JsonObject -> value.forEach { (key, child) -> rejectExplicitNulls(child, key) }
            is JsonArray -> value.forEach { rejectExplicitNulls(it) }
            else -> Unit
        }
    }

    internal fun canonical(value: JsonElement): ByteArray = canonicalString(value).toByteArray(Charsets.UTF_8)

    private fun boundedCanonical(value: JsonElement): ByteArray {
        val bytes = canonical(value)
        // Also checks limits for native-generated trees before exposing bytes.
        AgentBridgeRawJson.parse(bytes)
        return bytes
    }

    private fun canonicalString(value: JsonElement): String = when (value) {
        JsonNull -> "null"
        is JsonObject -> value.entries.sortedWith { a, b -> compareCodePoints(a.key, b.key) }
            .joinToString(",", "{", "}") { (key, child) -> quote(key) + ":" + canonicalString(child) }
        is JsonArray -> value.joinToString(",", "[", "]") { canonicalString(it) }
        is JsonPrimitive -> if (value.isString) quote(value.content) else value.content
    }

    internal fun compareCodePoints(a: String, b: String): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val left = a.codePointAt(i)
            val right = b.codePointAt(j)
            if (left != right) return left.compareTo(right)
            i += Character.charCount(left)
            j += Character.charCount(right)
        }
        return (a.length - i).compareTo(b.length - j)
    }

    private fun quote(value: String): String {
        AgentBridgeChecks.text(value, 0, 65536)
        return buildString {
            append('"')
            for (c in value) when (c) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000c' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (c.code < 32) append("\\u%04x".format(c.code)) else append(c)
            }
            append('"')
        }
    }

    internal inline fun <T> sanitized(block: () -> T): T = try {
        block()
    } catch (error: AgentBridgeException) {
        throw error
    } catch (_: Exception) {
        throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
    }
}

/** Actual byte-boundary parser: no duplicate keys, replacement UTF-8, floats, or scalar coercion. */
internal object AgentBridgeRawJson {
    fun parse(bytes: ByteArray): JsonElement = AgentBridgeCodec.sanitized {
        AgentBridgeChecks.require(bytes.isNotEmpty() && bytes.size <= 2097152)
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        Reader(text).parse()
    }

    private class Reader(val text: String) {
        var position = 0
        var nodes = 0

        fun parse(): JsonElement {
            val value = value(0)
            whitespace()
            AgentBridgeChecks.require(position == text.length)
            return value
        }

        fun node(depth: Int) {
            AgentBridgeChecks.require(depth <= 24 && ++nodes <= 262144)
        }

        fun value(depth: Int): JsonElement {
            node(depth)
            whitespace()
            AgentBridgeChecks.require(position < text.length)
            return when (text[position]) {
                '{' -> obj(depth)
                '[' -> array(depth)
                '"' -> JsonPrimitive(string())
                't' -> { literal("true"); JsonPrimitive(true) }
                'f' -> { literal("false"); JsonPrimitive(false) }
                'n' -> { literal("null"); JsonNull }
                '-', in '0'..'9' -> integer()
                else -> throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
            }
        }

        fun obj(depth: Int): JsonObject {
            position++
            val rows = linkedMapOf<String, JsonElement>()
            whitespace()
            if (take('}')) return JsonObject(rows)
            while (true) {
                node(depth + 1)
                whitespace()
                AgentBridgeChecks.require(rows.size < 512)
                val key = string()
                AgentBridgeChecks.require(key !in rows)
                whitespace()
                AgentBridgeChecks.require(take(':'))
                rows[key] = value(depth + 1)
                whitespace()
                if (take('}')) return JsonObject(rows)
                AgentBridgeChecks.require(take(','))
            }
        }

        fun array(depth: Int): JsonArray {
            position++
            val rows = mutableListOf<JsonElement>()
            whitespace()
            if (take(']')) return JsonArray(rows)
            while (true) {
                AgentBridgeChecks.require(rows.size < 4096)
                rows += value(depth + 1)
                whitespace()
                if (take(']')) return JsonArray(rows)
                AgentBridgeChecks.require(take(','))
            }
        }

        fun integer(): JsonPrimitive {
            val start = position
            take('-')
            AgentBridgeChecks.require(position < text.length)
            if (!take('0')) {
                AgentBridgeChecks.require(text[position] in '1'..'9')
                do { position++ } while (position < text.length && text[position] in '0'..'9')
            }
            val token = text.substring(start, position)
            val integer = token.toLongOrNull() ?: throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
            return JsonPrimitive(integer)
        }

        fun string(): String {
            AgentBridgeChecks.require(take('"'))
            val output = StringBuilder()
            while (position < text.length) {
                val c = text[position++]
                if (c == '"') {
                    val result = output.toString()
                    AgentBridgeChecks.text(result, 0, 65536)
                    return result
                }
                AgentBridgeChecks.require(c.code >= 32)
                if (c != '\\') output.append(c) else {
                    AgentBridgeChecks.require(position < text.length)
                    when (val escaped = text[position++]) {
                        '"', '\\', '/' -> output.append(escaped)
                        'b' -> output.append('\b')
                        'f' -> output.append('\u000c')
                        'n' -> output.append('\n')
                        'r' -> output.append('\r')
                        't' -> output.append('\t')
                        'u' -> {
                            AgentBridgeChecks.require(position + 4 <= text.length)
                            val token = text.substring(position, position + 4)
                            AgentBridgeChecks.require(token.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' })
                            output.append(token.toInt(16).toChar())
                            position += 4
                        }
                        else -> throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
                    }
                }
                AgentBridgeChecks.require(output.length <= 131072)
            }
            throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
        }

        fun literal(value: String) {
            AgentBridgeChecks.require(text.startsWith(value, position))
            position += value.length
        }

        fun take(c: Char): Boolean = if (position < text.length && text[position] == c) {
            position++
            true
        } else false

        fun whitespace() {
            while (position < text.length && text[position] in " \t\n\r") position++
        }
    }
}

/** kotlinx JSON permits quoted numeric scalars; reject them against the concrete DTO descriptor. */
@OptIn(ExperimentalSerializationApi::class)
internal object AgentBridgeShapes {
    fun <T> checked(value: JsonElement, serializer: DeserializationStrategy<T>): DeserializationStrategy<T> {
        validate(value, serializer.descriptor)
        return serializer
    }

    private fun validate(value: JsonElement, descriptor: SerialDescriptor) {
        if (value == JsonNull) {
            AgentBridgeChecks.require(descriptor.isNullable)
            return
        }
        when (descriptor.kind) {
            PrimitiveKind.STRING -> AgentBridgeChecks.require(value is JsonPrimitive && value.isString)
            PrimitiveKind.BOOLEAN -> AgentBridgeChecks.require(value is JsonPrimitive && !value.isString && value.content in listOf("true", "false"))
            PrimitiveKind.INT -> AgentBridgeChecks.require(value is JsonPrimitive && !value.isString && value.content.toIntOrNull() != null)
            PrimitiveKind.LONG -> AgentBridgeChecks.require(value is JsonPrimitive && !value.isString && value.content.toLongOrNull() != null)
            SerialKind.ENUM -> AgentBridgeChecks.require(value is JsonPrimitive && value.isString)
            StructureKind.LIST -> {
                AgentBridgeChecks.require(value is JsonArray)
                (value as JsonArray).forEach { validate(it, descriptor.getElementDescriptor(0)) }
            }
            StructureKind.CLASS, StructureKind.OBJECT -> {
                AgentBridgeChecks.require(value is JsonObject)
                val obj = value as JsonObject
                val keys = (0 until descriptor.elementsCount).map { descriptor.getElementName(it) }
                AgentBridgeChecks.require(obj.keys.all { it in keys })
                for (i in 0 until descriptor.elementsCount) {
                    val key = keys[i]
                    if (key !in obj) AgentBridgeChecks.require(descriptor.isElementOptional(i))
                    else validate(obj.getValue(key), descriptor.getElementDescriptor(i))
                }
            }
            // Closed content-union serializers check their concrete descriptor at selection time.
            else -> Unit
        }
    }
}

data class AgentBridgeMessage(val type: String, val payload: AgentBridgeDocument)

/** Standalone helper, not installed dispatch and not permission to advertise any new feature. */
class AgentBridgeNegotiation private constructor(
    val baseApplication: Int,
    val appleQueryExtension: Boolean,
    val agentExtension: Boolean,
) {
    companion object {
        fun negotiate(platform: AgentBridgePlatform, hostVersions: List<Int>, sourceVersions: List<Int>): AgentBridgeNegotiation {
            val common = hostVersions.intersect(sourceVersions.toSet())
            val base = if (platform == AgentBridgePlatform.APPLE) 1 else 2
            AgentBridgeChecks.require(base in common, AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
            return AgentBridgeNegotiation(base, platform == AgentBridgePlatform.APPLE && 3 in common, 4 in common)
        }
    }
}
