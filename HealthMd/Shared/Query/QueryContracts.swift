import Foundation

private struct HealthMdAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension Decoder {
    nonisolated func rejectUnknownKeys(_ allowed: Set<String>) throws {
        let container = try self.container(keyedBy: HealthMdAnyCodingKey.self)
        let unknown = Set(container.allKeys.map(\.stringValue)).subtracting(allowed)
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Unknown fields: \(unknown.sorted().joined(separator: ", "))"
            ))
        }
    }
}

// MARK: - Independent schema identities

nonisolated enum HealthMdQuerySchemas {
    static let queryRequest = "healthmd.query_request"
    static let queryResponse = "healthmd.query_response"
    static let queryError = "healthmd.query_error"
    static let compactContextDay = "healthmd.query_context_day"
    static let evidencePacket = "healthmd.evidence_packet"
    static let version = 1
}

// MARK: - Selection and operations

nonisolated enum HealthMdQueryDetailLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case summary
    case lossless
}

nonisolated enum HealthMdMetricSelection: Codable, Equatable, Sendable {
    case explicit([String])
    case allAvailable

    private enum CodingKeys: String, CodingKey { case type, metricIDs = "metric_ids" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .explicit(let ids):
            try c.encode("explicit", forKey: .type)
            try c.encode(Array(Set(ids)).sorted(), forKey: .metricIDs)
        case .allAvailable: try c.encode("all_available", forKey: .type)
        }
    }
    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(["type", "metric_ids"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "explicit":
            let ids = try c.decode([String].self, forKey: .metricIDs)
            guard Set(ids).count == ids.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .metricIDs,
                    in: c,
                    debugDescription: "Duplicate metric IDs are not allowed"
                )
            }
            self = .explicit(ids.sorted())
        case "all_available":
            guard !c.contains(.metricIDs) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .metricIDs,
                    in: c,
                    debugDescription: "all_available cannot include metric_ids"
                )
            }
            self = .allAvailable
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown metric selection"
            )
        }
    }
}

/// Stable query-layer source identities. These do not alter the daily export schema.
nonisolated enum HealthMdEvidenceSourceIDs {
    static let appleHealth = "apple_health"
    static let healthMdSummary = "healthmd_summary"
    static let providerNative = "provider_native"
    static let diagnostics = "healthmd_diagnostics"
}

/// Source filters are independent from metric filters. Omitting `sources` from a v1 request
/// decodes as `all_available`, preserving the original v1 request behavior.
nonisolated enum HealthMdSourceSelection: Codable, Equatable, Sendable {
    case explicit(sourceIDs: [String], providerIDs: [String])
    case allAvailable

    private enum CodingKeys: String, CodingKey {
        case type
        case sourceIDs = "source_ids"
        case providerIDs = "provider_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .explicit(let sourceIDs, let providerIDs):
            try container.encode("explicit", forKey: .type)
            try container.encode(Array(Set(sourceIDs)).sorted(), forKey: .sourceIDs)
            try container.encode(Array(Set(providerIDs)).sorted(), forKey: .providerIDs)
        case .allAvailable:
            try container.encode("all_available", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(["type", "source_ids", "provider_ids"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "explicit":
            let sourceIDs = try container.decodeIfPresent([String].self, forKey: .sourceIDs) ?? []
            let providerIDs = try container.decodeIfPresent([String].self, forKey: .providerIDs) ?? []
            guard Set(sourceIDs).count == sourceIDs.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sourceIDs,
                    in: container,
                    debugDescription: "Duplicate source IDs are not allowed"
                )
            }
            guard Set(providerIDs).count == providerIDs.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .providerIDs,
                    in: container,
                    debugDescription: "Duplicate provider IDs are not allowed"
                )
            }
            self = .explicit(
                sourceIDs: sourceIDs.sorted(),
                providerIDs: providerIDs.sorted()
            )
        case "all_available":
            guard !container.contains(.sourceIDs), !container.contains(.providerIDs) else {
                throw DecodingError.dataCorruptedError(
                    forKey: container.contains(.sourceIDs) ? .sourceIDs : .providerIDs,
                    in: container,
                    debugDescription: "all_available cannot include explicit sources"
                )
            }
            self = .allAvailable
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown source selection"
            )
        }
    }
}

nonisolated struct HealthMdDateRange: Codable, Equatable, Sendable {
    let startDate: String
    let endDate: String
    init(startDate: String, endDate: String) { self.startDate = startDate; self.endDate = endDate }
    enum CodingKeys: String, CodingKey { case startDate = "start_date", endDate = "end_date" }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(["start_date", "end_date"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decode(String.self, forKey: .startDate)
        endDate = try container.decode(String.self, forKey: .endDate)
    }
}

nonisolated enum HealthMdDateSelection: Codable, Equatable, Sendable {
    case exact(HealthMdDateRange)
    case allAvailable
    private enum CodingKeys: String, CodingKey { case type, range }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exact(let range): try c.encode("exact", forKey: .type); try c.encode(range, forKey: .range)
        case .allAvailable: try c.encode("all_available", forKey: .type)
        }
    }
    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(["type", "range"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "exact":
            self = .exact(try c.decode(HealthMdDateRange.self, forKey: .range))
        case "all_available":
            guard !c.contains(.range) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .range,
                    in: c,
                    debugDescription: "all_available cannot include a range"
                )
            }
            self = .allAvailable
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown date selection"
            )
        }
    }
}

