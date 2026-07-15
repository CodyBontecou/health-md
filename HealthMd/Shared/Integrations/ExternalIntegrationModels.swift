import Foundation

// MARK: - Connected Apps Feature Flag

/// Provider-specific Connected Apps rollout gates. A provider is visible and
/// queried only when its Info.plist flag is enabled, so WHOOP can ship without
/// coupling its rollout to unfinished provider integrations.
enum ConnectedAppsFeature {
    static let whoopFlagKey = "CONNECTED_APPS_WHOOP_ENABLED"

    static var enabledProviders: [ExternalIntegrationProvider] {
        enabledProviders(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    static var isEnabled: Bool { !enabledProviders.isEmpty }

    static func isEnabled(_ provider: ExternalIntegrationProvider) -> Bool {
        enabledProviders.contains(provider)
    }

    static func enabledProviders(infoDictionary: [String: Any]) -> [ExternalIntegrationProvider] {
        isTruthy(infoDictionary[whoopFlagKey]) ? [.whoop] : []
    }

    private static func isTruthy(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        guard let value = value as? String else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        default: return false
        }
    }
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

    var grantedScopes: Set<String>? {
        guard let scope else { return nil }
        return Set(scope.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
    }

    func grants(_ requiredScope: String) -> Bool {
        // Some providers omit `scope` from otherwise valid token responses. In
        // that case, let the endpoint response be the source of truth.
        grantedScopes?.contains(requiredScope) ?? true
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

enum ExternalProviderExportError: LocalizedError, Equatable {
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidDate:
            return "A provider sidecar had an invalid daily filename."
        }
    }
}

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

    var hasValidExportDate: Bool {
        guard date.count == 10 else { return false }
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let parsed = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: parsed)
        return components.year == year && components.month == month && components.day == day
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
        guard error == nil else { return false }
        guard let data else { return true }
        return data.isEmptyCollection
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(Self.redactedEndpoint(endpoint), forKey: .endpoint)
        try container.encode(statusCode, forKey: .statusCode)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(data?.redactingSensitiveValues(), forKey: .data)
        try container.encodeIfPresent(error, forKey: .error)
    }

    private static func redactedEndpoint(_ value: String) -> String {
        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return value
        }
        let sensitiveNames = Set(["accesstoken", "clientsecret", "refreshtoken", "code", "nexttoken"])
        components.queryItems = components.queryItems?.map { item in
            let normalizedName = item.name.lowercased().filter(\.isLetter)
            let value = sensitiveNames.contains(normalizedName) ? "[redacted]" : item.value
            return URLQueryItem(name: item.name, value: value)
        }
        return components.url?.absoluteString ?? value
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

    nonisolated init(any value: Any) {
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

    nonisolated var isEmptyCollection: Bool {
        switch self {
        case .array(let values):
            return values.isEmpty
        case .object(let values):
            if values.isEmpty { return true }
            // Collection APIs commonly wrap an empty result in `records` or
            // `data`, with an absent/null cursor alongside it.
            for key in ["records", "data"] {
                if let collection = values[key], collection.isEmptyCollection {
                    let remaining = values.filter { $0.key != key && $0.key != "next_token" }
                    if remaining.isEmpty { return true }
                }
            }
            return false
        default:
            return false
        }
    }

    nonisolated func redactingSensitiveValues() -> JSONValue {
        switch self {
        case .array(let values):
            return .array(values.map { $0.redactingSensitiveValues() })
        case .object(let values):
            let sensitiveNames = Set(["accesstoken", "refreshtoken", "clientsecret", "authorization", "code", "nexttoken"])
            return .object(values.mapValues { $0.redactingSensitiveValues() }.mapValuesWithKeys { key, value in
                let normalizedKey = key.lowercased().filter(\.isLetter)
                return sensitiveNames.contains(normalizedKey) ? .string("[redacted]") : value
            })
        default:
            return self
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    nonisolated func mapValuesWithKeys(_ transform: (String, JSONValue) -> JSONValue) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        result.reserveCapacity(count)
        for (key, value) in self {
            result[key] = transform(key, value)
        }
        return result
    }
}
