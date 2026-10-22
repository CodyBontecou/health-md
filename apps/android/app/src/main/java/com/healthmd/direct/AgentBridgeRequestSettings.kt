package com.healthmd.direct

import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.*
import com.healthmd.domain.registry.HealthMdCoreRegistryAdapter
import com.healthmd.rawexport.ExportMode
import com.healthmd.sharedsetup.ANDROID_SHARED_SETUP_ALIASES
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Collections
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Pinned configuration evidence, never a native permission, stored grant or approval. */
internal class AgentBridgeRequestSettingsCatalog(
    registry: CoreMetricRegistrySnapshot,
    availableNativeMetricIds: Set<String>,
    val revision: Int,
) {
    val registrySha256: String = registry.registrySha256
    val configurationSha256: String
    internal val metrics: Map<String, AgentBridgeRequestSettingsMetric>

    init {
        if (revision < 1) fail(AgentBridgeErrorCode.INVALID_REQUEST)
        // The real frozen native catalog validates profile, count, IDs, categories and units.
        val definitions = try {
            HealthMdCoreRegistryAdapter.definitions(registry)
        } catch (_: IllegalArgumentException) {
            fail(AgentBridgeErrorCode.BINDING_CHANGED)
        } catch (_: IllegalStateException) {
            fail(AgentBridgeErrorCode.BINDING_CHANGED)
        }
        if (registry.profileId != "android_frozen_v4" || definitions != HealthMetrics.allMetrics) {
            fail(AgentBridgeErrorCode.BINDING_CHANGED)
        }
        val reducers = mapOf(
            "steps" to "sum", "heart_rate_avg" to "average", "heart_rate_min" to "minimum",
            "heart_rate_max" to "maximum", "resting_heart_rate" to "latest", "android.hrv_rmssd" to "latest",
        )
        val resolved = linkedMapOf<String, AgentBridgeRequestSettingsMetric>()
        for (metric in registry.metrics.filter { it.semanticId in reducers }) {
            val alias = ANDROID_SHARED_SETUP_ALIASES[metric.semanticId]
            if (alias?.androidSelectionId != metric.selectionId || metric.sourceAggregation != reducers[metric.semanticId] ||
                metric.archiveOnly || metric.kind != "captured" || metric.sourceSelector != metric.selectionId ||
                resolved.containsKey(metric.semanticId)
            ) fail(AgentBridgeErrorCode.BINDING_CHANGED)
            val recordType = when (metric.selectionId) {
                "steps" -> StepsRecord::class.java.name
                "avg_hr", "min_hr", "max_hr" -> HeartRateRecord::class.java.name
                "resting_hr" -> RestingHeartRateRecord::class.java.name
                "hrv" -> HeartRateVariabilityRmssdRecord::class.java.name
                else -> fail(AgentBridgeErrorCode.BINDING_CHANGED)
            }
            if (metric.selectionId in availableNativeMetricIds) {
                resolved[metric.semanticId] = AgentBridgeRequestSettingsMetric(
                    metric.semanticId, metric.selectionId, metric.categoryId, recordType,
                    metric.sourceSelector, metric.sourceAggregation, metric.unit,
                )
            }
        }
        if (!registry.metrics.map { it.selectionId }.toSet().containsAll(availableNativeMetricIds)) {
            fail(AgentBridgeErrorCode.BINDING_CHANGED)
        }
        // Configuration identity including unselected availability, not stored permission evidence.
        val identity = listOf(registry.registrySha256, revision.toString()) + availableNativeMetricIds.sorted()
        configurationSha256 = AgentBridgeCodec.sha256(Json.encodeToString(identity).encodeToByteArray())
        metrics = Collections.unmodifiableMap(resolved)
    }
}

@kotlinx.serialization.Serializable
internal data class AgentBridgeRequestSettingsMetric(
    val semanticId: String,
    val nativeMetricId: String,
    val nativeCategoryId: String,
    val nativeRecordType: String,
    val sourceSelector: String,
    val sourceReducer: String,
    val canonicalUnit: String,
)

