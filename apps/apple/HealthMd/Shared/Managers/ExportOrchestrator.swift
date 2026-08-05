import Foundation

/// Complete, localized generated-file count text shared by live local and Connected Mac status.
/// A non-authoritative zero is unknown rather than an exact zero; API/CLI producers preserve their
/// explicit zero by marking their category accounting complete or supplying an authoritative total.
nonisolated enum GeneratedFileCountText {
    static func localizedDescription(count: Int, isAuthoritative: Bool) -> String {
        if isAuthoritative {
            return count == 1
                ? String(localized: "1 file", comment: "Exact singular generated-file count")
                : String(localized: "\(count) files", comment: "Exact generated-file count")
        }
        if count == 1 {
            return String(localized: "at least 1 file", comment: "Singular generated-file lower bound")
        }
        if count > 1 {
            return String(localized: "at least \(count) files", comment: "Generated-file lower bound")
        }
        return String(localized: "an unknown number of files", comment: "Unknown generated-file count")
    }

    /// Complete localized sentences for live status. Count fragments remain available for compact
    /// rows, but live iPhone, iPad, and Mac copy must not ask translators to embed one localized
    /// fragment inside another sentence.
    static func localizedSuccessfulExport(
        count: Int,
        isAuthoritative: Bool,
        destination: String? = nil
    ) -> String {
        if let destination {
            if isAuthoritative {
                return count == 1
                    ? String(localized: "Successfully exported 1 file to \(destination).", comment: "Successful generated-file export to a named destination, singular")
                    : String(localized: "Successfully exported \(count) files to \(destination).", comment: "Successful generated-file export to a named destination, plural or zero")
            }
            if count == 1 {
                return String(localized: "Successfully exported at least 1 file to \(destination).", comment: "Successful generated-file export to a named destination with a singular lower bound")
            }
            if count > 1 {
                return String(localized: "Successfully exported at least \(count) files to \(destination).", comment: "Successful generated-file export to a named destination with a lower bound")
            }
            return String(localized: "Successfully exported files to \(destination), but the generated-file count is unknown.", comment: "Successful generated-file export to a named destination with an unknown count")
        }

        if isAuthoritative {
            return count == 1
                ? String(localized: "Successfully exported 1 file.", comment: "Successful generated-file export, singular")
                : String(localized: "Successfully exported \(count) files.", comment: "Successful generated-file export, plural or zero")
        }
        if count == 1 {
            return String(localized: "Successfully exported at least 1 file.", comment: "Successful generated-file export with a singular lower bound")
        }
        if count > 1 {
            return String(localized: "Successfully exported at least \(count) files.", comment: "Successful generated-file export with a lower bound")
        }
        return String(localized: "The export succeeded, but the generated-file count is unknown.", comment: "Successful generated-file export with an unknown count")
    }

    static func localizedExported(
        count: Int,
        isAuthoritative: Bool,
        destination: String? = nil
    ) -> String {
        if let destination {
            if isAuthoritative {
                return count == 1
                    ? String(localized: "Exported 1 file to \(destination).", comment: "Generated-file export to a named destination, singular")
                    : String(localized: "Exported \(count) files to \(destination).", comment: "Generated-file export to a named destination, plural or zero")
            }
            if count == 1 {
                return String(localized: "Exported at least 1 file to \(destination).", comment: "Generated-file export to a named destination with a singular lower bound")
            }
            if count > 1 {
                return String(localized: "Exported at least \(count) files to \(destination).", comment: "Generated-file export to a named destination with a lower bound")
            }
            return String(localized: "Exported files to \(destination), but the generated-file count is unknown.", comment: "Generated-file export to a named destination with an unknown count")
        }

        if isAuthoritative {
            return count == 1
                ? String(localized: "Exported 1 file.", comment: "Generated-file export, singular")
                : String(localized: "Exported \(count) files.", comment: "Generated-file export, plural or zero")
        }
        if count == 1 {
            return String(localized: "Exported at least 1 file.", comment: "Generated-file export with a singular lower bound")
        }
        if count > 1 {
            return String(localized: "Exported at least \(count) files.", comment: "Generated-file export with a lower bound")
        }
        return String(localized: "Files were exported, but the generated-file count is unknown.", comment: "Generated-file export with an unknown count")
    }

    static func localizedStoppedExport(count: Int, isAuthoritative: Bool) -> String {
        if isAuthoritative {
            return count == 1
                ? String(localized: "Export stopped after exporting 1 file.", comment: "Stopped generated-file export, singular")
                : String(localized: "Export stopped after exporting \(count) files.", comment: "Stopped generated-file export, plural or zero")
        }
        if count == 1 {
            return String(localized: "Export stopped after exporting at least 1 file.", comment: "Stopped generated-file export with a singular lower bound")
        }
        if count > 1 {
            return String(localized: "Export stopped after exporting at least \(count) files.", comment: "Stopped generated-file export with a lower bound")
        }
        return String(localized: "Export stopped after writing files, but the generated-file count is unknown.", comment: "Stopped generated-file export with an unknown count")
    }

    static func localizedFailedExport(
        count: Int,
        isAuthoritative: Bool,
        destination: String
    ) -> String {
        if isAuthoritative {
            return count == 1
                ? String(localized: "The export to \(destination) failed after exporting 1 file.", comment: "Failed generated-file export to a named destination, singular")
                : String(localized: "The export to \(destination) failed after exporting \(count) files.", comment: "Failed generated-file export to a named destination, plural or zero")
        }
        if count == 1 {
            return String(localized: "The export to \(destination) failed after exporting at least 1 file.", comment: "Failed generated-file export to a named destination with a singular lower bound")
        }
        if count > 1 {
            return String(localized: "The export to \(destination) failed after exporting at least \(count) files.", comment: "Failed generated-file export to a named destination with a lower bound")
        }
        return String(localized: "The export to \(destination) failed after writing files, but the generated-file count is unknown.", comment: "Failed generated-file export to a named destination with an unknown count")
    }

    static func localizedDataDayProgress(successfulCount: Int, totalCount: Int) -> String {
        totalCount == 1
            ? String(localized: "\(successfulCount) of 1 data day completed.", comment: "Live export data-day progress when one day was requested")
            : String(localized: "\(successfulCount) of \(totalCount) data days completed.", comment: "Live export data-day progress when multiple days were requested")
    }

    static func localizedCompletedStatus(
        count: Int,
        isAuthoritative: Bool,
        successfulDataDayCount: Int,
        totalDataDayCount: Int
    ) -> String {
        localizedSuccessfulExport(count: count, isAuthoritative: isAuthoritative)
            + " "
            + localizedDataDayProgress(
                successfulCount: successfulDataDayCount,
                totalCount: totalDataDayCount
            )
    }

    static func localizedPartialStatus(
        count: Int,
        isAuthoritative: Bool,
        successfulDataDayCount: Int,
        totalDataDayCount: Int
    ) -> String {
        localizedExported(count: count, isAuthoritative: isAuthoritative)
            + " "
            + localizedDataDayProgress(
                successfulCount: successfulDataDayCount,
                totalCount: totalDataDayCount
            )
    }

    static func localizedStoppedStatus(
        count: Int,
        isAuthoritative: Bool,
        successfulDataDayCount: Int,
        totalDataDayCount: Int
    ) -> String {
        localizedStoppedExport(count: count, isAuthoritative: isAuthoritative)
            + " "
            + localizedDataDayProgress(
                successfulCount: successfulDataDayCount,
                totalCount: totalDataDayCount
            )
    }

    static func localizedDailyNotesUpdated(
        count: Int,
        destination: String? = nil
    ) -> String {
        if let destination {
            return count == 1
                ? String(localized: "Updated 1 daily note on \(destination).", comment: "One daily note updated on a named destination")
                : String(localized: "Updated \(count) daily notes on \(destination).", comment: "Daily notes updated on a named destination, plural or zero")
        }
        return count == 1
            ? String(localized: "Updated 1 daily note.", comment: "One daily note updated")
            : String(localized: "Updated \(count) daily notes.", comment: "Daily notes updated, plural or zero")
    }

    static func localizedPartialDailyNoteUpdate(
        updatedCount: Int,
        totalCount: Int,
        destination: String? = nil
    ) -> String {
        if let destination {
            return totalCount == 1
                ? String(localized: "Updated \(updatedCount) of 1 daily note on \(destination).", comment: "Partial daily-note update on a named destination when one note was requested")
                : String(localized: "Updated \(updatedCount) of \(totalCount) daily notes on \(destination).", comment: "Partial daily-note update on a named destination")
        }
        return totalCount == 1
            ? String(localized: "Updated \(updatedCount) of 1 daily note.", comment: "Partial daily-note update when one note was requested")
            : String(localized: "Updated \(updatedCount) of \(totalCount) daily notes.", comment: "Partial daily-note update")
    }

    static var localizedTerminalFailure: String {
        String(
            localized: "The export did not finish successfully after writing confirmed output.",
            comment: "Export terminal failure after confirmed output"
        )
    }

    static var localizedIncompleteDataDays: String {
        String(
            localized: "Some data days did not complete.",
            comment: "Partial export without explicit failed-date details"
        )
    }

    static func localizedFailedDates(_ dates: String) -> String {
        String(localized: "Failed dates: \(dates).", comment: "Partial export failed-date summary")
    }

    static func localizedBreakdown(_ breakdown: String) -> String {
        String(localized: "Generated files: \(breakdown).", comment: "Live export generated-file category breakdown")
    }

    static func localizedMacWrite(count: Int, isAuthoritative: Bool) -> String {
        if isAuthoritative {
            return count == 1
                ? String(localized: "Mac export wrote 1 file.", comment: "Mac activity generated-file count, singular")
                : String(localized: "Mac export wrote \(count) files.", comment: "Mac activity generated-file count, plural or zero")
        }
        if count == 1 {
            return String(localized: "Mac export wrote at least 1 file.", comment: "Mac activity generated-file count with a singular lower bound")
        }
        if count > 1 {
            return String(localized: "Mac export wrote at least \(count) files.", comment: "Mac activity generated-file count with a lower bound")
        }
        return String(localized: "Mac export wrote files, but the generated-file count is unknown.", comment: "Mac activity generated-file count when unknown")
    }

    static func localizedPartialCompact(count: Int, isAuthoritative: Bool) -> String {
        if isAuthoritative {
            return count == 1
                ? String(localized: "Partial: 1 file", comment: "Compact partial Connected Mac result, singular")
                : String(localized: "Partial: \(count) files", comment: "Compact partial Connected Mac result, plural or zero")
        }
        if count == 1 {
            return String(localized: "Partial: at least 1 file", comment: "Compact partial Connected Mac result with a singular lower bound")
        }
        if count > 1 {
            return String(localized: "Partial: at least \(count) files", comment: "Compact partial Connected Mac result with a lower bound")
        }
        return String(localized: "Partial: file count unknown", comment: "Compact partial Connected Mac result with an unknown count")
    }
}

