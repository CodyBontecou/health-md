import Foundation
import HealthMdCoreRust

// Dedicated public DTOs for healthmd.shared_setup v1. These types deliberately do not expose
// UserDefaults, ExportSettingsSnapshot, bookmarks, credentials, permissions, or runtime state.
struct SharedSetupV1: Codable, Equatable, Sendable {
    static let schemaName = "healthmd.shared_setup"
    static let schemaVersion = 1
    nonisolated static let maximumEncodedBytes = 262_144

    var schema: String
    var schemaVersion: Int
    var createdBy: CreatedBy
    var metricRegistry: MetricRegistry
    var profile: Profile
    var metricAliases: [MetricAlias]
    var platformExtensions: PlatformExtensions

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case createdBy = "created_by"
        case metricRegistry = "metric_registry"
        case profile
        case metricAliases = "metric_aliases"
        case platformExtensions = "platform_extensions"
    }

    struct CreatedBy: Codable, Equatable, Sendable {
        var platform: Platform
        var appVersion: String
        enum CodingKeys: String, CodingKey { case platform; case appVersion = "app_version" }
    }

    enum Platform: String, Codable, Sendable { case apple, android }

    struct MetricRegistry: Codable, Equatable, Sendable {
        var schema: String
        var registryVersion: Int
        var registrySHA256: String
        enum CodingKeys: String, CodingKey {
            case schema
            case registryVersion = "registry_version"
            case registrySHA256 = "registry_sha256"
        }
    }

    struct MetricAlias: Codable, Equatable, Sendable {
        var semanticID: String
        var equivalence: Equivalence
        var appleSelectionID: String?
        var androidSelectionID: String?
        enum CodingKeys: String, CodingKey {
            case semanticID = "semantic_id"
            case equivalence
            case appleSelectionID = "apple_selection_id"
            case androidSelectionID = "android_selection_id"
        }
    }

    enum Equivalence: String, Codable, Sendable {
        case platformExactOrUnavailable = "platform_exact_or_unavailable"
        case mappedAlias = "mapped_alias"
        case platformDistinct = "platform_distinct"
    }

    struct Profile: Codable, Equatable, Sendable {
        var export: Export
        var metrics: Metrics
        var presentation: Presentation
        var individualEntries: IndividualEntries
        var dailyNotes: DailyNotes
        var schedule: Schedule
        var apiEndpoint: APIEndpoint?
        enum CodingKeys: String, CodingKey {
            case export, metrics, presentation, schedule
            case individualEntries = "individual_entries"
            case dailyNotes = "daily_notes"
            case apiEndpoint = "api_endpoint"
        }
    }

    struct Export: Codable, Equatable, Sendable {
        var formats: [Format]
        var includeMetadata: Bool
        var groupByCategory: Bool
        var filenameTemplate: String
        var folderTemplate: String
        var writeMode: SharedWriteMode
        var includeGranularData: Bool
        enum CodingKeys: String, CodingKey {
            case formats
            case includeMetadata = "include_metadata"
            case groupByCategory = "group_by_category"
            case filenameTemplate = "filename_template"
            case folderTemplate = "folder_template"
            case writeMode = "write_mode"
            case includeGranularData = "include_granular_data"
        }
    }

    enum Format: String, Codable, Sendable { case markdown; case obsidianBases = "obsidian_bases"; case json; case csv }
    enum SharedWriteMode: String, Codable, Sendable { case overwrite, append, update }

    struct Metrics: Codable, Equatable, Sendable {
        var enabledIDs: [String]
        enum CodingKeys: String, CodingKey { case enabledIDs = "enabled_ids" }
    }

    struct Presentation: Codable, Equatable, Sendable {
        var dateFormat: DateFormat
        var timeFormat: TimeFormat
        var units: Units
        var frontmatter: Frontmatter
        var markdown: Markdown
        enum CodingKeys: String, CodingKey {
            case dateFormat = "date_format"
            case timeFormat = "time_format"
            case units, frontmatter, markdown
        }
    }

    enum DateFormat: String, Codable, Sendable { case iso8601, usShort = "us_short", usLong = "us_long", euShort = "eu_short", euLong = "eu_long", compact, friendly }
    enum TimeFormat: String, Codable, Sendable { case hour24 = "hour_24", hour24Seconds = "hour_24_seconds", hour12 = "hour_12", hour12Seconds = "hour_12_seconds" }
    enum Units: String, Codable, Sendable { case metric, imperial }

    struct Frontmatter: Codable, Equatable, Sendable {
        var fields: [FrontmatterField]
        var customValues: [String: String]
        var placeholders: [String]
        var includeDate: Bool
        var includeType: Bool
        var dateKey: String
        var typeKey: String
        var typeValue: String
        var keyStyle: KeyStyle
        enum CodingKeys: String, CodingKey {
            case fields, placeholders
            case customValues = "custom_values"
            case includeDate = "include_date"
            case includeType = "include_type"
            case dateKey = "date_key"
            case typeKey = "type_key"
            case typeValue = "type_value"
            case keyStyle = "key_style"
        }
    }

    struct FrontmatterField: Codable, Equatable, Sendable {
        var sourceKey: String
        var outputKey: String
        var enabled: Bool
        enum CodingKeys: String, CodingKey {
            case sourceKey = "source_key"
            case outputKey = "output_key"
            case enabled
        }
    }
    enum KeyStyle: String, Codable, Sendable { case snakeCase = "snake_case", camelCase = "camel_case" }

    struct Markdown: Codable, Equatable, Sendable {
        var style: MarkdownStyle
        var customText: String
        var headerLevel: Int
        var useEmoji: Bool
        var includeSummary: Bool
        var bulletStyle: BulletStyle
        var originDialect: OriginDialect
        enum CodingKeys: String, CodingKey {
            case style
            case customText = "custom_text"
            case headerLevel = "header_level"
            case useEmoji = "use_emoji"
            case includeSummary = "include_summary"
            case bulletStyle = "bullet_style"
            case originDialect = "origin_dialect"
        }
    }
    enum MarkdownStyle: String, Codable, Sendable { case standard, compact, detailed, custom }
    enum BulletStyle: String, Codable, Sendable { case dash, asterisk, plus }
    enum OriginDialect: String, Codable, Sendable { case portable, apple, android }

    struct IndividualEntries: Codable, Equatable, Sendable {
        var enabled: Bool
        var metrics: [String: IndividualMetric]
        var entriesFolder: String
        var organizeByCategory: Bool
        var filenameTemplate: String
        enum CodingKeys: String, CodingKey {
            case enabled, metrics
            case entriesFolder = "entries_folder"
            case organizeByCategory = "organize_by_category"
            case filenameTemplate = "filename_template"
        }
    }
    struct IndividualMetric: Codable, Equatable, Sendable {
        var enabled: Bool
        var customFolder: String?
        enum CodingKeys: String, CodingKey { case enabled; case customFolder = "custom_folder" }
    }

    struct DailyNotes: Codable, Equatable, Sendable {
        var enabled: Bool
        var folder: String
        var filenameTemplate: String
        var createIfMissing: Bool
        var injectSections: Bool
        enum CodingKeys: String, CodingKey {
            case enabled, folder
            case filenameTemplate = "filename_template"
            case createIfMissing = "create_if_missing"
            case injectSections = "inject_sections"
        }
    }

    struct Schedule: Codable, Equatable, Sendable {
        var activationRequested: Bool
        var cadence: Cadence
        var localTime: LocalTime
        var lookbackDays: Int
        var dateWindow: DateWindow
        var desiredTarget: DesiredTarget
        enum CodingKeys: String, CodingKey {
            case activationRequested = "activation_requested"
            case cadence
            case localTime = "local_time"
            case lookbackDays = "lookback_days"
            case dateWindow = "date_window"
            case desiredTarget = "desired_target"
        }
    }
    struct Cadence: Codable, Equatable, Sendable { var value: Int; var unit: CadenceUnit }
    enum CadenceUnit: String, Codable, Sendable { case minutes, hours, days, weeks, months }
    struct LocalTime: Codable, Equatable, Sendable { var hour: Int; var minute: Int }
    enum DateWindow: String, Codable, Sendable { case pastCompleteDays = "past_complete_days", today }
    enum DesiredTarget: String, Codable, Sendable { case deviceFolder = "device_folder", apiEndpoint = "api_endpoint" }

    struct APIEndpoint: Codable, Equatable, Sendable {
        var scheme: String
        var host: String
        var port: Int?
        var path: String
        var queryOmitted: Bool
        var credentialsRequired: Bool
        enum CodingKeys: String, CodingKey {
            case scheme, host, port, path
            case queryOmitted = "query_omitted"
            case credentialsRequired = "credentials_required"
        }

        var validatedURLString: String? {
            guard scheme == "https", credentialsRequired,
                  SharedSetupValidation.isDNSHost(host),
                  (port == nil || (1...65_535).contains(port!)),
                  path.count <= 2_048, path.first == "/", !path.hasPrefix("//"),
                  !path.contains(where: { $0 == "%" || $0 == "?" || $0 == "#" || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.port = port
            components.percentEncodedPath = path
            components.query = nil
            components.fragment = nil
            return components.url?.absoluteString
        }
    }

    struct PlatformExtensions: Codable, Equatable, Sendable { var apple: AppleExtension?; var android: AndroidExtension? }
    struct AppleExtension: Codable, Equatable, Sendable {
        var extensionVersion: Int
        var export: AppleExport
        var dailyNotes: AppleDailyNotes
        var schedule: AppleSchedule
        enum CodingKeys: String, CodingKey {
            case extensionVersion = "extension_version"
            case export, schedule
            case dailyNotes = "daily_notes"
        }
    }
    struct AppleExport: Codable, Equatable, Sendable {
        var organizeFormatsIntoFolders: Bool
        var archiveFiles: Bool
        var includeDataDictionary: Bool
        var summaryOnly: Bool
        var rollups: [Rollup]
        enum CodingKeys: String, CodingKey {
            case organizeFormatsIntoFolders = "organize_formats_into_folders"
            case archiveFiles = "archive_files"
            case includeDataDictionary = "include_data_dictionary"
            case summaryOnly = "summary_only"
            case rollups
        }
    }
    enum Rollup: String, Codable, Sendable { case weekly, monthly, yearly }
    struct AppleDailyNotes: Codable, Equatable, Sendable { var only: Bool }
    struct AppleSchedule: Codable, Equatable, Sendable {
        var frequency: AppleFrequency
        var customUnit: AppleCustomUnit
        var weekday: Int
        var todayRefreshRequested: Bool
        var todayRefreshIntervalHours: Int
        var desiredTarget: AppleDesiredTarget
        enum CodingKeys: String, CodingKey {
            case frequency, weekday
            case customUnit = "custom_unit"
            case todayRefreshRequested = "today_refresh_requested"
            case todayRefreshIntervalHours = "today_refresh_interval_hours"
            case desiredTarget = "desired_target"
        }
    }
    enum AppleFrequency: String, Codable, Sendable { case daily, weekly, custom }
    enum AppleCustomUnit: String, Codable, Sendable { case days, weeks, months }
    enum AppleDesiredTarget: String, Codable, Sendable { case localIPhoneFolder = "local_iphone_folder", connectedMac = "connected_mac", apiEndpoint = "api_endpoint" }
    struct AndroidExtension: Codable, Equatable, Sendable {
        var extensionVersion: Int
        var export: AndroidExport
        enum CodingKeys: String, CodingKey { case extensionVersion = "extension_version"; case export }
    }
    struct AndroidExport: Codable, Equatable, Sendable {
        var compatibilityProfile: AndroidProfile
        var includeLegacyAliases: Bool
        var includeAndroidNativeFields: Bool
        var subfolder: String
        var folderOrganization: FolderOrganization
        enum CodingKeys: String, CodingKey {
            case compatibilityProfile = "compatibility_profile"
            case includeLegacyAliases = "include_legacy_aliases"
            case includeAndroidNativeFields = "include_android_native_fields"
            case subfolder
            case folderOrganization = "folder_organization"
        }
    }
    enum AndroidProfile: String, Codable, Sendable { case frozenV4 = "frozen_v4", analyticalV5 = "analytical_v5" }
    enum FolderOrganization: String, Codable, Sendable { case flat, byYear = "by_year", byMonth = "by_month", byYearMonth = "by_year_month" }
}

enum SharedSetupCompatibilityStatus: String, Codable, Sendable { case applied; case requiresAction = "requires_action"; case unsupported; case invalid }

struct SharedSetupCompatibilityItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var status: SharedSetupCompatibilityStatus
}