nonisolated enum HealthMdAggregationKind: String, Codable, Equatable, Sendable {
    case sum, average, minimum, maximum, latest, count
    case durationSum = "duration_sum"
}

/// The authoritative daily-summary rule copied from the v7 data dictionary.
/// This is deliberately broader than period-query aggregations: clock times,
/// categories, lists, and workout-weighted values must retain their daily meaning.
nonisolated enum HealthMdDailyAggregation: String, Codable, Equatable, Sendable {
    case sum, average, minimum, maximum, latest, count, list
    case durationSum = "duration_sum"
    case firstTime = "first_time"
    case lastTime = "last_time"
    case categoryLatest = "category_latest"
    case weightedAverage = "weighted_average"
}

/// The caller supplies aggregation semantics rather than the evaluator guessing from a metric name.
nonisolated struct HealthMdAggregationDescriptor: Codable, Equatable, Sendable {
    let metricID: String
    let kind: HealthMdAggregationKind
    let expectedUnit: String?
    init(metricID: String, kind: HealthMdAggregationKind, expectedUnit: String? = nil) {
        self.metricID = metricID; self.kind = kind; self.expectedUnit = expectedUnit
    }
    enum CodingKeys: String, CodingKey { case metricID = "metric_id", kind, expectedUnit = "expected_unit" }
}

nonisolated enum HealthMdPacketKind: String, Codable, CaseIterable, Sendable {
    case dailyWellness = "daily_wellness"
    case training
    case doctorVisit = "doctor_visit"
}

nonisolated struct HealthMdSleepWindow: Codable, Equatable, Sendable {
    let startOffsetSeconds: Double
    let durationSeconds: Double

    init(startOffsetSeconds: Double = 0, durationSeconds: Double) {
        self.startOffsetSeconds = startOffsetSeconds
        self.durationSeconds = durationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case startOffsetSeconds = "start_offset_seconds"
        case durationSeconds = "duration_seconds"
    }
}

nonisolated enum HealthMdQueryOperation: Codable, Equatable, Sendable {
    case metricSeries
    case periodComparison(first: HealthMdDateRange, second: HealthMdDateRange, aggregations: [HealthMdAggregationDescriptor])
    case workoutListing
    case sleepSessionListing(window: HealthMdSleepWindow?, includeNaps: Bool)
    case workoutSleepAlignment(
        window: HealthMdSleepWindow?,
        workoutActivity: String?,
        includeNaps: Bool
    )
    case sourceRecordListing
    case coverage
    case derivePacket(kind: HealthMdPacketKind, detailIDs: [String])

    private enum CodingKeys: String, CodingKey {
        case type, first, second, aggregations, window
        case includeNaps = "include_naps"
        case workoutActivity = "workout_activity"
        case kind, detailIDs = "detail_ids"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metricSeries: try c.encode("metric_series", forKey: .type)
        case .periodComparison(let first, let second, let aggregations):
            try c.encode("period_comparison", forKey: .type); try c.encode(first, forKey: .first)
            try c.encode(second, forKey: .second)
            try c.encode(aggregations.sorted { $0.metricID < $1.metricID }, forKey: .aggregations)
        case .workoutListing: try c.encode("workout_listing", forKey: .type)
        case .sleepSessionListing(let window, let includeNaps):
            try c.encode("sleep_session_listing", forKey: .type)
            try c.encodeIfPresent(window, forKey: .window)
            try c.encode(includeNaps, forKey: .includeNaps)
        case .workoutSleepAlignment(let window, let workoutActivity, let includeNaps):
            try c.encode("workout_sleep_alignment", forKey: .type)
            try c.encodeIfPresent(window, forKey: .window)
            try c.encodeIfPresent(workoutActivity, forKey: .workoutActivity)
            try c.encode(includeNaps, forKey: .includeNaps)
        case .sourceRecordListing: try c.encode("source_record_listing", forKey: .type)
        case .coverage: try c.encode("coverage", forKey: .type)
        case .derivePacket(let kind, let detailIDs):
            try c.encode("derive_packet", forKey: .type); try c.encode(kind, forKey: .kind)
            try c.encode(Array(Set(detailIDs)).sorted(), forKey: .detailIDs)
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "metric_series": self = .metricSeries
        case "period_comparison": self = .periodComparison(
            first: try c.decode(HealthMdDateRange.self, forKey: .first),
            second: try c.decode(HealthMdDateRange.self, forKey: .second),
            aggregations: try c.decode([HealthMdAggregationDescriptor].self, forKey: .aggregations)
        )
        case "workout_listing": self = .workoutListing
        case "sleep_session_listing": self = .sleepSessionListing(
            window: try c.decodeIfPresent(HealthMdSleepWindow.self, forKey: .window),
            includeNaps: try c.decodeIfPresent(Bool.self, forKey: .includeNaps) ?? true
        )
        case "workout_sleep_alignment": self = .workoutSleepAlignment(
            window: try c.decodeIfPresent(HealthMdSleepWindow.self, forKey: .window),
            workoutActivity: try c.decodeIfPresent(String.self, forKey: .workoutActivity),
            includeNaps: try c.decodeIfPresent(Bool.self, forKey: .includeNaps) ?? false
        )
        case "source_record_listing", "evidence_listing": self = .sourceRecordListing
        case "coverage": self = .coverage
        case "derive_packet": self = .derivePacket(
            kind: try c.decode(HealthMdPacketKind.self, forKey: .kind),
            detailIDs: try c.decodeIfPresent([String].self, forKey: .detailIDs) ?? []
        )
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown query operation")
        }
    }
}

