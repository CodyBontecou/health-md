import Foundation
import Combine

/// Privacy-safe request and transfer metadata for an export history entry.
/// Health values and generated file contents are deliberately never persisted here.
struct ExportHistoryOperationDetails: Codable, Equatable {
    enum Kind: String, Codable {
        case generatedFiles = "generated_files"
        case rawExport = "raw_export"
        case canonicalExtraction = "canonical_extraction"
    }

    let kind: Kind
    let requestID: UUID
    let dateSelection: String
    let settingsPolicy: String
    let profile: String?
    let detailLevel: String?
    let metricIDs: [String]
    let categoryIDs: [String]
    let sourceIDs: [String]
    let objectPaths: [String]
    let fieldPointers: [String]
    let partitionCount: Int
    let transferredBytes: Int64
    let sampleCount: Int?
    let recordCount: Int?
    let warningDayCount: Int
    let failedDayCount: Int
    let integrityWarningCount: Int
    let partialFailureCount: Int

    init(
        kind: Kind,
        requestID: UUID,
        dateSelection: String,
        settingsPolicy: String,
        profile: String? = nil,
        detailLevel: String? = nil,
        metricIDs: [String] = [],
        categoryIDs: [String] = [],
        sourceIDs: [String] = [],
        objectPaths: [String] = [],
        fieldPointers: [String] = [],
        partitionCount: Int = 0,
        transferredBytes: Int64 = 0,
        sampleCount: Int? = nil,
        recordCount: Int? = nil,
        warningDayCount: Int = 0,
        failedDayCount: Int = 0,
        integrityWarningCount: Int = 0,
        partialFailureCount: Int = 0
    ) {
        self.kind = kind
        self.requestID = requestID
        self.dateSelection = dateSelection
        self.settingsPolicy = settingsPolicy
        self.profile = profile
        self.detailLevel = detailLevel
        self.metricIDs = Self.boundedValues(metricIDs, maximumCount: 512, maximumUTF8Bytes: 128)
        self.categoryIDs = Self.boundedValues(categoryIDs, maximumCount: 64, maximumUTF8Bytes: 128)
        self.sourceIDs = Self.boundedValues(sourceIDs, maximumCount: 32, maximumUTF8Bytes: 128)
        self.objectPaths = Self.boundedValues(objectPaths, maximumCount: 128, maximumUTF8Bytes: 1_024)
        self.fieldPointers = Self.boundedValues(fieldPointers, maximumCount: 256, maximumUTF8Bytes: 1_024)
        self.partitionCount = max(partitionCount, 0)
        self.transferredBytes = max(transferredBytes, 0)
        self.sampleCount = sampleCount.map { max($0, 0) }
        self.recordCount = recordCount.map { max($0, 0) }
        self.warningDayCount = max(warningDayCount, 0)
        self.failedDayCount = max(failedDayCount, 0)
        self.integrityWarningCount = max(integrityWarningCount, 0)
        self.partialFailureCount = max(partialFailureCount, 0)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(Kind.self, forKey: .kind),
            requestID: try container.decode(UUID.self, forKey: .requestID),
            dateSelection: try container.decode(String.self, forKey: .dateSelection),
            settingsPolicy: try container.decode(String.self, forKey: .settingsPolicy),
            profile: try container.decodeIfPresent(String.self, forKey: .profile),
            detailLevel: try container.decodeIfPresent(String.self, forKey: .detailLevel),
            metricIDs: try container.decodeIfPresent([String].self, forKey: .metricIDs) ?? [],
            categoryIDs: try container.decodeIfPresent([String].self, forKey: .categoryIDs) ?? [],
            sourceIDs: try container.decodeIfPresent([String].self, forKey: .sourceIDs) ?? [],
            objectPaths: try container.decodeIfPresent([String].self, forKey: .objectPaths) ?? [],
            fieldPointers: try container.decodeIfPresent([String].self, forKey: .fieldPointers) ?? [],
            partitionCount: try container.decodeIfPresent(Int.self, forKey: .partitionCount) ?? 0,
            transferredBytes: try container.decodeIfPresent(Int64.self, forKey: .transferredBytes) ?? 0,
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount),
            recordCount: try container.decodeIfPresent(Int.self, forKey: .recordCount),
            warningDayCount: try container.decodeIfPresent(Int.self, forKey: .warningDayCount) ?? 0,
            failedDayCount: try container.decodeIfPresent(Int.self, forKey: .failedDayCount) ?? 0,
            integrityWarningCount: try container.decodeIfPresent(Int.self, forKey: .integrityWarningCount) ?? 0,
            partialFailureCount: try container.decodeIfPresent(Int.self, forKey: .partialFailureCount) ?? 0
        )
    }

    var hasWarnings: Bool {
        warningDayCount > 0 || failedDayCount > 0 ||
            integrityWarningCount > 0 || partialFailureCount > 0
    }

    private static func boundedValues(
        _ values: [String],
        maximumCount: Int,
        maximumUTF8Bytes: Int
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty && value.utf8.count <= maximumUTF8Bytes {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count == maximumCount { break }
        }
        return result.sorted()
    }
}

