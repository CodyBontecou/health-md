package com.healthmd.domain.exportengine

import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.BulletStyle
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.rawexport.ExportMode
import java.nio.charset.StandardCharsets
import java.time.ZoneId
import java.util.Collections
import java.util.LinkedHashMap
import java.util.LinkedHashSet
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * Immutable, non-secret output settings accepted for one Android scheduled export operation.
 *
 * Destination credentials, request headers, folder grants, schedule state, pending work, purchase
 * state, and execution history deliberately remain outside this value. The endpoint identity is a
 * one-way hash; [restoreOnto] retains current destination plumbing only when that identity still
 * matches.
 */
@Serializable
data class AndroidExportSettingsSnapshot(
    val version: Int = CURRENT_VERSION,
    val exportMode: ExportMode,
    val exportProfile: AndroidExportProfile,
    val rawSnapshot: RawSnapshotSettings,
    val dataTypes: DataTypeSelection,
    val exportFormat: ExportFormat,
    val exportFormats: Set<ExportFormat>,
    val includeMetadata: Boolean,
    val groupByCategory: Boolean,
    val filenameFormat: String,
    val folderStructure: String,
    val writeMode: WriteMode,
    @Serializable(with = SnapshotFormatCustomizationSerializer::class)
    val formatCustomization: FormatCustomization,
    val metricSelection: MetricSelectionState,
    val dailyNoteInjection: DailyNoteInjectionSettings,
    val individualTracking: IndividualTrackingSettings,
    val includeGranularData: Boolean,
    val exportTarget: ExportTarget,
    val scheduledExportTarget: ExportTarget,
    val apiEndpointIdentitySha256: String? = null,
    val subfolder: String,
    val folderOrganization: FolderOrganization,
    val enginePin: ExportEnginePin? = null,
    val ianaTimeZone: String,
) {
    /**
     * Applies only frozen output choices. Current folder grants, endpoint URL/credentials, schedule
     * cadence/state, retry queues, and other installation plumbing are retained from [current].
     */
    fun restoreOnto(current: ExportSettings): ExportSettings {
        if (!AndroidExportSettingsSnapshotCodec.isStructurallyValid(this)) {
            throw AndroidExportSettingsSnapshotException(
                AndroidExportSettingsSnapshotError.INVALID_STRUCTURE,
            )
        }
        if (
            scheduledExportTarget == ExportTarget.API_ENDPOINT &&
            APIExportEndpoint.fingerprint(current.apiEndpointUrl) != apiEndpointIdentitySha256
        ) {
            throw AndroidExportSettingsSnapshotException(
                AndroidExportSettingsSnapshotError.DESTINATION_MISMATCH,
            )
        }

        val frozen = immutableDeepCopy()
        return current.copy(
            exportMode = frozen.exportMode,
            rawSnapshot = frozen.rawSnapshot,
            dataTypes = frozen.dataTypes,
            exportFormat = frozen.exportFormat,
            exportFormats = frozen.exportFormats,
            includeMetadata = frozen.includeMetadata,
            groupByCategory = frozen.groupByCategory,
            filenameFormat = frozen.filenameFormat,
            folderStructure = frozen.folderStructure,
            writeMode = frozen.writeMode,
            formatCustomization = frozen.formatCustomization,
            metricSelection = frozen.metricSelection,
            dailyNoteInjection = frozen.dailyNoteInjection,
            individualTracking = frozen.individualTracking,
            includeGranularData = frozen.includeGranularData,
            exportTarget = frozen.exportTarget,
            scheduledExportTarget = frozen.scheduledExportTarget,
            subfolder = frozen.subfolder,
            folderOrganization = frozen.folderOrganization,
            executionEnginePin = null,
            executionEngineAuthorityIsFrozen = true,
        )
    }

    companion object {
        const val CURRENT_VERSION: Int = 1

        /** Captures and size-validates every non-secret output setting before provider reads begin. */
        fun capture(
            settings: ExportSettings,
            pin: ExportEnginePin?,
            zone: ZoneId,
        ): AndroidExportSettingsSnapshot {
            val canonicalZone = runCatching { ZoneId.of(zone.id).id }.getOrElse {
                throw AndroidExportSettingsSnapshotException(
                    AndroidExportSettingsSnapshotError.INVALID_STRUCTURE,
                )
            }
            val operationProfile = settings.expectedScheduledExportProfile()
            val snapshot = AndroidExportSettingsSnapshot(
                exportMode = settings.exportMode,
                exportProfile = operationProfile,
                rawSnapshot = settings.rawSnapshot.normalized().copy(),
                dataTypes = settings.dataTypes.copy(),
                exportFormat = settings.exportFormat,
                exportFormats = settings.exportFormats.immutableSortedBy { it.name },
                includeMetadata = settings.includeMetadata,
                groupByCategory = settings.groupByCategory,
                filenameFormat = settings.filenameFormat,
                folderStructure = settings.folderStructure,
                writeMode = settings.writeMode,
                formatCustomization = settings.formatCustomization.immutableDeepCopy(),
                metricSelection = settings.metricSelection.immutableDeepCopy(),
                dailyNoteInjection = settings.dailyNoteInjection.immutableDeepCopy(),
                individualTracking = settings.individualTracking.immutableDeepCopy(),
                includeGranularData = settings.includeGranularData,
                exportTarget = settings.exportTarget,
                scheduledExportTarget = settings.scheduledExportTarget,
                apiEndpointIdentitySha256 = if (
                    settings.scheduledExportTarget == ExportTarget.API_ENDPOINT
                ) {
                    APIExportEndpoint.fingerprint(settings.apiEndpointUrl)
                } else {
                    null
                },
                subfolder = settings.subfolder,
                folderOrganization = settings.folderOrganization,
                enginePin = pin,
                ianaTimeZone = canonicalZone,
            ).immutableDeepCopy()

            // Encoding here makes an oversized or structurally inconsistent snapshot fail before
            // an alarm/work request can be accepted.
            AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
            return snapshot
        }
    }
}

