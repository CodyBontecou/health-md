import Foundation
import HealthMdConnectionCore

/// One retained metadata-operation owner for automated export admission. A logical
/// deadline may return unassessed evidence; cancellation never admits a new job.
@MainActor
final class HealthHistoryExportAdmission {
    private let worker: HealthHistoryAssessmentWorker

    init(worker: HealthHistoryAssessmentWorker = HealthHistoryAssessmentWorker()) {
        self.worker = worker
    }

    func observe(scope: HealthHistoryScope, operationID: UUID, requestBindingSHA256: String,
                 peerBinding: DirectPeerBinding, notCompleted: HealthHistoryAssessment,
                 operation: @escaping @MainActor () async -> HealthHistoryAssessment) async throws -> ExportHistoryObservation {
        guard notCompleted.scope == scope, notCompleted.requiresExplicitContinuation else {
            throw ExportHistoryObservation.ValidationError.invalidObservation
        }
        let assessment = await worker.assess(notCompleted: notCompleted, operation: operation)
        try Task.checkCancellation()
        guard assessment.scope == scope else { throw ExportHistoryObservation.ValidationError.invalidObservation }
        return try assessment.exportObservation(operationID: operationID, requestBindingSHA256: requestBindingSHA256,
            sourceInstallationID: peerBinding.sourceInstallationID,
            destinationInstallationID: peerBinding.destinationInstallationID)
    }

    enum AdmissionError: LocalizedError {
        case unsupportedPeer, invalidCheckpoint
        var errorDescription: String? {
            switch self {
            case .unsupportedPeer:
                return "This export requires history-observation support. Upgrade the CLI before resuming; its captured data is preserved."
            case .invalidCheckpoint:
                return "The export's history evidence no longer matches its immutable request. Its captured data is preserved."
            }
        }
    }

    static func validateResume(request: DirectExportRequest, accepted: DirectExportAccepted,
                               session: DirectTransferSession, historyRequired: Bool,
                               negotiatedVersion: Int?) throws {
        guard historyRequired == (accepted.historyObservation != nil) else { throw AdmissionError.invalidCheckpoint }
        guard let observation = accepted.historyObservation else { return }
        guard negotiatedVersion == 1 else { throw AdmissionError.unsupportedPeer }
        guard observation.matches(request: request, accepted: accepted, session: session) else {
            throw AdmissionError.invalidCheckpoint
        }
    }

    /// Validate the independent capture authority, not only the receipt's self-consistency.
    /// Legacy checkpoints deliberately remain unobserved and are never backfilled.
    static func validateCaptureScope(request: DirectExportRequest, accepted: DirectExportAccepted,
                                     metricIDs: Set<String>, requestedDates: [Date],
                                     originalDates: [Date], timeZoneIdentifier: String?) throws {
        guard let observation = accepted.historyObservation else { return }
        guard let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier),
              timeZoneIdentifier == accepted.sourceTimeZoneIdentifier,
              observation.metricIDs == metricIDs.sorted(),
              !requestedDates.isEmpty, requestedDates == requestedDates.sorted(),
              Set(requestedDates).count == requestedDates.count,
              Set(requestedDates).isSubset(of: Set(originalDates)) else {
            throw AdmissionError.invalidCheckpoint
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let expected = try scope(for: request, resolvedDates: originalDates, metricIDs: metricIDs, timeZone: timeZone)
        guard originalDates.allSatisfy({ $0 >= expected.startDate && $0 <= expected.endDate }),
              requestedDates.map({ formatter.string(from: $0) }) == accepted.resolvedDateIdentifiers,
              observation.requestedStart == CanonicalRFC3339UTC.string(from: expected.startDate),
              observation.requestedEnd == CanonicalRFC3339UTC.string(from: expected.endDate),
              observation.allAvailable == expected.allAvailable else {
            throw AdmissionError.invalidCheckpoint
        }
    }

    static func scope(for request: DirectExportRequest, resolvedDates: [Date], metricIDs: Set<String>,
                      timeZone: TimeZone) throws -> HealthHistoryScope {
        guard !metricIDs.isEmpty, let first = resolvedDates.first, let last = resolvedDates.last,
              resolvedDates == resolvedDates.sorted(), Set(resolvedDates).count == resolvedDates.count else {
            throw ExportHistoryObservation.ValidationError.invalidObservation
        }
        let start: Date
        let end: Date
        let allAvailable: Bool
        switch request.dateSelection {
        case .allAvailable:
            start = first; end = last; allAvailable = true
        case .exact(let from, let through):
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            guard let requestedStart = formatter.date(from: from), let requestedEnd = formatter.date(from: through),
                  formatter.string(from: requestedStart) == from, formatter.string(from: requestedEnd) == through,
                  requestedStart <= requestedEnd else { throw ExportHistoryObservation.ValidationError.invalidObservation }
            start = requestedStart; end = requestedEnd; allAvailable = false
        }
        return HealthHistoryScope(metricIDs: metricIDs, startDate: start, endDate: end,
            timeZoneIdentifier: timeZone.identifier, allAvailable: allAvailable,
            profileID: request.profileReference.flatMap { UUID(uuidString: $0.profileID) }, rangeSemantics: .ownerDates)
    }
}
