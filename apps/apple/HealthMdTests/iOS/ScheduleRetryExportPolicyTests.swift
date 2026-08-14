#if os(iOS)
import XCTest
@testable import HealthMd

final class ScheduleRetryExportPolicyTests: XCTestCase {
    func testDataDictionaryIsWrittenOnlyUntilFirstSuccessfulWrite() {
        XCTAssertTrue(ScheduleRetryExportPolicy.shouldWriteDataDictionary(currentFileCount: 0))
        XCTAssertFalse(ScheduleRetryExportPolicy.shouldWriteDataDictionary(currentFileCount: 1))
        XCTAssertFalse(ScheduleRetryExportPolicy.shouldWriteDataDictionary(currentFileCount: 2))
    }

    func testDailyNoteWriteFailureIsClassifiedAsFileWriteFailure() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)

        let detail = ScheduleRetryExportPolicy.failedWriteDetail(for: date, error: error)

        XCTAssertEqual(detail.reason, .fileWriteError)
        XCTAssertEqual(detail.errorDetails, error.localizedDescription)
    }

    func testExportErrorsPreserveDestinationAndWriteClassifications() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedWriteDetail(for: date, error: ExportError.accessDenied).reason,
            .accessDenied
        )
        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedWriteDetail(
                for: date,
                error: ExportError.destinationChanged
            ).reason,
            .accessDenied
        )
        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedWriteDetail(
                for: date,
                error: ExportError.dailyNotePathConflict(path: "Daily/2026-08-12.md")
            ).reason,
            .fileWriteError
        )
        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedWriteDetail(
                for: date,
                error: ExportError.invalidExportPath(path: "../outside.md")
            ).reason,
            .fileWriteError
        )
        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedWriteDetail(for: date, error: ExportError.noHealthData).reason,
            .noHealthData
        )
    }

    func testDailyNoteOutcomesPreserveSkipAndFailureSemantics() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let skipped = ScheduleRetryExportPolicy.failedDailyNoteDetail(
            for: date,
            result: .skipped(reason: "No daily note content")
        )
        XCTAssertEqual(skipped?.reason, .noHealthData)
        XCTAssertEqual(skipped?.errorDetails, "No daily note content")

        let missing = ScheduleRetryExportPolicy.failedDailyNoteDetail(for: date, result: nil)
        XCTAssertEqual(missing?.reason, .fileWriteError)
        XCTAssertEqual(missing?.errorDetails, "Daily note update was not performed.")

        XCTAssertNil(
            ScheduleRetryExportPolicy.failedDailyNoteDetail(for: date, result: .updated(path: "Daily/note.md"))
        )
    }

    func testHealthKitErrorsAreNotMisclassifiedAsWriteFailures() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedHealthKitDetail(
                for: date,
                error: HealthKitManager.HealthKitError.dataProtectedWhileLocked
            ).reason,
            .deviceLocked
        )
        XCTAssertEqual(
            ScheduleRetryExportPolicy.failedHealthKitDetail(
                for: date,
                error: HealthKitManager.HealthKitError.notAuthorized
            ).reason,
            .healthKitError
        )
    }
}
#endif