enum class AndroidExportSettingsSnapshotError {
    INVALID_STRUCTURE,
    INVALID_CANONICAL_JSON,
    SIZE_LIMIT_EXCEEDED,
    DESTINATION_MISMATCH,
}

/** Errors intentionally contain no user settings, endpoint, template, metric, or health values. */
class AndroidExportSettingsSnapshotException(
    val reason: AndroidExportSettingsSnapshotError,
) : IllegalArgumentException(
    when (reason) {
        AndroidExportSettingsSnapshotError.SIZE_LIMIT_EXCEEDED ->
            "Scheduled export settings snapshot exceeds its durable size limit."
        AndroidExportSettingsSnapshotError.DESTINATION_MISMATCH ->
            "Scheduled export destination no longer matches the accepted snapshot."
        AndroidExportSettingsSnapshotError.INVALID_STRUCTURE,
        AndroidExportSettingsSnapshotError.INVALID_CANONICAL_JSON ->
            "Scheduled export settings snapshot is invalid."
    },
)

/** Compact snapshot-only serializer; the app's persisted FormatCustomization wire shape is unchanged. */
object SnapshotFormatCustomizationSerializer : KSerializer<FormatCustomization> {
    override val descriptor: SerialDescriptor = SnapshotFormatCustomizationPayload.serializer().descriptor

    override fun serialize(encoder: Encoder, value: FormatCustomization) {
        encoder.encodeSerializableValue(
            SnapshotFormatCustomizationPayload.serializer(),
            SnapshotFormatCustomizationPayload.capture(value),
        )
    }

    override fun deserialize(decoder: Decoder): FormatCustomization =
        decoder.decodeSerializableValue(SnapshotFormatCustomizationPayload.serializer()).restore()
}