/// Bounded, health-free accounting for one export attempt. Counts describe days and
/// destination side effects only; filenames and exported health values are never stored.
nonisolated struct ExportHistoryOutputBreakdown: Codable, Equatable, Sendable {
    nonisolated static let maximumPersistedCount = 10_000_000

    let requestedDataDayCount: Int
    let successfulDataDayCount: Int
    let looseAggregateFileCount: Int
    let individualEntryFileCount: Int
    let dataDictionaryFileCount: Int
    let zipArchiveFileCount: Int
    let rollupFileCount: Int
    let providerSidecarFileCount: Int
    let dailyNoteUpdateCount: Int
    let dailyNoteSkipCount: Int
    /// Preserves an authoritative total when its categories were not recorded.
    let unclassifiedFileCount: Int
    let isFileCategoryBreakdownComplete: Bool

    enum CodingKeys: String, CodingKey {
        case requestedDataDayCount, successfulDataDayCount
        case looseAggregateFileCount, individualEntryFileCount, dataDictionaryFileCount
        case zipArchiveFileCount, rollupFileCount, providerSidecarFileCount
        case dailyNoteUpdateCount, dailyNoteSkipCount
        case unclassifiedFileCount, isFileCategoryBreakdownComplete
    }

    init(
        requestedDataDayCount: Int,
        successfulDataDayCount: Int,
        looseAggregateFileCount: Int = 0,
        individualEntryFileCount: Int = 0,
        dataDictionaryFileCount: Int = 0,
        zipArchiveFileCount: Int = 0,
        rollupFileCount: Int = 0,
        providerSidecarFileCount: Int = 0,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        unclassifiedFileCount: Int = 0,
        isFileCategoryBreakdownComplete: Bool = true
    ) {
        self.requestedDataDayCount = Self.boundedCount(requestedDataDayCount)
        self.successfulDataDayCount = Self.boundedCount(successfulDataDayCount)
        self.dailyNoteUpdateCount = Self.boundedCount(dailyNoteUpdateCount)
        self.dailyNoteSkipCount = Self.boundedCount(dailyNoteSkipCount)

        var remaining = Self.maximumPersistedCount
        var wasTruncated = false
        func allocate(_ value: Int) -> Int {
            let bounded = Self.boundedCount(value)
            let allocated = min(bounded, remaining)
            if allocated != bounded { wasTruncated = true }
            remaining -= allocated
            return allocated
        }

        self.looseAggregateFileCount = allocate(looseAggregateFileCount)
        self.individualEntryFileCount = allocate(individualEntryFileCount)
        self.dataDictionaryFileCount = allocate(dataDictionaryFileCount)
        self.zipArchiveFileCount = allocate(zipArchiveFileCount)
        self.rollupFileCount = allocate(rollupFileCount)
        self.providerSidecarFileCount = allocate(providerSidecarFileCount)
        self.unclassifiedFileCount = allocate(unclassifiedFileCount)
        self.isFileCategoryBreakdownComplete = isFileCategoryBreakdownComplete
            && !wasTruncated
            && self.unclassifiedFileCount == 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasDictionaryCategory = container.contains(.dataDictionaryFileCount)
        let decodedCompleteness = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFileCategoryBreakdownComplete
        ) ?? false
        self.init(
            requestedDataDayCount: try container.decodeIfPresent(Int.self, forKey: .requestedDataDayCount) ?? 0,
            successfulDataDayCount: try container.decodeIfPresent(Int.self, forKey: .successfulDataDayCount) ?? 0,
            looseAggregateFileCount: try container.decodeIfPresent(Int.self, forKey: .looseAggregateFileCount) ?? 0,
            individualEntryFileCount: try container.decodeIfPresent(Int.self, forKey: .individualEntryFileCount) ?? 0,
            dataDictionaryFileCount: try container.decodeIfPresent(Int.self, forKey: .dataDictionaryFileCount) ?? 0,
            zipArchiveFileCount: try container.decodeIfPresent(Int.self, forKey: .zipArchiveFileCount) ?? 0,
            rollupFileCount: try container.decodeIfPresent(Int.self, forKey: .rollupFileCount) ?? 0,
            providerSidecarFileCount: try container.decodeIfPresent(Int.self, forKey: .providerSidecarFileCount) ?? 0,
            dailyNoteUpdateCount: try container.decodeIfPresent(Int.self, forKey: .dailyNoteUpdateCount) ?? 0,
            dailyNoteSkipCount: try container.decodeIfPresent(Int.self, forKey: .dailyNoteSkipCount) ?? 0,
            unclassifiedFileCount: try container.decodeIfPresent(Int.self, forKey: .unclassifiedFileCount) ?? 0,
            isFileCategoryBreakdownComplete: hasDictionaryCategory && decodedCompleteness
        )
    }

    var categorizedFileCount: Int {
        looseAggregateFileCount
            + individualEntryFileCount
            + dataDictionaryFileCount
            + zipArchiveFileCount
            + rollupFileCount
            + providerSidecarFileCount
    }

    var generatedFileCount: Int {
        categorizedFileCount + unclassifiedFileCount
    }

    func reconciled(toAuthoritativeFileCount fileCount: Int) -> ExportHistoryOutputBreakdown {
        let authoritativeCount = Self.boundedCount(fileCount)
        guard authoritativeCount != generatedFileCount else { return self }

        guard authoritativeCount >= categorizedFileCount else {
            return ExportHistoryOutputBreakdown(
                requestedDataDayCount: requestedDataDayCount,
                successfulDataDayCount: successfulDataDayCount,
                dailyNoteUpdateCount: dailyNoteUpdateCount,
                dailyNoteSkipCount: dailyNoteSkipCount,
                unclassifiedFileCount: authoritativeCount,
                isFileCategoryBreakdownComplete: false
            )
        }

        return ExportHistoryOutputBreakdown(
            requestedDataDayCount: requestedDataDayCount,
            successfulDataDayCount: successfulDataDayCount,
            looseAggregateFileCount: looseAggregateFileCount,
            individualEntryFileCount: individualEntryFileCount,
            dataDictionaryFileCount: dataDictionaryFileCount,
            zipArchiveFileCount: zipArchiveFileCount,
            rollupFileCount: rollupFileCount,
            providerSidecarFileCount: providerSidecarFileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            unclassifiedFileCount: authoritativeCount - categorizedFileCount,
            isFileCategoryBreakdownComplete: false
        )
    }

    static func legacyFallback(
        requestedDataDayCount: Int,
        successfulDataDayCount: Int,
        fileCount: Int?,
        dailyNoteUpdateCount: Int,
        dailyNoteSkipCount: Int
    ) -> ExportHistoryOutputBreakdown {
        ExportHistoryOutputBreakdown(
            requestedDataDayCount: requestedDataDayCount,
            successfulDataDayCount: successfulDataDayCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            unclassifiedFileCount: fileCount ?? successfulDataDayCount,
            isFileCategoryBreakdownComplete: false
        )
    }

    nonisolated static func boundedCount(_ value: Int) -> Int {
        min(max(value, 0), maximumPersistedCount)
    }
}

