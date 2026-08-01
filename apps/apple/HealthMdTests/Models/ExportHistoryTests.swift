//
//  ExportHistoryTests.swift
//  HealthMdTests
//
//  TDD tests for ExportHistoryEntry, ExportFailureReason, and FailedDateDetail.
//

import XCTest
@testable import HealthMd

final class ExportHistoryTests: XCTestCase {

    func testRecordResultIsIdempotentWhenJobKeyIsProvided() {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let jobID = UUID()
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            formatsPerDate: 1
        )
        for _ in 0..<2 {
            ExportOrchestrator.recordResult(
                result,
                source: .macAgent,
                dateRangeStart: Date(),
                dateRangeEnd: Date(),
                idempotencyKey: jobID
            )
        }
        XCTAssertEqual(history.history.map(\.id), [jobID])
    }

    func testRecordResultPersistsTerminalCLIJobWithNoSuccessfulDays() {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let jobID = UUID()
        let details = ExportHistoryOperationDetails(
            kind: .rawExport,
            requestID: jobID,
            dateSelection: "exact_range",
            settingsPolicy: "requested_dates_only",
            failedDayCount: 2
        )
        let failedDate = Date()
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 2,
            failedDateDetails: [
                FailedDateDetail(date: failedDate, reason: .healthKitError)
            ],
            formatsPerDate: 0
        )

        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: failedDate,
            dateRangeEnd: failedDate,
            targetLabel: "Health.md CLI",
            fileCount: 0,
            idempotencyKey: jobID,
            operationDetails: details
        )

        XCTAssertEqual(history.history.count, 1)
        XCTAssertEqual(history.history.first?.id, jobID)
        XCTAssertFalse(history.history.first?.success ?? true)
        XCTAssertEqual(history.history.first?.operationDetails, details)
    }

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

    func testEntry_cliRawExportUsesSentDaysInsteadOfZeroFiles() {
        let jobID = UUID()
        let details = ExportHistoryOperationDetails(
            kind: .rawExport,
            requestID: jobID,
            dateSelection: "exact_range",
            settingsPolicy: "requested_dates_only",
            profile: "canonical_source_records_v1",
            detailLevel: "lossless",
            metricIDs: ["steps", "heart_rate"],
            sourceIDs: ["apple_health"],
            partitionCount: 2,
            transferredBytes: 4_096,
            sampleCount: 12,
            recordCount: 14
        )
        let entry = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 2,
            totalCount: 2,
            targetLabel: "Health.md CLI",
            fileCount: 0,
            operationDetails: details
        )

        XCTAssertTrue(entry.isCLIRawDelivery)
        XCTAssertTrue(entry.isFullSuccess)
        XCTAssertEqual(entry.resultCountLabel, "Days Sent")
        XCTAssertEqual(entry.resultCountDescription, "2 of 2")
        XCTAssertTrue(entry.summaryDescription.contains("Sent 2 day"))
        XCTAssertFalse(entry.summaryDescription.contains("0 file"))
        XCTAssertEqual(entry.operationDetails?.requestID, jobID)
        XCTAssertEqual(entry.sourceLabelForDisplay, "Health.md CLI")
        XCTAssertEqual(entry.sourceIconForDisplay, "terminal.fill")
    }

    func testEntry_cliRawWarningsArePartialEvenWhenEveryDayWasSent() {
        let details = ExportHistoryOperationDetails(
            kind: .canonicalExtraction,
            requestID: UUID(),
            dateSelection: "all_available",
            settingsPolicy: "requested_dates_only",
            warningDayCount: 1
        )
        let entry = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 3,
            totalCount: 3,
            fileCount: 0,
            operationDetails: details
        )

        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.isPartialSuccess)
        XCTAssertTrue(entry.summaryDescription.contains("Partial: sent 3/3 days"))
    }

    func testEntry_generatedFileMetricWarningsArePartial() {
        let details = ExportHistoryOperationDetails(
            kind: .generatedFiles,
            requestID: UUID(),
            dateSelection: "exact_range",
            settingsPolicy: "current_iphone_settings",
            partialFailureCount: 1
        )
        let entry = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            fileCount: 1,
            operationDetails: details
        )

        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.isPartialSuccess)
    }

    func testEntry_legacyCLIRawExportInfersDeliveryFromTarget() {
        let entry = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            targetLabel: "Direct CLI raw response",
            fileCount: 0
        )

        XCTAssertTrue(entry.isCLIRawDelivery)
        XCTAssertEqual(entry.summaryDescription, "Sent 1 day(s) to CLI")
    }

    func testEntry_apiUploadUsesUploadedDaysInsteadOfZeroFiles() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            targetLabel: "api.example.com",
            exportTarget: .apiEndpoint,
            fileCount: 0
        )

        XCTAssertTrue(entry.isAPIEndpointDelivery)
        XCTAssertEqual(entry.resultCountLabel, "Days Uploaded")
        XCTAssertEqual(entry.resultCountDescription, "1 of 1")
        XCTAssertTrue(entry.summaryDescription.contains("Uploaded 1 day"))
        XCTAssertFalse(entry.summaryDescription.contains("0 file"))
    }

    func testEntry_legacyAPIUploadInfersEndpointFromHostname() {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            targetLabel: "health.example.com",
            fileCount: 0
        )

        XCTAssertTrue(entry.isAPIEndpointDelivery)
        XCTAssertEqual(entry.resultCountLabel, "Days Uploaded")
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
        XCTAssertEqual(entry.failureReasonForDisplay, .unknown)
        XCTAssertEqual(entry.summaryDescription, "Export failed: Unknown error")
    }

    func testEntry_failureSummaryMakesFailureAndCauseExplicit() {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: false,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 1,
            failureReason: .deviceLocked
        )

        XCTAssertEqual(entry.summaryDescription, "Export failed: Device locked")
        XCTAssertEqual(entry.failureReasonForDisplay, .deviceLocked)
        XCTAssertTrue(entry.failureRecoverySuggestion?.contains("Unlock") == true)
    }

    func testEntry_failureReasonFallsBackToFailedDateForLegacyHistory() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: false,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 1,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .accessDenied)
            ]
        )

        XCTAssertEqual(entry.failureReasonForDisplay, .accessDenied)
        XCTAssertEqual(entry.summaryDescription, "Export failed: Vault access denied")
    }

    func testEntry_failureDiagnosticDetailsAreTrimmedAndDeduplicated() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: false,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 3,
            failureReason: .fileWriteError,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .fileWriteError, errorDetails: "  Disk is full.  "),
                FailedDateDetail(date: Date().addingTimeInterval(86_400), reason: .fileWriteError, errorDetails: "Disk is full."),
                FailedDateDetail(date: Date().addingTimeInterval(172_800), reason: .fileWriteError, errorDetails: "   ")
            ]
        )

        XCTAssertEqual(entry.failureDiagnosticDetails, ["Disk is full."])
        XCTAssertEqual(entry.failureListMessage, "Disk is full.")
    }

    func testEntry_knownFailureUsesRecoverySuggestionInHistoryList() {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: false,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 0,
            totalCount: 1,
            failureReason: .deviceLocked,
            failedDateDetails: [
                FailedDateDetail(date: Date(), reason: .deviceLocked, errorDetails: "Protected data unavailable")
            ]
        )

        XCTAssertEqual(entry.failureListMessage, ExportFailureReason.deviceLocked.recoverySuggestion)
    }

    func testEntry_successDoesNotExposeFailureHelp() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1
        )

        XCTAssertNil(entry.failureReasonForDisplay)
        XCTAssertNil(entry.failureRecoverySuggestion)
        XCTAssertNil(entry.failureListMessage)
        XCTAssertTrue(entry.failureDiagnosticDetails.isEmpty)
    }

    func testEntry_codable() throws {
        let pin = try makeSyntheticAppleExportEnginePin()
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 3,
            totalCount: 3,
            targetLabel: "MacBook Pro",
            exportTarget: .connectedMac,
            fileCount: 6,
            appleExportEnginePin: pin
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExportHistoryEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.source, entry.source)
        XCTAssertEqual(decoded.success, entry.success)
        XCTAssertEqual(decoded.successCount, entry.successCount)
        XCTAssertEqual(decoded.totalCount, entry.totalCount)
        XCTAssertEqual(decoded.targetLabel, "MacBook Pro")
        XCTAssertEqual(decoded.exportTarget, .connectedMac)
        XCTAssertEqual(decoded.fileCount, 6)
        XCTAssertEqual(decoded.appleExportEnginePin, pin)
        XCTAssertNil(decoded.operationDetails)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyObject.removeValue(forKey: "appleExportEnginePin")
        let legacy = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        XCTAssertNil(legacy.appleExportEnginePin)
    }

    func testEntry_codablePreservesCLIOperationDetails() throws {
        let details = ExportHistoryOperationDetails(
            kind: .canonicalExtraction,
            requestID: UUID(),
            dateSelection: "all_available",
            settingsPolicy: "requested_dates_only",
            profile: "health_data_projection",
            detailLevel: "summary",
            metricIDs: ["steps", "heart_rate", "steps"],
            categoryIDs: ["activity"],
            sourceIDs: ["apple_health"],
            objectPaths: ["daily.activity"],
            fieldPointers: ["/daily/activity/steps"],
            partitionCount: 3,
            transferredBytes: 8_192,
            sampleCount: 40,
            recordCount: 41,
            warningDayCount: 1,
            failedDayCount: 0,
            integrityWarningCount: 2,
            partialFailureCount: 1
        )
        let entry = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 2,
            totalCount: 2,
            fileCount: 0,
            operationDetails: details
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExportHistoryEntry.self, from: data)
        XCTAssertEqual(decoded.operationDetails, details)
        XCTAssertEqual(decoded.operationDetails?.metricIDs, ["heart_rate", "steps"])

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyObject.removeValue(forKey: "operationDetails")
        let legacy = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        XCTAssertNil(legacy.operationDetails)
    }

    func testOperationDetailsBoundsPersistedRequestScope() {
        let details = ExportHistoryOperationDetails(
            kind: .canonicalExtraction,
            requestID: UUID(),
            dateSelection: "exact_range",
            settingsPolicy: "requested_dates_only",
            metricIDs: (0..<600).map { "metric_\($0)" },
            objectPaths: [String(repeating: "x", count: 1_025)] +
                (0..<150).map { "object.\($0)" },
            fieldPointers: (0..<300).map { "/field/\($0)" }
        )

        XCTAssertEqual(details.metricIDs.count, 512)
        XCTAssertEqual(details.objectPaths.count, 128)
        XCTAssertEqual(details.fieldPointers.count, 256)
        XCTAssertFalse(details.objectPaths.contains(String(repeating: "x", count: 1_025)))
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

    func testFailureReason_noDataUsesInformationalAlertCopy() {
        XCTAssertEqual(ExportFailureReason.noHealthData.alertTitle, "No Health Data Found")
        XCTAssertNotEqual(
            ExportFailureReason.noHealthData.alertTitle,
            ExportFailureReason.fileWriteError.alertTitle
        )
        XCTAssertTrue(ExportFailureReason.noHealthData.detailedDescription.contains("new or empty device"))
        XCTAssertTrue(ExportFailureReason.noHealthData.recoverySuggestion.contains("All Time"))
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

    func testFailureReason_recoverySuggestionsAreActionable() {
        for reason in [ExportFailureReason.noVaultSelected, .accessDenied, .noHealthData,
                       .healthKitError, .deviceLocked, .fileWriteError, .backgroundTaskExpired, .unknown] {
            XCTAssertFalse(reason.recoverySuggestion.isEmpty, "\(reason.rawValue) should explain what to do next")
            XCTAssertNotEqual(reason.recoverySuggestion, reason.detailedDescription)
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
