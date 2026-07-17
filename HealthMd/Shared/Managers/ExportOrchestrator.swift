import Foundation

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

        init(
            successCount: Int,
            totalCount: Int,
            failedDateDetails: [FailedDateDetail],
            partialFailures: [ExportPartialFailure] = [],
            formatsPerDate: Int = 1,
            rollupFileCount: Int = 0,
            archiveCount: Int = 0,
            externalRecordFileCount: Int = 0,
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
            (successCount > 0 && successCount < totalCount) ||
            (successCount > 0 && wasCancelled) ||
            (successCount > 0 && hasPartialFailures)
        }
        var isFailure: Bool { successCount == 0 && totalCount > 0 }
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
        let totalDays = dates.count
        let formatsPerDate = looseFormatsPerDate(settings: settings)
        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var successfulHealthData: [HealthData] = []
        var externalRecordFileCount = 0
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
                    wasCancelled: true,
                    completedDates: settings.archiveExportFiles
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            }

            let dateString = dateFormatter.string(from: date)
            onProgress?(index + 1, totalDays, dateString)

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection
                )
                partialFailures.append(contentsOf: healthData.partialFailures)
                try await vaultManager.exportHealthData(healthData, settings: settings)
                if ConnectedAppsFeature.isEnabled, let externalIntegrations, externalIntegrations.connectedProviderCount > 0 {
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
                successfulHealthData.append(healthData)
                successCount += 1
                completedDates.append(date)
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
        let rollupFileCount = settings.archiveExportFiles ? 0 : writeRollupSummaries(
            from: rollupHealthData,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let archiveCount = writeArchive(
            from: successfulHealthData,
            rollupHealthData: rollupHealthData,
            selectedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )

        let durableCompletedDates = settings.archiveExportFiles && archiveCount == 0
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
        let formatsPerDate = looseFormatsPerDate(settings: settings)
        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        var successfulHealthData: [HealthData] = []

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
                    wasCancelled: true,
                    completedDates: settings.archiveExportFiles
                        ? terminalNoDataDates(in: failedDateDetails)
                        : completedDates
                )
            }

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection
                )
                partialFailures.append(contentsOf: healthData.partialFailures)

                if !healthData.filtered(by: settings.metricSelection).hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    completedDates.append(date)
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: settings)

                if success {
                    successfulHealthData.append(healthData)
                    successCount += 1
                    completedDates.append(date)
                } else {
                    failedDateDetails.append(FailedDateDetail(
                        date: date,
                        reason: .fileWriteError,
                        errorDetails: vaultManager.lastExportStatus
                    ))
                }
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
        let rollupFileCount = settings.archiveExportFiles ? 0 : writeRollupSummaries(
            from: rollupHealthData,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let archiveCount = writeArchive(
            from: successfulHealthData,
            rollupHealthData: rollupHealthData,
            selectedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )

        let durableCompletedDates = settings.archiveExportFiles && archiveCount == 0
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
            completedDates: durableCompletedDates
        )
    }

    // MARK: - ZIP Archive Export

    private static func looseFormatsPerDate(settings: AdvancedExportSettings) -> Int {
        settings.archiveExportFiles || settings.summaryOnlyModeEnabled ? 0 : settings.exportFormats.count
    }

    private static func writeArchive(
        from successfulHealthData: [HealthData],
        rollupHealthData: [HealthData],
        selectedDates: [Date],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        partialFailures: inout [ExportPartialFailure]
    ) -> Int {
        guard settings.archiveExportFiles else { return 0 }
        guard !settings.exportFormats.isEmpty else { return 0 }
        guard !successfulHealthData.isEmpty || (settings.summaryOnlyModeEnabled && !rollupHealthData.isEmpty) else { return 0 }

        let sortedDates = selectedDates.sorted()
        let startDate = sortedDates.first ?? successfulHealthData.map { $0.date }.min() ?? Date()
        let endDate = sortedDates.last ?? successfulHealthData.map { $0.date }.max() ?? startDate
        do {
            return try vaultManager.exportArchive(
                from: successfulHealthData,
                rollupHealthData: rollupHealthData,
                settings: settings,
                startDate: startDate,
                endDate: endDate
            ) == nil ? 0 : 1
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
            return 0
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

        let rollupFileCount = settings.archiveExportFiles ? 0 : writeRollupSummaries(
            from: rollupHealthData,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let archiveCount = writeArchive(
            from: [],
            rollupHealthData: rollupHealthData,
            selectedDates: dates,
            vaultManager: vaultManager,
            settings: settings,
            partialFailures: &partialFailures
        )
        let filesWritten = rollupFileCount + archiveCount

        let isTerminalNoData = filesWritten == 0
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
            completedDates: filesWritten > 0 || isTerminalNoData ? dates : []
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
        partialFailures: inout [ExportPartialFailure]
    ) -> Int {
        guard !rollupHealthData.isEmpty else { return 0 }
        guard HealthRollupExporter.isEnabled(settings: settings) else { return 0 }

        do {
            return try vaultManager.exportRollupSummaries(from: rollupHealthData, settings: settings).count
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
        fileCount: Int? = nil
    ) {
        let history = ExportHistoryManager.shared
        let resolvedFileCount = fileCount ?? result.totalFilesWritten

        if result.successCount > 0 {
            history.recordSuccess(
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails,
                targetLabel: targetLabel,
                fileCount: resolvedFileCount,
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
                fileCount: resolvedFileCount,
                partialFailures: result.partialFailures
            )
        }
    }
}