/// Represents a single export attempt (successful or failed)
struct ExportHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: ExportSource
    let success: Bool
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let successCount: Int
    let totalCount: Int
    let failureReason: ExportFailureReason?
    let failedDateDetails: [FailedDateDetail]
    let targetLabel: String?
    let exportTarget: ExportTargetSelection?
    let fileCount: Int?
    let outputBreakdown: ExportHistoryOutputBreakdown
    /// Number of exact pending scheduled data days this run retried. Zero means
    /// the entry was not produced by pending-recovery processing.
    let pendingRecoveryDayCount: Int
    let dailyNoteUpdateCount: Int
    let dailyNoteSkipCount: Int
    let partialFailures: [ExportPartialFailure]
    /// Terminal cancellation is persisted separately from confirmed successful output.
    /// Missing on older entries decodes as false.
    let wasCancelled: Bool
    /// A producer reported a non-success terminal state after any confirmed output. This is
    /// separate from cancellation and defaults to false for pre-field history entries.
    let hadTerminalFailure: Bool
    /// Health-free renderer provenance for diagnostics and rollback analysis.
    let appleExportEnginePin: AppleExportEnginePin?
    /// Bounded CLI request/transfer facts. Never contains exported health values.
    let operationDetails: ExportHistoryOperationDetails?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, source, success, dateRangeStart, dateRangeEnd
        case successCount, totalCount, failureReason, failedDateDetails
        case targetLabel, exportTarget, fileCount, outputBreakdown, pendingRecoveryDayCount
        case dailyNoteUpdateCount, dailyNoteSkipCount, partialFailures, wasCancelled
        case hadTerminalFailure, appleExportEnginePin, operationDetails
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: ExportSource,
        success: Bool,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        successCount: Int,
        totalCount: Int,
        failureReason: ExportFailureReason? = nil,
        failedDateDetails: [FailedDateDetail] = [],
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        outputBreakdown: ExportHistoryOutputBreakdown? = nil,
        pendingRecoveryDayCount: Int = 0,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        partialFailures: [ExportPartialFailure] = [],
        wasCancelled: Bool = false,
        hadTerminalFailure: Bool = false,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        let normalizedTotalCount = ExportHistoryOutputBreakdown.boundedCount(totalCount)
        let normalizedSuccessCount = min(
            ExportHistoryOutputBreakdown.boundedCount(successCount),
            normalizedTotalCount
        )
        let normalizedDailyNoteUpdateCount = min(
            ExportHistoryOutputBreakdown.boundedCount(dailyNoteUpdateCount),
            normalizedTotalCount
        )
        let normalizedDailyNoteSkipCount = min(
            ExportHistoryOutputBreakdown.boundedCount(dailyNoteSkipCount),
            normalizedTotalCount - normalizedDailyNoteUpdateCount
        )
        self.source = source
        self.success = success
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.successCount = normalizedSuccessCount
        self.totalCount = normalizedTotalCount
        self.failureReason = failureReason
        self.failedDateDetails = failedDateDetails
        self.targetLabel = targetLabel
        self.exportTarget = exportTarget
        let normalizedFileCount = fileCount.map(ExportHistoryOutputBreakdown.boundedCount)
        let initialBreakdown = outputBreakdown ?? .legacyFallback(
            requestedDataDayCount: normalizedTotalCount,
            successfulDataDayCount: normalizedSuccessCount,
            fileCount: normalizedFileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount
        )
        let fileReconciledBreakdown = normalizedFileCount.map {
            initialBreakdown.reconciled(toAuthoritativeFileCount: $0)
        } ?? initialBreakdown
        let normalizedBreakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: normalizedTotalCount,
            successfulDataDayCount: normalizedSuccessCount,
            looseAggregateFileCount: fileReconciledBreakdown.looseAggregateFileCount,
            individualEntryFileCount: fileReconciledBreakdown.individualEntryFileCount,
            dataDictionaryFileCount: fileReconciledBreakdown.dataDictionaryFileCount,
            zipArchiveFileCount: fileReconciledBreakdown.zipArchiveFileCount,
            rollupFileCount: fileReconciledBreakdown.rollupFileCount,
            providerSidecarFileCount: fileReconciledBreakdown.providerSidecarFileCount,
            dailyNoteUpdateCount: normalizedDailyNoteUpdateCount,
            dailyNoteSkipCount: normalizedDailyNoteSkipCount,
            unclassifiedFileCount: fileReconciledBreakdown.unclassifiedFileCount,
            isFileCategoryBreakdownComplete: fileReconciledBreakdown.isFileCategoryBreakdownComplete
        )
        self.fileCount = normalizedFileCount.map { _ in normalizedBreakdown.generatedFileCount }
        self.outputBreakdown = normalizedBreakdown
        self.pendingRecoveryDayCount = min(
            ExportHistoryOutputBreakdown.boundedCount(pendingRecoveryDayCount),
            normalizedTotalCount
        )
        self.dailyNoteUpdateCount = normalizedDailyNoteUpdateCount
        self.dailyNoteSkipCount = normalizedDailyNoteSkipCount
        self.partialFailures = partialFailures
        self.wasCancelled = wasCancelled
        self.hadTerminalFailure = hadTerminalFailure
        self.appleExportEnginePin = appleExportEnginePin
        self.operationDetails = operationDetails
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSuccessCount = try container.decode(Int.self, forKey: .successCount)
        let decodedTotalCount = try container.decode(Int.self, forKey: .totalCount)
        let decodedFileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount)
        let decodedDailyNoteUpdateCount = try container.decodeIfPresent(
            Int.self,
            forKey: .dailyNoteUpdateCount
        ) ?? 0
        let decodedDailyNoteSkipCount = try container.decodeIfPresent(
            Int.self,
            forKey: .dailyNoteSkipCount
        ) ?? 0
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            source: try container.decode(ExportSource.self, forKey: .source),
            success: try container.decode(Bool.self, forKey: .success),
            dateRangeStart: try container.decode(Date.self, forKey: .dateRangeStart),
            dateRangeEnd: try container.decode(Date.self, forKey: .dateRangeEnd),
            successCount: decodedSuccessCount,
            totalCount: decodedTotalCount,
            failureReason: try container.decodeIfPresent(ExportFailureReason.self, forKey: .failureReason),
            failedDateDetails: try container.decodeIfPresent(
                [FailedDateDetail].self,
                forKey: .failedDateDetails
            ) ?? [],
            targetLabel: try container.decodeIfPresent(String.self, forKey: .targetLabel),
            exportTarget: try container.decodeIfPresent(ExportTargetSelection.self, forKey: .exportTarget),
            fileCount: decodedFileCount,
            outputBreakdown: try container.decodeIfPresent(
                ExportHistoryOutputBreakdown.self,
                forKey: .outputBreakdown
            ),
            pendingRecoveryDayCount: try container.decodeIfPresent(
                Int.self,
                forKey: .pendingRecoveryDayCount
            ) ?? 0,
            dailyNoteUpdateCount: decodedDailyNoteUpdateCount,
            dailyNoteSkipCount: decodedDailyNoteSkipCount,
            partialFailures: try container.decodeIfPresent(
                [ExportPartialFailure].self,
                forKey: .partialFailures
            ) ?? [],
            wasCancelled: try container.decodeIfPresent(Bool.self, forKey: .wasCancelled) ?? false,
            hadTerminalFailure: try container.decodeIfPresent(
                Bool.self,
                forKey: .hadTerminalFailure
            ) ?? false,
            appleExportEnginePin: try container.decodeIfPresent(
                AppleExportEnginePin.self,
                forKey: .appleExportEnginePin
            ),
            operationDetails: try container.decodeIfPresent(
                ExportHistoryOperationDetails.self,
                forKey: .operationDetails
            )
        )
    }

    /// Returns true if all exports succeeded
    var isFullSuccess: Bool {
        success
            && !wasCancelled
            && !hadTerminalFailure
            && successCount == totalCount
            && totalCount > 0
            && failedDateDetails.isEmpty
            && partialFailures.isEmpty
            && operationDetails?.hasWarnings != true
    }

    /// Returns true when confirmed output exists but the terminal result was not full success.
    var isPartialSuccess: Bool {
        success && (successCount > 0 || dailyNoteSkipCount > 0)
            && (successCount < totalCount
                || wasCancelled
                || hadTerminalFailure
                || !failedDateDetails.isEmpty
                || !partialFailures.isEmpty
                || operationDetails?.hasWarnings == true)
    }

    var partialFailureSummary: String? {
        guard let first = partialFailures.first else { return nil }
        if partialFailures.count == 1 {
            return "Warning: \(first.summary)"
        }
        return "Warning: \(partialFailures.count) metric fetches failed, including \(first.summary)"
    }

    /// Resolves the most useful reason available, including older history entries
    /// that only persisted a reason on their per-date failure details.
    var failureReasonForDisplay: ExportFailureReason? {
        guard !isFullSuccess else { return nil }
        if let failureReason { return failureReason }
        if let failedDateReason = failedDateDetails.first?.reason { return failedDateReason }
        return success ? nil : .unknown
    }

    var failureRecoverySuggestion: String? {
        failureReasonForDisplay?.recoverySuggestion
    }

    /// Keeps the history list useful at a glance. Generic and write failures use
    /// the captured error when one exists; known failures lead with the fix.
    var failureListMessage: String? {
        guard let reason = failureReasonForDisplay else { return nil }
        if reason == .unknown || reason == .fileWriteError,
           let diagnostic = failureDiagnosticDetails.first {
            return diagnostic
        }
        return reason.recoverySuggestion
    }

    /// Unique underlying messages retained by the export pipeline. These are kept
    /// separate from the plain-language reason so the UI can show them without
    /// making the primary explanation feel like a generic system error.
    var failureDiagnosticDetails: [String] {
        guard !isFullSuccess else { return [] }

        var seen: Set<String> = []
        return failedDateDetails.compactMap { detail in
            guard let rawDetails = detail.errorDetails else { return nil }
            let details = rawDetails.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !details.isEmpty, seen.insert(details).inserted else { return nil }
            return details
        }
    }

    var isDailyNoteOnlyResult: Bool {
        (dailyNoteUpdateCount > 0 || dailyNoteSkipCount > 0) && fileCount == 0
    }

    /// Raw CLI responses transfer daily data rather than generated files. The
    /// target-label fallback repairs entries written by older app versions.
    var isCLIRawDelivery: Bool {
        if let kind = operationDetails?.kind {
            return kind == .rawExport || kind == .canonicalExtraction
        }
        guard source == .macAgent, fileCount == 0, let targetLabel else { return false }
        return targetLabel == "CLI raw response" || targetLabel == "Direct CLI raw response"
    }

    var sourceLabelForDisplay: String {
        operationDetails != nil || isCLIRawDelivery
            ? String(localized: "Health.md CLI")
            : source.rawValue
    }

    var sourceIconForDisplay: String {
        operationDetails != nil || isCLIRawDelivery ? "terminal.fill" : source.icon
    }

    /// API Endpoint exports POST daily records directly and intentionally do not
    /// create local files. The hostname fallback recognizes entries persisted by
    /// older app versions before `exportTarget` was stored in history.
    var isAPIEndpointDelivery: Bool {
        if exportTarget == .apiEndpoint { return true }
        guard exportTarget == nil,
              successCount > 0,
              fileCount == 0,
              !isDailyNoteOnlyResult,
              let targetLabel else { return false }
        return targetLabel == "localhost" || targetLabel.contains(".")
    }

    /// Known generated files. This is an exact total only when `fileCount` is non-nil;
    /// otherwise it is a lower bound assembled from confirmed category writes.
    var generatedFileCountForDisplay: Int {
        outputBreakdown.generatedFileCount
    }

    var hasAuthoritativeGeneratedFileCount: Bool {
        fileCount != nil
    }

    var generatedFileCountCompactDescription: String {
        if let fileCount { return "\(fileCount)" }
        let lowerBound = generatedFileCountForDisplay
        if lowerBound == 0 {
            return String(localized: "Unknown", comment: "Export history compact generated-file total when no authoritative total or lower bound is available")
        }
        return String(localized: "At least \(lowerBound)", comment: "Export history compact generated-file lower bound when no authoritative total is available")
    }

    var isPendingRecovery: Bool {
        source == .scheduled && pendingRecoveryDayCount > 0
    }

    var isGeneratedFileDelivery: Bool {
        !isDailyNoteOnlyResult && !isCLIRawDelivery && !isAPIEndpointDelivery
    }

    var dataDayCountDescription: String {
        totalCount == 1
            ? String(localized: "\(successCount) of 1 data day", comment: "Export history successful data-day count when one day was requested")
            : String(localized: "\(successCount) of \(totalCount) data days", comment: "Export history successful data-day count when multiple days were requested")
    }

    var generatedFileCountDescription: String {
        if let fileCount {
            return fileCount == 1
                ? String(localized: "1 generated file", comment: "Export history authoritative generated-file count when singular")
                : String(localized: "\(fileCount) generated files", comment: "Export history authoritative generated-file count when plural or zero")
        }
        let lowerBound = generatedFileCountForDisplay
        if lowerBound == 0 {
            return String(localized: "Unknown", comment: "Export history generated-file total when no authoritative total or lower bound is available")
        }
        return lowerBound == 1
            ? String(localized: "At least 1 generated file", comment: "Export history generated-file lower bound when singular")
            : String(localized: "At least \(lowerBound) generated files", comment: "Export history generated-file lower bound when plural")
    }

    var pendingRecoveryCountDescription: String {
        pendingRecoveryDayCount == 1
            ? String(localized: "1 pending recovery data day", comment: "Export history pending recovery count when singular")
            : String(localized: "\(pendingRecoveryDayCount) pending recovery data days", comment: "Export history pending recovery count when plural")
    }

    var pendingRecoveryBadgeDescription: String {
        pendingRecoveryDayCount == 1
            ? String(localized: "Pending recovery · 1 data day", comment: "Export history pending recovery badge when singular")
            : String(localized: "Pending recovery · \(pendingRecoveryDayCount) data days", comment: "Export history pending recovery badge when plural")
    }

    var pendingRecoveryDescription: String? {
        guard isPendingRecovery else { return nil }
        return pendingRecoveryDayCount == 1
            ? String(localized: "Retried 1 pending recovery data day from an earlier scheduled occurrence.", comment: "Export history recovery detail when one pending day was attempted")
            : String(localized: "Retried \(pendingRecoveryDayCount) pending recovery data days from an earlier scheduled occurrence.", comment: "Export history recovery detail when multiple pending days were attempted")
    }

    var resultCountLabel: String {
        if isDailyNoteOnlyResult {
            return String(localized: "Daily Notes Updated")
        }
        if isCLIRawDelivery {
            return String(localized: "Days Sent")
        }
        if isAPIEndpointDelivery {
            return String(localized: "Days Uploaded")
        }
        return String(localized: "Files Exported")
    }

    var resultCountDescription: String {
        if isDailyNoteOnlyResult {
            switch (dailyNoteUpdateCount == 1, totalCount == 1) {
            case (true, true):
                return String(localized: "1 note (\(successCount) of 1 data day)", comment: "Export history daily-note result when one note and one data day were requested")
            case (true, false):
                return String(localized: "1 note (\(successCount) of \(totalCount) data days)", comment: "Export history daily-note result when one note and multiple data days were requested")
            case (false, true):
                return String(localized: "\(dailyNoteUpdateCount) notes (\(successCount) of 1 data day)", comment: "Export history daily-note result when multiple notes and one data day were requested")
            case (false, false):
                return String(localized: "\(dailyNoteUpdateCount) notes (\(successCount) of \(totalCount) data days)", comment: "Export history daily-note result when multiple notes and data days were requested")
            }
        }
        if isCLIRawDelivery || isAPIEndpointDelivery {
            return String(localized: "\(successCount) of \(totalCount)", comment: "Export history delivered-day fraction")
        }
        if fileCount == nil {
            let count = generatedFileCountDescription
            return totalCount == 1
                ? String(localized: "\(count) from \(successCount) of 1 data day", comment: "Export history non-authoritative generated-file result with one requested data day")
                : String(localized: "\(count) from \(successCount) of \(totalCount) data days", comment: "Export history non-authoritative generated-file result with multiple requested data days")
        }
        switch (generatedFileCountForDisplay == 1, totalCount == 1) {
        case (true, true):
            return String(localized: "1 generated file from \(successCount) of 1 data day", comment: "Export history result with one generated file and one requested data day")
        case (true, false):
            return String(localized: "1 generated file from \(successCount) of \(totalCount) data days", comment: "Export history result with one generated file and multiple requested data days")
        case (false, true):
            return String(localized: "\(generatedFileCountForDisplay) generated files from \(successCount) of 1 data day", comment: "Export history result with multiple generated files and one requested data day")
        case (false, false):
            return String(localized: "\(generatedFileCountForDisplay) generated files from \(successCount) of \(totalCount) data days", comment: "Export history result with multiple generated files and requested data days")
        }
    }

    var resultCountAccessibilityDescription: String {
        if isDailyNoteOnlyResult {
            switch (dailyNoteUpdateCount == 1, totalCount == 1) {
            case (true, true):
                return String(localized: "1 daily note updated across \(successCount) of 1 data day", comment: "Accessible daily-note export count with one note and one requested data day")
            case (true, false):
                return String(localized: "1 daily note updated across \(successCount) of \(totalCount) data days", comment: "Accessible daily-note export count with one note and multiple requested data days")
            case (false, true):
                return String(localized: "\(dailyNoteUpdateCount) daily notes updated across \(successCount) of 1 data day", comment: "Accessible daily-note export count with multiple notes and one requested data day")
            case (false, false):
                return String(localized: "\(dailyNoteUpdateCount) daily notes updated across \(successCount) of \(totalCount) data days", comment: "Accessible daily-note export count with multiple notes and requested data days")
            }
        }
        if isCLIRawDelivery {
            return totalCount == 1
                ? String(localized: "\(successCount) of 1 data day sent to the CLI", comment: "Accessible CLI delivery count when one data day was requested")
                : String(localized: "\(successCount) of \(totalCount) data days sent to the CLI", comment: "Accessible CLI delivery count when multiple data days were requested")
        }
        if isAPIEndpointDelivery {
            return totalCount == 1
                ? String(localized: "\(successCount) of 1 data day uploaded", comment: "Accessible API delivery count when one data day was requested")
                : String(localized: "\(successCount) of \(totalCount) data days uploaded", comment: "Accessible API delivery count when multiple data days were requested")
        }
        if fileCount == nil {
            let lowerBound = generatedFileCountForDisplay
            if lowerBound == 0 {
                return totalCount == 1
                    ? String(localized: "Generated file count unknown from \(successCount) of 1 data day", comment: "Accessible export count when the file total is unknown and one data day was requested")
                    : String(localized: "Generated file count unknown from \(successCount) of \(totalCount) data days", comment: "Accessible export count when the file total is unknown and multiple data days were requested")
            }
            if lowerBound == 1 {
                return totalCount == 1
                    ? String(localized: "At least 1 generated file exported from \(successCount) of 1 data day", comment: "Accessible export lower bound with one file and one requested data day")
                    : String(localized: "At least 1 generated file exported from \(successCount) of \(totalCount) data days", comment: "Accessible export lower bound with one file and multiple requested data days")
            }
            return totalCount == 1
                ? String(localized: "At least \(lowerBound) generated files exported from \(successCount) of 1 data day", comment: "Accessible export lower bound with multiple files and one requested data day")
                : String(localized: "At least \(lowerBound) generated files exported from \(successCount) of \(totalCount) data days", comment: "Accessible export lower bound with multiple files and requested data days")
        }
        switch (generatedFileCountForDisplay == 1, totalCount == 1) {
        case (true, true):
            return String(localized: "1 generated file exported from \(successCount) of 1 data day", comment: "Accessible export count with one file and one requested data day")
        case (true, false):
            return String(localized: "1 generated file exported from \(successCount) of \(totalCount) data days", comment: "Accessible export count with one file and multiple requested data days")
        case (false, true):
            return String(localized: "\(generatedFileCountForDisplay) generated files exported from \(successCount) of 1 data day", comment: "Accessible export count with multiple files and one requested data day")
        case (false, false):
            return String(localized: "\(generatedFileCountForDisplay) generated files exported from \(successCount) of \(totalCount) data days", comment: "Accessible export count with multiple files and requested data days")
        }
    }

    var summaryAccessibilityDescription: String {
        guard let pendingRecoveryDescription else { return summaryDescription }
        return summaryDescription + " " + pendingRecoveryDescription
    }

    /// Summary description for display.
    var summaryDescription: String {
        if isDailyNoteOnlyResult {
            return dailyNoteSummaryDescription
        }
        if isCLIRawDelivery {
            if isFullSuccess {
                return successCount == 1
                    ? String(localized: "Sent 1 data day to CLI", comment: "CLI raw export success summary when singular")
                    : String(localized: "Sent \(successCount) data days to CLI", comment: "CLI raw export success summary when plural")
            }
            if isPartialSuccess {
                return totalCount == 1
                    ? String(localized: "Partial: sent \(successCount) of 1 data day to CLI", comment: "Partial CLI raw export summary when one data day was requested")
                    : String(localized: "Partial: sent \(successCount) of \(totalCount) data days to CLI", comment: "Partial CLI raw export summary when multiple data days were requested")
            }
        }
        if isAPIEndpointDelivery {
            if isFullSuccess {
                return successCount == 1
                    ? String(localized: "Uploaded 1 data day to API", comment: "API export success summary when singular")
                    : String(localized: "Uploaded \(successCount) data days to API", comment: "API export success summary when plural")
            }
            if isPartialSuccess {
                return partialAPISummaryDescription
            }
        }
        if isFullSuccess {
            return fullGeneratedFileSummaryDescription
        }
        if isPartialSuccess {
            return partialGeneratedFileSummaryDescription
        }
        return failureSummaryDescription
    }

    private var dailyNoteSummaryDescription: String {
        if dailyNoteSkipCount == 0 {
            return dailyNoteUpdateCount == 1
                ? String(localized: "Updated 1 daily note", comment: "Daily-note-only export success summary when singular")
                : String(localized: "Updated \(dailyNoteUpdateCount) daily notes", comment: "Daily-note-only export success summary when plural or zero")
        }
        if dailyNoteUpdateCount == 0 {
            return dailyNoteSkipCount == 1
                ? String(localized: "Skipped 1 missing daily note", comment: "Daily-note-only skip summary when singular")
                : String(localized: "Skipped \(dailyNoteSkipCount) missing daily notes", comment: "Daily-note-only skip summary when plural")
        }
        switch (dailyNoteUpdateCount == 1, dailyNoteSkipCount == 1) {
        case (true, true):
            return String(localized: "Updated 1 daily note and skipped 1 missing daily note", comment: "Daily-note-only mixed summary with singular updated and skipped counts")
        case (true, false):
            return String(localized: "Updated 1 daily note and skipped \(dailyNoteSkipCount) missing daily notes", comment: "Daily-note-only mixed summary with one update and multiple skips")
        case (false, true):
            return String(localized: "Updated \(dailyNoteUpdateCount) daily notes and skipped 1 missing daily note", comment: "Daily-note-only mixed summary with multiple updates and one skip")
        case (false, false):
            return String(localized: "Updated \(dailyNoteUpdateCount) daily notes and skipped \(dailyNoteSkipCount) missing daily notes", comment: "Daily-note-only mixed summary with multiple updated and skipped counts")
        }
    }

    private var partialAPISummaryDescription: String {
        if partialFailures.count == 1 {
            return totalCount == 1
                ? String(localized: "Partial: uploaded \(successCount) of 1 data day with 1 metric warning", comment: "Partial API export summary with one requested data day and one warning")
                : String(localized: "Partial: uploaded \(successCount) of \(totalCount) data days with 1 metric warning", comment: "Partial API export summary with requested data days and one warning")
        }
        if partialFailures.count > 1 {
            return totalCount == 1
                ? String(localized: "Partial: uploaded \(successCount) of 1 data day with \(partialFailures.count) metric warnings", comment: "Partial API export summary with one requested data day and multiple warnings")
                : String(localized: "Partial: uploaded \(successCount) of \(totalCount) data days with \(partialFailures.count) metric warnings", comment: "Partial API export summary with requested data days and multiple warnings")
        }
        return totalCount == 1
            ? String(localized: "Partial: uploaded \(successCount) of 1 data day", comment: "Partial API export summary with one requested data day and no metric warnings")
            : String(localized: "Partial: uploaded \(successCount) of \(totalCount) data days", comment: "Partial API export summary with requested data days and no metric warnings")
    }

    private var fullGeneratedFileSummaryDescription: String {
        if fileCount == nil {
            let lowerBound = generatedFileCountForDisplay
            if lowerBound == 0 {
                return successCount == 1
                    ? String(localized: "Exported files from 1 data day (Unknown total)", comment: "Export success summary when the generated-file total is unknown and one data day succeeded")
                    : String(localized: "Exported files from \(successCount) data days (Unknown total)", comment: "Export success summary when the generated-file total is unknown and multiple data days succeeded")
            }
            if lowerBound == 1 {
                return successCount == 1
                    ? String(localized: "Exported at least 1 file from 1 data day", comment: "Export success summary with a one-file lower bound and one successful data day")
                    : String(localized: "Exported at least 1 file from \(successCount) data days", comment: "Export success summary with a one-file lower bound and multiple successful data days")
            }
            return successCount == 1
                ? String(localized: "Exported at least \(lowerBound) files from 1 data day", comment: "Export success summary with a multiple-file lower bound and one successful data day")
                : String(localized: "Exported at least \(lowerBound) files from \(successCount) data days", comment: "Export success summary with a multiple-file lower bound and successful data days")
        }
        switch (generatedFileCountForDisplay == 1, successCount == 1) {
        case (true, true):
            return String(localized: "Exported 1 file from 1 data day", comment: "Export success summary with one file and one successful data day")
        case (true, false):
            return String(localized: "Exported 1 file from \(successCount) data days", comment: "Export success summary with one file and multiple successful data days")
        case (false, true):
            return String(localized: "Exported \(generatedFileCountForDisplay) files from 1 data day", comment: "Export success summary with multiple files and one successful data day")
        case (false, false):
            return String(localized: "Exported \(generatedFileCountForDisplay) files from \(successCount) data days", comment: "Export success summary with multiple files and successful data days")
        }
    }

    private var partialGeneratedFileSummaryDescription: String {
        if fileCount == nil {
            let lowerBound = generatedFileCountForDisplay
            let base: String
            if lowerBound == 0 {
                base = totalCount == 1
                    ? String(localized: "Partial: files from \(successCount) of 1 data day (Unknown total)", comment: "Partial export summary when the generated-file total is unknown and one data day was requested")
                    : String(localized: "Partial: files from \(successCount) of \(totalCount) data days (Unknown total)", comment: "Partial export summary when the generated-file total is unknown and multiple data days were requested")
            } else if lowerBound == 1 {
                base = totalCount == 1
                    ? String(localized: "Partial: at least 1 file from \(successCount) of 1 data day", comment: "Partial export summary with a one-file lower bound and one requested data day")
                    : String(localized: "Partial: at least 1 file from \(successCount) of \(totalCount) data days", comment: "Partial export summary with a one-file lower bound and requested data days")
            } else {
                base = totalCount == 1
                    ? String(localized: "Partial: at least \(lowerBound) files from \(successCount) of 1 data day", comment: "Partial export summary with a multiple-file lower bound and one requested data day")
                    : String(localized: "Partial: at least \(lowerBound) files from \(successCount) of \(totalCount) data days", comment: "Partial export summary with a multiple-file lower bound and requested data days")
            }
            if partialFailures.count == 1 {
                return base + String(localized: ", 1 metric warning", comment: "Suffix for a partial export with one metric warning")
            }
            if partialFailures.count > 1 {
                return base + String(localized: ", \(partialFailures.count) metric warnings", comment: "Suffix for a partial export with multiple metric warnings")
            }
            return base
        }
        if partialFailures.count == 1 {
            switch (generatedFileCountForDisplay == 1, totalCount == 1) {
            case (true, true):
                return String(localized: "Partial: 1 file from \(successCount) of 1 data day, 1 metric warning", comment: "Partial export summary with one file, one requested data day, and one warning")
            case (true, false):
                return String(localized: "Partial: 1 file from \(successCount) of \(totalCount) data days, 1 metric warning", comment: "Partial export summary with one file, requested data days, and one warning")
            case (false, true):
                return String(localized: "Partial: \(generatedFileCountForDisplay) files from \(successCount) of 1 data day, 1 metric warning", comment: "Partial export summary with multiple files, one requested data day, and one warning")
            case (false, false):
                return String(localized: "Partial: \(generatedFileCountForDisplay) files from \(successCount) of \(totalCount) data days, 1 metric warning", comment: "Partial export summary with multiple files, requested data days, and one warning")
            }
        }
        if partialFailures.count > 1 {
            switch (generatedFileCountForDisplay == 1, totalCount == 1) {
            case (true, true):
                return String(localized: "Partial: 1 file from \(successCount) of 1 data day, \(partialFailures.count) metric warnings", comment: "Partial export summary with one file, one requested data day, and multiple warnings")
            case (true, false):
                return String(localized: "Partial: 1 file from \(successCount) of \(totalCount) data days, \(partialFailures.count) metric warnings", comment: "Partial export summary with one file, requested data days, and multiple warnings")
            case (false, true):
                return String(localized: "Partial: \(generatedFileCountForDisplay) files from \(successCount) of 1 data day, \(partialFailures.count) metric warnings", comment: "Partial export summary with multiple files, one requested data day, and multiple warnings")
            case (false, false):
                return String(localized: "Partial: \(generatedFileCountForDisplay) files from \(successCount) of \(totalCount) data days, \(partialFailures.count) metric warnings", comment: "Partial export summary with multiple files, requested data days, and multiple warnings")
            }
        }
        switch (generatedFileCountForDisplay == 1, totalCount == 1) {
        case (true, true):
            return String(localized: "Partial: 1 file from \(successCount) of 1 data day", comment: "Partial export summary with one file and one requested data day")
        case (true, false):
            return String(localized: "Partial: 1 file from \(successCount) of \(totalCount) data days", comment: "Partial export summary with one file and requested data days")
        case (false, true):
            return String(localized: "Partial: \(generatedFileCountForDisplay) files from \(successCount) of 1 data day", comment: "Partial export summary with multiple files and one requested data day")
        case (false, false):
            return String(localized: "Partial: \(generatedFileCountForDisplay) files from \(successCount) of \(totalCount) data days", comment: "Partial export summary with multiple files and requested data days")
        }
    }

    private var failureSummaryDescription: String {
        switch failureReasonForDisplay ?? .unknown {
        case .noVaultSelected:
            return String(localized: "Export failed: No vault selected", comment: "Export failure summary when no vault is selected")
        case .accessDenied:
            return String(localized: "Export failed: Vault access denied", comment: "Export failure summary when vault access is denied")
        case .noHealthData:
            return String(localized: "Export failed: No health data", comment: "Export failure summary when no health data is available")
        case .healthKitError:
            return String(localized: "Export failed: HealthKit error", comment: "Export failure summary for a HealthKit error")
        case .deviceLocked:
            return String(localized: "Export failed: Device locked", comment: "Export failure summary when the device is locked")
        case .fileWriteError:
            return String(localized: "Export failed: File write failed", comment: "Export failure summary for a file write error")
        case .backgroundTaskExpired:
            return String(localized: "Export failed: Task timed out", comment: "Export failure summary when a background task expires")
        case .unknown:
            return String(localized: "Export failed: Unknown error", comment: "Export failure summary for an unknown error")
        }
    }

}

