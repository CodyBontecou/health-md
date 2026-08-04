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

    func testRecordResultPersistsCompleteGeneratedFileBreakdown() throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            formatsPerDate: 2,
            looseAggregateFileCount: 2,
            individualEntryFileCount: 35,
            dataDictionaryFileCount: 1,
            rollupFileCount: 1,
            archiveCount: 1,
            externalRecordFileCount: 1,
            isFileCategoryBreakdownComplete: true,
            dailyNoteUpdateCount: 1
        )

        ExportOrchestrator.recordResult(
            result,
            source: .scheduled,
            dateRangeStart: Date(),
            dateRangeEnd: Date()
        )

        let entry = try XCTUnwrap(history.history.first)
        let breakdown = entry.outputBreakdown
        XCTAssertEqual(entry.generatedFileCountDescription, "41 generated files")
        XCTAssertEqual(entry.generatedFileCountCompactDescription, "41")
        XCTAssertFalse(entry.resultCountDescription.contains("At least"))
        XCTAssertEqual(breakdown.requestedDataDayCount, 1)
        XCTAssertEqual(breakdown.successfulDataDayCount, 1)
        XCTAssertEqual(breakdown.looseAggregateFileCount, 2)
        XCTAssertEqual(breakdown.individualEntryFileCount, 35)
        XCTAssertEqual(breakdown.dataDictionaryFileCount, 1)
        XCTAssertEqual(breakdown.zipArchiveFileCount, 1)
        XCTAssertEqual(breakdown.rollupFileCount, 1)
        XCTAssertEqual(breakdown.providerSidecarFileCount, 1)
        XCTAssertEqual(breakdown.dailyNoteUpdateCount, 1)
        XCTAssertEqual(breakdown.generatedFileCount, result.totalFilesWritten)
        XCTAssertTrue(breakdown.isFileCategoryBreakdownComplete)
    }

    func testRecordResultPersistsUnknownIncompleteMacStreamFailureInsteadOfAuthoritativeZero() throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let date = Date()
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 1,
            failedDateDetails: [
                FailedDateDetail(date: date, reason: .fileWriteError)
            ],
            formatsPerDate: 1,
            isFileCategoryBreakdownComplete: false
        )

        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: date,
            dateRangeEnd: date,
            targetLabel: "Mac"
        )

        let entry = try XCTUnwrap(history.history.first)
        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertNil(decoded.fileCount)
        XCTAssertEqual(decoded.outputBreakdown.generatedFileCount, 0)
        XCTAssertFalse(decoded.outputBreakdown.isFileCategoryBreakdownComplete)
        XCTAssertEqual(decoded.generatedFileCountDescription, "Unknown")
        XCTAssertEqual(decoded.generatedFileCountCompactDescription, "Unknown")
        XCTAssertEqual(decoded.resultCountDescription, "Unknown from 0 of 1 data day")
        XCTAssertTrue(decoded.resultCountAccessibilityDescription.contains("count unknown"))
    }

    func testRecordResultPreservesUnknownMacFailureTotalAndKnownPartialCategories() throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let date = Date()
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: 1,
            failedDateDetails: [
                FailedDateDetail(date: date, reason: .fileWriteError)
            ],
            formatsPerDate: 1,
            looseAggregateFileCount: 2,
            isFileCategoryBreakdownComplete: false
        )

        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: date,
            dateRangeEnd: date,
            targetLabel: "Mac"
        )

        let entry = try XCTUnwrap(history.history.first)
        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertNil(decoded.fileCount)
        XCTAssertEqual(decoded.outputBreakdown.looseAggregateFileCount, 2)
        XCTAssertEqual(decoded.outputBreakdown.generatedFileCount, 2)
        XCTAssertFalse(decoded.outputBreakdown.isFileCategoryBreakdownComplete)
        XCTAssertEqual(decoded.generatedFileCountDescription, "At least 2 generated files")
        XCTAssertEqual(decoded.generatedFileCountCompactDescription, "At least 2")
        XCTAssertEqual(
            decoded.resultCountDescription,
            "At least 2 generated files from 0 of 1 data day"
        )
        XCTAssertTrue(decoded.resultCountAccessibilityDescription.hasPrefix("At least 2"))
    }

    func testMacPayloadLowerBoundDoesNotBecomeAuthoritativeHistoryTotal() throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let date = Date()
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 0,
            looseAggregateFileCount: 2,
            isFileCategoryBreakdownComplete: false
        )
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .failure,
            successCount: 0,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 2,
            isTotalFilesWrittenAuthoritative: false,
            outputBreakdown: breakdown,
            failedDateDetails: [
                FailedDateDetail(date: date, reason: .fileWriteError)
            ],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: date
        )

        ExportOrchestrator.recordResult(
            ExportOrchestrator.ExportResult(macExportPayload: payload),
            source: .macAgent,
            dateRangeStart: date,
            dateRangeEnd: date
        )

        let entry = try XCTUnwrap(history.history.first)
        XCTAssertNil(entry.fileCount)
        XCTAssertEqual(entry.outputBreakdown.looseAggregateFileCount, 2)
        XCTAssertEqual(entry.generatedFileCountDescription, "At least 2 generated files")
    }

    func testMacPayloadTerminalFailureCannotBecomeFullSuccessAfterEveryDataDayCompleted() throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let date = Date()
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .failure,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            failedDateDetails: [],
            completedDates: [date],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: date
        )

        XCTAssertTrue(payload.hadTerminalFailure)
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertTrue(result.hadTerminalFailure)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertTrue(result.didCompleteAllRequestedDates)

        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: date,
            dateRangeEnd: date
        )
        let entry = try XCTUnwrap(history.history.first)
        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertTrue(decoded.hadTerminalFailure)
        XCTAssertFalse(decoded.isFullSuccess)
        XCTAssertTrue(decoded.isPartialSuccess)
        XCTAssertTrue(decoded.summaryDescription.hasPrefix("Partial:"))
        XCTAssertEqual(
            decoded.failureListMessage,
            "The export did not finish successfully after writing confirmed output."
        )
    }

    func testSuccessfulMacPayloadStillProducesFullDailyCompletion() {
        let date = Date()
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            failedDateDetails: [],
            completedDates: [date],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: date
        )

        XCTAssertFalse(payload.hadTerminalFailure)
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertFalse(result.hadTerminalFailure)
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
    }

    func testLegacyHistoryWithoutTerminalFailureFieldDefaultsFalseAndRemainsFullSuccess() throws {
        let date = Date()
        let entry = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: date,
            dateRangeEnd: date,
            successCount: 1,
            totalCount: 1,
            fileCount: 1,
            hadTerminalFailure: true
        )
        let encoded = try JSONEncoder().encode(entry)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "hadTerminalFailure")

        let legacy = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertFalse(legacy.hadTerminalFailure)
        XCTAssertTrue(legacy.isFullSuccess)
        XCTAssertFalse(legacy.isPartialSuccess)
    }

    func testMacExportFailureCarriesExactCommittedCategoriesIntoFailureHistory() throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        let date = Date()
        let diagnostic = "Injected final dictionary failure"
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 0,
            looseAggregateFileCount: 2,
            isFileCategoryBreakdownComplete: true
        )
        let failure = MacExportFailure(
            jobID: UUID(),
            reason: .exportWriteFailure,
            message: "Mac export failed.",
            underlyingError: diagnostic,
            totalFilesWritten: 2,
            outputBreakdown: breakdown
        )
        let detail = FailedDateDetail(
            date: date,
            reason: .fileWriteError,
            errorDetails: diagnostic
        )

        ExportOrchestrator.recordResult(
            ExportOrchestrator.ExportResult(
                macExportFailure: failure,
                totalCount: 1,
                formatsPerDate: 1,
                failedDateDetails: [detail]
            ),
            source: .macAgent,
            dateRangeStart: date,
            dateRangeEnd: date
        )

        let entry = try XCTUnwrap(history.history.first)
        XCTAssertFalse(entry.success)
        XCTAssertEqual(entry.fileCount, 2)
        XCTAssertEqual(entry.outputBreakdown.looseAggregateFileCount, 2)
        XCTAssertEqual(entry.failureDiagnosticDetails, [diagnostic])
    }

    func testMacExportFailurePreservesPriorSuccessfulDataDaysAndExactCategories() throws {
        let date = Date()
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 3,
            successfulDataDayCount: 2,
            looseAggregateFileCount: 4,
            providerSidecarFileCount: 1,
            isFileCategoryBreakdownComplete: false
        )
        let failure = MacExportFailure(
            jobID: UUID(),
            reason: .exportWriteFailure,
            message: "Final roll-up failed.",
            totalFilesWritten: nil,
            outputBreakdown: breakdown
        )
        let detail = FailedDateDetail(
            date: date,
            reason: .fileWriteError,
            errorDetails: failure.message
        )
        let result = ExportOrchestrator.ExportResult(
            macExportFailure: failure,
            totalCount: 3,
            formatsPerDate: 2,
            failedDateDetails: [detail]
        )

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.looseAggregateFileCount, 4)
        XCTAssertEqual(result.externalRecordFileCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 5)
        XCTAssertFalse(result.hasAuthoritativeFileCount)
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertNil(result.remainingDates(from: [date]))

        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }
        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: date,
            dateRangeEnd: date
        )
        let entry = try XCTUnwrap(history.history.first)
        XCTAssertEqual(entry.successCount, 2)
        XCTAssertEqual(entry.outputBreakdown.successfulDataDayCount, 2)
        XCTAssertEqual(entry.outputBreakdown.generatedFileCount, 5)
        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.isPartialSuccess)
    }

    func testRecordResultPersistsCancellationAndNeverPromotesAllDaysToFullSuccess() throws {
        let date = Date()
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            formatsPerDate: 1,
            looseAggregateFileCount: 1,
            isFileCategoryBreakdownComplete: true,
            wasCancelled: true,
            completedDates: [date]
        )
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }

        ExportOrchestrator.recordResult(
            result,
            source: .manual,
            dateRangeStart: date,
            dateRangeEnd: date
        )

        let entry = try XCTUnwrap(history.history.first)
        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertTrue(decoded.wasCancelled)
        XCTAssertFalse(decoded.isFullSuccess)
        XCTAssertTrue(decoded.isPartialSuccess)
        XCTAssertEqual(decoded.successCount, decoded.totalCount)
    }

    func testFailedDateDetailPreventsOtherwiseCompleteHistoryFromFullSuccess() {
        let entry = ExportHistoryEntry(
            source: .manual,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [FailedDateDetail(date: Date(), reason: .fileWriteError)],
            fileCount: 1
        )

        XCTAssertFalse(entry.isFullSuccess)
        XCTAssertTrue(entry.isPartialSuccess)
    }

    #if os(iOS)
    @MainActor
    func testExportHistoryDetailDataDayDescriptionUsesCompleteLocalizedLiterals() {
        XCTAssertEqual(ExportHistoryDetailView.dataDayDescription(0), "0 data days")
        XCTAssertEqual(ExportHistoryDetailView.dataDayDescription(1), "1 data day")
        XCTAssertEqual(ExportHistoryDetailView.dataDayDescription(2), "2 data days")
    }
    #endif

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
        XCTAssertEqual(history.history.first?.fileCount, 0)
        XCTAssertEqual(history.history.first?.outputBreakdown.generatedFileCount, 0)
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
        XCTAssertFalse(entry.isGeneratedFileDelivery)
        XCTAssertTrue(entry.isFullSuccess)
        XCTAssertEqual(entry.resultCountLabel, "Days Sent")
        XCTAssertEqual(entry.resultCountDescription, "2 of 2")
        XCTAssertEqual(entry.summaryDescription, "Sent 2 data days to CLI")
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
        XCTAssertEqual(entry.summaryDescription, "Partial: sent 3 of 3 data days to CLI")
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
        XCTAssertEqual(entry.summaryDescription, "Sent 1 data day to CLI")
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
        XCTAssertFalse(entry.isGeneratedFileDelivery)
        XCTAssertEqual(entry.resultCountLabel, "Days Uploaded")
        XCTAssertEqual(entry.resultCountDescription, "1 of 1")
        XCTAssertEqual(entry.summaryDescription, "Uploaded 1 data day to API")
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

        XCTAssertTrue(entry.isDailyNoteOnlyResult)
        XCTAssertFalse(entry.isGeneratedFileDelivery)
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
        XCTAssertEqual(entry.summaryDescription, "Skipped 2 missing daily notes")
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
        XCTAssertTrue(entry.summaryDescription.contains("3 files"))
        XCTAssertTrue(entry.summaryDescription.contains("3 of 5 data days"))
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

    func testEntry_codableRoundTripPreservesBoundedOutputAndRecoveryBreakdown() throws {
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 2,
            successfulDataDayCount: 1,
            looseAggregateFileCount: 3,
            individualEntryFileCount: 34,
            zipArchiveFileCount: 1,
            rollupFileCount: 2,
            providerSidecarFileCount: 4,
            dailyNoteUpdateCount: 1,
            dailyNoteSkipCount: 1
        )
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 2,
            fileCount: breakdown.generatedFileCount,
            outputBreakdown: breakdown,
            pendingRecoveryDayCount: 2,
            dailyNoteUpdateCount: 1,
            dailyNoteSkipCount: 1
        )

        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONEncoder().encode(entry)
        )

        XCTAssertEqual(decoded.outputBreakdown, breakdown)
        XCTAssertEqual(decoded.pendingRecoveryDayCount, 2)
        XCTAssertTrue(decoded.isPendingRecovery)
        XCTAssertEqual(
            decoded.pendingRecoveryDescription,
            "Retried 2 pending recovery data days from an earlier scheduled occurrence."
        )
    }

    func testEntry_decodesLegacyHistoryWithSensibleOutputFallbacks() throws {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 2,
            totalCount: 3,
            fileCount: 6,
            dailyNoteUpdateCount: 1,
            dailyNoteSkipCount: 0
        )
        let encoded = try JSONEncoder().encode(entry)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "outputBreakdown")
        legacyObject.removeValue(forKey: "pendingRecoveryDayCount")
        legacyObject.removeValue(forKey: "wasCancelled")

        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )

        XCTAssertEqual(decoded.outputBreakdown.requestedDataDayCount, 3)
        XCTAssertEqual(decoded.outputBreakdown.successfulDataDayCount, 2)
        XCTAssertEqual(decoded.outputBreakdown.generatedFileCount, 6)
        XCTAssertEqual(decoded.outputBreakdown.unclassifiedFileCount, 6)
        XCTAssertEqual(decoded.outputBreakdown.dailyNoteUpdateCount, 1)
        XCTAssertFalse(decoded.outputBreakdown.isFileCategoryBreakdownComplete)
        XCTAssertEqual(decoded.pendingRecoveryDayCount, 0)
        XCTAssertFalse(decoded.isPendingRecovery)
        XCTAssertFalse(decoded.wasCancelled)
    }

    func testEntryDecodesPreDictionaryBreakdownAsIncomplete() throws {
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: 2
        )
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            fileCount: 2,
            outputBreakdown: breakdown
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        )
        var legacyBreakdown = try XCTUnwrap(object["outputBreakdown"] as? [String: Any])
        legacyBreakdown.removeValue(forKey: "dataDictionaryFileCount")
        object["outputBreakdown"] = legacyBreakdown

        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.outputBreakdown.generatedFileCount, 2)
        XCTAssertEqual(decoded.outputBreakdown.dataDictionaryFileCount, 0)
        XCTAssertFalse(decoded.outputBreakdown.isFileCategoryBreakdownComplete)
    }

    func testEntryDecoderClampsAndReconcilesCorruptLegacyCounts() throws {
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            fileCount: 1
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        )
        object["successCount"] = Int.max
        object["totalCount"] = Int.max
        object["fileCount"] = -100
        object["pendingRecoveryDayCount"] = Int.max
        object["dailyNoteUpdateCount"] = Int.max
        object["dailyNoteSkipCount"] = Int.max
        object.removeValue(forKey: "outputBreakdown")

        let decoded = try JSONDecoder().decode(
            ExportHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.successCount, ExportHistoryOutputBreakdown.maximumPersistedCount)
        XCTAssertEqual(decoded.totalCount, ExportHistoryOutputBreakdown.maximumPersistedCount)
        XCTAssertEqual(decoded.fileCount, 0)
        XCTAssertEqual(decoded.outputBreakdown.generatedFileCount, 0)
        XCTAssertEqual(decoded.pendingRecoveryDayCount, ExportHistoryOutputBreakdown.maximumPersistedCount)
        XCTAssertEqual(decoded.dailyNoteUpdateCount, ExportHistoryOutputBreakdown.maximumPersistedCount)
        XCTAssertEqual(decoded.dailyNoteSkipCount, 0)
    }

    func testMacPayloadUsesAuthoritativeTotalWithoutInferringLooseFiles() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 2,
            totalCount: 2,
            formatsPerDate: 3,
            totalFilesWritten: 7,
            externalRecordFileCount: 1,
            failedDateDetails: [],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)

        XCTAssertEqual(result.looseAggregateFileCount, 0)
        XCTAssertEqual(result.externalRecordFileCount, 1)
        XCTAssertEqual(result.totalFilesWritten, 7)
        XCTAssertEqual(result.outputBreakdown.unclassifiedFileCount, 6)
        XCTAssertFalse(result.outputBreakdown.isFileCategoryBreakdownComplete)
    }

    func testOutputBreakdownDropsContradictoryCategoriesDuringReconciliation() {
        let measured = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: 10,
            individualEntryFileCount: 5
        )

        let reconciled = measured.reconciled(toAuthoritativeFileCount: 4)

        XCTAssertEqual(reconciled.generatedFileCount, 4)
        XCTAssertEqual(reconciled.categorizedFileCount, 0)
        XCTAssertEqual(reconciled.unclassifiedFileCount, 4)
        XCTAssertFalse(reconciled.isFileCategoryBreakdownComplete)
    }

    func testOutputBreakdownClampsPersistedCountsAndOverflowingTotals() {
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: .max,
            successfulDataDayCount: -1,
            looseAggregateFileCount: .max,
            individualEntryFileCount: .max,
            dailyNoteSkipCount: -10,
            unclassifiedFileCount: .max,
            isFileCategoryBreakdownComplete: true
        )

        XCTAssertEqual(
            breakdown.requestedDataDayCount,
            ExportHistoryOutputBreakdown.maximumPersistedCount
        )
        XCTAssertEqual(breakdown.successfulDataDayCount, 0)
        XCTAssertEqual(
            breakdown.generatedFileCount,
            ExportHistoryOutputBreakdown.maximumPersistedCount
        )
        XCTAssertEqual(breakdown.unclassifiedFileCount, 0)
        XCTAssertEqual(breakdown.dailyNoteSkipCount, 0)
        XCTAssertFalse(breakdown.isFileCategoryBreakdownComplete)
    }

    func testOutputBreakdownDecoderClampsCorruptLegacyCounts() throws {
        let encoded = try JSONSerialization.data(withJSONObject: [
            "requestedDataDayCount": Int.max,
            "successfulDataDayCount": -1,
            "looseAggregateFileCount": Int.max,
            "individualEntryFileCount": Int.max,
            "unclassifiedFileCount": Int.max,
            "dailyNoteSkipCount": -10,
            "isFileCategoryBreakdownComplete": true
        ])

        let breakdown = try JSONDecoder().decode(ExportHistoryOutputBreakdown.self, from: encoded)

        XCTAssertEqual(
            breakdown.requestedDataDayCount,
            ExportHistoryOutputBreakdown.maximumPersistedCount
        )
        XCTAssertEqual(breakdown.successfulDataDayCount, 0)
        XCTAssertEqual(
            breakdown.generatedFileCount,
            ExportHistoryOutputBreakdown.maximumPersistedCount
        )
        XCTAssertEqual(breakdown.dailyNoteSkipCount, 0)
        XCTAssertFalse(breakdown.isFileCategoryBreakdownComplete)
    }

    func testGeneratedFileAndRecoveryDescriptionsUseCompleteSingularAndPluralLiterals() {
        let singularBreakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: 1
        )
        let singular = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            fileCount: 1,
            outputBreakdown: singularBreakdown,
            pendingRecoveryDayCount: 1
        )
        XCTAssertEqual(singular.summaryDescription, "Exported 1 file from 1 data day")
        XCTAssertEqual(singular.generatedFileCountDescription, "1 generated file")
        XCTAssertEqual(singular.dataDayCountDescription, "1 of 1 data day")
        XCTAssertEqual(singular.pendingRecoveryBadgeDescription, "Pending recovery · 1 data day")
        XCTAssertEqual(
            singular.pendingRecoveryDescription,
            "Retried 1 pending recovery data day from an earlier scheduled occurrence."
        )

        let pluralBreakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 2,
            successfulDataDayCount: 2,
            looseAggregateFileCount: 2
        )
        let plural = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 2,
            totalCount: 2,
            fileCount: 2,
            outputBreakdown: pluralBreakdown,
            pendingRecoveryDayCount: 2
        )
        XCTAssertEqual(plural.summaryDescription, "Exported 2 files from 2 data days")
        XCTAssertEqual(plural.generatedFileCountDescription, "2 generated files")
        XCTAssertEqual(plural.dataDayCountDescription, "2 of 2 data days")
        XCTAssertEqual(plural.pendingRecoveryBadgeDescription, "Pending recovery · 2 data days")
        XCTAssertFalse(plural.summaryAccessibilityDescription.contains("(s)"))
    }

    func testGeneratedFileRowSummaryAndAccessibilityDistinguishFilesFromDataDays() {
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: 4,
            individualEntryFileCount: 35,
            zipArchiveFileCount: 1
        )
        let entry = ExportHistoryEntry(
            source: .scheduled,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            fileCount: 40,
            outputBreakdown: breakdown,
            pendingRecoveryDayCount: 1
        )
        XCTAssertEqual(entry.summaryDescription, "Exported 40 files from 1 data day")
        XCTAssertEqual(entry.generatedFileCountDescription, "40 generated files")
        XCTAssertEqual(entry.dataDayCountDescription, "1 of 1 data day")
        XCTAssertTrue(entry.resultCountAccessibilityDescription.contains("40 generated files"))
        XCTAssertTrue(entry.resultCountAccessibilityDescription.contains("1 of 1 data day"))
        #if os(iOS)
        let row = ExportHistoryRow(entry: entry)
        XCTAssertTrue(row.accessibilityDescription.contains("Exported 40 files from 1 data day"))
        XCTAssertTrue(row.accessibilityDescription.contains("pending recovery data day"))
        #endif
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
