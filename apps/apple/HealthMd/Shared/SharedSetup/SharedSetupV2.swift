import CoreFoundation
import Foundation

// Dedicated public DTOs for healthmd.shared_setup v2. The v2 writer is a closed
// allowlist: these types contain no opaque payload slot and decoding unknown,
// bounded optional fields never makes those fields available for re-export.
struct SharedSetupV2: Codable, Equatable, Sendable {
    static let schemaName = "healthmd.shared_setup"
    static let schemaVersion = 2
    nonisolated static let maximumEncodedBytes = 4_194_304
    nonisolated static let maximumProfiles = 100

    var schema: String
    var schemaVersion: Int
    var createdBy: CreatedBy
    var metricRegistry: MetricRegistry
    var profiles: [Profile]
    var activeProfile: String
    var metricAliases: [MetricAlias]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case createdBy = "created_by"
        case metricRegistry = "metric_registry"
        case profiles
        case activeProfile = "active_profile"
        case metricAliases = "metric_aliases"
    }

    struct CreatedBy: Codable, Equatable, Sendable {
        var platform: Platform
        var appVersion: String

        enum CodingKeys: String, CodingKey {
            case platform
            case appVersion = "app_version"
        }
    }

    enum Platform: String, Codable, Hashable, Sendable {
        case apple
        case android
    }

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

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(semanticID, forKey: .semanticID)
            try container.encode(equivalence, forKey: .equivalence)
            if let appleSelectionID {
                try container.encode(appleSelectionID, forKey: .appleSelectionID)
            } else {
                try container.encodeNil(forKey: .appleSelectionID)
            }
            if let androidSelectionID {
                try container.encode(androidSelectionID, forKey: .androidSelectionID)
            } else {
                try container.encodeNil(forKey: .androidSelectionID)
            }
        }
    }

    enum Equivalence: String, Codable, Hashable, Sendable {
        case platformExactOrUnavailable = "platform_exact_or_unavailable"
        case mappedAlias = "mapped_alias"
        case platformDistinct = "platform_distinct"
    }

    struct Profile: Codable, Equatable, Sendable {
        var bundleID: String
        var name: String
        var export: Export
        var metrics: Metrics
        var presentation: Presentation
        var individualEntries: IndividualEntries
        var dailyNotes: DailyNotes
        var destination: Destination
        var schedule: Schedule?
        var platformExtensions: PlatformExtensions

        enum CodingKeys: String, CodingKey {
            case bundleID = "bundle_id"
            case name
            case export
            case metrics
            case presentation
            case individualEntries = "individual_entries"
            case dailyNotes = "daily_notes"
            case destination
            case schedule
            case platformExtensions = "platform_extensions"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(bundleID, forKey: .bundleID)
            try container.encode(name, forKey: .name)
            try container.encode(export, forKey: .export)
            try container.encode(metrics, forKey: .metrics)
            try container.encode(presentation, forKey: .presentation)
            try container.encode(individualEntries, forKey: .individualEntries)
            try container.encode(dailyNotes, forKey: .dailyNotes)
            try container.encode(destination, forKey: .destination)
            if let schedule {
                try container.encode(schedule, forKey: .schedule)
            } else {
                try container.encodeNil(forKey: .schedule)
            }
            try container.encode(platformExtensions, forKey: .platformExtensions)
        }
    }

    struct Export: Codable, Equatable, Sendable {
        var formats: [Format]
        var includeMetadata: Bool
        var groupByCategory: Bool
        var filenameTemplate: String
        var folderTemplate: String
        var writeMode: SharedWriteMode
        var compatibilityDetail: CompatibilityDetail

        enum CodingKeys: String, CodingKey {
            case formats
            case includeMetadata = "include_metadata"
            case groupByCategory = "group_by_category"
            case filenameTemplate = "filename_template"
            case folderTemplate = "folder_template"
            case writeMode = "write_mode"
            case compatibilityDetail = "compatibility_detail"
        }
    }

    enum Format: String, Codable, Hashable, Sendable {
        case csv
        case json
        case markdown
        case obsidianBases = "obsidian_bases"
    }

    enum SharedWriteMode: String, Codable, Hashable, Sendable {
        case overwrite
        case append
        case update
    }

    enum CompatibilityDetail: String, Codable, Hashable, Sendable {
        case summary
        case selectedTimeSeries = "selected_time_series"
    }

    struct Metrics: Codable, Equatable, Sendable {
        var enabledIDs: [String]

        enum CodingKeys: String, CodingKey {
            case enabledIDs = "enabled_ids"
        }
    }

    // v2 deliberately owns this presentation grammar even though its current
    // wire shape matches v1. Future v1 compatibility must not be retrofitted.
    struct Presentation: Codable, Equatable, Sendable {
        var dateFormat: DateFormat
        var timeFormat: TimeFormat
        var units: Units
        var frontmatter: Frontmatter
        var markdown: Markdown

        enum CodingKeys: String, CodingKey {
            case dateFormat = "date_format"
            case timeFormat = "time_format"
            case units
            case frontmatter
            case markdown
        }
    }

    enum DateFormat: String, Codable, Hashable, Sendable {
        case iso8601
        case usShort = "us_short"
        case usLong = "us_long"
        case euShort = "eu_short"
        case euLong = "eu_long"
        case compact
        case friendly
    }

    enum TimeFormat: String, Codable, Hashable, Sendable {
        case hour24 = "hour_24"
        case hour24Seconds = "hour_24_seconds"
        case hour12 = "hour_12"
        case hour12Seconds = "hour_12_seconds"
    }

    enum Units: String, Codable, Hashable, Sendable {
        case metric
        case imperial
    }

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
            case fields
            case customValues = "custom_values"
            case placeholders
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

    enum KeyStyle: String, Codable, Hashable, Sendable {
        case snakeCase = "snake_case"
        case camelCase = "camel_case"
    }

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

    enum MarkdownStyle: String, Codable, Hashable, Sendable {
        case standard
        case compact
        case detailed
        case custom
    }

    enum BulletStyle: String, Codable, Hashable, Sendable {
        case dash
        case asterisk
        case plus
    }

    enum OriginDialect: String, Codable, Hashable, Sendable {
        case portable
        case apple
        case android
    }

    struct IndividualEntries: Codable, Equatable, Sendable {
        var enabled: Bool
        var metrics: [String: IndividualMetric]
        var entriesFolder: String
        var organizeByCategory: Bool
        var filenameTemplate: String

        enum CodingKeys: String, CodingKey {
            case enabled
            case metrics
            case entriesFolder = "entries_folder"
            case organizeByCategory = "organize_by_category"
            case filenameTemplate = "filename_template"
        }
    }

    struct IndividualMetric: Codable, Equatable, Sendable {
        var enabled: Bool
        var customFolder: String?

        enum CodingKeys: String, CodingKey {
            case enabled
            case customFolder = "custom_folder"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
            if let customFolder {
                try container.encode(customFolder, forKey: .customFolder)
            } else {
                try container.encodeNil(forKey: .customFolder)
            }
        }
    }

    struct DailyNotes: Codable, Equatable, Sendable {
        var enabled: Bool
        var folder: String
        var filenameTemplate: String
        var createIfMissing: Bool
        var injectSections: Bool

        enum CodingKeys: String, CodingKey {
            case enabled
            case folder
            case filenameTemplate = "filename_template"
            case createIfMissing = "create_if_missing"
            case injectSections = "inject_sections"
        }
    }

    struct Destination: Codable, Equatable, Sendable {
        var kind: DestinationKind
        var apiEndpoint: APIEndpoint?

        enum CodingKeys: String, CodingKey {
            case kind
            case apiEndpoint = "api_endpoint"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            if let apiEndpoint {
                try container.encode(apiEndpoint, forKey: .apiEndpoint)
            } else {
                try container.encodeNil(forKey: .apiEndpoint)
            }
        }
    }

    enum DestinationKind: String, Codable, Hashable, Sendable {
        case deviceFolder = "device_folder"
        case connectedMac = "connected_mac"
        case apiEndpoint = "api_endpoint"
        case cloud
    }

    struct APIEndpoint: Codable, Equatable, Sendable {
        var scheme: String
        var host: String
        var port: Int?
        var path: String
        var queryOmitted: Bool
        var credentialsRequired: Bool

        enum CodingKeys: String, CodingKey {
            case scheme
            case host
            case port
            case path
            case queryOmitted = "query_omitted"
            case credentialsRequired = "credentials_required"
        }

        var validatedURLString: String? {
            SharedSetupV2Validation.validatedURLString(for: self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scheme, forKey: .scheme)
            try container.encode(host, forKey: .host)
            if let port {
                try container.encode(port, forKey: .port)
            } else {
                try container.encodeNil(forKey: .port)
            }
            try container.encode(path, forKey: .path)
            try container.encode(queryOmitted, forKey: .queryOmitted)
            try container.encode(credentialsRequired, forKey: .credentialsRequired)
        }
    }

    struct Schedule: Codable, Equatable, Sendable {
        var activationRequested: Bool
        var cadence: Cadence
        var localTime: LocalTime
        var weekday: Int
        var lookbackDays: Int
        var dateWindow: DateWindow

        enum CodingKeys: String, CodingKey {
            case activationRequested = "activation_requested"
            case cadence
            case localTime = "local_time"
            case weekday
            case lookbackDays = "lookback_days"
            case dateWindow = "date_window"
        }
    }

    struct Cadence: Codable, Equatable, Sendable {
        var value: Int
        var unit: CadenceUnit
        var anchorDate: String

        enum CodingKeys: String, CodingKey {
            case value
            case unit
            case anchorDate = "anchor_date"
        }
    }

    enum CadenceUnit: String, Codable, Hashable, Sendable {
        case days
        case weeks
        case months
    }

    struct LocalTime: Codable, Equatable, Sendable {
        var hour: Int
        var minute: Int
    }

    enum DateWindow: String, Codable, Hashable, Sendable {
        case pastCompleteDays = "past_complete_days"
    }

    struct PlatformExtensions: Codable, Equatable, Sendable {
        var apple: AppleExtension?
        var android: AndroidExtension?

        enum CodingKeys: String, CodingKey {
            case apple
            case android
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let apple {
                try container.encode(apple, forKey: .apple)
            } else {
                try container.encodeNil(forKey: .apple)
            }
            if let android {
                try container.encode(android, forKey: .android)
            } else {
                try container.encodeNil(forKey: .android)
            }
        }
    }

    struct AppleExtension: Codable, Equatable, Sendable {
        var extensionVersion: Int
        var export: AppleExport
        var dailyNotes: AppleDailyNotes
        var schedule: AppleSchedule?

        enum CodingKeys: String, CodingKey {
            case extensionVersion = "extension_version"
            case export
            case dailyNotes = "daily_notes"
            case schedule
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(extensionVersion, forKey: .extensionVersion)
            try container.encode(export, forKey: .export)
            try container.encode(dailyNotes, forKey: .dailyNotes)
            if let schedule {
                try container.encode(schedule, forKey: .schedule)
            } else {
                try container.encodeNil(forKey: .schedule)
            }
        }
    }

    struct AppleExport: Codable, Equatable, Sendable {
        var organizeFormatsIntoFolders: Bool
        var archiveFiles: Bool
        var includeDataDictionary: Bool
        var summaryOnly: Bool
        var healthKitSourceArchive: HealthKitSourceArchive
        var generateRangeSummary: Bool

        enum CodingKeys: String, CodingKey {
            case organizeFormatsIntoFolders = "organize_formats_into_folders"
            case archiveFiles = "archive_files"
            case includeDataDictionary = "include_data_dictionary"
            case summaryOnly = "summary_only"
            case healthKitSourceArchive = "healthkit_source_archive"
            case generateRangeSummary = "generate_range_summary"
        }
    }

    enum HealthKitSourceArchive: String, Codable, Hashable, Sendable {
        case none
        case canonicalV1 = "canonical_v1"
    }

    struct AppleDailyNotes: Codable, Equatable, Sendable {
        var only: Bool
    }

    struct AppleSchedule: Codable, Equatable, Sendable {
        var frequency: AppleFrequency
        var customUnit: AppleCustomUnit
        var todayRefreshRequested: Bool
        var todayRefreshIntervalHours: Int

        enum CodingKeys: String, CodingKey {
            case frequency
            case customUnit = "custom_unit"
            case todayRefreshRequested = "today_refresh_requested"
            case todayRefreshIntervalHours = "today_refresh_interval_hours"
        }
    }

    enum AppleFrequency: String, Codable, Hashable, Sendable {
        case daily
        case weekly
        case custom
    }

    enum AppleCustomUnit: String, Codable, Hashable, Sendable {
        case days
        case weeks
        case months
    }

    struct AndroidExtension: Codable, Equatable, Sendable {
        var extensionVersion: Int
        var export: AndroidExport

        enum CodingKeys: String, CodingKey {
            case extensionVersion = "extension_version"
            case export
        }
    }

    struct AndroidExport: Codable, Equatable, Sendable {
        var mode: AndroidMode
        var legacyPrimaryFormat: AndroidLegacyPrimaryFormat
        var compatibilityProfile: AndroidCompatibilityProfile
        var includeLegacyAliases: Bool
        var includeAndroidNativeFields: Bool
        var legacyDataTypes: AndroidLegacyDataTypes
        var subfolder: String
        var folderOrganization: AndroidFolderOrganization
        var rawSnapshot: AndroidRawSnapshot

        enum CodingKeys: String, CodingKey {
            case mode
            case legacyPrimaryFormat = "legacy_primary_format"
            case compatibilityProfile = "compatibility_profile"
            case includeLegacyAliases = "include_legacy_aliases"
            case includeAndroidNativeFields = "include_android_native_fields"
            case legacyDataTypes = "legacy_data_types"
            case subfolder
            case folderOrganization = "folder_organization"
            case rawSnapshot = "raw_snapshot"
        }
    }

    enum AndroidMode: String, Codable, Hashable, Sendable {
        case compatibility
        case rawSnapshot = "raw_snapshot"
    }

    enum AndroidLegacyPrimaryFormat: String, Codable, Hashable, Sendable {
        case markdown
        case obsidianBases = "obsidian_bases"
        case json
        case csv
    }

    enum AndroidCompatibilityProfile: String, Codable, Hashable, Sendable {
        case frozenV4 = "frozen_v4"
        case analyticalV5 = "analytical_v5"
    }

    struct AndroidLegacyDataTypes: Codable, Equatable, Sendable {
        var sleep: Bool
        var activity: Bool
        var heart: Bool
        var vitals: Bool
        var body: Bool
        var nutrition: Bool
        var mobility: Bool
        var reproductiveHealth: Bool
        var mindfulness: Bool
        var workouts: Bool
        var plannedWorkouts: Bool
        var medicalResources: Bool

        enum CodingKeys: String, CodingKey {
            case sleep
            case activity
            case heart
            case vitals
            case body
            case nutrition
            case mobility
            case reproductiveHealth = "reproductive_health"
            case mindfulness
            case workouts
            case plannedWorkouts = "planned_workouts"
            case medicalResources = "medical_resources"
        }
    }

    enum AndroidFolderOrganization: String, Codable, Hashable, Sendable {
        case flat
        case byYear = "by_year"
        case byMonth = "by_month"
        case byYearMonth = "by_year_month"
    }

    struct AndroidRawSnapshot: Codable, Equatable, Sendable {
        var format: AndroidRawFormat
        var scope: AndroidRawScope
        var includeExerciseRoutes: Bool
        var pageSize: Int

        enum CodingKeys: String, CodingKey {
            case format
            case scope
            case includeExerciseRoutes = "include_exercise_routes"
            case pageSize = "page_size"
        }
    }

    enum AndroidRawFormat: String, Codable, Hashable, Sendable {
        case json
        case ndjson
    }

    enum AndroidRawScope: String, Codable, Hashable, Sendable {
        case selectedRecordTypes = "selected_record_types"
        case allAuthorizedSupportedData = "all_authorized_supported_data"
    }
}

