package com.healthmd.sharedsetup

import java.nio.charset.CharacterCodingException
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI

class SharedSetupCodec(
    private val registry: SharedSetupMetricRegistry = AndroidSharedSetupMetricRegistry(),
) {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = true
        encodeDefaults = true
    }

    fun decode(bytes: ByteArray): SharedSetupDecodeResult {
        if (bytes.size > SHARED_SETUP_MAX_BYTES) return invalid("Shared setup exceeds 256 KB.")
        // Decode before the JSON try block: a malformed UTF-8 sequence must map to
        // the promised Invalid result instead of escaping as an uncaught
        // CharacterCodingException that leaves the import screen stuck on Loading.
        val text = try {
            bytes.decodeToString(throwOnInvalidSequence = true)
        } catch (_: CharacterCodingException) {
            return invalid("Shared setup is not valid UTF-8.")
        }
        val root = try {
            json.parseToJsonElement(text)
        } catch (_: IllegalArgumentException) {
            return invalid("Shared setup is not valid UTF-8 JSON.")
        } catch (_: SerializationException) {
            return invalid("Shared setup is not valid JSON.")
        }
        validateGenericBounds(root)?.let { return invalid(it) }
        scanSecurity(root)?.let { return invalid(it) }
        val obj = root as? JsonObject ?: return invalid("Shared setup must be a JSON object.")
        if (obj["schema"]?.jsonPrimitive?.contentOrNull != SHARED_SETUP_SCHEMA) {
            return invalid("This is not a Health.md shared setup.")
        }
        if (obj["schema_version"]?.jsonPrimitive?.intOrNull != SHARED_SETUP_VERSION) {
            return invalid("This shared setup version is not supported.")
        }
        val document = try {
            json.decodeFromJsonElement<SharedSetupV1>(root)
        } catch (_: Exception) {
            return invalid("Shared setup is missing required settings or contains invalid values.")
        }
        validateDocument(document)?.let { return invalid(it) }
        return SharedSetupDecodeResult.Valid(document)
    }

    fun encode(document: SharedSetupV1): ByteArray {
        validateDocument(document)?.let { throw IllegalArgumentException(it) }
        val encoded = json.encodeToString(document)
        val root = json.parseToJsonElement(encoded)
        validateGenericBounds(root)?.let { throw IllegalArgumentException(it) }
        scanSecurity(root)?.let { throw IllegalArgumentException(it) }
        val bytes = encoded.toByteArray(Charsets.UTF_8)
        require(bytes.size <= SHARED_SETUP_MAX_BYTES) { "Shared setup exceeds 256 KB." }
        return bytes
    }

    internal fun validateDocument(d: SharedSetupV1): String? {
        if (d.schema != SHARED_SETUP_SCHEMA || d.schemaVersion != SHARED_SETUP_VERSION) {
            return "Unsupported shared setup discriminator."
        }
        if (d.createdBy.platform !in setOf("apple", "android") || d.createdBy.appVersion.isBlank() || d.createdBy.appVersion.length > 256) {
            return "Invalid creator metadata."
        }
        if (
            d.metricRegistry.schema != "healthmd.metric_registry" ||
            d.metricRegistry.registryVersion < 1 ||
            !d.metricRegistry.registrySha256.matches(Regex("[0-9a-f]{64}"))
        ) return "Invalid metric registry identity."

        val export = d.profile.export
        if (export.formats.size != export.formats.distinct().size || export.formats.any { it !in FORMATS }) {
            return "Invalid export format."
        }
        if (export.writeMode !in WRITE_MODES) return "Invalid write mode."

        val presentation = d.profile.presentation
        if (presentation.dateFormat !in DATE_FORMATS) return "Invalid date format."
        if (presentation.timeFormat !in TIME_FORMATS) return "Invalid time format."
        if (presentation.units !in setOf("metric", "imperial")) return "Invalid unit preference."
        val frontmatter = presentation.frontmatter
        if (frontmatter.fields.size > 256 || frontmatter.customValues.size > 128 || frontmatter.placeholders.size > 128) {
            return "Frontmatter configuration is too large."
        }
        if (frontmatter.fields.any { !isNonEmptyShortString(it.sourceKey) || !isNonEmptyShortString(it.outputKey) }) {
            return "Invalid frontmatter field identity."
        }
        if (frontmatter.customValues.any { (key, value) -> !isNonEmptyShortString(key) || value.length > 4096 } ||
            frontmatter.placeholders.any { !isNonEmptyShortString(it) } || frontmatter.placeholders.size != frontmatter.placeholders.distinct().size ||
            !isNonEmptyShortString(frontmatter.dateKey) || !isNonEmptyShortString(frontmatter.typeKey) ||
            frontmatter.typeValue.length > 4096 || frontmatter.keyStyle !in setOf("snake_case", "camel_case")
        ) return "Invalid frontmatter configuration."

        val markdown = presentation.markdown
        if (
            markdown.style !in setOf("standard", "compact", "detailed", "custom") ||
            markdown.headerLevel !in 1..6 ||
            markdown.bulletStyle !in setOf("dash", "asterisk", "plus") ||
            markdown.originDialect !in setOf("portable", "apple", "android")
        ) return "Invalid Markdown configuration."
        if (markdown.customText.length > 65_536) return "Custom Markdown is too long."

        val paths = buildList {
            add(export.folderTemplate to true)
            add(export.filenameTemplate to false)
            add(d.profile.individualEntries.entriesFolder to true)
            add(d.profile.individualEntries.filenameTemplate to false)
            add(d.profile.dailyNotes.folder to true)
            add(d.profile.dailyNotes.filenameTemplate to false)
            d.platformExtensions.android?.let { add(it.export.subfolder to true) }
            d.profile.individualEntries.metrics.values.mapNotNull { it.customFolder }.forEach { add(it to true) }
        }
        if (paths.any { !isSafeRelative(it.first, it.second) }) return "A folder or filename template is unsafe."

        val individual = d.profile.individualEntries
        if (individual.metrics.size > 256 || individual.metrics.keys.any { !identifier.matches(it) }) {
            return "Invalid individual-entry metric configuration."
        }

        val schedule = d.profile.schedule
        if (
            schedule.cadence.value !in 1..365 ||
            schedule.cadence.unit !in setOf("minutes", "hours", "days", "weeks", "months") ||
            schedule.localTime.hour !in 0..23 || schedule.localTime.minute !in 0..59 ||
            schedule.lookbackDays !in 1..365 ||
            schedule.dateWindow !in setOf("past_complete_days", "today") ||
            schedule.desiredTarget !in setOf("device_folder", "api_endpoint")
        ) return "Invalid schedule intent."

        d.profile.apiEndpoint?.let { endpoint ->
            if (
                endpoint.scheme != "https" || !endpoint.credentialsRequired ||
                endpoint.port?.let { it !in 1..65535 } == true ||
                !isSafeHost(endpoint.host) || !isSafeEndpointPath(endpoint.path)
            ) return "Unsafe API endpoint hint."
        }

        val ids = d.profile.metrics.enabledIds
        if (ids.size > 256 || ids != ids.sorted() || ids.size != ids.distinct().size || ids.any { !identifier.matches(it) }) {
            return "Metric semantic IDs must be unique and sorted."
        }
        val aliases = d.metricAliases
        val aliasIds = aliases.map { it.semanticId }
        if (
            aliases.size > 256 || aliasIds != aliasIds.sorted() || aliasIds.size != aliasIds.distinct().size ||
            aliasIds.toSet() != ids.toSet()
        ) return "Metric aliases must exactly and uniquely cover selected semantic IDs."

        val sourceMatches = d.metricRegistry.registryVersion == registry.version && d.metricRegistry.registrySha256 == registry.sha256
        aliases.forEach { alias ->
            if (alias.equivalence !in EQUIVALENCES ||
                alias.appleSelectionId?.let { it.length > 128 || !identifier.matches(it) } == true ||
                alias.androidSelectionId?.let { it.length > 128 || !identifier.matches(it) } == true
            ) return "Invalid metric alias evidence."
            val local = registry.bySemanticId[alias.semanticId]
            if (sourceMatches && (
                    local == null || alias.appleSelectionId != local.appleSelectionId ||
                        alias.androidSelectionId != local.androidSelectionId || alias.equivalence != local.equivalence
                    )
            ) return "Metric alias does not match the pinned registry."
        }

        val apple = d.platformExtensions.apple
        val android = d.platformExtensions.android
        if ((d.createdBy.platform == "apple" && apple == null) ||
            (d.createdBy.platform == "android" && android == null) ||
            apple?.extensionVersion?.let { it != 1 } == true ||
            android?.extensionVersion?.let { it != 1 } == true
        ) return "The writer must include its own versioned platform extension."
        if (android != null && (
                android.export.compatibilityProfile !in setOf("frozen_v4", "analytical_v5") ||
                    android.export.folderOrganization !in setOf("flat", "by_year", "by_month", "by_year_month")
                )
        ) return "Invalid Android platform extension."
        if (apple != null && (
                apple.export.rollups.any { it !in setOf("weekly", "monthly", "yearly") } ||
                    apple.export.rollups.size != apple.export.rollups.distinct().size ||
                    apple.schedule.frequency !in setOf("daily", "weekly", "custom") ||
                    apple.schedule.customUnit !in setOf("days", "weeks", "months") ||
                    apple.schedule.weekday !in 1..7 ||
                    apple.schedule.todayRefreshIntervalHours !in setOf(3, 6, 12) ||
                    apple.schedule.desiredTarget !in setOf("local_iphone_folder", "connected_mac", "api_endpoint")
                )
        ) return "Invalid Apple platform extension."
        if (d.createdBy.platform == "apple" && apple != null) {
            val cadenceMatches = when (apple.schedule.frequency) {
                "daily" -> schedule.cadence.value == 1 && schedule.cadence.unit == "days"
                "weekly" -> schedule.cadence.value == 1 && schedule.cadence.unit == "weeks"
                else -> schedule.cadence.unit == apple.schedule.customUnit
            }
            val target = if (apple.schedule.desiredTarget == "api_endpoint") "api_endpoint" else "device_folder"
            if (!cadenceMatches || schedule.desiredTarget != target) {
                return "The portable and Apple schedule representations contradict each other."
            }
        }
        return null
    }

    private fun validateGenericBounds(root: JsonElement): String? {
        var nodes = 0
        fun walk(element: JsonElement, depth: Int): String? {
            nodes += 1
            if (nodes > 16_384) return "Shared setup has too many JSON values."
            if (depth > 16) return "Shared setup is nested too deeply."
            return when (element) {
                is JsonObject -> when {
                    element.size > 256 || element.keys.any { it.length > 256 } -> "Shared setup object is too large."
                    else -> element.values.firstNotNullOfOrNull { walk(it, depth + 1) }
                }
                is JsonArray -> when {
                    element.size > 256 -> "Shared setup array is too large."
                    else -> element.firstNotNullOfOrNull { walk(it, depth + 1) }
                }
                is JsonPrimitive -> if (element.isString && element.content.codePointCount(0, element.content.length) > 65_536) {
                    "Shared setup text is too long."
                } else null
            }
        }
        return walk(root, 0)
    }

    private fun scanSecurity(root: JsonElement): String? {
        val allowedKeys = setOf("credentials_required", "header_level")
        fun walk(element: JsonElement): String? = when (element) {
            is JsonObject -> element.entries.firstNotNullOfOrNull { (key, value) ->
                val normalized = key.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')
                if (normalized !in allowedKeys && FORBIDDEN_KEY_FRAGMENTS.any { normalized.contains(it) }) {
                    "Shared setup contains a forbidden sensitive or runtime field."
                } else walk(value)
            }
            is JsonArray -> element.firstNotNullOfOrNull(::walk)
            is JsonPrimitive -> if (element.isString && containsForbiddenString(element.content)) {
                "Shared setup contains device-bound or authorization material."
            } else null
        }
        return walk(root)
    }

    companion object {
        private val identifier = Regex("^[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*$")
        private val FORMATS = setOf("markdown", "obsidian_bases", "json", "csv")
        private val WRITE_MODES = setOf("overwrite", "append", "update")
        private val DATE_FORMATS = setOf("iso8601", "us_short", "us_long", "eu_short", "eu_long", "compact", "friendly")
        private val TIME_FORMATS = setOf("hour_24", "hour_24_seconds", "hour_12", "hour_12_seconds")
        private val EQUIVALENCES = setOf("platform_exact_or_unavailable", "mapped_alias", "platform_distinct")
        private val FORBIDDEN_KEY_FRAGMENTS = listOf(
            "credential", "password", "token", "secret", "authorization", "request_header", "cookie",
            "bookmark", "saf_uri", "content_uri", "folder_grant", "permission", "purchase", "entitlement",
            "history", "device_id", "installation_id", "account_id", "health_record", "health_data", "source_data",
            "analytics", "email", "api_key", "raw_snapshot", "session_id", "pending_retry", "pending_request",
            "operation_id", "destination_fingerprint", "engine_pin", "last_run", "last_success", "enabled_at",
            "worker_id", "alarm_id", "enabled_categories", "category_selection", "onboarding",
        )

        private fun isNonEmptyShortString(value: String): Boolean =
            value.isNotEmpty() && value.length <= 256 && value.none { it.code < 32 }

        fun isSafeRelative(value: String, allowSegments: Boolean): Boolean {
            if (
                value.length > 4096 || value.any { it.code < 32 } || value.contains('\\') || value.contains('%') ||
                value.contains("://") || value.startsWith('/') || value.matches(Regex("^[A-Za-z]:.*"))
            ) return false
            val parts = value.split('/')
            if (value.isNotEmpty() && parts.any { it.isEmpty() || it == "." || it == ".." }) return false
            return allowSegments || (value.isNotEmpty() && parts.size == 1)
        }

        fun isSafeHost(host: String): Boolean = host.length in 1..253 && runCatching {
            URI("https://$host/").host == host && host.split('.').all { label ->
                label.isNotBlank() && label.length <= 63 && !label.startsWith('-') && !label.endsWith('-') &&
                    label.all { it.isLetterOrDigit() || it == '-' }
            }
        }.getOrDefault(false)

        fun isSafeEndpointPath(path: String): Boolean =
            path.startsWith('/') && !path.startsWith("//") && path.length <= 2048 &&
                path.none { it in "%?#" || it.code < 32 }

        fun templateSyntaxProblem(text: String): String? {
            if (text.length > 65_536) return "Custom Markdown is too long."
            val token = Regex("\\{\\{([#/]?)([A-Za-z0-9_]+)\\}\\}")
            val stack = ArrayDeque<String>()
            token.findAll(text).forEach { match ->
                when (match.groupValues[1]) {
                    "#" -> {
                        if (stack.isNotEmpty()) return "Nested template sections are not supported."
                        stack.addLast(match.groupValues[2])
                    }
                    "/" -> if (stack.removeLastOrNull() != match.groupValues[2]) {
                        return "Template sections are not balanced."
                    }
                }
            }
            val unmatched = text.replace(token, "")
            if (stack.isNotEmpty() || unmatched.contains("{{") || unmatched.contains("}}")) {
                return "Template tokens are malformed."
            }
            return null
        }

        private fun containsForbiddenString(value: String): Boolean =
            value.startsWith("content://", ignoreCase = true) || value.startsWith("file://", ignoreCase = true) ||
                Regex("(?i)\\b(?:bearer|basic)\\s+[a-z0-9]").containsMatchIn(value) ||
                value.contains("authorization:", ignoreCase = true)

        private fun invalid(message: String) = SharedSetupDecodeResult.Invalid(message)
    }
}
