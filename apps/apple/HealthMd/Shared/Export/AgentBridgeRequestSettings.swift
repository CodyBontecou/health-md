import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

/// Configuration evidence only. Availability is not a HealthKit grant or an approval.
/// The native adapter supplies a pinned registry and a configuration-only availability snapshot.
struct AgentBridgeRequestSettingsCatalog {
    let revision: Int64
    let registrySHA256: String
    let configurationSHA256: String
    fileprivate let metrics: [String: AgentBridgeRequestSettingsMetric]

    init(registry: CoreMetricRegistrySnapshot, availableNativeMetricIDs: Set<String>, revision: Int64) throws {
        guard revision > 0 else { throw AgentBridgeValidationError.invalidRequest }
        guard HealthMdCoreRegistryAdapter.shadowDifferences(snapshot: registry).isEmpty else {
            throw AgentBridgeValidationError.bindingChanged
        }
        let supported: Set<String> = [
            "steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"
        ]
        var resolved: [String: AgentBridgeRequestSettingsMetric] = [:]
        for metric in registry.metrics where supported.contains(metric.semanticId) {
            // These reviewed Apple semantic IDs are exact native IDs, not name/category aliases.
            guard metric.semanticId == metric.selectionId, !metric.archiveOnly,
                  metric.kind == "quantity", !metric.sourceSelector.isEmpty,
                  resolved[metric.semanticId] == nil else {
                throw AgentBridgeValidationError.bindingChanged
            }
            if availableNativeMetricIDs.contains(metric.selectionId) {
                resolved[metric.semanticId] = .init(
                    semanticID: metric.semanticId,
                    nativeMetricID: metric.selectionId,
                    nativeCategoryID: metric.categoryId,
                    sourceSelector: metric.sourceSelector,
                    sourceReducer: metric.sourceAggregation,
                    canonicalUnit: metric.unit
                )
            }
        }
        guard availableNativeMetricIDs.isSubset(of: Set(registry.metrics.map(\.selectionId))) else {
            throw AgentBridgeValidationError.bindingChanged
        }
        self.revision = revision
        registrySHA256 = registry.registrySha256
        // Configuration identity only, including unselected availability; never permission evidence.
        configurationSHA256 = AgentBridgeV4Codec.sha256(try JSONEncoder().encode(
            [registry.registrySha256, String(revision)] + availableNativeMetricIDs.sorted()
        ))
        metrics = resolved
    }
}

struct AgentBridgeRequestSettingsMetric: Codable, Equatable {
    let semanticID: String
    let nativeMetricID: String
    let nativeCategoryID: String
    let sourceSelector: String
    let sourceReducer: String
    let canonicalUnit: String
}

/// Supplied private output snapshot. No store, active-profile lookup or destination is consulted.
struct AgentBridgeRequestSettingsSnapshot {
    let revision: Int64
    let settings: ExportSettingsSnapshot
}

struct AgentBridgeRequestSettingsProfile {
    let profileID: AgentBridgeUUID
    let snapshot: AgentBridgeRequestSettingsSnapshot
    let executionBlocked: Bool
}

struct AgentBridgeRequestSettingsInputs {
    let catalog: AgentBridgeRequestSettingsCatalog
    let savedDevice: AgentBridgeRequestSettingsSnapshot?
    let profiles: [AgentBridgeRequestSettingsProfile]
}

enum AgentBridgeRequestSettingsOrigin: String, Codable {
    case request
    case savedDeviceSettings = "saved_device_settings"
    case profile
}

/// Non-persisted public output alongside the unchanged version-1 private native resolution.
struct AgentBridgeRequestSettingsOutputResolution {
    let native: AgentBridgeRequestSettingsResolution
    let effectiveOutput: AgentBridgeOutputSettings
}

/// Independently versioned private resolution material, not a plan, journal or authorization.
/// Persist only inside a future authenticated journal that separately binds approvals and authority.
/// Value snapshots copy on mutation; reconstruct execution from this value, never from live settings.
struct AgentBridgeRequestSettingsResolution: Codable, Equatable {
    let version: Int
    let intentSHA256: String
    let peer: AgentBridgePeer
    let destination: AgentBridgeDestination
    let capabilityRevision: Int64
    let catalogSHA256: String
    let registrySHA256: String
    let settingsOrigin: AgentBridgeRequestSettingsOrigin
    let settingsRevision: Int64?
    let profileID: AgentBridgeUUID?
    let resolvedAt: Date
    let dates: AgentBridgeDates
    let requestedDays: [AgentBridgeDate]
    let predictedRelativePaths: [String]
    let selection: [AgentBridgeRequestSettingsMetric]
    let settings: ExportSettingsSnapshot