enum SharedSetupV2Error: LocalizedError, Equatable {
    case oversized(maximumBytes: Int)
    case malformed(String)
    case invalid(String)
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .oversized(let maximumBytes):
            "This setup file is larger than the supported \(maximumBytes)-byte limit."
        case .malformed(let reason), .invalid(let reason):
            reason
        case .unsupportedVersion:
            "This Health.md setup version is not supported."
        }
    }
}

enum SharedSetupVersionedDocument: Equatable, Sendable {
    case v1(SharedSetupV1)
    case v2(SharedSetupV2)
}

/// Strict shared-setup dispatcher. It performs only a bounded generic parse to
/// discover the discriminator, then applies the selected version's recursive
/// preflight before any typed decode.
enum SharedSetupVersionedCodec {
    static func decode(_ data: Data) throws -> SharedSetupVersionedDocument {
        guard data.count <= SharedSetupV2.maximumEncodedBytes else {
            throw SharedSetupV2Error.oversized(maximumBytes: SharedSetupV2.maximumEncodedBytes)
        }
        let version = try SharedSetupV2JSONPreflight.strictVersion(in: data)
        switch version {
        case SharedSetupV1.schemaVersion:
            guard data.count <= SharedSetupV1.maximumEncodedBytes else {
                throw SharedSetupError.oversized
            }
            // SharedSetupCodec performs the historical v1 depth/container/node
            // preflight before decoding and preserves the 256 KiB contract.
            return .v1(try SharedSetupCodec.decode(data))
        case SharedSetupV2.schemaVersion:
            return .v2(try SharedSetupV2Codec.decode(data))
        default:
            throw SharedSetupV2Error.unsupportedVersion
        }
    }

