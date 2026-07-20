import Foundation

@MainActor
final class LocalArchiveSpool {
    private let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "healthmd-local-archive-\(UUID().uuidString)",
        isDirectory: true
    )
    private var nextIndex = 0
    private(set) var files: [RenderedHealthDataArchiveEntryFile] = []

    func append(_ healthData: HealthData, settings: AdvancedExportSettings) async throws {
        if nextIndex == 0 {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let preparedExport = healthData.preparedExport(settings: settings)
        var stagedFiles: [RenderedHealthDataArchiveEntryFile] = []
        do {
            for (offset, format) in settings.exportFormats
                .sorted(by: { $0.rawValue < $1.rawValue })
                .enumerated() {
                try Task.checkCancellation()
                let content = try preparedExport.content(format: format, settings: settings)
                guard let data = content.data(using: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                let order = nextIndex + offset
                let fileURL = directoryURL.appendingPathComponent("\(order).entry")
                try await Self.write(data, to: fileURL)
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

    nonisolated private static func write(_ data: Data, to url: URL) async throws {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            try data.write(to: url, options: .atomic)
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
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
        /// Number of loose files written per successful date.
        let formatsPerDate: Int
        /// Number of derived roll-up summary files written after successful daily exports.
        let rollupFileCount: Int
        /// Number of ZIP archives written for packaged exports.
        let archiveCount: Int
        /// Number of third-party provider sidecar JSON files written.
        let externalRecordFileCount: Int
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
            rollupFileCount: Int = 0,
            archiveCount: Int = 0,
            externalRecordFileCount: Int = 0,
            dailyNoteUpdateCount: Int = 0,
            dailyNoteSkipCount: Int = 0,
            wasCancelled: Bool = false,
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
            self.formatsPerDate = formatsPerDate
            self.rollupFileCount = rollupFileCount
            self.archiveCount = archiveCount
            self.externalRecordFileCount = externalRecordFileCount
            self.dailyNoteUpdateCount = dailyNoteUpdateCount
            self.dailyNoteSkipCount = dailyNoteSkipCount
            self.wasCancelled = wasCancelled
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
            completedDateCount == totalCount && totalCount > 0 && !wasCancelled
        }

        /// Returns the exact unresolved subset when the producer supplied
        /// per-date completion. Legacy aggregate-only partial results return nil
        /// so callers can conservatively preserve the original request.
        func remainingDates(
            from requestedDates: [Date],
            calendar: Calendar = .current
        ) -> [Date]? {
            guard let completedDates else { return nil }
            let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })
            return requestedDates
                .map { calendar.startOfDay(for: $0) }
                .filter { !completedDays.contains($0) }
        }
        var isFullSuccess: Bool {
            successCount == totalCount && didCompleteAllRequestedDates && !hasPartialFailures
        }
        var isPartialSuccess: Bool {
            ((successCount > 0 || dailyNoteSkipCount > 0) && successCount < totalCount) ||
            ((successCount > 0 || dailyNoteSkipCount > 0) && wasCancelled) ||
            ((successCount > 0 || dailyNoteSkipCount > 0) && hasPartialFailures)
        }
        var isFailure: Bool {
            successCount == 0 && dailyNoteSkipCount == 0 && totalCount > 0
        }
        var primaryFailureReason: ExportFailureReason? { failedDateDetails.first?.reason }
        /// Total file count = loose daily files plus ZIP archives, roll-up summaries, and provider sidecars.
        var totalFilesWritten: Int { successCount * formatsPerDate + rollupFileCount + archiveCount + externalRecordFileCount }

        var fileBreakdownDescription: String {
            let dailyDescription: String
            if formatsPerDate > 1 {
                dailyDescription = "\(successCount) days × \(formatsPerDate) loose formats"
            } else if formatsPerDate == 1 {
                dailyDescription = "\(successCount) daily file\(successCount == 1 ? "" : "s")"
            } else {
                dailyDescription = "no loose daily files"
            }
            var parts = [dailyDescription]
            if archiveCount > 0 {
                parts.append("\(archiveCount) ZIP archive\(archiveCount == 1 ? "" : "s")")
            }
            if rollupFileCount > 0 {
                parts.append("\(rollupFileCount) roll-up summar\(rollupFileCount == 1 ? "y" : "ies")")
            }
            if externalRecordFileCount > 0 {
                parts.append("\(externalRecordFileCount) provider sidecar\(externalRecordFileCount == 1 ? "" : "s")")
            }
            if dailyNoteUpdateCount > 0 {
                parts.append("\(dailyNoteUpdateCount) daily note\(dailyNoteUpdateCount == 1 ? "" : "s") updated")
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

                for date in dateRange(from: start, to: end) {
                    expandedDates.insert(calendar.startOfDay(for: date))
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
        let archiveSpool = settings.archiveModeEnabled ? LocalArchiveSpool() : nil
        defer { archiveSpool?.cleanup() }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

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

            let dateString = dateFormatter.string(from: date)
            onProgress?(index + 1, totalDays, dateString)

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: settings.effectiveGranularDataEnabled,
                    metricSelection: settings.metricSelection
                )
                partialFailures.append(contentsOf: healthData.partialFailures)
                let writeResult = try await vaultManager.exportHealthData(
                    healthData,
                    settings: settings,
                    writeDataDictionary: shouldWriteDataDictionary
                )
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

                if settings.writesExternalProviderSidecars,
                   ConnectedAppsFeature.isEnabled,
                   let externalIntegrations,
                   externalIntegrations.connectedProviderCount > 0 {
                    let externalRecords = await externalIntegrations.fetchDailyRecords(for: date)
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
                    try await archiveSpool.append(healthData, settings: settings)
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
                case .noFormatsSelected:
                    reason = .unknown
                    errorDetails = error.localizedDescription
                case .dailyNotePathConflict:
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

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: dates,
            seedData: successfulHealthData,
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let rollupFileCount = settings.archiveModeEnabled ? 0 : writeRollupSummaries(
            from: rollupHealthData,
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

    // MARK: - Background Export (caller-managed scope)

    /// Export health data for a list of dates without managing security scope.
    /// Caller must start/stop vault access. Suitable for background tasks and
    /// scheduled exports where scope is managed externally.
    static func exportDatesBackground(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings
    ) async -> ExportResult {
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
        let formatsPerDate = looseFormatsPerDate(settings: settings)
        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var successfulHealthData: [HealthData] = []
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var shouldWriteDataDictionary = true
        let archiveSpool = settings.archiveModeEnabled ? LocalArchiveSpool() : nil
        defer { archiveSpool?.cleanup() }

        if settings.summaryOnlyModeEnabled {
            return await exportSummaryOnlyDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: settings
            )
        }

        for date in dates {
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

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: settings.effectiveGranularDataEnabled,
                    metricSelection: settings.metricSelection
                )
                partialFailures.append(contentsOf: healthData.partialFailures)

                let preparedExport = healthData.preparedExport(settings: settings)
                if !preparedExport.hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    completedDates.append(date)
                    continue
                }

                let writeResult = try vaultManager.exportHealthDataResult(
                    healthData,
                    for: date,
                    settings: settings,
                    writeDataDictionary: shouldWriteDataDictionary,
                    preparedExport: preparedExport
                )
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

                if let archiveSpool {
                    try await archiveSpool.append(healthData, settings: settings)
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

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: dates,
            seedData: successfulHealthData,
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let rollupFileCount = settings.archiveModeEnabled ? 0 : writeRollupSummaries(
            from: rollupHealthData,
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
            totalCount: dates.count,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: formatsPerDate,
            rollupFileCount: rollupFileCount,
            archiveCount: archiveCount,
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
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        let totalDays = dates.count
        var partialFailures: [ExportPartialFailure] = []
        var failedDateDetails: [FailedDateDetail] = []

        if totalDays > 0 {
            onProgress?(1, totalDays, "roll-up summaries")
        }

        let rollupHealthData = await fetchRollupHealthData(
            selectedDates: dates,
            seedData: [],
            healthKitManager: healthKitManager,
            settings: settings,
            partialFailures: &partialFailures
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
        let filesWritten = rollupFileCount + archiveCount

        let isTerminalNoData = !archiveResult.wasCancelled
            && filesWritten == 0
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
        partialFailures: inout [ExportPartialFailure]
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

        for date in sourceDates {
            if Task.isCancelled { break }

            let day = calendar.startOfDay(for: date)
            guard dataByDay[day] == nil else { continue }

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
        }

        return sourceDates.compactMap { date in
            dataByDay[calendar.startOfDay(for: date)]
        }
    }

    private static func writeRollupSummaries(
        from rollupHealthData: [HealthData],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        writeDataDictionary: Bool = true,
        partialFailures: inout [ExportPartialFailure]
    ) -> Int {
        guard !rollupHealthData.isEmpty else { return 0 }
        guard HealthRollupExporter.isEnabled(settings: settings) else { return 0 }

        do {
            return try vaultManager.exportRollupSummaries(
                from: rollupHealthData,
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
                    dataType: "Roll-up summaries",
                    dateRangeDescription: rangeDescription,
                    errorDescription: error.localizedDescription
                )
            )
            return 0
        }
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
        fileCount: Int? = nil
    ) {
        let history = ExportHistoryManager.shared
        let resolvedFileCount = fileCount ?? result.totalFilesWritten

        if result.successCount > 0 || result.dailyNoteSkipCount > 0 {
            history.recordSuccess(
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails,
                targetLabel: targetLabel,
                exportTarget: exportTarget,
                fileCount: resolvedFileCount,
                dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                dailyNoteSkipCount: result.dailyNoteSkipCount,
                partialFailures: result.partialFailures
            )
        } else {
            history.recordFailure(
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
                dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                dailyNoteSkipCount: result.dailyNoteSkipCount,
                partialFailures: result.partialFailures
            )
        }
    }
}