nonisolated struct HealthMdPageControls: Codable, Equatable, Sendable {
    /// Per-page bounds protect memory and wire frames. They never cap total
    /// query results because every non-terminal page returns a cursor.
    static let maximumItems = 1_000
    static let maximumBytes = 1 * 1_024 * 1_024

    let maxItems: Int
    let maxBytes: Int
    let cursor: String?
    init(maxItems: Int = 250, maxBytes: Int = 256 * 1024, cursor: String? = nil) {
        self.maxItems = maxItems; self.maxBytes = maxBytes; self.cursor = cursor
    }
    enum CodingKeys: String, CodingKey { case maxItems = "max_items", maxBytes = "max_bytes", cursor }
}

nonisolated struct HealthMdQueryRequest: Codable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let metrics: HealthMdMetricSelection
    let sources: HealthMdSourceSelection
    let dates: HealthMdDateSelection
    let operation: HealthMdQueryOperation
    let page: HealthMdPageControls

    init(
        metrics: HealthMdMetricSelection,
        sources: HealthMdSourceSelection = .allAvailable,
        dates: HealthMdDateSelection,
        operation: HealthMdQueryOperation,
        page: HealthMdPageControls = .init(),
        schema: String = HealthMdQuerySchemas.queryRequest,
        schemaVersion: Int = 1
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.metrics = metrics
        self.sources = sources
        self.dates = dates
        self.operation = operation
        self.page = page
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case metrics, sources, dates, operation, page
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys([
            "schema", "schema_version", "metrics", "sources", "dates", "operation", "page"
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        metrics = try container.decode(HealthMdMetricSelection.self, forKey: .metrics)
        sources = try container.decodeIfPresent(HealthMdSourceSelection.self, forKey: .sources) ?? .allAvailable
        dates = try container.decode(HealthMdDateSelection.self, forKey: .dates)
        operation = try container.decode(HealthMdQueryOperation.self, forKey: .operation)
        page = try container.decode(HealthMdPageControls.self, forKey: .page)
    }
}

nonisolated struct HealthMdQueryError: Codable, Error, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let code: String
    let message: String
    let retryable: Bool
    let details: [String: HealthMdJSONValue]
    init(code: String, message: String, retryable: Bool = false, details: [String: HealthMdJSONValue] = [:]) {
        schema = HealthMdQuerySchemas.queryError; schemaVersion = 1; self.code = code
        self.message = message; self.retryable = retryable; self.details = details
    }
    enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", code, message, retryable, details }
}

// MARK: - Missingness, coverage, and evidence

nonisolated enum HealthMdAvailabilityStatus: String, Codable, CaseIterable, Sendable {
    case available
    case completeEmpty = "complete_empty"
    case partial
    case failed
    case unsupported
    case skipped
    case cancelled
    case notRequested = "not_requested"
    case legacyUnavailable = "legacy_unavailable"
    case redacted
    case notSynchronized = "not_synchronized"
}

nonisolated struct HealthMdMissingInterval: Codable, Equatable, Sendable {
    let range: HealthMdDateRange
    let status: HealthMdAvailabilityStatus
    let reason: String?
    init(range: HealthMdDateRange, status: HealthMdAvailabilityStatus, reason: String? = nil) {
        self.range = range; self.status = status; self.reason = reason
    }
}

nonisolated struct HealthMdCoverage: Codable, Equatable, Sendable {
    let requestedRange: HealthMdDateRange?
    let availableRange: HealthMdDateRange?
    let status: HealthMdAvailabilityStatus
    let daysConsidered: Int
    let daysWithValues: Int
    let missing: [HealthMdMissingInterval]
    init(requestedRange: HealthMdDateRange?, availableRange: HealthMdDateRange?, status: HealthMdAvailabilityStatus, daysConsidered: Int, daysWithValues: Int, missing: [HealthMdMissingInterval] = []) {
        self.requestedRange = requestedRange; self.availableRange = availableRange; self.status = status
        self.daysConsidered = daysConsidered; self.daysWithValues = daysWithValues
        self.missing = missing.sorted { $0.range.startDate < $1.range.startDate }
    }
    enum CodingKeys: String, CodingKey { case requestedRange = "requested_range", availableRange = "available_range", status, daysConsidered = "days_considered", daysWithValues = "days_with_values", missing }
}

nonisolated struct HealthMdLimitation: Codable, Equatable, Hashable, Sendable {
    let code: String
    let message: String
    init(code: String, message: String) { self.code = code; self.message = message }
}

nonisolated struct HealthMdSourceDescriptor: Codable, Equatable, Hashable, Sendable {
    let schema: String
    let schemaVersion: Int
    let digest: String
    init(schema: String, schemaVersion: Int, digest: String) { self.schema = schema; self.schemaVersion = schemaVersion; self.digest = digest }
    enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", digest }
}

