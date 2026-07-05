import Foundation

/// Builds iOS-originated Mac export jobs by capturing the current export settings
/// and fetching one HealthKit record for each requested date.
@MainActor
struct MacExportJobBuilder {
    typealias HealthDataFetcher = (_ date: Date, _ includeGranularData: Bool) async throws -> HealthData
    typealias ExternalDailyRecordFetcher = (_ date: Date) async -> [ExternalDailyRecord]

    static func build(
        jobID: UUID = UUID(),
        createdAt: Date = Date(),
        sourceDeviceName: String,
        startDate: Date,
        endDate: Date,
        settings: AdvancedExportSettings,
        destinationDisplayName: String?,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        onProgress: ((_ processed: Int, _ total: Int, _ date: Date) -> Void)? = nil
    ) async throws -> MacExportJob {
        let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        let requestedDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        let rollupDates = ExportOrchestrator.rollupSourceDates(for: dates, settings: settings)
        let transferDates = Array(Set(dates + rollupDates)).sorted()
        let settingsSnapshot = ExportSettingsSnapshot.from(settings)
        let includeGranularData = settings.includeGranularData
        var records: [HealthData] = []
        var externalDailyRecords: [ExternalDailyRecord] = []

        for (index, date) in transferDates.enumerated() {
            try Task.checkCancellation()
            onProgress?(index + 1, transferDates.count, date)
            let day = Calendar.current.startOfDay(for: date)
            let shouldIncludeGranularData = requestedDays.contains(day) && includeGranularData
            let record = try await fetchHealthData(date, shouldIncludeGranularData)
            records.append(record)

            if requestedDays.contains(day), !settings.summaryOnlyModeEnabled, let fetchExternalDailyRecords {
                let providerRecords = await fetchExternalDailyRecords(date)
                externalDailyRecords.append(contentsOf: providerRecords.filter(\.shouldExport))
            }
        }

        return MacExportJob(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: sourceDeviceName,
            dateRangeStart: dates.first ?? Calendar.current.startOfDay(for: startDate),
            dateRangeEnd: dates.last ?? Calendar.current.startOfDay(for: endDate),
            records: records,
            externalDailyRecords: externalDailyRecords,
            settingsSnapshot: settingsSnapshot,
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: ExportTargetSelection.connectedMac.title,
                destinationDisplayName: destinationDisplayName
            )
        )
    }
}