/// The source of the export (manual, scheduled, Shortcut, or Mac-agent)
enum ExportSource: String, Codable {
    case manual = "Manual"
    case scheduled = "Scheduled"
    case shortcut = "Shortcut"
    case macAgent = "iPhone → Mac"

    var icon: String {
        switch self {
        case .manual: return "hand.tap.fill"
        case .scheduled: return "clock.fill"
        case .shortcut: return "wand.and.stars"
        case .macAgent: return "iphone"
        }
    }
}

/// Reasons why an export attempt failed
enum ExportFailureReason: String, Codable {
    case noVaultSelected = "no_vault"
    case accessDenied = "access_denied"
    case noHealthData = "no_health_data"
    case healthKitError = "healthkit_error"
    case deviceLocked = "device_locked"
    case fileWriteError = "file_write_error"
    case backgroundTaskExpired = "task_expired"
    case unknown = "unknown"

    var shortDescription: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "No vault selected", comment: "Short error: no vault folder selected")
        case .accessDenied:
            return String(localized: "Vault access denied", comment: "Short error: vault folder access denied")
        case .noHealthData:
            return String(localized: "No health data", comment: "Short error: no health data available")
        case .healthKitError:
            return String(localized: "HealthKit error", comment: "Short error: HealthKit error")
        case .deviceLocked:
            return String(localized: "Device locked", comment: "Short error: device is locked")
        case .fileWriteError:
            return String(localized: "File write failed", comment: "Short error: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "Task timed out", comment: "Short error: background task timed out")
        case .unknown:
            return String(localized: "Unknown error", comment: "Short error: unknown")
        }
    }

    var alertTitle: String {
        switch self {
        case .noHealthData:
            return String(localized: "No Health Data Found", comment: "Alert title for an empty Apple Health export selection")
        default:
            return String(localized: "Export Couldn’t Finish", comment: "Alert title for an export failure")
        }
    }

    var detailedDescription: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "No export folder was selected for this destination, so Health.md had nowhere to save the files.", comment: "Detailed error: no vault selected")
        case .accessDenied:
            return String(localized: "Health.md could not open the selected export folder. The Files, iCloud Drive, or network location may be offline, or the saved folder permission may have expired.", comment: "Detailed error: vault access denied")
        case .noHealthData:
            return String(localized: "Apple Health returned no records for the selected date range and data types. This is expected on a new or empty device, and can also happen when Health.md does not have read access to the selected data.", comment: "Detailed empty state: no health data")
        case .healthKitError:
            return String(localized: "Health.md could not read one or more requested data types from Apple Health.", comment: "Detailed error: HealthKit error")
        case .deviceLocked:
            return String(localized: "iOS protected your health data because the iPhone was locked when Health.md tried to read it.", comment: "Detailed error: device locked")
        case .fileWriteError:
            return String(localized: "Health.md reached the export destination but could not create or update one or more files.", comment: "Detailed error: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "iOS ended the background export before Health.md could finish writing all requested dates.", comment: "Detailed error: task expired")
        case .unknown:
            return String(localized: "Health.md encountered an unexpected error during export. Any system message captured at the time appears in the Technical details section.", comment: "Detailed error: unknown")
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "Choose an export folder in Health.md, then retry the export.", comment: "Recovery: no vault selected")
        case .accessDenied:
            return String(localized: "Open the folder in Files to confirm it is available. Then re-select the folder in Health.md and retry.", comment: "Recovery: vault access denied")
        case .noHealthData:
            return String(localized: "Try All Time or another date range. You can also open Apple Health and review Health.md under Profile → Apps and Services. If the device has no matching records, there is nothing to export yet.", comment: "Recovery: no health data")
        case .healthKitError:
            return String(localized: "Open the Health app and review Health.md under Profile → Apps and Services. Allow the needed data types, then retry.", comment: "Recovery: HealthKit error")
        case .deviceLocked:
            return String(localized: "Unlock your iPhone, open Health.md, and retry. Scheduled HealthKit reads cannot finish while the iPhone is locked.", comment: "Recovery: device locked")
        case .fileWriteError:
            return String(localized: "Check that the destination is online and has free space. Re-select the export folder to refresh access, then retry.", comment: "Recovery: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "Open Health.md and retry while the app is visible. If it happens again, export a smaller date range.", comment: "Recovery: task expired")
        case .unknown:
            return String(localized: "Review the Technical details section below, then retry. If it fails again, include that exact message in your bug report.", comment: "Recovery: unknown export error")
        }
    }
}

