import XCTest
@testable import HealthMd

final class ExportPreviewDisplayContentTests: XCTestCase {

    func testSmallContentRendersUnchanged() {
        let content = "{\"steps\":12500}"

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 128,
            headBytes: 96,
            tailBytes: 32
        )

        XCTAssertEqual(display.text, content)
        XCTAssertEqual(display.originalByteCount, content.utf8.count)
        XCTAssertEqual(display.omittedByteCount, 0)
        XCTAssertFalse(display.isTruncated)
    }

    func testEmptyContentUsesPlaceholder() {
        let display = ExportPreviewDisplayContent.make(from: "")

        XCTAssertEqual(display.text, "(empty file)")
        XCTAssertEqual(display.originalByteCount, 0)
        XCTAssertFalse(display.isTruncated)
    }

    func testLargeContentKeepsHeadAndTailWithTruncationMarker() {
        let content = String(repeating: "a", count: 1_000)
            + "CENTER_SENTINEL"
            + String(repeating: "z", count: 1_000)

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 24,
            headBytes: 10,
            tailBytes: 8
        )

        XCTAssertTrue(display.isTruncated)
        XCTAssertEqual(display.originalByteCount, content.utf8.count)
        XCTAssertTrue(display.text.hasPrefix(String(repeating: "a", count: 10)))
        XCTAssertTrue(display.text.hasSuffix(String(repeating: "z", count: 8)))
        XCTAssertTrue(display.text.contains("Preview truncated"))
        XCTAssertFalse(display.text.contains("CENTER_SENTINEL"))
        XCTAssertLessThan(display.text.utf8.count, content.utf8.count)
    }

    func testTruncationDoesNotSplitMultibyteCharacters() {
        let content = String(repeating: "é", count: 80)
            + "middle"
            + String(repeating: "🙂", count: 80)

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 32,
            headBytes: 9,
            tailBytes: 11
        )

        XCTAssertTrue(display.isTruncated)
        XCTAssertTrue(display.text.hasPrefix(String(repeating: "é", count: 4)))
        XCTAssertTrue(display.text.hasSuffix(String(repeating: "🙂", count: 2)))
        XCTAssertTrue(display.text.contains("Preview truncated"))
    }

    func testPermissionGuidanceRecognizesAuthorizationNotDetermined() throws {
        let failure = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 0),
            dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBiologicalSex",
            dateRangeDescription: "2026-07-15",
            errorDescription: "Authorization is not determined"
        )

        let guidance = try XCTUnwrap(ExportPermissionGuidance(failure: failure))

        XCTAssertEqual(guidance.healthDataName, "Biological Sex")
        XCTAssertTrue(guidance.iOSInstructions.contains("Request Access"))
        XCTAssertTrue(guidance.iOSInstructions.contains("do not appear"))
        XCTAssertTrue(guidance.iOSInstructions.contains("Biological Sex"))
    }

    func testPermissionGuidanceRecognizesAuthorizationMessageWithoutIs() {
        let failure = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 0),
            dataType: "HealthKit specialized record HKActivitySummaryTypeIdentifier",
            dateRangeDescription: "2026-07-15",
            errorDescription: "Authorization not determined"
        )

        XCTAssertEqual(
            ExportPermissionGuidance(failure: failure)?.healthDataName,
            "Activity Summary Rings and Goals"
        )
    }

    func testPermissionGuidanceIgnoresUnrelatedWarnings() {
        let failure = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 0),
            dataType: "Daily Note",
            dateRangeDescription: "2026-07-15",
            errorDescription: "Daily note not found"
        )

        XCTAssertNil(ExportPermissionGuidance(failure: failure))
    }

    func testPartialExportNoticeOffersPermissionRecovery() throws {
        let failures = [
            ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBiologicalSex",
                dateRangeDescription: "2026-07-15",
                errorDescription: "Authorization is not determined"
            ),
            ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBloodType",
                dateRangeDescription: "2026-07-15",
                errorDescription: "Authorization not determined"
            )
        ]
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            partialFailures: failures
        )

        let notice = try XCTUnwrap(PartialExportNotice(result: result))
        let guidance = try XCTUnwrap(notice.permissionGuidance)

        XCTAssertEqual(notice.issueCount, 2)
        XCTAssertTrue(notice.toastMessage.contains("Health permissions need attention"))
        XCTAssertTrue(guidance.healthDataName.contains("Biological Sex"))
        XCTAssertTrue(guidance.healthDataName.contains("Blood Type"))
        XCTAssertTrue(
            notice.permissionAlertMessage(instructions: guidance.iOSInstructions)
                .contains("some health data was skipped")
        )
    }

    func testLargePermissionSetUsesCompactGuidance() throws {
        let identifiers = [
            "HKActivitySummaryTypeIdentifier",
            "HKCharacteristicTypeIdentifierBiologicalSex",
            "HKCharacteristicTypeIdentifierBloodType",
            "HKCharacteristicTypeIdentifierDateOfBirth"
        ]
        let failures = identifiers.map { identifier in
            ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "HealthKit specialized record \(identifier)",
                dateRangeDescription: "2026-07-15",
                errorDescription: "Authorization is not determined"
            )
        }

        let guidance = try XCTUnwrap(ExportPermissionGuidance(failures: failures))

        XCTAssertEqual(guidance.healthDataCount, 4)
        XCTAssertEqual(guidance.healthDataName, "4 additional health data types")
        XCTAssertTrue(guidance.iOSInstructions.contains("additional data types you want to export"))
        XCTAssertFalse(guidance.iOSInstructions.contains("Activity Summary Rings and Goals,"))
    }

    func testPartialExportNoticeSummarizesNonPermissionIssues() throws {
        let failedDate = FailedDateDetail(
            date: Date(timeIntervalSince1970: 0),
            reason: .fileWriteError
        )
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 2,
            failedDateDetails: [failedDate]
        )

        let notice = try XCTUnwrap(PartialExportNotice(result: result))

        XCTAssertNil(notice.permissionGuidance)
        XCTAssertEqual(notice.issueCount, 1)
        XCTAssertTrue(notice.toastMessage.contains("1 issue"))
        XCTAssertTrue(notice.genericAlertMessage.contains("File write failed"))
    }
}