@Serializable
private data class SnapshotFormatCustomizationPayload(
    @SerialName("d") val dateFormat: DateFormatPreference,
    @SerialName("t") val timeFormat: TimeFormatPreference,
    @SerialName("u") val unitPreference: UnitPreference,
    @SerialName("c") val includeAndroidCompatibilityKeys: Boolean,
    @SerialName("l") val includeLegacyAndroidAliases: Boolean,
    @SerialName("n") val includeAndroidNativeFields: Boolean,
    @SerialName("p") val compatibilitySchemaProfile: CompatibilitySchemaProfile,
    @SerialName("f") val frontmatter: SnapshotFrontmatterPayload,
    @SerialName("m") val markdown: SnapshotMarkdownPayload,
) {
    @Suppress("DEPRECATION")
    fun restore(): FormatCustomization = FormatCustomization(
        dateFormat = dateFormat,
        timeFormat = timeFormat,
        unitPreference = unitPreference,
        includeAndroidCompatibilityKeys = includeAndroidCompatibilityKeys,
        includeLegacyAndroidAliases = includeLegacyAndroidAliases,
        includeAndroidNativeFields = includeAndroidNativeFields,
        compatibilitySchemaProfile = compatibilitySchemaProfile,
        frontmatterConfig = frontmatter.restore(),
        markdownTemplate = markdown.restore(),
    )

    companion object {
        @Suppress("DEPRECATION")
        fun capture(value: FormatCustomization): SnapshotFormatCustomizationPayload =
            SnapshotFormatCustomizationPayload(
                dateFormat = value.dateFormat,
                timeFormat = value.timeFormat,
                unitPreference = value.unitPreference,
                includeAndroidCompatibilityKeys = value.includeAndroidCompatibilityKeys,
                includeLegacyAndroidAliases = value.includeLegacyAndroidAliases,
                includeAndroidNativeFields = value.includeAndroidNativeFields,
                compatibilitySchemaProfile = value.compatibilitySchemaProfile,
                frontmatter = SnapshotFrontmatterPayload.capture(value.frontmatterConfig),
                markdown = SnapshotMarkdownPayload.capture(value.markdownTemplate),
            )
    }
}

@Serializable
private data class SnapshotFrontmatterPayload(
    @SerialName("o") val fieldOrder: List<String>,
    @SerialName("k") val customKeysByIndex: Map<String, String>,
    @SerialName("x") val disabledIndices: Set<Int>,
    @SerialName("c") val customFields: Map<String, String>,
    @SerialName("p") val placeholderFields: List<String>,
    @SerialName("d") val includeDate: Boolean,
    @SerialName("t") val includeType: Boolean,
    @SerialName("D") val customDateKey: String,
    @SerialName("T") val customTypeKey: String,
    @SerialName("v") val customTypeValue: String,
    @SerialName("s") val keyStyle: FrontmatterKeyStyle,
) {
    fun restore(): FrontmatterConfiguration = FrontmatterConfiguration(
        fields = fieldOrder.mapIndexed { index, originalKey ->
            CustomFrontmatterField(
                originalKey = originalKey,
                customKey = customKeysByIndex[index.toString()] ?: originalKey,
                isEnabled = index !in disabledIndices,
            )
        },
        customFields = customFields.toMap(),
        placeholderFields = placeholderFields.toList(),
        includeDate = includeDate,
        includeType = includeType,
        customDateKey = customDateKey,
        customTypeKey = customTypeKey,
        customTypeValue = customTypeValue,
        keyStyle = keyStyle,
    )

    companion object {
        fun capture(value: FrontmatterConfiguration): SnapshotFrontmatterPayload =
            SnapshotFrontmatterPayload(
                fieldOrder = value.fields.map(CustomFrontmatterField::originalKey),
                customKeysByIndex = value.fields.mapIndexedNotNull { index, field ->
                    field.customKey.takeIf { it != field.originalKey }
                        ?.let { index.toString() to it }
                }.toMap(),
                disabledIndices = value.fields.mapIndexedNotNull { index, field ->
                    index.takeUnless { field.isEnabled }
                }.toSet(),
                customFields = value.customFields.toMap(),
                placeholderFields = value.placeholderFields.toList(),
                includeDate = value.includeDate,
                includeType = value.includeType,
                customDateKey = value.customDateKey,
                customTypeKey = value.customTypeKey,
                customTypeValue = value.customTypeValue,
                keyStyle = value.keyStyle,
            )
    }
}

