//
//  ExportOrchestratorTests.swift
//  HealthMdTests
//
//  TDD tests for ExportOrchestrator date range generation and ExportResult
//  computed properties.
//

import XCTest
@testable import HealthMd

final class ExportOrchestratorTests: XCTestCase {

    // MARK: - dateRange

    func testDateRange_singleDay() {
        let date = makeDate(2026, 3, 15)
        let range = ExportOrchestrator.dateRange(from: date, to: date)
        XCTAssertEqual(range.count, 1)
    }

    func testDateRange_threeDays() {
        let start = makeDate(2026, 3, 15)
        let end = makeDate(2026, 3, 17)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertEqual(range.count, 3)
    }

    func testDateRange_crossesMonthBoundary() {
        let start = makeDate(2026, 3, 30)
        let end = makeDate(2026, 4, 2)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertEqual(range.count, 4) // Mar 30, 31, Apr 1, 2
    }

    func testDateRange_endBeforeStart_returnsEmpty() {
        let start = makeDate(2026, 3, 15)
        let end = makeDate(2026, 3, 14)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertTrue(range.isEmpty)
    }

    func testDateRange_datesAreStartOfDay() {
        // Even if we pass mid-day dates, the range should normalize to start of day
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 15
        comps.hour = 14; comps.minute = 30
        let midDay = calendar.date(from: comps)!

        let range = ExportOrchestrator.dateRange(from: midDay, to: midDay)
        XCTAssertEqual(range.count, 1)
        let resultComps = calendar.dateComponents([.hour, .minute], from: range[0])
        XCTAssertEqual(resultComps.hour, 0)
        XCTAssertEqual(resultComps.minute, 0)
    }

    func testDateRange_fullWeek() {
        let start = makeDate(2026, 3, 1)
        let end = makeDate(2026, 3, 7)
        let range = ExportOrchestrator.dateRange(from: start, to: end)
        XCTAssertEqual(range.count, 7)
    }

    // MARK: - ExportResult computed properties

    func testExportResult_fullSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 5,
            totalCount: 5,
            failedDateDetails: []
        )
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertNil(result.primaryFailureReason)
    }

    func testExportResult_partialSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 3,
            totalCount: 5,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .noHealthData)
            ]
        )
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .noHealthData)
    }

    func testExportResult_totalFailure() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 5,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .accessDenied)
            ]
        )
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.primaryFailureReason, .accessDenied)
    }

    func testExportResult_cancelled_withSomeSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 2,
            totalCount: 5,
            failedDateDetails: [],
            wasCancelled: true
        )
        XCTAssertFalse(result.isFullSuccess) // cancelled, so not full success
        XCTAssertTrue(result.isPartialSuccess) // has some success + cancelled
    }

    func testExportResult_cancelled_noSuccess() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 5,
            failedDateDetails: [],
            wasCancelled: true
        )
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertTrue(result.isFailure)
    }

    func testExportResult_zeroTotal() {
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 0,
            failedDateDetails: []
        )
        XCTAssertFalse(result.isFullSuccess) // totalCount must be > 0
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFailure) // totalCount must be > 0
    }

    // MARK: - Helpers

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)!
    }
}