struct SharedSetupPreview: Equatable, Sendable {
    var document: SharedSetupV1
    var items: [SharedSetupCompatibilityItem]
    var supportedMetricSelectionIDs: Set<String>
    var supportedIndividualMetricSelectionIDs: [String: SharedSetupV1.IndividualMetric]
    var installCustomTemplate: Bool

    var hasInvalidItems: Bool { items.contains { $0.status == .invalid } }
    var selectedMetricCount: Int { document.profile.metrics.enabledIDs.count }
    var requiresAttention: [SharedSetupCompatibilityItem] { items.filter { $0.status != .applied } }
}

enum SharedSetupError: LocalizedError, Equatable {
    case oversized
    case malformed(String)
    case invalid(String)
    case persistenceVerificationFailed
    case noUndoSnapshot

    var errorDescription: String? {
        switch self {
        case .oversized: "This setup file is larger than 256 KB."
        case .malformed(let reason), .invalid(let reason): reason
        case .persistenceVerificationFailed: "Health.md could not verify the imported setup and restored the previous setup."
        case .noUndoSnapshot: "There is no shared setup to undo."
        }
    }
}

enum SharedSetupCodec {
    static func decode(_ data: Data) throws -> SharedSetupV1 {
        guard data.count <= SharedSetupV1.maximumEncodedBytes else { throw SharedSetupError.oversized }
        try SharedSetupValidation.preflightJSON(data)
        let document: SharedSetupV1
        do { document = try JSONDecoder().decode(SharedSetupV1.self, from: data) }
        catch { throw SharedSetupError.malformed("This is not a valid Health.md setup file.") }
        try SharedSetupValidation.validate(document)
        return document
    }