/** Trusted native adapter inputs only. No implicit repository/store/active-profile lookup. */
internal data class AgentBridgeRequestSettingsSnapshot(val revision: Int, val settings: ExportSettings)
internal data class AgentBridgeRequestSettingsProfile(
    val profileId: String,
    val snapshot: AgentBridgeRequestSettingsSnapshot,
    val executionBlocked: Boolean,
)
internal data class AgentBridgeRequestSettingsInputs(
    val catalog: AgentBridgeRequestSettingsCatalog,
    val savedDevice: AgentBridgeRequestSettingsSnapshot?,
    val profiles: List<AgentBridgeRequestSettingsProfile>,
)

@kotlinx.serialization.Serializable
internal enum class AgentBridgeRequestSettingsOrigin { REQUEST, SAVED_DEVICE_SETTINGS, PROFILE }

/** Independently versioned private resolution material, not a journal/plan/approval or authority.
 * The frozen native output JSON contains no API target, credentials, schedules or endpoint identity.
 * Future native journals must separately bind stored authorization, approvals and these revisions. */
@kotlinx.serialization.Serializable
internal class AgentBridgeRequestSettingsResolution internal constructor(
    val version: Int,
    val intentSha256: String,
    val peer: AgentBridgePeer,
    val destination: AgentBridgeDestination,
    val capabilityRevision: Int,
    val catalogSha256: String,
    val registrySha256: String,
    val settingsOrigin: AgentBridgeRequestSettingsOrigin,
    val settingsRevision: Int?,
    val profileId: String?,
    val resolvedAtEpochSecond: Long,
    val dates: AgentBridgeDates,
    val calendarTimezone: String,
    private val frozenRequestedDays: List<String>,
    private val frozenPredictedRelativePaths: List<String>,
    private val frozenSelection: List<AgentBridgeRequestSettingsMetric>,
    private val nativeSettingsJson: String,
) {
    val requestedDays: List<String> get() = frozenRequestedDays.toList()
    val predictedRelativePaths: List<String> get() = frozenPredictedRelativePaths.toList()
    val selection: List<AgentBridgeRequestSettingsMetric> get() = frozenSelection.toList()

    internal fun configurationEquals(other: AgentBridgeRequestSettingsResolution): Boolean =
        version == other.version && intentSha256 == other.intentSha256 && peer == other.peer &&
            destination == other.destination && capabilityRevision == other.capabilityRevision &&
            catalogSha256 == other.catalogSha256 && registrySha256 == other.registrySha256 && settingsOrigin == other.settingsOrigin &&
            settingsRevision == other.settingsRevision && profileId == other.profileId &&
            resolvedAtEpochSecond == other.resolvedAtEpochSecond && dates == other.dates &&
            calendarTimezone == other.calendarTimezone && frozenRequestedDays == other.frozenRequestedDays &&
            frozenPredictedRelativePaths == other.frozenPredictedRelativePaths && frozenSelection == other.frozenSelection &&
            nativeSettingsJson == other.nativeSettingsJson

    /** Renderer adapter only: no capture, store, preferences, quota, grant, wake or delivery work. */
    fun exporterSettings(): ExportSettings {
        if (version != 1) fail(AgentBridgeErrorCode.INVALID_REQUEST)
        val snapshot = try {
            AndroidExportSettingsSnapshotCodec.decode(nativeSettingsJson)
        } catch (_: IllegalArgumentException) {
            fail(AgentBridgeErrorCode.INVALID_REQUEST)
        }
        // A new blank value, not current settings: restore cannot inherit installation/API plumbing.
        return snapshot.restoreOnto(ExportSettings()).copy(
            executionEnginePin = null,
            executionEngineAuthorityIsFrozen = true,
        )
    }
}

