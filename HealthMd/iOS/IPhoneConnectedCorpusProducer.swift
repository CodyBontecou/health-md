#if os(iOS)
import Foundation
import UIKit

/// Corpus producer used by iPhone-initiated interactive and scheduled Mac
/// exports. It spools one HealthKit day at a time and transfers only bounded
/// checksum partitions.
@MainActor
enum IPhoneConnectedCorpusProducer {
    struct Result {
        let sessionID: UUID
        let acknowledgement: ConnectedCorpusTransferFinalAck
    }

    static func sendFileExport(
        jobID: UUID,
        startDate: Date,
        endDate: Date,
        requestedDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        destinationDisplayName: String?,
        negotiation: ConnectedCorpusTransferNegotiation,
        healthKitManager: HealthKitManager,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        progress: ((_ processedDays: Int, _ totalDays: Int, _ date: Date, _ message: String) -> Void)? = nil
    ) async throws -> Result {
        let metadata = MacExportStreamingJobBuilder.metadata(
            startDate: startDate,
            endDate: endDate,
            requestedDates: requestedDates,
            settings: settings,
            healthSubfolder: healthSubfolder,
            destinationDisplayName: destinationDisplayName
        )
        let createdAt = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let exportManifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: createdAt,
            sourceDeviceName: UIDevice.current.name,
            sourceTimeZoneIdentifier: TimeZone.current.identifier,
            dateRangeStart: metadata.dateRangeStart,
            dateRangeEnd: metadata.dateRangeEnd,
            requestedDates: metadata.requestedDates,
            requestedDateIdentifiers: metadata.requestedDates.map { dateFormatter.string(from: $0) },
            transferDates: metadata.transferDates,
            settingsSnapshot: metadata.settingsSnapshot,
            requestedTarget: metadata.requestedTarget
        )
        let senderResult = try await ConnectedCorpusSender.send(
            configuration: ConnectedCorpusSender.Configuration(
                jobID: jobID,
                manifest: exportManifest,
                negotiation: negotiation
            ),
            transport: .syncService(syncService),
            onValidatedPartitionProgress: { descriptor, _, _ in
                guard let date = descriptor.sourceDates.last else { return }
                let processed = (metadata.transferDates.firstIndex(of: date) ?? 0) + 1
                progress?(
                    processed,
                    metadata.totalTransferDays,
                    date,
                    "Transferring partitioned corpus data…"
                )
            },
            produceItems: { append in
                for (index, date) in metadata.transferDates.enumerated() {
                    try Task.checkCancellation()
                    progress?(
                        index + 1,
                        metadata.totalTransferDays,
                        date,
                        "Preparing partitioned corpus data…"
                    )
                    let day = Calendar.current.startOfDay(for: date)
                    let isRequested = metadata.requestedDays.contains(day)
                    let includesGranularData = MacExportStreamingJobBuilder.shouldIncludeGranularData(
                        for: date,
                        metadata: metadata,
                        settings: settings
                    )
                    let outcome = try await HealthKitDailyCapture.capture(
                        date: date,
                        includeGranularData: includesGranularData,
                        metricSelection: settings.metricSelection,
                        transform: .sanitizeGranular,
                        emptyRecordPolicy: .retain,
                        fetchExternalRecords: isRequested && !settings.summaryOnlyModeEnabled,
                        failurePolicy: .connectedMac,
                        fetchHealthData: { date, includeGranularData, metricSelection in
                            try await healthKitManager.fetchHealthData(
                                for: date,
                                includeGranularData: includeGranularData,
                                metricSelection: metricSelection
                            )
                        },
                        fetchExternalDailyRecords: externalRecordFetcher
                    )
                    let payload = ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: isRequested,
                        record: outcome.record,
                        externalDailyRecords: outcome.externalDailyRecords,
                        failure: outcome.failure
                    )
                    try await append(try ConnectedCorpusSpoolItem.encode(
                        payload,
                        kind: .macHealthDay,
                        sourceDate: date,
                        isRequestedDate: isRequested
                    ))
                }
            }
        )
        return Result(
            sessionID: senderResult.sessionID,
            acknowledgement: senderResult.acknowledgement
        )
    }
}
#endif