    static func encode(_ document: SharedSetupV1) throws -> Data {
        try SharedSetupValidation.validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(document)
        guard var root = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var profile = root["profile"] as? [String: Any],
              var aliases = root["metric_aliases"] as? [[String: Any]],
              var extensions = root["platform_extensions"] as? [String: Any],
              var individual = profile["individual_entries"] as? [String: Any],
              var metrics = individual["metrics"] as? [String: Any] else {
            throw SharedSetupError.malformed("Health.md could not encode the setup document.")
        }
        for index in aliases.indices {
            if aliases[index]["apple_selection_id"] == nil { aliases[index]["apple_selection_id"] = NSNull() }
            if aliases[index]["android_selection_id"] == nil { aliases[index]["android_selection_id"] = NSNull() }
        }
        for key in metrics.keys {
            guard var metric = metrics[key] as? [String: Any] else { continue }
            if metric["custom_folder"] == nil { metric["custom_folder"] = NSNull() }
            metrics[key] = metric
        }
        individual["metrics"] = metrics
        profile["individual_entries"] = individual
        if profile["api_endpoint"] == nil {
            profile["api_endpoint"] = NSNull()
        } else if var endpoint = profile["api_endpoint"] as? [String: Any], endpoint["port"] == nil {
            endpoint["port"] = NSNull()
            profile["api_endpoint"] = endpoint
        }
        if extensions["apple"] == nil { extensions["apple"] = NSNull() }
        if extensions["android"] == nil { extensions["android"] = NSNull() }
        root["profile"] = profile
        root["metric_aliases"] = aliases
        root["platform_extensions"] = extensions
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= SharedSetupV1.maximumEncodedBytes else { throw SharedSetupError.oversized }
        try SharedSetupValidation.preflightJSON(data)
        return data
    }
}

enum SharedSetupValidation {
    private nonisolated static let identifier = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*$"#)
    private static let allowedSensitiveLookingKeys: Set<String> = ["credentials_required"]
    private static let forbiddenKeyParts = [
        "authorization", "bearer", "token", "credential", "password", "secret", "api_key",
        "request_header", "cookie", "bookmark", "content_uri", "saf_uri", "folder_grant",
        "permission", "purchase", "entitlement", "device_id", "installation_id", "account_id",
        "health_record", "health_data", "source_data", "history", "analytics", "email",
        "last_run", "last_success", "operation_id", "fingerprint", "engine_pin", "enabled_at",
        "retry", "pending_request", "raw_snapshot", "session_id", "worker_id", "alarm_id",
        "enabled_categories", "category_selection", "onboarding"
    ]