    static func encode(_ document: SharedSetupVersionedDocument) throws -> Data {
        switch document {
        case .v1(let document):
            // Keep the historical v1 encoder byte-for-byte unchanged.
            return try SharedSetupCodec.encode(document)
        case .v2(let document):
            return try SharedSetupV2Codec.encode(document)
        }
    }
}

enum SharedSetupV2Codec {
    static func decode(_ data: Data) throws -> SharedSetupV2 {
        guard data.count <= SharedSetupV2.maximumEncodedBytes else {
            throw SharedSetupV2Error.oversized(maximumBytes: SharedSetupV2.maximumEncodedBytes)
        }
        try SharedSetupV2JSONPreflight.preflightV2(data)
        let document: SharedSetupV2
        do {
            document = try JSONDecoder().decode(SharedSetupV2.self, from: data)
        } catch {
            throw SharedSetupV2Error.malformed("This is not a valid Health.md Shared Setup v2 file.")
        }
        try SharedSetupV2Validation.validate(document)
        return document
    }

    static func encode(_ document: SharedSetupV2) throws -> Data {
        try SharedSetupV2Validation.validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw SharedSetupV2Error.malformed("Health.md could not encode the Shared Setup v2 document.")
        }

        // Canonical v2 bytes are compact sorted UTF-8 JSON followed by exactly
        // one LF. The public 4 MiB limit includes that final byte.
        guard data.count < SharedSetupV2.maximumEncodedBytes else {
            throw SharedSetupV2Error.oversized(maximumBytes: SharedSetupV2.maximumEncodedBytes)
        }
        data.append(0x0A)

