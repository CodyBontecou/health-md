import Foundation

/// Access evidence observed before capture, not a grant, capture result, or current permission.
/// Frozen with the operation; resumed work must not replace it with newer evidence.
public struct ExportHistoryObservation: Codable, Equatable, Sendable {
    public static let schemaName = "healthmd.export_history_observation"
    public static let maximumBytes = 256 * 1_024
    public let schema: String
    public let schemaVersion: Int
    public let observationID: String
    public let operationID: String
    public let observedAt: String
    public let requestBindingSHA256: String
    public let sourceID: String
    public let sourceInstallationID: String?
    public let destinationInstallationID: String?
    public let timeZoneIdentifier: String
    public let metricIDs: [String]
    public let requestedStart: String
    public let requestedEnd: String
    public let allAvailable: Bool
    public let rangeSemantics: String
    public let evidenceMethod: String
    public let types: [ExportHistoryTypeObservation]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, types
        case schemaVersion = "schema_version"
        case observationID = "observation_id"
        case operationID = "operation_id"
        case observedAt = "observed_at"
        case requestBindingSHA256 = "request_binding_sha256"
        case sourceID = "source_id"
        case sourceInstallationID = "source_installation_id"
        case destinationInstallationID = "destination_installation_id"
        case timeZoneIdentifier = "time_zone_identifier"
        case metricIDs = "metric_ids"
        case requestedStart = "requested_start"
        case requestedEnd = "requested_end"
        case allAvailable = "all_available"
        case rangeSemantics = "range_semantics"
        case evidenceMethod = "evidence_method"
    }

    public init(observationID: UUID, operationID: UUID, observedAt: String,
                requestBindingSHA256: String, sourceInstallationID: UUID? = nil,
                destinationInstallationID: UUID? = nil, timeZoneIdentifier: String,
                metricIDs: [String], requestedStart: String, requestedEnd: String,
                allAvailable: Bool, rangeSemantics: String, evidenceMethod: String,
                types: [ExportHistoryTypeObservation]) throws {
        schema = Self.schemaName
        schemaVersion = 1
        self.observationID = observationID.uuidString.lowercased()
        self.operationID = operationID.uuidString.lowercased()
        self.observedAt = observedAt
        self.requestBindingSHA256 = requestBindingSHA256
        sourceID = "apple.healthkit"
        self.sourceInstallationID = sourceInstallationID?.uuidString.lowercased()
        self.destinationInstallationID = destinationInstallationID?.uuidString.lowercased()
        self.timeZoneIdentifier = timeZoneIdentifier
        self.metricIDs = metricIDs
        self.requestedStart = requestedStart
        self.requestedEnd = requestedEnd
        self.allAvailable = allAvailable
        self.rangeSemantics = rangeSemantics
        self.evidenceMethod = evidenceMethod
        self.types = types
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownObservationKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        observationID = try c.decode(String.self, forKey: .observationID)
        operationID = try c.decode(String.self, forKey: .operationID)
        observedAt = try c.decode(String.self, forKey: .observedAt)
        requestBindingSHA256 = try c.decode(String.self, forKey: .requestBindingSHA256)
        sourceID = try c.decode(String.self, forKey: .sourceID)
        sourceInstallationID = try c.decodeIfPresent(String.self, forKey: .sourceInstallationID)
        destinationInstallationID = try c.decodeIfPresent(String.self, forKey: .destinationInstallationID)
        timeZoneIdentifier = try c.decode(String.self, forKey: .timeZoneIdentifier)
        metricIDs = try c.decode([String].self, forKey: .metricIDs)
        requestedStart = try c.decode(String.self, forKey: .requestedStart)
        requestedEnd = try c.decode(String.self, forKey: .requestedEnd)
        allAvailable = try c.decode(Bool.self, forKey: .allAvailable)
        rangeSemantics = try c.decode(String.self, forKey: .rangeSemantics)
        evidenceMethod = try c.decode(String.self, forKey: .evidenceMethod)
        types = try c.decode([ExportHistoryTypeObservation].self, forKey: .types)
        try validate()
    }

    public enum ValidationError: Error { case invalidObservation }

    private func validate() throws {
        func require(_ valid: Bool) throws {
            guard valid else { throw ValidationError.invalidObservation }
        }
        func validUUID(_ value: String) -> Bool {
            UUID(uuidString: value)?.uuidString.lowercased() == value
        }
        func identifiers(_ values: [String]) -> Bool {
            values.count <= 512 && values == Array(Set(values)).sorted()
                && values.allSatisfy { value in
                    !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
                        (48...57).contains($0) || (65...90).contains($0)
                            || (97...122).contains($0) || [95, 46, 58, 45].contains($0)
                    }
                }
        }
        func instant(_ value: String) -> Bool {
            let bytes = Array(value.utf8)
            guard bytes.count == 30 else { return false }
            let separators: [Int: UInt8] = [4: 45, 7: 45, 10: 84, 13: 58, 16: 58, 19: 46, 29: 90]
            for (index, byte) in bytes.enumerated() {
                if let separator = separators[index] {
                    guard byte == separator else { return false }
                } else if !(48...57).contains(byte) { return false }
            }
            func number(_ range: Range<Int>) -> Int {
                bytes[range].reduce(0) { $0 * 10 + Int($1 - 48) }
            }
            let year = number(0..<4), month = number(5..<7), day = number(8..<10)
            guard year > 0, (1...12).contains(month) else { return false }
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            return (1...monthDays[month - 1]).contains(day) && number(11..<13) < 24
                && number(14..<16) < 60 && number(17..<19) < 60
        }
        try require(schema == Self.schemaName && schemaVersion == 1)
        try require(validUUID(observationID) && validUUID(operationID))
        try require(sourceInstallationID == nil && destinationInstallationID == nil
                    || sourceInstallationID.map(validUUID) == true && destinationInstallationID.map(validUUID) == true)
        try require(requestBindingSHA256.count == 64 && requestBindingSHA256.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        })
        try require(sourceID == "apple.healthkit" && instant(observedAt))
        try require(instant(requestedStart) && instant(requestedEnd) && requestedStart <= requestedEnd)
        try require(TimeZone.knownTimeZoneIdentifiers.contains(timeZoneIdentifier) || ["UTC", "GMT"].contains(timeZoneIdentifier))
        try require(!metricIDs.isEmpty && identifiers(metricIDs) && identifiers([evidenceMethod]))
        try require(["owner_dates", "exact_interval"].contains(rangeSemantics))
        try require(types.count <= 512 && identifiers(types.map(\.typeID)))
        let selected = Set(metricIDs)
        var directlyAttributed = Set<String>()
        for row in types {
            try require(identifiers(row.directMetricIDs) && identifiers(row.dependencyMetricIDs)
                        && identifiers(row.dependencyReasons))
            try require(!row.directMetricIDs.isEmpty || !row.dependencyMetricIDs.isEmpty)
            try require(row.dependencyReasons.isEmpty || !row.dependencyMetricIDs.isEmpty)
            try require(Set(row.directMetricIDs + row.dependencyMetricIDs).isSubset(of: selected))
            directlyAttributed.formUnion(row.directMetricIDs)
            switch row.outcome {
            case "limited":
                try require(row.sampleEndBoundary.map(instant) == true && row.unassessedReason == nil)
            case "unknown", "api_unavailable", "assessment_failed":
                try require(row.sampleEndBoundary == nil && row.unassessedReason == nil)
            case "unassessed":
                try require(row.sampleEndBoundary == nil && row.unassessedReason.map { identifiers([$0]) } == true)
            default: throw ValidationError.invalidObservation
            }
        }
        try require(directlyAttributed == selected)
        try require(try JSONEncoder().encode(self).count <= Self.maximumBytes)
    }
}