    static func preflightJSON(_ data: Data) throws {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw SharedSetupError.malformed("This setup file is not valid JSON.") }
        var nodes = 0
        func walk(_ value: Any, depth: Int) throws {
            guard depth <= 16 else { throw SharedSetupError.invalid("The setup file is nested too deeply.") }
            nodes += 1
            guard nodes <= 16_384 else { throw SharedSetupError.invalid("The setup file contains too many values.") }
            switch value {
            case let dictionary as [String: Any]:
                guard dictionary.count <= 256 else { throw SharedSetupError.invalid("The setup file contains an oversized object.") }
                for (key, child) in dictionary {
                    guard key.unicodeScalars.count <= 65_536 else { throw SharedSetupError.invalid("The setup file contains an oversized key.") }
                    let normalized = key.lowercased()
                        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                    if !allowedSensitiveLookingKeys.contains(normalized),
                       forbiddenKeyParts.contains(where: normalized.contains) {
                        throw SharedSetupError.invalid("The setup file contains prohibited private or runtime state.")
                    }
                    try walk(child, depth: depth + 1)
                }
            case let array as [Any]:
                guard array.count <= 256 else { throw SharedSetupError.invalid("The setup file contains an oversized list.") }
                for child in array { try walk(child, depth: depth + 1) }
            case let string as String:
                guard string.unicodeScalars.count <= 65_536 else { throw SharedSetupError.invalid("The setup file contains oversized text.") }
                let lowered = string.lowercased()
                if lowered.hasPrefix("content://") || lowered.hasPrefix("file://") ||
                    lowered.contains("authorization:") ||
                    string.range(of: #"(?i)\b(?:bearer|basic)\s+[a-z0-9]"#, options: .regularExpression) != nil {
                    throw SharedSetupError.invalid("The setup file contains device-bound or authorization material.")
                }
            default: break
            }
        }
        try walk(object, depth: 1)
        try validateRequiredNullableKeys(object)
    }

    private static func validateRequiredNullableKeys(_ root: Any) throws {
        guard let object = root as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              profile.keys.contains("api_endpoint"),
              let individual = profile["individual_entries"] as? [String: Any],
              let individualMetrics = individual["metrics"] as? [String: Any],
              let aliases = object["metric_aliases"] as? [[String: Any]],
              aliases.allSatisfy({ $0.keys.contains("apple_selection_id") && $0.keys.contains("android_selection_id") }),
              individualMetrics.values.allSatisfy({ ($0 as? [String: Any])?.keys.contains("custom_folder") == true }),
              let extensions = object["platform_extensions"] as? [String: Any],
              extensions.keys.contains("apple"), extensions.keys.contains("android") else {
            throw SharedSetupError.invalid("The setup is missing a required explicit nullable field.")
        }
        if let endpoint = profile["api_endpoint"] as? [String: Any], !endpoint.keys.contains("port") {
            throw SharedSetupError.invalid("The endpoint is missing its explicit nullable port.")
        }
    }

    static func validate(_ value: SharedSetupV1) throws {
        guard value.schema == SharedSetupV1.schemaName, value.schemaVersion == 1 else { throw SharedSetupError.invalid("This setup version is not supported.") }
        guard !value.createdBy.appVersion.isEmpty, value.createdBy.appVersion.count <= 256 else { throw SharedSetupError.invalid("The sender version is invalid.") }
        guard value.metricRegistry.schema == "healthmd.metric_registry", value.metricRegistry.registryVersion >= 1,
              value.metricRegistry.registrySHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw SharedSetupError.invalid("The metric registry identity is invalid.") }
        let ids = value.profile.metrics.enabledIDs
        guard ids.count <= 256, ids == ids.sorted(), Set(ids).count == ids.count, ids.allSatisfy(isIdentifier) else { throw SharedSetupError.invalid("Metric IDs must be unique, sorted canonical semantic IDs.") }
        let aliasIDs = value.metricAliases.map(\.semanticID)
        guard value.metricAliases.count <= 256, aliasIDs == aliasIDs.sorted(),
              Set(aliasIDs).count == aliasIDs.count, Set(aliasIDs) == Set(ids),
              value.metricAliases.allSatisfy({ isIdentifier($0.semanticID) && $0.appleSelectionID.map(isIdentifier) ?? true && $0.androidSelectionID.map(isIdentifier) ?? true }) else { throw SharedSetupError.invalid("The metric alias ledger is incomplete or not canonical.") }
        guard Set(value.profile.export.formats).count == value.profile.export.formats.count else { throw SharedSetupError.invalid("Export formats must be unique.") }
        try validateRelativePath(value.profile.export.folderTemplate)
        try validateFilename(value.profile.export.filenameTemplate)
        try validateRelativePath(value.profile.individualEntries.entriesFolder)
        try validateFilename(value.profile.individualEntries.filenameTemplate)
        try validateRelativePath(value.profile.dailyNotes.folder)
        try validateFilename(value.profile.dailyNotes.filenameTemplate)
        if let androidExtension = value.platformExtensions.android {
            try validateRelativePath(androidExtension.export.subfolder)
        }
        guard value.profile.individualEntries.metrics.count <= 256 else {
            throw SharedSetupError.invalid("The individual-entry metric configuration is too large.")
        }
        for (id, config) in value.profile.individualEntries.metrics {
            guard isIdentifier(id) else { throw SharedSetupError.invalid("An individual-entry metric ID is invalid.") }
            if let folder = config.customFolder { try validateRelativePath(folder) }
        }
        guard (1...365).contains(value.profile.schedule.cadence.value),
              (0...23).contains(value.profile.schedule.localTime.hour),
              (0...59).contains(value.profile.schedule.localTime.minute),
              (1...365).contains(value.profile.schedule.lookbackDays) else { throw SharedSetupError.invalid("The schedule intent is out of range.") }
        guard (value.createdBy.platform != .apple || value.platformExtensions.apple != nil),
              (value.createdBy.platform != .android || value.platformExtensions.android != nil),
              value.platformExtensions.apple?.extensionVersion == nil || value.platformExtensions.apple?.extensionVersion == 1,
              value.platformExtensions.android?.extensionVersion == nil || value.platformExtensions.android?.extensionVersion == 1 else {
            throw SharedSetupError.invalid("The writer must include its own versioned platform extension.")
        }
        if let appleSchedule = value.platformExtensions.apple?.schedule {
            guard (1...7).contains(appleSchedule.weekday),
                  ExportSchedule.todayRefreshIntervalOptions.contains(appleSchedule.todayRefreshIntervalHours) else {
                throw SharedSetupError.invalid("A platform extension value is not supported.")
            }
            if value.createdBy.platform == .apple {
                let cadence = value.profile.schedule.cadence
                let cadenceMatches: Bool
                switch appleSchedule.frequency {
                case .daily: cadenceMatches = cadence == .init(value: 1, unit: .days)
                case .weekly: cadenceMatches = cadence == .init(value: 1, unit: .weeks)
                case .custom:
                    let unit: SharedSetupV1.CadenceUnit
                    switch appleSchedule.customUnit {
                    case .days: unit = .days
                    case .weeks: unit = .weeks
                    case .months: unit = .months
                    }
                    cadenceMatches = cadence.unit == unit
                }
                let portableTarget: SharedSetupV1.DesiredTarget = appleSchedule.desiredTarget == .apiEndpoint ? .apiEndpoint : .deviceFolder
                guard cadenceMatches, value.profile.schedule.desiredTarget == portableTarget else {
                    throw SharedSetupError.invalid("The portable and Apple schedule representations contradict each other.")
                }
            }
        }
        let frontmatter = value.profile.presentation.frontmatter
        guard value.profile.presentation.markdown.customText.count <= 65_536,
              (1...6).contains(value.profile.presentation.markdown.headerLevel),
              frontmatter.fields.count <= 256,
              frontmatter.fields.allSatisfy({ isNonEmptyShortString($0.sourceKey) && isNonEmptyShortString($0.outputKey) }),
              frontmatter.customValues.count <= 128,
              frontmatter.customValues.allSatisfy({ isNonEmptyShortString($0.key) && $0.value.count <= 4_096 }),
              frontmatter.placeholders.count <= 128,
              Set(frontmatter.placeholders).count == frontmatter.placeholders.count,
              frontmatter.placeholders.allSatisfy(isNonEmptyShortString),
              isNonEmptyShortString(frontmatter.dateKey), isNonEmptyShortString(frontmatter.typeKey),
              frontmatter.typeValue.count <= 4_096,
              value.platformExtensions.apple.map({ Set($0.export.rollups).count == $0.export.rollups.count }) ?? true else { throw SharedSetupError.invalid("Custom presentation content exceeds setup limits or is not canonical.") }
        if let endpoint = value.profile.apiEndpoint, endpoint.validatedURLString == nil { throw SharedSetupError.invalid("The endpoint hint must be a safe HTTPS host and path without query, fragment, or credentials.") }
    }

    static func validateRelativePath(_ path: String) throws {
        guard path.count <= 4096, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("%"), !path.contains("//"), !path.contains("://"), !path.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ $0 != "." && $0 != ".." }),
              path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else { throw SharedSetupError.invalid("A setup path is unsafe.") }
    }

    static func validateFilename(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", value.count <= 4096, !value.contains("/"), !value.contains("\\"), !value.contains("%"), !value.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }), value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else { throw SharedSetupError.invalid("A filename template is unsafe.") }
    }

    nonisolated static func isIdentifier(_ value: String) -> Bool {
        identifier.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil && value.count <= 128
    }

    nonisolated static func isNonEmptyShortString(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && !value.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
    }

    static func isDNSHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253, host.unicodeScalars.allSatisfy(\.isASCII),
              !host.contains(":"), !host.contains("@") else { return false }
        let isASCIIAlphaNumeric: (UInt8) -> Bool = {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            let bytes = Array(label.utf8)
            return !bytes.isEmpty && bytes.count <= 63 &&
                isASCIIAlphaNumeric(bytes[0]) &&
                isASCIIAlphaNumeric(bytes[bytes.count - 1]) &&
                bytes.allSatisfy { isASCIIAlphaNumeric($0) || $0 == 45 }
        }
    }
}

enum SharedSetupPlaceholderValidator {
    private static let replacements: Set<String> = ["date", "metrics", "sleep_metrics", "activity_metrics", "heart_metrics", "vitals_metrics", "body_metrics", "nutrition_metrics", "mobility_metrics", "mindfulness_metrics", "workout_list"]
    private static let sections: Set<String> = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mobility", "mindfulness", "workouts"]
    private static let tokenRegex = try! NSRegularExpression(pattern: #"\{\{([#/]?)([A-Za-z0-9_]+)\}\}"#)

    static func isSyntacticallyValid(_ text: String) -> Bool {
        let matches = tokenRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var stack: [String] = []
        for match in matches {
            guard let prefixRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text) else { return false }
            let prefix = String(text[prefixRange])
            let name = String(text[nameRange])
            if prefix == "#" {
                guard stack.isEmpty else { return false }
                stack.append(name)
            } else if prefix == "/" {
                guard stack.last == name else { return false }
                stack.removeLast()
            }
        }
        let stripped = tokenRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return stack.isEmpty && !stripped.contains("{{") && !stripped.contains("}}")
    }

