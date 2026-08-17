package com.healthmd.sharedsetup

import com.healthmd.BuildConfig
import com.healthmd.domain.model.BulletStyle
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.DateFormatPreference
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
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import java.net.URI
import java.util.TreeMap

class SharedSetupMapper(
    private val registry: SharedSetupMetricRegistry = AndroidSharedSetupMetricRegistry(),
) {
    fun export(
        settings: ExportSettings,
        preservedAppleExtension: SharedSetupAppleExtension? = null,
    ): SharedSetupV1 {
        val enabledBindings = settings.metricSelection.enabledMetrics
            .mapNotNull(registry.byAndroidSelectionId::get)
            .sortedBy { it.semanticId }
        val individual = settings.individualTracking.metricConfigs.mapNotNull { (selectionId, config) ->
            registry.byAndroidSelectionId[selectionId]?.let { binding ->
                binding.semanticId to SharedSetupIndividualMetric(config.trackIndividually, config.customFolder)
            }
        }.toMap(TreeMap())
        val endpoint = endpointHint(settings.apiEndpointUrl)
        val customization = settings.formatCustomization
        val frontmatter = customization.frontmatterConfig
        val markdown = customization.markdownTemplate
        val originDialect = if (
            markdown.style == MarkdownTemplateStyle.CUSTOM &&
            templateCompatibilityProblem(
                SharedSetupMarkdown(
                    style = "custom",
                    customText = markdown.customTemplate,
                    headerLevel = markdown.sectionHeaderLevel,
                    useEmoji = markdown.useEmoji,
                    includeSummary = markdown.includeSummary,
                    bulletStyle = markdown.bulletStyle.name.lowercase(),
                    originDialect = "portable",
                )
            ) != null
        ) "android" else "portable"
        return SharedSetupV1(
            schema = SHARED_SETUP_SCHEMA,
            schemaVersion = SHARED_SETUP_VERSION,
            createdBy = SharedSetupCreatedBy("android", BuildConfig.VERSION_NAME),
            metricRegistry = SharedSetupMetricRegistryIdentity(
                schema = "healthmd.metric_registry",
                registryVersion = registry.version,
                registrySha256 = registry.sha256,
            ),
            profile = SharedSetupProfile(
                export = SharedSetupExport(
                    formats = settings.selectedExportFormats.map(::formatWire).sorted(),
                    includeMetadata = settings.includeMetadata,
                    groupByCategory = settings.groupByCategory,
                    filenameTemplate = settings.filenameFormat,
                    folderTemplate = settings.folderStructure,
                    writeMode = settings.writeMode.name.lowercase(),
                    includeGranularData = settings.includeGranularData,
                ),
                metrics = SharedSetupMetrics(enabledBindings.map { it.semanticId }),
                presentation = SharedSetupPresentation(
                    dateFormat = dateWire(customization.dateFormat),
                    timeFormat = timeWire(customization.timeFormat),
                    units = customization.unitPreference.name.lowercase(),
                    frontmatter = SharedSetupFrontmatter(
                        fields = frontmatter.fields.map {
                            SharedSetupFrontmatterField(it.originalKey, it.customKey, it.isEnabled)
                        },
                        customValues = frontmatter.customFields.toSortedMap(),
                        placeholders = frontmatter.placeholderFields,
                        includeDate = frontmatter.includeDate,
                        includeType = frontmatter.includeType,
                        dateKey = frontmatter.customDateKey,
                        typeKey = frontmatter.customTypeKey,
                        typeValue = frontmatter.customTypeValue,
                        keyStyle = if (frontmatter.keyStyle == FrontmatterKeyStyle.SNAKE_CASE) "snake_case" else "camel_case",
                    ),
                    markdown = SharedSetupMarkdown(
                        style = markdown.style.name.lowercase(),
                        customText = markdown.customTemplate,
                        headerLevel = markdown.sectionHeaderLevel,
                        useEmoji = markdown.useEmoji,
                        includeSummary = markdown.includeSummary,
                        bulletStyle = markdown.bulletStyle.name.lowercase(),
                        originDialect = originDialect,
                    ),
                ),
                individualEntries = SharedSetupIndividualEntries(
                    enabled = settings.individualTracking.globalEnabled,
                    metrics = individual,
                    entriesFolder = settings.individualTracking.entriesFolder,
                    organizeByCategory = settings.individualTracking.organizeByCategory,
                    // Always explicit; Android's default differs from Apple's.
                    filenameTemplate = settings.individualTracking.filenameTemplate,
                ),
                dailyNotes = SharedSetupDailyNotes(
                    enabled = settings.dailyNoteInjection.enabled,
                    folder = settings.dailyNoteInjection.folderPath,
                    filenameTemplate = settings.dailyNoteInjection.filenamePattern,
                    // Always explicit; Android's historical default differs from Apple's.
                    createIfMissing = settings.dailyNoteInjection.createIfMissing,
                    injectSections = settings.dailyNoteInjection.injectMarkdownSections,
                ),
                schedule = SharedSetupSchedule(
                    activationRequested = settings.scheduleEnabled,
                    cadence = SharedSetupCadence(settings.scheduleCadenceValue, settings.scheduleCadenceUnit.name.lowercase()),
                    // Always explicit; Android's default time differs from Apple's.
                    localTime = SharedSetupLocalTime(settings.scheduleHour, settings.scheduleMinute),
                    lookbackDays = settings.scheduleLookbackDays,
                    dateWindow = settings.scheduleDateWindow.name.lowercase(),
                    desiredTarget = if (settings.scheduledExportTarget == ExportTarget.API_ENDPOINT) "api_endpoint" else "device_folder",
                ),
                apiEndpoint = endpoint,
            ),
            metricAliases = enabledBindings.map {
                SharedSetupMetricAlias(
                    semanticId = it.semanticId,
                    equivalence = it.equivalence,
                    appleSelectionId = it.appleSelectionId,
                    androidSelectionId = it.androidSelectionId,
                )
            },
            platformExtensions = SharedSetupPlatformExtensions(
                apple = preservedAppleExtension,
                android = SharedSetupAndroidExtension(
                    extensionVersion = 1,
                    export = SharedSetupAndroidExport(
                        compatibilityProfile = if (customization.compatibilitySchemaProfile == CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5) "analytical_v5" else "frozen_v4",
                        includeLegacyAliases = customization.includeLegacyAndroidAliases,
                        includeAndroidNativeFields = customization.includeAndroidNativeFields,
                        subfolder = settings.subfolder,
                        folderOrganization = folderWire(settings.folderOrganization),
                    ),
                ),
            ),
        )
    }

    fun preview(document: SharedSetupV1, current: ExportSettings): SharedSetupPreview {
        val profile = document.profile
        val items = mutableListOf<SharedSetupCompatibilityItem>()
        val selectedIds = profile.metrics.enabledIds.mapNotNull { registry.bySemanticId[it]?.androidSelectionId }.toSet()
        val unavailableMetrics = profile.metrics.enabledIds.filter {
            registry.bySemanticId[it]?.androidSelectionId == null
        }
        if (unavailableMetrics.isNotEmpty()) {
            items += SharedSetupCompatibilityItem(
                SharedSetupCompatibilityStatus.REQUIRES_ACTION,
                "Metrics unavailable",
                "${unavailableMetrics.size} metric(s) are not available on this device and will be skipped; supported selections will still apply.",
            )
        }

        val markdownProblem = templateCompatibilityProblem(profile.presentation.markdown)
        if (markdownProblem != null) {
            items += SharedSetupCompatibilityItem(
                SharedSetupCompatibilityStatus.REQUIRES_ACTION,
                "Template needs review",
                "$markdownProblem Your existing local template will stay unchanged.",
            )
        }

        val appleSchedule = document.platformExtensions.apple?.schedule
        val appleSourceScheduleIsRepresentable = document.createdBy.platform != "apple" || (
            appleSchedule != null && !appleSchedule.todayRefreshRequested &&
                appleSchedule.desiredTarget != "connected_mac"
            )
        val cadence = profile.schedule.cadence
        val cadenceIsExact = cadence.unit in setOf("minutes", "hours", "days", "weeks") &&
            (cadence.unit != "minutes" || cadence.value >= 15)
        val exactSchedule = cadenceIsExact && profile.schedule.lookbackDays <= 30 && appleSourceScheduleIsRepresentable
        if (profile.schedule.activationRequested || !exactSchedule) {
            items += SharedSetupCompatibilityItem(
                SharedSetupCompatibilityStatus.REQUIRES_ACTION,
                "Schedule will remain off",
                if (exactSchedule) {
                    "Review permissions, destination, credentials, and entitlement before enabling it."
                } else {
                    "This schedule cannot be represented exactly on Android and will not be approximated; existing local schedule details remain unchanged."
                },
            )
        }

        val pendingEndpoint = profile.apiEndpoint?.toUrlString()
        profile.apiEndpoint?.let {
            items += SharedSetupCompatibilityItem(
                SharedSetupCompatibilityStatus.REQUIRES_ACTION,
                "API endpoint needs confirmation",
                "${it.host}${it.path}; authentication is not included and existing credentials are not used.",
            )
        }

        val appleUnsupported = document.platformExtensions.apple?.let { apple ->
            apple.export.let {
                it.organizeFormatsIntoFolders || it.archiveFiles || it.includeDataDictionary || it.summaryOnly || it.rollups.isNotEmpty()
            } || apple.dailyNotes.only
        } ?: false
        if (appleUnsupported) {
            items += SharedSetupCompatibilityItem(
                SharedSetupCompatibilityStatus.UNSUPPORTED,
                "Apple-only settings not applied",
                "Archive, roll-up, format-folder, data-dictionary, summary-only, or Daily Notes Only preferences stay unsupported on Android.",
            )
        }
        items += SharedSetupCompatibilityItem(
            SharedSetupCompatibilityStatus.APPLIED,
            "Portable settings",
            "Supported export, naming, units, Daily Notes, and individual-entry settings are ready to apply.",
        )

        val frontmatter = profile.presentation.frontmatter
        val markdown = profile.presentation.markdown
        val unavailableIndividualMetrics = profile.individualEntries.metrics.keys.filter {
            registry.bySemanticId[it]?.androidSelectionId == null
        }
        if (unavailableIndividualMetrics.isNotEmpty()) {
            items += SharedSetupCompatibilityItem(
                SharedSetupCompatibilityStatus.REQUIRES_ACTION,
                "Individual-entry metrics unavailable",
                "${unavailableIndividualMetrics.size} individual-entry metric setting(s) are unavailable and will be skipped.",
            )
        }
        val individualConfigs = profile.individualEntries.metrics.mapNotNull { (semanticId, config) ->
            registry.bySemanticId[semanticId]?.androidSelectionId?.let { it to MetricTrackingConfig(config.enabled, config.customFolder) }
        }.toMap()
        val extension = document.platformExtensions.android?.export
        val candidate = current.copy(
            exportFormats = profile.export.formats.map(::formatFromWire).toSet(),
            exportFormat = profile.export.formats.firstOrNull()?.let(::formatFromWire) ?: current.exportFormat,
            includeMetadata = profile.export.includeMetadata,
            groupByCategory = profile.export.groupByCategory,
            filenameFormat = profile.export.filenameTemplate,
            folderStructure = profile.export.folderTemplate,
            writeMode = WriteMode.valueOf(profile.export.writeMode.uppercase()),
            includeGranularData = profile.export.includeGranularData,
            metricSelection = MetricSelectionState(selectedIds),
            formatCustomization = FormatCustomization(
                dateFormat = dateFromWire(profile.presentation.dateFormat),
                timeFormat = timeFromWire(profile.presentation.timeFormat),
                unitPreference = if (profile.presentation.units == "imperial") UnitPreference.IMPERIAL else UnitPreference.METRIC,
                includeLegacyAndroidAliases = extension?.includeLegacyAliases ?: current.formatCustomization.includeLegacyAndroidAliases,
                includeAndroidNativeFields = extension?.includeAndroidNativeFields ?: current.formatCustomization.includeAndroidNativeFields,
                compatibilitySchemaProfile = extension?.let {
                    if (it.compatibilityProfile == "analytical_v5") CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 else CompatibilitySchemaProfile.IOS_V4_FROZEN
                } ?: current.formatCustomization.compatibilitySchemaProfile,
                frontmatterConfig = FrontmatterConfiguration(
                    fields = frontmatter.fields.map { CustomFrontmatterField(it.sourceKey, it.outputKey, it.enabled) },
                    customFields = frontmatter.customValues,
                    placeholderFields = frontmatter.placeholders,
                    includeDate = frontmatter.includeDate,
                    includeType = frontmatter.includeType,
                    customDateKey = frontmatter.dateKey,
                    customTypeKey = frontmatter.typeKey,
                    customTypeValue = frontmatter.typeValue,
                    keyStyle = if (frontmatter.keyStyle == "camel_case") FrontmatterKeyStyle.CAMEL_CASE else FrontmatterKeyStyle.SNAKE_CASE,
                ),
                markdownTemplate = if (markdownProblem == null) {
                    MarkdownTemplateConfig(
                        style = MarkdownTemplateStyle.valueOf(markdown.style.uppercase()),
                        customTemplate = markdown.customText,
                        sectionHeaderLevel = markdown.headerLevel,
                        useEmoji = markdown.useEmoji,
                        includeSummary = markdown.includeSummary,
                        bulletStyle = BulletStyle.valueOf(markdown.bulletStyle.uppercase()),
                    )
                } else current.formatCustomization.markdownTemplate,
            ),
            dailyNoteInjection = DailyNoteInjectionSettings(
                enabled = profile.dailyNotes.enabled,
                folderPath = profile.dailyNotes.folder,
                filenamePattern = profile.dailyNotes.filenameTemplate,
                createIfMissing = profile.dailyNotes.createIfMissing,
                injectMarkdownSections = profile.dailyNotes.injectSections,
            ),
            individualTracking = IndividualTrackingSettings(
                globalEnabled = profile.individualEntries.enabled,
                enabledMetrics = individualConfigs.filterValues { it.trackIndividually }.keys,
                metricConfigs = individualConfigs,
                entriesFolder = profile.individualEntries.entriesFolder,
                organizeByCategory = profile.individualEntries.organizeByCategory,
                filenameTemplate = profile.individualEntries.filenameTemplate,
            ),
            subfolder = extension?.subfolder ?: current.subfolder,
            folderOrganization = extension?.let { folderFromWire(it.folderOrganization) } ?: current.folderOrganization,
            scheduleEnabled = false,
            scheduleCadenceValue = if (exactSchedule) profile.schedule.cadence.value else current.scheduleCadenceValue,
            scheduleCadenceUnit = if (exactSchedule) ScheduleCadenceUnit.valueOf(profile.schedule.cadence.unit.uppercase()) else current.scheduleCadenceUnit,
            scheduleHour = if (exactSchedule) profile.schedule.localTime.hour else current.scheduleHour,
            scheduleMinute = if (exactSchedule) profile.schedule.localTime.minute else current.scheduleMinute,
            scheduleLookbackDays = if (exactSchedule) profile.schedule.lookbackDays else current.scheduleLookbackDays,
            scheduleDateWindow = if (exactSchedule) ScheduleDateWindow.valueOf(profile.schedule.dateWindow.uppercase()) else current.scheduleDateWindow,
            scheduledExportTarget = if (exactSchedule && profile.schedule.desiredTarget == "api_endpoint") ExportTarget.API_ENDPOINT else if (exactSchedule) ExportTarget.DEVICE_FOLDER else current.scheduledExportTarget,
            // Folder/SAF state is stored outside ExportSettings. The active endpoint and its
            // encrypted credentials are intentionally preserved; only a pending hint is stored.
            apiEndpointUrl = current.apiEndpointUrl,
            pendingScheduledRetryDates = emptyList(),
            pendingScheduledExportRequests = emptyList(),
            executionEnginePin = null,
            executionEngineAuthorityIsFrozen = false,
        )
        val review = SharedSetupReviewSummary(
            formats = profile.export.formats,
            metricCount = profile.metrics.enabledIds.size,
            filenameTemplate = profile.export.filenameTemplate,
            units = profile.presentation.units,
            dailyNotesEnabled = profile.dailyNotes.enabled,
            individualEntriesEnabled = profile.individualEntries.enabled,
            hasCustomContent = frontmatter.customValues.isNotEmpty() || frontmatter.placeholders.isNotEmpty() || markdown.style == "custom",
            scheduleRequested = profile.schedule.activationRequested,
            endpointDescription = profile.apiEndpoint?.let { "${it.host}${it.path}" },
            items = items,
        )
        return SharedSetupPreview(document, current.normalized(), candidate.normalized(), pendingEndpoint, review)
    }

    private fun endpointHint(value: String): SharedSetupApiEndpoint? {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed.any { it == '\r' || it == '\n' }) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (!uri.scheme.equals("https", true) || uri.host.isNullOrBlank()) return null
        val path = uri.path.ifBlank { "/" }
        if ('%' in (uri.rawPath ?: "") || '?' in path || '#' in path) return null
        return SharedSetupApiEndpoint(
            scheme = "https",
            host = uri.host,
            port = uri.port.takeIf { it != -1 },
            path = path,
            queryOmitted = uri.rawQuery != null,
            credentialsRequired = true,
        )
    }

    private fun templateCompatibilityProblem(markdown: SharedSetupMarkdown): String? {
        SharedSetupCodec.templateSyntaxProblem(markdown.customText)?.let { return it }
        val tokens = Regex("\\{\\{([#/]?)([A-Za-z0-9_]+)\\}\\}").findAll(markdown.customText)
        val unsupported = tokens.filter { match ->
            val prefix = match.groupValues[1]
            val name = match.groupValues[2]
            if (prefix.isEmpty()) name !in PORTABLE_TOKENS else name !in PORTABLE_SECTIONS
        }.map { it.groupValues[2] }.toSet()
        return unsupported.takeIf { it.isNotEmpty() }?.let {
            "Unsupported placeholder(s): ${it.sorted().joinToString()}"
        }
    }

    private fun SharedSetupApiEndpoint.toUrlString(): String =
        URI(scheme, null, host, port ?: -1, path, null, null).toASCIIString()

    private fun formatWire(value: ExportFormat): String = when (value) {
        ExportFormat.MARKDOWN -> "markdown"
        ExportFormat.OBSIDIAN_BASES -> "obsidian_bases"
        ExportFormat.JSON -> "json"
        ExportFormat.CSV -> "csv"
    }

    private fun formatFromWire(value: String): ExportFormat = when (value) {
        "markdown" -> ExportFormat.MARKDOWN
        "obsidian_bases" -> ExportFormat.OBSIDIAN_BASES
        "json" -> ExportFormat.JSON
        else -> ExportFormat.CSV
    }

    private fun dateWire(value: DateFormatPreference): String = value.name.lowercase()
    private fun dateFromWire(value: String): DateFormatPreference = DateFormatPreference.valueOf(value.uppercase())
    private fun timeWire(value: TimeFormatPreference): String = value.name.lowercase()
    private fun timeFromWire(value: String): TimeFormatPreference = TimeFormatPreference.valueOf(value.uppercase())
    private fun folderWire(value: FolderOrganization): String = value.name.lowercase()
    private fun folderFromWire(value: String): FolderOrganization = FolderOrganization.valueOf(value.uppercase())

    companion object {
        private val PORTABLE_TOKENS = setOf(
            "date", "metrics", "sleep_metrics", "activity_metrics", "heart_metrics", "vitals_metrics",
            "body_metrics", "nutrition_metrics", "mobility_metrics", "mindfulness_metrics", "workout_list",
        )
        private val PORTABLE_SECTIONS = setOf(
            "sleep", "activity", "heart", "vitals", "body", "nutrition", "mobility", "mindfulness", "workouts",
        )
    }
}