nonisolated enum HealthMdEvidenceLocator: Codable, Equatable, Hashable, Sendable {
    case summaryKey(ownerDate: String, key: String)
    case canonicalUUID(ownerDate: String, uuid: String)
    case externalIdentity(ownerDate: String, identifier: String)
    case queryManifest(ownerDate: String, identifier: String)
    case warning(ownerDate: String, code: String)
    case partialFailure(ownerDate: String, identifier: String)

    private enum CodingKeys: String, CodingKey { case type, ownerDate = "owner_date", key, uuid, identifier, code }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .summaryKey(let day, let key): try c.encode("summary_key", forKey: .type); try c.encode(day, forKey: .ownerDate); try c.encode(key, forKey: .key)
        case .canonicalUUID(let day, let uuid): try c.encode("canonical_uuid", forKey: .type); try c.encode(day, forKey: .ownerDate); try c.encode(uuid.lowercased(), forKey: .uuid)
        case .externalIdentity(let day, let id): try c.encode("external_identity", forKey: .type); try c.encode(day, forKey: .ownerDate); try c.encode(id, forKey: .identifier)
        case .queryManifest(let day, let id): try c.encode("query_manifest", forKey: .type); try c.encode(day, forKey: .ownerDate); try c.encode(id, forKey: .identifier)
        case .warning(let day, let code): try c.encode("warning", forKey: .type); try c.encode(day, forKey: .ownerDate); try c.encode(code, forKey: .code)
        case .partialFailure(let day, let id): try c.encode("partial_failure", forKey: .type); try c.encode(day, forKey: .ownerDate); try c.encode(id, forKey: .identifier)
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); let type = try c.decode(String.self, forKey: .type)
        let day = try c.decode(String.self, forKey: .ownerDate)
        switch type {
        case "summary_key": self = .summaryKey(ownerDate: day, key: try c.decode(String.self, forKey: .key))
        case "canonical_uuid": self = .canonicalUUID(ownerDate: day, uuid: try c.decode(String.self, forKey: .uuid))
        case "external_identity": self = .externalIdentity(ownerDate: day, identifier: try c.decode(String.self, forKey: .identifier))
        case "query_manifest": self = .queryManifest(ownerDate: day, identifier: try c.decode(String.self, forKey: .identifier))
        case "warning": self = .warning(ownerDate: day, code: try c.decode(String.self, forKey: .code))
        case "partial_failure": self = .partialFailure(ownerDate: day, identifier: try c.decode(String.self, forKey: .identifier))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown evidence locator")
        }
    }

    var ownerDate: String {
        switch self {
        case .summaryKey(let ownerDate, _), .canonicalUUID(let ownerDate, _),
             .externalIdentity(let ownerDate, _), .queryManifest(let ownerDate, _),
             .warning(let ownerDate, _), .partialFailure(let ownerDate, _):
            return ownerDate
        }
    }
}

nonisolated struct HealthMdEvidenceReference: Codable, Equatable, Hashable, Sendable {
    let evidenceID: String
    let locator: HealthMdEvidenceLocator
    let source: HealthMdSourceDescriptor
    let sourceID: String
    let providerID: String?

    init(
        evidenceID: String,
        locator: HealthMdEvidenceLocator,
        source: HealthMdSourceDescriptor,
        sourceID: String? = nil,
        providerID: String? = nil
    ) {
        self.evidenceID = evidenceID
        self.locator = locator
        self.source = source
        self.sourceID = sourceID ?? Self.legacySourceID(for: locator)
        self.providerID = providerID
    }

    enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case locator, source
        case sourceID = "source_id"
        case providerID = "provider_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evidenceID = try container.decode(String.self, forKey: .evidenceID)
        locator = try container.decode(HealthMdEvidenceLocator.self, forKey: .locator)
        source = try container.decode(HealthMdSourceDescriptor.self, forKey: .source)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
            ?? Self.legacySourceID(for: locator)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
    }

    fileprivate static func legacySourceID(for locator: HealthMdEvidenceLocator) -> String {
        switch locator {
        case .summaryKey:
            return HealthMdEvidenceSourceIDs.healthMdSummary
        case .canonicalUUID, .queryManifest, .partialFailure:
            return HealthMdEvidenceSourceIDs.appleHealth
        case .externalIdentity, .warning:
            return HealthMdEvidenceSourceIDs.diagnostics
        }
    }
}

