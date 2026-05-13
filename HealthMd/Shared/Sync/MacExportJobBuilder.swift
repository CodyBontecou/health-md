import Foundation

/// Builds iOS-originated Mac export jobs by capturing the current export settings
/// and fetching one HealthKit record for each requested date.
@MainActor
struct MacExportJobBuilder {
    typealias HealthDataFetcher = (_ date: Date, _ includeGranularData: Bool) async throws -> HealthData

    static func build(
        jobID: UUID = UUID(),
        createdAt: Date = Date(),
        sourceDeviceName: String,
        startDate: Date,
        endDate: Date,
        settings: AdvancedExportSettings,
        destinationDisplayName: String?,
        fetchHealthData: HealthDataFetcher,
        onProgress: ((_ processed: Int, _ total: Int, _ date: Date) -> Void)? = nil
    ) async throws -> MacExportJob {
        let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        let settingsSnapshot = ExportSettingsSnapshot.from(settings)
        let includeGranularData = settings.includeGranularData
        var records: [HealthData] = []

        for (index, date) in dates.enumerated() {
            try Task.checkCancellation()
            onProgress?(index + 1, dates.count, date)
            let record = try await fetchHealthData(date, includeGranularData)
            records.append(record)
        }

        return MacExportJob(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: sourceDeviceName,
            dateRangeStart: dates.first ?? Calendar.current.startOfDay(for: startDate),
            dateRangeEnd: dates.last ?? Calendar.current.startOfDay(for: endDate),
            records: records,
            settingsSnapshot: settingsSnapshot,
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: ExportTargetSelection.connectedMac.title,
                destinationDisplayName: destinationDisplayName
            )
        )
    }
}
