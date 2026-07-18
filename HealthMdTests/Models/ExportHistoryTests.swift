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
            totalCount: 5,
            fileCount: 10
        )
        XCTAssertTrue(entry.isFullSuccess)
        XCTAssertFalse(entry.isPartialSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("10"))
    }

    func testEntry_dailyNotesOnlyUsesNoteSummaryAndCodableCounts() throws {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 2,
            totalCount: 2,
            fileCount: 0,
            dailyNoteUpdateCount: 2,
            dailyNoteSkipCount: 0
        )

        XCTAssertTrue(entry.summaryDescription.contains("Updated 2 daily note"))
        XCTAssertFalse(entry.summaryDescription.contains("0 file"))

        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertEqual(decoded.dailyNoteUpdateCount, 2)
        XCTAssertEqual(decoded.dailyNoteSkipCount, 0)
    }

    func testEntry_terminalDailyNoteSkipsAreNotReportedAsFailure() {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 2,
            failedDateDetails: [],
            fileCount: 0,
            dailyNoteUpdateCount: 0,
            dailyNoteSkipCount: 2
        )

        XCTAssertTrue(entry.isPartialSuccess)
        XCTAssertEqual(entry.summaryDescription, "Skipped 2 missing daily note(s)")
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

    func testEntry_partialMetricFailure_isPartialAndSummarizesWarning() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            partialFailures: [
                ExportPartialFailure(
                    date: Date(),
                    dataType: "workouts",
                    dateRangeDescription: "2026-03-15 00:00:00 - 2026-03-15 23:59:59",
                    errorDescription: "HealthKit query failed"
                )
            ]
        )

        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.isPartialSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("warning"))
        XCTAssertTrue(entry.partialFailureSummary?.contains("workouts") ?? false)
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
            totalCount: 3,
            targetLabel: "MacBook Pro",
            fileCount: 6
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExportHistoryEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.source, entry.source)
        XCTAssertEqual(decoded.success, entry.success)
        XCTAssertEqual(decoded.successCount, entry.successCount)
        XCTAssertEqual(decoded.totalCount, entry.totalCount)
        XCTAssertEqual(decoded.targetLabel, "MacBook Pro")
        XCTAssertEqual(decoded.fileCount, 6)
    }

    func testEntry_codablePreservesPartialFailures() throws {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            partialFailures: [
                ExportPartialFailure(
                    date: Date(),
                    dataType: "sleep",
                    dateRangeDescription: "2026-03-15 00:00:00 - 2026-03-15 23:59:59",
                    errorDescription: "Protected data unavailable"
                )
            ]
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExportHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.partialFailures, entry.partialFailures)
        XCTAssertTrue(decoded.isPartialSuccess)
    }

    // MARK: - ExportSource

    func testExportSource_rawValues() {
        XCTAssertEqual(ExportSource.manual.rawValue, "Manual")
        XCTAssertEqual(ExportSource.scheduled.rawValue, "Scheduled")
        XCTAssertEqual(ExportSource.shortcut.rawValue, "Shortcut")
        XCTAssertEqual(ExportSource.macAgent.rawValue, "iPhone → Mac")
    }

    func testExportSource_icons() {
        XCTAssertFalse(ExportSource.manual.icon.isEmpty)
        XCTAssertFalse(ExportSource.scheduled.icon.isEmpty)
        XCTAssertFalse(ExportSource.shortcut.icon.isEmpty)
        XCTAssertFalse(ExportSource.macAgent.icon.isEmpty)
    }

    func testExportSource_codable() throws {
        for source in [ExportSource.manual, .scheduled, .shortcut, .macAgent] {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(ExportSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
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