public struct ExportHistoryTypeObservation: Codable, Equatable, Sendable {
    public let typeID: String
    public let directMetricIDs: [String]
    public let dependencyMetricIDs: [String]
    public let dependencyReasons: [String]
    public let outcome: String
    public let sampleEndBoundary: String?
    public let unassessedReason: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
        case typeID = "type_id"
        case directMetricIDs = "direct_metric_ids"
        case dependencyMetricIDs = "dependency_metric_ids"
        case dependencyReasons = "dependency_reasons"
        case sampleEndBoundary = "sample_end_boundary"
        case unassessedReason = "unassessed_reason"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownObservationKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        typeID = try c.decode(String.self, forKey: .typeID)
        directMetricIDs = try c.decode([String].self, forKey: .directMetricIDs)
        dependencyMetricIDs = try c.decode([String].self, forKey: .dependencyMetricIDs)
        dependencyReasons = try c.decode([String].self, forKey: .dependencyReasons)
        outcome = try c.decode(String.self, forKey: .outcome)
        sampleEndBoundary = try c.decodeIfPresent(String.self, forKey: .sampleEndBoundary)
        unassessedReason = try c.decodeIfPresent(String.self, forKey: .unassessedReason)
    }

    public init(typeID: String, directMetricIDs: [String], dependencyMetricIDs: [String] = [],
                dependencyReasons: [String] = [], outcome: String, sampleEndBoundary: String? = nil,
                unassessedReason: String? = nil) {
        self.typeID = typeID
        self.directMetricIDs = directMetricIDs
        self.dependencyMetricIDs = dependencyMetricIDs
        self.dependencyReasons = dependencyReasons
        self.outcome = outcome
        self.sampleEndBoundary = sampleEndBoundary
        self.unassessedReason = unassessedReason
    }
}

private struct ObservationCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownObservationKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: ObservationCodingKey.self)
    guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw ExportHistoryObservation.ValidationError.invalidObservation
    }
}

extension ExportHistoryObservation {
    /// Authenticate scope against the receiver's existing immutable job authority.
    /// This binds evidence to a request; it still makes no full-history claim.
    public func matches(request: DirectExportRequest, accepted: DirectExportAccepted,
                        session: DirectTransferSession) -> Bool {
        guard operationID == request.jobID.uuidString.lowercased(),
              accepted.jobID == request.jobID, session.jobID == request.jobID,
              requestBindingSHA256 == session.requestFingerprint.sha256,
              sourceInstallationID == session.peerBinding.sourceInstallationID.uuidString.lowercased(),
              destinationInstallationID == session.peerBinding.destinationInstallationID.uuidString.lowercased(),
              session.peerBinding == accepted.peerBinding,
              timeZoneIdentifier == accepted.sourceTimeZoneIdentifier,
              rangeSemantics == "owner_dates" else { return false }
        guard let metrics = accepted.resolvedCanonicalSelection?.metricIDs,
              metricIDs == metrics.sorted() else { return false }
        let instantFormatter = ISO8601DateFormatter()
        instantFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        guard let start = instantFormatter.date(from: requestedStart),
              let end = instantFormatter.date(from: requestedEnd) else { return false }
        let startDay = dayFormatter.string(from: start), endDay = dayFormatter.string(from: end)
        switch request.dateSelection {
        case .exact(let start, let end):
            return !allAvailable && startDay == start && endDay == end
        case .allAvailable:
            return allAvailable && startDay == accepted.resolvedDateIdentifiers.first
                && endDay == accepted.resolvedDateIdentifiers.last
        }
    }
}
