#if os(iOS)
import Foundation

/// Single trust boundary for Mac export result accounting received by iOS.
/// Result callbacks are mutually exclusive; malformed results are converted to
/// terminal failures before any result consumer or waiter sees them.
@MainActor
enum MacExportResultIngress {
    enum Route: Equatable {
        case scheduled
        case request
        case recoveredScheduled
        case recoveredRequest
        case published
    }

    struct Outcome: Equatable {
        let route: Route
        let rejected: Bool
    }

    static func handle(
        _ payload: MacExportResultPayload,
        cancelWaiters: (UUID) -> Void,
        completeScheduledResult: (MacExportResultPayload) -> Bool,
        completeRequestResult: (MacExportResultPayload) -> Bool,
        completeRecoveredScheduledResult: (MacExportResultPayload) async -> Bool,
        completeRecoveredRequestResult: (MacExportResultPayload) -> Bool,
        publishResult: (MacExportResultPayload) -> Void,
        completeScheduledFailure: (MacExportFailure) -> Bool,
        completeRequestFailure: (MacExportFailure) -> Bool,
        completeRecoveredScheduledFailure: (MacExportFailure) async -> Bool,
        completeRecoveredRequestFailure: (MacExportFailure) -> Bool,
        publishFailure: (MacExportFailure) -> Void
    ) async -> Outcome {
        guard payload.hasConsistentFileAccounting else {
            let failure = MacExportFailure(
                jobID: payload.jobID,
                reason: .payloadDecodeFailure,
                message: "The Mac returned invalid export accounting. The completion was rejected."
            )
            cancelWaiters(payload.jobID)
            if completeScheduledFailure(failure) {
                return Outcome(route: .scheduled, rejected: true)
            }
            if completeRequestFailure(failure) {
                return Outcome(route: .request, rejected: true)
            }
            if await completeRecoveredScheduledFailure(failure) {
                return Outcome(route: .recoveredScheduled, rejected: true)
            }
            if completeRecoveredRequestFailure(failure) {
                return Outcome(route: .recoveredRequest, rejected: true)
            }
            publishFailure(failure)
            return Outcome(route: .published, rejected: true)
        }

        cancelWaiters(payload.jobID)
        if completeScheduledResult(payload) {
            return Outcome(route: .scheduled, rejected: false)
        }
        if completeRequestResult(payload) {
            return Outcome(route: .request, rejected: false)
        }
        if await completeRecoveredScheduledResult(payload) {
            return Outcome(route: .recoveredScheduled, rejected: false)
        }
        if completeRecoveredRequestResult(payload) {
            return Outcome(route: .recoveredRequest, rejected: false)
        }
        publishResult(payload)
        return Outcome(route: .published, rejected: false)
    }
}
#endif
