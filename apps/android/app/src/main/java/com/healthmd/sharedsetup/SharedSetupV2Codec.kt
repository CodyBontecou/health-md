package com.healthmd.sharedsetup

import java.net.URI
import java.nio.charset.CharacterCodingException
import java.time.LocalDate
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

/**
 * Bounded version dispatcher plus the independent Shared Setup v2 codec.
 *
 * Dispatch examines only a generically preflighted JSON object. No typed v1 or v2 decode occurs
 * until `schema` and the lexical integer `schema_version` have been accepted. V1 is then delegated
 * unchanged to its existing codec and keeps its 256 KiB and v1 structural limits.
 */
class SharedSetupV2Codec(
    private val registry: SharedSetupMetricRegistry = AndroidSharedSetupMetricRegistry(),
) {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = true
        encodeDefaults = true
        isLenient = false
    }
    private val v1Codec by lazy { SharedSetupCodec(registry) }

    fun decode(bytes: ByteArray): SharedSetupVersionedDecodeResult {
        if (bytes.size > SHARED_SETUP_V2_MAX_BYTES) {
            return invalid("Shared setup exceeds 4 MiB.")
        }
        val text = try {
            bytes.decodeToString(throwOnInvalidSequence = true)
        } catch (_: CharacterCodingException) {
            return invalid("Shared setup is not valid UTF-8.")
        }
        val root = try {
            json.parseToJsonElement(text)
        } catch (_: SerializationException) {
            return invalid("Shared setup is not valid JSON.")
        } catch (_: IllegalArgumentException) {
            return invalid("Shared setup is not valid UTF-8 JSON.")
        }

        validateGenericBounds(root)?.let { return invalid(it) }
        val objectRoot = root as? JsonObject
            ?: return invalid("Shared setup must be a JSON object.")
        val schema = objectRoot["schema"] as? JsonPrimitive
        if (schema?.isString != true || schema.content != SHARED_SETUP_SCHEMA) {
            return invalid("This is not a Health.md shared setup.")
        }
        val versionPrimitive = objectRoot["schema_version"] as? JsonPrimitive
        val version = versionPrimitive?.strictIntegerOrNull()
            ?: return invalid("Shared setup schema_version must be an integer.")

        return when (version) {
            SHARED_SETUP_VERSION -> {
                if (bytes.size > SHARED_SETUP_MAX_BYTES) {
                    invalid("Shared Setup v1 exceeds 256 KiB.")
                } else {
                    when (val decoded = v1Codec.decode(bytes)) {
                        is SharedSetupDecodeResult.Valid -> SharedSetupVersionedDecodeResult.Valid(
                            SharedSetupDecodedDocument.V1(decoded.document),
                        )
                        is SharedSetupDecodeResult.Invalid -> invalid(decoded.message)
                    }
                }
            }
            SHARED_SETUP_V2_VERSION -> decodeV2(root)
            else -> invalid("This shared setup version is not supported.")
        }
    }

    /** Canonical v2 only. Production v1 writing remains owned by [SharedSetupCodec]. */
    fun encode(document: SharedSetupV2): ByteArray {
        validateV2Document(document)?.let { throw IllegalArgumentException(it) }
        val canonical = canonicalize(
            json.encodeToJsonElement(SharedSetupV2.serializer(), document),
        )
        validateGenericBounds(canonical)?.let { throw IllegalArgumentException(it) }
        scanSecurity(canonical)?.let { throw IllegalArgumentException(it) }
        val encoded = canonical.toString().encodeToByteArray()
        require(encoded.size <= SHARED_SETUP_V2_MAX_BYTES) { "Shared setup exceeds 4 MiB." }
        return encoded
    }

    private fun decodeV2(root: JsonElement): SharedSetupVersionedDecodeResult {
        scanSecurity(root)?.let { return invalid(it) }
        val document = try {
            json.decodeFromJsonElement<SharedSetupV2>(root)
        } catch (_: Exception) {
            return invalid("Shared Setup v2 is missing required settings or contains invalid values.")
        }
        validateV2Document(document)?.let { return invalid(it) }
        return SharedSetupVersionedDecodeResult.Valid(SharedSetupDecodedDocument.V2(document))
    }

    internal fun validateV2Document(document: SharedSetupV2): String? {
        if (document.schema != SHARED_SETUP_SCHEMA || document.schemaVersion != SHARED_SETUP_V2_VERSION) {
            return "Unsupported Shared Setup v2 discriminator."
        }
        if (
            document.createdBy.platform !in PLATFORMS ||
            !document.createdBy.appVersion.isNonEmptyBounded(256)
        ) {
            return "Invalid creator metadata."
        }
        if (
            document.metricRegistry.schema != METRIC_REGISTRY_SCHEMA ||
            document.metricRegistry.registryVersion != METRIC_REGISTRY_VERSION ||
            !document.metricRegistry.registrySha256.isLowercaseSha256()
        ) {
            return "Invalid metric registry identity."
        }
        if (document.profiles.size !in 1..SHARED_SETUP_V2_MAX_PROFILES) {
            return "Shared Setup v2 must contain between 1 and 100 profiles."
        }

        val expectedBundleIds = document.profiles.indices.map(::bundleIdForIndex)
        if (document.profiles.map { it.bundleId } != expectedBundleIds) {
            return "Profile bundle IDs must be sequential and match profile order."
        }
        if (document.activeProfile !in expectedBundleIds) {
            return "The active profile reference is invalid."
        }
        val names = document.profiles.map { it.name }
        if (
            names.any { !it.isNonEmptyBounded(256) || it != it.trim() } ||
            names.map { it.lowercase() }.distinct().size != names.size
        ) {
            return "Profile names must be trimmed, non-empty, and case-insensitively unique."
        }

        document.profiles.forEach { profile ->
            validateProfile(profile, document.createdBy.platform)?.let { return it }
        }

        val requiredAliasIds = document.profiles
            .flatMap { profile ->
                profile.metrics.enabledIds + profile.individualEntries.metrics.keys
            }
            .toSortedSet()
            .toList()
        val aliases = document.metricAliases
        val aliasIds = aliases.map { it.semanticId }
        if (
            aliases.size > MAX_ALIASES ||
            aliasIds != aliasIds.sorted() ||
            aliasIds.distinct().size != aliasIds.size ||
            aliasIds != requiredAliasIds
        ) {
            return "Metric aliases must exactly and uniquely cover every referenced semantic ID."
        }
        val sourceRegistryMatches =
            document.metricRegistry.registryVersion == registry.version &&
                document.metricRegistry.registrySha256 == registry.sha256
        aliases.forEach { alias ->
            if (
                !alias.semanticId.isIdentifier() ||
                alias.equivalence !in EQUIVALENCES ||
                alias.appleSelectionId?.isIdentifier() == false ||
                alias.androidSelectionId?.isIdentifier() == false
            ) {
                return "Invalid metric alias evidence."
            }
            if (sourceRegistryMatches) {
                val local = registry.bySemanticId[alias.semanticId]
                if (
                    local == null ||
                    alias.equivalence != local.equivalence ||
                    alias.appleSelectionId != local.appleSelectionId ||
                    alias.androidSelectionId != local.androidSelectionId
                ) {
                    return "Metric alias does not match the pinned registry."
                }
            }
        }
        return null
    }

    private fun validateProfile(profile: SharedSetupV2Profile, writerPlatform: String): String? {
        val export = profile.export
        if (
            export.formats.size > 4 ||
            export.formats != export.formats.sorted() ||
            export.formats.distinct().size != export.formats.size ||
            export.formats.any { it !in FORMATS } ||
            export.writeMode !in WRITE_MODES ||
            export.compatibilityDetail !in COMPATIBILITY_DETAILS ||
            !isSafeRelative(export.folderTemplate, allowSegments = true) ||
            !isSafeRelative(export.filenameTemplate, allowSegments = false)
        ) {
            return "Invalid portable export settings."
        }

        val enabledIds = profile.metrics.enabledIds
        if (
            enabledIds.size > MAX_PROFILE_METRICS ||
            enabledIds != enabledIds.sorted() ||
            enabledIds.distinct().size != enabledIds.size ||
            enabledIds.any { !it.isIdentifier() }
        ) {
            return "Metric semantic IDs must be unique and sorted."
        }

        validatePresentation(profile.presentation)?.let { return it }
        validateIndividualEntries(profile.individualEntries)?.let { return it }
        if (
            !isSafeRelative(profile.dailyNotes.folder, allowSegments = true) ||
            !isSafeRelative(profile.dailyNotes.filenameTemplate, allowSegments = false)
        ) {
            return "Invalid Daily Notes paths."
        }
        validateDestination(profile.destination)?.let { return it }
        profile.schedule?.let { schedule ->
            validateSchedule(schedule)?.let { return it }
        }
        validateExtensions(profile, writerPlatform)?.let { return it }
        return null
    }

    private fun validatePresentation(presentation: SharedSetupV2Presentation): String? {
        if (
            presentation.dateFormat !in DATE_FORMATS ||
            presentation.timeFormat !in TIME_FORMATS ||
            presentation.units !in UNITS
        ) {
            return "Invalid presentation preferences."
        }
        val frontmatter = presentation.frontmatter
        if (
            frontmatter.fields.size > 256 ||
            frontmatter.customValues.size > 128 ||
            frontmatter.placeholders.size > 128 ||
            frontmatter.placeholders.distinct().size != frontmatter.placeholders.size ||
            frontmatter.fields.any {
                !it.sourceKey.isNonEmptyBounded(256) || !it.outputKey.isNonEmptyBounded(256)
            } ||
            frontmatter.customValues.any { (key, value) ->
                !key.isNonEmptyBounded(256) || value.scalarCount() > 4_096
            } ||
            frontmatter.placeholders.any { !it.isNonEmptyBounded(256) } ||
            !frontmatter.dateKey.isNonEmptyBounded(256) ||
            !frontmatter.typeKey.isNonEmptyBounded(256) ||
            frontmatter.typeValue.scalarCount() > 4_096 ||
            frontmatter.keyStyle !in KEY_STYLES
        ) {
            return "Invalid frontmatter configuration."
        }
        val markdown = presentation.markdown
        if (
            markdown.style !in MARKDOWN_STYLES ||
            markdown.customText.scalarCount() > MAX_CUSTOM_MARKDOWN_SCALARS ||
            markdown.headerLevel !in 1..6 ||
            markdown.bulletStyle !in BULLET_STYLES ||
            markdown.originDialect !in ORIGIN_DIALECTS
        ) {
            return "Invalid Markdown configuration."
        }
        return null
    }

    private fun validateIndividualEntries(individual: SharedSetupV2IndividualEntries): String? {
        if (
            individual.metrics.size > MAX_PROFILE_METRICS ||
            individual.metrics.keys.any { !it.isIdentifier() } ||
            !isSafeRelative(individual.entriesFolder, allowSegments = true) ||
            !isSafeRelative(individual.filenameTemplate, allowSegments = false) ||
            individual.metrics.values.any { metric ->
                metric.customFolder?.let { !isSafeRelative(it, allowSegments = true) } == true
            }
        ) {
            return "Invalid individual-entry configuration."
        }
        return null
    }

    private fun validateDestination(destination: SharedSetupV2Destination): String? {
        if (destination.kind !in DESTINATION_KINDS) {
            return "Invalid destination intent."
        }
        if (destination.kind != "api_endpoint" && destination.apiEndpoint != null) {
            return "Only an API endpoint destination may contain an endpoint hint."
        }
        destination.apiEndpoint?.let { endpoint ->
            if (
                endpoint.scheme != "https" ||
                !endpoint.credentialsRequired ||
                endpoint.port?.let { it !in 1..65_535 } == true ||
                !isSafeHost(endpoint.host) ||
                !isSafeEndpointPath(endpoint.path)
            ) {
                return "Unsafe API endpoint hint."
            }
        }
        return null
    }

    private fun validateSchedule(schedule: SharedSetupV2Schedule): String? {
        val anchor = runCatching { LocalDate.parse(schedule.cadence.anchorDate) }.getOrNull()
        if (
            schedule.cadence.value !in 1..365 ||
            schedule.cadence.unit !in CADENCE_UNITS ||
            anchor == null || anchor.toString() != schedule.cadence.anchorDate ||
            schedule.localTime.hour !in 0..23 ||
            schedule.localTime.minute !in 0..59 ||
            schedule.weekday !in 1..7 ||
            schedule.lookbackDays !in 1..365 ||
            schedule.dateWindow != "past_complete_days"
        ) {
            return "Invalid schedule intent."
        }
        return null
    }

    private fun validateExtensions(
        profile: SharedSetupV2Profile,
        writerPlatform: String,
    ): String? {
        val apple = profile.platformExtensions.apple
        val android = profile.platformExtensions.android
        if (
            (writerPlatform == "apple" && apple == null) ||
            (writerPlatform == "android" && android == null)
        ) {
            return "The writer must include its own extension for every profile."
        }
        if (apple?.extensionVersion?.let { it != SHARED_SETUP_V2_VERSION } == true) {
            return "Invalid Apple extension version."
        }
        if (android?.extensionVersion?.let { it != SHARED_SETUP_V2_VERSION } == true) {
            return "Invalid Android extension version."
        }

        apple?.let { extension ->
            if (extension.export.healthkitSourceArchive !in HEALTHKIT_ARCHIVES) {
                return "Invalid Apple archive policy."
            }
            extension.schedule?.let { schedule ->
                if (
                    schedule.frequency !in APPLE_SCHEDULE_FREQUENCIES ||
                    schedule.customUnit !in CADENCE_UNITS ||
                    schedule.todayRefreshIntervalHours !in TODAY_REFRESH_INTERVALS
                ) {
                    return "Invalid Apple schedule extension."
                }
            }
        }

        android?.export?.let { export ->
            if (
                export.mode !in ANDROID_MODES ||
                export.legacyPrimaryFormat !in FORMATS ||
                export.compatibilityProfile !in ANDROID_COMPATIBILITY_PROFILES ||
                export.folderOrganization !in FOLDER_ORGANIZATIONS ||
                !isSafeRelative(export.subfolder, allowSegments = true) ||
                export.rawSnapshot.format !in RAW_FORMATS ||
                export.rawSnapshot.scope !in RAW_SCOPES ||
                export.rawSnapshot.pageSize !in 1..5_000
            ) {
                return "Invalid Android extension."
            }
        }

        // Only an Apple-authored extension is authoritative enough to constrain the common
        // schedule. A foreign Apple extension retained by Android is preserved, not approximated.
        if (writerPlatform == "apple") {
            val appleSchedule = requireNotNull(apple).schedule
            if ((profile.schedule == null) != (appleSchedule == null)) {
                return "The portable and Apple schedule representations contradict each other."
            }
            if (profile.schedule != null && appleSchedule != null) {
                val cadenceMatches = when (appleSchedule.frequency) {
                    "daily" -> profile.schedule.cadence.value == 1 && profile.schedule.cadence.unit == "days"
                    "weekly" -> profile.schedule.cadence.value == 1 && profile.schedule.cadence.unit == "weeks"
                    else -> profile.schedule.cadence.unit == appleSchedule.customUnit
                }
                if (!cadenceMatches) {
                    return "The portable and Apple schedule representations contradict each other."
                }
            }
        }
        return null
    }

    private fun validateGenericBounds(root: JsonElement): String? {
        var nodes = 0
        fun walk(element: JsonElement, depth: Int): String? {
            nodes += 1
            if (nodes > MAX_JSON_NODES) return "Shared setup has too many JSON values."
            if (depth > MAX_JSON_DEPTH) return "Shared setup is nested too deeply."
            return when (element) {
                is JsonObject -> when {
                    element.size > MAX_JSON_CONTAINER_SIZE -> "Shared setup object is too large."
                    element.keys.any { it.scalarCount() > MAX_JSON_STRING_SCALARS } ->
                        "Shared setup object key is too long."
                    else -> element.values.firstNotNullOfOrNull { walk(it, depth + 1) }
                }
                is JsonArray -> when {
                    element.size > MAX_JSON_CONTAINER_SIZE -> "Shared setup array is too large."
                    else -> element.firstNotNullOfOrNull { walk(it, depth + 1) }
                }
                is JsonPrimitive -> if (
                    element.isString && element.content.scalarCount() > MAX_JSON_STRING_SCALARS
                ) {
                    "Shared setup text is too long."
                } else {
                    null
                }
            }
        }
        return walk(root, 0)
    }

    /** Security preflight covers known and ignored unknown input before typed decoding. */
    private fun scanSecurity(root: JsonElement): String? {
        fun walk(element: JsonElement, isEndpointComponent: Boolean = false): String? = when (element) {
            is JsonObject -> element.entries.firstNotNullOfOrNull { (key, value) ->
                val normalized = key
                    .replace(Regex("([a-z0-9])([A-Z])"), "$1_$2")
                    .lowercase()
                    .replace(Regex("[^a-z0-9]+"), "_")
                    .trim('_')
                if (
                    FORBIDDEN_KEY_FRAGMENTS.any(normalized::contains) &&
                    !isAllowedSecurityKey(normalized, element, value)
                ) {
                    "Shared setup contains a forbidden sensitive or runtime field."
                } else {
                    val endpointComponent =
                        key in setOf("host", "path") &&
                            (element["scheme"] as? JsonPrimitive)?.let {
                                it.isString && it.content == "https"
                            } == true
                    walk(value, isEndpointComponent = endpointComponent)
                }
            }
            is JsonArray -> element.firstNotNullOfOrNull { walk(it) }
            is JsonPrimitive -> if (
                element.isString && containsForbiddenString(
                    value = element.content,
                    allowEndpointIdentity = isEndpointComponent,
                )
            ) {
                "Shared setup contains device-bound or authorization material."
            } else {
                null
            }
        }
        return walk(root)
    }

    private fun canonicalize(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(
            element.entries
                .sortedBy { it.key }
                .associate { (key, value) -> key to canonicalize(value) },
        )
        is JsonArray -> JsonArray(element.map(::canonicalize))
        else -> element
    }

    companion object {
        internal const val MAX_JSON_DEPTH: Int = 20
        internal const val MAX_JSON_CONTAINER_SIZE: Int = 512
        internal const val MAX_JSON_STRING_SCALARS: Int = 65_536
        internal const val MAX_JSON_NODES: Int = 262_144

        private const val MAX_PROFILE_METRICS = 256
        private const val MAX_ALIASES = 512
        private const val MAX_CUSTOM_MARKDOWN_SCALARS = 65_536
        private const val METRIC_REGISTRY_SCHEMA = "healthmd.metric_registry"
        private const val METRIC_REGISTRY_VERSION = 1

        private val INTEGER_LEXEME = Regex("-?(?:0|[1-9][0-9]*)")
        private val IDENTIFIER = Regex("^[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*$")
        private val LOWERCASE_SHA256 = Regex("^[0-9a-f]{64}$")
        private val UUID = Regex("(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(?![0-9a-f])")
        private val WINDOWS_ABSOLUTE_PATH = Regex("(?i)(?:^|[\\s\"'])(?:[a-z]:[\\\\/])")
        private val URL_USERINFO = Regex("(?i)https?://[^\\s/@]+(?::[^\\s/@]*)?@")
        private val SECRET_QUERY = Regex("(?i)[?&](?:access_?token|api_?key|password|secret|authorization)=")

        private val PLATFORMS = setOf("apple", "android")
        private val FORMATS = setOf("csv", "json", "markdown", "obsidian_bases")
        private val WRITE_MODES = setOf("overwrite", "append", "update")
        private val COMPATIBILITY_DETAILS = setOf("summary", "selected_time_series")
        private val DATE_FORMATS = setOf("iso8601", "us_short", "us_long", "eu_short", "eu_long", "compact", "friendly")
        private val TIME_FORMATS = setOf("hour_24", "hour_24_seconds", "hour_12", "hour_12_seconds")
        private val UNITS = setOf("metric", "imperial")
        private val KEY_STYLES = setOf("snake_case", "camel_case")
        private val MARKDOWN_STYLES = setOf("standard", "compact", "detailed", "custom")
        private val BULLET_STYLES = setOf("dash", "asterisk", "plus")
        private val ORIGIN_DIALECTS = setOf("portable", "apple", "android")
        private val DESTINATION_KINDS = setOf("device_folder", "connected_mac", "api_endpoint", "cloud")
        private val CADENCE_UNITS = setOf("days", "weeks", "months")
        private val EQUIVALENCES = setOf("platform_exact_or_unavailable", "mapped_alias", "platform_distinct")
        private val HEALTHKIT_ARCHIVES = setOf("none", "canonical_v1")
        private val APPLE_SCHEDULE_FREQUENCIES = setOf("daily", "weekly", "custom")
        private val TODAY_REFRESH_INTERVALS = setOf(3, 6, 12)
        private val ANDROID_MODES = setOf("compatibility", "raw_snapshot")
        private val ANDROID_COMPATIBILITY_PROFILES = setOf("frozen_v4", "analytical_v5")
        private val FOLDER_ORGANIZATIONS = setOf("flat", "by_year", "by_month", "by_year_month")
        private val RAW_FORMATS = setOf("json", "ndjson")
        private val RAW_SCOPES = setOf("selected_record_types", "all_authorized_supported_data")

        private val FORBIDDEN_KEY_FRAGMENTS = listOf(
            "credential",
            "password",
            "token",
            "secret",
            "authorization",
            "oauth",
            "request_header",
            "endpoint_header",
            "header",
            "cookie",
            "bookmark",
            "saf_uri",
            "content_uri",
            "folder_uri",
            "folder_grant",
            "grant_state",
            "display_grant",
            "native_profile",
            "native_id",
            "native_identity",
            "profile_uuid",
            "device_id",
            "installation_id",
            "install_id",
            "account_id",
            "user_id",
            "pairing",
            "purchase",
            "permission",
            "entitlement",
            "onboarding",
            "runtime",
            "timestamp",
            "created_at",
            "updated_at",
            "enabled_at",
            "last_run",
            "last_success",
            "refresh_history",
            "export_history",
            "progress",
            "pending",
            "retry",
            "operation_id",
            "destination_fingerprint",
            "fingerprint",
            "engine_pin",
            "engine_authority",
            "renderer_pin",
            "timezone",
            "time_zone",
            "zone_id",
            "worker_id",
            "alarm_id",
            "health_record",
            "health_data",
            "source_data",
            "api_endpoint_url",
            "destination_root",
            "destination_path",
            "native_path",
            "root_path",
        )

        internal fun bundleIdForIndex(index: Int): String = "profile-%03d".format(index + 1)

        private fun isAllowedSecurityKey(
            normalizedKey: String,
            parent: JsonObject,
            value: JsonElement,
        ): Boolean = when (normalizedKey) {
            "credentials_required" ->
                (value as? JsonPrimitive)?.let {
                    !it.isString && it.content == "true"
                } == true &&
                    (parent["scheme"] as? JsonPrimitive)?.let {
                        it.isString && it.content == "https"
                    } == true &&
                    parent.keys.containsAll(setOf("host", "path", "query_omitted"))
            "header_level" ->
                (value as? JsonPrimitive)?.strictIntegerOrNull()?.let { it in 1..6 } == true &&
                    parent.keys.containsAll(setOf("style", "custom_text"))
            else -> false
        }

        private fun JsonPrimitive.strictIntegerOrNull(): Int? =
            takeUnless { isString }
                ?.content
                ?.takeIf(INTEGER_LEXEME::matches)
                ?.toIntOrNull()

        private fun String.isLowercaseSha256(): Boolean = LOWERCASE_SHA256.matches(this)

        private fun String.isIdentifier(): Boolean =
            scalarCount() in 1..128 && IDENTIFIER.matches(this)

        private fun String.isNonEmptyBounded(maxScalars: Int): Boolean =
            isNotBlank() && scalarCount() <= maxScalars && none { it.code < 32 }

        private fun String.scalarCount(): Int = codePointCount(0, length)

        internal fun isSafeRelative(value: String, allowSegments: Boolean): Boolean {
            if (
                value.scalarCount() > 4_096 ||
                value.any { it.code < 32 } ||
                value.contains('\\') ||
                value.contains('%') ||
                value.contains("://") ||
                value.startsWith('/') ||
                value.matches(Regex("^[A-Za-z]:.*"))
            ) {
                return false
            }
            val parts = value.split('/')
            if (value.isNotEmpty() && parts.any { it.isEmpty() || it == "." || it == ".." }) {
                return false
            }
            return allowSegments || (value.isNotEmpty() && parts.size == 1)
        }

        internal fun isSafeHost(host: String): Boolean =
            host.scalarCount() in 1..253 && runCatching {
                URI("https://$host/").host == host && host.split('.').all { label ->
                    label.isNotBlank() &&
                        label.length <= 63 &&
                        !label.startsWith('-') &&
                        !label.endsWith('-') &&
                        label.all { it.isLetterOrDigit() && it.code < 128 || it == '-' }
                }
            }.getOrDefault(false)

        internal fun isSafeEndpointPath(path: String): Boolean =
            path.startsWith('/') &&
                !path.startsWith("//") &&
                path.scalarCount() <= 2_048 &&
                path.none { it in "%?#" || it.code < 32 }

        private fun containsForbiddenString(
            value: String,
            allowEndpointIdentity: Boolean,
        ): Boolean {
            val lowercase = value.lowercase()
            val containsNativeIdentityOrPath = !allowEndpointIdentity && (
                UUID.containsMatchIn(value) ||
                    WINDOWS_ABSOLUTE_PATH.containsMatchIn(value) ||
                    lowercase.contains("/users/") ||
                    lowercase.contains("/home/") ||
                    lowercase.contains("/private/") ||
                    lowercase.contains("/var/mobile/") ||
                    lowercase.contains("/data/user/") ||
                    lowercase.contains("/storage/emulated/") ||
                    lowercase.contains("/sdcard/") ||
                    lowercase.contains("/mnt/") ||
                    lowercase.startsWith("~/")
                )
            return lowercase.contains("content://") ||
                lowercase.contains("file://") ||
                lowercase.contains("saf://") ||
                Regex("(?i)\\b(?:bearer|basic)\\s+[a-z0-9+/=_-]").containsMatchIn(value) ||
                value.contains("authorization:", ignoreCase = true) ||
                value.contains("-----BEGIN PRIVATE KEY", ignoreCase = true) ||
                containsNativeIdentityOrPath ||
                URL_USERINFO.containsMatchIn(value) ||
                SECRET_QUERY.containsMatchIn(value)
        }

        private fun invalid(message: String): SharedSetupVersionedDecodeResult.Invalid =
            SharedSetupVersionedDecodeResult.Invalid(message)
    }
}