    static func isCompatible(_ text: String, dialect _: SharedSetupV1.OriginDialect) -> Bool {
        guard isSyntacticallyValid(text) else { return false }
        let matches = tokenRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.allSatisfy { match in
            guard let prefixRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text) else { return false }
            let prefix = String(text[prefixRange])
            let name = String(text[nameRange])
            return prefix.isEmpty ? replacements.contains(name) : sections.contains(name)
        }
    }
}

struct SharedSetupMetricRegistry {
    let version: Int
    let sha256: String
    let semanticToApple: [String: String]
    let semanticToAndroid: [String: String]
    let equivalence: [String: SharedSetupV1.Equivalence]

    static func current(service: HealthMdCoreService = HealthMdCoreService()) throws -> SharedSetupMetricRegistry {
        let apple = try service.metricRegistry(profile: .appleHealthDataV8)
        let android = try service.metricRegistry(profile: .androidAnalyticalV5)
        guard apple.registryVersion == 1,
              apple.registryVersion == android.registryVersion,
              apple.registrySha256 == android.registrySha256 else {
            throw SharedSetupError.invalid("The bundled Apple and Android metric projections do not share one pinned registry identity.")
        }
        let androidMap = Dictionary(uniqueKeysWithValues: android.metrics.map { ($0.semanticId, $0.selectionId) })
        var equivalence: [String: SharedSetupV1.Equivalence] = [:]
        var semanticToAndroid: [String: String] = [:]
        var semanticToApple: [String: String] = [:]
        for metric in apple.metrics {
            semanticToApple[metric.semanticId] = metric.selectionId
            if let mapped = androidMap[metric.semanticId] { semanticToAndroid[metric.semanticId] = mapped }
            let a = metric.selectionId
            let b = semanticToAndroid[metric.semanticId]
            equivalence[metric.semanticId] = b == nil || a == b ? .platformExactOrUnavailable : .mappedAlias
        }
        for metric in android.metrics where semanticToApple[metric.semanticId] == nil {
            semanticToAndroid[metric.semanticId] = metric.selectionId
            equivalence[metric.semanticId] = metric.semanticId.hasPrefix("android.") ? .platformDistinct : .platformExactOrUnavailable
        }
        return SharedSetupMetricRegistry(version: Int(apple.registryVersion), sha256: apple.registrySha256, semanticToApple: semanticToApple, semanticToAndroid: semanticToAndroid, equivalence: equivalence)
    }
}

enum SharedSetupMapper {
    static func preview(_ document: SharedSetupV1, registry: SharedSetupMetricRegistry? = try? .current()) -> SharedSetupPreview {
        guard let registry else {
            return SharedSetupPreview(document: document, items: [.init(id: "registry", title: "Metrics", detail: "Metric registry is unavailable.", status: .invalid)], supportedMetricSelectionIDs: [], supportedIndividualMetricSelectionIDs: [:], installCustomTemplate: false)
        }
        var items: [SharedSetupCompatibilityItem] = []
        var supported: Set<String> = []
        var ledger: [String: SharedSetupV1.MetricAlias] = [:]
        for alias in document.metricAliases { ledger[alias.semanticID] = alias }
        let sourceRegistryMatches = document.metricRegistry.registryVersion == registry.version &&
            document.metricRegistry.registrySHA256 == registry.sha256
        for semanticID in document.profile.metrics.enabledIDs {
            guard let alias = ledger[semanticID] else {
                items.append(.init(id: "metric.\(semanticID)", title: semanticID, detail: "The metric alias evidence is missing.", status: .invalid))
                continue
            }
            if sourceRegistryMatches,
               alias.appleSelectionID != registry.semanticToApple[semanticID] ||
                alias.androidSelectionID != registry.semanticToAndroid[semanticID] ||
                alias.equivalence != registry.equivalence[semanticID] {
                items.append(.init(id: "metric.\(semanticID)", title: semanticID, detail: "The metric alias evidence does not match the pinned registry.", status: .invalid))
                continue
            }
            guard let selectionID = registry.semanticToApple[semanticID] else {
                items.append(.init(id: "metric.\(semanticID)", title: semanticID, detail: "This metric is not available on this Apple version and will stay unchanged.", status: .requiresAction))
                continue
            }
            supported.insert(selectionID)
        }
        items.append(.init(id: "metrics", title: "Metrics", detail: "\(supported.count) exact metric selections can be applied.", status: .applied))
        items.append(.init(id: "export", title: "Formats and naming", detail: "Formats, naming, units, Daily Notes, and individual entries will replace their portable settings.", status: .applied))

        let template = document.profile.presentation.markdown
        let installTemplate = template.style != .custom ||
            (template.originDialect == .apple && SharedSetupPlaceholderValidator.isSyntacticallyValid(template.customText)) ||
            SharedSetupPlaceholderValidator.isCompatible(template.customText, dialect: template.originDialect)
        if !installTemplate {
            items.append(.init(id: "template", title: "Custom template", detail: "The custom template uses unsupported or malformed placeholders; your current template will remain unchanged.", status: .requiresAction))
        } else if template.style == .custom || !document.profile.presentation.frontmatter.customValues.isEmpty {
            items.append(.init(id: "custom-content", title: "Custom content", detail: "Custom template and frontmatter text is copied verbatim. Review it for personal or secret text.", status: .applied))
        }

        let scheduleExact = exactAppleSchedule(document)
        items.append(.init(id: "schedule", title: "Schedule", detail: scheduleExact == nil ? "This cadence cannot be represented exactly on Apple. Scheduling stays off and your current schedule details remain unchanged." : "Schedule intent will be saved exactly but will remain off until enabled locally.", status: scheduleExact == nil ? .requiresAction : .applied))
        if let endpoint = document.profile.apiEndpoint {
            items.append(.init(id: "endpoint", title: "API endpoint", detail: "\(endpoint.host)\(endpoint.path) requires confirmation; authentication is not included and no existing credential is inherited.", status: .requiresAction))
        }
        if document.platformExtensions.android != nil {
            items.append(.init(id: "android-extension", title: "Android-only settings", detail: "Android compatibility and folder organization are unsupported on Apple and are preserved without being applied.", status: .unsupported))
        }
        items.append(.init(id: "device-setup", title: "Device setup", detail: "Folder access, Apple Health permissions, purchases, credentials, and automation activation still require setup on this device.", status: .requiresAction))

        var individual: [String: SharedSetupV1.IndividualMetric] = [:]
        for (semanticID, value) in document.profile.individualEntries.metrics {
            if let selection = registry.semanticToApple[semanticID] { individual[selection] = value }
            else { items.append(.init(id: "individual.\(semanticID)", title: semanticID, detail: "Individual tracking is unavailable for this metric.", status: .requiresAction)) }
        }
        return SharedSetupPreview(document: document, items: items, supportedMetricSelectionIDs: supported, supportedIndividualMetricSelectionIDs: individual, installCustomTemplate: installTemplate)
    }