        // A successful decode proves the allowlisted writer emitted all
        // required nullable keys, no prohibited material, and a document that
        // round-trips through the strict v2 grammar.
        let decoded = try decode(data)
        guard decoded == document else {
            throw SharedSetupV2Error.malformed(
                "Health.md could not round-trip the Shared Setup v2 document."
            )
        }
        return data
    }
}

private enum SharedSetupV2JSONPreflight {
    private static let allowedSensitiveLookingKeys: Set<String> = [
        "credentials_required",
        "healthkit_source_archive",
        "raw_snapshot"
    ]

    private static let forbiddenKeyParts = [
        "authorization", "bearer", "token", "credential", "password", "secret",
        "api_key", "headers", "request_header", "http_header", "cookie", "oauth", "bookmark", "content_uri",
        "saf_uri", "folder_uri", "document_uri", "grant", "permission", "purchase", "entitlement",
        "device_id", "install_id", "installation_id", "account_id", "user_id", "native_profile_id",
        "native_id", "profile_id", "destination_id", "folder_id", "endpoint_id", "uuid", "folder_vault_id", "api_endpoint_id",
        "pairing", "health_record", "health_data", "source_data", "export_history",
        "runtime", "timestamp", "created_at", "updated_at", "started_at", "completed_at",
        "first_failed", "last_attempt", "attempt_count", "last_run", "last_success",
        "last_export", "last_refresh", "operation_id", "fingerprint", "engine_pin",
        "renderer_pin", "engine_authority", "enabled_at", "retry", "pending_work", "pending_request",
        "progress", "session_id", "worker_id", "alarm_id", "timezone", "time_zone",
        "enabled_categories", "category_selection", "onboarding", "standardized_path",
        "vault_path", "file_path", "folder_path", "root_path", "absolute_path",
        "destination_path", "destination_root", "folder_identity", "destination_identity",
        "vault_name", "destination_name", "endpoint_url", "url_string"
    ]