@Serializable
private data class SnapshotMarkdownPayload(
    @SerialName("s") val style: MarkdownTemplateStyle,
    @SerialName("t") val customTemplate: String,
    @SerialName("h") val sectionHeaderLevel: Int,
    @SerialName("e") val useEmoji: Boolean,
    @SerialName("i") val includeSummary: Boolean,
    @SerialName("b") val bulletStyle: BulletStyle,
) {
    fun restore(): MarkdownTemplateConfig = MarkdownTemplateConfig(
        style = style,
        customTemplate = customTemplate,
        sectionHeaderLevel = sectionHeaderLevel,
        useEmoji = useEmoji,
        includeSummary = includeSummary,
        bulletStyle = bulletStyle,
    )

    companion object {
        fun capture(value: MarkdownTemplateConfig): SnapshotMarkdownPayload =
            SnapshotMarkdownPayload(
                style = value.style,
                customTemplate = value.customTemplate,
                sectionHeaderLevel = value.sectionHeaderLevel,
                useEmoji = value.useEmoji,
                includeSummary = value.includeSummary,
                bulletStyle = value.bulletStyle,
            )
    }
}

/** Strict, bounded, deterministic JSON codec for accepted scheduled-export settings. */
object AndroidExportSettingsSnapshotCodec {
    const val MAX_CANONICAL_JSON_BYTES: Int = 32 * 1024

    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
        prettyPrint = false
    }

    fun encodeCanonical(snapshot: AndroidExportSettingsSnapshot): String {
        if (!isStructurallyValid(snapshot)) {
            throw AndroidExportSettingsSnapshotException(
                AndroidExportSettingsSnapshotError.INVALID_STRUCTURE,
            )
        }
        val normalized = snapshot.immutableDeepCopy()
        val canonical = canonicalize(
            json.parseToJsonElement(json.encodeToString(normalized)),
        ).toString()
        if (canonical.toByteArray(StandardCharsets.UTF_8).size > MAX_CANONICAL_JSON_BYTES) {
            throw AndroidExportSettingsSnapshotException(
                AndroidExportSettingsSnapshotError.SIZE_LIMIT_EXCEEDED,
            )
        }
        return canonical
    }

    /** Returns null for missing, corrupt, non-canonical, oversized, or inconsistent metadata. */
    fun decodeOrNull(raw: String?): AndroidExportSettingsSnapshot? {
        if (
            raw.isNullOrEmpty() ||
            raw.toByteArray(StandardCharsets.UTF_8).size > MAX_CANONICAL_JSON_BYTES
        ) return null

        return try {
            val decoded = json.decodeFromJsonElement(
                AndroidExportSettingsSnapshot.serializer(),
                json.parseToJsonElement(raw).jsonObject,
            ).immutableDeepCopy()
            if (!isStructurallyValid(decoded)) return null
            if (encodeCanonical(decoded) != raw) return null
            decoded
        } catch (_: Exception) {
            null
        }
    }

    fun decode(raw: String): AndroidExportSettingsSnapshot = decodeOrNull(raw)
        ?: throw AndroidExportSettingsSnapshotException(
            AndroidExportSettingsSnapshotError.INVALID_CANONICAL_JSON,
        )

    fun isStructurallyValid(snapshot: AndroidExportSettingsSnapshot): Boolean = runCatching {
        if (snapshot.version != AndroidExportSettingsSnapshot.CURRENT_VERSION) return false
        if (snapshot.ianaTimeZone.length > MAX_TIME_ZONE_CHARACTERS) return false
        if (ZoneId.of(snapshot.ianaTimeZone).id != snapshot.ianaTimeZone) return false
        if (snapshot.rawSnapshot.pageSize !in RawSnapshotSettings.MIN_PAGE_SIZE..RawSnapshotSettings.MAX_PAGE_SIZE) {
            return false
        }
        if (snapshot.exportProfile != snapshot.expectedOperationProfile()) return false
        if (snapshot.exportMode == ExportMode.RAW_SNAPSHOT && snapshot.enginePin != null) return false

        val pin = snapshot.enginePin
        if (pin != null) {
            if (pin.engine == ExportEngineMode.legacy) return false
            if (!ExportEnginePinCodec.isStructurallyValid(pin)) return false
            if (pin.profile != snapshot.exportProfile) return false
            if (pin.ianaTimeZone != snapshot.ianaTimeZone) return false
        }

        when (snapshot.scheduledExportTarget) {
            ExportTarget.DEVICE_FOLDER, ExportTarget.GOOGLE_DRIVE ->
                if (snapshot.apiEndpointIdentitySha256 != null) return false
            ExportTarget.API_ENDPOINT -> if (!snapshot.apiEndpointIdentitySha256.isLowercaseSha256()) return false
        }
        true
    }.getOrDefault(false)

    private fun canonicalize(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(
            element.entries
                .sortedBy(Map.Entry<String, JsonElement>::key)
                .associate { (key, value) -> key to canonicalize(value) },
        )
        is JsonArray -> JsonArray(element.map(::canonicalize))
        else -> element
    }

    private const val MAX_TIME_ZONE_CHARACTERS = 128
}

