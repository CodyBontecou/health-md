import CryptoKit
import Foundation

/// Query-only, immutable observation. No daily/export/raw/packet schema adoption.
/// The receipt is not a grant token, a current permission epoch, or capture coverage.
nonisolated struct HealthHistoryQueryCapture: Sendable {
    static let maximumReceiptBytes = 256 * 1_024
    static let maximumIdentifiers = 512
    static let maximumIdentifierBytes = 128

    let days: [HealthMdCompactContextDay]
    let metricIDs: Set<String>
    let logicalMetrics: HealthMdMetricSelection
    let sources: HealthMdSourceSelection
    let logicalDates: HealthMdDateSelection
    let timeZoneIdentifier: String
    let captureID: UUID
    let receipt: HealthMdJSONValue
    let receiptDigest: String
    let datasetDigest: String
    let peerInstallationID: UUID
    let sourceInstallationID: UUID
    let limitations: [HealthMdLimitation]

    init(days: [HealthMdCompactContextDay], metricIDs: Set<String>, query: HealthMdQueryRequest,
         assessment: HealthHistoryAssessment, timeZone: TimeZone, ownerDates: [String],
         peerInstallationID: UUID, sourceInstallationID: UUID,
         captureID: UUID = UUID(), capturedAt: Date = Date()) throws {
        guard metricIDs.count <= Self.maximumIdentifiers, assessment.types.count <= Self.maximumIdentifiers else {
            throw HealthMdQueryContractError.singleItemExceedsPageBytes
        }
        guard assessment.scope.metricIDs == metricIDs,
              assessment.scope.timeZoneIdentifier == timeZone.identifier,
              assessment.scope.rangeSemantics == .ownerDates,
              !metricIDs.isEmpty,
              Set(assessment.types.map(\.id)).count == assessment.types.count,
              ownerDates.count <= 366_000, !ownerDates.isEmpty,
              capturedAt.timeIntervalSince1970.isFinite,
              assessment.assessedAt.timeIntervalSince1970.isFinite else {
            throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
        }
        // This v3 producer supports Apple/Apple-derived summary sources only.
        // Refuse provider-only scope instead of projecting Apple restrictions onto it.
        let resolvedSourceIDs: [String]
        switch query.sources {
        case .allAvailable:
            resolvedSourceIDs = [HealthMdEvidenceSourceIDs.appleHealth, HealthMdEvidenceSourceIDs.healthMdSummary].sorted()
        case .explicit(let ids, let providers):
            guard providers.isEmpty, !ids.isEmpty,
                  Set(ids).isSubset(of: [HealthMdEvidenceSourceIDs.appleHealth, HealthMdEvidenceSourceIDs.healthMdSummary]) else {
                throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
            }
            resolvedSourceIDs = Array(Set(ids)).sorted()
        }
        if case .explicit(let ids) = query.metrics, Set(ids) != metricIDs {
            throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
        }
        switch query.dates {
        case .allAvailable:
            guard assessment.scope.allAvailable else { throw HealthMdQueryContractError.scopeViolation("history_assessment_scope") }
        case .exact(let range):
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            guard !assessment.scope.allAvailable,
                  formatter.string(from: assessment.scope.startDate) == range.startDate,
                  formatter.string(from: assessment.scope.endDate) == range.endDate,
                  ownerDates.allSatisfy({ $0 >= range.startDate && $0 <= range.endDate }) else {
                throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
            }
        }
        guard Set(days.map(\.ownerDate)) == Set(ownerDates), days.count == ownerDates.count,
              Set(ownerDates).count == ownerDates.count,
              days.allSatisfy({ $0.calendarTimeZone == timeZone.identifier }),
              assessment.evidenceSource.utf8.count <= Self.maximumIdentifierBytes,
              timeZone.identifier.utf8.count <= Self.maximumIdentifierBytes,
              TimeZone.knownTimeZoneIdentifiers.contains(timeZone.identifier) || ["GMT", "UTC"].contains(timeZone.identifier) else {
            throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
        }
        var identifierBytes = 0
        func validate(_ ids: [String]) throws {
            guard ids.count <= Self.maximumIdentifiers, Set(ids).count == ids.count else {
                throw HealthMdQueryContractError.singleItemExceedsPageBytes
            }
            for id in ids {
                guard !id.isEmpty, id.utf8.count <= Self.maximumIdentifierBytes,
                      id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [95, 46, 58, 45].contains($0) }) else {
                    throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
                }
                identifierBytes += id.utf8.count
                guard identifierBytes <= Self.maximumReceiptBytes else {
                    throw HealthMdQueryContractError.singleItemExceedsPageBytes
                }
            }
        }
        try validate(metricIDs.sorted())
        var directlyAttributed = Set<String>()
        for row in assessment.types {
            try validate([row.id])
            try validate(row.directMetricIDs)
            try validate(row.dependencyMetricIDs)
            try validate(row.dependencyReasons)
            guard Set(row.directMetricIDs + row.dependencyMetricIDs).isSubset(of: metricIDs) else {
                throw HealthMdQueryContractError.scopeViolation("history_assessment_scope")
            }
            if case .unassessed(let reason) = row.access { try validate([reason]) }
            directlyAttributed.formUnion(row.directMetricIDs)
        }
        guard directlyAttributed == metricIDs else { throw HealthMdQueryContractError.scopeViolation("history_assessment_scope") }

        let sortedDays = days.sorted {
            if $0.ownerDate != $1.ownerDate { return $0.ownerDate < $1.ownerDate }
            return $0.source.digest < $1.source.digest
        }
        let datasetDigest = try HealthMdQueryCanonicalSerializer.sha256(of: sortedDays)
        let sortedOwnerDates = Array(Set(ownerDates)).sorted()
        func json<T: Encodable>(_ value: T) throws -> HealthMdJSONValue {
            try JSONDecoder().decode(HealthMdJSONValue.self, from: HealthMdQueryCanonicalSerializer.data(for: value))
        }
        let rows: [HealthMdJSONValue] = try assessment.types.sorted { $0.id < $1.id }.map { row in
            var value: [String: HealthMdJSONValue] = [
                "type_id": .string(row.id),
                "direct_metric_ids": .array(row.directMetricIDs.sorted().map(HealthMdJSONValue.string)),
                "dependency_metric_ids": .array(row.dependencyMetricIDs.sorted().map(HealthMdJSONValue.string)),
                "dependency_reasons": .array(row.dependencyReasons.sorted().map(HealthMdJSONValue.string)),
                "intersection": .string("unknown")
            ]
            switch row.access {
            case .limited(let boundary):
                value["outcome"] = .string("limited")
                // Use the existing exact nine-fractional-digit instant codec, not
                // civil midnight, display text, or whole-second transport dates.
                value["sample_end_boundary"] = try json(boundary)
                value["intersection"] = .string(row.limitationIntersects(assessment.scope) ? "potential" : "no_known_intersection")
            case .unknown: value["outcome"] = .string("unknown")
            case .apiUnavailable: value["outcome"] = .string("api_unavailable")
            case .assessmentFailed: value["outcome"] = .string("assessment_failed")
            case .unassessed(let reason):
                value["outcome"] = .string("unassessed")
                value["unassessed_reason"] = .string(reason)
            }
            return .object(value)
        }
        let receipt: HealthMdJSONValue = .object([
            "schema": .string("healthmd.history_assessment"), "schema_version": .integer(1),
            "assessment_id": .string(assessment.id.uuidString.lowercased()),
            "capture_id": .string(captureID.uuidString.lowercased()),
            "observed_at": try json(assessment.assessedAt),
            "capture_completed_at": try json(capturedAt),
            "evidence_method": .string(assessment.evidenceSource),
            "producer": .string("Health.md"), "platform": .string("apple_healthkit"),
            "calendar_identifier": .string("gregorian"), "time_zone_identifier": .string(timeZone.identifier),
            "boundary_semantics": .string("sample_end_instant"),
            "boundary_equality_physically_verified": .boolean(false),
            "logical_metrics": try json(query.metrics), "resolved_metric_ids": .array(metricIDs.sorted().map(HealthMdJSONValue.string)),
            "logical_sources": try json(query.sources),
            "resolved_source_ids": .array(resolvedSourceIDs.map(HealthMdJSONValue.string)),
            "resolved_provider_ids": .array([]), "logical_dates": try json(query.dates),
            "resolved_owner_dates": .object([
                "count": .integer(Int64(sortedOwnerDates.count)),
                "digest": .string(try HealthMdQueryCanonicalSerializer.sha256(of: sortedOwnerDates)),
                "first": .string(sortedOwnerDates.first!), "last": .string(sortedOwnerDates.last!)
            ]),
            "types": .array(rows), "dataset_digest": .string(datasetDigest),
            "trusted_peer_installation_id": .string(peerInstallationID.uuidString.lowercased()),
            "source_installation_id": .string(sourceInstallationID.uuidString.lowercased())
        ])
        let encoded = try HealthMdQueryCanonicalSerializer.data(for: receipt)
        guard encoded.count <= Self.maximumReceiptBytes else {
            throw HealthMdQueryContractError.singleItemExceedsPageBytes
        }
        self.days = sortedDays
        self.metricIDs = metricIDs
        self.logicalMetrics = query.metrics
        self.sources = query.sources
        self.logicalDates = query.dates
        self.timeZoneIdentifier = timeZone.identifier
        self.captureID = captureID
        self.receipt = receipt
        self.receiptDigest = try HealthMdQueryCanonicalSerializer.sha256(of: receipt)
        self.datasetDigest = datasetDigest
        self.peerInstallationID = peerInstallationID
        self.sourceInstallationID = sourceInstallationID
        self.limitations = [
            .init(code: "history_assessment_observation", message: "History assessment is an observation at capture time, not current permission or full-history certification. Boundaries concern sample ends; earlier starts and owner dates are preserved."),
            .init(code: assessment.hasIntersectingLimit ? "history_sample_end_limited" : "history_access_unverified", message: assessment.hasIntersectingLimit ? "Some selected Apple history may be unavailable. Earlier data is unknown, not missing. Readable records remain included." : "No full-history claim is possible. Omitted boundaries, empty results and completed capture do not establish historical authorization.")
        ]
    }

    var metadata: [String: HealthMdJSONValue] { ["history_assessment": receipt] }

    /// Existing opaque cursor caller binding; request and dataset fingerprints
    /// and public cursor grammar remain unchanged. Same bytes/new evidence fail.
    var cursorBinding: String {
        let domain = "healthmd.history_assessment/1\n\(peerInstallationID.uuidString.lowercased())\n\(captureID.uuidString.lowercased())\n\(receiptDigest)\n\(datasetDigest)"
        return SHA256.hash(data: Data(domain.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