    static func strictVersion(in data: Data) throws -> Int {
        let object = try parseJSON(data)
        guard let root = object as? [String: Any],
              let schema = root["schema"] as? String,
              schema == SharedSetupV2.schemaName,
              let number = root["schema_version"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw SharedSetupV2Error.invalid("This is not a versioned Health.md setup file.")
        }
        let numberType = String(cString: number.objCType)
        guard numberType != "f", numberType != "d" else {
            throw SharedSetupV2Error.invalid("The setup schema version must be an integer.")
        }
        let version = number.intValue
        guard version == SharedSetupV1.schemaVersion || version == SharedSetupV2.schemaVersion else {
            throw SharedSetupV2Error.unsupportedVersion
        }
        return version
    }

    static func preflightV2(_ data: Data) throws {
        let object = try parseJSON(data)
        var nodes = 0

        func walk(_ value: Any, depth: Int) throws {
            guard depth <= 20 else {
                throw SharedSetupV2Error.invalid("The setup file is nested too deeply.")
            }
            nodes += 1
            guard nodes <= 262_144 else {
                throw SharedSetupV2Error.invalid("The setup file contains too many values.")
            }

            switch value {
            case let dictionary as [String: Any]:
                guard dictionary.count <= 512 else {
                    throw SharedSetupV2Error.invalid("The setup file contains an oversized object.")
                }
                for (key, child) in dictionary {
                    guard key.unicodeScalars.count <= 65_536 else {
                        throw SharedSetupV2Error.invalid("The setup file contains an oversized key.")
                    }
                    let normalized = normalizedKey(key)
                    let compact = normalized.replacingOccurrences(of: "_", with: "")
                    if !allowedSensitiveLookingKeys.contains(normalized),
                       forbiddenKeyParts.contains(where: { part in
                           normalized.contains(part) ||
                               compact.contains(part.replacingOccurrences(of: "_", with: ""))
                       }) {
                        throw SharedSetupV2Error.invalid(
                            "The setup file contains prohibited private, device-bound, or runtime state."
                        )
                    }
                    try walk(child, depth: depth + 1)
                }
            case let array as [Any]:
                guard array.count <= 512 else {
                    throw SharedSetupV2Error.invalid("The setup file contains an oversized list.")
                }
                for child in array {
                    try walk(child, depth: depth + 1)
                }
            case let string as String:
                guard string.unicodeScalars.count <= 65_536 else {
                    throw SharedSetupV2Error.invalid("The setup file contains oversized text.")
                }
                let lowered = string.lowercased()
                if lowered.hasPrefix("content://") || lowered.hasPrefix("file://") ||
                    lowered.contains("authorization:") ||
                    lowered.contains("-----begin private key") ||
                    string.range(
                        of: #"(?i)\b(?:bearer|basic)\s+[a-z0-9]"#,
                        options: .regularExpression
                    ) != nil {
                    throw SharedSetupV2Error.invalid(
                        "The setup file contains device-bound or authorization material."
                    )
                }
            default:
                break
            }
        }

        try walk(object, depth: 1)
        let version = try strictVersion(in: data)
        guard version == SharedSetupV2.schemaVersion else {
            throw SharedSetupV2Error.unsupportedVersion
        }
        try validateRequiredNullableKeys(object)
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SharedSetupV2Error.malformed("This setup file is not valid JSON.")
        }
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func validateRequiredNullableKeys(_ rootValue: Any) throws {
        guard let root = rootValue as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]],
              let aliases = root["metric_aliases"] as? [[String: Any]] else {
            return
        }

        guard aliases.allSatisfy({
            $0.keys.contains("apple_selection_id") && $0.keys.contains("android_selection_id")
        }) else {
            throw SharedSetupV2Error.invalid(
                "The metric alias ledger is missing a required explicit nullable field."
            )
        }

        for profile in profiles {
            guard profile.keys.contains("schedule"),
                  let destination = profile["destination"] as? [String: Any],
                  destination.keys.contains("api_endpoint"),
                  let extensions = profile["platform_extensions"] as? [String: Any],
                  extensions.keys.contains("apple"),
                  extensions.keys.contains("android"),
                  let individual = profile["individual_entries"] as? [String: Any],
                  let metrics = individual["metrics"] as? [String: Any],
                  metrics.values.allSatisfy({
                      ($0 as? [String: Any])?.keys.contains("custom_folder") == true
                  }) else {
                throw SharedSetupV2Error.invalid(
                    "A profile is missing a required explicit nullable field."
                )
            }

            if let endpoint = destination["api_endpoint"] as? [String: Any],
               !endpoint.keys.contains("port") {
                throw SharedSetupV2Error.invalid(
                    "The endpoint hint is missing its explicit nullable port."
                )
            }
            if let apple = extensions["apple"] as? [String: Any],
               !apple.keys.contains("schedule") {
                throw SharedSetupV2Error.invalid(
                    "The Apple extension is missing its explicit nullable schedule."
                )
            }
        }
    }
}