nonisolated struct HealthMdContextEvidence: Codable, Equatable, Sendable {
    let reference: HealthMdEvidenceReference
    let value: HealthMdQueryValue?
    let note: String?
    let metricIDs: [String]

    init(
        reference: HealthMdEvidenceReference,
        value: HealthMdQueryValue? = nil,
        note: String? = nil,
        metricIDs: [String] = []
    ) {
        self.reference = Self.normalizedReference(reference, value: value)
        self.value = value
        self.note = note
        self.metricIDs = Array(Set(metricIDs)).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case reference, value, note
        case metricIDs = "metric_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedValue = try container.decodeIfPresent(HealthMdQueryValue.self, forKey: .value)
        reference = Self.normalizedReference(
            try container.decode(HealthMdEvidenceReference.self, forKey: .reference),
            value: decodedValue
        )
        value = decodedValue
        note = try container.decodeIfPresent(String.self, forKey: .note)
        metricIDs = Array(Set(try container.decodeIfPresent([String].self, forKey: .metricIDs) ?? [])).sorted()
    }

    private static func normalizedReference(
        _ reference: HealthMdEvidenceReference,
        value: HealthMdQueryValue?
    ) -> HealthMdEvidenceReference {
        guard reference.providerID == nil else { return reference }
        if let providerID = providerID(from: value) {
            return .init(
                evidenceID: reference.evidenceID,
                locator: reference.locator,
                source: reference.source,
                sourceID: HealthMdEvidenceSourceIDs.providerNative,
                providerID: providerID
            )
        }
        if isAppleExternalRecord(value) {
            return .init(
                evidenceID: reference.evidenceID,
                locator: reference.locator,
                source: reference.source,
                sourceID: HealthMdEvidenceSourceIDs.appleHealth
            )
        }
        return reference
    }

    private static func providerID(from value: HealthMdQueryValue?) -> String? {
        guard case .unknown(let type, let payload) = value,
              type == "external_provider_payload",
              case .object(let object)? = payload,
              case .string(let provider)? = object["provider"] else { return nil }
        return provider
    }

    private static func isAppleExternalRecord(_ value: HealthMdQueryValue?) -> Bool {
        guard case .unknown(let type, _) = value else { return false }
        return type == "canonical_healthkit_external_record" || type == "medication_inventory"
    }
}

// MARK: - Compact context-day v1

nonisolated struct HealthMdContextMetric: Codable, Equatable, Sendable {
    let observationID: String
    let metricID: String
    let displayName: String
    let value: HealthMdQueryValue?
    let status: HealthMdAvailabilityStatus
    let dailyAggregation: HealthMdDailyAggregation?
    let evidenceIDs: [String]
    let limitations: [HealthMdLimitation]
    init(observationID: String, metricID: String, displayName: String, value: HealthMdQueryValue?, status: HealthMdAvailabilityStatus, dailyAggregation: HealthMdDailyAggregation? = nil, evidenceIDs: [String] = [], limitations: [HealthMdLimitation] = []) {
        self.observationID = observationID; self.metricID = metricID; self.displayName = displayName
        self.value = value; self.status = status; self.dailyAggregation = dailyAggregation
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted()
        self.limitations = limitations.sorted { $0.code < $1.code }
    }
    enum CodingKeys: String, CodingKey { case observationID = "observation_id", metricID = "metric_id", displayName = "display_name", value, status, dailyAggregation = "daily_aggregation", evidenceIDs = "evidence_ids", limitations }
}

nonisolated struct HealthMdContextWorkout: Codable, Equatable, Sendable {
    let workoutID: String
    let activity: String
    let start: Date
    let end: Date
    let details: [String: HealthMdQueryValue]
    let evidenceIDs: [String]
    init(workoutID: String, activity: String, start: Date, end: Date, details: [String: HealthMdQueryValue] = [:], evidenceIDs: [String] = []) {
        self.workoutID = workoutID; self.activity = activity; self.start = start; self.end = end
        self.details = details; self.evidenceIDs = Array(Set(evidenceIDs)).sorted()
    }
    enum CodingKeys: String, CodingKey { case workoutID = "workout_id", activity, start, end, details, evidenceIDs = "evidence_ids" }
}

nonisolated enum HealthMdSleepSessionClassification: String, Codable, Equatable, Sendable {
    case overnight
    case nap
    case sleep
}

nonisolated enum HealthMdSleepCompleteness: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case truncatedAtStart = "truncated_at_start"
    case truncatedAtEnd = "truncated_at_end"
    case truncatedAtBoth = "truncated_at_both"
    case aggregated
    case outsideSession = "outside_session"
}

nonisolated struct HealthMdContextSleepStageInterval: Codable, Equatable, Sendable {
    let stage: String
    let start: Date
    let end: Date

    init(stage: String, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }
}

nonisolated struct HealthMdContextSleepSession: Codable, Equatable, Sendable {
    let sessionID: String
    let start: Date
    let end: Date
    let classification: HealthMdSleepSessionClassification
    let completeness: HealthMdSleepCompleteness
    let stageIntervals: [HealthMdContextSleepStageInterval]
    let aggregateStageDurations: [String: Double]
    let evidenceIDs: [String]
    let limitations: [HealthMdLimitation]

    init(
        sessionID: String,
        start: Date,
        end: Date,
        classification: HealthMdSleepSessionClassification,
        completeness: HealthMdSleepCompleteness,
        stageIntervals: [HealthMdContextSleepStageInterval] = [],
        aggregateStageDurations: [String: Double] = [:],
        evidenceIDs: [String] = [],
        limitations: [HealthMdLimitation] = []
    ) {
        self.sessionID = sessionID
        self.start = start
        self.end = end
        self.classification = classification
        self.completeness = completeness
        self.stageIntervals = stageIntervals.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.stage < $1.stage
        }
        self.aggregateStageDurations = aggregateStageDurations
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted()
        self.limitations = Array(Set(limitations)).sorted { $0.code < $1.code }
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case start, end, classification, completeness
        case stageIntervals = "stage_intervals"
        case aggregateStageDurations = "aggregate_stage_durations_seconds"
        case evidenceIDs = "evidence_ids"
        case limitations
    }
}

