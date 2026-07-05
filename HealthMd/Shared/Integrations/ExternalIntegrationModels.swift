import Foundation

// MARK: - Connected Apps Feature Flag

/// Keeps the unreleased Connected Apps provider flow dormant until the product
/// is ready to ship OAuth setup, provider sidecars, and API envelope additions.
enum ConnectedAppsFeature {
    static let isEnabled = false
}

// MARK: - External Integration Providers

/// Third-party provider integrations that export sidecar JSON files next to the
/// canonical Apple Health export. These records deliberately use a separate
/// schema so the long-lived `healthmd.health_data` daily export contract remains
/// stable until we intentionally promote normalized provider fields.
enum ExternalIntegrationProvider: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case fitbit
    case oura
    case whoop
    case withings
    case strava

    var id: String { rawValue }

    static let supportedWithoutPartnerApplication: [ExternalIntegrationProvider] = [
        .withings,
        .oura,
        .strava,
        .fitbit,
        .whoop
    ]

    var displayName: String {
        switch self {
        case .fitbit: return "Fitbit"
        case .oura: return "Oura"
        case .whoop: return "WHOOP"
        case .withings: return "Withings"
        case .strava: return "Strava"
        }
    }

    var exportFolderName: String { rawValue }

    var iconName: String {
        switch self {
        case .fitbit: return "figure.walk"
        case .oura: return "circle.hexagongrid.fill"
        case .whoop: return "waveform.path.ecg"
        case .withings: return "scalemass.fill"
        case .strava: return "figure.run"
        }
    }

    /// Scopes requested for the first read-only MVP. Provider apps can still
    /// reject optional scopes; export treats 403s for individual payloads as
    /// per-payload warnings instead of failing the entire daily export.
    var defaultScopes: [String] {
        switch self {
        case .fitbit:
            return ["activity", "heartrate", "sleep", "weight", "location"]
        case .oura:
            return ["daily", "heartrate", "workout", "spo2Daily"]
        case .whoop:
            return ["offline", "read:recovery", "read:cycles", "read:sleep", "read:workout", "read:body_measurement"]
        case .withings:
            return ["user.info", "user.metrics", "user.activity", "user.sleepevents"]
        case .strava:
            return ["read", "activity:read"]
        }
    }

    /// Fitbit supports native PKCE. Other current provider docs still require a
    /// broker-held client secret for token exchange/refresh, so PKCE is not
    /// assumed unless documented.
    var usesPKCE: Bool {
        switch self {
        case .fitbit: return true
        case .oura, .whoop, .withings, .strava: return false
        }
    }

    var summary: String {
        switch self {
        case .fitbit:
            return "Activity, sleep, heart, HRV, weight, and workout summaries."
        case .oura:
            return "Readiness, sleep, stress, resilience, HRV, SpO₂, and workouts."
        case .whoop:
            return "Recovery, strain, sleep need, HRV, respiratory rate, and workouts."
        case .withings:
            return "Weight, body composition, blood pressure, sleep, HRV, SpO₂, and temperature."
        case .strava:
            return "Workout activities, route metadata, streams, laps, zones, and sports context."
        }
    }
}

// MARK: - External OAuth Tokens

struct ExternalIntegrationToken: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var scope: String?
    var expiresAt: Date?
    var providerUserID: String?

    init(
        accessToken: String,
        refreshToken: String? = nil,
        tokenType: String = "Bearer",
        scope: String? = nil,
        expiresAt: Date? = nil,
        providerUserID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = expiresAt
        self.providerUserID = providerUserID
    }

    var authorizationHeaderValue: String {
        let type = tokenType.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(type.isEmpty ? "Bearer" : type) \(accessToken)"
    }

    func needsRefresh(now: Date = Date(), leeway: TimeInterval = 120) -> Bool {
        guard refreshToken?.isEmpty == false, let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= leeway
    }
}

struct ExternalIntegrationAccount: Codable, Equatable, Identifiable, Sendable {
    var provider: ExternalIntegrationProvider
    var connectedAt: Date
    var lastSuccessfulExportAt: Date?
    var scope: String?
    var providerUserID: String?

    var id: ExternalIntegrationProvider { provider }
}

// MARK: - External Sidecar Export Schema

struct ExternalDailyRecord: Codable, Equatable, Sendable {
    static let schema = "healthmd.external_provider_daily"
    static let schemaVersion = 1

    var schema: String = Self.schema
    var schemaVersion: Int = Self.schemaVersion
    var provider: ExternalIntegrationProvider
    var providerDisplayName: String
    var date: String
    var fetchedAt: Date
    var payloads: [ExternalProviderPayload]
    var warnings: [String]

    init(
        provider: ExternalIntegrationProvider,
        date: String,
        fetchedAt: Date = Date(),
        payloads: [ExternalProviderPayload],
        warnings: [String] = []
    ) {
        self.provider = provider
        self.providerDisplayName = provider.displayName
        self.date = date
        self.fetchedAt = fetchedAt
        self.payloads = payloads
        self.warnings = warnings
    }

    var hasPayloads: Bool {
        payloads.contains { !$0.isEmpty }
    }

    var shouldExport: Bool {
        hasPayloads || !warnings.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case provider
        case providerDisplayName = "provider_display_name"
        case date
        case fetchedAt = "fetched_at"
        case payloads
        case warnings
    }
}

struct ExternalProviderPayload: Codable, Equatable, Sendable {
    var name: String
    var endpoint: String
    var statusCode: Int
    var fetchedAt: Date
    var data: JSONValue?
    var error: String?

    init(
        name: String,
        endpoint: String,
        statusCode: Int,
        fetchedAt: Date = Date(),
        data: JSONValue? = nil,
        error: String? = nil
    ) {
        self.name = name
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.fetchedAt = fetchedAt
        self.data = data
        self.error = error
    }

    var isEmpty: Bool {
        guard error == nil, let data else { return false }
        return data.isEmptyCollection
    }

    enum CodingKeys: String, CodingKey {
        case name
        case endpoint
        case statusCode = "status_code"
        case fetchedAt = "fetched_at"
        case data
        case error
    }
}

// MARK: - JSON Value

/// Codable representation for provider JSON that Health.md preserves without
/// losing unknown fields. This keeps the MVP useful while provider-specific
/// normalized fields evolve separately.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }

    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Int64:
            self = .number(Double(value))
        case let value as UInt64:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as Float:
            self = .number(Double(value))
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init(any:)))
        default:
            self = .string(String(describing: value))
        }
    }

    var isEmptyCollection: Bool {
        switch self {
        case .array(let values): return values.isEmpty
        case .object(let values): return values.isEmpty
        default: return false
        }
    }
}