enum SharedSetupV2Validation {
    private nonisolated static let identifier = try! NSRegularExpression(
        pattern: #"^[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*$"#
    )
    private nonisolated static let dateOnly = try! NSRegularExpression(
        pattern: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#
    )
    private nonisolated static let todayRefreshIntervals: Set<Int> = [3, 6, 12]

    static func validate(_ value: SharedSetupV2) throws {
        guard value.schema == SharedSetupV2.schemaName,
              value.schemaVersion == SharedSetupV2.schemaVersion else {
            throw SharedSetupV2Error.invalid("This setup version is not supported.")
        }
        guard isNonEmptyShortString(value.createdBy.appVersion) else {
            throw SharedSetupV2Error.invalid("The sender version is invalid.")
        }
        guard value.metricRegistry.schema == "healthmd.metric_registry",
              value.metricRegistry.registryVersion == 1,
              value.metricRegistry.registrySHA256.range(
                  of: #"^[0-9a-f]{64}$"#,
                  options: .regularExpression
              ) != nil else {
            throw SharedSetupV2Error.invalid("The metric registry identity is invalid.")
        }
        guard (1...SharedSetupV2.maximumProfiles).contains(value.profiles.count) else {
            throw SharedSetupV2Error.invalid("A Shared Setup v2 bundle must contain 1 to 100 profiles.")
        }

        var expectedBundleIDs: [String] = []
        var normalizedNames = Set<String>()
        var semanticUnion = Set<String>()

        for (offset, profile) in value.profiles.enumerated() {
            let expectedID = String(format: "profile-%03d", offset + 1)
            expectedBundleIDs.append(expectedID)
            guard profile.bundleID == expectedID else {
                throw SharedSetupV2Error.invalid(
                    "Profile bundle IDs must be sequential profile-NNN values in store order."
                )
            }

            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard profile.name == trimmedName, isNonEmptyShortString(trimmedName) else {
                throw SharedSetupV2Error.invalid("Profile names must be non-empty and already trimmed.")
            }
            let normalizedName = trimmedName.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard normalizedNames.insert(normalizedName).inserted else {
                throw SharedSetupV2Error.invalid("Profile names must be unique ignoring case.")
            }

            try validate(profile, sourcePlatform: value.createdBy.platform)
            semanticUnion.formUnion(profile.metrics.enabledIDs)
            semanticUnion.formUnion(profile.individualEntries.metrics.keys)
        }

        guard expectedBundleIDs.contains(value.activeProfile) else {
            throw SharedSetupV2Error.invalid("The active profile must reference a profile in this bundle.")
        }

        let aliases = value.metricAliases
        let aliasIDs = aliases.map(\.semanticID)
        guard aliases.count <= 512,
              aliasIDs == aliasIDs.sorted(),
              Set(aliasIDs).count == aliasIDs.count,
              Set(aliasIDs) == semanticUnion,
              aliases.allSatisfy({ alias in
                  isIdentifier(alias.semanticID) &&
                      (alias.appleSelectionID.map(isIdentifier) ?? true) &&
                      (alias.androidSelectionID.map(isIdentifier) ?? true)
              }) else {
            throw SharedSetupV2Error.invalid(
                "The metric alias ledger must be the sorted exact union of every profile meaning."
            )
        }
    }