    /// Renderer adapter only; it does not authorize or start capture, delivery, quota or history.
    func makeExporterSettings() throws -> AdvancedExportSettings {
        guard version == 1,
              let zoneID = settings.calendarTimeZoneIdentifier,
              AppleExportEnginePin.isIANAIdentifier(zoneID),
              let zone = TimeZone(identifier: zoneID),
              let backing = UserDefaults(suiteName: "AgentBridgeRequestSettings.\(UUID().uuidString)") else {
            throw AgentBridgeValidationError.invalidRequest
        }
        let execution = AdvancedExportSettings(
            snapshot: settings,
            userDefaults: backing,
            persistChanges: false
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        execution.exportCalendarOverride = calendar
        execution.exportLocaleOverride = Locale(identifier: "en_US_POSIX")
        return execution
    }
}

/// Legacy references may use a display name only when the ID is actually absent. A supplied
/// malformed/deleted ID is authoritative and cannot be replaced by a matching name hint.
enum AgentBridgeRequestSettingsProfileLookup {
    static func resolve<T>(_ reference: DirectProfileReference, byID: (UUID) -> T?, byName: (String) -> T?) -> T? {
        if !reference.profileID.isEmpty {
            guard let id = UUID(uuidString: reference.profileID) else { return nil }
            return byID(id)
        }
        guard let name = reference.name else { return nil }
        return byName(name)
    }
}

/// Bounded production adapter for summary/no-archive loose daily JSON. All other dialects reject.
/// Native stored authority, readiness, approval, revalidation and durable execution remain mandatory
/// outside this pure seam. In particular, neither a codec digest nor catalog availability grants read.
enum AgentBridgeRequestSettingsResolver {
    static func resolve(
        _ intent: AgentBridgeGeneratedIntent,
        inputs: AgentBridgeRequestSettingsInputs,
        clock: Date,
        calendar: Calendar
    ) throws -> AgentBridgeRequestSettingsResolution {
        try resolveWithOutput(intent, inputs: inputs, clock: clock, calendar: calendar).native
    }

    static func resolveWithOutput(
        _ intent: AgentBridgeGeneratedIntent,
        inputs: AgentBridgeRequestSettingsInputs,
        clock: Date,
        calendar: Calendar
    ) throws -> AgentBridgeRequestSettingsOutputResolution {
        // Recheck constructors with the integrated strict codec, including closed paths and grammar.
        let intentDigest = try AgentBridgeV4Codec.digest(intent)
        guard intent.peer.platform == .apple,
              calendar.identifier == .gregorian,
              calendar.timeZone == TimeZone(identifier: intent.calendarTimezone.rawValue),
              clock.timeIntervalSince1970.isFinite else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        let capture = intent.captureScope
        let requested = capture.selection
        guard !requested.metricIDs.isEmpty else { throw AgentBridgeValidationError.unsupportedMetric }
        guard requested.categoryIDs.isEmpty, !requested.allMetrics,
              requested.sourceIDs.map(\.rawValue) == ["apple_health"], requested.providerIDs.isEmpty,
              capture.compatibilityDetail == .summary, capture.nativeArchive == .none else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        let selection = try requested.metricIDs.map { id in
            guard let metric = inputs.catalog.metrics[id.rawValue] else {
                throw AgentBridgeValidationError.unsupportedMetric
            }
            return metric
        }

        let output: AgentBridgeOutputSettings
        let origin: AgentBridgeRequestSettingsOrigin
        let revision: Int64?
        let profileID: AgentBridgeUUID?
        switch intent.settingsPolicy {
        case .explicit(let value):
            output = value; origin = .request; revision = nil; profileID = nil
        case .savedDeviceSettings(let expected):
            guard let snapshot = inputs.savedDevice else { throw AgentBridgeValidationError.unsupportedCapability }
            try checkRevision(snapshot.revision, expected: expected)
            output = try outputSettings(from: snapshot.settings)
            origin = .savedDeviceSettings; revision = snapshot.revision; profileID = nil
        case .profile(let id, let expected):
            let matches = inputs.profiles.filter { $0.profileID == id }
            guard matches.count == 1, let profile = matches.first else {
                throw AgentBridgeValidationError.unsupportedCapability
            }
            try checkRevision(profile.snapshot.revision, expected: expected)
            guard !profile.executionBlocked else { throw AgentBridgeValidationError.nativeRebindRequired }
            output = try outputSettings(from: profile.snapshot.settings)
            origin = .profile; revision = profile.snapshot.revision; profileID = id
        }
        try validate(output)
        let dates = try resolvedDates(intent.dates, calendar: calendar)
        let paths = try AgentBridgePaths.predictedPaths(dates: dates, settings: output)
        let days = try requestedDays(dates, calendar: calendar)
        let settings = snapshot(output: output, selection: selection, timeZone: intent.calendarTimezone.rawValue)
        return .init(native: .init(
            version: 1, intentSHA256: intentDigest, peer: intent.peer, destination: intent.destination,
            capabilityRevision: inputs.catalog.revision, catalogSHA256: inputs.catalog.configurationSHA256, registrySHA256: inputs.catalog.registrySHA256,
            settingsOrigin: origin, settingsRevision: revision, profileID: profileID, resolvedAt: clock,
            dates: dates, requestedDays: days, predictedRelativePaths: paths, selection: selection, settings: settings
        ), effectiveOutput: output)
    }

