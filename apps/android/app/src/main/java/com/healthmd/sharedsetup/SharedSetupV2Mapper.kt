package com.healthmd.sharedsetup

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileDateWindow
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import java.net.URI
import java.time.LocalDate
import java.util.TreeMap

/**
 * Pure projection between current ordered Android profile snapshots and Shared Setup v2.
 *
 * Profile UUIDs are used only to join in-memory inputs. They, snapshot JSON, endpoint identities,
 * SAF state, timestamps, zones, runtime work, and engine pins never enter the returned DTO graph.
 */
class SharedSetupV2Mapper(
    private val registry: SharedSetupMetricRegistry = AndroidSharedSetupMetricRegistry(),
) {
    private val codec = SharedSetupV2Codec(registry)

    fun export(
        profiles: List<ExportProfile>,
        activeProfileId: String?,
        schedules: List<ScheduledProfileEntry>,
        appVersion: String,
        preservedAppleExtensionsByProfileId: Map<String, SharedSetupV2AppleExtension> = emptyMap(),
    ): SharedSetupV2 {
        require(profiles.size in 1..SHARED_SETUP_V2_MAX_PROFILES) {
            "Shared Setup v2 requires between 1 and 100 export profiles."
        }
        val trimmedNames = profiles.map { it.name.trim() }
        require(trimmedNames.none(String::isEmpty)) { "Export profile names must not be blank." }
        require(trimmedNames.map(String::lowercase).distinct().size == trimmedNames.size) {
            "Export profile names must be case-insensitively unique."
        }
        val nativeIds = profiles.map { it.id }
        require(nativeIds.distinct().size == nativeIds.size) { "Export profile identities must be unique." }

        val activeIndex = if (activeProfileId == null) {
            0
        } else {
            profiles.indexOfFirst { it.id == activeProfileId }.also { index ->
                require(index >= 0) { "The active export profile is missing." }
            }
        }
        val relevantSchedules = schedules.filter { schedule -> schedule.profileId in nativeIds }
        require(relevantSchedules.groupBy { it.profileId }.values.none { it.size > 1 }) {
            "An export profile has more than one schedule entry."
        }
        val scheduleByNativeId = relevantSchedules.associateBy { it.profileId }

        val mappedProfiles = profiles.mapIndexed { index, profile ->
            val bundleId = SharedSetupV2Codec.bundleIdForIndex(index)
            val snapshot = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
                ?: throw IllegalArgumentException(
                    "The frozen settings for $bundleId are not canonical or structurally valid.",
                )
            mapProfile(
                bundleId = bundleId,
                name = trimmedNames[index],
                profile = profile,
                snapshot = snapshot,
                schedule = scheduleByNativeId[profile.id],
                preservedAppleExtension = preservedAppleExtensionsByProfileId[profile.id],
            )
        }

        val aliasIds = mappedProfiles
            .flatMap { profile ->
                profile.metrics.enabledIds + profile.individualEntries.metrics.keys
            }
            .toSortedSet()
        val aliases = aliasIds.map { semanticId ->
            val binding = registry.bySemanticId[semanticId]
                ?: throw IllegalArgumentException("A mapped semantic metric is absent from the pinned registry.")
            SharedSetupV2MetricAlias(
                semanticId = binding.semanticId,
                equivalence = binding.equivalence,
                appleSelectionId = binding.appleSelectionId,
                androidSelectionId = binding.androidSelectionId,
            )
        }
        val document = SharedSetupV2(
            schema = SHARED_SETUP_SCHEMA,
            schemaVersion = SHARED_SETUP_V2_VERSION,
            createdBy = SharedSetupV2CreatedBy(
                platform = "android",
                appVersion = appVersion,
            ),
            metricRegistry = SharedSetupV2MetricRegistryIdentity(
                schema = "healthmd.metric_registry",
                registryVersion = registry.version,
                registrySha256 = registry.sha256,
            ),
            profiles = mappedProfiles,
            activeProfile = SharedSetupV2Codec.bundleIdForIndex(activeIndex),
            metricAliases = aliases,
        )

        // Validate writer structure, security, and encoded bounds now rather than returning a DTO
        // that can only fail later at a document/share boundary.
        codec.encode(document)
        return document
    }

    /** Pure compatibility analysis and typed intent preservation; this function performs no IO. */
    fun planImport(document: SharedSetupV2): SharedSetupV2ImportPlan {
        // Reuse the complete typed, security, generic-bound, and encoded-size validation. The
        // returned bytes are intentionally discarded; planning remains pure and write-free.
        codec.encode(document)
        val plans = document.profiles.map { profile ->
            val referencedIds = (
                profile.metrics.enabledIds + profile.individualEntries.metrics.keys
                ).toSortedSet()
            val supported = referencedIds.filter { semanticId ->
                registry.bySemanticId[semanticId]?.androidSelectionId != null
            }
            val unavailable = (referencedIds - supported.toSet()).toList()
            val compatibility = mutableListOf(
                SharedSetupV2CompatibilityItem(
                    status = SharedSetupV2CompatibilityStatus.APPLIED,
                    field = "${profile.bundleId}.portable",
                    title = "Portable profile settings",
                    detail = "Supported common settings can be staged without changing local state.",
                ),
            )
            if (unavailable.isNotEmpty()) {
                compatibility += SharedSetupV2CompatibilityItem(
                    status = SharedSetupV2CompatibilityStatus.REQUIRES_ACTION,
                    field = "${profile.bundleId}.metrics",
                    title = "Metrics unavailable on Android",
                    detail = "${unavailable.size} semantic metric setting(s) remain unapplied without alias substitution.",
                )
            }
            profile.platformExtensions.android?.let {
                compatibility += SharedSetupV2CompatibilityItem(
                    status = SharedSetupV2CompatibilityStatus.APPLIED,
                    field = "${profile.bundleId}.platform_extensions.android",
                    title = "Android settings",
                    detail = "The typed Android export mode and compatibility preferences can be staged exactly.",
                )
            }

            val destinationStatus = when (profile.destination.kind) {
                "connected_mac", "cloud" -> SharedSetupV2CompatibilityStatus.UNSUPPORTED
                else -> SharedSetupV2CompatibilityStatus.REQUIRES_ACTION
            }
            compatibility += SharedSetupV2CompatibilityItem(
                status = destinationStatus,
                field = "${profile.bundleId}.destination",
                title = "Destination remains inert",
                detail = "The ${profile.destination.kind} intent requires explicit local rebinding; no credential or grant is inherited.",
            )

            profile.schedule?.let {
                compatibility += SharedSetupV2CompatibilityItem(
                    status = SharedSetupV2CompatibilityStatus.REQUIRES_ACTION,
                    field = "${profile.bundleId}.schedule",
                    title = "Schedule remains disabled",
                    detail = "Exact cadence intent is retained, but activation requires a separate local confirmation.",
                )
            }

            profile.platformExtensions.apple?.let { apple ->
                val archiveMeaning = apple.export.healthkitSourceArchive
                compatibility += SharedSetupV2CompatibilityItem(
                    status = SharedSetupV2CompatibilityStatus.UNSUPPORTED,
                    field = "${profile.bundleId}.platform_extensions.apple",
                    title = "Apple settings preserved",
                    detail = "The typed Apple extension, including HealthKit archive policy $archiveMeaning, is preserved without Android approximation.",
                )
            }

            SharedSetupV2ProfileImportPlan(
                bundleId = profile.bundleId,
                name = profile.name,
                source = profile,
                supportedMetricIds = supported,
                unavailableMetricIds = unavailable,
                destinationIntent = SharedSetupV2DestinationImportIntent(profile.destination),
                scheduleIntent = profile.schedule?.let(::SharedSetupV2ScheduleImportIntent),
                preservedAppleExtension = profile.platformExtensions.apple,
                compatibility = compatibility,
            )
        }
        return SharedSetupV2ImportPlan(
            source = document,
            profiles = plans,
            activeProfile = document.activeProfile,
        )
    }

    private fun mapProfile(
        bundleId: String,
        name: String,
        profile: ExportProfile,
        snapshot: AndroidExportSettingsSnapshot,
        schedule: ScheduledProfileEntry?,
        preservedAppleExtension: SharedSetupV2AppleExtension?,
    ): SharedSetupV2Profile {
        val enabledIds = snapshot.metricSelection.enabledMetrics
            .map { selectionId -> bindingForAndroidSelection(selectionId, bundleId).semanticId }
            .distinct()
            .sorted()
        val individualMetrics = mapIndividualMetrics(snapshot.individualTracking, bundleId)
        val customization = snapshot.formatCustomization
        val frontmatter = customization.frontmatterConfig
        val markdown = customization.markdownTemplate
        val originDialect = if (
            markdown.style == MarkdownTemplateStyle.CUSTOM &&
            containsAndroidOnlyTemplateMeaning(markdown.customTemplate)
        ) {
            "android"
        } else {
            "portable"
        }

        return SharedSetupV2Profile(
            bundleId = bundleId,
            name = name,
            export = SharedSetupV2Export(
                formats = snapshot.exportFormats.map(::formatWire).distinct().sorted(),
                includeMetadata = snapshot.includeMetadata,
                groupByCategory = snapshot.groupByCategory,
                filenameTemplate = snapshot.filenameFormat,
                folderTemplate = snapshot.folderStructure,
                writeMode = snapshot.writeMode.name.lowercase(),
                // This is only the common selected-series axis. Android raw mode remains solely
                // in the Android extension and never becomes an Apple source-archive policy.
                compatibilityDetail = if (snapshot.includeGranularData) {
                    "selected_time_series"
                } else {
                    "summary"
                },
            ),
            metrics = SharedSetupV2Metrics(enabledIds),
            presentation = SharedSetupV2Presentation(
                dateFormat = dateWire(customization.dateFormat),
                timeFormat = timeWire(customization.timeFormat),
                units = customization.unitPreference.name.lowercase(),
                frontmatter = SharedSetupV2Frontmatter(
                    fields = frontmatter.fields.map { field ->
                        SharedSetupV2FrontmatterField(
                            sourceKey = field.originalKey,
                            outputKey = field.outputKey,
                            enabled = field.isEnabled,
                        )
                    },
                    customValues = frontmatter.customFields.toSortedMap(),
                    placeholders = frontmatter.placeholderFields.toList(),
                    includeDate = frontmatter.includeDate,
                    includeType = frontmatter.includeType,
                    dateKey = frontmatter.customDateKey,
                    typeKey = frontmatter.customTypeKey,
                    typeValue = frontmatter.customTypeValue,
                    keyStyle = if (frontmatter.keyStyle == FrontmatterKeyStyle.SNAKE_CASE) {
                        "snake_case"
                    } else {
                        "camel_case"
                    },
                ),
                markdown = SharedSetupV2Markdown(
                    style = markdown.style.name.lowercase(),
                    customText = markdown.customTemplate,
                    headerLevel = markdown.sectionHeaderLevel,
                    useEmoji = markdown.useEmoji,
                    includeSummary = markdown.includeSummary,
                    bulletStyle = markdown.bulletStyle.name.lowercase(),
                    originDialect = originDialect,
                ),
            ),
            individualEntries = SharedSetupV2IndividualEntries(
                enabled = snapshot.individualTracking.globalEnabled,
                metrics = individualMetrics,
                entriesFolder = snapshot.individualTracking.entriesFolder,
                organizeByCategory = snapshot.individualTracking.organizeByCategory,
                filenameTemplate = snapshot.individualTracking.filenameTemplate,
            ),
            dailyNotes = SharedSetupV2DailyNotes(
                enabled = snapshot.dailyNoteInjection.enabled,
                folder = snapshot.dailyNoteInjection.folderPath,
                filenameTemplate = snapshot.dailyNoteInjection.filenamePattern,
                createIfMissing = snapshot.dailyNoteInjection.createIfMissing,
                injectSections = snapshot.dailyNoteInjection.injectMarkdownSections,
            ),
            destination = when (profile.target) {
                ExportTarget.DEVICE_FOLDER -> SharedSetupV2Destination(
                    kind = "device_folder",
                    apiEndpoint = null,
                )
                ExportTarget.API_ENDPOINT -> SharedSetupV2Destination(
                    kind = "api_endpoint",
                    apiEndpoint = endpointHint(profile.apiEndpointUrl),
                )
                // Shared Setup v2 has no gateway DestinationKind by contract: exporting a
                // gateway-targeted profile into a setup bundle fails closed instead of
                // fabricating a device-folder or API intent. (Compile-required exhaustiveness
                // branch only; no wire grammar change.)
                ExportTarget.AGENT_DATA_GATEWAY -> throw IllegalArgumentException(
                    "Agent Data gateway destinations are not part of Shared Setup v2 bundles.",
                )
            },
            schedule = schedule?.toSharedSetupV2Schedule(),
            platformExtensions = SharedSetupV2PlatformExtensions(
                apple = preservedAppleExtension,
                android = SharedSetupV2AndroidExtension(
                    extensionVersion = SHARED_SETUP_V2_VERSION,
                    export = SharedSetupV2AndroidExport(
                        mode = when (snapshot.exportMode) {
                            ExportMode.COMPATIBILITY -> "compatibility"
                            ExportMode.RAW_SNAPSHOT -> "raw_snapshot"
                        },
                        legacyPrimaryFormat = formatWire(snapshot.exportFormat),
                        compatibilityProfile = when (customization.compatibilitySchemaProfile) {
                            CompatibilitySchemaProfile.IOS_V4_FROZEN -> "frozen_v4"
                            CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> "analytical_v5"
                        },
                        includeLegacyAliases = customization.includeLegacyAndroidAliases,
                        includeAndroidNativeFields = customization.includeAndroidNativeFields,
                        legacyDataTypes = snapshot.dataTypes.toSharedSetupV2LegacyDataTypes(),
                        subfolder = snapshot.subfolder,
                        folderOrganization = folderWire(snapshot.folderOrganization),
                        rawSnapshot = snapshot.rawSnapshot.toSharedSetupV2RawSnapshot(),
                    ),
                ),
            ),
        )
    }

    private fun mapIndividualMetrics(
        settings: IndividualTrackingSettings,
        bundleId: String,
    ): Map<String, SharedSetupV2IndividualMetric> {
        // Expand the historical blood-pressure keys before registry translation. Explicit modern
        // rows win over an older aggregate row, matching IndividualTrackingSettings.configFor.
        val expanded = linkedMapOf<String, MetricTrackingConfig>()
        settings.metricConfigs.entries
            .sortedBy { (selectionId, _) -> selectionId !in LEGACY_INDIVIDUAL_SELECTION_IDS }
            .forEach { (selectionId, config) ->
                expandedIndividualSelectionIds(selectionId).forEach { expandedId ->
                    expanded[expandedId] = config
                }
            }
        settings.enabledMetrics.sorted().forEach { selectionId ->
            expandedIndividualSelectionIds(selectionId).forEach { expandedId ->
                expanded.putIfAbsent(
                    expandedId,
                    MetricTrackingConfig(trackIndividually = true),
                )
            }
        }

        val mapped = TreeMap<String, SharedSetupV2IndividualMetric>()
        expanded.forEach { (selectionId, config) ->
            val semanticId = bindingForAndroidSelection(selectionId, bundleId).semanticId
            val previous = mapped[semanticId]
            val candidate = SharedSetupV2IndividualMetric(
                enabled = config.trackIndividually,
                customFolder = config.customFolder,
            )
            require(previous == null || previous == candidate) {
                "Two native individual-entry settings map to one semantic metric with different meanings."
            }
            mapped[semanticId] = candidate
        }
        return mapped
    }

    private fun expandedIndividualSelectionIds(selectionId: String): List<String> = when (selectionId) {
        "blood_pressure" -> listOf("bp_systolic", "bp_diastolic")
        "blood_pressure_systolic" -> listOf("bp_systolic")
        "blood_pressure_diastolic" -> listOf("bp_diastolic")
        else -> listOf(selectionId)
    }

    private fun bindingForAndroidSelection(
        selectionId: String,
        bundleId: String,
    ): SharedSetupRegistryBinding = registry.byAndroidSelectionId[selectionId]
        ?: throw IllegalArgumentException(
            "The frozen settings for $bundleId contain an unregistered Android metric selection.",
        )

    private fun ScheduledProfileEntry.toSharedSetupV2Schedule(): SharedSetupV2Schedule =
        SharedSetupV2Schedule(
            activationRequested = isEnabled,
            cadence = SharedSetupV2Cadence(
                value = cadenceValue,
                unit = when (cadenceUnit) {
                    ScheduledProfileCadenceUnit.DAY -> "days"
                    ScheduledProfileCadenceUnit.WEEK -> "weeks"
                    ScheduledProfileCadenceUnit.MONTH -> "months"
                },
                anchorDate = LocalDate.ofEpochDay(anchorEpochDay).toString(),
            ),
            localTime = SharedSetupV2LocalTime(hour = hour, minute = minute),
            weekday = weekdayIso,
            lookbackDays = lookbackDays,
            dateWindow = when (dateWindow) {
                ScheduledProfileDateWindow.PAST_COMPLETE_DAYS -> "past_complete_days"
            },
        )

    private fun DataTypeSelection.toSharedSetupV2LegacyDataTypes(): SharedSetupV2AndroidLegacyDataTypes =
        SharedSetupV2AndroidLegacyDataTypes(
            sleep = sleep,
            activity = activity,
            heart = heart,
            vitals = vitals,
            body = body,
            nutrition = nutrition,
            mobility = mobility,
            reproductiveHealth = reproductiveHealth,
            mindfulness = mindfulness,
            workouts = workouts,
            plannedWorkouts = plannedWorkouts,
            medicalResources = medicalResources,
        )

    private fun RawSnapshotSettings.toSharedSetupV2RawSnapshot(): SharedSetupV2AndroidRawSnapshot =
        SharedSetupV2AndroidRawSnapshot(
            format = when (format) {
                RawExportFormat.JSON -> "json"
                RawExportFormat.NDJSON -> "ndjson"
            },
            scope = when (scope) {
                RawSnapshotScope.SELECTED_RECORD_TYPES -> "selected_record_types"
                RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA -> "all_authorized_supported_data"
            },
            includeExerciseRoutes = includeExerciseRoutes,
            pageSize = pageSize,
        )

    private fun endpointHint(value: String?): SharedSetupV2ApiEndpoint? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty() || trimmed.any { it == '\r' || it == '\n' }) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (
            !uri.scheme.equals("https", ignoreCase = true) ||
            uri.host.isNullOrBlank() ||
            uri.rawUserInfo != null ||
            uri.rawFragment != null ||
            (uri.port != -1 && uri.port !in 1..65_535)
        ) {
            return null
        }
        val rawPath = uri.rawPath.orEmpty()
        if ('%' in rawPath) return null
        val path = uri.path?.ifBlank { "/" } ?: "/"
        if (
            !SharedSetupV2Codec.isSafeHost(uri.host) ||
            !SharedSetupV2Codec.isSafeEndpointPath(path)
        ) {
            return null
        }
        return SharedSetupV2ApiEndpoint(
            scheme = "https",
            host = uri.host,
            port = uri.port.takeIf { it != -1 },
            path = path,
            queryOmitted = uri.rawQuery != null,
            credentialsRequired = true,
        )
    }

    private fun containsAndroidOnlyTemplateMeaning(template: String): Boolean {
        val tokens = Regex("\\{\\{([#/]?)([A-Za-z0-9_]+)\\}\\}").findAll(template)
        return tokens.any { match ->
            val marker = match.groupValues[1]
            val name = match.groupValues[2]
            if (marker.isEmpty()) name !in PORTABLE_TOKENS else name !in PORTABLE_SECTIONS
        }
    }

    private fun formatWire(value: ExportFormat): String = when (value) {
        ExportFormat.MARKDOWN -> "markdown"
        ExportFormat.OBSIDIAN_BASES -> "obsidian_bases"
        ExportFormat.JSON -> "json"
        ExportFormat.CSV -> "csv"
    }

    private fun dateWire(value: DateFormatPreference): String = value.name.lowercase()
    private fun timeWire(value: TimeFormatPreference): String = value.name.lowercase()
    private fun folderWire(value: FolderOrganization): String = value.name.lowercase()

    companion object {
        private val LEGACY_INDIVIDUAL_SELECTION_IDS = setOf(
            "blood_pressure",
            "blood_pressure_systolic",
            "blood_pressure_diastolic",
        )
        private val PORTABLE_TOKENS = setOf(
            "date",
            "metrics",
            "sleep_metrics",
            "activity_metrics",
            "heart_metrics",
            "vitals_metrics",
            "body_metrics",
            "nutrition_metrics",
            "mobility_metrics",
            "mindfulness_metrics",
            "workout_list",
        )
        private val PORTABLE_SECTIONS = setOf(
            "sleep",
            "activity",
            "heart",
            "vitals",
            "body",
            "nutrition",
            "mobility",
            "mindfulness",
            "workouts",
        )
    }
}
