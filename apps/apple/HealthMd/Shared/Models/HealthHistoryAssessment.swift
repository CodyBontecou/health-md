import Foundation

/// Independent, in-memory evidence model. Not Codable: no export/wire adoption is
/// implied. Query completion and readable samples are intentionally not inputs.
nonisolated enum HealthHistoryRangeSemantics: String, Sendable {
    case exactInterval
    case ownerDates
}

nonisolated struct HealthHistoryScope: Equatable, Hashable, Sendable {
    let metricIDs: Set<String>
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String
    let allAvailable: Bool
    let profileID: UUID?
    let rangeSemantics: HealthHistoryRangeSemantics
    let sourceID: String = "apple.healthkit"

    init(metricIDs: Set<String>, startDate: Date, endDate: Date, timeZoneIdentifier: String,
         allAvailable: Bool, profileID: UUID?, rangeSemantics: HealthHistoryRangeSemantics = .exactInterval) {
        self.metricIDs = metricIDs
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.allAvailable = allAvailable
        self.profileID = profileID
        self.rangeSemantics = rangeSemantics
    }

    /// Keep original requested dates, while disclosing against the same owner-day
    /// interval the exporter captures in the frozen timezone. No acquisition edit.
    var sampleQueryStart: Date {
        guard rangeSemantics == .ownerDates else { return startDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: startDate)
    }
}


nonisolated enum HealthHistoryQueryOutcome: Equatable, Sendable {
    case boundaries([String: Date])
    case unavailable
    case failure
}

nonisolated enum HealthHistoryAccess: Equatable, Sendable {
    case limited(sampleEndBoundary: Date)
    /// Full access, denied access and limited access without a date are ambiguous.
    case unknown
    case apiUnavailable
    case assessmentFailed
    case unassessed(reason: String)
}

nonisolated struct HealthHistoryTypeAssessment: Equatable, Sendable, Identifiable {
    let id: String
    let directMetricIDs: [String]
    let dependencyMetricIDs: [String]
    let dependencyReasons: [String]
    let access: HealthHistoryAccess

    /// Disclosure only; never a query predicate or a start-date clamp. The exact
    /// equality behavior of HealthKit's end boundary still needs device QA.
    func limitationIntersects(_ scope: HealthHistoryScope) -> Bool {
        guard case .limited(let boundary) = access else { return false }
        return scope.allAvailable || scope.sampleQueryStart < boundary
    }
}

nonisolated struct HealthHistoryAssessment: Equatable, Sendable {
    static let modelVersion = 1
    let id: UUID
    let assessedAt: Date
    let scope: HealthHistoryScope
    let types: [HealthHistoryTypeAssessment]
    let evidenceSource: String

    init(id: UUID, assessedAt: Date, scope: HealthHistoryScope, types: [HealthHistoryTypeAssessment],
         evidenceSource: String = "HKHealthStore.earliestAuthorizedSampleDate(for:)") {
        self.id = id
        self.assessedAt = assessedAt
        self.scope = scope
        self.types = types
        self.evidenceSource = evidenceSource
    }

    var hasIntersectingLimit: Bool { types.contains { $0.limitationIntersects(scope) } }
    var hasUnverifiedHistory: Bool {
        types.contains {
            if case .limited = $0.access { return false }
            return true
        }
    }
    var needsWarning: Bool { hasIntersectingLimit || hasUnverifiedHistory }
    var warningTitle: String {
        hasIntersectingLimit ? "Some history may be unavailable" : "History access could not be verified"
    }
    var warningMessage: String {
        if evidenceSource == "assessment_not_completed" {
            return "History assessment did not finish. This export continues without verified history coverage. Readable records can still be exported with their original dates."
        }
        if hasIntersectingLimit {
            return "Apple Health limits the history Health.md can read for some selected data. Earlier data is unknown, not missing. Readable records are still exported with their original dates."
        }
        return "Apple Health does not let Health.md distinguish full access from denied access when no boundary is returned. Empty data and completed queries do not prove full history. Readable records can still be exported."
    }

    static func displayed(preview: Self?, execution: Self?, scope: HealthHistoryScope) -> Self? {
        if let execution, execution.scope == scope { return execution }
        if let preview, preview.scope == scope { return preview }
        return nil
    }

    func boundaryDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: scope.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: date)) (\(scope.timeZoneIdentifier))"
    }

    func access(for identifier: String) -> HealthHistoryAccess {
        types.first { $0.id == identifier }?.access ?? .unassessed(reason: "outside_selected_scope")
    }
}

/// Preview results are valid only for the current revision AND exact scope.
/// Revisions also invalidate A → B → A edits and foreground permission changes.
nonisolated struct HealthHistoryAssessmentRevision: Sendable {
    private(set) var id = UUID()
    mutating func invalidate() { id = UUID() }
    func accepts(_ token: UUID, assessment: HealthHistoryAssessment, scope: HealthHistoryScope) -> Bool {
        token == id && assessment.scope == scope
    }
}