@MainActor
final class LocalArchiveSpool {
    private let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "healthmd-local-archive-\(UUID().uuidString)",
        isDirectory: true
    )
    private var nextIndex = 0
    private(set) var files: [RenderedHealthDataArchiveEntryFile] = []

    func append(
        _ healthData: HealthData,
        settings: AdvancedExportSettings,
        preparedExport suppliedPreparedExport: PreparedHealthDataExport? = nil
    ) async throws {
        if nextIndex == 0 {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let preparedExport = suppliedPreparedExport
            ?? healthData.preparedExport(settings: settings)
        var stagedFiles: [RenderedHealthDataArchiveEntryFile] = []
        do {
            for (offset, format) in settings.exportFormats
                .sorted(by: { $0.rawValue < $1.rawValue })
                .enumerated() {
                try Task.checkCancellation()
                let artifact = try preparedExport.renderArtifact(
                    format: format,
                    in: directoryURL
                )
                // LocalArchiveSpool owns the enclosing private directory until
                // ZIP finalization, so transfer cleanup from the temporary lease.
                artifact.lease.relinquishCleanupOwnership()
                let order = nextIndex + offset
                let fileURL = artifact.url
                stagedFiles.append(RenderedHealthDataArchiveEntryFile(
                    date: healthData.date,
                    archivePath: Self.archiveEntryPath(
                        for: healthData.date,
                        format: format,
                        settings: settings
                    ),
                    order: order,
                    url: fileURL
                ))
                await Task.yield()
            }
        } catch {
            for file in stagedFiles { try? FileManager.default.removeItem(at: file.url) }
            throw error
        }
        files.append(contentsOf: stagedFiles)
        nextIndex += stagedFiles.count
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
        files.removeAll(keepingCapacity: false)
    }

    private static func archiveEntryPath(
        for date: Date,
        format: ExportFormat,
        settings: AdvancedExportSettings
    ) -> String {
        var components: [String] = []
        if let folderPath = settings.formatFolderPath(for: date, format: format) {
            components.append(folderPath)
        }
        components.append(settings.filename(for: date, format: format))
        return components.joined(separator: "/")
    }

}

/// Shared export orchestration logic used by both iOS and macOS.
/// Eliminates duplication between manual export (ContentView), scheduled export
/// (SchedulingManager), and future macOS export triggers.
@MainActor
struct ExportOrchestrator {

    // MARK: - Result Type

    struct ExportResult {
        let successCount: Int
        let totalCount: Int
        /// Exact requested dates whose outcome is terminal for this run. `nil`
        /// means a legacy/aggregate-only producer could not identify them.
        let completedDates: [Date]?
        /// Aggregate completion retained for legacy result producers and tests.
        /// When `completedDates` is present, this is always its unique day count.
        let completedDateCount: Int
        let failedDateDetails: [FailedDateDetail]
        let partialFailures: [ExportPartialFailure]
        let wasCancelled: Bool
        /// A producer reached a non-success terminal state other than cancellation. This remains
        /// distinct from confirmed output and prevents all committed data days from masquerading
        /// as full success when a final roll-up, archive, or remote finalizer fails.
        let hadTerminalFailure: Bool
        /// Number of loose formats configured per successful date.
        let formatsPerDate: Int
        /// Exact number of loose aggregate files written across successful dates.
        let looseAggregateFileCount: Int
        /// Exact number of Individual Entry Tracking files written across successful dates.
        let individualEntryFileCount: Int
        /// Exact number of `_healthmd_data_dictionary.json` files written.
        let dataDictionaryFileCount: Int
        /// Number of derived roll-up summary files written after successful daily exports.
        let rollupFileCount: Int
        /// Number of ZIP archives written for packaged exports.
        let archiveCount: Int
        /// Number of third-party provider sidecar JSON files written to a filesystem destination.
        let externalRecordFileCount: Int
        /// Provider records embedded in an API payload. These are not generated files.
        let externalRecordPayloadCount: Int
        /// Confirmed generated files whose category was not available. This remains a lower
        /// bound unless `authoritativeFileCount` is non-nil.
        let unclassifiedFileCount: Int
        /// Authoritative total from a producer that cannot classify every generated file.
        let authoritativeFileCount: Int?
        /// True only when every physical generated-file category was measured by the writer.
        let isFileCategoryBreakdownComplete: Bool
        /// Existing or newly created daily notes successfully updated.
        let dailyNoteUpdateCount: Int
        /// Daily-note-only targets intentionally skipped (for example, missing
        /// notes while Create Note If Missing is off).
        let dailyNoteSkipCount: Int

        init(
            successCount: Int,
            totalCount: Int,
            failedDateDetails: [FailedDateDetail],
            partialFailures: [ExportPartialFailure] = [],
            formatsPerDate: Int = 1,
            looseAggregateFileCount: Int = 0,
            individualEntryFileCount: Int = 0,
            dataDictionaryFileCount: Int = 0,
            rollupFileCount: Int = 0,
            archiveCount: Int = 0,
            externalRecordFileCount: Int = 0,
            externalRecordPayloadCount: Int = 0,
            unclassifiedFileCount: Int = 0,
            authoritativeFileCount: Int? = nil,
            isFileCategoryBreakdownComplete: Bool = false,
            dailyNoteUpdateCount: Int = 0,
            dailyNoteSkipCount: Int = 0,
            wasCancelled: Bool = false,
            hadTerminalFailure: Bool = false,
            completedDates: [Date]? = nil,
            completedDateCount: Int? = nil
        ) {
            self.successCount = successCount
            self.totalCount = totalCount
            if let completedDates {
                self.completedDates = Array(Set(completedDates)).sorted()
                self.completedDateCount = self.completedDates?.count ?? 0
            } else {
                self.completedDates = nil
                self.completedDateCount = completedDateCount ?? successCount
            }
            self.failedDateDetails = failedDateDetails
            self.partialFailures = partialFailures
            self.formatsPerDate = ExportHistoryOutputBreakdown.boundedCount(formatsPerDate)
            let normalizedBreakdown = ExportHistoryOutputBreakdown(
                requestedDataDayCount: totalCount,
                successfulDataDayCount: successCount,
                looseAggregateFileCount: looseAggregateFileCount,
                individualEntryFileCount: individualEntryFileCount,
                dataDictionaryFileCount: dataDictionaryFileCount,
                zipArchiveFileCount: archiveCount,
                rollupFileCount: rollupFileCount,
                providerSidecarFileCount: externalRecordFileCount,
                dailyNoteUpdateCount: dailyNoteUpdateCount,
                dailyNoteSkipCount: dailyNoteSkipCount,
                unclassifiedFileCount: unclassifiedFileCount,
                isFileCategoryBreakdownComplete: isFileCategoryBreakdownComplete
            )
            self.looseAggregateFileCount = normalizedBreakdown.looseAggregateFileCount
            self.individualEntryFileCount = normalizedBreakdown.individualEntryFileCount
            self.dataDictionaryFileCount = normalizedBreakdown.dataDictionaryFileCount
            self.rollupFileCount = normalizedBreakdown.rollupFileCount
            self.archiveCount = normalizedBreakdown.zipArchiveFileCount
            self.externalRecordFileCount = normalizedBreakdown.providerSidecarFileCount
            self.externalRecordPayloadCount = ExportHistoryOutputBreakdown.boundedCount(
                externalRecordPayloadCount
            )
            self.unclassifiedFileCount = normalizedBreakdown.unclassifiedFileCount
            let normalizedAuthoritativeFileCount = authoritativeFileCount.map(
                ExportHistoryOutputBreakdown.boundedCount
            )
            self.authoritativeFileCount = normalizedAuthoritativeFileCount
            self.isFileCategoryBreakdownComplete = normalizedBreakdown.isFileCategoryBreakdownComplete
                && (normalizedAuthoritativeFileCount.map {
                    $0 == normalizedBreakdown.generatedFileCount
                } ?? true)
            self.dailyNoteUpdateCount = normalizedBreakdown.dailyNoteUpdateCount
            self.dailyNoteSkipCount = normalizedBreakdown.dailyNoteSkipCount
            self.wasCancelled = wasCancelled
            self.hadTerminalFailure = hadTerminalFailure
        }