    /// Configuration-only reuse check. The candidate is comparison material, never replacement
    /// execution settings; callers keep the original frozen value. This is not approval/resume
    /// authorization, expiry verification or authenticated journal validation.
    static func validateForReuse(
        _ frozen: AgentBridgeRequestSettingsResolution,
        intent: AgentBridgeGeneratedIntent,
        inputs: AgentBridgeRequestSettingsInputs,
        calendar: Calendar
    ) throws {
        guard frozen.version == 1 else { throw AgentBridgeValidationError.invalidRequest }
        let candidate = try resolve(intent, inputs: inputs, clock: frozen.resolvedAt, calendar: calendar)
        guard candidate == frozen else { throw AgentBridgeValidationError.bindingChanged }
    }

    private static func checkRevision(_ actual: Int64, expected: Int64) throws {
        guard actual > 0, actual == expected else { throw AgentBridgeValidationError.revisionConflict }
    }

    private static func validate(_ output: AgentBridgeOutputSettings) throws {
        // Validate saved snapshots too; they were not necessarily constructed by the wire codec.
        _ = try AgentBridgeV4Codec.encode(output)
        guard output.formats == [.json], output.outputProfile == .appleV8,
              output.writeMode == .overwrite,
              output.presentation.displayUnits == .metric, output.presentation.locale == "en-US",
              output.presentation.includeMetadata, output.presentation.groupByCategory,
              output.presentation.frontmatter == .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: false),
              output.presentation.markdown == .init(style: .lists, customTemplate: "", placeholderIDs: []),
              output.individualEntries == .init(enabled: false, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false),
              output.dailyNotes == .init(enabled: false, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []),
              output.packaging == .looseFiles, output.dictionary == .none else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        // Both shipped aggregate exporters treat the subfolder as a literal, not a date template.
        guard !output.subfolder.contains("{"), !output.subfolder.contains("}") else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        // Match Android's reviewed bounded ASCII path preflight; do not claim Unicode host safety.
        guard [output.subfolder, output.folderTemplate, output.filenameTemplate].allSatisfy({ $0.utf8.allSatisfy { $0 < 128 } }) else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
    }

    private static func snapshot(output: AgentBridgeOutputSettings, selection: [AgentBridgeRequestSettingsMetric], timeZone: String) -> ExportSettingsSnapshot {
        ExportSettingsSnapshot(
            exportFormats: [.json], includeMetadata: true, groupByCategory: true,
            filenameFormat: output.filenameTemplate, folderStructure: output.folderTemplate,
            healthSubfolder: output.subfolder, organizeFormatsIntoFolders: false, archiveExportFiles: false,
            includeDataDictionary: false, summaryOnlyExport: false, writeMode: .overwrite,
            formatCustomization: .init(
                dateFormat: .iso8601, timeFormat: .hour24, unitPreference: .metric,
                frontmatterConfig: .init(fields: [], customFields: [:], placeholderFields: [], includeDate: true, includeType: true, customDateKey: "date", customTypeKey: "type", customTypeValue: "health-data", keyStyle: .snakeCase),
                markdownTemplate: MarkdownTemplateConfig()
            ),
            individualTracking: .init(globalEnabled: false, metricConfigs: [:], entriesFolder: "", useCategoryFolders: false, filenameTemplate: "{metric}-{date}"),
            dailyNoteInjection: .init(enabled: false, folderPath: "", filenamePattern: "{date}", createIfMissing: false, injectMarkdownSections: false, dailyNotesOnly: false),
            includeGranularData: false, compatibilityDetail: .summary, healthKitSourceArchivePolicy: HealthKitSourceArchivePolicy.none,
            generateRangeSummary: false,
            metricSelection: .init(enabledMetricIDs: Set(selection.map(\.nativeMetricID)), enabledCategoryIDs: Set(selection.map(\.nativeCategoryID))),
            appleExportEnginePin: nil, appleExportEngineAuthorityIsFrozen: true, calendarTimeZoneIdentifier: timeZone
        )
    }

