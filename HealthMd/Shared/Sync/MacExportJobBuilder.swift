import Foundation

/// Request-scoped connected-export mode. Summary-only jobs may retain the saved
/// Lossless Health Records toggle, but they must never fetch or transfer archives.
enum ConnectedExportGranularMode {
    static func isEnabled(for settings: AdvancedExportSettings) -> Bool {
        settings.includeGranularData && !settings.summaryOnlyModeEnabled
    }

    static func isEnabled(for snapshot: ExportSettingsSnapshot) -> Bool {
        let hasRollups = snapshot.generateWeeklyRollups
            || snapshot.generateMonthlyRollups
            || snapshot.generateYearlyRollups
        let summaryOnlyModeEnabled = snapshot.summaryOnlyExport
            && hasRollups
            && !snapshot.exportFormats.isEmpty
        return snapshot.includeGranularData && !summaryOnlyModeEnabled
    }

    static func sanitized(_ record: HealthData, includesGranularData: Bool) -> HealthData {
        guard !includesGranularData else { return record }
        var sanitized = record
        sanitized.healthKitRecordArchive = nil
        sanitized.healthKitRecordCaptureStatus = .notRequested
        return sanitized
    }
}

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
        requestedDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        destinationDisplayName: String?,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        onProgress: ((_ processed: Int, _ total: Int, _ date: Date) -> Void)? = nil
    ) async throws -> MacExportJob {
        let dates = requestedDates.map {
            Array(Set($0.map { Calendar.current.startOfDay(for: $0) })).sorted()
        } ?? ExportOrchestrator.dateRange(from: startDate, to: endDate)
        let requestedDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        let rollupDates = ExportOrchestrator.rollupSourceDates(for: dates, settings: settings)
        let transferDates = Array(Set(dates + rollupDates)).sorted()
        let settingsSnapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: healthSubfolder
        )
        let includeGranularData = ConnectedExportGranularMode.isEnabled(for: settings)
        var records: [HealthData] = []
        var externalDailyRecords: [ExternalDailyRecord] = []

        for (index, date) in transferDates.enumerated() {
            try Task.checkCancellation()
            onProgress?(index + 1, transferDates.count, date)
            let day = Calendar.current.startOfDay(for: date)
            let shouldIncludeGranularData = requestedDays.contains(day) && includeGranularData
            let fetchedRecord = try await fetchHealthData(date, shouldIncludeGranularData)
            let record = ConnectedExportGranularMode.sanitized(
                fetchedRecord,
                includesGranularData: shouldIncludeGranularData
            )
            records.append(record)

            if record.hasAnyData,
               requestedDays.contains(day),
               !settings.summaryOnlyModeEnabled,
               let fetchExternalDailyRecords {
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
            requestedDates: dates,
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

/// Shared helpers for the chunked iPhone → Mac export stream prototype.
///
/// v1 intentionally uses a small fixed chunk size so each Multipeer transfer is
/// bounded while the Mac-side executor is still evolving. Sequence numbers are
/// 1-based and chunks preserve the same transfer-date ordering used by the
/// whole-job fallback builder.
@MainActor
struct MacExportStreamingJobBuilder {
    /// Fixed number of transfer days per stream chunk for the first protocol version.
    nonisolated static let transferDaysPerChunk = 7
    nonisolated static let chunkStrategyVersion = 1

    struct Metadata {
        let requestedDates: [Date]
        let requestedDays: Set<Date>
        let transferDates: [Date]
        let settingsSnapshot: ExportSettingsSnapshot
        let requestedTarget: ExportTargetSnapshot

        var dateRangeStart: Date { requestedDates.first ?? Date() }
        var dateRangeEnd: Date { requestedDates.last ?? dateRangeStart }
        var totalRequestedDays: Int { requestedDates.count }
        var totalTransferDays: Int { transferDates.count }
    }

    struct Chunk {
        let sequence: Int
        let dates: [Date]
    }

    static func metadata(
        startDate: Date,
        endDate: Date,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        destinationDisplayName: String?
    ) -> Metadata {
        let requestedDates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        let requestedDays = Set(requestedDates.map { Calendar.current.startOfDay(for: $0) })
        let rollupDates = ExportOrchestrator.rollupSourceDates(for: requestedDates, settings: settings)
        let transferDates = Array(Set(requestedDates + rollupDates)).sorted()

        return Metadata(
            requestedDates: requestedDates,
            requestedDays: requestedDays,
            transferDates: transferDates,
            settingsSnapshot: ExportSettingsSnapshot.from(
                settings,
                healthSubfolder: healthSubfolder
            ),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: ExportTargetSelection.connectedMac.title,
                destinationDisplayName: destinationDisplayName
            )
        )
    }

    static func chunks(for transferDates: [Date], chunkSize: Int = transferDaysPerChunk) -> [Chunk] {
        guard chunkSize > 0, !transferDates.isEmpty else { return [] }
        return stride(from: 0, to: transferDates.count, by: chunkSize).enumerated().map { index, start in
            let end = min(start + chunkSize, transferDates.count)
            return Chunk(sequence: index + 1, dates: Array(transferDates[start..<end]))
        }
    }

    static func shouldIncludeGranularData(
        for date: Date,
        metadata: Metadata,
        settings: AdvancedExportSettings
    ) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return metadata.requestedDays.contains(day)
            && ConnectedExportGranularMode.isEnabled(for: settings)
    }
}
