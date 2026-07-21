import Foundation

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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "explicit": self = .explicit(Array(Set(try c.decode([String].self, forKey: .metricIDs))).sorted())
        case "all_available": self = .allAvailable
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown metric selection")
        }
    }
}

nonisolated struct HealthMdDateRange: Codable, Equatable, Sendable {
    let startDate: String
    let endDate: String
    init(startDate: String, endDate: String) { self.startDate = startDate; self.endDate = endDate }
    enum CodingKeys: String, CodingKey { case startDate = "start_date", endDate = "end_date" }
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "exact": self = .exact(try c.decode(HealthMdDateRange.self, forKey: .range))
        case "all_available": self = .allAvailable
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown date selection")
        }
    }
}

nonisolated enum HealthMdAggregationKind: String, Codable, Equatable, Sendable {
    case sum, average, minimum, maximum, latest, count
    case durationSum = "duration_sum"
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

nonisolated enum HealthMdQueryOperation: Codable, Equatable, Sendable {
    case metricSeries
    case periodComparison(first: HealthMdDateRange, second: HealthMdDateRange, aggregations: [HealthMdAggregationDescriptor])
    case workoutListing
    case coverage
    case derivePacket(kind: HealthMdPacketKind, detailIDs: [String])

    private enum CodingKeys: String, CodingKey { case type, first, second, aggregations, kind, detailIDs = "detail_ids" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metricSeries: try c.encode("metric_series", forKey: .type)
        case .periodComparison(let first, let second, let aggregations):
            try c.encode("period_comparison", forKey: .type); try c.encode(first, forKey: .first)
            try c.encode(second, forKey: .second)
            try c.encode(aggregations.sorted { $0.metricID < $1.metricID }, forKey: .aggregations)
        case .workoutListing: try c.encode("workout_listing", forKey: .type)
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
    let dates: HealthMdDateSelection
    let operation: HealthMdQueryOperation
    let page: HealthMdPageControls

    init(metrics: HealthMdMetricSelection, dates: HealthMdDateSelection, operation: HealthMdQueryOperation, page: HealthMdPageControls = .init(), schema: String = HealthMdQuerySchemas.queryRequest, schemaVersion: Int = 1) {
        self.schema = schema; self.schemaVersion = schemaVersion; self.metrics = metrics
        self.dates = dates; self.operation = operation; self.page = page
    }
    enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", metrics, dates, operation, page }
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
}

nonisolated struct HealthMdEvidenceReference: Codable, Equatable, Hashable, Sendable {
    let evidenceID: String
    let locator: HealthMdEvidenceLocator
    let source: HealthMdSourceDescriptor
    init(evidenceID: String, locator: HealthMdEvidenceLocator, source: HealthMdSourceDescriptor) { self.evidenceID = evidenceID; self.locator = locator; self.source = source }
    enum CodingKeys: String, CodingKey { case evidenceID = "evidence_id", locator, source }
}

nonisolated struct HealthMdContextEvidence: Codable, Equatable, Sendable {
    let reference: HealthMdEvidenceReference
    let value: HealthMdQueryValue?
    let note: String?
    init(reference: HealthMdEvidenceReference, value: HealthMdQueryValue? = nil, note: String? = nil) { self.reference = reference; self.value = value; self.note = note }
}

// MARK: - Compact context-day v1

nonisolated struct HealthMdContextMetric: Codable, Equatable, Sendable {
    let observationID: String
    let metricID: String
    let displayName: String
    let value: HealthMdQueryValue?
    let status: HealthMdAvailabilityStatus
    let evidenceIDs: [String]
    let limitations: [HealthMdLimitation]
    init(observationID: String, metricID: String, displayName: String, value: HealthMdQueryValue?, status: HealthMdAvailabilityStatus, evidenceIDs: [String] = [], limitations: [HealthMdLimitation] = []) {
        self.observationID = observationID; self.metricID = metricID; self.displayName = displayName
        self.value = value; self.status = status; self.evidenceIDs = Array(Set(evidenceIDs)).sorted()
        self.limitations = limitations.sorted { $0.code < $1.code }
    }
    enum CodingKeys: String, CodingKey { case observationID = "observation_id", metricID = "metric_id", displayName = "display_name", value, status, evidenceIDs = "evidence_ids", limitations }
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
    let evidence: [HealthMdContextEvidence]
    let limitations: [HealthMdLimitation]

    init(ownerDate: String, intervalStart: Date, intervalEnd: Date, calendarTimeZone: String, source: HealthMdSourceDescriptor, status: HealthMdAvailabilityStatus, metrics: [HealthMdContextMetric] = [], workouts: [HealthMdContextWorkout] = [], evidence: [HealthMdContextEvidence] = [], limitations: [HealthMdLimitation] = [], schema: String = HealthMdQuerySchemas.compactContextDay, schemaVersion: Int = 1) {
        self.schema = schema; self.schemaVersion = schemaVersion; self.ownerDate = ownerDate
        self.intervalStart = intervalStart; self.intervalEnd = intervalEnd; self.calendarTimeZone = calendarTimeZone
        self.source = source; self.status = status
        self.metrics = metrics.sorted { $0.metricID != $1.metricID ? $0.metricID < $1.metricID : $0.observationID < $1.observationID }
        self.workouts = workouts.sorted { $0.start != $1.start ? $0.start < $1.start : $0.workoutID < $1.workoutID }
        self.evidence = evidence.sorted { $0.reference.evidenceID < $1.reference.evidenceID }
        self.limitations = limitations.sorted { $0.code < $1.code }
    }
    enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", ownerDate = "owner_date", intervalStart = "interval_start", intervalEnd = "interval_end", calendarTimeZone = "calendar_timezone", source, status, metrics, workouts, evidence, limitations }
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

nonisolated enum HealthMdQueryItem: Codable, Equatable, Sendable {
    case metric(HealthMdMetricPoint)
    case comparison(HealthMdPeriodComparison)
    case workout(HealthMdContextWorkout)
    private enum CodingKeys: String, CodingKey { case type, metric, comparison, workout }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); switch self {
        case .metric(let v): try c.encode("metric", forKey: .type); try c.encode(v, forKey: .metric)
        case .comparison(let v): try c.encode("comparison", forKey: .type); try c.encode(v, forKey: .comparison)
        case .workout(let v): try c.encode("workout", forKey: .type); try c.encode(v, forKey: .workout) } }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); switch try c.decode(String.self, forKey: .type) {
        case "metric": self = .metric(try c.decode(HealthMdMetricPoint.self, forKey: .metric))
        case "comparison": self = .comparison(try c.decode(HealthMdPeriodComparison.self, forKey: .comparison))
        case "workout": self = .workout(try c.decode(HealthMdContextWorkout.self, forKey: .workout))
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

    init(
        items: [HealthMdQueryItem],
        packet: HealthMdEvidencePacket?,
        coverage: HealthMdCoverage,
        sources: [HealthMdSourceDescriptor],
        evidence: [HealthMdEvidenceReference],
        nextCursor: String?,
        limitations: [HealthMdLimitation],
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
    }

    enum CodingKeys: String, CodingKey {
        case schema, schemaVersion = "schema_version", items, packet, coverage, sources, evidence
        case nextCursor = "next_cursor"
        case limitations
    }
}

/// Capabilities injected by the caller. Packet derivation cannot disclose anything outside this scope.
nonisolated struct HealthMdEvidenceScope: Equatable, Sendable {
    let allowedMetricIDs: Set<String>
    let allowedDetailIDs: Set<String>
    let allowsWorkouts: Bool
    init(allowedMetricIDs: Set<String>, allowedDetailIDs: Set<String> = [], allowsWorkouts: Bool = false) {
        self.allowedMetricIDs = allowedMetricIDs; self.allowedDetailIDs = allowedDetailIDs; self.allowsWorkouts = allowsWorkouts
    }
}