    private static func outputSettings(from native: ExportSettingsSnapshot) throws -> AgentBridgeOutputSettings {
        guard let subfolder = native.healthSubfolder else { throw AgentBridgeValidationError.unsupportedCapability }
        let output = AgentBridgeOutputSettings(
            formats: [.json], outputProfile: .appleV8, subfolder: subfolder,
            folderTemplate: native.folderStructure, filenameTemplate: native.filenameFormat, writeMode: .overwrite,
            presentation: .init(displayUnits: .metric, locale: "en-US", includeMetadata: true, groupByCategory: true,
                                frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: false),
                                markdown: .init(style: .lists, customTemplate: "", placeholderIDs: [])),
            individualEntries: .init(enabled: false, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false),
            dailyNotes: .init(enabled: false, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []),
            packaging: .looseFiles, dictionary: .none
        )
        let supported = snapshot(output: output, selection: [], timeZone: "UTC")
        // Capture selections/detail/archive/timezone come from the request for every policy.
        // No output-affecting native extension is silently dropped or replaced with a default.
        guard native.exportFormats == supported.exportFormats,
              native.includeMetadata == supported.includeMetadata,
              native.groupByCategory == supported.groupByCategory,
              native.organizeFormatsIntoFolders == supported.organizeFormatsIntoFolders,
              native.archiveExportFiles == supported.archiveExportFiles,
              native.includeDataDictionary == supported.includeDataDictionary,
              native.summaryOnlyExport == supported.summaryOnlyExport,
              native.writeMode == supported.writeMode,
              native.formatCustomization == supported.formatCustomization,
              native.individualTracking == supported.individualTracking,
              native.dailyNoteInjection == supported.dailyNoteInjection,
              !native.generateRangeSummary, native.appleExportEnginePin == nil else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        return output
    }

    private static func resolvedDates(_ input: AgentBridgeDates, calendar: Calendar) throws -> AgentBridgeDates {
        guard case .pastCompleteDays(let count, let anchor) = input else { return input }
        // Labels are Gregorian civil days, not elapsed 24-hour source instants. Use a fixed label
        // calendar so a zone that skips an entire day cannot silently narrow the requested range.
        let labels = labelCalendar(from: calendar)
        let date = try civilDate(anchor, calendar: labels)
        guard let start = labels.date(byAdding: .day, value: -Int(count), to: date),
              let end = labels.date(byAdding: .day, value: -1, to: date) else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return try .exact(.init(startDate: civilDay(start, calendar: labels), endDate: civilDay(end, calendar: labels)))
    }

    private static func requestedDays(_ dates: AgentBridgeDates, calendar: Calendar) throws -> [AgentBridgeDate] {
        guard case .exact(let range) = dates else { return [] } // all_available never discovers history.
        let labels = labelCalendar(from: calendar)
        let first = try civilDate(range.startDate, calendar: labels)
        let last = try civilDate(range.endDate, calendar: labels)
        guard let count = labels.dateComponents([.day], from: first, to: last).day,
              (0..<4096).contains(count) else { throw AgentBridgeValidationError.queryBudgetExceeded }
        return try (0...count).map { offset in
            guard let date = labels.date(byAdding: .day, value: offset, to: first) else {
                throw AgentBridgeValidationError.invalidRequest
            }
            let day = try civilDay(date, calendar: labels)
            _ = try civilDate(day, calendar: calendar) // No nonexistent source day is approximated.
            return day
        }
    }

    private static func labelCalendar(from calendar: Calendar) -> Calendar {
        var labels = calendar
        labels.timeZone = TimeZone(secondsFromGMT: 0)!
        labels.locale = Locale(identifier: "en_US_POSIX")
        return labels
    }

    private static func civilDate(_ day: AgentBridgeDate, calendar: Calendar) throws -> Date {
        let parts = day.rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              try civilDay(date, calendar: calendar) == day else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return date
    }

    private static func civilDay(_ date: Date, calendar: Calendar) throws -> AgentBridgeDate {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, (1...9999).contains(year), let month = parts.month, let day = parts.day else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return try AgentBridgeDate(String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), year, month, day))
    }
}
