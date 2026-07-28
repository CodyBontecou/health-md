//
//  AdvancedExportSettings.swift
//  Health.md
//
//  Created by Claude on 2026-01-13.
//

import Foundation
import Combine

enum WriteMode: String, CaseIterable, Codable {
    case overwrite = "Overwrite"
    case append = "Append"
    case update = "Update"
    
    var description: String {
        switch self {
        case .overwrite:
            return "Replace existing files with new health data"
        case .append:
            return "Add health data to the end of existing files"
        case .update:
            return "Update app-managed sections while preserving your custom content"
        }
    }
}

enum ExportFormat: String, CaseIterable, Codable {
    case markdown = "Markdown"
    case obsidianBases = "Obsidian Bases"
    case json = "JSON"
    case csv = "CSV"

    var isMarkdownFile: Bool {
        switch self {
        case .markdown, .obsidianBases: return true
        case .json, .csv: return false
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .obsidianBases: return "md"
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    /// Folder name used when exports are organized by file type.
    /// Obsidian Bases are Markdown files, but users distinguish them from
    /// regular notes, so they get their own concise "Bases" folder.
    var formatFolderName: String {
        switch self {
        case .markdown: return "Markdown"
        case .obsidianBases: return "Bases"
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }
}

// MARK: - Format Customization Settings

class FormatCustomization: ObservableObject, Codable {
    @Published var dateFormat: DateFormatPreference
    @Published var timeFormat: TimeFormatPreference
    @Published var unitPreference: UnitPreference
    @Published var frontmatterConfig: FrontmatterConfiguration
    @Published var markdownTemplate: MarkdownTemplateConfig
    
    /// Forwards internal FrontmatterConfiguration changes up through our own objectWillChange,
    /// so any subscriber (e.g. AdvancedExportSettings) that listens to this object will also
    /// react to mutations deep inside frontmatterConfig.
    private var frontmatterCancellable: AnyCancellable?
    
    enum CodingKeys: String, CodingKey {
        case dateFormat, timeFormat, unitPreference, frontmatterConfig, markdownTemplate
    }
    
    init() {
        self.dateFormat = .iso8601
        self.timeFormat = .hour24
        self.unitPreference = .metric
        self.frontmatterConfig = FrontmatterConfiguration()
        self.markdownTemplate = MarkdownTemplateConfig()
        subscribeToFrontmatterConfig()
        #if DEBUG
        LifecycleTracker.trackCreation(of: "FormatCustomization")
        #endif
    }

    deinit {
        #if DEBUG
        LifecycleTracker.trackDeinit(of: "FormatCustomization")
        #endif
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateFormat = try container.decodeIfPresent(DateFormatPreference.self, forKey: .dateFormat) ?? .iso8601
        timeFormat = try container.decodeIfPresent(TimeFormatPreference.self, forKey: .timeFormat) ?? .hour24
        unitPreference = try container.decodeIfPresent(UnitPreference.self, forKey: .unitPreference) ?? .metric
        frontmatterConfig = try container.decodeIfPresent(FrontmatterConfiguration.self, forKey: .frontmatterConfig) ?? FrontmatterConfiguration()
        markdownTemplate = try container.decodeIfPresent(MarkdownTemplateConfig.self, forKey: .markdownTemplate) ?? MarkdownTemplateConfig()
        subscribeToFrontmatterConfig()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateFormat, forKey: .dateFormat)
        try container.encode(timeFormat, forKey: .timeFormat)
        try container.encode(unitPreference, forKey: .unitPreference)
        try container.encode(frontmatterConfig, forKey: .frontmatterConfig)
        try container.encode(markdownTemplate, forKey: .markdownTemplate)
    }
    
    func reset() {
        dateFormat = .iso8601
        timeFormat = .hour24
        unitPreference = .metric
        frontmatterConfig.reset()
        markdownTemplate = MarkdownTemplateConfig()
        // Re-subscribe in case frontmatterConfig was replaced
        subscribeToFrontmatterConfig()
    }
    
    // MARK: - Private
    
    /// Subscribes to frontmatterConfig.objectWillChange and forwards it through our own
    /// objectWillChange. This is necessary because @Published on a class (reference type)
    /// only fires objectWillChange when the reference itself is reassigned — not when the
    /// object's internal @Published properties change. Without this, edits to fields like
    /// keyStyle or individual field toggles would never reach AdvancedExportSettings and
    /// would never be persisted to UserDefaults.
    private func subscribeToFrontmatterConfig() {
        frontmatterCancellable = frontmatterConfig.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
    
    /// Get a configured unit converter
    var unitConverter: UnitConverter {
        UnitConverter(preference: unitPreference)
    }
}

// Legacy DataTypeSelection - compatibility only.
// Runtime export filtering uses MetricSelectionState.
struct DataTypeSelection: Codable {
    var sleep: Bool = true
    var activity: Bool = true
    var heart: Bool = true
    var vitals: Bool = true
    var body: Bool = true
    var nutrition: Bool = true
    var mindfulness: Bool = true
    var mobility: Bool = true
    var hearing: Bool = true
    var reproductiveHealth: Bool = true
    var workouts: Bool = true

    var hasAnySelected: Bool {
        sleep || activity || heart || vitals || body || nutrition ||
        mindfulness || mobility || hearing || reproductiveHealth || workouts
    }

    /// Returns the count of enabled data types
    var enabledCount: Int {
        [sleep, activity, heart, vitals, body, nutrition, mindfulness, mobility, hearing, reproductiveHealth, workouts]
            .filter { $0 }.count
    }

    /// Select all data types
    mutating func selectAll() {
        sleep = true
        activity = true
        heart = true
        vitals = true
        body = true
        nutrition = true
        mindfulness = true
        mobility = true
        hearing = true
        reproductiveHealth = true
        workouts = true
    }

    /// Deselect all data types
    mutating func deselectAll() {
        sleep = false
        activity = false
        heart = false
        vitals = false
        body = false
        nutrition = false
        mindfulness = false
        mobility = false
        hearing = false
        reproductiveHealth = false
        workouts = false
    }

    /// Convert to MetricSelectionState for the new system
    func toMetricSelectionState() -> MetricSelectionState {
        let state = MetricSelectionState()
        state.deselectAll()

        // Map old categories to new metric categories
        if sleep {
            state.toggleCategory(.sleep)
        }
        if activity {
            state.toggleCategory(.activity)
        }
        if heart {
            state.toggleCategory(.heart)
        }
        if vitals {
            state.toggleCategory(.vitals)
            state.toggleCategory(.respiratory)
        }
        if body {
            state.toggleCategory(.bodyMeasurements)
        }
        if nutrition {
            state.toggleCategory(.nutrition)
            state.toggleCategory(.vitamins)
            state.toggleCategory(.minerals)
        }
        if mindfulness {
            state.toggleCategory(.mindfulness)
        }
        if mobility {
            state.toggleCategory(.mobility)
            state.toggleCategory(.cycling)
        }
        if hearing {
            state.toggleCategory(.hearing)
        }
        if reproductiveHealth {
            state.toggleCategory(.reproductiveHealth)
        }
        if workouts {
            state.toggleCategory(.workouts)
        }

        return state
    }
}

/// Runtime output mode for file destinations. The persisted settings remain
/// independent so toggling Daily Notes Only never destroys format, archive,
/// roll-up, or individual-entry preferences.
enum EffectiveFileExportMode: Equatable {
    case standard
    case summaryOnly
    case dailyNotesOnly
}

class AdvancedExportSettings: ObservableObject {
    // Legacy compatibility only (old saved settings + migration source).
    // Export runtime decisions must come from metricSelection.
    @Published var dataTypes: DataTypeSelection {
        didSet { save() }
    }

    // New comprehensive metric selection
    @Published var metricSelection: MetricSelectionState {
        didSet {
            saveMetricSelection()
            subscribeToMetricSelection()
        }
    }

    @Published var exportFormats: Set<ExportFormat> {
        didSet { saveFormats() }
    }

    /// Stable representative format for previews and single-format codepaths.
    /// Returns markdown if selected, else the alphabetically-first selected format,
    /// else markdown as a final fallback.
    var primaryFormat: ExportFormat {
        if exportFormats.contains(.markdown) { return .markdown }
        return exportFormats.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .markdown
    }

    @Published var includeMetadata: Bool {
        didSet { save() }
    }

    @Published var groupByCategory: Bool {
        didSet { save() }
    }

    @Published var filenameFormat: String {
        didSet { save() }
    }

    @Published var folderStructure: String {
        didSet { save() }
    }

    /// When enabled, each aggregate export format is written under a stable
    /// file-type folder (Markdown/, Bases/, JSON/, CSV/) before the optional
    /// date-based folder structure.
    @Published var organizeFormatsIntoFolders: Bool {
        didSet { save() }
    }

    /// When enabled, selected aggregate export formats are written into one ZIP
    /// archive per export run instead of thousands of loose files.
    @Published var archiveExportFiles: Bool {
        didSet { save() }
    }

    /// When enabled with at least one roll-up period, exports write only weekly,
    /// monthly, and/or yearly summary files instead of per-day aggregate records.
    @Published var summaryOnlyExport: Bool {
        didSet { save() }
    }

    @Published var writeMode: WriteMode {
        didSet { save() }
    }

    // Format customization settings
    @Published var formatCustomization: FormatCustomization {
        didSet {
            saveFormatCustomization()
            subscribeToFormatCustomization()
        }
    }
    
    // Individual entry tracking settings
    @Published var individualTracking: IndividualTrackingSettings {
        didSet {
            saveIndividualTracking()
            subscribeToIndividualTracking()
        }
    }

    // Daily note injection settings
    @Published var dailyNoteInjection: DailyNoteInjectionSettings {
        didSet {
            saveDailyNoteInjection()
            subscribeToDailyNoteInjection()
        }
    }

    /// When enabled, exports include canonical lossless HealthKit source records and
    /// detailed series alongside daily summaries. The persisted key and public name
    /// remain unchanged for compatibility with existing settings and integrations.
    @Published var includeGranularData: Bool {
        didSet { save() }
    }

    /// Generate derived weekly summaries from successful daily snapshots in the export run.
    @Published var generateWeeklyRollups: Bool {
        didSet { save() }
    }

    /// Generate derived monthly summaries from successful daily snapshots in the export run.
    @Published var generateMonthlyRollups: Bool {
        didSet { save() }
    }

    /// Generate derived yearly summaries from successful daily snapshots in the export run.
    @Published var generateYearlyRollups: Bool {
        didSet { save() }
    }

    private let userDefaults: UserDefaults
    
    /// Combine subscriptions for observing nested ObservableObject changes
    private var metricSelectionCancellable: AnyCancellable?
    private var individualTrackingCancellable: AnyCancellable?
    private var formatCustomizationCancellable: AnyCancellable?
    private var dailyNoteInjectionCancellable: AnyCancellable?
    private let dataTypesKey = "advancedExportSettings.dataTypes"
    private let metricSelectionKey = "advancedExportSettings.metricSelection"
    private let formatKey = "advancedExportSettings.format"  // legacy single-format key, read once for migration
    private let formatsKey = "advancedExportSettings.formats"
    private let metadataKey = "advancedExportSettings.metadata"
    private let groupByCategoryKey = "advancedExportSettings.groupByCategory"
    private let filenameFormatKey = "advancedExportSettings.filenameFormat"
    private let folderStructureKey = "advancedExportSettings.folderStructure"
    private let organizeFormatsIntoFoldersKey = "advancedExportSettings.organizeFormatsIntoFolders"
    private let archiveExportFilesKey = "advancedExportSettings.archiveExportFiles"
    private let legacyArchiveMarkdownExportsKey = "advancedExportSettings.archiveMarkdownExports"
    private let summaryOnlyExportKey = "advancedExportSettings.summaryOnlyExport"
    private let writeModeKey = "advancedExportSettings.writeMode"
    private let legacyUseRollingDateRangeKey = "advancedExportSettings.useRollingDateRange"
    private let legacyRollingDateRangeDaysKey = "advancedExportSettings.rollingDateRangeDays"
    private let formatCustomizationKey = "advancedExportSettings.formatCustomization"
    private let individualTrackingKey = "advancedExportSettings.individualTracking"
    private let dailyNoteInjectionKey = "advancedExportSettings.dailyNoteInjection"
    private let includeGranularDataKey = "advancedExportSettings.includeGranularData"
    private let generateWeeklyRollupsKey = "advancedExportSettings.generateWeeklyRollups"
    private let generateMonthlyRollupsKey = "advancedExportSettings.generateMonthlyRollups"
    private let generateYearlyRollupsKey = "advancedExportSettings.generateYearlyRollups"
    private let medicationAuthorizationRequestedKey = "healthKit.medicationAuthorizationRequested"
    private let verifiableClinicalRecordsOptInMigrationKey =
        "advancedExportSettings.verifiableClinicalRecordsOptInMigration.v1"

    static let defaultFilenameFormat = "{date}"
    static let defaultFolderStructure = ""  // Empty = flat structure

    /// Request-scoped source calendar used by connected exports. It is never
    /// persisted; local exports continue using the device's current time zone.
    var exportTimeZoneOverride: TimeZone? = nil

    /// Formats a filename using the current format template and a given date
    /// Supported placeholders: {date}, {year}, {YR}, {month}, {day}, {weekday}, {monthName}, {quarter}
    func formatFilename(for date: Date) -> String {
        return applyDatePlaceholders(to: filenameFormat, for: date)
    }

    /// Returns the full filename (with extension) for a given format on a given date.
    /// When BOTH .markdown and .obsidianBases are selected in the same folder,
    /// Obsidian Bases gets a "-bases" suffix so it doesn't collide with the
    /// regular markdown file. If file-type folders are enabled, both files can
    /// safely keep the same base filename because they live in different folders.
    func filename(for date: Date, format: ExportFormat) -> String {
        let base = formatFilename(for: date)
        let needsBasesSuffix = format == .obsidianBases
            && !organizeFormatsIntoFolders
            && exportFormats.contains(.markdown)
            && exportFormats.contains(.obsidianBases)
        let suffix = needsBasesSuffix ? "-bases" : ""
        return "\(base)\(suffix).\(format.fileExtension)"
    }

    /// Formats the folder structure path using the current template and a given date.
    /// Returns nil if folder structure is empty (flat structure) and format folders are disabled.
    /// Supported date placeholders: {date}, {year}, {YR}, {month}, {day}, {weekday}, {monthName}, {quarter}.
    /// When `organizeFormatsIntoFolders` is enabled and a format is supplied, the
    /// path is prefixed with Markdown/, Bases/, JSON/, or CSV/.
    func formatFolderPath(for date: Date, format: ExportFormat? = nil) -> String? {
        var components: [String] = []
        if organizeFormatsIntoFolders, let format {
            components.append(format.formatFolderName)
        }
        if !folderStructure.isEmpty {
            components.append(applyDatePlaceholders(to: folderStructure, for: date))
        }
        let path = components
            .flatMap { folderPathSegments($0) }
            .joined(separator: "/")
        return path.isEmpty ? nil : path
    }

    /// Splits a user-entered folder path into clean relative path segments.
    private func folderPathSegments(_ rawPath: String) -> [String] {
        rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Common method to apply date placeholders to a template string
    private func applyDatePlaceholders(to template: String, for date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = exportTimeZoneOverride ?? .current
        var result = template

        // {date} -> yyyy-MM-dd
        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))

        // {year} -> yyyy
        dateFormatter.dateFormat = "yyyy"
        result = result.replacingOccurrences(of: "{year}", with: dateFormatter.string(from: date))

        // {YR} -> yy
        dateFormatter.dateFormat = "yy"
        result = result.replacingOccurrences(of: "{YR}", with: dateFormatter.string(from: date))

        // {month} -> MM
        dateFormatter.dateFormat = "MM"
        result = result.replacingOccurrences(of: "{month}", with: dateFormatter.string(from: date))

        // {day} -> dd
        dateFormatter.dateFormat = "dd"
        result = result.replacingOccurrences(of: "{day}", with: dateFormatter.string(from: date))

        // {weekday} -> Monday, Tuesday, etc.
        dateFormatter.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{weekday}", with: dateFormatter.string(from: date))

        // {monthName} -> January, February, etc.
        dateFormatter.dateFormat = "MMMM"
        result = result.replacingOccurrences(of: "{monthName}", with: dateFormatter.string(from: date))

        // {quarter} -> Q1, Q2, Q3, Q4
        var calendar = Calendar.current
        calendar.timeZone = exportTimeZoneOverride ?? .current
        let month = calendar.component(.month, from: date)
        let quarter = "Q\((month - 1) / 3 + 1)"
        result = result.replacingOccurrences(of: "{quarter}", with: quarter)

        return result
    }

    /// Reconstructs request-scoped export settings without replaying every
    /// property observer into UserDefaults. The returned object remains mutable,
    /// and later caller mutations persist only to the supplied isolated domain.
    init(snapshot: ExportSettingsSnapshot, userDefaults: UserDefaults) {
        let metricSelection = MetricSelectionState()
        snapshot.metricSelection.apply(to: metricSelection)
        let formatCustomization = FormatCustomization()
        snapshot.formatCustomization.apply(to: formatCustomization)
        let individualTracking = IndividualTrackingSettings()
        snapshot.individualTracking.apply(to: individualTracking)
        let dailyNoteInjection = DailyNoteInjectionSettings()
        snapshot.dailyNoteInjection.apply(to: dailyNoteInjection)

        self.userDefaults = userDefaults
        dataTypes = DataTypeSelection()
        self.metricSelection = metricSelection
        exportFormats = snapshot.exportFormats
        includeMetadata = snapshot.includeMetadata
        groupByCategory = snapshot.groupByCategory
        filenameFormat = snapshot.filenameFormat
        folderStructure = snapshot.folderStructure
        organizeFormatsIntoFolders = snapshot.organizeFormatsIntoFolders
        archiveExportFiles = snapshot.archiveExportFiles
        summaryOnlyExport = snapshot.summaryOnlyExport
        writeMode = snapshot.writeMode
        self.formatCustomization = formatCustomization
        self.individualTracking = individualTracking
        self.dailyNoteInjection = dailyNoteInjection
        includeGranularData = snapshot.includeGranularData
        generateWeeklyRollups = snapshot.generateWeeklyRollups
        generateMonthlyRollups = snapshot.generateMonthlyRollups
        generateYearlyRollups = snapshot.generateYearlyRollups

        subscribeToMetricSelection()
        subscribeToIndividualTracking()
        subscribeToFormatCustomization()
        subscribeToDailyNoteInjection()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        var migratedMetricSelectionFromLegacyDataTypes = false

        // Load data types (legacy)
        let loadedLegacyDataTypes: DataTypeSelection
        if let data = userDefaults.data(forKey: dataTypesKey),
           let decoded = try? JSONDecoder().decode(DataTypeSelection.self, from: data) {
            loadedLegacyDataTypes = decoded
        } else {
            loadedLegacyDataTypes = DataTypeSelection()
        }
        self.dataTypes = loadedLegacyDataTypes

        // Load new metric selection.
        // Migration path: if missing, derive once from legacy dataTypes and persist immediately.
        if let data = userDefaults.data(forKey: metricSelectionKey),
           let decoded = try? JSONDecoder().decode(MetricSelectionState.self, from: data) {
            self.metricSelection = decoded
        } else if userDefaults.object(forKey: dataTypesKey) != nil {
            self.metricSelection = loadedLegacyDataTypes.toMetricSelectionState()
            migratedMetricSelectionFromLegacyDataTypes = true
        } else {
            // First time: use default metric selection
            self.metricSelection = MetricSelectionState()
        }

        // Load formats. New multi-format key wins. Otherwise migrate from the legacy
        // single-format key. Otherwise default to markdown.
        var migratedFormatsFromLegacy = false
        if let data = userDefaults.data(forKey: formatsKey),
           let decoded = try? JSONDecoder().decode([ExportFormat].self, from: data) {
            self.exportFormats = Set(decoded)
        } else if let formatString = userDefaults.string(forKey: formatKey),
                  let format = ExportFormat(rawValue: formatString) {
            self.exportFormats = [format]
            migratedFormatsFromLegacy = true
        } else {
            self.exportFormats = [.markdown]
        }

        // Load metadata option
        self.includeMetadata = userDefaults.bool(forKey: metadataKey)
        if userDefaults.object(forKey: metadataKey) == nil {
            self.includeMetadata = true // Default to true
        }

        // Load group by category option
        self.groupByCategory = userDefaults.bool(forKey: groupByCategoryKey)
        if userDefaults.object(forKey: groupByCategoryKey) == nil {
            self.groupByCategory = true // Default to true
        }

        // Load filename format
        if let savedFormat = userDefaults.string(forKey: filenameFormatKey) {
            self.filenameFormat = savedFormat
        } else {
            self.filenameFormat = Self.defaultFilenameFormat
        }

        // Load folder structure
        if let savedStructure = userDefaults.string(forKey: folderStructureKey) {
            self.folderStructure = savedStructure
        } else {
            self.folderStructure = Self.defaultFolderStructure
        }

        // Load format-folder organization. Defaults off to preserve existing vault paths.
        self.organizeFormatsIntoFolders = userDefaults.bool(forKey: organizeFormatsIntoFoldersKey)

        // Load ZIP archive packaging. Defaults off to preserve existing vault paths.
        if userDefaults.object(forKey: archiveExportFilesKey) != nil {
            self.archiveExportFiles = userDefaults.bool(forKey: archiveExportFilesKey)
        } else {
            self.archiveExportFiles = userDefaults.bool(forKey: legacyArchiveMarkdownExportsKey)
        }

        // Load summary-only mode. Defaults off so existing exports keep writing daily records.
        self.summaryOnlyExport = userDefaults.bool(forKey: summaryOnlyExportKey)

        // Load write mode
        if let savedMode = userDefaults.string(forKey: writeModeKey),
           let mode = WriteMode(rawValue: savedMode) {
            self.writeMode = mode
        } else {
            self.writeMode = .overwrite // Default to overwrite for backwards compatibility
        }

        // Rolling manual date ranges were removed in favor of explicit date range presets.
        // Clear legacy keys so a previously-enabled hidden toggle cannot affect exports.
        userDefaults.removeObject(forKey: legacyUseRollingDateRangeKey)
        userDefaults.removeObject(forKey: legacyRollingDateRangeDaysKey)
        
        // Load format customization
        if let data = userDefaults.data(forKey: formatCustomizationKey),
           let decoded = try? JSONDecoder().decode(FormatCustomization.self, from: data) {
            self.formatCustomization = decoded
        } else {
            self.formatCustomization = FormatCustomization()
        }
        
        // Load individual tracking settings
        if let data = userDefaults.data(forKey: individualTrackingKey),
           let decoded = try? JSONDecoder().decode(IndividualTrackingSettings.self, from: data) {
            self.individualTracking = decoded
        } else {
            self.individualTracking = IndividualTrackingSettings()
        }

        // Load daily note injection settings
        if let data = userDefaults.data(forKey: dailyNoteInjectionKey),
           let decoded = try? JSONDecoder().decode(DailyNoteInjectionSettings.self, from: data) {
            self.dailyNoteInjection = decoded
        } else {
            self.dailyNoteInjection = DailyNoteInjectionSettings()
        }

        // Preserve any explicit legacy choice exactly. A missing key identifies a fresh
        // installation and defaults to lossless source-record capture.
        if userDefaults.object(forKey: includeGranularDataKey) == nil {
            self.includeGranularData = true
        } else {
            self.includeGranularData = userDefaults.bool(forKey: includeGranularDataKey)
        }

        // Load roll-up summary settings (default off to avoid writing derived files unexpectedly)
        self.generateWeeklyRollups = userDefaults.bool(forKey: generateWeeklyRollupsKey)
        self.generateMonthlyRollups = userDefaults.bool(forKey: generateMonthlyRollupsKey)
        self.generateYearlyRollups = userDefaults.bool(forKey: generateYearlyRollupsKey)
        // Medications use a separate per-object HealthKit authorization flow.
        // If a prior build persisted medication metrics by default before that
        // flow was completed, remove them so users opt in explicitly.
        var removedUnauthorizedMedicationMetrics = false
        if !userDefaults.bool(forKey: medicationAuthorizationRequestedKey),
           let medicationMetricIDs = HealthMetrics.byCategory[.medications]?.map(\.id) {
            let medicationIDSet = Set(medicationMetricIDs)
            if !metricSelection.enabledMetrics.isDisjoint(with: medicationIDSet) ||
                metricSelection.enabledCategories.contains(HealthMetricCategory.medications.rawValue) {
                metricSelection.enabledMetrics.subtract(medicationIDSet)
                metricSelection.enabledCategories.remove(HealthMetricCategory.medications.rawValue)
                removedUnauthorizedMedicationMetrics = true
            }
        }

        // Earlier lossless builds could retain Verifiable Clinical Records as a
        // broad selection or workout dependency. Its HealthKit API opens a
        // one-time "Share Once" selector whenever queried, so existing installs
        // must opt in again after the query-planning fix rather than unexpectedly
        // opening that selector during ordinary exports.
        var removedLegacyVerifiableClinicalRecords = false
        if !userDefaults.bool(forKey: verifiableClinicalRecordsOptInMigrationKey) {
            userDefaults.set(true, forKey: verifiableClinicalRecordsOptInMigrationKey)
            if metricSelection.enabledMetrics.remove("verifiable_clinical_records") != nil {
                metricSelection.enabledCategories.remove(HealthMetricCategory.clinicalDocuments.rawValue)
                removedLegacyVerifiableClinicalRecords = true
            }
        }

        // Persist migrated metricSelection immediately so future launches never
        // fall back to legacy dataTypes or reopen one-time selectors implicitly.
        if migratedMetricSelectionFromLegacyDataTypes || removedUnauthorizedMedicationMetrics ||
            removedLegacyVerifiableClinicalRecords {
            saveMetricSelection()
        }

        // Persist migrated formats immediately and remove the legacy key so we never
        // read from it again on subsequent launches.
        if migratedFormatsFromLegacy {
            saveFormats()
            userDefaults.removeObject(forKey: formatKey)
        }
        
        // Subscribe to nested ObservableObject changes so internal mutations
        // (e.g. toggling a metric) are persisted to UserDefaults.
        // didSet only fires when the entire object reference is reassigned,
        // NOT when @Published properties inside the object change.
        subscribeToMetricSelection()
        subscribeToIndividualTracking()
        subscribeToFormatCustomization()
        subscribeToDailyNoteInjection()
    }
    
    // MARK: - Nested ObservableObject Subscriptions
    
    private func subscribeToMetricSelection() {
        metricSelectionCancellable = metricSelection.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.saveMetricSelection()
            }
    }
    
    private func subscribeToIndividualTracking() {
        individualTrackingCancellable = individualTracking.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.saveIndividualTracking()
            }
    }

