#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class MacExportResultIngressTests: XCTestCase {
    func testRejectsInvalidAccountingBeforeResultConsumersAndTerminatesMatchingOperation() async {
        let payload = makePayload(totalFilesWritten: 1, externalRecordFileCount: 2)
        var cancelledJobIDs: [UUID] = []
        var scheduledFailures: [MacExportFailure] = []
        var resultMutationCount = 0
        var laterRouteCount = 0

        let input = MacExportResultIngress.validate(payload)
        guard case .rejected(let rejectedJobID, let ingressFailure) = input else {
            return XCTFail("Invalid accounting must be rejected at app ingress")
        }
        XCTAssertEqual(rejectedJobID, payload.jobID)
        XCTAssertEqual(ingressFailure.jobID, payload.jobID)

        let outcome = await MacExportResultIngress.handle(
            input,
            cancelWaiters: { cancelledJobIDs.append($0) },
            completeScheduledResult: { _ in resultMutationCount += 1; return true },
            completeRequestResult: { _ in resultMutationCount += 1; return true },
            completeRecoveredScheduledResult: { _ in resultMutationCount += 1; return true },
            completeRecoveredRequestResult: { _ in resultMutationCount += 1; return true },
            publishResult: { _ in resultMutationCount += 1 },
            completeScheduledFailure: { failure in
                scheduledFailures.append(failure)
                return true
            },
            completeRequestFailure: { _ in laterRouteCount += 1; return true },
            completeRecoveredScheduledFailure: { _ in laterRouteCount += 1; return true },
            completeRecoveredRequestFailure: { _ in laterRouteCount += 1; return true },
            publishFailure: { _ in laterRouteCount += 1 }
        )

        XCTAssertEqual(outcome, .init(route: .scheduled, rejected: true))
        XCTAssertEqual(cancelledJobIDs, [payload.jobID])
        XCTAssertEqual(scheduledFailures.count, 1)
        XCTAssertEqual(scheduledFailures.first?.jobID, payload.jobID)
        XCTAssertEqual(scheduledFailures.first?.reason, .payloadDecodeFailure)
        XCTAssertEqual(resultMutationCount, 0, "Rejected payload must not reach history/quota/UI result consumers")
        XCTAssertEqual(laterRouteCount, 0, "Terminal failure routing must be exclusive")
    }

    func testRejectsMismatchedBreakdownDailyNoteCountsAtIngress() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            isTotalFilesWrittenAuthoritative: true,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 1,
                successfulDataDayCount: 1,
                looseAggregateFileCount: 1,
                dailyNoteUpdateCount: 1
            ),
            dailyNoteUpdateCount: 2,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        guard case .rejected(let jobID, let failure) = MacExportResultIngress.validate(payload) else {
            return XCTFail("Duplicated producer counts must agree before ingress routing")
        }
        XCTAssertEqual(jobID, payload.jobID)
        XCTAssertEqual(failure.reason, .payloadDecodeFailure)
    }

    func testRejectsContradictoryFailureBeforeUIPublication() async {
        let payload = makePayload(status: .failure)
        var resultMutationCount = 0
        var publishedFailures: [MacExportFailure] = []

        let outcome = await MacExportResultIngress.handle(
            MacExportResultIngress.validate(payload),
            cancelWaiters: { _ in },
            completeScheduledResult: { _ in resultMutationCount += 1; return false },
            completeRequestResult: { _ in resultMutationCount += 1; return false },
            completeRecoveredScheduledResult: { _ in resultMutationCount += 1; return false },
            completeRecoveredRequestResult: { _ in resultMutationCount += 1; return false },
            publishResult: { _ in resultMutationCount += 1 },
            completeScheduledFailure: { _ in false },
            completeRequestFailure: { _ in false },
            completeRecoveredScheduledFailure: { _ in false },
            completeRecoveredRequestFailure: { _ in false },
            publishFailure: { publishedFailures.append($0) }
        )

        XCTAssertEqual(outcome, .init(route: .published, rejected: true))
        XCTAssertEqual(resultMutationCount, 0, "Invalid status counters must not mutate operation or UI result state")
        XCTAssertEqual(publishedFailures.count, 1)
        XCTAssertEqual(publishedFailures.first?.jobID, payload.jobID)
        XCTAssertEqual(publishedFailures.first?.reason, .payloadDecodeFailure)
    }

    func testAcceptsCancellationAndTerminalNoDataAtIngress() {
        let cancelled = makePayload(
            status: .cancelled,
            successCount: 0,
            totalCount: 2,
            formatsPerDate: 0,
            totalFilesWritten: 0
        )
        let terminalNoData = makePayload(
            status: .failure,
            successCount: 0,
            totalCount: 2,
            formatsPerDate: 0,
            totalFilesWritten: 0,
            hadTerminalRangeFailure: true,
            failedDateDetails: [FailedDateDetail(date: Date(), reason: .noHealthData)]
        )

        for payload in [cancelled, terminalNoData] {
            guard case .validated(let validated) = MacExportResultIngress.validate(payload) else {
                return XCTFail("Valid cancellation and terminal no-data results must reach consumers")
            }
            XCTAssertEqual(validated.jobID, payload.jobID)
        }
    }

    func testValidCompletionUsesOnlyFirstMatchingRouteForCollidingJobID() async {
        let payload = makePayload()
        var scheduledCount = 0
        var requestCount = 0
        var recoveredCount = 0
        var publishedCount = 0
        var failureCount = 0

        let input = MacExportResultIngress.validate(payload)
        guard case .validated(let validatedPayload) = input else {
            return XCTFail("Consistent accounting must pass app ingress")
        }
        XCTAssertEqual(validatedPayload.jobID, payload.jobID)

        let outcome = await MacExportResultIngress.handle(
            input,
            cancelWaiters: { _ in },
            completeScheduledResult: { _ in scheduledCount += 1; return true },
            completeRequestResult: { _ in requestCount += 1; return true },
            completeRecoveredScheduledResult: { _ in recoveredCount += 1; return true },
            completeRecoveredRequestResult: { _ in recoveredCount += 1; return true },
            publishResult: { _ in publishedCount += 1 },
            completeScheduledFailure: { _ in failureCount += 1; return true },
            completeRequestFailure: { _ in failureCount += 1; return true },
            completeRecoveredScheduledFailure: { _ in failureCount += 1; return true },
            completeRecoveredRequestFailure: { _ in failureCount += 1; return true },
            publishFailure: { _ in failureCount += 1 }
        )

        XCTAssertEqual(outcome, .init(route: .scheduled, rejected: false))
        XCTAssertEqual(scheduledCount, 1)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(recoveredCount, 0)
        XCTAssertEqual(publishedCount, 0)
        XCTAssertEqual(failureCount, 0)
    }

    func testUnmatchedRejectedCompletionPublishesFailureInsteadOfInvalidResult() async {
        let payload = makePayload(totalFilesWritten: 0, externalRecordFileCount: 1)
        var publishedResults = 0
        var publishedFailures: [MacExportFailure] = []

        let outcome = await MacExportResultIngress.handle(
            MacExportResultIngress.validate(payload),
            cancelWaiters: { _ in },
            completeScheduledResult: { _ in false },
            completeRequestResult: { _ in false },
            completeRecoveredScheduledResult: { _ in false },
            completeRecoveredRequestResult: { _ in false },
            publishResult: { _ in publishedResults += 1 },
            completeScheduledFailure: { _ in false },
            completeRequestFailure: { _ in false },
            completeRecoveredScheduledFailure: { _ in false },
            completeRecoveredRequestFailure: { _ in false },
            publishFailure: { publishedFailures.append($0) }
        )

        XCTAssertEqual(outcome, .init(route: .published, rejected: true))
        XCTAssertEqual(publishedResults, 0)
        XCTAssertEqual(publishedFailures.count, 1)
        XCTAssertEqual(publishedFailures.first?.jobID, payload.jobID)
    }

    func testUnmatchedValidatedCompletionPublishesOnlyValidatedResult() async {
        let payload = makePayload()
        var publishedResults: [MacExportResultPayload] = []
        var publishedFailureCount = 0

        let outcome = await MacExportResultIngress.handle(
            MacExportResultIngress.validate(payload),
            cancelWaiters: { _ in },
            completeScheduledResult: { _ in false },
            completeRequestResult: { _ in false },
            completeRecoveredScheduledResult: { _ in false },
            completeRecoveredRequestResult: { _ in false },
            publishResult: { publishedResults.append($0) },
            completeScheduledFailure: { _ in false },
            completeRequestFailure: { _ in false },
            completeRecoveredScheduledFailure: { _ in false },
            completeRecoveredRequestFailure: { _ in false },
            publishFailure: { _ in publishedFailureCount += 1 }
        )

        XCTAssertEqual(outcome, .init(route: .published, rejected: false))
        XCTAssertEqual(publishedResults.map(\.jobID), [payload.jobID])
        XCTAssertTrue(publishedResults.allSatisfy(\.hasConsistentFileAccounting))
        XCTAssertTrue(publishedResults.allSatisfy(\.hasCoherentStatus))
        XCTAssertEqual(publishedFailureCount, 0)
    }

    private func makePayload(
        status: MacExportResultStatus = .success,
        successCount: Int = 1,
        totalCount: Int = 1,
        formatsPerDate: Int = 1,
        totalFilesWritten: Int = 1,
        externalRecordFileCount: Int = 0,
        hadTerminalRangeFailure: Bool = false,
        failedDateDetails: [FailedDateDetail] = []
    ) -> MacExportResultPayload {
        MacExportResultPayload(
            jobID: UUID(),
            status: status,
            successCount: successCount,
            totalCount: totalCount,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: totalFilesWritten,
            isTotalFilesWrittenAuthoritative: true,
            externalRecordFileCount: externalRecordFileCount,
            hadTerminalRangeFailure: hadTerminalRangeFailure,
            failedDateDetails: failedDateDetails,
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }
}
#endif