    static func exportDocument(
        settings: AdvancedExportSettings,
        schedule: ExportSchedule,
        apiExportSettings: APIExportSettings? = nil,
        appVersion: String,
        preservedAndroidExtension: SharedSetupV1.AndroidExtension? = nil,
        registry: SharedSetupMetricRegistry? = try? .current()
    ) throws -> SharedSetupV1 {
        guard let registry else { throw SharedSetupError.invalid("The metric registry is unavailable.") }
        guard settings.detailPolicy.isLegacyRepresentable else {
            throw SharedSetupError.invalid(
                "Shared Setup v1 cannot represent separate time-series and HealthKit archive choices. Choose Summary or Lossless Health Records before sharing this setup."
            )
        }
        let reverse = Dictionary(uniqueKeysWithValues: registry.semanticToApple.map { ($1, $0) })
        let enabledSemantic = settings.metricSelection.enabledMetrics.compactMap { reverse[$0] }.sorted()
        let aliases = enabledSemantic.map { semantic in
            SharedSetupV1.MetricAlias(semanticID: semantic, equivalence: registry.equivalence[semantic] ?? .platformExactOrUnavailable, appleSelectionID: registry.semanticToApple[semantic], androidSelectionID: registry.semanticToAndroid[semantic])
        }
        let individual = Dictionary(uniqueKeysWithValues: settings.individualTracking.metricConfigs.compactMap { native, config in
            reverse[native].map { ($0, SharedSetupV1.IndividualMetric(enabled: config.trackIndividually, customFolder: config.customFolder)) }
        })
        let frontmatter = settings.formatCustomization.frontmatterConfig
        let markdown = settings.formatCustomization.markdownTemplate
        let customCadenceUnit: SharedSetupV1.CadenceUnit
        switch schedule.customUnit {
        case .day: customCadenceUnit = .days
        case .week: customCadenceUnit = .weeks
        case .month: customCadenceUnit = .months
        }
        let cadence: SharedSetupV1.Cadence
        switch schedule.frequency {
        case .daily: cadence = .init(value: 1, unit: .days)
        case .weekly: cadence = .init(value: 1, unit: .weeks)
        case .custom: cadence = .init(value: schedule.customInterval, unit: customCadenceUnit)
        }
        let appleTarget: SharedSetupV1.AppleDesiredTarget
        switch schedule.target {
        case .localIPhoneFolder: appleTarget = .localIPhoneFolder
        case .connectedMac: appleTarget = .connectedMac
        case .apiEndpoint: appleTarget = .apiEndpoint
        }
        let appleFrequency: SharedSetupV1.AppleFrequency
        switch schedule.frequency {
        case .daily: appleFrequency = .daily
        case .weekly: appleFrequency = .weekly
        case .custom: appleFrequency = .custom
        }
        let appleCustomUnit: SharedSetupV1.AppleCustomUnit
        switch schedule.customUnit {
        case .day: appleCustomUnit = .days
        case .week: appleCustomUnit = .weeks
        case .month: appleCustomUnit = .months
        }
        let profileTarget: SharedSetupV1.DesiredTarget = schedule.target == .apiEndpoint ? .apiEndpoint : .deviceFolder
        let originDialect: SharedSetupV1.OriginDialect = markdown.style == .custom &&
            !SharedSetupPlaceholderValidator.isCompatible(markdown.customTemplate, dialect: .portable)
            ? .apple
            : .portable
        let androidExtension = preservedAndroidExtension
        return SharedSetupV1(
            schema: SharedSetupV1.schemaName, schemaVersion: 1,
            createdBy: .init(platform: .apple, appVersion: appVersion),
            metricRegistry: .init(schema: "healthmd.metric_registry", registryVersion: registry.version, registrySHA256: registry.sha256),
            profile: .init(
                export: .init(formats: settings.exportFormats.compactMap(sharedFormat).sorted { $0.rawValue < $1.rawValue }, includeMetadata: settings.includeMetadata, groupByCategory: settings.groupByCategory, filenameTemplate: settings.filenameFormat, folderTemplate: settings.folderStructure, writeMode: sharedWriteMode(settings.writeMode), includeGranularData: settings.includeGranularData),
                metrics: .init(enabledIDs: enabledSemantic),
                presentation: .init(dateFormat: sharedDate(settings.formatCustomization.dateFormat), timeFormat: sharedTime(settings.formatCustomization.timeFormat), units: settings.formatCustomization.unitPreference == .metric ? .metric : .imperial, frontmatter: .init(fields: frontmatter.fields.map { .init(sourceKey: $0.originalKey, outputKey: $0.customKey, enabled: $0.isEnabled) }, customValues: frontmatter.customFields, placeholders: frontmatter.placeholderFields, includeDate: frontmatter.includeDate, includeType: frontmatter.includeType, dateKey: frontmatter.customDateKey, typeKey: frontmatter.customTypeKey, typeValue: frontmatter.customTypeValue, keyStyle: frontmatter.keyStyle == .snakeCase ? .snakeCase : .camelCase), markdown: .init(style: sharedMarkdownStyle(markdown.style), customText: markdown.customTemplate, headerLevel: markdown.sectionHeaderLevel, useEmoji: markdown.useEmoji, includeSummary: markdown.includeSummary, bulletStyle: sharedBullet(markdown.bulletStyle), originDialect: originDialect)),
                individualEntries: .init(enabled: settings.individualTracking.globalEnabled, metrics: individual, entriesFolder: settings.individualTracking.entriesFolder, organizeByCategory: settings.individualTracking.useCategoryFolders, filenameTemplate: settings.individualTracking.filenameTemplate),
                dailyNotes: .init(enabled: settings.dailyNoteInjection.enabled, folder: settings.dailyNoteInjection.folderPath, filenameTemplate: settings.dailyNoteInjection.filenamePattern, createIfMissing: settings.dailyNoteInjection.createIfMissing, injectSections: settings.dailyNoteInjection.injectMarkdownSections),
                schedule: .init(activationRequested: schedule.isEnabled, cadence: cadence, localTime: .init(hour: schedule.preferredHour, minute: schedule.preferredMinute), lookbackDays: schedule.lookbackDays, dateWindow: .pastCompleteDays, desiredTarget: profileTarget),
                apiEndpoint: endpointHint(apiExportSettings)
            ),
            metricAliases: aliases,
            platformExtensions: .init(
                // Shared Setup v1 can express only historical calendar windows. A v9 range
                // summary has different identity and missing-edge semantics, so omit it rather
                // than serializing the range toggle as weekly/monthly/yearly behavior.
                apple: .init(extensionVersion: 1, export: .init(organizeFormatsIntoFolders: settings.organizeFormatsIntoFolders, archiveFiles: settings.archiveExportFiles, includeDataDictionary: settings.includeDataDictionary, summaryOnly: settings.summaryOnlyExport, rollups: []), dailyNotes: .init(only: settings.dailyNoteInjection.dailyNotesOnly), schedule: .init(frequency: appleFrequency, customUnit: appleCustomUnit, weekday: schedule.weekday, todayRefreshRequested: schedule.todayRefreshEnabled, todayRefreshIntervalHours: schedule.todayRefreshIntervalHours, desiredTarget: appleTarget)),
                android: androidExtension
            )
        )
    }