    private func subscribeToFormatCustomization() {
        formatCustomizationCancellable = formatCustomization.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.saveFormatCustomization()
            }
    }

    private func subscribeToDailyNoteInjection() {
        dailyNoteInjectionCancellable = dailyNoteInjection.objectWillChange
            .sink { [weak self] _ in
                // Forward immediately so parent views re-render (e.g. summary row).
                // @Published emits objectWillChange before the property is mutated,
                // so persist on the next main-queue turn to encode the post-toggle value.
                self?.objectWillChange.send()
                DispatchQueue.main.async { [weak self] in
                    self?.saveDailyNoteInjection()
                }
            }
    }

    private func saveMetricSelection() {
        if let encoded = try? JSONEncoder().encode(metricSelection) {
            userDefaults.set(encoded, forKey: metricSelectionKey)
        }
    }
    
    private func saveFormatCustomization() {
        if let encoded = try? JSONEncoder().encode(formatCustomization) {
            userDefaults.set(encoded, forKey: formatCustomizationKey)
        }
    }
    
    private func saveIndividualTracking() {
        if let encoded = try? JSONEncoder().encode(individualTracking) {
            userDefaults.set(encoded, forKey: individualTrackingKey)
        }
    }

    private func saveDailyNoteInjection() {
        if let encoded = try? JSONEncoder().encode(dailyNoteInjection) {
            userDefaults.set(encoded, forKey: dailyNoteInjectionKey)
        }
    }

    private func saveFormats() {
        let sorted = Array(exportFormats).sorted(by: { $0.rawValue < $1.rawValue })
        if let encoded = try? JSONEncoder().encode(sorted) {
            userDefaults.set(encoded, forKey: formatsKey)
        }
    }

    private func save() {
        // Save data types
        if let encoded = try? JSONEncoder().encode(dataTypes) {
            userDefaults.set(encoded, forKey: dataTypesKey)
        }

        // Save metadata option
        userDefaults.set(includeMetadata, forKey: metadataKey)

        // Save group by category option
        userDefaults.set(groupByCategory, forKey: groupByCategoryKey)

        // Save filename format
        userDefaults.set(filenameFormat, forKey: filenameFormatKey)

        // Save folder structure
        userDefaults.set(folderStructure, forKey: folderStructureKey)

        // Save format-folder organization
        userDefaults.set(organizeFormatsIntoFolders, forKey: organizeFormatsIntoFoldersKey)

        // Save ZIP archive packaging
        userDefaults.set(archiveExportFiles, forKey: archiveExportFilesKey)

        // Save summary-only mode
        userDefaults.set(summaryOnlyExport, forKey: summaryOnlyExportKey)

        // Save write mode
        userDefaults.set(writeMode.rawValue, forKey: writeModeKey)

        // Save granular data setting
        userDefaults.set(includeGranularData, forKey: includeGranularDataKey)

        // Save roll-up summary settings
        userDefaults.set(generateWeeklyRollups, forKey: generateWeeklyRollupsKey)
        userDefaults.set(generateMonthlyRollups, forKey: generateMonthlyRollupsKey)
        userDefaults.set(generateYearlyRollups, forKey: generateYearlyRollupsKey)
    }

    func reset() {
        dataTypes = DataTypeSelection()
        metricSelection = MetricSelectionState()
        exportFormats = [.markdown]
        includeMetadata = true
        groupByCategory = true
        filenameFormat = Self.defaultFilenameFormat
        folderStructure = Self.defaultFolderStructure
        organizeFormatsIntoFolders = false
        archiveExportFiles = false
        summaryOnlyExport = false
        writeMode = .overwrite
        formatCustomization = FormatCustomization()
        individualTracking = IndividualTrackingSettings()
        dailyNoteInjection = DailyNoteInjectionSettings()
        includeGranularData = true
        generateWeeklyRollups = false
        generateMonthlyRollups = false
        generateYearlyRollups = false
    }

    /// Daily Notes Only is effective only while Daily Note Injection itself is enabled.
    var dailyNotesOnlyModeEnabled: Bool {
        dailyNoteInjection.enabled && dailyNoteInjection.dailyNotesOnly
    }

    /// A file destination is valid when it has at least one aggregate format or
    /// explicitly uses Daily Notes Only. API destinations still require formats.
    var hasFileDestinationOutput: Bool {
        dailyNotesOnlyModeEnabled || !exportFormats.isEmpty
    }

    var rollupSummariesEnabled: Bool {
        generateWeeklyRollups || generateMonthlyRollups || generateYearlyRollups
    }

    var effectiveFileExportMode: EffectiveFileExportMode {
        if dailyNotesOnlyModeEnabled { return .dailyNotesOnly }
        if summaryOnlyExport && rollupSummariesEnabled && !exportFormats.isEmpty {
            return .summaryOnly
        }
        return .standard
    }

    var summaryOnlyModeEnabled: Bool {
        effectiveFileExportMode == .summaryOnly
    }

    /// ZIP packaging is ignored while Daily Notes Only is active and when no
    /// aggregate format is selected, but the user's persisted preference remains.
    var archiveModeEnabled: Bool {
        archiveExportFiles && !dailyNotesOnlyModeEnabled && !exportFormats.isEmpty
    }

    var writesDailyAggregateFiles: Bool {
        effectiveFileExportMode == .standard && !archiveModeEnabled && !exportFormats.isEmpty
    }

    var writesIndividualEntryFiles: Bool {
        effectiveFileExportMode == .standard && individualTracking.globalEnabled
    }

    var writesExternalProviderSidecars: Bool {
        effectiveFileExportMode == .standard
    }

    /// Daily note frontmatter/sections only require aggregate snapshots, not the
    /// potentially much larger lossless source-record archive.
    var effectiveGranularDataEnabled: Bool {
        includeGranularData && effectiveFileExportMode == .standard
    }

    var configuredRollupPeriods: [HealthRollupPeriod] {
        var periods: [HealthRollupPeriod] = []
        if generateWeeklyRollups { periods.append(.weekly) }
        if generateMonthlyRollups { periods.append(.monthly) }
        if generateYearlyRollups { periods.append(.yearly) }
        return periods
    }

    /// Runtime periods are empty in Daily Notes Only mode while preserving the
    /// configured period toggles for when that mode is disabled.
    var enabledRollupPeriods: [HealthRollupPeriod] {
        dailyNotesOnlyModeEnabled ? [] : configuredRollupPeriods
    }

    var looseFormatsPerDate: Int {
        writesDailyAggregateFiles ? exportFormats.count : 0
    }

    /// Check if a specific metric is enabled for export
    func isMetricEnabled(_ metricId: String) -> Bool {
        metricSelection.isMetricEnabled(metricId)
    }

    /// Check if a category has any enabled metrics
    func isCategoryEnabled(_ category: HealthMetricCategory) -> Bool {
        metricSelection.enabledMetricCount(for: category) > 0
    }
}
