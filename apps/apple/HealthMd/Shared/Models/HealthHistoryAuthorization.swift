import Foundation

/// Platform-neutral completeness state for a health-data history scope.
///
/// `full_history` means the source reported no date-window restriction for the
/// assessed types. It does not override platform privacy: on Apple platforms a
/// denied read and an unrestricted read can remain indistinguishable.
nonisolated enum HealthHistoryAuthorizationState: String, Codable, CaseIterable, Sendable {
    case fullHistory = "full_history"
    case limitedHistory = "limited_history"
    case unknown
    case apiUnavailable = "api_unavailable"
}

nonisolated struct HealthHistoryAuthorizationBoundary: Codable, Equatable, Sendable {
    let typeIdentifier: String
    let earliestAuthorizedSampleDate: Date

    enum CodingKeys: String, CodingKey {
        case typeIdentifier = "type_identifier"
        case earliestAuthorizedSampleDate = "earliest_authorized_sample_date"
    }
}

/// Exact, privacy-preserving result of assessing a selected health-data scope.
/// The result contains type identifiers and authorization dates, never samples.
nonisolated struct HealthHistoryAuthorizationAssessment: Codable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let state: HealthHistoryAuthorizationState
    let assessedTypeIdentifiers: [String]
    let boundaries: [HealthHistoryAuthorizationBoundary]
    let unassessedMetricIDs: [String]
    let checkedAt: Date?
    let message: String

    init(
        state: HealthHistoryAuthorizationState,
        assessedTypeIdentifiers: [String] = [],
        boundaries: [HealthHistoryAuthorizationBoundary] = [],
        unassessedMetricIDs: [String] = [],
        checkedAt: Date? = nil,
        message: String
    ) {
        schema = "healthmd.history_authorization"
        schemaVersion = 1
        self.state = state
        self.assessedTypeIdentifiers = Array(Set(assessedTypeIdentifiers)).sorted()
        self.boundaries = boundaries.sorted { lhs, rhs in
            if lhs.earliestAuthorizedSampleDate != rhs.earliestAuthorizedSampleDate {
                return lhs.earliestAuthorizedSampleDate < rhs.earliestAuthorizedSampleDate
            }
            return lhs.typeIdentifier < rhs.typeIdentifier
        }
        self.unassessedMetricIDs = Array(Set(unassessedMetricIDs)).sorted()
        self.checkedAt = checkedAt
        self.message = message
    }

    static let unknown = Self(
        state: .unknown,
        message: "History authorization has not been assessed."
    )

    var earliestAuthorizedSampleDate: Date? {
        boundaries.map(\.earliestAuthorizedSampleDate).min()
    }

    /// True only when the runtime assessment completed, found no limited
    /// boundary, and covered every selected metric with historical semantics.
    var supportsUnqualifiedFullHistoryClaim: Bool {
        state == .fullHistory && unassessedMetricIDs.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case state
        case assessedTypeIdentifiers = "assessed_type_identifiers"
        case boundaries
        case unassessedMetricIDs = "unassessed_metric_ids"
        case checkedAt = "checked_at"
        case message
    }
}