nonisolated struct HealthMdCompactContextDay: Codable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let ownerDate: String
    let intervalStart: Date
    let intervalEnd: Date
    let calendarTimeZone: String
    let source: HealthMdSourceDescriptor
    let status: HealthMdAvailabilityStatus
    let metrics: [HealthMdContextMetric]
    let workouts: [HealthMdContextWorkout]
    let sleepSessions: [HealthMdContextSleepSession]
    let evidence: [HealthMdContextEvidence]
    let limitations: [HealthMdLimitation]

    init(ownerDate: String, intervalStart: Date, intervalEnd: Date, calendarTimeZone: String, source: HealthMdSourceDescriptor, status: HealthMdAvailabilityStatus, metrics: [HealthMdContextMetric] = [], workouts: [HealthMdContextWorkout] = [], sleepSessions: [HealthMdContextSleepSession] = [], evidence: [HealthMdContextEvidence] = [], limitations: [HealthMdLimitation] = [], schema: String = HealthMdQuerySchemas.compactContextDay, schemaVersion: Int = 1) {
        self.schema = schema; self.schemaVersion = schemaVersion; self.ownerDate = ownerDate
        self.intervalStart = intervalStart; self.intervalEnd = intervalEnd; self.calendarTimeZone = calendarTimeZone
        self.source = source; self.status = status
        self.metrics = metrics.sorted { $0.metricID != $1.metricID ? $0.metricID < $1.metricID : $0.observationID < $1.observationID }
        self.workouts = workouts.sorted { $0.start != $1.start ? $0.start < $1.start : $0.workoutID < $1.workoutID }
        self.sleepSessions = sleepSessions.sorted { $0.start != $1.start ? $0.start < $1.start : $0.sessionID < $1.sessionID }
        self.evidence = evidence.sorted { $0.reference.evidenceID < $1.reference.evidenceID }
        self.limitations = limitations.sorted { $0.code < $1.code }
    }
    enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", ownerDate = "owner_date", intervalStart = "interval_start", intervalEnd = "interval_end", calendarTimeZone = "calendar_timezone", source, status, metrics, workouts, sleepSessions = "sleep_sessions", evidence, limitations }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ownerDate = try container.decode(String.self, forKey: .ownerDate)
        intervalStart = try container.decode(Date.self, forKey: .intervalStart)
        intervalEnd = try container.decode(Date.self, forKey: .intervalEnd)
        calendarTimeZone = try container.decode(String.self, forKey: .calendarTimeZone)
        source = try container.decode(HealthMdSourceDescriptor.self, forKey: .source)
        status = try container.decode(HealthMdAvailabilityStatus.self, forKey: .status)
        metrics = try container.decodeIfPresent([HealthMdContextMetric].self, forKey: .metrics) ?? []
        workouts = try container.decodeIfPresent([HealthMdContextWorkout].self, forKey: .workouts) ?? []
        sleepSessions = try container.decodeIfPresent([HealthMdContextSleepSession].self, forKey: .sleepSessions) ?? []
        evidence = try container.decodeIfPresent([HealthMdContextEvidence].self, forKey: .evidence) ?? []
        limitations = try container.decodeIfPresent([HealthMdLimitation].self, forKey: .limitations) ?? []
    }
}

// MARK: - Results and evidence packets

nonisolated struct HealthMdMetricPoint: Codable, Equatable, Sendable {
    let metricID: String; let displayName: String; let ownerDate: String
    let value: HealthMdQueryValue?; let status: HealthMdAvailabilityStatus
    let evidence: [HealthMdEvidenceReference]; let limitations: [HealthMdLimitation]
    enum CodingKeys: String, CodingKey { case metricID = "metric_id", displayName = "display_name", ownerDate = "owner_date", value, status, evidence, limitations }
}

nonisolated enum HealthMdComparisonDirection: String, Codable, Sendable { case increased, decreased, unchanged, notComparable = "not_comparable" }
nonisolated struct HealthMdPeriodComparison: Codable, Equatable, Sendable {
    let metricID: String; let aggregation: HealthMdAggregationDescriptor
    let firstRange: HealthMdDateRange; let secondRange: HealthMdDateRange
    let firstValue: HealthMdQueryValue?; let secondValue: HealthMdQueryValue?
    let absoluteChange: HealthMdQueryValue?; let percentChange: Double?
    let direction: HealthMdComparisonDirection; let coverage: HealthMdCoverage
    let evidence: [HealthMdEvidenceReference]; let limitations: [HealthMdLimitation]
    enum CodingKeys: String, CodingKey { case metricID = "metric_id", aggregation, firstRange = "first_range", secondRange = "second_range", firstValue = "first_value", secondValue = "second_value", absoluteChange = "absolute_change", percentChange = "percent_change", direction, coverage, evidence, limitations }
}

nonisolated struct HealthMdSleepPhysiologyCoverage: Codable, Equatable, Sendable {
    let metricID: String
    let status: HealthMdAvailabilityStatus
    let sampleCount: Int
    let firstSampleAt: Date?
    let lastSampleAt: Date?
    let observedOwnerDates: [String]
    let evidence: [HealthMdEvidenceReference]

    init(
        metricID: String,
        status: HealthMdAvailabilityStatus,
        sampleCount: Int,
        firstSampleAt: Date?,
        lastSampleAt: Date?,
        observedOwnerDates: [String],
        evidence: [HealthMdEvidenceReference]
    ) {
        self.metricID = metricID
        self.status = status
        self.sampleCount = sampleCount
        self.firstSampleAt = firstSampleAt
        self.lastSampleAt = lastSampleAt
        self.observedOwnerDates = Array(Set(observedOwnerDates)).sorted()
        self.evidence = Array(Set(evidence)).sorted { $0.evidenceID < $1.evidenceID }
    }

    enum CodingKeys: String, CodingKey {
        case metricID = "metric_id"
        case status
        case sampleCount = "sample_count"
        case firstSampleAt = "first_sample_at"
        case lastSampleAt = "last_sample_at"
        case observedOwnerDates = "observed_owner_dates"
        case evidence
    }
}

