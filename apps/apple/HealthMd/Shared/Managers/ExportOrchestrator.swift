import Foundation

@MainActor
final class LocalArchiveSpool {
    private let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "healthmd-local-archive-\(UUID().uuidString)",
        isDirectory: true
    )
    private var nextIndex = 0
    private(set) var files: [RenderedHealthDataArchiveEntryFile] = []
    private(set) var capturedDates: Set<Date> = []

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
                // Each artifact render is a synchronous MainActor segment; the
                // autoreleasepool drains per-format Foundation intermediates so a
                // multi-thousand-day archive spool does not accumulate them.
                let artifact = try autoreleasepool {
                    try preparedExport.renderArtifact(
                        format: format,
                        in: directoryURL
                    )
                }
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
        capturedDates.insert(healthData.date)
        nextIndex += stagedFiles.count
    }

    func markCapturedWithoutOutput(_ date: Date) {
        capturedDates.insert(date)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
        files.removeAll(keepingCapacity: false)
        capturedDates.removeAll(keepingCapacity: false)
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
        let completedDates: [Date]?
        let completedDateCount: Int
        let failedDateDetails: [FailedDateDetail]
        let partialFailures: [ExportPartialFailure]
        let wasCancelled: Bool
        /// True only for a range-level derived-output/finalizer failure. Ordinary per-date
        /// partial results retain exact completed dates for residual scheduled retries.
        let hadTerminalRangeFailure: Bool
        let formatsPerDate: Int
        let looseAggregateFileCount: Int
        let individualEntryFileCount: Int
        let dataDictionaryFileCount: Int
        let rollupFileCount: Int
        let archiveCount: Int
        let externalRecordFileCount: Int
        /// Provider records encoded in an API request; never generated files.
        let externalRecordPayloadCount: Int
        let unclassifiedFileCount: Int
        /// Confirmed wire total retained even when category persistence was truncated.
        let fileCountLowerBound: Int?
        let authoritativeFileCount: Int?
        let isFileCategoryBreakdownComplete: Bool
        /// True when persistence budgeting reduced one or more file-category counts.
        /// Category completeness remains a separate producer fact.
        let wasFileAccountingTruncated: Bool
        let dailyNoteUpdateCount: Int
        let dailyNoteSkipCount: Int

        init(
            successCount: Int,
            totalCount: Int,
            failedDateDetails: [FailedDateDetail],
            partialFailures: [ExportPartialFailure] = [],
            formatsPerDate: Int = 1,
            looseAggregateFileCount: Int? = nil,
            individualEntryFileCount: Int = 0,
            dataDictionaryFileCount: Int = 0,
            rollupFileCount: Int = 0,
            archiveCount: Int = 0,
            externalRecordFileCount: Int = 0,
            externalRecordPayloadCount: Int = 0,
            unclassifiedFileCount: Int = 0,
            fileCountLowerBound: Int? = nil,
            authoritativeFileCount: Int? = nil,
            isFileCategoryBreakdownComplete: Bool = false,
            wasFileAccountingTruncated: Bool = false,
            dailyNoteUpdateCount: Int = 0,
            dailyNoteSkipCount: Int = 0,
            wasCancelled: Bool = false,
            hadTerminalRangeFailure: Bool = false,
            completedDates: [Date]? = nil,
            completedDateCount: Int? = nil
        ) {
            self.successCount = max(successCount, 0)
            self.totalCount = max(totalCount, 0)
            if let completedDates {
                self.completedDates = Array(Set(completedDates)).sorted()
                self.completedDateCount = self.completedDates?.count ?? 0
            } else {
                self.completedDates = nil
                self.completedDateCount = completedDateCount ?? self.successCount
            }
            self.failedDateDetails = failedDateDetails
            self.partialFailures = partialFailures
            self.formatsPerDate = max(formatsPerDate, 0)
            let legacyLooseCount = self.successCount.multipliedReportingOverflow(by: self.formatsPerDate)
            let loose = looseAggregateFileCount.map { max($0, 0) } ?? 0
            let legacyUnclassified = looseAggregateFileCount == nil && !legacyLooseCount.overflow
                ? legacyLooseCount.partialValue : 0
            self.looseAggregateFileCount = loose
            self.individualEntryFileCount = max(individualEntryFileCount, 0)
            self.dataDictionaryFileCount = max(dataDictionaryFileCount, 0)
            self.rollupFileCount = max(rollupFileCount, 0)
            self.archiveCount = max(archiveCount, 0)
            self.externalRecordFileCount = max(externalRecordFileCount, 0)
            self.externalRecordPayloadCount = max(externalRecordPayloadCount, 0)
            self.unclassifiedFileCount = Self.saturatingAdd(
                max(unclassifiedFileCount, 0),
                legacyUnclassified
            )
            self.fileCountLowerBound = fileCountLowerBound.map { max($0, 0) }
            self.authoritativeFileCount = authoritativeFileCount.map { max($0, 0) }
            self.isFileCategoryBreakdownComplete = isFileCategoryBreakdownComplete
                && looseAggregateFileCount != nil
                && self.unclassifiedFileCount == 0
            self.wasFileAccountingTruncated = wasFileAccountingTruncated
            self.dailyNoteUpdateCount = max(dailyNoteUpdateCount, 0)
            self.dailyNoteSkipCount = max(dailyNoteSkipCount, 0)
            self.wasCancelled = wasCancelled
            self.hadTerminalRangeFailure = hadTerminalRangeFailure
        }

        init(macExportPayload payload: MacExportResultPayload) {
            let breakdown = payload.outputBreakdown
            let impliedLooseFiles = payload.successCount.multipliedReportingOverflow(
                by: payload.formatsPerDate
            )
            let legacyLooseFileCount = impliedLooseFiles.overflow
                ? 0 : max(impliedLooseFiles.partialValue, 0)
            let legacyCategorizedFileCount = Self.saturatingAdd(
                legacyLooseFileCount,
                payload.externalRecordFileCount
            )
            let knownFiles = breakdown?.generatedFileCount ?? legacyCategorizedFileCount
            let unclassifiedGap: Int
            if breakdown?.wasTruncated == true {
                unclassifiedGap = 0
            } else {
                let difference = payload.totalFilesWritten.subtractingReportingOverflow(knownFiles)
                unclassifiedGap = difference.overflow ? 0 : max(difference.partialValue, 0)
            }
            let unclassified = Self.saturatingAdd(
                breakdown?.unclassifiedFileCount ?? 0,
                unclassifiedGap
            )
            self.init(
                successCount: payload.successCount,
                totalCount: payload.totalCount,
                failedDateDetails: payload.failedDateDetails,
                partialFailures: payload.partialFailures ?? [],
                formatsPerDate: payload.formatsPerDate,
                // Legacy payloads identify successful per-format outputs as loose
                // files even though they predate the full category breakdown.
                looseAggregateFileCount: breakdown?.looseAggregateFileCount
                    ?? legacyLooseFileCount,
                individualEntryFileCount: breakdown?.individualEntryFileCount ?? 0,
                dataDictionaryFileCount: breakdown?.dataDictionaryFileCount ?? 0,
                rollupFileCount: breakdown?.rollupFileCount ?? 0,
                archiveCount: breakdown?.zipArchiveFileCount ?? 0,
                externalRecordFileCount: breakdown?.providerSidecarFileCount
                    ?? payload.externalRecordFileCount,
                // Only the remainder after every known category (including provider
                // sidecars) is unclassified. A truncated breakdown's gap is budget
                // loss, not evidence that the producer emitted unclassified files.
                // Saturation also keeps malformed direct construction non-trapping;
                // app ingress separately rejects inconsistent wire payloads.
                unclassifiedFileCount: unclassified,
                fileCountLowerBound: payload.totalFilesWritten,
                authoritativeFileCount: payload.isTotalFilesWrittenAuthoritative
                    ? payload.totalFilesWritten : nil,
                isFileCategoryBreakdownComplete: breakdown?.isFileCategoryBreakdownComplete ?? false,
                wasFileAccountingTruncated: breakdown?.wasTruncated ?? false,
                dailyNoteUpdateCount: payload.dailyNoteUpdateCount,
                dailyNoteSkipCount: payload.dailyNoteSkipCount,
                wasCancelled: payload.status == .cancelled,
                hadTerminalRangeFailure: payload.hadTerminalRangeFailure,
                completedDates: payload.completedDates
            )
        }

        private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
            let result = lhs.addingReportingOverflow(rhs)
            return result.overflow ? Int.max : result.partialValue
        }

        var hasPartialFailures: Bool { !partialFailures.isEmpty }
        var partialFailureSummary: String {
            guard let first = partialFailures.first else { return "" }
            if partialFailures.count == 1 { return "Warning: \(first.summary)" }
            return "Warning: \(partialFailures.count) export warnings, including \(first.summary)"
        }
        var localizedPartialFailureSummary: String {
            guard let first = partialFailures.first else { return "" }
            if partialFailures.count == 1 { return String(localized: "Warning: \(first.localizedSummary)") }
            return String(localized: "Warning: \(partialFailures.count) export warnings, including \(first.localizedSummary)")
        }
        var didCompleteAllRequestedDates: Bool {
            completedDateCount == totalCount && totalCount > 0 && !wasCancelled && !hadTerminalRangeFailure
        }
        func remainingDates(from requestedDates: [Date], calendar: Calendar = .current) -> [Date]? {
            guard !hadTerminalRangeFailure, let completedDates else { return nil }
            let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })
            return requestedDates.map { calendar.startOfDay(for: $0) }.filter { !completedDays.contains($0) }
        }
        var isFullSuccess: Bool {
            successCount == totalCount && didCompleteAllRequestedDates && failedDateDetails.isEmpty && !hasPartialFailures
        }
        var isPartialSuccess: Bool {
            guard !isFullSuccess else { return false }
            let hasConfirmedOutput = successCount > 0
                || dailyNoteUpdateCount > 0
                || dailyNoteSkipCount > 0
                || knownFileCount > 0
            return hasConfirmedOutput
        }
        var isFailure: Bool {
            !isFullSuccess && !isPartialSuccess && totalCount > 0
        }
        var primaryFailureReason: ExportFailureReason? { failedDateDetails.first?.reason }
        var categorizedFileCount: Int {
            [
                looseAggregateFileCount,
                individualEntryFileCount,
                dataDictionaryFileCount,
                rollupFileCount,
                archiveCount,
                externalRecordFileCount
            ].reduce(0, Self.saturatingAdd)
        }
        var knownFileCount: Int {
            Self.saturatingAdd(categorizedFileCount, unclassifiedFileCount)
        }
        var totalFilesWritten: Int {
            max(authoritativeFileCount ?? 0, max(fileCountLowerBound ?? 0, knownFileCount))
        }
        var hasAuthoritativeFileCount: Bool {
            !outputBreakdown.wasTruncated
                && (authoritativeFileCount != nil || isFileCategoryBreakdownComplete)
        }
        var outputBreakdown: ExportHistoryOutputBreakdown {
            ExportHistoryOutputBreakdown(
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
                isFileCategoryBreakdownComplete: isFileCategoryBreakdownComplete,
                persistedWasTruncated: wasFileAccountingTruncated
            )
        }

        var localizedGeneratedFileAndDataDayDescription: String {
            if hasAuthoritativeFileCount {
                return String(localized: "\(totalFilesWritten) generated file(s) · \(successCount) of \(totalCount) data day(s)")
            }
            let confirmedFiles = String(localized: "\(totalFilesWritten) generated file(s)")
            let dataDays = String(localized: "\(successCount) of \(totalCount) data day(s)")
            return "≥ \(confirmedFiles) · \(dataDays)"
        }

        var fileBreakdownDescription: String {
            var parts: [String] = []
            if looseAggregateFileCount > 0 { parts.append("\(looseAggregateFileCount) loose files") }
            if individualEntryFileCount > 0 { parts.append("\(individualEntryFileCount) individual-entry files") }
            if dataDictionaryFileCount > 0 { parts.append("\(dataDictionaryFileCount) data dictionary") }
            if archiveCount > 0 { parts.append("\(archiveCount) ZIP archive") }
            if rollupFileCount > 0 { parts.append("\(rollupFileCount) roll-up summaries") }
            if externalRecordFileCount > 0 { parts.append("\(externalRecordFileCount) provider sidecars") }
            if unclassifiedFileCount > 0 { parts.append("\(unclassifiedFileCount) unclassified files") }
            if dailyNoteUpdateCount > 0 { parts.append("\(dailyNoteUpdateCount) daily notes updated") }
            return parts.isEmpty ? "no generated files" : parts.joined(separator: " + ")
        }
    }

    // MARK: - Date Range Helper

    /// Builds an array of calendar days from startDate through endDate (inclusive).
    static func dateRange(
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
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
                if period == .range {
                    expandedDates.insert(calendar.startOfDay(for: selectedDate))
                    continue
                }
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
        var externalRecordFileCount = 0
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var shouldWriteDataDictionary = true
        let hasProviderSideEffects = ConnectedAppsFeature.isEnabled
            && (externalIntegrations?.connectedProviderCount ?? 0) > 0
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
            try vaultManager.preflightExportDestinations(
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
                    externalRecordFileCount: externalRecordFileCount,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            }

            // Cooperative yield between days: the fetch below releases the main
            // actor, but the prepared-export build and the vault write are
            // synchronous MainActor segments. Yielding here lets the main actor
            // service UI events (progress paint, touch handling) between days so
            // multi-thousand-day exports no longer freeze the interface.
            await Task.yield()

            let dateString = dateFormatter.string(from: date)
            onProgress?(index, totalDays, dateString)

            do {
                var healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    detailPolicy: frozenOperationSettings.effectiveDetailPolicy,
                    metricSelection: frozenOperationSettings.metricSelection,
                    timeZone: sourceTimeZone
                )
                let externalRecords: [ExternalDailyRecord]
                if healthData.hasAnyData,
                   settings.writesExternalProviderSidecars,
                   ConnectedAppsFeature.isEnabled,
                   let externalIntegrations,
                   externalIntegrations.connectedProviderCount > 0 {
                    var providerCalendar = Calendar(identifier: .gregorian)
                    providerCalendar.timeZone = sourceTimeZone
                    externalRecords = await externalIntegrations.fetchDailyRecords(
                        for: date,
                        calendar: providerCalendar
                    )
                    healthData.providers = HealthProviderSections.normalized(from: externalRecords)
                } else {
                    externalRecords = []
                }
                partialFailures.append(contentsOf: healthData.partialFailures)
                // HealthKitManager has already applied the frozen selection. Reuse
                // one snapshot for loose-file and ZIP staging renders instead of
                // filtering a potentially dense archive for each destination.
                // The prepared export and the retained day are the only per-day
                // allocations that outlive this statement; the autoreleasepool
                // drains Foundation intermediates before the next day begins.
                //
                // Follow-up (main-actor render): building this snapshot off the
                // main actor is blocked end-to-end by MainActor isolation:
                //   - HealthData.swift:1543 `struct PreparedHealthDataExport`
                //     (no `nonisolated`; the app target compiles with
                //     SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so its init and
                //     render members are MainActor-isolated)
                //   - HealthData.swift:1673 `preparedExportAssumingSelectionApplied`
                //     and ExportDataSnapshot.swift:272 `exportSnapshot` (members of
                //     `extension HealthData` also default to MainActor isolation)
                //   - AdvancedExportSettings.swift:279 `AdvancedExportSettings`
                //     supplies formatCustomization/includeMetadata/groupByCategory
                //     from MainActor-isolated members
                // Moving the render would require re-annotating those types, which
                // are outside this file's ownership boundary.
                let preparedExport = autoreleasepool {
                    healthData.preparedExportAssumingSelectionApplied(
                        settings: frozenOperationSettings
                    )
                }
                let writeResult = try await vaultManager.exportHealthData(
                    healthData,
                    settings: settings,
                    writeDataDictionary: shouldWriteDataDictionary,
                    operationSurface: operationSurface,
                    frozenSettingsSnapshot: operationSettingsSnapshot,
                    preparedExport: preparedExport
                )
                partialFailures.append(contentsOf: writeResult.individualEntryCoverageGaps)
                if !settings.archiveModeEnabled && !settings.dailyNotesOnlyModeEnabled {
                    shouldWriteDataDictionary = false
                }
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

                if !externalRecords.isEmpty {
                    do {
                        externalRecordFileCount += try await vaultManager.exportExternalDailyRecords(externalRecords)
                    } catch {
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
                return ExportResult(
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    externalRecordFileCount: externalRecordFileCount,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
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
                    reason = .accessDenied
                    errorDetails = error.localizedDescription
                case .noFormatsSelected:
                    reason = .unknown
                    errorDetails = error.localizedDescription
                case .markdownMergeRejected, .dailyNotePathConflict, .invalidExportPath:
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
        // A cancellation delivered by the final source-day await must stop before
        // any range-level artifact begins. Daily files already committed remain
        // accounted, while archive mode has no durable per-day success yet.
        if Task.isCancelled {
            return ExportResult(
                successCount: successCount,
                totalCount: totalDays,
                failedDateDetails: failedDateDetails,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                externalRecordFileCount: externalRecordFileCount,
                dailyNoteUpdateCount: dailyNoteUpdateCount,
                dailyNoteSkipCount: dailyNoteSkipCount,
                wasCancelled: true,
                completedDates: settings.archiveModeEnabled
                    ? terminalNoDataDates(in: failedDateDetails)
                    : completedDates
            )
        }
        let rollupFileCount = settings.archiveModeEnabled ? 0 : writeRollupSummaries(
            from: rollupHealthData,
            requestedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            writeDataDictionary: shouldWriteDataDictionary,
            partialFailures: &partialFailures
        )
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
            rollupFileCount: rollupFileCount,
            archiveCount: archiveCount,
            externalRecordFileCount: externalRecordFileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            wasCancelled: archiveResult.wasCancelled,
            completedDates: durableCompletedDates
        )
    }

    private static func exportForegroundPinnedSimpleRange(
        _ dates: [Date],
        requestedRollupDates: [Date]? = nil,
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settingsSnapshot: ExportSettingsSnapshot,
        operationSurface: AppleExportOperationSurface,
        sourceTimeZone: TimeZone,
        onProgress: ((Int, Int, String) -> Void)?
    ) async -> ExportResult {
        let totalCount = dates.count
        var calendar = Calendar.current
        calendar.timeZone = sourceTimeZone
        let immutableRollupDates = requestedRollupDates ?? dates
        let requestedIdentifiers = Set(immutableRollupDates.map {
            HealthKitDailyOwnershipMetadata.ownerDate(
                for: $0,
                calendarTimeZoneIdentifier: sourceTimeZone.identifier
            )
        })
        var effectiveSettingsSnapshot = settingsSnapshot
        var requestedRange: HealthRollupRangeRequest?
        var partialFailures: [ExportPartialFailure] = []
        if settingsSnapshot.generateRangeSummary {
            do {
                requestedRange = try HealthRollupRangeRequest(
                    ownerDateIdentifiers: requestedIdentifiers,
                    calendarTimeZoneIdentifier: sourceTimeZone.identifier
                )
            } catch HealthRollupRangeRequest.ValidationError.exceedsDayLimit {
                partialFailures.append(rangeSummaryUnavailableFailure(
                    requestedDates: immutableRollupDates,
                    calendarTimeZone: sourceTimeZone
                ))
                // The range artifact is independently bounded. Keep the frozen daily renderer
                // authority and continue the residual daily request without asking core for v9.
                effectiveSettingsSnapshot.generateRangeSummary = false
            } catch {
                return ExportResult(
                    successCount: 0,
                    totalCount: totalCount,
                    failedDateDetails: dates.map {
                        FailedDateDetail(
                            date: $0,
                            reason: .fileWriteError,
                            errorDetails: error.localizedDescription
                        )
                    },
                    formatsPerDate: settingsSnapshot.summaryOnlyExport ? 0 : settingsSnapshot.exportFormats.count
                )
            }
        }
        let frozenSettings = effectiveSettingsSnapshot.makeAdvancedExportSettings()
        let isSummaryOnly = frozenSettings.summaryOnlyModeEnabled
        let formatsPerDate = looseFormatsPerDate(settings: frozenSettings)
        let selectedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let sourceDates = rollupSourceDates(
            for: immutableRollupDates,
            periods: frozenSettings.enabledRollupPeriods,
            calendar: calendar,
            latestAllowedDate: max(Date(), dates.max() ?? Date())
        )
        let captureDates = sourceDates.isEmpty ? dates : sourceDates
        var records: [HealthData] = []
        var hasRenderableCapture = false
        var selectedRecordDates: [Date] = []
        var dailyOutputOwnerDates: Set<String> = []
        var completedDates: [Date] = []
        var failures: [FailedDateDetail] = []
        var selectedProgress = 0
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
                    wasCancelled: true,
                    completedDates: completedDates
                )
            }
            // Cooperative yield between capture days keeps the main actor
            // responsive during expanded roll-up windows (weekly/monthly/yearly
            // capture ranges are many times larger than the selected range).
            await Task.yield()
            do {
                let record = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: false,
                    metricSelection: frozenSettings.metricSelection,
                    timeZone: sourceTimeZone
                )
                partialFailures.append(contentsOf: record.partialFailures)
                // Drain Foundation render intermediates for this day before the
                // record is retained for the range write.
                let hasRenderableData = autoreleasepool {
                    record.preparedExport(settings: frozenSettings).hasAnyData
                }
                // A successful capture is range provenance even when the selected metrics are
                // empty. Keep it for range-v9 source_dates/days_counted, while selecting daily
                // output only when the prepared daily artifact has renderable data.
                if hasRenderableData || requestedRange != nil {
                    records.append(record)
                }
                if hasRenderableData {
                    hasRenderableCapture = true
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

        guard !records.isEmpty, hasRenderableCapture else {
            if isSummaryOnly && partialFailures.isEmpty && totalCount > 0 {
                failures.append(contentsOf: terminalNoDataFailures(for: dates, calendar: calendar))
                completedDates = dates
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
        if Task.isCancelled {
            return ExportResult(
                successCount: 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                wasCancelled: true,
                completedDates: completedDates
            )
        }

        do {
            guard let writeResult = try await vaultManager.exportHealthDataRange(
                records,
                settingsSnapshot: effectiveSettingsSnapshot,
                operationSurface: operationSurface,
                dailyOutputOwnerDates: dailyOutputOwnerDates,
                requestedRange: requestedRange
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
                    failures.append(contentsOf: terminalNoDataFailures(for: dates, calendar: calendar))
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
                    rollupFileCount: filesWritten,
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
                rollupFileCount: writeResult.rollupFileCount,
                completedDates: completedDates
            )
        } catch is CancellationError {
            return ExportResult(
                successCount: 0,
                totalCount: totalCount,
                failedDateDetails: failures,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                wasCancelled: true,
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
        requestedRollupDates: [Date]? = nil,
        operationSurface: AppleExportOperationSurface = .legacyOnly,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        await HealthKitQueryExecutionController.withController {
            await exportDatesBackgroundWithQueryController(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings,
                frozenSettingsSnapshot: frozenSettingsSnapshot,
                requestedRollupDates: requestedRollupDates,
                operationSurface: operationSurface,
                externalIntegrations: externalIntegrations,
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
        requestedRollupDates: [Date]?,
        operationSurface: AppleExportOperationSurface,
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
                phase: "background-export",
                timer: performanceTimer,
                itemCount: dates.count
            )
        }
        #endif
        externalIntegrations?.beginExportAction()
        defer { externalIntegrations?.endExportAction() }
        vaultManager.clearLastExportPresentationTarget()
        let formatsPerDate = looseFormatsPerDate(settings: settings)
        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var successfulHealthData: [HealthData] = []
        var externalRecordFileCount = 0
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var shouldWriteDataDictionary = true
        let frozenOperationSettings = frozenSettingsSnapshot?.makeAdvancedExportSettings()
            ?? settings
        do {
            try vaultManager.preflightExportDestinations(
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
                    formatsPerDate: formatsPerDate
                )
            }
            return await exportForegroundPinnedSimpleRange(
                dates,
                requestedRollupDates: requestedRollupDates,
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
                requestedRollupDates: requestedRollupDates,
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
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            }

            // Cooperative yield between days: scheduled exports run through this
            // same @MainActor orchestrator, so the main actor must also be able to
            // service UI events between the synchronous render/write segments.
            await Task.yield()

            onProgress?(index, dates.count, progressFormatter.string(from: date))

            do {
                var healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    detailPolicy: frozenOperationSettings.effectiveDetailPolicy,
                    metricSelection: frozenOperationSettings.metricSelection,
                    timeZone: frozenOperationSettings.exportTimeZoneOverride
                )
                let externalRecords: [ExternalDailyRecord]
                if healthData.hasAnyData,
                   settings.writesExternalProviderSidecars,
                   ConnectedAppsFeature.isEnabled,
                   let externalIntegrations,
                   externalIntegrations.connectedProviderCount > 0 {
                    var providerCalendar = Calendar(identifier: .gregorian)
                    providerCalendar.timeZone = frozenOperationSettings.exportTimeZoneOverride ?? .current
                    externalRecords = await externalIntegrations.fetchDailyRecords(
                        for: date,
                        calendar: providerCalendar
                    )
                    healthData.providers = HealthProviderSections.normalized(from: externalRecords)
                } else {
                    externalRecords = []
                }
                partialFailures.append(contentsOf: healthData.partialFailures)
                // Drain Foundation render intermediates per day; see the matching
                // comment in exportDatesWithQueryController for why the render
                // itself cannot leave the main actor yet.
                let preparedExport = autoreleasepool {
                    healthData.preparedExportAssumingSelectionApplied(
                        settings: frozenOperationSettings
                    )
                }

                let writeResult = try await vaultManager.exportHealthData(
                    healthData,
                    settings: settings,
                    healthSubfolder: frozenSettingsSnapshot?.healthSubfolder,
                    writeDataDictionary: shouldWriteDataDictionary,
                    operationSurface: operationSurface,
                    frozenSettingsSnapshot: frozenSettingsSnapshot,
                    preparedExport: preparedExport
                )
                partialFailures.append(contentsOf: writeResult.individualEntryCoverageGaps)
                if !settings.archiveModeEnabled && !settings.dailyNotesOnlyModeEnabled {
                    shouldWriteDataDictionary = false
                }
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

                if !externalRecords.isEmpty {
                    do {
                        externalRecordFileCount += try await vaultManager.exportExternalDailyRecords(externalRecords)
                    } catch {
                        partialFailures.append(ExportPartialFailure(
                            date: date,
                            dataType: "External integrations",
                            dateRangeDescription: progressFormatter.string(from: date),
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
                    settings: frozenOperationSettings
                ) {
                    successfulHealthData.append(retained)
                }
                successCount += 1
                completedDates.append(date)
            } catch is CancellationError {
                return ExportResult(
                    successCount: successCount,
                    totalCount: dates.count,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    wasCancelled: true,
                    completedDates: settings.archiveModeEnabled
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
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
                    reason = .accessDenied
                case .noFormatsSelected:
                    reason = .unknown
                case .markdownMergeRejected, .dailyNotePathConflict, .invalidExportPath:
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
                failedDateDetails.append(FailedDateDetail(
                    date: date, reason: .healthKitError, errorDetails: error.localizedDescription
                ))
            }
        }
        if let lastDate = dates.last {
            onProgress?(dates.count, dates.count, progressFormatter.string(from: lastDate))
        }

        let immutableRollupDates = requestedRollupDates ?? dates
        var archiveHasCompleteOriginalSources = true
        if let archiveSpool, requestedRollupDates != nil {
            var archiveCalendar = Calendar(identifier: .gregorian)
            archiveCalendar.timeZone = frozenOperationSettings.exportTimeZoneOverride ?? .current
            let capturedDays = Set(archiveSpool.capturedDates.map { archiveCalendar.startOfDay(for: $0) })
            for originalDate in immutableRollupDates where !capturedDays.contains(
                archiveCalendar.startOfDay(for: originalDate)
            ) {
                do {
                    var healthData = try await healthKitManager.fetchHealthData(
                        for: originalDate,
                        detailPolicy: frozenOperationSettings.effectiveDetailPolicy,
                        metricSelection: frozenOperationSettings.metricSelection,
                        timeZone: frozenOperationSettings.exportTimeZoneOverride
                    )
                    if healthData.hasAnyData,
                       settings.writesExternalProviderSidecars,
                       ConnectedAppsFeature.isEnabled,
                       let externalIntegrations,
                       externalIntegrations.connectedProviderCount > 0 {
                        let providerRecords = await externalIntegrations.fetchDailyRecords(
                            for: originalDate,
                            calendar: archiveCalendar
                        )
                        healthData.providers = HealthProviderSections.normalized(from: providerRecords)
                    }
                    let prepared = autoreleasepool {
                        healthData.preparedExportAssumingSelectionApplied(
                            settings: frozenOperationSettings
                        )
                    }
                    if prepared.hasAnyData {
                        try await archiveSpool.append(
                            healthData,
                            settings: frozenOperationSettings,
                            preparedExport: prepared
                        )
                    } else {
                        archiveSpool.markCapturedWithoutOutput(healthData.date)
                    }
                } catch is CancellationError {
                    return ExportResult(
                        successCount: successCount,
                        totalCount: dates.count,
                        failedDateDetails: failedDateDetails,
                        partialFailures: partialFailures,
                        formatsPerDate: formatsPerDate,
                        dailyNoteUpdateCount: dailyNoteUpdateCount,
                        dailyNoteSkipCount: dailyNoteSkipCount,
                        wasCancelled: true,
                        completedDates: terminalNoDataDates(in: failedDateDetails)
                    )
                } catch {
                    archiveHasCompleteOriginalSources = false
                    partialFailures.append(ExportPartialFailure(
                        date: originalDate,
                        dataType: "ZIP archive",
                        dateRangeDescription: progressFormatter.string(from: originalDate),
                        errorDescription: "The original range could not be recaptured; the existing archive was preserved."
                    ))
                    break
                }
            }
        }
        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: immutableRollupDates,
            seedData: successfulHealthData,
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        // Recheck after the final awaited capture. Without this boundary a
        // cancelled foreground/background task can still publish a range roll-up
        // or ZIP after its final requested day has returned.
        if Task.isCancelled {
            return ExportResult(
                successCount: successCount,
                totalCount: dates.count,
                failedDateDetails: failedDateDetails,
                partialFailures: partialFailures,
                formatsPerDate: formatsPerDate,
                dailyNoteUpdateCount: dailyNoteUpdateCount,
                dailyNoteSkipCount: dailyNoteSkipCount,
                wasCancelled: true,
                completedDates: settings.archiveModeEnabled
                    ? terminalNoDataDates(in: failedDateDetails)
                    : completedDates
            )
        }
        let rollupFileCount = settings.archiveModeEnabled ? 0 : writeRollupSummaries(
            from: rollupHealthData,
            requestedDates: immutableRollupDates,
            vaultManager: vaultManager,
            settings: settings,
            writeDataDictionary: shouldWriteDataDictionary,
            partialFailures: &partialFailures
        )
        let archiveResult = archiveHasCompleteOriginalSources ? await writeArchive(
            from: successfulHealthData,
            archiveEntryFiles: archiveSpool?.files ?? [],
            rollupHealthData: rollupHealthData,
            selectedDates: immutableRollupDates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        ) : .noOutput
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
            rollupFileCount: rollupFileCount,
            archiveCount: archiveCount,
            externalRecordFileCount: externalRecordFileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            wasCancelled: archiveResult.wasCancelled,
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
        return ConnectedExportDetailPolicy.sanitized(
            healthData,
            detailPolicy: .summary
        )
    }

    // MARK: - ZIP Archive Export

    private static func looseFormatsPerDate(settings: AdvancedExportSettings) -> Int {
        settings.looseFormatsPerDate
    }

    private struct ArchiveWriteResult {
        let archiveCount: Int
        let wasCancelled: Bool

        static let noOutput = ArchiveWriteResult(archiveCount: 0, wasCancelled: false)
        static let cancelled = ArchiveWriteResult(archiveCount: 0, wasCancelled: true)
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
        if settings.generateRangeSummary,
           let calendarTimeZone = settings.exportTimeZoneOverride {
            do {
                _ = try HealthRollupRangeRequest(
                    startDate: startDate,
                    endDate: endDate,
                    calendarTimeZoneIdentifier: calendarTimeZone.identifier
                )
            } catch HealthRollupRangeRequest.ValidationError.exceedsDayLimit {
                partialFailures.append(rangeSummaryUnavailableFailure(
                    requestedDates: sortedDates,
                    calendarTimeZone: calendarTimeZone
                ))
            } catch {
                // The archive writer reports other invalid range authority as its own failure.
            }
        }
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
                wasCancelled: false
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            partialFailures.append(
                ExportPartialFailure(
                    date: startDate,
                    dataType: "ZIP archive",
                    dateRangeDescription: formatter.string(from: startDate) == formatter.string(from: endDate)
                        ? formatter.string(from: startDate)
                        : "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))",
                    errorDescription: error.localizedDescription
                )
            )
            return .noOutput
        }
    }

    // MARK: - Roll-up Summary Export

    private static func exportSummaryOnlyDates(
        _ dates: [Date],
        requestedRollupDates: [Date]? = nil,
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        let totalDays = dates.count
        var partialFailures: [ExportPartialFailure] = []
        var failedDateDetails: [FailedDateDetail] = []

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = settings.exportTimeZoneOverride ?? .gmt
        let immutableRollupDates = requestedRollupDates ?? dates
        let sourceDateCount = rollupSourceDates(
            for: immutableRollupDates,
            settings: settings,
            calendar: calendar
        ).count
        let progressFormatter = DateFormatter()
        progressFormatter.dateFormat = "yyyy-MM-dd"
        progressFormatter.timeZone = settings.exportTimeZoneOverride ?? .current

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: immutableRollupDates,
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
                wasCancelled: true,
                completedDates: []
            )
        }

        let rollupFileCount = settings.archiveModeEnabled ? 0 : writeRollupSummaries(
            from: rollupHealthData,
            requestedDates: immutableRollupDates,
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
        if sourceDateCount > 0, !archiveResult.wasCancelled {
            onProgress?(sourceDateCount + 1, sourceDateCount + 1, "summary files")
        }
        let filesWritten = rollupFileCount + archiveCount

        let isTerminalNoData = !archiveResult.wasCancelled
            && filesWritten == 0
            && totalDays > 0
            && failedDateDetails.isEmpty
            && partialFailures.isEmpty
        if isTerminalNoData {
            failedDateDetails.append(contentsOf: terminalNoDataFailures(for: dates, calendar: calendar))
        }

        return ExportResult(
            successCount: filesWritten > 0 ? totalDays : 0,
            totalCount: totalDays,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: 0,
            rollupFileCount: rollupFileCount,
            archiveCount: archiveCount,
            wasCancelled: archiveResult.wasCancelled,
            completedDates: archiveResult.wasCancelled
                ? []
                : (filesWritten > 0 || isTerminalNoData ? dates : [])
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

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = settings.exportTimeZoneOverride ?? .gmt
        let sourceDates = rollupSourceDates(
            for: selectedDates,
            settings: settings,
            calendar: calendar
        )
        guard !sourceDates.isEmpty else { return seedData }

        var dataByDay = Dictionary(uniqueKeysWithValues: seedData.map { data in
            (calendar.startOfDay(for: data.date), data)
        })
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for (index, date) in sourceDates.enumerated() {
            if Task.isCancelled { break }

            // Cooperative yield between roll-up source days. A summary-only or
            // All Time run can expand to thousands of capture days; each fetch
            // releases the main actor but the dictionary/mapping work in between
            // does not, so yield to keep the UI responsive.
            await Task.yield()

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
                    metricSelection: settings.metricSelection,
                    timeZone: calendar.timeZone
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

    private static func writeRollupSummaries(
        from rollupHealthData: [HealthData],
        requestedDates: [Date],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        writeDataDictionary: Bool = true,
        partialFailures: inout [ExportPartialFailure]
    ) -> Int {
        guard !rollupHealthData.isEmpty else { return 0 }
        guard HealthRollupExporter.isEnabled(settings: settings) else { return 0 }

        do {
            guard let timeZone = settings.exportTimeZoneOverride else {
                throw ExportError.invalidExportPath(path: "missing calendar timezone")
            }
            let requestedIdentifiers = Set(requestedDates.map {
                HealthKitDailyOwnershipMetadata.ownerDate(
                    for: $0,
                    calendarTimeZoneIdentifier: timeZone.identifier
                )
            })
            let requestedRange = try HealthRollupRangeRequest(
                ownerDateIdentifiers: requestedIdentifiers,
                calendarTimeZoneIdentifier: timeZone.identifier
            )
            return try vaultManager.exportRollupSummaries(
                from: rollupHealthData,
                requestedRange: requestedRange,
                settings: settings,
                writeDataDictionary: writeDataDictionary
            ).count
        } catch {
            let sortedDates = rollupHealthData.map(\.date).sorted()
            let firstDate = sortedDates.first ?? Date()
            let lastDate = sortedDates.last ?? firstDate
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let rangeDescription: String
            if formatter.string(from: firstDate) == formatter.string(from: lastDate) {
                rangeDescription = formatter.string(from: firstDate)
            } else {
                rangeDescription = "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate))"
            }

            partialFailures.append(
                ExportPartialFailure(
                    date: firstDate,
                    dataType: error as? HealthRollupRangeRequest.ValidationError == .exceedsDayLimit
                        ? "Range Summary"
                        : "Roll-up summaries",
                    dateRangeDescription: rangeDescription,
                    errorDescription: error.localizedDescription
                )
            )
            return 0
        }
    }

    static func settingsByDisablingUnavailableRangeSummary(
        _ snapshot: ExportSettingsSnapshot,
        requestedDates: [Date],
        calendarTimeZone: TimeZone
    ) -> (snapshot: ExportSettingsSnapshot, warning: ExportPartialFailure?) {
        guard snapshot.generateRangeSummary else { return (snapshot, nil) }
        do {
            _ = try HealthRollupRangeRequest(
                ownerDateIdentifiers: Set(requestedDates.map {
                    HealthKitDailyOwnershipMetadata.ownerDate(
                        for: $0,
                        calendarTimeZoneIdentifier: calendarTimeZone.identifier
                    )
                }),
                calendarTimeZoneIdentifier: calendarTimeZone.identifier
            )
            return (snapshot, nil)
        } catch HealthRollupRangeRequest.ValidationError.exceedsDayLimit {
            var effectiveSnapshot = snapshot
            effectiveSnapshot.generateRangeSummary = false
            return (
                effectiveSnapshot,
                rangeSummaryUnavailableFailure(
                    requestedDates: requestedDates,
                    calendarTimeZone: calendarTimeZone
                )
            )
        } catch {
            // Preserve the frozen request for the renderer to report any non-limit validation
            // failure through its existing terminal path.
            return (snapshot, nil)
        }
    }

    static func terminalNoDataFailures(
        for requestedDates: [Date],
        calendar: Calendar = .current,
        errorDetails: String = "No roll-up summary data was available for the selected period."
    ) -> [FailedDateDetail] {
        var seen: Set<Date> = []
        return requestedDates.compactMap { date in
            let day = calendar.startOfDay(for: date)
            guard seen.insert(day).inserted else { return nil }
            return FailedDateDetail(
                date: date,
                reason: .noHealthData,
                errorDetails: errorDetails
            )
        }
    }

    static func rangeSummaryUnavailableFailure(
        requestedDates: [Date],
        calendarTimeZone: TimeZone
    ) -> ExportPartialFailure {
        let sortedDates = requestedDates.sorted()
        let firstDate = sortedDates.first ?? Date()
        let lastDate = sortedDates.last ?? firstDate
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendarTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: firstDate)
        let last = formatter.string(from: lastDate)
        return ExportPartialFailure(
            date: firstDate,
            dataType: "Range Summary",
            dateRangeDescription: first == last ? first : "\(first) – \(last)",
            errorDescription: HealthRollupRangeRequest.dayLimitUnavailableMessage
        )
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
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil,
        profileName: String? = nil
    ) {
        let history = ExportHistoryManager.shared
        let suppliedFileCount = fileCount.map { max($0, 0) }
        let resolvedFileCount = suppliedFileCount ?? result.totalFilesWritten
        let isAuthoritative = !result.outputBreakdown.wasTruncated
            && (suppliedFileCount != nil || result.hasAuthoritativeFileCount)
        let historyFileCount = isAuthoritative ? resolvedFileCount : nil

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
                fileCount: historyFileCount,
                outputBreakdown: result.outputBreakdown,
                dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                dailyNoteSkipCount: result.dailyNoteSkipCount,
                partialFailures: result.partialFailures,
                appleExportEnginePin: appleExportEnginePin,
                operationDetails: operationDetails,
                profileName: profileName
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
                fileCount: historyFileCount,
                outputBreakdown: result.outputBreakdown,
                dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                dailyNoteSkipCount: result.dailyNoteSkipCount,
                partialFailures: result.partialFailures,
                appleExportEnginePin: appleExportEnginePin,
                operationDetails: operationDetails,
                profileName: profileName
            )
        }
    }
}