    private static func validate(
        _ profile: SharedSetupV2.Profile,
        sourcePlatform: SharedSetupV2.Platform
    ) throws {
        let formats = profile.export.formats
        guard formats.count <= 4,
              Set(formats).count == formats.count,
              formats == formats.sorted(by: { $0.rawValue < $1.rawValue }) else {
            throw SharedSetupV2Error.invalid("Export formats must be unique and canonical.")
        }
        try validateFilename(profile.export.filenameTemplate)
        try validateRelativePath(profile.export.folderTemplate)

        let enabledIDs = profile.metrics.enabledIDs
        guard enabledIDs.count <= 256,
              enabledIDs == enabledIDs.sorted(),
              Set(enabledIDs).count == enabledIDs.count,
              enabledIDs.allSatisfy(isIdentifier) else {
            throw SharedSetupV2Error.invalid(
                "Metric IDs must be unique, sorted canonical semantic IDs."
            )
        }

        try validate(profile.presentation)
        try validate(profile.individualEntries)
        try validateRelativePath(profile.dailyNotes.folder)
        try validateFilename(profile.dailyNotes.filenameTemplate)
        try validate(profile.destination)
        if let schedule = profile.schedule {
            try validate(schedule)
        }

        let extensions = profile.platformExtensions
        guard (extensions.apple?.extensionVersion == nil || extensions.apple?.extensionVersion == 2),
              (extensions.android?.extensionVersion == nil || extensions.android?.extensionVersion == 2),
              (sourcePlatform != .apple || extensions.apple != nil),
              (sourcePlatform != .android || extensions.android != nil) else {
            throw SharedSetupV2Error.invalid(
                "Every profile must include the writer platform's typed version-2 extension."
            )
        }

        if let android = extensions.android {
            try validateRelativePath(android.export.subfolder)
            guard (1...5_000).contains(android.export.rawSnapshot.pageSize) else {
                throw SharedSetupV2Error.invalid("The Android raw-snapshot page size is invalid.")
            }
        }

        if let apple = extensions.apple {
            if let appleSchedule = apple.schedule,
               !todayRefreshIntervals.contains(appleSchedule.todayRefreshIntervalHours) {
                throw SharedSetupV2Error.invalid("The Apple Today Refresh interval is invalid.")
            }
            if sourcePlatform == .apple {
                guard (profile.schedule == nil) == (apple.schedule == nil) else {
                    throw SharedSetupV2Error.invalid(
                        "The common and Apple schedule representations contradict each other."
                    )
                }
                if let schedule = profile.schedule, let appleSchedule = apple.schedule {
                    try validateAppleScheduleContradiction(
                        common: schedule,
                        apple: appleSchedule
                    )
                }
            }
        }
    }

    private static func validate(_ presentation: SharedSetupV2.Presentation) throws {
        let frontmatter = presentation.frontmatter
        guard frontmatter.fields.count <= 256,
              frontmatter.fields.allSatisfy({
                  isNonEmptyShortString($0.sourceKey) && isNonEmptyShortString($0.outputKey)
              }),
              frontmatter.customValues.count <= 128,
              frontmatter.customValues.allSatisfy({
                  isNonEmptyShortString($0.key) && $0.value.unicodeScalars.count <= 4_096
              }),
              frontmatter.placeholders.count <= 128,
              Set(frontmatter.placeholders).count == frontmatter.placeholders.count,
              frontmatter.placeholders.allSatisfy(isNonEmptyShortString),
              isNonEmptyShortString(frontmatter.dateKey),
              isNonEmptyShortString(frontmatter.typeKey),
              frontmatter.typeValue.unicodeScalars.count <= 4_096,
              presentation.markdown.customText.unicodeScalars.count <= 65_536,
              (1...6).contains(presentation.markdown.headerLevel) else {
            throw SharedSetupV2Error.invalid(
                "Custom presentation content exceeds setup limits or is not deterministic."
            )
        }
    }

    private static func validate(_ individual: SharedSetupV2.IndividualEntries) throws {
        guard individual.metrics.count <= 256 else {
            throw SharedSetupV2Error.invalid(
                "The individual-entry metric configuration is too large."
            )
        }
        try validateRelativePath(individual.entriesFolder)
        try validateFilename(individual.filenameTemplate)
        for (semanticID, config) in individual.metrics {
            guard isIdentifier(semanticID) else {
                throw SharedSetupV2Error.invalid("An individual-entry metric ID is invalid.")
            }
            if let customFolder = config.customFolder {
                try validateRelativePath(customFolder)
            }
        }
    }