    static func portableSnapshot(from preview: SharedSetupPreview, preservingTemplateFrom current: AdvancedExportSettings) -> SharedSetupPortableSnapshot {
        let document = preview.document
        let format = document.profile.presentation
        let currentMarkdown = current.formatCustomization.markdownTemplate
        let apple = document.platformExtensions.apple
        let detailPolicy: AppleExportDetailPolicy = document.profile.export.includeGranularData
            ? .lossless
            : .summary
        return SharedSetupPortableSnapshot(
            exportFormats: Set(document.profile.export.formats.compactMap(nativeFormat)), includeMetadata: document.profile.export.includeMetadata, groupByCategory: document.profile.export.groupByCategory, filenameFormat: document.profile.export.filenameTemplate, folderStructure: document.profile.export.folderTemplate, organizeFormatsIntoFolders: apple?.export.organizeFormatsIntoFolders ?? current.organizeFormatsIntoFolders, archiveExportFiles: apple?.export.archiveFiles ?? current.archiveExportFiles, includeDataDictionary: apple?.export.includeDataDictionary ?? current.includeDataDictionary, summaryOnlyExport: apple?.export.summaryOnly ?? current.summaryOnlyExport, writeMode: nativeWriteMode(document.profile.export.writeMode), includeGranularData: document.profile.export.includeGranularData, compatibilityDetail: detailPolicy.compatibilityDetail, healthKitSourceArchivePolicy: detailPolicy.healthKitSourceArchive, generateWeeklyRollups: current.generateRangeSummary, generateMonthlyRollups: current.generateRangeSummary, generateYearlyRollups: current.generateRangeSummary,
            metricSelectionIDs: preview.supportedMetricSelectionIDs,
            dateFormat: nativeDate(format.dateFormat), timeFormat: nativeTime(format.timeFormat), unitPreference: format.units == .metric ? .metric : .imperial,
            frontmatter: .init(fields: format.frontmatter.fields.map { .init(originalKey: $0.sourceKey, customKey: $0.outputKey, isEnabled: $0.enabled) }, customFields: format.frontmatter.customValues, placeholderFields: format.frontmatter.placeholders, includeDate: format.frontmatter.includeDate, includeType: format.frontmatter.includeType, customDateKey: format.frontmatter.dateKey, customTypeKey: format.frontmatter.typeKey, customTypeValue: format.frontmatter.typeValue, keyStyle: format.frontmatter.keyStyle == .snakeCase ? .snakeCase : .camelCase),
            frontmatterPreservesExactFieldSet: true,
            markdownTemplate: preview.installCustomTemplate ? .init(style: nativeMarkdownStyle(format.markdown.style), customTemplate: format.markdown.customText, sectionHeaderLevel: format.markdown.headerLevel, useEmoji: format.markdown.useEmoji, includeSummary: format.markdown.includeSummary, bulletStyle: nativeBullet(format.markdown.bulletStyle)) : currentMarkdown,
            individualTracking: .init(globalEnabled: document.profile.individualEntries.enabled, metricConfigs: preview.supportedIndividualMetricSelectionIDs.mapValues { .init(trackIndividually: $0.enabled, customFolder: $0.customFolder) }, entriesFolder: document.profile.individualEntries.entriesFolder, useCategoryFolders: document.profile.individualEntries.organizeByCategory, filenameTemplate: document.profile.individualEntries.filenameTemplate),
            dailyNotes: .init(enabled: document.profile.dailyNotes.enabled, folderPath: document.profile.dailyNotes.folder, filenamePattern: document.profile.dailyNotes.filenameTemplate, createIfMissing: document.profile.dailyNotes.createIfMissing, injectMarkdownSections: document.profile.dailyNotes.injectSections, dailyNotesOnly: apple?.dailyNotes.only ?? current.dailyNoteInjection.dailyNotesOnly)
        )
    }