/// Details about why a specific date failed to export
struct FailedDateDetail: Codable {
    let date: Date
    let reason: ExportFailureReason
    let errorDetails: String?

    init(date: Date, reason: ExportFailureReason, errorDetails: String? = nil) {
        self.date = date
        self.reason = reason
        self.errorDetails = errorDetails
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Returns the detailed error message, including raw error details if available
    var detailedMessage: String {
        if let details = errorDetails, !details.isEmpty {
            return "\(reason.detailedDescription)\n\nDetails: \(details)"
        }
        return reason.detailedDescription
    }
}

// MARK: - Export History Manager

/// Manages persistent storage of export history
class ExportHistoryManager: ObservableObject {
    static let shared = ExportHistoryManager()

    private static let historyKey = "exportHistory"
    private static let maxHistoryEntries = 50

    @Published private(set) var history: [ExportHistoryEntry] = []

    private init() {
        loadHistory()
    }

    // MARK: - Public Methods

    /// Records a successful export attempt
    func recordSuccess(
        id: UUID = UUID(),
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        successCount: Int,
        totalCount: Int,
        failedDateDetails: [FailedDateDetail] = [],
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        outputBreakdown: ExportHistoryOutputBreakdown? = nil,
        pendingRecoveryDayCount: Int = 0,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        partialFailures: [ExportPartialFailure] = [],
        wasCancelled: Bool = false,
        hadTerminalFailure: Bool = false,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        let entry = ExportHistoryEntry(
            id: id,
            source: source,
            success: true,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: successCount,
            totalCount: totalCount,
            failedDateDetails: failedDateDetails,
            targetLabel: targetLabel,
            exportTarget: exportTarget,
            fileCount: fileCount,
            outputBreakdown: outputBreakdown,
            pendingRecoveryDayCount: pendingRecoveryDayCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            partialFailures: partialFailures,
            wasCancelled: wasCancelled,
            hadTerminalFailure: hadTerminalFailure,
            appleExportEnginePin: appleExportEnginePin,
            operationDetails: operationDetails
        )
        addEntry(entry)
    }