        /// Builds a conservative history result from the connected-Mac payload. Older peers keep
        /// their aggregate total authoritative; interrupted current writers can explicitly mark
        /// that total as a lower bound while retaining every confirmed category.
        init(macExportPayload payload: MacExportResultPayload) {
            let breakdown = payload.outputBreakdown
            let measuredGeneratedFiles = breakdown?.generatedFileCount
                ?? payload.externalRecordFileCount
            let inferredUnclassifiedLowerBound = max(
                payload.totalFilesWritten - measuredGeneratedFiles,
                0
            )
            self.init(
                successCount: payload.successCount,
                totalCount: payload.totalCount,
                failedDateDetails: payload.failedDateDetails,
                formatsPerDate: payload.formatsPerDate,
                looseAggregateFileCount: breakdown?.looseAggregateFileCount ?? 0,
                individualEntryFileCount: breakdown?.individualEntryFileCount ?? 0,
                dataDictionaryFileCount: breakdown?.dataDictionaryFileCount ?? 0,
                rollupFileCount: breakdown?.rollupFileCount ?? 0,
                archiveCount: breakdown?.zipArchiveFileCount ?? 0,
                externalRecordFileCount: breakdown?.providerSidecarFileCount
                    ?? payload.externalRecordFileCount,
                unclassifiedFileCount: (breakdown?.unclassifiedFileCount ?? 0)
                    + inferredUnclassifiedLowerBound,
                authoritativeFileCount: payload.isTotalFilesWrittenAuthoritative
                    ? payload.totalFilesWritten
                    : nil,
                isFileCategoryBreakdownComplete: breakdown?.isFileCategoryBreakdownComplete
                    ?? false,
                dailyNoteUpdateCount: payload.dailyNoteUpdateCount,
                dailyNoteSkipCount: payload.dailyNoteSkipCount,
                wasCancelled: payload.status == .cancelled,
                hadTerminalFailure: payload.hadTerminalFailure,
                completedDates: payload.completedDates
            )
        }

        init(
            macExportFailure failure: MacExportFailure,
            totalCount: Int,
            formatsPerDate: Int,
            failedDateDetails: [FailedDateDetail]
        ) {
            let breakdown = failure.outputBreakdown
            let inferredUnclassifiedCount = max(
                (failure.totalFilesWritten ?? 0) - (breakdown?.generatedFileCount ?? 0),
                0
            )
            self.init(
                successCount: breakdown?.successfulDataDayCount ?? 0,
                totalCount: totalCount,
                failedDateDetails: failedDateDetails,
                formatsPerDate: formatsPerDate,
                looseAggregateFileCount: breakdown?.looseAggregateFileCount ?? 0,
                individualEntryFileCount: breakdown?.individualEntryFileCount ?? 0,
                dataDictionaryFileCount: breakdown?.dataDictionaryFileCount ?? 0,
                rollupFileCount: breakdown?.rollupFileCount ?? 0,
                archiveCount: breakdown?.zipArchiveFileCount ?? 0,
                externalRecordFileCount: breakdown?.providerSidecarFileCount ?? 0,
                unclassifiedFileCount: (breakdown?.unclassifiedFileCount ?? 0)
                    + inferredUnclassifiedCount,
                authoritativeFileCount: failure.totalFilesWritten,
                isFileCategoryBreakdownComplete: breakdown?.isFileCategoryBreakdownComplete
                    ?? false,
                dailyNoteUpdateCount: breakdown?.dailyNoteUpdateCount ?? 0,
                dailyNoteSkipCount: breakdown?.dailyNoteSkipCount ?? 0,
                wasCancelled: failure.reason == .cancelled,
                hadTerminalFailure: failure.reason != .cancelled
            )
        }

        var hasPartialFailures: Bool { !partialFailures.isEmpty }
        var partialFailureSummary: String {
            guard let first = partialFailures.first else { return "" }
            if partialFailures.count == 1 {
                return "Warning: \(first.summary)"
            }
            return "Warning: \(partialFailures.count) export warnings, including \(first.summary)"
        }
        /// Whether every requested date completed, even if retained records include
        /// non-fatal partial-capture warnings.
        var didCompleteAllRequestedDates: Bool {
            completedDateCount == totalCount
                && totalCount > 0
                && !wasCancelled
                && !hadTerminalFailure
        }