nonisolated struct HealthMdSleepSessionResult: Codable, Equatable, Sendable {
    let sessionID: String
    let ownerDate: String
    let calendarDates: [String]
    let classification: HealthMdSleepSessionClassification
    let completeness: HealthMdSleepCompleteness
    let start: Date
    let end: Date
    let localStart: String
    let localEnd: String
    let calendarTimeZone: String
    let analysisStart: Date
    let analysisEnd: Date
    let requestedWindow: HealthMdSleepWindow?
    let elapsedDurationSeconds: Double
    let observedDurationSeconds: Double
    let untrackedDurationSeconds: Double
    let asleepDurationSeconds: Double
    let awakeDurationSeconds: Double
    let stageDurationsSeconds: [String: Double]
    let physiology: [HealthMdSleepPhysiologyCoverage]
    let evidence: [HealthMdEvidenceReference]
    let limitations: [HealthMdLimitation]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case ownerDate = "owner_date"
        case calendarDates = "calendar_dates"
        case classification, completeness, start, end
        case localStart = "local_start"
        case localEnd = "local_end"
        case calendarTimeZone = "calendar_timezone"
        case analysisStart = "analysis_start"
        case analysisEnd = "analysis_end"
        case requestedWindow = "requested_window"
        case elapsedDurationSeconds = "elapsed_duration_seconds"
        case observedDurationSeconds = "observed_duration_seconds"
        case untrackedDurationSeconds = "untracked_duration_seconds"
        case asleepDurationSeconds = "asleep_duration_seconds"
        case awakeDurationSeconds = "awake_duration_seconds"
        case stageDurationsSeconds = "stage_durations_seconds"
        case physiology, evidence, limitations
    }
}

nonisolated enum HealthMdWorkoutSleepAlignmentStatus: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case unavailable
}

nonisolated struct HealthMdWorkoutSleepAlignment: Codable, Equatable, Sendable {
    let alignmentID: String
    let workout: HealthMdContextWorkout
    let precedingSleep: HealthMdSleepSessionResult?
    let followingSleep: HealthMdSleepSessionResult?
    let secondsFromPrecedingSleep: Double?
    let secondsUntilFollowingSleep: Double?
    let physiologySampleCount: Int
    let status: HealthMdWorkoutSleepAlignmentStatus
    let evidence: [HealthMdEvidenceReference]
    let limitations: [HealthMdLimitation]

    init(
        alignmentID: String,
        workout: HealthMdContextWorkout,
        precedingSleep: HealthMdSleepSessionResult?,
        followingSleep: HealthMdSleepSessionResult?,
        secondsFromPrecedingSleep: Double?,
        secondsUntilFollowingSleep: Double?,
        physiologySampleCount: Int,
        status: HealthMdWorkoutSleepAlignmentStatus,
        evidence: [HealthMdEvidenceReference],
        limitations: [HealthMdLimitation]
    ) {
        self.alignmentID = alignmentID
        self.workout = workout
        self.precedingSleep = precedingSleep
        self.followingSleep = followingSleep
        self.secondsFromPrecedingSleep = secondsFromPrecedingSleep
        self.secondsUntilFollowingSleep = secondsUntilFollowingSleep
        self.physiologySampleCount = physiologySampleCount
        self.status = status
        self.evidence = Array(Set(evidence)).sorted { $0.evidenceID < $1.evidenceID }
        self.limitations = Array(Set(limitations)).sorted { $0.code < $1.code }
    }

    enum CodingKeys: String, CodingKey {
        case alignmentID = "alignment_id"
        case workout
        case precedingSleep = "preceding_sleep"
        case followingSleep = "following_sleep"
        case secondsFromPrecedingSleep = "seconds_from_preceding_sleep"
        case secondsUntilFollowingSleep = "seconds_until_following_sleep"
        case physiologySampleCount = "physiology_sample_count"
        case status, evidence, limitations
    }
}

