import Foundation

enum WatchExportError: LocalizedError {
    case invalidDestination, invalidCredential, storage, pendingUpload, noDestination
    case invalidCapture, rejected, invalidAcknowledgement, transport, unavailable

    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "Use an HTTPS URL without a username, password, query, or fragment."
        case .invalidCredential: return "Enter a valid backend bearer token (maximum 4096 characters)."
        case .storage: return "Secure storage is unavailable. Unlock the Watch and try again."
        case .pendingUpload: return "Retry or explicitly discard the pending upload before changing destination."
        case .noDestination: return "Set up an API destination on this Watch first."
        case .invalidCapture: return "The local capture is invalid; nothing was uploaded."
        case .rejected: return "The backend rejected this upload. Pending data is retained; check endpoint and access."
        case .invalidAcknowledgement: return "No matching backend acknowledgement. Delivery is uncertain; retry the same upload."
        case .transport: return "Delivery is uncertain. Check Wi-Fi or cellular and retry the pending upload."
        case .unavailable: return "Health data is not available on this Watch."
        }
    }
}

struct WatchExportDestination: Codable, Equatable {
    let endpoint: URL
    let bearerToken: String

    init(endpoint: String, bearerToken: String) throws {
        guard endpoint.utf8.count <= 2048,
              let components = URLComponents(string: endpoint),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else { throw WatchExportError.invalidDestination }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+/=")
        guard !bearerToken.isEmpty, bearerToken.utf8.count <= 4096,
              bearerToken.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw WatchExportError.invalidCredential
        }
        self.endpoint = url
        self.bearerToken = bearerToken
    }

    func validated() throws -> Self {
        try Self(endpoint: endpoint.absoluteString, bearerToken: bearerToken)
    }
}

enum WatchExportMetric: String, CaseIterable, Codable {
    case steps, activeEnergy = "active_energy_kcal", exercise = "apple_exercise_minutes"

    var unit: String {
        switch self {
        case .steps: return "count"
        case .activeEnergy: return "kcal"
        case .exercise: return "min"
        }
    }
}

struct WatchExportObservation: Codable, Equatable {
    enum Status: String, Codable { case value, noData = "no_data_or_not_authorized", failed = "query_failed", unsupported }
    let metric: WatchExportMetric
    let unit: String
    let reducer: String
    let status: Status
    let value: Double?

    init(metric: WatchExportMetric, value: Double?, status: Status? = nil) throws {
        let resolved = status ?? (value == nil ? .noData : .value)
        guard (resolved == .value) == (value != nil),
              value.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw WatchExportError.invalidCapture }
        self.metric = metric
        self.unit = metric.unit
        self.reducer = "healthkit_cumulative_sum"
        self.status = resolved
        self.value = value
    }
}

struct WatchExportPayload: Encodable {
    let schema = "healthmd.watch_snapshot"
    let schemaVersion = 1
    let uploadID: UUID
    let capturedAt: Date
    let intervalStart: Date
    let intervalEnd: Date
    let calendarTimezone: String
    let source = "watch_local_healthkit"
    let historyAvailability = "unknown_local_store_may_be_purged"
    let earliestPermittedSampleDate: Date
    let workoutsStatus = "not_requested"
    let observations: [WatchExportObservation]

    var captureStatus: String {
        observations.contains { $0.status == .failed || $0.status == .unsupported } ? "partial" : "observed"
    }

    enum CodingKeys: String, CodingKey {
        case schema, schemaVersion = "schema_version", uploadID = "upload_id", capturedAt = "captured_at"
        case intervalStart = "interval_start", intervalEnd = "interval_end", calendarTimezone = "calendar_timezone"
        case source, historyAvailability = "history_availability"
        case earliestPermittedSampleDate = "earliest_permitted_sample_date", workoutsStatus = "workouts_status"
        case observations, captureStatus = "capture_status"
    }

    // Encoding only: queued requests preserve exact bytes, not a decoded/rebuilt snapshot.
    init(uploadID: UUID = UUID(), capturedAt: Date, intervalStart: Date, intervalEnd: Date,
         calendarTimezone: String, earliestPermittedSampleDate: Date, observations: [WatchExportObservation]) throws {
        guard intervalStart <= intervalEnd, intervalEnd <= capturedAt,
              TimeZone(identifier: calendarTimezone) != nil,
              observations.map(\.metric) == WatchExportMetric.allCases else { throw WatchExportError.invalidCapture }
        self.uploadID = uploadID
        self.capturedAt = capturedAt
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.calendarTimezone = calendarTimezone
        self.earliestPermittedSampleDate = earliestPermittedSampleDate
        self.observations = observations
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(uploadID, forKey: .uploadID)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(intervalStart, forKey: .intervalStart)
        try container.encode(intervalEnd, forKey: .intervalEnd)
        try container.encode(calendarTimezone, forKey: .calendarTimezone)
        try container.encode(source, forKey: .source)
        try container.encode(historyAvailability, forKey: .historyAvailability)
        try container.encode(earliestPermittedSampleDate, forKey: .earliestPermittedSampleDate)
        try container.encode(workoutsStatus, forKey: .workoutsStatus)
        try container.encode(observations, forKey: .observations)
        try container.encode(captureStatus, forKey: .captureStatus)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

struct WatchPendingUpload: Codable, Equatable {
    let id: UUID
    let body: Data
}

struct WatchExportState: Codable, Equatable {
    var destination: WatchExportDestination?
    var pending: WatchPendingUpload?
}
