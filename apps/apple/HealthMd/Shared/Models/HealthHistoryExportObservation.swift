import Foundation
import HealthMdConnectionCore

extension HealthHistoryAssessment {
    /// Convert admission-time evidence without changing sample predicates, dates,
    /// or capture status. The caller owns the immutable request/settings binding.
    func exportObservation(operationID: UUID, requestBindingSHA256: String,
                           sourceInstallationID: UUID? = nil,
                           destinationInstallationID: UUID? = nil) throws -> ExportHistoryObservation {
        func validDate(_ date: Date) -> Bool {
            let seconds = date.timeIntervalSince1970
            return seconds.isFinite && seconds >= -62_135_596_800 && seconds < 253_402_300_800
        }
        guard [assessedAt, scope.startDate, scope.endDate].allSatisfy(validDate),
              types.allSatisfy({ row in
                  if case .limited(let boundary) = row.access { return validDate(boundary) }
                  return true
              }) else { throw ExportHistoryObservation.ValidationError.invalidObservation }
        let rows = types.sorted { $0.id < $1.id }.map { row -> ExportHistoryTypeObservation in
            let outcome: String
            let boundary: String?
            let reason: String?
            switch row.access {
            case .limited(let date):
                outcome = "limited"
                boundary = CanonicalRFC3339UTC.string(from: date)
                reason = nil
            case .unknown: outcome = "unknown"; boundary = nil; reason = nil
            case .apiUnavailable: outcome = "api_unavailable"; boundary = nil; reason = nil
            case .assessmentFailed: outcome = "assessment_failed"; boundary = nil; reason = nil
            case .unassessed(let value): outcome = "unassessed"; boundary = nil; reason = value
            }
            return ExportHistoryTypeObservation(typeID: row.id,
                directMetricIDs: row.directMetricIDs.sorted(),
                dependencyMetricIDs: row.dependencyMetricIDs.sorted(),
                dependencyReasons: row.dependencyReasons.sorted(), outcome: outcome,
                sampleEndBoundary: boundary, unassessedReason: reason)
        }
        let method: String
        switch evidenceSource {
        case "HKHealthStore.earliestAuthorizedSampleDate(for:)":
            method = "healthkit_earliest_authorized_sample_date"
        case "assessment_not_completed": method = "assessment_not_completed"
        case "synthetic_ui_fixture": method = "synthetic_ui_fixture"
        default: throw ExportHistoryObservation.ValidationError.invalidObservation
        }
        return try ExportHistoryObservation(observationID: id, operationID: operationID,
            observedAt: CanonicalRFC3339UTC.string(from: assessedAt),
            requestBindingSHA256: requestBindingSHA256,
            sourceInstallationID: sourceInstallationID, destinationInstallationID: destinationInstallationID,
            timeZoneIdentifier: scope.timeZoneIdentifier, metricIDs: scope.metricIDs.sorted(),
            requestedStart: CanonicalRFC3339UTC.string(from: scope.startDate),
            requestedEnd: CanonicalRFC3339UTC.string(from: scope.endDate), allAvailable: scope.allAvailable,
            rangeSemantics: scope.rangeSemantics == .ownerDates ? "owner_dates" : "exact_interval",
            evidenceMethod: method, types: rows)
    }
}