private fun ExportSettings.expectedScheduledExportProfile(): AndroidExportProfile =
    if (scheduledExportTarget == ExportTarget.API_ENDPOINT) {
        AndroidExportProfile.android_frozen_v4
    } else {
        formatCustomization.compatibilitySchemaProfile.toAndroidExportProfile()
    }

private fun AndroidExportSettingsSnapshot.expectedOperationProfile(): AndroidExportProfile =
    if (scheduledExportTarget == ExportTarget.API_ENDPOINT) {
        AndroidExportProfile.android_frozen_v4
    } else {
        formatCustomization.compatibilitySchemaProfile.toAndroidExportProfile()
    }

private fun CompatibilitySchemaProfile.toAndroidExportProfile(): AndroidExportProfile = when (this) {
    CompatibilitySchemaProfile.IOS_V4_FROZEN -> AndroidExportProfile.android_frozen_v4
    CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> AndroidExportProfile.android_analytical_v5
}

private fun AndroidExportSettingsSnapshot.immutableDeepCopy(): AndroidExportSettingsSnapshot = copy(
    rawSnapshot = rawSnapshot.copy(),
    dataTypes = dataTypes.copy(),
    exportFormats = exportFormats.immutableSortedBy { it.name },
    formatCustomization = formatCustomization.immutableDeepCopy(),
    metricSelection = metricSelection.immutableDeepCopy(),
    dailyNoteInjection = dailyNoteInjection.immutableDeepCopy(),
    individualTracking = individualTracking.immutableDeepCopy(),
)

private fun FormatCustomization.immutableDeepCopy(): FormatCustomization = copy(
    frontmatterConfig = frontmatterConfig.immutableDeepCopy(),
    markdownTemplate = markdownTemplate.immutableDeepCopy(),
)

private fun FrontmatterConfiguration.immutableDeepCopy(): FrontmatterConfiguration = copy(
    fields = Collections.unmodifiableList(fields.map { it.copy() }),
    customFields = Collections.unmodifiableMap(
        LinkedHashMap(customFields.toSortedMap()),
    ),
    placeholderFields = Collections.unmodifiableList(placeholderFields.toList()),
)

private fun MarkdownTemplateConfig.immutableDeepCopy(): MarkdownTemplateConfig = copy()

private fun MetricSelectionState.immutableDeepCopy(): MetricSelectionState = MetricSelectionState(
    enabledMetrics = enabledMetrics.immutableSortedBy { it },
)

private fun DailyNoteInjectionSettings.immutableDeepCopy(): DailyNoteInjectionSettings = copy(
    enabledMetrics = enabledMetrics.immutableSortedBy { it },
)

private fun IndividualTrackingSettings.immutableDeepCopy(): IndividualTrackingSettings = copy(
    enabledMetrics = enabledMetrics.immutableSortedBy { it },
    metricConfigs = Collections.unmodifiableMap(
        LinkedHashMap(
            metricConfigs.toSortedMap().mapValues { (_, config) -> config.copy() },
        ),
    ),
)

private fun <T> Set<T>.immutableSortedBy(selector: (T) -> String): Set<T> =
    Collections.unmodifiableSet(LinkedHashSet(sortedBy(selector)))

private fun String?.isLowercaseSha256(): Boolean =
    this != null && length == 64 && all { it in '0'..'9' || it in 'a'..'f' }
