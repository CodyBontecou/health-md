import XCTest
@testable import HealthMd

@MainActor
final class MacExportResultSummaryTests: XCTestCase {
    func testCompletedSummaryUsesStatusAndConfirmedCounts() {
        let result = makeResult(status: .success, successCount: 3, filesWritten: 6)

        XCTAssertEqual(
            MacExportResultSummary.message(for: result),
            "Export completed: 3 of 3 day(s); 6 file(s)."
        )
    }

    func testPartialSummaryPreservesLowerBoundAccounting() {
        let result = makeResult(
            status: .partialSuccess, successCount: 1, filesWritten: 2, authoritative: false
        )

        XCTAssertEqual(
            MacExportResultSummary.message(for: result),
            "Export partially completed: 1 of 3 day(s); at least 2 file(s)."
        )
    }

    func testFailureAndCancellationRemainDistinct() {
        XCTAssertEqual(
            MacExportResultSummary.message(for: makeResult(
                status: .failure, successCount: 0, filesWritten: 0
            )),
            "Export failed: 0 of 3 day(s); 0 file(s)."
        )
        XCTAssertEqual(
            MacExportResultSummary.message(for: makeResult(
                status: .cancelled, successCount: 1, filesWritten: 2
            )),
            "Export cancelled: 1 of 3 day(s); 2 file(s)."
        )
    }

    func testUnknownZeroFileCountIsNotPresentedAsAuthoritative() {
        XCTAssertEqual(
            MacExportResultSummary.message(for: makeResult(
                status: .failure, successCount: 0, filesWritten: 0, authoritative: false
            )),
            "Export failed: 0 of 3 day(s); file count unavailable."
        )
    }

    func testInconsistentAccountingCannotProduceAnExactFileCount() {
        XCTAssertEqual(
            MacExportResultSummary.message(for: makeResult(
                status: .success, successCount: 3, filesWritten: 1
            )),
            "Export completed: 3 of 3 day(s); at least 1 file(s)."
        )
    }

    func testPrivateDetailsStayOutOfSummaryAndWireEncodingIsUnchanged() throws {
        let result = makeResult(
            status: .partialSuccess,
            successCount: 1,
            filesWritten: 2,
            failedDateDetails: [FailedDateDetail(
                date: Date(timeIntervalSince1970: 0),
                reason: .unknown,
                errorDetails: "synthetic-private-error"
            )],
            partialFailures: [ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "synthetic-private-type",
                dateRangeDescription: "synthetic-private-range",
                errorDescription: "synthetic-private-warning"
            )]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(result)

        XCTAssertEqual(
            MacExportResultSummary.message(for: result),
            "Export partially completed: 1 of 3 day(s); 2 file(s)."
        )
        XCTAssertEqual(try encoder.encode(result), before)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        XCTAssertNil(object["message"], "Local summary must not add a deployed wire member")
    }

    private func makeResult(
        status: MacExportResultStatus,
        successCount: Int,
        filesWritten: Int,
        authoritative: Bool = true,
        failedDateDetails: [FailedDateDetail] = [],
        partialFailures: [ExportPartialFailure]? = nil
    ) -> MacExportResultPayload {
        MacExportResultPayload(
            jobID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            status: status,
            successCount: successCount,
            totalCount: 3,
            formatsPerDate: 2,
            totalFilesWritten: filesWritten,
            isTotalFilesWrittenAuthoritative: authoritative,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            destinationDisplayName: "synthetic-private-destination",
            destinationPathForDisplay: "synthetic-private-path",
            completedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