        /// Returns the exact unresolved subset when the producer supplied
        /// per-date completion. Legacy aggregate-only or terminal derived-output failures return
        /// nil so callers conservatively preserve the original request. A derived output belongs
        /// to the range, not one date, so successful daily commits cannot prove it is resolved.
        func remainingDates(
            from requestedDates: [Date],
            calendar: Calendar = .current
        ) -> [Date]? {
            guard !hadTerminalFailure, let completedDates else { return nil }
            let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })
            return requestedDates
                .map { calendar.startOfDay(for: $0) }
                .filter { !completedDays.contains($0) }
        }
        var isFullSuccess: Bool {
            successCount == totalCount
                && didCompleteAllRequestedDates
                && failedDateDetails.isEmpty
                && !hasPartialFailures
                && !hadTerminalFailure
        }
        var isPartialSuccess: Bool {
            let hasConfirmedSuccess = successCount > 0 || dailyNoteSkipCount > 0
            return hasConfirmedSuccess && (
                successCount < totalCount
                    || wasCancelled
                    || hadTerminalFailure
                    || !failedDateDetails.isEmpty
                    || hasPartialFailures
            )
        }
        var isFailure: Bool {
            successCount == 0 && dailyNoteSkipCount == 0 && totalCount > 0
        }
        var primaryFailureReason: ExportFailureReason? { failedDateDetails.first?.reason }
        /// Sum of file categories that this producer measured directly.
        var categorizedFileCount: Int {
            [
                looseAggregateFileCount,
                individualEntryFileCount,
                dataDictionaryFileCount,
                rollupFileCount,
                archiveCount,
                externalRecordFileCount
            ].reduce(0) { partial, count in
                let addition = partial.addingReportingOverflow(count)
                return addition.overflow ? Int.max : addition.partialValue
            }
        }

        var knownFileCount: Int {
            let addition = categorizedFileCount.addingReportingOverflow(unclassifiedFileCount)
            return addition.overflow ? Int.max : addition.partialValue
        }

        /// Authoritative physical generated-file total when available, otherwise the confirmed
        /// lower bound. Daily-note updates and provider payload records are tracked separately.
        var totalFilesWritten: Int {
            authoritativeFileCount ?? knownFileCount
        }

        var hasAuthoritativeFileCount: Bool {
            authoritativeFileCount != nil || isFileCategoryBreakdownComplete
        }

        var generatedFileCountDescription: String {
            GeneratedFileCountText.localizedDescription(
                count: totalFilesWritten,
                isAuthoritative: hasAuthoritativeFileCount
            )
        }

        var outputBreakdown: ExportHistoryOutputBreakdown {
            outputBreakdown(resolvedFileCount: totalFilesWritten)
        }

        /// Reconciles producers that supply an authoritative total without a complete category
        /// payload. Known exact categories are retained only when they fit that total.
        func outputBreakdown(resolvedFileCount: Int) -> ExportHistoryOutputBreakdown {
            let resolvedFileCount = ExportHistoryOutputBreakdown.boundedCount(resolvedFileCount)
            let measuredBreakdown = ExportHistoryOutputBreakdown(
                requestedDataDayCount: totalCount,
                successfulDataDayCount: successCount,
                looseAggregateFileCount: looseAggregateFileCount,
                individualEntryFileCount: individualEntryFileCount,
                dataDictionaryFileCount: dataDictionaryFileCount,
                zipArchiveFileCount: archiveCount,
                rollupFileCount: rollupFileCount,
                providerSidecarFileCount: externalRecordFileCount,
                dailyNoteUpdateCount: dailyNoteUpdateCount,
                dailyNoteSkipCount: dailyNoteSkipCount,
                unclassifiedFileCount: unclassifiedFileCount,
                isFileCategoryBreakdownComplete: isFileCategoryBreakdownComplete
            )
            return measuredBreakdown.reconciled(toAuthoritativeFileCount: resolvedFileCount)
        }

        var fileBreakdownDescription: String {
            let breakdown = outputBreakdown
            let hasCompleteBreakdown = breakdown.isFileCategoryBreakdownComplete
            var parts: [String] = []
            if looseAggregateFileCount == 0 {
                if hasCompleteBreakdown {
                    parts.append(String(localized: "No loose aggregate files", comment: "Export result breakdown with no loose aggregate output"))
                }
            } else {
                let expectedLooseCount = successCount.multipliedReportingOverflow(by: formatsPerDate)
                if hasCompleteBreakdown,
                   formatsPerDate > 1,
                   !expectedLooseCount.overflow,
                   looseAggregateFileCount == expectedLooseCount.partialValue {
                    parts.append(successCount == 1
                        ? String(localized: "1 data day × \(formatsPerDate) loose formats", comment: "Exact loose export matrix for one data day")
                        : String(localized: "\(successCount) data days × \(formatsPerDate) loose formats", comment: "Exact loose export matrix for multiple data days"))
                } else {
                    parts.append(looseAggregateFileCount == 1
                        ? String(localized: "1 loose aggregate file", comment: "Loose aggregate file count when singular")
                        : String(localized: "\(looseAggregateFileCount) loose aggregate files", comment: "Loose aggregate file count when plural"))
                }
            }
            if individualEntryFileCount == 1 {
                parts.append(String(localized: "1 individual-entry file", comment: "Individual-entry file count when singular"))
            } else if individualEntryFileCount > 1 {
                parts.append(String(localized: "\(individualEntryFileCount) individual-entry files", comment: "Individual-entry file count when plural"))
            }
            if dataDictionaryFileCount == 1 {
                parts.append(String(localized: "1 data dictionary", comment: "Data dictionary file count when singular"))
            } else if dataDictionaryFileCount > 1 {
                parts.append(String(localized: "\(dataDictionaryFileCount) data dictionaries", comment: "Data dictionary file count when plural"))
            }
            if archiveCount == 1 {
                parts.append(String(localized: "1 ZIP archive", comment: "ZIP archive count when singular"))
            } else if archiveCount > 1 {
                parts.append(String(localized: "\(archiveCount) ZIP archives", comment: "ZIP archive count when plural"))
            }
            if rollupFileCount == 1 {
                parts.append(String(localized: "1 roll-up summary", comment: "Roll-up summary file count when singular"))
            } else if rollupFileCount > 1 {
                parts.append(String(localized: "\(rollupFileCount) roll-up summaries", comment: "Roll-up summary file count when plural"))
            }
            if externalRecordFileCount == 1 {
                parts.append(String(localized: "1 provider sidecar", comment: "Provider sidecar file count when singular"))
            } else if externalRecordFileCount > 1 {
                parts.append(String(localized: "\(externalRecordFileCount) provider sidecars", comment: "Provider sidecar file count when plural"))
            }
            if breakdown.unclassifiedFileCount == 1 {
                parts.append(String(localized: "1 unclassified file", comment: "Unclassified generated-file count when singular"))
            } else if breakdown.unclassifiedFileCount > 1 {
                parts.append(String(localized: "\(breakdown.unclassifiedFileCount) unclassified files", comment: "Unclassified generated-file count when plural"))
            }
            if dailyNoteUpdateCount == 1 {
                parts.append(String(localized: "1 daily note updated", comment: "Daily-note update count when singular"))
            } else if dailyNoteUpdateCount > 1 {
                parts.append(String(localized: "\(dailyNoteUpdateCount) daily notes updated", comment: "Daily-note update count when plural"))
            }
            if parts.isEmpty {
                parts.append(hasCompleteBreakdown
                    ? String(localized: "No generated files", comment: "Export result with a complete zero-file breakdown")
                    : String(localized: "File categories unavailable", comment: "Export result whose producer did not classify generated files"))
            }
            return parts.joined(separator: " + ")
        }
    }

    // MARK: - Date Range Helper

    /// Builds an array of calendar days from startDate through endDate (inclusive).
    static func dateRange(from startDate: Date, to endDate: Date) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    /// Expands the user's selected dates to the full roll-up period windows they
    /// intersect. For example, selecting one day with monthly roll-ups enabled
    /// produces every day in that month, so the summary reflects the selected
    /// roll-up window instead of only the daily export range.
    static func rollupSourceDates(
        for selectedDates: [Date],
        settings: AdvancedExportSettings,
        calendar: Calendar = .current,
        latestAllowedDate: Date = Date()
    ) -> [Date] {
        rollupSourceDates(
            for: selectedDates,
            periods: settings.enabledRollupPeriods,
            calendar: calendar,
            latestAllowedDate: latestAllowedDate
        )
    }

    static func rollupSourceDates(
        for selectedDates: [Date],
        periods: [HealthRollupPeriod],
        calendar: Calendar = .current,
        latestAllowedDate: Date = Date()
    ) -> [Date] {
        guard !selectedDates.isEmpty, !periods.isEmpty else { return [] }

        let latestAllowedDay = calendar.startOfDay(for: latestAllowedDate)
        var expandedDates = Set<Date>()

        for selectedDate in selectedDates {
            for period in periods {
                let window = HealthRollupPeriodWindow.window(
                    containing: calendar.startOfDay(for: selectedDate),
                    period: period,
                    calendar: calendar
                )
                let start = calendar.startOfDay(for: window.startDate)
                let periodEnd = calendar.startOfDay(for: window.endDate)
                let end = min(periodEnd, latestAllowedDay)
                guard start <= end else { continue }

                var current = start
                while current <= end {
                    expandedDates.insert(calendar.startOfDay(for: current))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                        break
                    }
                    current = next
                }
            }
        }

        return expandedDates.sorted()
    }

    // MARK: - Foreground Export (security-scoped)

    /// Export health data for a list of dates.
    /// Each date manages its own security-scoped access via VaultManager's async method.
    /// Suitable for manual/foreground exports.
    static func exportDates(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        await HealthKitQueryExecutionController.withController {
            await exportDatesWithQueryController(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings,
                externalIntegrations: externalIntegrations,
                onProgress: onProgress
            )
        }
    }

    private static func exportDatesWithQueryController(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?,
        onProgress: ((Int, Int, String) -> Void)?
    ) async -> ExportResult {
        let awakeActivityID = UUID()
        IdleTimerCoordinator.shared.beginActivity(awakeActivityID)
        defer { IdleTimerCoordinator.shared.endActivity(awakeActivityID) }

        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "local-files",
                phase: "foreground-export",
                timer: performanceTimer,
                itemCount: dates.count
            )
        }
        #endif
        externalIntegrations?.beginExportAction()
        defer { externalIntegrations?.endExportAction() }
        vaultManager.clearLastExportPresentationTarget()

        let totalDays = dates.count
        let formatsPerDate = looseFormatsPerDate(settings: settings)
        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var successfulHealthData: [HealthData] = []
        var looseAggregateFileCount = 0
        var individualEntryFileCount = 0
        var dataDictionaryFileCount = 0
        var externalRecordFileCount = 0
        var isFileAccountingComplete = true
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var shouldWriteDataDictionary = true
        let hasProviderSideEffects = ConnectedAppsFeature.isEnabled
            && (externalIntegrations?.connectedProviderCount ?? 0) > 0
        let shouldWriteExternalRecords = settings.writesExternalProviderSidecars
            && hasProviderSideEffects
        let operationSurface: AppleExportOperationSurface = hasProviderSideEffects
            ? .legacyOnly
            : .localVaultRangeWithoutSideEffects
        let sourceTimeZone = settings.exportTimeZoneOverride ?? .current
        // Foreground ranges freeze renderer authority and calendar ownership once before the first
        // HealthKit read. Per-day planning must never inherit a flag or timezone changed mid-run.
        let operationSettingsSnapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: vaultManager.healthSubfolder,
            calendarTimeZone: sourceTimeZone,
            surface: operationSurface,
            hasNativeOnlyCompanionAction: hasProviderSideEffects
        )
        let frozenOperationSettings = operationSettingsSnapshot.makeAdvancedExportSettings()
        frozenOperationSettings.exportTimeZoneOverride = sourceTimeZone
        do {
            try vaultManager.preflightDataDictionaryArtifactCollisions(
                settings: frozenOperationSettings,
                healthSubfolder: operationSettingsSnapshot.healthSubfolder,
                dates: dates
            )
        } catch {
            return ExportResult(
                successCount: 0,
                totalCount: totalDays,
                failedDateDetails: dates.map {
                    FailedDateDetail(
                        date: $0,
                        reason: .fileWriteError,
                        errorDetails: error.localizedDescription
                    )
                },
                formatsPerDate: formatsPerDate,
                isFileCategoryBreakdownComplete: true,
                completedDates: []
            )
        }
        let archiveSpool = settings.archiveModeEnabled ? LocalArchiveSpool() : nil
        defer { archiveSpool?.cleanup() }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if operationSettingsSnapshot.appleExportEnginePin != nil {
            return await exportForegroundPinnedSimpleRange(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settingsSnapshot: operationSettingsSnapshot,
                operationSurface: operationSurface,
                sourceTimeZone: sourceTimeZone,
                onProgress: onProgress
            )
        }

        if settings.summaryOnlyModeEnabled {
            return await exportSummaryOnlyDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings,
                onProgress: onProgress
            )
        }

        for (index, date) in dates.enumerated() {
            // Check for cancellation before each date
            if Task.isCancelled {
                return ExportResult(
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    looseAggregateFileCount: looseAggregateFileCount,
                    individualEntryFileCount: individualEntryFileCount,
                    dataDictionaryFileCount: dataDictionaryFileCount,
                    externalRecordFileCount: externalRecordFileCount,
                    isFileCategoryBreakdownComplete: isFileAccountingComplete,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            }

            let dateString = dateFormatter.string(from: date)
            onProgress?(index, totalDays, dateString)

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: frozenOperationSettings.effectiveGranularDataEnabled,
                    metricSelection: frozenOperationSettings.metricSelection,
                    timeZone: sourceTimeZone
                )
                partialFailures.append(contentsOf: healthData.partialFailures)
                // HealthKitManager has already applied the frozen selection. Reuse
                // one snapshot for loose-file and ZIP staging renders instead of
                // filtering a potentially dense archive for each destination.
                let preparedExport = healthData.preparedExportAssumingSelectionApplied(
                    settings: frozenOperationSettings
                )
                let externalRecordPlan: VaultManager.ExternalDailyRecordWritePlan?
                if shouldWriteExternalRecords, let externalIntegrations {
                    let externalRecords = await externalIntegrations.fetchDailyRecords(for: date)
                    externalRecordPlan = try vaultManager.planExternalDailyRecordDestinations(
                        externalRecords,
                        healthSubfolder: operationSettingsSnapshot.healthSubfolder
                    )
                } else {
                    externalRecordPlan = nil
                }
                let writeResult = try await vaultManager.exportHealthData(
                    healthData,
                    settings: settings,
                    writeDataDictionary: shouldWriteDataDictionary,
                    additionalArtifactRelativePaths: externalRecordPlan?.artifactRelativePaths ?? [],
                    operationSurface: operationSurface,
                    frozenSettingsSnapshot: operationSettingsSnapshot,
                    preparedExport: preparedExport
                )
                if !settings.archiveModeEnabled && !settings.dailyNotesOnlyModeEnabled {
                    shouldWriteDataDictionary = false
                }
                looseAggregateFileCount += writeResult.aggregateFileCount
                individualEntryFileCount += writeResult.individualEntryFileCount
                dataDictionaryFileCount += writeResult.dataDictionaryFileCount
                dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                dailyNoteSkipCount += writeResult.dailyNoteSkippedCount

                if settings.dailyNotesOnlyModeEnabled {
                    switch writeResult.dailyNoteResult {
                    case .updated:
                        break
                    case .skipped(let reason):
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .noHealthData,
                            errorDetails: reason
                        ))
                        completedDates.append(date)
                        continue
                    case .failed(let error):
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .fileWriteError,
                            errorDetails: error.localizedDescription
                        ))
                        continue
                    case .none:
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .fileWriteError,
                            errorDetails: "Daily note update was not performed."
                        ))
                        continue
                    }
                }

                if let externalRecordPlan {
                    do {
                        externalRecordFileCount += try await vaultManager.exportExternalDailyRecords(
                            externalRecordPlan
                        )
                    } catch let error as ExportPartialWriteError {
                        externalRecordFileCount += error.providerSidecarFileCount
                        isFileAccountingComplete = false
                        if error.wasCancelled { throw CancellationError() }
                        partialFailures.append(ExportPartialFailure(
                            date: date,
                            dataType: "External integrations",
                            dateRangeDescription: dateString,
                            errorDescription: error.diagnostic
                        ))
                    } catch is CancellationError {
                        isFileAccountingComplete = false
                        throw CancellationError()
                    } catch {
                        isFileAccountingComplete = false
                        partialFailures.append(ExportPartialFailure(
                            date: date,
                            dataType: "External integrations",
                            dateRangeDescription: dateString,
                            errorDescription: error.localizedDescription
                        ))
                    }
                }
                if let archiveSpool {
                    try await archiveSpool.append(
                        healthData,
                        settings: frozenOperationSettings,
                        preparedExport: preparedExport
                    )
                }
                if let retained = retainedHealthDataForDerivedOutputs(
                    healthData,
                    settings: settings
                ) {
                    successfulHealthData.append(retained)
                }
                successCount += 1
                completedDates.append(date)
            } catch is CancellationError {
                isFileAccountingComplete = false
                return ExportResult(
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    looseAggregateFileCount: looseAggregateFileCount,
                    individualEntryFileCount: individualEntryFileCount,
                    dataDictionaryFileCount: dataDictionaryFileCount,
                    externalRecordFileCount: externalRecordFileCount,
                    isFileCategoryBreakdownComplete: isFileAccountingComplete,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            } catch let error as ExportPartialWriteError {
                looseAggregateFileCount += error.looseAggregateFileCount
                individualEntryFileCount += error.individualEntryFileCount
                dataDictionaryFileCount += error.dataDictionaryFileCount
                externalRecordFileCount += error.providerSidecarFileCount
                dailyNoteUpdateCount += error.dailyNoteUpdateCount
                dailyNoteSkipCount += error.dailyNoteSkipCount
                isFileAccountingComplete = false
                if error.wasCancelled {
                    return ExportResult(
                        successCount: successCount,
                        totalCount: totalDays,
                        failedDateDetails: failedDateDetails,
                        partialFailures: partialFailures,
                        formatsPerDate: formatsPerDate,
                        looseAggregateFileCount: looseAggregateFileCount,
                        individualEntryFileCount: individualEntryFileCount,
                        dataDictionaryFileCount: dataDictionaryFileCount,
                        externalRecordFileCount: externalRecordFileCount,
                        isFileCategoryBreakdownComplete: false,
                        dailyNoteUpdateCount: dailyNoteUpdateCount,
                        dailyNoteSkipCount: dailyNoteSkipCount,
                        wasCancelled: true,
                        completedDates: settings.archiveModeEnabled
                            ? terminalNoDataDates(in: failedDateDetails)
                            : completedDates
                    )
                }
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: .fileWriteError,
                    errorDetails: error.diagnostic
                ))
            } catch let error as ExportError {
                let reason: ExportFailureReason
                let errorDetails: String?
                switch error {
                case .noVaultSelected:
                    reason = .noVaultSelected
                    errorDetails = nil
                case .noHealthData:
                    reason = .noHealthData
                    errorDetails = nil
                    completedDates.append(date)
                case .accessDenied:
                    reason = .accessDenied
                    errorDetails = nil
                case .destinationChanged:
                    isFileAccountingComplete = false
                    reason = .accessDenied
                    errorDetails = error.localizedDescription
                case .noFormatsSelected:
                    reason = .unknown
                    errorDetails = error.localizedDescription
                case .dailyNotePathConflict, .dataDictionaryPathConflict, .invalidExportPath:
                    reason = .fileWriteError
                    errorDetails = error.localizedDescription
                }
                failedDateDetails.append(FailedDateDetail(date: date, reason: reason, errorDetails: errorDetails))
            } catch let error as HealthKitManager.HealthKitError {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: failureReason(for: error)
                ))
            } catch {
                isFileAccountingComplete = false
                failedDateDetails.append(FailedDateDetail(
                    date: date, reason: .unknown, errorDetails: error.localizedDescription
                ))
            }
        }
        if let lastDate = dates.last {
            onProgress?(totalDays, totalDays, dateFormatter.string(from: lastDate))
        }

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: dates,
            seedData: successfulHealthData,
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let rollupResult: RollupWriteAccountingResult = settings.archiveModeEnabled
            ? .noOutput
            : writeRollupSummaries(
                from: rollupHealthData,
                vaultManager: vaultManager,
                settings: settings,
                writeDataDictionary: shouldWriteDataDictionary,
                partialFailures: &partialFailures
            )
        dataDictionaryFileCount += rollupResult.dataDictionaryFileCount
        let archiveResult = await writeArchive(
            from: successfulHealthData,
            archiveEntryFiles: archiveSpool?.files ?? [],
            rollupHealthData: rollupHealthData,
            selectedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let archiveCount = archiveResult.archiveCount

        let durableCompletedDates = settings.archiveModeEnabled && archiveCount == 0
            ? terminalNoDataDates(in: failedDateDetails)
            : completedDates
        return ExportResult(
            successCount: successCount,
            totalCount: totalDays,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: formatsPerDate,
            looseAggregateFileCount: looseAggregateFileCount,
            individualEntryFileCount: individualEntryFileCount,
            dataDictionaryFileCount: dataDictionaryFileCount,
            rollupFileCount: rollupResult.rollupFileCount,
            archiveCount: archiveCount,
            externalRecordFileCount: externalRecordFileCount,
            isFileCategoryBreakdownComplete: isFileAccountingComplete
                && rollupResult.isFileAccountingComplete
                && archiveResult.isFileAccountingComplete,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            wasCancelled: rollupResult.wasCancelled || archiveResult.wasCancelled,
            hadTerminalFailure: !rollupResult.wasCancelled
                && !archiveResult.wasCancelled
                && (!isFileAccountingComplete
                    || !rollupResult.isFileAccountingComplete
                    || !archiveResult.isFileAccountingComplete),
            completedDates: durableCompletedDates
        )
    }

    private static func exportForegroundPinnedSimpleRange(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settingsSnapshot: ExportSettingsSnapshot,
        operationSurface: AppleExportOperationSurface,
        sourceTimeZone: TimeZone,
        onProgress: ((Int, Int, String) -> Void)?
    ) async -> ExportResult {
        let frozenSettings = settingsSnapshot.makeAdvancedExportSettings()
        let isSummaryOnly = frozenSettings.summaryOnlyModeEnabled
        let totalCount = dates.count
        let formatsPerDate = looseFormatsPerDate(settings: frozenSettings)
        var calendar = Calendar.current
        calendar.timeZone = sourceTimeZone
        let selectedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let sourceDates = rollupSourceDates(
            for: dates,
            periods: frozenSettings.enabledRollupPeriods,
            calendar: calendar,
            latestAllowedDate: max(Date(), dates.max() ?? Date())
        )
        let captureDates = sourceDates.isEmpty ? dates : sourceDates
        var records: [HealthData] = []
        var selectedRecordDates: [Date] = []
        var dailyOutputOwnerDates: Set<String> = []
        var completedDates: [Date] = []
        var failures: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var selectedProgress = 0
        var didStartWriting = false
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = sourceTimeZone

        for (captureIndex, date) in captureDates.enumerated() {
            let day = calendar.startOfDay(for: date)
            let isSelected = selectedDays.contains(day)
            if Task.isCancelled {
                return ExportResult(
                    successCount: 0,
                    totalCount: totalCount,
                    failedDateDetails: failures,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    isFileCategoryBreakdownComplete: !didStartWriting,
                    wasCancelled: true,
                    completedDates: completedDates
                )
            }
            do {
                let record = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: false,
                    metricSelection: frozenSettings.metricSelection,
                    timeZone: sourceTimeZone
                )
                partialFailures.append(contentsOf: record.partialFailures)
                if record.preparedExport(settings: frozenSettings).hasAnyData {
                    records.append(record)
                    if isSelected && !isSummaryOnly {
                        selectedRecordDates.append(record.date)
                        dailyOutputOwnerDates.insert(
                            HealthKitDailyOwnershipMetadata.ownerDate(
                                for: record.date,
                                calendarTimeZoneIdentifier: sourceTimeZone.identifier
                            )
                        )
                    }
                } else if isSelected && !isSummaryOnly {
                    failures.append(FailedDateDetail(date: date, reason: .noHealthData))
                    completedDates.append(date)
                }
            } catch is CancellationError {
                return ExportResult(
                    successCount: 0,
                    totalCount: totalCount,
                    failedDateDetails: failures,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    isFileCategoryBreakdownComplete: !didStartWriting,
                    wasCancelled: true,
                    completedDates: completedDates
                )
            } catch let error as HealthKitManager.HealthKitError {
                if isSelected && !isSummaryOnly {
                    failures.append(FailedDateDetail(date: date, reason: failureReason(for: error)))
                } else {
                    partialFailures.append(ExportPartialFailure(
                        date: date,
                        dataType: "Roll-up summaries",
                        dateRangeDescription: formatter.string(from: date),
                        errorDescription: error.localizedDescription
                    ))
                }
            } catch {
                if isSelected && !isSummaryOnly {
                    failures.append(FailedDateDetail(
                        date: date,
                        reason: .unknown,
                        errorDetails: error.localizedDescription
                    ))
                } else {
                    partialFailures.append(ExportPartialFailure(
                        date: date,
                        dataType: "Roll-up summaries",
                        dateRangeDescription: formatter.string(from: date),
                        errorDescription: error.localizedDescription
                    ))
                }
            }
            if isSummaryOnly {
                onProgress?(
                    captureIndex + 1,
                    captureDates.count + 1,
                    formatter.string(from: date)
                )
            } else if isSelected {
                selectedProgress += 1
                onProgress?(selectedProgress, totalCount, formatter.string(from: date))
            }
        }

        guard !records.isEmpty else {
            if isSummaryOnly && partialFailures.isEmpty && totalCount > 0 {
                failures.append(FailedDateDetail(
                    date: dates.first ?? Date(),
                    reason: .noHealthData,
                    errorDetails: "No roll-up summary data was available for the selected period."
                ))
                completedDates = dates
            }
            return ExportResult(
                successCount: 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                isFileCategoryBreakdownComplete: true,
                completedDates: completedDates
            )
        }
        if Task.isCancelled {
            return ExportResult(
                successCount: 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                isFileCategoryBreakdownComplete: true,
                wasCancelled: true,
                completedDates: completedDates
            )
        }

        didStartWriting = true
        do {
            guard let writeResult = try await vaultManager.exportHealthDataRange(
                records,
                settingsSnapshot: settingsSnapshot,
                operationSurface: operationSurface,
                dailyOutputOwnerDates: dailyOutputOwnerDates
            ) else {
                // A persisted nonlegacy pin may never be delivered through per-day legacy writes.
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            if isSummaryOnly {
                let filesWritten = writeResult.rollupFileCount
                let isTerminalNoData = filesWritten == 0
                    && failures.isEmpty
                    && partialFailures.isEmpty
                    && totalCount > 0
                if isTerminalNoData {
                    failures.append(FailedDateDetail(
                        date: dates.first ?? Date(),
                        reason: .noHealthData,
                        errorDetails: "No roll-up summary data was available for the selected period."
                    ))
                }
                if filesWritten > 0 || isTerminalNoData {
                    completedDates = dates
                }
                onProgress?(captureDates.count + 1, captureDates.count + 1, "summary files")
                return ExportResult(
                    successCount: filesWritten > 0 ? totalCount : 0,
                    totalCount: totalCount,
                    failedDateDetails: failures,
                    partialFailures: partialFailures,
                    formatsPerDate: 0,
                    dataDictionaryFileCount: writeResult.dataDictionaryFileCount,
                    rollupFileCount: filesWritten,
                    isFileCategoryBreakdownComplete: true,
                    completedDates: completedDates
                )
            }
            completedDates.append(contentsOf: selectedRecordDates)
            return ExportResult(
                successCount: selectedRecordDates.count,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                looseAggregateFileCount: writeResult.dailyFileCount,
                dataDictionaryFileCount: writeResult.dataDictionaryFileCount,
                rollupFileCount: writeResult.rollupFileCount,
                isFileCategoryBreakdownComplete: true,
                completedDates: completedDates
            )
        } catch is CancellationError {
            return ExportResult(
                successCount: 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                isFileCategoryBreakdownComplete: !didStartWriting,
                wasCancelled: true,
                completedDates: completedDates
            )
        } catch let error as ExportPartialWriteError {
            if !error.wasCancelled {
                if isSummaryOnly {
                    let sortedDates = records.map(\.date).sorted()
                    let firstDate = sortedDates.first ?? dates.first ?? Date()
                    let lastDate = sortedDates.last ?? firstDate
                    let first = formatter.string(from: firstDate)
                    let last = formatter.string(from: lastDate)
                    partialFailures.append(ExportPartialFailure(
                        date: firstDate,
                        dataType: "Roll-up summaries",
                        dateRangeDescription: first == last ? first : "\(first) – \(last)",
                        errorDescription: error.diagnostic
                    ))
                } else {
                    failures.append(contentsOf: selectedRecordDates.map {
                        FailedDateDetail(
                            date: $0,
                            reason: .fileWriteError,
                            errorDetails: error.diagnostic
                        )
                    })
                }
            }
            return ExportResult(
                successCount: isSummaryOnly && error.rollupFileCount > 0 ? totalCount : 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                looseAggregateFileCount: error.looseAggregateFileCount,
                individualEntryFileCount: error.individualEntryFileCount,
                dataDictionaryFileCount: error.dataDictionaryFileCount,
                rollupFileCount: error.rollupFileCount,
                archiveCount: error.zipArchiveFileCount,
                externalRecordFileCount: error.providerSidecarFileCount,
                isFileCategoryBreakdownComplete: false,
                dailyNoteUpdateCount: error.dailyNoteUpdateCount,
                dailyNoteSkipCount: error.dailyNoteSkipCount,
                wasCancelled: error.wasCancelled,
                completedDates: completedDates
            )
        } catch {
            if isSummaryOnly {
                let sortedDates = records.map(\.date).sorted()
                let firstDate = sortedDates.first ?? dates.first ?? Date()
                let lastDate = sortedDates.last ?? firstDate
                let first = formatter.string(from: firstDate)
                let last = formatter.string(from: lastDate)
                partialFailures.append(ExportPartialFailure(
                    date: firstDate,
                    dataType: "Roll-up summaries",
                    dateRangeDescription: first == last ? first : "\(first) – \(last)",
                    errorDescription: error.localizedDescription
                ))
            } else {
                failures.append(contentsOf: selectedRecordDates.map {
                    FailedDateDetail(
                        date: $0,
                        reason: .fileWriteError,
                        errorDetails: error.localizedDescription
                    )
                })
            }
            return ExportResult(
                successCount: 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                completedDates: completedDates
            )
        }
    }

    // MARK: - Background Export (caller-managed scope)

    /// Export health data for a list of dates without managing security scope.
    /// Caller must start/stop vault access. Suitable for background tasks and
    /// scheduled exports where scope is managed externally.
    static func exportDatesBackground(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        frozenSettingsSnapshot: ExportSettingsSnapshot? = nil,
        operationSurface: AppleExportOperationSurface = .legacyOnly,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        await HealthKitQueryExecutionController.withController {
            await exportDatesBackgroundWithQueryController(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings,
                frozenSettingsSnapshot: frozenSettingsSnapshot,
                operationSurface: operationSurface,
                onProgress: onProgress
            )
        }
    }

    private static func exportDatesBackgroundWithQueryController(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        frozenSettingsSnapshot: ExportSettingsSnapshot?,
        operationSurface: AppleExportOperationSurface,
        onProgress: ((Int, Int, String) -> Void)?
    ) async -> ExportResult {
        let awakeActivityID = UUID()
        IdleTimerCoordinator.shared.beginActivity(awakeActivityID)
        defer { IdleTimerCoordinator.shared.endActivity(awakeActivityID) }

        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "local-files",
                phase: "background-export",
                timer: performanceTimer,
                itemCount: dates.count
            )
        }
        #endif
        vaultManager.clearLastExportPresentationTarget()
        let formatsPerDate = looseFormatsPerDate(settings: settings)
        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var successfulHealthData: [HealthData] = []
        var looseAggregateFileCount = 0
        var individualEntryFileCount = 0
        var dataDictionaryFileCount = 0
        var isFileAccountingComplete = true
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var shouldWriteDataDictionary = true
        let frozenOperationSettings = frozenSettingsSnapshot?.makeAdvancedExportSettings()
            ?? settings
        do {
            try vaultManager.preflightDataDictionaryArtifactCollisions(
                settings: frozenOperationSettings,
                healthSubfolder: frozenSettingsSnapshot?.healthSubfolder,
                dates: dates
            )
        } catch {
            return ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map {
                    FailedDateDetail(
                        date: $0,
                        reason: .fileWriteError,
                        errorDetails: error.localizedDescription
                    )
                },
                formatsPerDate: formatsPerDate,
                isFileCategoryBreakdownComplete: true,
                completedDates: []
            )
        }
        let archiveSpool = frozenOperationSettings.archiveModeEnabled
            ? LocalArchiveSpool()
            : nil
        defer { archiveSpool?.cleanup() }

        if let frozenSettingsSnapshot,
           frozenSettingsSnapshot.appleExportEnginePin != nil {
            guard let identifier = frozenSettingsSnapshot.calendarTimeZoneIdentifier,
                  let sourceTimeZone = TimeZone(identifier: identifier) else {
                return ExportResult(
                    successCount: 0,
                    totalCount: dates.count,
                    failedDateDetails: dates.map {
                        FailedDateDetail(
                            date: $0,
                            reason: .unknown,
                            errorDetails: AppleLooseDailyExportPlannerError.rustPlanningFailed.rawValue
                        )
                    },
                    formatsPerDate: formatsPerDate,
                    isFileCategoryBreakdownComplete: true
                )
            }
            return await exportForegroundPinnedSimpleRange(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settingsSnapshot: frozenSettingsSnapshot,
                operationSurface: operationSurface,
                sourceTimeZone: sourceTimeZone,
                onProgress: onProgress
            )
        }

        if settings.summaryOnlyModeEnabled {
            return await exportSummaryOnlyDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings,
                onProgress: onProgress
            )
        }

        let progressFormatter = DateFormatter()
        progressFormatter.dateFormat = "yyyy-MM-dd"
        progressFormatter.timeZone = settings.exportTimeZoneOverride ?? .current

        for (index, date) in dates.enumerated() {
            // Check for cancellation before each date
            if Task.isCancelled {
                return ExportResult(
                    successCount: successCount,
                    totalCount: dates.count,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    looseAggregateFileCount: looseAggregateFileCount,
                    individualEntryFileCount: individualEntryFileCount,
                    dataDictionaryFileCount: dataDictionaryFileCount,
                    isFileCategoryBreakdownComplete: isFileAccountingComplete,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            }

            onProgress?(index, dates.count, progressFormatter.string(from: date))

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: frozenOperationSettings.effectiveGranularDataEnabled,
                    metricSelection: frozenOperationSettings.metricSelection,
                    timeZone: frozenOperationSettings.exportTimeZoneOverride
                )
                partialFailures.append(contentsOf: healthData.partialFailures)
                let preparedExport = healthData.preparedExportAssumingSelectionApplied(
                    settings: frozenOperationSettings
                )

                let writeResult = try await vaultManager.exportHealthData(
                    healthData,
                    settings: settings,
                    healthSubfolder: frozenSettingsSnapshot?.healthSubfolder,
                    writeDataDictionary: shouldWriteDataDictionary,
                    operationSurface: operationSurface,
                    frozenSettingsSnapshot: frozenSettingsSnapshot,
                    preparedExport: preparedExport
                )
                if !settings.archiveModeEnabled && !settings.dailyNotesOnlyModeEnabled {
                    shouldWriteDataDictionary = false
                }
                looseAggregateFileCount += writeResult.aggregateFileCount
                individualEntryFileCount += writeResult.individualEntryFileCount
                dataDictionaryFileCount += writeResult.dataDictionaryFileCount
                dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                dailyNoteSkipCount += writeResult.dailyNoteSkippedCount

                if settings.dailyNotesOnlyModeEnabled {
                    switch writeResult.dailyNoteResult {
                    case .updated:
                        break
                    case .skipped(let reason):
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .noHealthData,
                            errorDetails: reason
                        ))
                        completedDates.append(date)
                        continue
                    case .failed(let error):
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .fileWriteError,
                            errorDetails: error.localizedDescription
                        ))
                        continue
                    case .none:
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .fileWriteError,
                            errorDetails: "Daily note update was not performed."
                        ))
                        continue
                    }
                }

                if let archiveSpool {
                    try await archiveSpool.append(
                        healthData,
                        settings: frozenOperationSettings,
                        preparedExport: preparedExport
                    )
                }
                if let retained = retainedHealthDataForDerivedOutputs(
                    healthData,
                    settings: frozenOperationSettings
                ) {
                    successfulHealthData.append(retained)
                }
                successCount += 1
                completedDates.append(date)
            } catch is CancellationError {
                isFileAccountingComplete = false
                return ExportResult(
                    successCount: successCount,
                    totalCount: dates.count,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    looseAggregateFileCount: looseAggregateFileCount,
                    individualEntryFileCount: individualEntryFileCount,
                    dataDictionaryFileCount: dataDictionaryFileCount,
                    isFileCategoryBreakdownComplete: isFileAccountingComplete,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            } catch let error as ExportPartialWriteError {
                looseAggregateFileCount += error.looseAggregateFileCount
                individualEntryFileCount += error.individualEntryFileCount
                dataDictionaryFileCount += error.dataDictionaryFileCount
                dailyNoteUpdateCount += error.dailyNoteUpdateCount
                dailyNoteSkipCount += error.dailyNoteSkipCount
                isFileAccountingComplete = false
                if error.wasCancelled {
                    return ExportResult(
                        successCount: successCount,
                        totalCount: dates.count,
                        failedDateDetails: failedDateDetails,
                        partialFailures: partialFailures,
                        formatsPerDate: formatsPerDate,
                        looseAggregateFileCount: looseAggregateFileCount,
                        individualEntryFileCount: individualEntryFileCount,
                        dataDictionaryFileCount: dataDictionaryFileCount,
                        isFileCategoryBreakdownComplete: false,
                        dailyNoteUpdateCount: dailyNoteUpdateCount,
                        dailyNoteSkipCount: dailyNoteSkipCount,
                        wasCancelled: true,
                        completedDates: settings.archiveModeEnabled
                            ? terminalNoDataDates(in: failedDateDetails)
                            : completedDates
                    )
                }
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: .fileWriteError,
                    errorDetails: error.diagnostic
                ))
            } catch let error as ExportError {
                let reason: ExportFailureReason
                switch error {
                case .noVaultSelected:
                    reason = .noVaultSelected
                case .noHealthData:
                    reason = .noHealthData
                    completedDates.append(date)
                case .accessDenied:
                    reason = .accessDenied
                case .destinationChanged:
                    isFileAccountingComplete = false
                    reason = .accessDenied
                case .noFormatsSelected:
                    reason = .unknown
                case .dailyNotePathConflict, .dataDictionaryPathConflict, .invalidExportPath:
                    reason = .fileWriteError
                }
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: reason,
                    errorDetails: error.localizedDescription
                ))
            } catch let error as HealthKitManager.HealthKitError {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: failureReason(for: error)
                ))
            } catch {
                isFileAccountingComplete = false
                failedDateDetails.append(FailedDateDetail(
                    date: date, reason: .healthKitError, errorDetails: error.localizedDescription
                ))
            }
        }
        if let lastDate = dates.last {
            onProgress?(dates.count, dates.count, progressFormatter.string(from: lastDate))
        }

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: dates,
            seedData: successfulHealthData,
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let rollupResult: RollupWriteAccountingResult = settings.archiveModeEnabled
            ? .noOutput
            : writeRollupSummaries(
                from: rollupHealthData,
                vaultManager: vaultManager,
                settings: settings,
                writeDataDictionary: shouldWriteDataDictionary,
                partialFailures: &partialFailures
            )
        dataDictionaryFileCount += rollupResult.dataDictionaryFileCount
        let archiveResult = await writeArchive(
            from: successfulHealthData,
            archiveEntryFiles: archiveSpool?.files ?? [],
            rollupHealthData: rollupHealthData,
            selectedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let archiveCount = archiveResult.archiveCount

        let durableCompletedDates = settings.archiveModeEnabled && archiveCount == 0
            ? terminalNoDataDates(in: failedDateDetails)
            : completedDates
        return ExportResult(
            successCount: successCount,
            totalCount: dates.count,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: formatsPerDate,
            looseAggregateFileCount: looseAggregateFileCount,
            individualEntryFileCount: individualEntryFileCount,
            dataDictionaryFileCount: dataDictionaryFileCount,
            rollupFileCount: rollupResult.rollupFileCount,
            archiveCount: archiveCount,
            isFileCategoryBreakdownComplete: isFileAccountingComplete
                && rollupResult.isFileAccountingComplete
                && archiveResult.isFileAccountingComplete,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            wasCancelled: rollupResult.wasCancelled || archiveResult.wasCancelled,
            hadTerminalFailure: !rollupResult.wasCancelled
                && !archiveResult.wasCancelled
                && (!isFileAccountingComplete
                    || !rollupResult.isFileAccountingComplete
                    || !archiveResult.isFileAccountingComplete),
            completedDates: durableCompletedDates
        )
    }

    // MARK: - Derived-output retention

    /// Loose daily exports are complete once their files and side effects have
    /// been written. Keep no dense source model unless a later derived output
    /// needs it. Roll-ups never consume the canonical archive, so retain an
    /// archive-free projection rather than multiplying lossless one-day memory
    /// by the selected date count.
    static func retainedHealthDataForDerivedOutputs(
        _ healthData: HealthData,
        settings: AdvancedExportSettings
    ) -> HealthData? {
        guard HealthRollupExporter.isEnabled(settings: settings) else {
            return nil
        }
        return ConnectedExportGranularMode.sanitized(
            healthData,
            includesGranularData: false
        )
    }

    // MARK: - ZIP Archive Export

    private static func looseFormatsPerDate(settings: AdvancedExportSettings) -> Int {
        settings.looseFormatsPerDate
    }

    private struct ArchiveWriteResult {
        let archiveCount: Int
        let wasCancelled: Bool
        let isFileAccountingComplete: Bool

        static let noOutput = ArchiveWriteResult(
            archiveCount: 0,
            wasCancelled: false,
            isFileAccountingComplete: true
        )
        static let cancelled = ArchiveWriteResult(
            archiveCount: 0,
            wasCancelled: true,
            isFileAccountingComplete: false
        )
        static let failed = ArchiveWriteResult(
            archiveCount: 0,
            wasCancelled: false,
            isFileAccountingComplete: false
        )
    }

    private static func writeArchive(
        from successfulHealthData: [HealthData],
        archiveEntryFiles: [RenderedHealthDataArchiveEntryFile] = [],
        rollupHealthData: [HealthData],
        selectedDates: [Date],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        partialFailures: inout [ExportPartialFailure]
    ) async -> ArchiveWriteResult {
        guard settings.archiveModeEnabled else { return .noOutput }
        guard !settings.exportFormats.isEmpty else { return .noOutput }
        guard !archiveEntryFiles.isEmpty
                || !successfulHealthData.isEmpty
                || (settings.summaryOnlyModeEnabled && !rollupHealthData.isEmpty) else {
            return .noOutput
        }

        let sortedDates = selectedDates.sorted()
        let sourceDates = archiveEntryFiles.map(\.date) + successfulHealthData.map(\.date)
        let startDate = sortedDates.first ?? sourceDates.min() ?? Date()
        let endDate = sortedDates.last ?? sourceDates.max() ?? startDate
        do {
            let archiveURL: URL?
            if archiveEntryFiles.isEmpty {
                archiveURL = try await vaultManager.exportArchive(
                    from: successfulHealthData,
                    rollupHealthData: rollupHealthData,
                    settings: settings,
                    startDate: startDate,
                    endDate: endDate
                )
            } else {
                archiveURL = try await vaultManager.exportArchive(
                    fromRenderedFiles: archiveEntryFiles,
                    rollupHealthData: rollupHealthData,
                    settings: settings,
                    startDate: startDate,
                    endDate: endDate
                )
            }
            return ArchiveWriteResult(
                archiveCount: archiveURL == nil ? 0 : 1,
                wasCancelled: false,
                isFileAccountingComplete: true
            )
        } catch is CancellationError {
            return .cancelled
        } catch let error as ExportPartialWriteError {
            if !error.wasCancelled {
                appendArchiveFailure(
                    error.diagnostic,
                    startDate: startDate,
                    endDate: endDate,
                    partialFailures: &partialFailures
                )
            }
            return ArchiveWriteResult(
                archiveCount: error.zipArchiveFileCount,
                wasCancelled: error.wasCancelled,
                isFileAccountingComplete: false
            )
        } catch {
            appendArchiveFailure(
                error.localizedDescription,
                startDate: startDate,
                endDate: endDate,
                partialFailures: &partialFailures
            )
            return .failed
        }
    }

    private static func appendArchiveFailure(
        _ description: String,
        startDate: Date,
        endDate: Date,
        partialFailures: inout [ExportPartialFailure]
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        partialFailures.append(ExportPartialFailure(
            date: startDate,
            dataType: "ZIP archive",
            dateRangeDescription: formatter.string(from: startDate) == formatter.string(from: endDate)
                ? formatter.string(from: startDate)
                : "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))",
            errorDescription: description
        ))
    }

    // MARK: - Roll-up Summary Export

    private static func exportSummaryOnlyDates(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        let totalDays = dates.count
        var partialFailures: [ExportPartialFailure] = []
        var failedDateDetails: [FailedDateDetail] = []

        let sourceDateCount = rollupSourceDates(for: dates, settings: settings).count
        let progressFormatter = DateFormatter()
        progressFormatter.dateFormat = "yyyy-MM-dd"
        progressFormatter.timeZone = settings.exportTimeZoneOverride ?? .current

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: dates,
            seedData: [],
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures,
            progress: { processed, total, date in
                onProgress?(processed, total + 1, progressFormatter.string(from: date))
            }
        )

        if Task.isCancelled {
            return ExportResult(
                successCount: 0,
                totalCount: totalDays,
                failedDateDetails: failedDateDetails,
                partialFailures: partialFailures,
                formatsPerDate: 0,
                isFileCategoryBreakdownComplete: true,
                wasCancelled: true,
                completedDates: []
            )
        }

        let rollupResult: RollupWriteAccountingResult = settings.archiveModeEnabled
            ? .noOutput
            : writeRollupSummaries(
                from: rollupHealthData,
                vaultManager: vaultManager,
                settings: settings,
                partialFailures: &partialFailures
            )
        let archiveResult = await writeArchive(
            from: [],
            rollupHealthData: rollupHealthData,
            selectedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let archiveCount = archiveResult.archiveCount
        let wasCancelled = rollupResult.wasCancelled || archiveResult.wasCancelled
        if sourceDateCount > 0, !wasCancelled {
            onProgress?(sourceDateCount + 1, sourceDateCount + 1, "summary files")
        }
        let outputArtifactCount = rollupResult.rollupFileCount + archiveCount

        let isTerminalNoData = !wasCancelled
            && outputArtifactCount == 0
            && totalDays > 0
            && failedDateDetails.isEmpty
            && partialFailures.isEmpty
        if isTerminalNoData {
            failedDateDetails.append(FailedDateDetail(
                date: dates.first ?? Date(),
                reason: .noHealthData,
                errorDetails: "No roll-up summary data was available for the selected period."
            ))
        }

        return ExportResult(
            successCount: outputArtifactCount > 0 ? totalDays : 0,
            totalCount: totalDays,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: 0,
            dataDictionaryFileCount: rollupResult.dataDictionaryFileCount,
            rollupFileCount: rollupResult.rollupFileCount,
            archiveCount: archiveCount,
            isFileCategoryBreakdownComplete: rollupResult.isFileAccountingComplete
                && archiveResult.isFileAccountingComplete,
            wasCancelled: wasCancelled,
            hadTerminalFailure: !wasCancelled
                && (!rollupResult.isFileAccountingComplete
                    || !archiveResult.isFileAccountingComplete),
            completedDates: wasCancelled
                ? []
                : (outputArtifactCount > 0 || isTerminalNoData ? dates : [])
        )
    }

    private static func fetchRollupHealthData(
        selectedDates: [Date],
        seedData: [HealthData],
        healthKitManager: HealthKitManager,
        settings: AdvancedExportSettings,
        partialFailures: inout [ExportPartialFailure],
        progress: ((_ processed: Int, _ total: Int, _ date: Date) -> Void)? = nil
    ) async -> [HealthData] {
        guard HealthRollupExporter.isEnabled(settings: settings) else { return seedData }

        let sourceDates = rollupSourceDates(for: selectedDates, settings: settings)
        guard !sourceDates.isEmpty else { return seedData }

        let calendar = Calendar.current
        var dataByDay = Dictionary(uniqueKeysWithValues: seedData.map { data in
            (calendar.startOfDay(for: data.date), data)
        })
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for (index, date) in sourceDates.enumerated() {
            if Task.isCancelled { break }

            let day = calendar.startOfDay(for: date)
            guard dataByDay[day] == nil else {
                progress?(index + 1, sourceDates.count, date)
                continue
            }

            do {
                // Roll-up summaries only need daily aggregate snapshots, even
                // when the daily export includes larger granular time-series data.
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: false,
                    metricSelection: settings.metricSelection
                )
                partialFailures.append(contentsOf: healthData.partialFailures)
                dataByDay[day] = healthData
            } catch {
                partialFailures.append(
                    ExportPartialFailure(
                        date: date,
                        dataType: "Roll-up summaries",
                        dateRangeDescription: formatter.string(from: date),
                        errorDescription: error.localizedDescription
                    )
                )
            }
            progress?(index + 1, sourceDates.count, date)
        }

        return sourceDates.compactMap { date in
            dataByDay[calendar.startOfDay(for: date)]
        }
    }

    private struct RollupWriteAccountingResult {
        let rollupFileCount: Int
        let dataDictionaryFileCount: Int
        let isFileAccountingComplete: Bool
        let wasCancelled: Bool

        static let noOutput = RollupWriteAccountingResult(
            rollupFileCount: 0,
            dataDictionaryFileCount: 0,
            isFileAccountingComplete: true,
            wasCancelled: false
        )
        static let failed = RollupWriteAccountingResult(
            rollupFileCount: 0,
            dataDictionaryFileCount: 0,
            isFileAccountingComplete: false,
            wasCancelled: false
        )
        static let cancelled = RollupWriteAccountingResult(
            rollupFileCount: 0,
            dataDictionaryFileCount: 0,
            isFileAccountingComplete: false,
            wasCancelled: true
        )
    }

    private static func writeRollupSummaries(
        from rollupHealthData: [HealthData],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        writeDataDictionary: Bool = true,
        partialFailures: inout [ExportPartialFailure]
    ) -> RollupWriteAccountingResult {
        guard !rollupHealthData.isEmpty else { return .noOutput }
        guard HealthRollupExporter.isEnabled(settings: settings) else { return .noOutput }

        do {
            let result = try vaultManager.exportRollupSummaries(
                from: rollupHealthData,
                settings: settings,
                writeDataDictionary: writeDataDictionary
            )
            return RollupWriteAccountingResult(
                rollupFileCount: result.count,
                dataDictionaryFileCount: result.dataDictionaryFileCount,
                isFileAccountingComplete: true,
                wasCancelled: false
            )
        } catch is CancellationError {
            return .cancelled
        } catch let error as ExportPartialWriteError {
            if !error.wasCancelled {
                appendRollupFailure(
                    error.diagnostic,
                    rollupHealthData: rollupHealthData,
                    partialFailures: &partialFailures
                )
            }
            return RollupWriteAccountingResult(
                rollupFileCount: error.rollupFileCount,
                dataDictionaryFileCount: error.dataDictionaryFileCount,
                isFileAccountingComplete: false,
                wasCancelled: error.wasCancelled
            )
        } catch {
            appendRollupFailure(
                error.localizedDescription,
                rollupHealthData: rollupHealthData,
                partialFailures: &partialFailures
            )
            return .failed
        }
    }

    private static func appendRollupFailure(
        _ description: String,
        rollupHealthData: [HealthData],
        partialFailures: inout [ExportPartialFailure]
    ) {
        let sortedDates = rollupHealthData.map(\.date).sorted()
        let firstDate = sortedDates.first ?? Date()
        let lastDate = sortedDates.last ?? firstDate
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let rangeDescription = formatter.string(from: firstDate) == formatter.string(from: lastDate)
            ? formatter.string(from: firstDate)
            : "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
        partialFailures.append(ExportPartialFailure(
            date: firstDate,
            dataType: "Roll-up summaries",
            dateRangeDescription: rangeDescription,
            errorDescription: description
        ))
    }

    // MARK: - Failure Mapping

    private static func terminalNoDataDates(
        in details: [FailedDateDetail],
        calendar: Calendar = .current
    ) -> [Date] {
        Array(Set(details.compactMap { detail in
            guard detail.reason == .noHealthData else { return nil }
            return calendar.startOfDay(for: detail.date)
        })).sorted()
    }

    private static func failureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized, .dataNotAvailable, .medicationAuthorizationUnsupported,
             .visionAuthorizationUnsupported:
            return .healthKitError
        }
    }

    // MARK: - History Recording Helper

    /// Records an export result in the history manager.
    static func recordResult(
        _ result: ExportResult,
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        idempotencyKey: UUID? = nil,
        pendingRecoveryDayCount: Int = 0,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        let history = ExportHistoryManager.shared
        // An omitted count is authoritative only when the producer supplied an exact total or
        // measured every physical category. Incomplete producers retain known category counters
        // without turning their lower bound into a false authoritative total.
        let resolvedFileCount: Int?
        if let fileCount {
            resolvedFileCount = fileCount
        } else if let authoritativeFileCount = result.authoritativeFileCount {
            resolvedFileCount = authoritativeFileCount
        } else if result.isFileCategoryBreakdownComplete {
            resolvedFileCount = result.categorizedFileCount
        } else {
            resolvedFileCount = nil
        }
        let outputBreakdown = resolvedFileCount.map {
            result.outputBreakdown(resolvedFileCount: $0)
        } ?? result.outputBreakdown

        if result.successCount > 0 || result.dailyNoteSkipCount > 0 {
            history.recordSuccess(
                id: idempotencyKey ?? UUID(),
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails,
                targetLabel: targetLabel,
                exportTarget: exportTarget,
                fileCount: resolvedFileCount,
                outputBreakdown: outputBreakdown,
                pendingRecoveryDayCount: pendingRecoveryDayCount,
                dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                dailyNoteSkipCount: result.dailyNoteSkipCount,
                partialFailures: result.partialFailures,
                wasCancelled: result.wasCancelled,
                hadTerminalFailure: result.hadTerminalFailure,
                appleExportEnginePin: appleExportEnginePin,
                operationDetails: operationDetails
            )
        } else {
            history.recordFailure(
                id: idempotencyKey ?? UUID(),
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                reason: result.primaryFailureReason ?? .unknown,
                successCount: 0,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails,
                targetLabel: targetLabel,
                exportTarget: exportTarget,
                fileCount: resolvedFileCount,
                outputBreakdown: outputBreakdown,
                pendingRecoveryDayCount: pendingRecoveryDayCount,
                dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                dailyNoteSkipCount: result.dailyNoteSkipCount,
                partialFailures: result.partialFailures,
                wasCancelled: result.wasCancelled,
                hadTerminalFailure: result.hadTerminalFailure,
                appleExportEnginePin: appleExportEnginePin,
                operationDetails: operationDetails
            )
        }
    }
}
