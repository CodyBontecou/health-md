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
    /// iPhone-owned export subfolder appended to the Mac-selected destination root.
    /// Nil preserves compatibility with jobs sent by older iPhone versions.
    var healthSubfolder: String?
    var organizeFormatsIntoFolders: Bool
    var archiveExportFiles: Bool
    var summaryOnlyExport: Bool
    var writeMode: WriteMode
    var formatCustomization: FormatCustomizationSnapshot
    var individualTracking: IndividualTrackingSnapshot
    var dailyNoteInjection: DailyNoteInjectionSnapshot
    var includeGranularData: Bool
    var generateWeeklyRollups: Bool
    var generateMonthlyRollups: Bool
    var generateYearlyRollups: Bool
    var metricSelection: MetricSelectionSnapshot

    enum CodingKeys: String, CodingKey {
        case exportFormats
        case includeMetadata
        case groupByCategory
        case filenameFormat
        case folderStructure
        case healthSubfolder
        case organizeFormatsIntoFolders
        case archiveExportFiles
        case summaryOnlyExport
        case writeMode
        case formatCustomization
        case individualTracking
        case dailyNoteInjection
        case includeGranularData
        case generateWeeklyRollups
        case generateMonthlyRollups
        case generateYearlyRollups
        case metricSelection
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case archiveMarkdownExports
    }

    var dailyNotesOnlyModeEnabled: Bool {
        dailyNoteInjection.enabled && dailyNoteInjection.dailyNotesOnly
    }

    var hasFileDestinationOutput: Bool {
        dailyNotesOnlyModeEnabled || !exportFormats.isEmpty
    }

    init(
        exportFormats: Set<ExportFormat>,
        includeMetadata: Bool,
        groupByCategory: Bool,
        filenameFormat: String,
        folderStructure: String,
        healthSubfolder: String? = nil,
        organizeFormatsIntoFolders: Bool,
        archiveExportFiles: Bool,
        summaryOnlyExport: Bool = false,
        writeMode: WriteMode,
        formatCustomization: FormatCustomizationSnapshot,
        individualTracking: IndividualTrackingSnapshot,
        dailyNoteInjection: DailyNoteInjectionSnapshot,
        includeGranularData: Bool,
        generateWeeklyRollups: Bool,
        generateMonthlyRollups: Bool,
        generateYearlyRollups: Bool,
        metricSelection: MetricSelectionSnapshot
    ) {
        self.exportFormats = exportFormats
        self.includeMetadata = includeMetadata
        self.groupByCategory = groupByCategory
        self.filenameFormat = filenameFormat
        self.folderStructure = folderStructure
        self.healthSubfolder = healthSubfolder
        self.organizeFormatsIntoFolders = organizeFormatsIntoFolders
        self.archiveExportFiles = archiveExportFiles
        self.summaryOnlyExport = summaryOnlyExport
        self.writeMode = writeMode
        self.formatCustomization = formatCustomization
        self.individualTracking = individualTracking
        self.dailyNoteInjection = dailyNoteInjection
        self.includeGranularData = includeGranularData
        self.generateWeeklyRollups = generateWeeklyRollups
        self.generateMonthlyRollups = generateMonthlyRollups
        self.generateYearlyRollups = generateYearlyRollups
        self.metricSelection = metricSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        exportFormats = try container.decode(Set<ExportFormat>.self, forKey: .exportFormats)
        includeMetadata = try container.decode(Bool.self, forKey: .includeMetadata)
        groupByCategory = try container.decode(Bool.self, forKey: .groupByCategory)
        filenameFormat = try container.decode(String.self, forKey: .filenameFormat)
        folderStructure = try container.decode(String.self, forKey: .folderStructure)
        healthSubfolder = try container.decodeIfPresent(String.self, forKey: .healthSubfolder)
        organizeFormatsIntoFolders = try container.decodeIfPresent(Bool.self, forKey: .organizeFormatsIntoFolders) ?? false
        archiveExportFiles = try container.decodeIfPresent(Bool.self, forKey: .archiveExportFiles)
            ?? legacyContainer.decodeIfPresent(Bool.self, forKey: .archiveMarkdownExports)
            ?? false
        summaryOnlyExport = try container.decodeIfPresent(Bool.self, forKey: .summaryOnlyExport) ?? false
        writeMode = try container.decode(WriteMode.self, forKey: .writeMode)
        formatCustomization = try container.decode(FormatCustomizationSnapshot.self, forKey: .formatCustomization)
        individualTracking = try container.decode(IndividualTrackingSnapshot.self, forKey: .individualTracking)
        dailyNoteInjection = try container.decode(DailyNoteInjectionSnapshot.self, forKey: .dailyNoteInjection)
        // Older snapshots predate source-record capture. Missing means the sender
        // supplied summary data only; current snapshots always encode this key.
        includeGranularData = try container.decodeIfPresent(Bool.self, forKey: .includeGranularData) ?? false
        generateWeeklyRollups = try container.decodeIfPresent(Bool.self, forKey: .generateWeeklyRollups) ?? false
        generateMonthlyRollups = try container.decodeIfPresent(Bool.self, forKey: .generateMonthlyRollups) ?? false
        generateYearlyRollups = try container.decodeIfPresent(Bool.self, forKey: .generateYearlyRollups) ?? false
        metricSelection = try container.decode(MetricSelectionSnapshot.self, forKey: .metricSelection)
    }

    static func from(
        _ settings: AdvancedExportSettings,
        healthSubfolder: String? = nil
    ) -> ExportSettingsSnapshot {
        ExportSettingsSnapshot(
            exportFormats: settings.exportFormats,
            includeMetadata: settings.includeMetadata,
            groupByCategory: settings.groupByCategory,
            filenameFormat: settings.filenameFormat,
            folderStructure: settings.folderStructure,
            healthSubfolder: healthSubfolder,
            organizeFormatsIntoFolders: settings.organizeFormatsIntoFolders,
            archiveExportFiles: settings.archiveExportFiles,
            summaryOnlyExport: settings.summaryOnlyExport,
            writeMode: settings.writeMode,
            formatCustomization: .from(settings.formatCustomization),
            individualTracking: .from(settings.individualTracking),
            dailyNoteInjection: .from(settings.dailyNoteInjection),
            includeGranularData: settings.includeGranularData,
            generateWeeklyRollups: settings.generateWeeklyRollups,
            generateMonthlyRollups: settings.generateMonthlyRollups,
            generateYearlyRollups: settings.generateYearlyRollups,
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
        settings.organizeFormatsIntoFolders = organizeFormatsIntoFolders
        settings.archiveExportFiles = archiveExportFiles
        settings.summaryOnlyExport = summaryOnlyExport
        settings.writeMode = writeMode
        formatCustomization.apply(to: settings.formatCustomization)
        individualTracking.apply(to: settings.individualTracking)
        dailyNoteInjection.apply(to: settings.dailyNoteInjection)
        settings.includeGranularData = includeGranularData
        settings.generateWeeklyRollups = generateWeeklyRollups
        settings.generateMonthlyRollups = generateMonthlyRollups
        settings.generateYearlyRollups = generateYearlyRollups
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
    var dailyNotesOnly: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, folderPath, filenamePattern, createIfMissing, injectMarkdownSections, dailyNotesOnly
    }

    init(
        enabled: Bool,
        folderPath: String,
        filenamePattern: String,
        createIfMissing: Bool,
        injectMarkdownSections: Bool,
        dailyNotesOnly: Bool = false
    ) {
        self.enabled = enabled
        self.folderPath = folderPath
        self.filenamePattern = filenamePattern
        self.createIfMissing = createIfMissing
        self.injectMarkdownSections = injectMarkdownSections
        self.dailyNotesOnly = dailyNotesOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath) ?? "Daily"
        filenamePattern = try container.decodeIfPresent(String.self, forKey: .filenamePattern) ?? "{date}"
        createIfMissing = try container.decodeIfPresent(Bool.self, forKey: .createIfMissing) ?? false
        injectMarkdownSections = try container.decodeIfPresent(Bool.self, forKey: .injectMarkdownSections) ?? false
        dailyNotesOnly = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesOnly) ?? false
    }

    static func from(_ settings: DailyNoteInjectionSettings) -> DailyNoteInjectionSnapshot {
        DailyNoteInjectionSnapshot(
            enabled: settings.enabled,
            folderPath: settings.folderPath,
            filenamePattern: settings.filenamePattern,
            createIfMissing: settings.createIfMissing,
            injectMarkdownSections: settings.injectMarkdownSections,
            dailyNotesOnly: settings.dailyNotesOnly
        )
    }

    func apply(to settings: DailyNoteInjectionSettings) {
        settings.enabled = enabled
        settings.folderPath = folderPath
        settings.filenamePattern = filenamePattern
        settings.createIfMissing = createIfMissing
        settings.injectMarkdownSections = injectMarkdownSections
        settings.dailyNotesOnly = dailyNotesOnly
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