    private static func validate(_ destination: SharedSetupV2.Destination) throws {
        switch destination.kind {
        case .apiEndpoint:
            if let endpoint = destination.apiEndpoint,
               validatedURLString(for: endpoint) == nil {
                throw SharedSetupV2Error.invalid(
                    "The endpoint hint must be a safe HTTPS host and path without credentials."
                )
            }
        case .deviceFolder, .connectedMac, .cloud:
            guard destination.apiEndpoint == nil else {
                throw SharedSetupV2Error.invalid(
                    "Only an API Endpoint destination may contain an endpoint hint."
                )
            }
        }
    }

    private static func validate(_ schedule: SharedSetupV2.Schedule) throws {
        guard (1...365).contains(schedule.cadence.value),
              isDateOnly(schedule.cadence.anchorDate),
              (0...23).contains(schedule.localTime.hour),
              (0...59).contains(schedule.localTime.minute),
              (1...7).contains(schedule.weekday),
              (1...365).contains(schedule.lookbackDays) else {
            throw SharedSetupV2Error.invalid("The schedule intent is out of range.")
        }
    }

    private static func validateAppleScheduleContradiction(
        common: SharedSetupV2.Schedule,
        apple: SharedSetupV2.AppleSchedule
    ) throws {
        let cadenceMatches: Bool
        switch apple.frequency {
        case .daily:
            cadenceMatches = common.cadence.value == 1 && common.cadence.unit == .days
        case .weekly:
            cadenceMatches = common.cadence.value == 1 && common.cadence.unit == .weeks
        case .custom:
            cadenceMatches = common.cadence.unit.rawValue == apple.customUnit.rawValue
        }
        guard cadenceMatches else {
            throw SharedSetupV2Error.invalid(
                "The common and Apple cadence representations contradict each other."
            )
        }
    }

    static func validatedURLString(for endpoint: SharedSetupV2.APIEndpoint) -> String? {
        guard endpoint.scheme == "https",
              endpoint.credentialsRequired,
              isDNSHost(endpoint.host),
              endpoint.port.map({ (1...65_535).contains($0) }) ?? true,
              endpoint.path.unicodeScalars.count <= 2_048,
              endpoint.path.first == "/",
              !endpoint.path.hasPrefix("//"),
              !endpoint.path.contains(where: {
                  $0 == "%" || $0 == "?" || $0 == "#" || $0.isNewline ||
                      ($0.asciiValue.map { $0 < 32 } == true)
              }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = endpoint.host
        components.port = endpoint.port
        components.percentEncodedPath = endpoint.path
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    static func validateRelativePath(_ path: String) throws {
        guard path.unicodeScalars.count <= 4_096,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("%"),
              !path.contains("//"),
              !path.contains("://"),
              !path.contains(where: {
                  $0.isNewline || ($0.asciiValue.map { $0 < 32 } == true)
              }),
              path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ $0 != "." && $0 != ".." }),
              path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
            throw SharedSetupV2Error.invalid("A setup path is unsafe.")
        }
    }

    static func validateFilename(_ value: String) throws {
        guard !value.isEmpty,
              value != ".",
              value != "..",
              value.unicodeScalars.count <= 4_096,
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains("%"),
              !value.contains(where: {
                  $0.isNewline || ($0.asciiValue.map { $0 < 32 } == true)
              }),
              value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
            throw SharedSetupV2Error.invalid("A filename template is unsafe.")
        }
    }

    nonisolated static func isIdentifier(_ value: String) -> Bool {
        identifier.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil && value.unicodeScalars.count <= 128
    }

    nonisolated static func isNonEmptyShortString(_ value: String) -> Bool {
        !value.isEmpty &&
            value.unicodeScalars.count <= 256 &&
            !value.contains(where: {
                $0.isNewline || ($0.asciiValue.map { $0 < 32 } == true)
            })
    }

    nonisolated static func isDNSHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.utf8.count <= 253,
              host.unicodeScalars.allSatisfy(\.isASCII),
              !host.contains(":"),
              !host.contains("@") else {
            return false
        }
        let isASCIIAlphaNumeric: (UInt8) -> Bool = {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            let bytes = Array(label.utf8)
            return !bytes.isEmpty &&
                bytes.count <= 63 &&
                isASCIIAlphaNumeric(bytes[0]) &&
                isASCIIAlphaNumeric(bytes[bytes.count - 1]) &&
                bytes.allSatisfy { isASCIIAlphaNumeric($0) || $0 == 45 }
        }
    }

    private nonisolated static func isDateOnly(_ value: String) -> Bool {
        guard dateOnly.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil else {
            return false
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9_999).contains(parts[0]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        )) else {
            return false
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == parts[0] &&
            roundTrip.month == parts[1] &&
            roundTrip.day == parts[2]
    }
}