    static func exactAppleSchedule(_ document: SharedSetupV1) -> ExportSchedule? {
        let profile = document.profile.schedule
        let cadence = profile.cadence
        guard profile.dateWindow == .pastCompleteDays,
              profile.lookbackDays <= ExportSchedule.maximumLookbackDays else { return nil }
        if document.createdBy.platform == .android && document.platformExtensions.apple == nil {
            // Android's public daily cadence and local time are exact on Apple when no preserved
            // Apple extension exists. Weekly/monthly recurrence needs an Apple weekday/anchor that
            // the portable profile intentionally does not invent, so it is never approximated.
            guard cadence == .init(value: 1, unit: .days) else { return nil }
            let target: ExportTargetSelection = profile.desiredTarget == .apiEndpoint
                ? .apiEndpoint
                : .localIPhoneFolder
            return ExportSchedule(
                isEnabled: false,
                frequency: .daily,
                customInterval: 1,
                customUnit: .day,
                preferredHour: profile.localTime.hour,
                preferredMinute: profile.localTime.minute,
                weekday: 1,
                target: target,
                lookbackDays: profile.lookbackDays,
                todayRefreshEnabled: false,
                todayRefreshIntervalHours: 3,
                lastExportDate: nil,
                lastTodayRefreshDate: nil,
                enabledAt: nil
            )
        }
        guard let ext = document.platformExtensions.apple?.schedule else { return nil }
        let cadenceUnit: SharedSetupV1.CadenceUnit
        switch ext.customUnit {
        case .days: cadenceUnit = .days
        case .weeks: cadenceUnit = .weeks
        case .months: cadenceUnit = .months
        }
        let expected: SharedSetupV1.Cadence
        switch ext.frequency {
        case .daily: expected = .init(value: 1, unit: .days)
        case .weekly: expected = .init(value: 1, unit: .weeks)
        case .custom: expected = .init(value: cadence.value, unit: cadenceUnit)
        }
        guard cadence == expected,
              (1...7).contains(ext.weekday), ExportSchedule.todayRefreshIntervalOptions.contains(ext.todayRefreshIntervalHours) else { return nil }
        let target: ExportTargetSelection
        switch ext.desiredTarget {
        case .localIPhoneFolder: target = .localIPhoneFolder
        case .connectedMac: target = .connectedMac
        case .apiEndpoint: target = .apiEndpoint
        }
        guard document.profile.schedule.desiredTarget == (target == .apiEndpoint ? .apiEndpoint : .deviceFolder) else { return nil }
        let frequency: ScheduleFrequency
        switch ext.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .custom: frequency = .custom
        }
        let customUnit: ScheduleIntervalUnit
        switch ext.customUnit {
        case .days: customUnit = .day
        case .weeks: customUnit = .week
        case .months: customUnit = .month
        }
        return ExportSchedule(isEnabled: false, frequency: frequency, customInterval: cadence.value, customUnit: customUnit, preferredHour: document.profile.schedule.localTime.hour, preferredMinute: document.profile.schedule.localTime.minute, weekday: ext.weekday, target: target, lookbackDays: document.profile.schedule.lookbackDays, todayRefreshEnabled: ext.todayRefreshRequested, todayRefreshIntervalHours: ext.todayRefreshIntervalHours, lastExportDate: nil, lastTodayRefreshDate: nil, enabledAt: nil)
    }

    private static func endpointHint(_ settings: APIExportSettings?) -> SharedSetupV1.APIEndpoint? {
        guard let url = settings?.endpointURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host, SharedSetupValidation.isDNSHost(host) else { return nil }
        components.user = nil
        components.password = nil
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard !path.contains("%") else { return nil }
        let queryOmitted = components.query != nil
        components.query = nil
        components.fragment = nil
        let endpoint = SharedSetupV1.APIEndpoint(
            scheme: "https",
            host: host,
            port: components.port,
            path: path,
            queryOmitted: queryOmitted,
            credentialsRequired: true
        )
        return endpoint.validatedURLString == nil ? nil : endpoint
    }

    private nonisolated static func nativeFormat(_ value: SharedSetupV1.Format) -> ExportFormat? { switch value { case .markdown: .markdown; case .obsidianBases: .obsidianBases; case .json: .json; case .csv: .csv } }
    private nonisolated static func sharedFormat(_ value: ExportFormat) -> SharedSetupV1.Format? { switch value { case .markdown: .markdown; case .obsidianBases: .obsidianBases; case .json: .json; case .csv: .csv } }
    private static func nativeWriteMode(_ value: SharedSetupV1.SharedWriteMode) -> WriteMode { switch value { case .overwrite: .overwrite; case .append: .append; case .update: .update } }
    private static func sharedWriteMode(_ value: WriteMode) -> SharedSetupV1.SharedWriteMode { switch value { case .overwrite: .overwrite; case .append: .append; case .update: .update } }
    private static func nativeDate(_ value: SharedSetupV1.DateFormat) -> DateFormatPreference { switch value { case .iso8601: .iso8601; case .usShort: .usShort; case .usLong: .usLong; case .euShort: .euShort; case .euLong: .euLong; case .compact: .compact; case .friendly: .friendly } }
    private static func sharedDate(_ value: DateFormatPreference) -> SharedSetupV1.DateFormat { switch value { case .iso8601: .iso8601; case .usShort: .usShort; case .usLong: .usLong; case .euShort: .euShort; case .euLong: .euLong; case .compact: .compact; case .friendly: .friendly } }
    private static func nativeTime(_ value: SharedSetupV1.TimeFormat) -> TimeFormatPreference { switch value { case .hour24: .hour24; case .hour24Seconds: .hour24WithSeconds; case .hour12: .hour12; case .hour12Seconds: .hour12WithSeconds } }
    private static func sharedTime(_ value: TimeFormatPreference) -> SharedSetupV1.TimeFormat { switch value { case .hour24: .hour24; case .hour24WithSeconds: .hour24Seconds; case .hour12: .hour12; case .hour12WithSeconds: .hour12Seconds } }
    private static func nativeMarkdownStyle(_ value: SharedSetupV1.MarkdownStyle) -> MarkdownTemplateStyle { switch value { case .standard: .standard; case .compact: .compact; case .detailed: .detailed; case .custom: .custom } }
    private static func sharedMarkdownStyle(_ value: MarkdownTemplateStyle) -> SharedSetupV1.MarkdownStyle { switch value { case .standard: .standard; case .compact: .compact; case .detailed: .detailed; case .custom: .custom } }
    private static func nativeBullet(_ value: SharedSetupV1.BulletStyle) -> MarkdownTemplateConfig.BulletStyle { switch value { case .dash: .dash; case .asterisk: .asterisk; case .plus: .plus } }
    private static func sharedBullet(_ value: MarkdownTemplateConfig.BulletStyle) -> SharedSetupV1.BulletStyle { switch value { case .dash: .dash; case .asterisk: .asterisk; case .plus: .plus } }
}

struct SharedSetupPortableSnapshot: Codable, Equatable {
    var exportFormats: Set<ExportFormat>
    var includeMetadata: Bool
    var groupByCategory: Bool
    var filenameFormat: String
    var folderStructure: String
    var organizeFormatsIntoFolders: Bool
    var archiveExportFiles: Bool
    var includeDataDictionary: Bool
    var summaryOnlyExport: Bool
    var writeMode: WriteMode
    var includeGranularData: Bool
    var compatibilityDetail: ExportCompatibilityDetail? = nil
    var healthKitSourceArchivePolicy: HealthKitSourceArchivePolicy? = nil
    var generateWeeklyRollups: Bool
    var generateMonthlyRollups: Bool
    var generateYearlyRollups: Bool
    var metricSelectionIDs: Set<String>
    var dateFormat: DateFormatPreference
    var timeFormat: TimeFormatPreference
    var unitPreference: UnitPreference
    var frontmatter: FrontmatterConfigurationSnapshot
    var frontmatterPreservesExactFieldSet: Bool
    var markdownTemplate: MarkdownTemplateConfig
    var individualTracking: IndividualTrackingSnapshot
    var dailyNotes: DailyNoteInjectionSnapshot

    var detailPolicy: AppleExportDetailPolicy {
        if let compatibilityDetail, let healthKitSourceArchivePolicy {
            return AppleExportDetailPolicy(
                compatibilityDetail: compatibilityDetail,
                healthKitSourceArchive: healthKitSourceArchivePolicy
            )
        }
        return includeGranularData ? .lossless : .summary
    }

    static func capture(_ settings: AdvancedExportSettings) -> SharedSetupPortableSnapshot {
        SharedSetupPortableSnapshot(exportFormats: settings.exportFormats, includeMetadata: settings.includeMetadata, groupByCategory: settings.groupByCategory, filenameFormat: settings.filenameFormat, folderStructure: settings.folderStructure, organizeFormatsIntoFolders: settings.organizeFormatsIntoFolders, archiveExportFiles: settings.archiveExportFiles, includeDataDictionary: settings.includeDataDictionary, summaryOnlyExport: settings.summaryOnlyExport, writeMode: settings.writeMode, includeGranularData: settings.detailPolicy.legacyIncludeGranularData, compatibilityDetail: settings.compatibilityDetail, healthKitSourceArchivePolicy: settings.healthKitSourceArchivePolicy, generateWeeklyRollups: settings.generateWeeklyRollups, generateMonthlyRollups: settings.generateMonthlyRollups, generateYearlyRollups: settings.generateYearlyRollups, metricSelectionIDs: settings.metricSelection.enabledMetrics, dateFormat: settings.formatCustomization.dateFormat, timeFormat: settings.formatCustomization.timeFormat, unitPreference: settings.formatCustomization.unitPreference, frontmatter: .from(settings.formatCustomization.frontmatterConfig), frontmatterPreservesExactFieldSet: settings.formatCustomization.frontmatterConfig.preservesExactFieldSet, markdownTemplate: settings.formatCustomization.markdownTemplate, individualTracking: .from(settings.individualTracking), dailyNotes: .from(settings.dailyNoteInjection))
    }
}

private extension MarkdownTemplateConfig {
    init(style: MarkdownTemplateStyle, customTemplate: String, sectionHeaderLevel: Int, useEmoji: Bool, includeSummary: Bool, bulletStyle: BulletStyle) {
        self.style = style; self.customTemplate = customTemplate; self.sectionHeaderLevel = sectionHeaderLevel; self.useEmoji = useEmoji; self.includeSummary = includeSummary; self.bulletStyle = bulletStyle
    }
}

