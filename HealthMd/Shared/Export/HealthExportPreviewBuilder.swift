import Foundation

/// Health.md adapter around ExportKit's generic preview builder.
///
/// ExportKit owns the record-fetch/render/plan loop and generic planned files.
/// Health.md owns health-specific filtering, Daily Note Injection previews,
/// individual-entry extraction, and warning copy.
enum HealthExportPreviewBuilder {
    static let dailyNoteInjectionPluginID = HealthExportPluginIDs.dailyNoteInjection
    static let individualEntryPluginID = HealthExportPluginIDs.individualEntry

    @MainActor
    static func buildPreview(
        startDate: Date,
        endDate: Date,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        destinationRootName: String?,
        targetType: PricingAnalyticsExportTargetType,
        maxRenderedDates: Int = ExportPreviewBuilder<Date, HealthExportRecord>.defaultMaxRenderedRecords,
        maxFetchAttempts: Int = ExportPreviewBuilder<Date, HealthExportRecord>.defaultMaxFetchAttempts,
        fetchHealthData: @escaping (Date) async -> HealthData?
    ) async throws -> ExportPreview {
        let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        return try await buildPreview(
            dates: dates,
            vaultManager: vaultManager,
            settings: settings,
            destinationRootName: destinationRootName,
            targetType: targetType,
            maxRenderedDates: maxRenderedDates,
            maxFetchAttempts: maxFetchAttempts,
            fetchHealthData: fetchHealthData
        )
    }

    @MainActor
    static func buildPreview(
        dates: [Date],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        destinationRootName: String?,
        targetType: PricingAnalyticsExportTargetType,
        maxRenderedDates: Int = ExportPreviewBuilder<Date, HealthExportRecord>.defaultMaxRenderedRecords,
        maxFetchAttempts: Int = ExportPreviewBuilder<Date, HealthExportRecord>.defaultMaxFetchAttempts,
        fetchHealthData: @escaping (Date) async -> HealthData?
    ) async throws -> ExportPreview {
        let registry = HealthExportRendererAdapter.registry(settings: settings)
        let selectedFormatIDs = settings.sortedExportFormats.map(\.exportKitFormatID)
        let healthSubfolder = vaultManager.healthSubfolder
        let vaultURL = vaultManager.vaultURL
        _ = destinationRootName // Destination display names remain UI-owned; plugins only need paths.
        let pluginRunner = ExportPluginRunner(plugins: HealthExportPluginAdapter.makePlugins(
            settings: settings,
            healthSubfolder: healthSubfolder,
            dailyNotePreviewBaseResolver: { date in
                dailyNotePreviewBase(
                    for: date,
                    vaultURL: vaultURL,
                    settings: settings.dailyNoteInjection,
                    targetType: targetType,
                    vaultManager: vaultManager
                )
            }
        ))

        let request = ExportPreviewRequest<Date, HealthExportRecord>(
            recordInputs: dates,
            selectedFormatIDs: selectedFormatIDs,
            dataSource: AnyExportRecordDataSource { date in
                guard let healthData = await fetchHealthData(date) else {
                    return ExportFetchedRecord(record: nil)
                }

                let warnings = healthData.partialFailures.enumerated().map { offset, failure in
                    ExportWarning(
                        id: "healthmd.preview.partial.\(healthData.date.timeIntervalSince1970).\(offset).\(failure.dataType)",
                        message: failure.summary
                    )
                }

                guard healthData.filtered(by: settings.metricSelection).hasAnyData else {
                    return ExportFetchedRecord(record: nil, warnings: warnings)
                }

                return ExportFetchedRecord(record: HealthExportRecord(healthData: healthData), warnings: warnings)
            },
            rendererRegistry: registry,
            recordReference: { date in
                ExportRecordReference(
                    id: HealthExportRecord(healthData: HealthData(date: date)).exportRecordID,
                    date: date,
                    displayName: dateLabelFormatter.string(from: date)
                )
            },
            planAggregateFile: { record, descriptor, rendered in
                try HealthAggregateExportAdapter.plannedAggregateFile(
                    record: record,
                    descriptor: descriptor,
                    rendered: rendered,
                    settings: settings,
                    healthSubfolder: healthSubfolder,
                    safetyPolicy: .preserveCurrentBehavior
                )
            },
            supplementalFilePlanner: { record, aggregateFiles in
                try await MainActor.run {
                    let context = ExportPluginContext(
                        record: record,
                        operation: .preview,
                        aggregateFiles: aggregateFiles,
                        writeMode: .overwrite
                    )
                    return try pluginRunner.previewSupplementalPlan(record: record, context: context)
                }
            }
        )

        let builder = ExportPreviewBuilder<Date, HealthExportRecord>(
            maxRenderedRecords: maxRenderedDates,
            maxFetchAttempts: maxFetchAttempts
        )
        return try await builder.buildPreview(request)
    }


    @MainActor
    private static func dailyNotePreviewBase(
        for date: Date,
        vaultURL: URL?,
        settings: DailyNoteInjectionSettings,
        targetType: PricingAnalyticsExportTargetType,
        vaultManager: VaultManager
    ) -> HealthDailyNotePreviewBaseResolution {
        guard targetType == .localFile,
              let vaultURL,
              let localURL = try? ExportPathPlanner.safeDailyNoteURL(
                vaultURL: vaultURL,
                settings: settings,
                date: date
              ) else {
            return .resolved(.emptyDocument)
        }

        vaultManager.startVaultAccess()
        defer { vaultManager.stopVaultAccess() }

        if FileManager.default.fileExists(atPath: localURL.path) {
            do {
                return .resolved(.existingContent(try String(contentsOf: localURL, encoding: .utf8)))
            } catch {
                return .unreadable(error)
            }
        }

        return settings.createIfMissing ? .resolved(.emptyDocument) : .missing
    }


    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()
}
