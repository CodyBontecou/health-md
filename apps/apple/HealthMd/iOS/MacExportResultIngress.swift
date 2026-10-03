#if os(iOS)
import Foundation

/// Single trust boundary for Mac export result accounting received by iOS.
/// Result callbacks are mutually exclusive; malformed results are converted to
/// terminal failures before any result consumer or waiter sees them.
@MainActor
enum MacExportResultIngress {
    enum Input {
        case validated(MacExportResultPayload)
        case rejected(jobID: UUID, failure: MacExportFailure)
    }

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

    /// Validate synchronously at the app callback boundary, before the result is
    /// captured by asynchronous routing or exposed to any result subscriber.
    static func validate(_ payload: MacExportResultPayload) -> Input {
        guard payload.hasConsistentFileAccounting,
              payload.hasCoherentStatus else {
            return .rejected(
                jobID: payload.jobID,
                failure: MacExportFailure(
                    jobID: payload.jobID,
                    reason: .payloadDecodeFailure,
                    message: "The Mac returned invalid export accounting. The completion was rejected."
                )
            )
        }
        return .validated(payload)
    }

    static func handle(
        _ input: Input,
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
        switch input {
        case .rejected(let jobID, let failure):
            cancelWaiters(jobID)
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
        case .validated(let payload):
            cancelWaiters(payload.jobID)
            return await routeValidated(
                payload,
                completeScheduledResult: completeScheduledResult,
                completeRequestResult: completeRequestResult,
                completeRecoveredScheduledResult: completeRecoveredScheduledResult,
                completeRecoveredRequestResult: completeRecoveredRequestResult,
                publishResult: publishResult
            )
        }
    }

    private static func routeValidated(
        _ payload: MacExportResultPayload,
        completeScheduledResult: (MacExportResultPayload) -> Bool,
        completeRequestResult: (MacExportResultPayload) -> Bool,
        completeRecoveredScheduledResult: (MacExportResultPayload) async -> Bool,
        completeRecoveredRequestResult: (MacExportResultPayload) -> Bool,
        publishResult: (MacExportResultPayload) -> Void
    ) async -> Outcome {
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
        // Only unmatched validated results reach the observer stream. This is
        // the path used by interactive UI and the physical performance lab.
        publishResult(payload)
        return Outcome(route: .published, rejected: false)
    }
}
#endif
