import Foundation
import ExportKit

/// Immutable, portable copy of every setting that affects export output.
///
/// iOS sends this snapshot to macOS with a Mac export job. The generic
/// `portableProfile` owns format/path/write-mode/plugin metadata so the Mac can
/// reconstruct the same ExportKit request shape used by local exports, while
/// Health.md-specific renderer and metric-selection settings remain app-owned.
struct ExportSettingsSnapshot: Codable, Equatable {
    var portableProfile: PortableExportProfileSnapshot
    var includeMetadata: Bool
    var groupByCategory: Bool
    var formatCustomization: FormatCustomizationSnapshot
    var individualTracking: IndividualTrackingSnapshot
    var dailyNoteInjection: DailyNoteInjectionSnapshot
    var includeGranularData: Bool
    var metricSelection: MetricSelectionSnapshot

    var exportFormats: Set<ExportFormat> {
        get { Set(portableProfile.formatIDs.compactMap(ExportFormat.init(exportKitFormatID:))) }
        set { portableProfile.formatIDs = Self.formatIDs(from: newValue) }
    }

    var filenameFormat: String {
        get { portableProfile.aggregateFilenameTemplate }
        set { portableProfile.aggregateFilenameTemplate = newValue }
    }

    var folderStructure: String {
        get { portableProfile.aggregateFolderTemplate }
        set { portableProfile.aggregateFolderTemplate = newValue }
    }

    var writeMode: WriteMode {
        get { WriteMode(exportKitWriteMode: portableProfile.writeMode) }
        set { portableProfile.writeMode = ExportWriteMode(writeMode: newValue) }
    }

    init(
        exportFormats: Set<ExportFormat>,
        includeMetadata: Bool,
        groupByCategory: Bool,
        filenameFormat: String,
        folderStructure: String,
        writeMode: WriteMode,
        formatCustomization: FormatCustomizationSnapshot,
        individualTracking: IndividualTrackingSnapshot,
        dailyNoteInjection: DailyNoteInjectionSnapshot,
        includeGranularData: Bool,
        metricSelection: MetricSelectionSnapshot
    ) {
        self.portableProfile = PortableExportProfileSnapshot(
            formatIDs: Self.formatIDs(from: exportFormats),
            aggregateFolderTemplate: folderStructure,
            aggregateFilenameTemplate: filenameFormat,
            writeMode: ExportWriteMode(writeMode: writeMode),
            enabledPluginIDs: Self.enabledPluginIDs(
                individualTracking: individualTracking,
                dailyNoteInjection: dailyNoteInjection
            )
        )
        self.includeMetadata = includeMetadata
        self.groupByCategory = groupByCategory
        self.formatCustomization = formatCustomization
        self.individualTracking = individualTracking
        self.dailyNoteInjection = dailyNoteInjection
        self.includeGranularData = includeGranularData
        self.metricSelection = metricSelection
    }

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

    private static func formatIDs(from formats: Set<ExportFormat>) -> [String] {
        HealthExportRendererAdapter.sortedFormats(formats).map(\.exportKitFormatID)
    }

    private static func enabledPluginIDs(
        individualTracking: IndividualTrackingSnapshot,
        dailyNoteInjection: DailyNoteInjectionSnapshot
    ) -> [String] {
        var ids: [String] = []
        if dailyNoteInjection.enabled {
            ids.append(HealthExportPluginIDs.dailyNoteInjection)
        }
        if individualTracking.globalEnabled {
            ids.append(HealthExportPluginIDs.individualEntry)
        }
        return ids
    }

    private enum CodingKeys: String, CodingKey {
        case portableProfile
        // Legacy keys are still encoded/decoded for mixed-version local-peer compatibility.
        case exportFormats
        case filenameFormat
        case folderStructure
        case writeMode
        case includeMetadata
        case groupByCategory
        case formatCustomization
        case individualTracking
        case dailyNoteInjection
        case includeGranularData
        case metricSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        includeMetadata = try container.decode(Bool.self, forKey: .includeMetadata)
        groupByCategory = try container.decode(Bool.self, forKey: .groupByCategory)
        formatCustomization = try container.decode(FormatCustomizationSnapshot.self, forKey: .formatCustomization)
        individualTracking = try container.decode(IndividualTrackingSnapshot.self, forKey: .individualTracking)
        dailyNoteInjection = try container.decode(DailyNoteInjectionSnapshot.self, forKey: .dailyNoteInjection)
        includeGranularData = try container.decode(Bool.self, forKey: .includeGranularData)
        metricSelection = try container.decode(MetricSelectionSnapshot.self, forKey: .metricSelection)

        if let portableProfile = try container.decodeIfPresent(PortableExportProfileSnapshot.self, forKey: .portableProfile) {
            self.portableProfile = portableProfile
        } else {
            let legacyFormats = try container.decode(Set<ExportFormat>.self, forKey: .exportFormats)
            let legacyFilenameFormat = try container.decode(String.self, forKey: .filenameFormat)
            let legacyFolderStructure = try container.decode(String.self, forKey: .folderStructure)
            let legacyWriteMode = try container.decode(WriteMode.self, forKey: .writeMode)
            self.portableProfile = PortableExportProfileSnapshot(
                formatIDs: Self.formatIDs(from: legacyFormats),
                aggregateFolderTemplate: legacyFolderStructure,
                aggregateFilenameTemplate: legacyFilenameFormat,
                writeMode: ExportWriteMode(writeMode: legacyWriteMode),
                enabledPluginIDs: Self.enabledPluginIDs(
                    individualTracking: individualTracking,
                    dailyNoteInjection: dailyNoteInjection
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(portableProfile, forKey: .portableProfile)
        try container.encode(HealthExportRendererAdapter.sortedFormats(exportFormats), forKey: .exportFormats)
        try container.encode(filenameFormat, forKey: .filenameFormat)
        try container.encode(folderStructure, forKey: .folderStructure)
        try container.encode(writeMode, forKey: .writeMode)
        try container.encode(includeMetadata, forKey: .includeMetadata)
        try container.encode(groupByCategory, forKey: .groupByCategory)
        try container.encode(formatCustomization, forKey: .formatCustomization)
        try container.encode(individualTracking, forKey: .individualTracking)
        try container.encode(dailyNoteInjection, forKey: .dailyNoteInjection)
        try container.encode(includeGranularData, forKey: .includeGranularData)
        try container.encode(metricSelection, forKey: .metricSelection)
    }
}

private extension ExportWriteMode {
    init(writeMode: WriteMode) {
        switch writeMode {
        case .overwrite:
            self = .overwrite
        case .append:
            self = .append
        case .update:
            self = .update
        }
    }
}

private extension WriteMode {
    init(exportKitWriteMode: ExportWriteMode) {
        switch exportKitWriteMode {
        case .overwrite:
            self = .overwrite
        case .append:
            self = .append
        case .update:
            self = .update
        }
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