/** Planning-only return seam. No new fields are added to persisted private resolution v1. */
internal data class AgentBridgeRequestSettingsOutputResolution(
    val effectiveOutput: AgentBridgeOutputSettings,
    val resolution: AgentBridgeRequestSettingsResolution,
)

/** Bounded production summary/no-archive loose-JSON settings adapter. Unsupported dialects reject.
 * Codec digests and catalog availability are data only. Native stored authorization/approval,
 * readiness, resume revalidation and journaled execution remain separate mandatory gates. */
internal object AgentBridgeRequestSettingsResolver {
    fun resolve(
        request: AgentBridgeGeneratedIntent,
        inputs: AgentBridgeRequestSettingsInputs,
        clock: Clock,
    ): AgentBridgeRequestSettingsResolution = resolveWithOutput(request, inputs, clock).resolution

    fun resolveWithOutput(
        request: AgentBridgeGeneratedIntent,
        inputs: AgentBridgeRequestSettingsInputs,
        clock: Clock,
    ): AgentBridgeRequestSettingsOutputResolution {
        // Recheck constructors and copy caller-owned collections with the integrated strict codec.
        val bytes = AgentBridgeCodec.encode(request)
        val intent = AgentBridgeCodec.decode(bytes) as AgentBridgeGeneratedIntent
        if (intent.peer.platform != AgentBridgePlatform.ANDROID) fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val capture = intent.captureScope
        val requested = capture.selection
        if (requested.metricIds.isEmpty() || requested.categoryIds.isNotEmpty() || requested.allMetrics ||
            requested.sourceIds != listOf("health_connect") || requested.providerIds.isNotEmpty() ||
            capture.compatibilityDetail != AgentBridgeCompatibilityDetail.SUMMARY || capture.nativeArchive !is AgentBridgeArchiveNone
        ) fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val selection = requested.metricIds.map { inputs.catalog.metrics[it] ?: fail(AgentBridgeErrorCode.UNSUPPORTED_METRIC) }

        val origin: AgentBridgeRequestSettingsOrigin
        val revision: Int?
        val profileId: String?
        val output = when (val policy = intent.settingsPolicy) {
            is AgentBridgeSettingsPolicyExplicit -> {
                origin = AgentBridgeRequestSettingsOrigin.REQUEST; revision = null; profileId = null
                policy.settings
            }
            is AgentBridgeSettingsPolicySavedDeviceSettings -> {
                val snapshot = inputs.savedDevice ?: fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
                checkRevision(snapshot.revision, policy.expectedRevision)
                origin = AgentBridgeRequestSettingsOrigin.SAVED_DEVICE_SETTINGS; revision = snapshot.revision; profileId = null
                outputSettings(snapshot.settings)
            }
            is AgentBridgeSettingsPolicyProfile -> {
                val profile = inputs.profiles.singleOrNull { it.profileId == policy.profileId }
                    ?: fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
                checkRevision(profile.snapshot.revision, policy.expectedRevision)
                if (profile.executionBlocked) fail(AgentBridgeErrorCode.NATIVE_REBIND_REQUIRED)
                origin = AgentBridgeRequestSettingsOrigin.PROFILE; revision = profile.snapshot.revision; profileId = policy.profileId
                outputSettings(profile.snapshot.settings)
            }
        }
        validateOutput(output)
        // Validate supplied private output with the same grammar as explicit wire settings.
        AgentBridgeCodec.encode(intent.copy(settingsPolicy = AgentBridgeSettingsPolicyExplicit(output, "explicit")))
        val dates = AgentBridgeValidation.resolveDates(intent.dates, intent.calendarTimezone)
        val paths = AgentBridgeValidation.predictedPaths(intent, output)
        val days = requestedDays(dates, ZoneId.of(intent.calendarTimezone))
        val settings = settings(output, selection)
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, null, ZoneId.of(intent.calendarTimezone))
        val frozenJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
        return AgentBridgeRequestSettingsOutputResolution(output, AgentBridgeRequestSettingsResolution(
            1, AgentBridgeCodec.sha256(bytes), intent.peer, intent.destination, inputs.catalog.revision,
            inputs.catalog.configurationSha256, inputs.catalog.registrySha256, origin, revision, profileId, clock.instant().epochSecond,
            dates, intent.calendarTimezone, days.toList(), paths.toList(), selection.toList(), frozenJson,
        ))
    }

    /** Configuration-only comparison, not stored authority, approval, expiry or journal validation.
     * The candidate is never returned as replacement execution material; reuse the original value. */
    fun validateForReuse(
        frozen: AgentBridgeRequestSettingsResolution,
        intent: AgentBridgeGeneratedIntent,
        inputs: AgentBridgeRequestSettingsInputs,
    ) {
        if (frozen.version != 1) fail(AgentBridgeErrorCode.INVALID_REQUEST)
        val clock = runCatching {
            Clock.fixed(java.time.Instant.ofEpochSecond(frozen.resolvedAtEpochSecond), ZoneId.of("UTC"))
        }.getOrElse { fail(AgentBridgeErrorCode.INVALID_REQUEST) }
        val candidate = resolve(intent, inputs, clock)
        if (!candidate.configurationEquals(frozen)) fail(AgentBridgeErrorCode.BINDING_CHANGED)
    }

    private fun checkRevision(actual: Int, expected: Int) {
        if (actual < 1 || actual != expected) fail(AgentBridgeErrorCode.REVISION_CONFLICT)
    }

    private fun validateOutput(output: AgentBridgeOutputSettings) {
        val p = output.presentation
        if (output.formats != listOf(AgentBridgeFormat.JSON) || output.outputProfile != AgentBridgeOutputProfile.ANDROID_FROZEN_V4 ||
            output.writeMode != AgentBridgeWriteMode.OVERWRITE || p.displayUnits != AgentBridgePresentationDisplayUnits.METRIC ||
            p.machineUnits != "canonical" || p.locale != "en-US" || !p.includeMetadata || !p.groupByCategory ||
            p.frontmatter != AgentBridgeFrontmatter(emptyList(), emptyList(), false, true) ||
            p.markdown != AgentBridgeMarkdown("", emptyList(), AgentBridgeMarkdownStyle.LISTS) ||
            output.individualEntries != AgentBridgeIndividualEntries(false, false, "{metric}-{date}", "", emptyList()) ||
            output.dailyNotes != AgentBridgeDailyNotes(false, false, "{date}", "", false, emptyList()) ||
            output.packaging !is AgentBridgePackagingLooseFiles || output.dictionary !is AgentBridgeDictionaryNone
        ) fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        // Shipped native aggregate subfolders are literal; date expansion there is not implemented.
        if ('{' in output.subfolder || '}' in output.subfolder ||
            listOf(output.subfolder, output.folderTemplate, output.filenameTemplate).any { path -> path.any { it.code >= 128 } }
        ) fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
    }

    private fun settings(output: AgentBridgeOutputSettings, selection: List<AgentBridgeRequestSettingsMetric>): ExportSettings {
        val metricSelection = MetricSelectionState(selection.map { it.nativeMetricId }.toSet())
        return ExportSettings(
            exportMode = ExportMode.COMPATIBILITY,
            rawSnapshot = RawSnapshotSettings(includeExerciseRoutes = false),
            dataTypes = metricSelection.toDataTypeSelection(),
            exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
            includeMetadata = true, groupByCategory = true, filenameFormat = output.filenameTemplate,
            folderStructure = output.folderTemplate, writeMode = WriteMode.OVERWRITE,
            formatCustomization = FormatCustomization(
                dateFormat = DateFormatPreference.ISO8601, timeFormat = TimeFormatPreference.HOUR_24,
                unitPreference = UnitPreference.METRIC, includeLegacyAndroidAliases = false,
                includeAndroidNativeFields = false, compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
                frontmatterConfig = FrontmatterConfiguration(fields = emptyList()),
                markdownTemplate = MarkdownTemplateConfig(),
            ),
            metricSelection = metricSelection,
            dailyNoteInjection = DailyNoteInjectionSettings(enabled = false, folderPath = "", filenamePattern = "{date}", createIfMissing = false, injectMarkdownSections = false, enabledMetrics = emptySet()),
            individualTracking = IndividualTrackingSettings(globalEnabled = false, enabledMetrics = emptySet(), metricConfigs = emptyMap(), entriesFolder = "", organizeByCategory = false, filenameTemplate = "{metric}-{date}"),
            includeGranularData = false, exportTarget = ExportTarget.DEVICE_FOLDER,
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER, apiEndpointUrl = "",
            subfolder = output.subfolder, folderOrganization = FolderOrganization.FLAT,
            scheduleEnabled = false, pendingScheduledRetryDates = emptyList(), pendingScheduledExportRequests = emptyList(),
            executionEnginePin = null, executionEngineAuthorityIsFrozen = true,
            executionAPIRecoveryRequired = false, executionAPIRecovery = null,
        )
    }

    private fun outputSettings(native: ExportSettings): AgentBridgeOutputSettings {
        val output = AgentBridgeOutputSettings(
            AgentBridgeDailyNotes(false, false, "{date}", "", false, emptyList()), AgentBridgeDictionaryNone("none"),
            native.filenameFormat, native.folderStructure, listOf(AgentBridgeFormat.JSON),
            AgentBridgeIndividualEntries(false, false, "{metric}-{date}", "", emptyList()),
            AgentBridgeOutputProfile.ANDROID_FROZEN_V4, AgentBridgePackagingLooseFiles("loose_files"),
            AgentBridgePresentation(AgentBridgePresentationDisplayUnits.METRIC, AgentBridgeFrontmatter(emptyList(), emptyList(), false, true), true, true, "en-US", "canonical", AgentBridgeMarkdown("", emptyList(), AgentBridgeMarkdownStyle.LISTS)),
            native.subfolder, AgentBridgeWriteMode.OVERWRITE,
        )
        val baseline = settings(output, emptyList())
        // Request scope overrides native selections/detail. Destination/schedule/raw-archive plumbing
        // is not an output policy and must never be inherited. Every other native output field checks.
        if (native.exportMode != baseline.exportMode || native.exportFormat != baseline.exportFormat ||
            native.exportFormats != baseline.exportFormats || native.includeMetadata != baseline.includeMetadata ||
            native.groupByCategory != baseline.groupByCategory || native.writeMode != baseline.writeMode ||
            native.formatCustomization != baseline.formatCustomization || native.dailyNoteInjection != baseline.dailyNoteInjection ||
            native.individualTracking != baseline.individualTracking || native.folderOrganization != baseline.folderOrganization ||
            native.executionEnginePin != null
        ) fail(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        return output
    }

    private fun requestedDays(dates: AgentBridgeDates, zone: ZoneId): List<String> {
        if (dates is AgentBridgeDatesAllAvailable) return emptyList() // No earliest-date/provider work.
        val range = (dates as AgentBridgeDatesExact).range
        val first = LocalDate.parse(range.startDate)
        val count = ChronoUnit.DAYS.between(first, LocalDate.parse(range.endDate)) + 1
        if (count !in 1..4096) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        return (0 until count.toInt()).map {
            val day = first.plusDays(it.toLong())
            if (day.atStartOfDay(zone).toLocalDate() != day) fail(AgentBridgeErrorCode.INVALID_REQUEST)
            day.toString()
        }
    }
}

private fun fail(code: AgentBridgeErrorCode): Nothing = throw AgentBridgeException(code)