    /// Records a failed export attempt
    func recordFailure(
        id: UUID = UUID(),
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        reason: ExportFailureReason,
        successCount: Int = 0,
        totalCount: Int = 0,
        failedDateDetails: [FailedDateDetail] = [],
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        outputBreakdown: ExportHistoryOutputBreakdown? = nil,
        pendingRecoveryDayCount: Int = 0,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        partialFailures: [ExportPartialFailure] = [],
        wasCancelled: Bool = false,
        hadTerminalFailure: Bool = false,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        let entry = ExportHistoryEntry(
            id: id,
            source: source,
            success: false,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: successCount,
            totalCount: totalCount,
            failureReason: reason,
            failedDateDetails: failedDateDetails,
            targetLabel: targetLabel,
            exportTarget: exportTarget,
            fileCount: fileCount,
            outputBreakdown: outputBreakdown,
            pendingRecoveryDayCount: pendingRecoveryDayCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            partialFailures: partialFailures,
            wasCancelled: wasCancelled,
            hadTerminalFailure: hadTerminalFailure,
            appleExportEnginePin: appleExportEnginePin,
            operationDetails: operationDetails
        )
        addEntry(entry)
    }

    /// Clears all history
    func clearHistory() {
        history = []
        saveHistory()
    }

    // MARK: - Private Methods

    private func addEntry(_ entry: ExportHistoryEntry) {
        guard !history.contains(where: { $0.id == entry.id }) else { return }
        history.insert(entry, at: 0)

        // Trim history to max entries
        if history.count > Self.maxHistoryEntries {
            history = Array(history.prefix(Self.maxHistoryEntries))
        }

        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([ExportHistoryEntry].self, from: data) else {
            history = []
            return
        }
        history = decoded
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: Self.historyKey)
        }
    }
}
