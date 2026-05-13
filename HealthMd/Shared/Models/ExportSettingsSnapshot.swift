import Foundation

/// Immutable, portable copy of every setting that affects export output.
///
/// iOS sends this snapshot to macOS with a Mac export job. The Mac can then
/// render/write files exactly as iOS would without persisting these choices as
/// Mac-local preferences.
struct ExportSettingsSnapshot: Codable, Equatable {
    var exportFormats: Set<ExportFormat>
    var includeMetadata: Bool
    var groupByCategory: Bool
    var filenameFormat: String
    var folderStructure: String
    var writeMode: WriteMode
    var formatCustomization: FormatCustomizationSnapshot
    var individualTracking: IndividualTrackingSnapshot
    var dailyNoteInjection: DailyNoteInjectionSnapshot
    var includeGranularData: Bool
    var metricSelection: MetricSelectionSnapshot

    static func from(_ settings: AdvancedExportSettings) -> ExportSettingsSnapshot {
        ExportSettingsSnapshot(
            exportFormats: settings.exportFormats,
            includeMetadata: settings.includeMetadata,
            groupByCategory: settings.groupByCategory,
            filenameFormat: settings.filenameFormat,
            folderStructure: settings.folderStructure,
            writeMode: settings.writeMode,
            formatCustomization: .from(settings.formatCustomization),
            individualTracking: .from(settings.individualTracking),
            dailyNoteInjection: .from(settings.dailyNoteInjection),
            includeGranularData: settings.includeGranularData,
            metricSelection: .from(settings.metricSelection)
        )
    }

    /// Builds a temporary `AdvancedExportSettings` object backed by isolated
    /// UserDefaults so applying a received iOS snapshot never mutates the Mac's
    /// persisted export preferences.
    func makeAdvancedExportSettings(
        userDefaults: UserDefaults = ExportSettingsSnapshot.makeTemporaryUserDefaults()
    ) -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: userDefaults)
        apply(to: settings)
        return settings
    }

    func apply(to settings: AdvancedExportSettings) {
        settings.exportFormats = exportFormats
        settings.includeMetadata = includeMetadata
        settings.groupByCategory = groupByCategory
        settings.filenameFormat = filenameFormat
        settings.folderStructure = folderStructure
        settings.writeMode = writeMode
        formatCustomization.apply(to: settings.formatCustomization)
        individualTracking.apply(to: settings.individualTracking)
        dailyNoteInjection.apply(to: settings.dailyNoteInjection)
        settings.includeGranularData = includeGranularData
        metricSelection.apply(to: settings.metricSelection)
    }

    static func makeTemporaryUserDefaults() -> UserDefaults {
        let suiteName = "ExportSettingsSnapshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults for ExportSettingsSnapshot")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

// MARK: - Format Customization Snapshot

struct FormatCustomizationSnapshot: Codable, Equatable {
    var dateFormat: DateFormatPreference
    var timeFormat: TimeFormatPreference
    var unitPreference: UnitPreference
    var frontmatterConfig: FrontmatterConfigurationSnapshot
    var markdownTemplate: MarkdownTemplateConfig

    static func from(_ customization: FormatCustomization) -> FormatCustomizationSnapshot {
        FormatCustomizationSnapshot(
            dateFormat: customization.dateFormat,
            timeFormat: customization.timeFormat,
            unitPreference: customization.unitPreference,
            frontmatterConfig: .from(customization.frontmatterConfig),
            markdownTemplate: customization.markdownTemplate
        )
    }

    func apply(to customization: FormatCustomization) {
        customization.dateFormat = dateFormat
        customization.timeFormat = timeFormat
        customization.unitPreference = unitPreference
        frontmatterConfig.apply(to: customization.frontmatterConfig)
        customization.markdownTemplate = markdownTemplate
    }
}

struct FrontmatterConfigurationSnapshot: Codable, Equatable {
    var fields: [CustomFrontmatterField]
    var customFields: [String: String]
    var placeholderFields: [String]
    var includeDate: Bool
    var includeType: Bool
    var customDateKey: String
    var customTypeKey: String
    var customTypeValue: String
    var keyStyle: FrontmatterKeyStyle

    static func from(_ config: FrontmatterConfiguration) -> FrontmatterConfigurationSnapshot {
        FrontmatterConfigurationSnapshot(
            fields: config.fields,
            customFields: config.customFields,
            placeholderFields: config.placeholderFields,
            includeDate: config.includeDate,
            includeType: config.includeType,
            customDateKey: config.customDateKey,
            customTypeKey: config.customTypeKey,
            customTypeValue: config.customTypeValue,
            keyStyle: config.keyStyle
        )
    }

    func apply(to config: FrontmatterConfiguration) {
        config.fields = fields
        config.customFields = customFields
        config.placeholderFields = placeholderFields
        config.includeDate = includeDate
        config.includeType = includeType
        config.customDateKey = customDateKey
        config.customTypeKey = customTypeKey
        config.customTypeValue = customTypeValue
        config.keyStyle = keyStyle
    }
}

// MARK: - Individual Tracking Snapshot

struct IndividualTrackingSnapshot: Codable, Equatable {
    var globalEnabled: Bool
    var metricConfigs: [String: MetricTrackingConfig]
    var entriesFolder: String
    var useCategoryFolders: Bool
    var filenameTemplate: String

    static func from(_ settings: IndividualTrackingSettings) -> IndividualTrackingSnapshot {
        IndividualTrackingSnapshot(
            globalEnabled: settings.globalEnabled,
            metricConfigs: settings.metricConfigs,
            entriesFolder: settings.entriesFolder,
            useCategoryFolders: settings.useCategoryFolders,
            filenameTemplate: settings.filenameTemplate
        )
    }

    func apply(to settings: IndividualTrackingSettings) {
        settings.globalEnabled = globalEnabled
        settings.metricConfigs = metricConfigs
        settings.entriesFolder = entriesFolder
        settings.useCategoryFolders = useCategoryFolders
        settings.filenameTemplate = filenameTemplate
    }
}

// MARK: - Daily Note Injection Snapshot

struct DailyNoteInjectionSnapshot: Codable, Equatable {
    var enabled: Bool
    var folderPath: String
    var filenamePattern: String
    var createIfMissing: Bool
    var injectMarkdownSections: Bool

    static func from(_ settings: DailyNoteInjectionSettings) -> DailyNoteInjectionSnapshot {
        DailyNoteInjectionSnapshot(
            enabled: settings.enabled,
            folderPath: settings.folderPath,
            filenamePattern: settings.filenamePattern,
            createIfMissing: settings.createIfMissing,
            injectMarkdownSections: settings.injectMarkdownSections
        )
    }

    func apply(to settings: DailyNoteInjectionSettings) {
        settings.enabled = enabled
        settings.folderPath = folderPath
        settings.filenamePattern = filenamePattern
        settings.createIfMissing = createIfMissing
        settings.injectMarkdownSections = injectMarkdownSections
    }
}

// MARK: - Metric Selection Snapshot

struct MetricSelectionSnapshot: Codable, Equatable {
    var enabledMetricIDs: Set<String>
    var enabledCategoryIDs: Set<String>

    static func from(_ selection: MetricSelectionState) -> MetricSelectionSnapshot {
        MetricSelectionSnapshot(
            enabledMetricIDs: selection.enabledMetrics,
            enabledCategoryIDs: selection.enabledCategories
        )
    }

    func apply(to selection: MetricSelectionState) {
        selection.enabledMetrics = enabledMetricIDs
        selection.enabledCategories = enabledCategoryIDs
    }
}
