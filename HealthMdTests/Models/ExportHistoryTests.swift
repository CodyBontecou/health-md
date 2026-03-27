//
//  ExportHistoryTests.swift
//  HealthMdTests
//
//  TDD tests for ExportHistoryEntry, ExportFailureReason, and FailedDateDetail.
//

import XCTest
@testable import HealthMd

final class ExportHistoryTests: XCTestCase {

    // MARK: - ExportHistoryEntry

    func testEntry_fullSuccess() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 5,
            totalCount: 5
        )
        XCTAssertTrue(entry.isFullSuccess)
        XCTAssertFalse(entry.isPartialSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("5"))
    }

    func testEntry_partialSuccess() {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 3,
            totalCount: 5
        )
        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.isPartialSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("3"))
        XCTAssertTrue(entry.summaryDescription.contains("5"))
    }

    func testEntry_failure() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: false,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 3,
            failureReason: .noVaultSelected
        )
        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertFalse(entry.isPartialSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("vault"))
    }

    func testEntry_failureNoReason() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: false,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 1
        )
        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("failed"))
    }

    func testEntry_codable() throws {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 3,
            totalCount: 3
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExportHistoryEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.source, entry.source)
        XCTAssertEqual(decoded.success, entry.success)
        XCTAssertEqual(decoded.successCount, entry.successCount)
        XCTAssertEqual(decoded.totalCount, entry.totalCount)
    }

    // MARK: - ExportSource

    func testExportSource_rawValues() {
        XCTAssertEqual(ExportSource.manual.rawValue, "Manual")
        XCTAssertEqual(ExportSource.scheduled.rawValue, "Scheduled")
    }

    func testExportSource_icons() {
        XCTAssertFalse(ExportSource.manual.icon.isEmpty)
        XCTAssertFalse(ExportSource.scheduled.icon.isEmpty)
    }

    func testExportSource_codable() throws {
        let data = try JSONEncoder().encode(ExportSource.manual)
        let decoded = try JSONDecoder().decode(ExportSource.self, from: data)
        XCTAssertEqual(decoded, .manual)
    }

    // MARK: - ExportFailureReason

    func testFailureReason_shortDescriptions() {
        for reason in [ExportFailureReason.noVaultSelected, .accessDenied, .noHealthData,
                       .healthKitError, .deviceLocked, .fileWriteError, .backgroundTaskExpired, .unknown] {
            XCTAssertFalse(reason.shortDescription.isEmpty, "\(reason.rawValue) should have a short description")
        }
    }

    func testFailureReason_detailedDescriptions() {
        for reason in [ExportFailureReason.noVaultSelected, .accessDenied, .noHealthData,
                       .healthKitError, .deviceLocked, .fileWriteError, .backgroundTaskExpired, .unknown] {
            XCTAssertFalse(reason.detailedDescription.isEmpty, "\(reason.rawValue) should have a detailed description")
            XCTAssertTrue(
                reason.detailedDescription.count > reason.shortDescription.count,
                "\(reason.rawValue) detailed description should be longer than short description"
            )
        }
    }

    func testFailureReason_codable() throws {
        let reasons: [ExportFailureReason] = [.noVaultSelected, .accessDenied, .noHealthData,
                                               .healthKitError, .deviceLocked, .fileWriteError,
                                               .backgroundTaskExpired, .unknown]
        for reason in reasons {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(ExportFailureReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }

    // MARK: - FailedDateDetail

    func testFailedDateDetail_dateString() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 27
        let date = Calendar.current.date(from: comps)!

        let detail = FailedDateDetail(date: date, reason: .noHealthData)
        XCTAssertEqual(detail.dateString, "2026-03-27")
    }

    func testFailedDateDetail_detailedMessageWithErrorDetails() {
        let detail = FailedDateDetail(
            date: Date(),
            reason: .unknown,
            errorDetails: "Connection timed out"
        )
        XCTAssertTrue(detail.detailedMessage.contains("Connection timed out"))
        XCTAssertTrue(detail.detailedMessage.contains("unexpected error"))
    }

    func testFailedDateDetail_detailedMessageWithoutErrorDetails() {
        let detail = FailedDateDetail(date: Date(), reason: .noHealthData)
        XCTAssertEqual(detail.detailedMessage, ExportFailureReason.noHealthData.detailedDescription)
    }

    func testFailedDateDetail_codable() throws {
        let detail = FailedDateDetail(
            date: Date(),
            reason: .accessDenied,
            errorDetails: "some error"
        )
        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(FailedDateDetail.self, from: data)
        XCTAssertEqual(decoded.reason, .accessDenied)
        XCTAssertEqual(decoded.errorDetails, "some error")
    }
}
