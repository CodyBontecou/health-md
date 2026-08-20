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
        originalRequestedDates: [Date]? = nil,
        originalCalendarTimeZoneIdentifier: String? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        destinationDisplayName: String?,
        frozenSettingsSnapshot: ExportSettingsSnapshot? = nil,
        negotiation: ConnectedCorpusTransferNegotiation,
        healthKitManager: HealthKitManager,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        origin: ConnectedCorpusOutboundOrigin = .interactiveIPhone,
        progress: ((IPhoneConnectedCorpusProgressUpdate) -> Void)? = nil
    ) async throws -> Result {
        #if DEBUG
        let performanceSpan = ExportPerformanceInstrumentation.beginSpan(
            pipeline: "connected-mac",
            phase: "iphone-producer"
        )
        var performanceOutcome = ExportPerformanceSpanOutcome.failure
        defer {
            performanceSpan.finish(
                outcome: Task.isCancelled ? .cancelled : performanceOutcome
            )
        }
        #endif
        let metadata: MacExportStreamingJobBuilder.Metadata
        if let frozenSettingsSnapshot {
            metadata = MacExportStreamingJobBuilder.metadata(
                startDate: startDate,
                endDate: endDate,
                requestedDates: requestedDates,
                rollupRequestedDates: originalRequestedDates,
                settings: settings,
                healthSubfolder: healthSubfolder,
                destinationDisplayName: destinationDisplayName,
                frozenSettingsSnapshot: frozenSettingsSnapshot
            )
        } else {
            metadata = await MacExportStreamingJobBuilder.metadataForNewOperation(
                startDate: startDate,
                endDate: endDate,
                requestedDates: requestedDates,
                rollupRequestedDates: originalRequestedDates,
                settings: settings,
                healthSubfolder: healthSubfolder,
                destinationDisplayName: destinationDisplayName,
                enforceConnectedOperationGate: true,
                connectedOperationSurface: MacExportStreamingJobBuilder.connectedOperationSurface(
                    protocolVersion: negotiation.protocolVersion
                ),
                hasNativeOnlyCompanionAction: settings.writesExternalProviderSidecars
                    && externalRecordFetcher != nil
            )
        }
        let createdAt = Date()
        let sourceTimeZone = metadata.settingsSnapshot.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? settings.exportTimeZoneOverride
            ?? .current
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = sourceCalendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = sourceTimeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let exportManifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: createdAt,
            sourceDeviceName: UIDevice.current.name,
            sourceTimeZoneIdentifier: sourceTimeZone.identifier,
            dateRangeStart: metadata.dateRangeStart,
            dateRangeEnd: metadata.dateRangeEnd,
            requestedDates: metadata.requestedDates,
            originalRequestedDates: originalRequestedDates ?? metadata.requestedDates,
            originalCalendarTimeZoneIdentifier: originalCalendarTimeZoneIdentifier
                ?? sourceTimeZone.identifier,
            requestedDateIdentifiers: metadata.requestedDates.map { dateFormatter.string(from: $0) },
            transferDates: metadata.transferDates,
            settingsSnapshot: metadata.settingsSnapshot,
            appleExportEnginePin: metadata.settingsSnapshot.appleExportEnginePin,
            requestedTarget: metadata.requestedTarget
        )
        let restoredJournal = IPhoneCorpusExportRecoveryManager.shared.journal(jobID: jobID)
        var preparedDays = min(
            max(restoredJournal?.nextItemIndex ?? 0, 0),
            metadata.totalTransferDays
        )
        var transferredDays = min(
            max(restoredJournal?.completedItemCount ?? 0, 0),
            preparedDays
        )
        let reportPreparedItem: (Int, Date) -> Void = { index, date in
            preparedDays = max(preparedDays, index + 1)
            progress?(.prepared(
                itemIndex: index,
                totalDays: metadata.totalTransferDays,
                date: date,
                includesGranularData: MacExportStreamingJobBuilder.shouldIncludeGranularData(
                    for: date,
                    metadata: metadata,
                    settings: settings
                ),
                transferredDays: transferredDays
            ))
        }
        let produceItem: ConnectedCorpusDurableSender.ItemProducer = { index, date in
            try Task.checkCancellation()
            let day = sourceCalendar.startOfDay(for: date)
            let isRequested = metadata.requestedDays.contains(day)
            let includesGranularData = MacExportStreamingJobBuilder.shouldIncludeGranularData(
                for: date,
                metadata: metadata,
                settings: settings
            )
            progress?(.preparing(
                itemIndex: index,
                totalDays: metadata.totalTransferDays,
                date: date,
                includesGranularData: includesGranularData,
                transferredDays: transferredDays
            ))
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
                        metricSelection: metricSelection,
                        timeZone: sourceTimeZone
                    )
                },
                fetchExternalDailyRecords: externalRecordFetcher
            )
            let item = try await ConnectedCorpusSpoolItem.encodeHealthDay(
                ConnectedCorpusHealthDayPayload(
                    sourceDate: date,
                    isRequestedDate: isRequested,
                    record: outcome.record,
                    externalDailyRecords: outcome.externalDailyRecords,
                    failure: outcome.failure
                ),
                sourceDate: date,
                isRequestedDate: isRequested,
                protocolVersion: negotiation.protocolVersion
            )
            return item
        }
        let progressHandler: (
            ConnectedCorpusPartitionDescriptor,
            Int,
            Int
        ) -> Void = { descriptor, _, _ in
            guard let date = descriptor.sourceDates.last else { return }
            let dayNumber = (metadata.transferDates.firstIndex(of: date) ?? 0) + 1
            progress?(.transferring(
                preparedDays: preparedDays,
                transferredDays: transferredDays,
                totalDays: metadata.totalTransferDays,
                date: date,
                dayNumber: dayNumber
            ))
        }

        if let remote = syncService.remoteCapabilities,
           let durableNegotiation = syncService.localCapabilities
                .negotiateDurableConnectedCorpusTransfer(with: remote) {
            let senderResult = try await IPhoneCorpusExportRecoveryManager.shared.send(
                origin: origin,
                jobID: jobID,
                manifest: exportManifest,
                durableNegotiation: durableNegotiation,
                syncService: syncService,
                onCheckpoint: { journal in
                    let durablePreparedDays = min(
                        max(journal.nextItemIndex, 0),
                        metadata.totalTransferDays
                    )
                    if durablePreparedDays > preparedDays {
                        reportPreparedItem(
                            durablePreparedDays - 1,
                            metadata.transferDates[durablePreparedDays - 1]
                        )
                    }
                    let durableTransferredDays = min(
                        max(journal.completedItemCount, 0),
                        preparedDays
                    )
                    if durableTransferredDays > transferredDays {
                        transferredDays = durableTransferredDays
                        let date = metadata.transferDates[durableTransferredDays - 1]
                        progress?(.transferring(
                            preparedDays: preparedDays,
                            transferredDays: transferredDays,
                            totalDays: metadata.totalTransferDays,
                            date: date,
                            dayNumber: durableTransferredDays
                        ))
                    }
                },
                onValidatedPartitionProgress: progressHandler,
                produceItem: produceItem
            )
            #if DEBUG
            performanceOutcome = .success
            #endif
            return Result(
                sessionID: senderResult.sessionID,
                acknowledgement: senderResult.acknowledgement
            )
        }

        let senderResult = try await HealthKitQueryExecutionController.withController {
            try await ConnectedCorpusSender.send(
                configuration: ConnectedCorpusSender.Configuration(
                    jobID: jobID,
                    manifest: exportManifest,
                    negotiation: negotiation
                ),
                transport: .syncService(syncService),
                onValidatedPartitionProgress: progressHandler,
                produceItems: { append in
                    for (index, date) in metadata.transferDates.enumerated() {
                        let item = try await produceItem(index, date)
                        try await append(item)
                        reportPreparedItem(index, date)
                    }
                }
            )
        }
        #if DEBUG
        performanceOutcome = .success
        #endif
        return Result(
            sessionID: senderResult.sessionID,
            acknowledgement: senderResult.acknowledgement
        )
    }
}
#endif