nonisolated enum HealthMdQueryItem: Codable, Equatable, Sendable {
    case metric(HealthMdMetricPoint)
    case comparison(HealthMdPeriodComparison)
    case workout(HealthMdContextWorkout)
    case sleepSession(HealthMdSleepSessionResult)
    case workoutSleepAlignment(HealthMdWorkoutSleepAlignment)
    case evidence(HealthMdContextEvidence)
    private enum CodingKeys: String, CodingKey { case type, metric, comparison, workout, sleepSession = "sleep_session", workoutSleepAlignment = "workout_sleep_alignment", evidence }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); switch self {
        case .metric(let v): try c.encode("metric", forKey: .type); try c.encode(v, forKey: .metric)
        case .comparison(let v): try c.encode("comparison", forKey: .type); try c.encode(v, forKey: .comparison)
        case .workout(let v): try c.encode("workout", forKey: .type); try c.encode(v, forKey: .workout)
        case .sleepSession(let v): try c.encode("sleep_session", forKey: .type); try c.encode(v, forKey: .sleepSession)
        case .workoutSleepAlignment(let v): try c.encode("workout_sleep_alignment", forKey: .type); try c.encode(v, forKey: .workoutSleepAlignment)
        case .evidence(let v): try c.encode("evidence", forKey: .type); try c.encode(v, forKey: .evidence) } }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); switch try c.decode(String.self, forKey: .type) {
        case "metric": self = .metric(try c.decode(HealthMdMetricPoint.self, forKey: .metric))
        case "comparison": self = .comparison(try c.decode(HealthMdPeriodComparison.self, forKey: .comparison))
        case "workout": self = .workout(try c.decode(HealthMdContextWorkout.self, forKey: .workout))
        case "sleep_session": self = .sleepSession(try c.decode(HealthMdSleepSessionResult.self, forKey: .sleepSession))
        case "workout_sleep_alignment": self = .workoutSleepAlignment(try c.decode(HealthMdWorkoutSleepAlignment.self, forKey: .workoutSleepAlignment))
        case "evidence": self = .evidence(try c.decode(HealthMdContextEvidence.self, forKey: .evidence))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown query item") } }
}

nonisolated struct HealthMdPacketFact: Codable, Equatable, Sendable {
    let factID: String; let label: String; let ownerDate: String?; let value: HealthMdQueryValue
    let evidence: [HealthMdEvidenceReference]
    init(factID: String, label: String, ownerDate: String? = nil, value: HealthMdQueryValue, evidence: [HealthMdEvidenceReference]) { self.factID = factID; self.label = label; self.ownerDate = ownerDate; self.value = value; self.evidence = evidence.sorted { $0.evidenceID < $1.evidenceID } }
    enum CodingKeys: String, CodingKey { case factID = "fact_id", label, ownerDate = "owner_date", value, evidence }
}

nonisolated struct HealthMdEvidencePacketMetadata: Codable, Equatable, Sendable {
    let generatedAt: Date
    let producer: String
    init(generatedAt: Date = Date(), producer: String = "Health.md") { self.generatedAt = generatedAt; self.producer = producer }
    enum CodingKeys: String, CodingKey { case generatedAt = "generated_at", producer }
}

nonisolated struct HealthMdEvidencePacket: Codable, Equatable, Sendable {
    let schema: String; let schemaVersion: Int; let packetID: String
    let kind: HealthMdPacketKind; let range: HealthMdDateRange?
    let facts: [HealthMdPacketFact]; let coverage: HealthMdCoverage
    let sources: [HealthMdSourceDescriptor]; let limitations: [HealthMdLimitation]
    let metadata: HealthMdEvidencePacketMetadata
    enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", packetID = "packet_id", kind, range, facts, coverage, sources, limitations, metadata }
}

nonisolated struct HealthMdQueryResponse: Codable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let items: [HealthMdQueryItem]
    let packet: HealthMdEvidencePacket?
    let coverage: HealthMdCoverage
    let sources: [HealthMdSourceDescriptor]
    let evidence: [HealthMdEvidenceReference]
    let nextCursor: String?
    let limitations: [HealthMdLimitation]
    let metadata: [String: HealthMdJSONValue]?

    init(
        items: [HealthMdQueryItem],
        packet: HealthMdEvidencePacket?,
        coverage: HealthMdCoverage,
        sources: [HealthMdSourceDescriptor],
        evidence: [HealthMdEvidenceReference],
        nextCursor: String?,
        limitations: [HealthMdLimitation],
        metadata: [String: HealthMdJSONValue]? = nil,
        schema: String = HealthMdQuerySchemas.queryResponse,
        schemaVersion: Int = HealthMdQuerySchemas.version
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.items = items
        self.packet = packet
        self.coverage = coverage
        self.sources = sources
        self.evidence = evidence
        self.nextCursor = nextCursor
        self.limitations = limitations
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case schema, schemaVersion = "schema_version", items, packet, coverage, sources, evidence
        case nextCursor = "next_cursor"
        case limitations, metadata
    }
}

/// Capabilities injected by the caller. Packet derivation cannot disclose anything outside this scope.
nonisolated struct HealthMdEvidenceScope: Equatable, Sendable {
    let allowedMetricIDs: Set<String>
    let allowedDetailIDs: Set<String>
    let allowsWorkouts: Bool
    /// Nil means every stable query source identity is authorized.
    let allowedSourceIDs: Set<String>?
    /// Nil means every provider identity is authorized.
    let allowedProviderIDs: Set<String>?
    let allowsEvidenceValues: Bool

    init(
        allowedMetricIDs: Set<String>,
        allowedDetailIDs: Set<String> = [],
        allowsWorkouts: Bool = false,
        allowedSourceIDs: Set<String>? = nil,
        allowedProviderIDs: Set<String>? = nil,
        allowsEvidenceValues: Bool = false
    ) {
        self.allowedMetricIDs = allowedMetricIDs
        self.allowedDetailIDs = allowedDetailIDs
        self.allowsWorkouts = allowsWorkouts
        self.allowedSourceIDs = allowedSourceIDs
        self.allowedProviderIDs = allowedProviderIDs
        self.allowsEvidenceValues = allowsEvidenceValues
    }
}
