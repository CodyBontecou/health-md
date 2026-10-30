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

    struct AcceptedFileCapture {
        let snapshot: ExportSettingsSnapshot
        let settings: AdvancedExportSettings
        let context: AppleSleepCaptureContext
        let providers: (any ExternalIntegrationDailyRecordProviding)?
        let fetchExternalRecords: MacExportJobBuilder.ExternalDailyRecordFetcher?
    }

    /// Accept configuration and provider grants before renderer qualification can suspend.
    static func prepareFileCapture(
        settings: AdvancedExportSettings,
        savedSnapshot: ExportSettingsSnapshot? = nil,
        healthSubfolder: String,
        protocolVersion: Int,
        healthKitManager: HealthKitManager,
        providers: (any ExternalIntegrationDailyRecordProviding)?,
        legacyFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher? = nil,
        needsCapture: Bool = true
    ) async throws -> AcceptedFileCapture {
        let context = try savedSnapshot?.recoveredSleepCaptureContext()
            ?? healthKitManager.resolveSleepCaptureContext(settings: settings)
        var snapshot = savedSnapshot ?? ExportSettingsSnapshot.from(settings, healthSubfolder: healthSubfolder,
            appleExportEngineAuthorityIsFrozen: false, calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier)
        snapshot.sleepCaptureContext = context
        let wantsSidecars = needsCapture && snapshot.makeAdvancedExportSettings().writesExternalProviderSidecars
        let frozenAuthority = savedSnapshot != nil || settings.executionExternalProviderCaptureAuthorityIsFrozen
        let accepted: (any ExternalIntegrationDailyRecordProviding)?
        var usesLegacyFetcher = false
        if !wantsSidecars {
            accepted = nil
            if savedSnapshot == nil { snapshot.externalProviderCaptureAuthority = .init(connections: [:]) }
        } else if let authority = snapshot.externalProviderCaptureAuthority {
            accepted = try restoreProviders(authority: authority, providers: providers)
        } else if frozenAuthority && context.sleepDayAttribution == .morningEnds {
            throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
        } else {
            if context.sleepDayAttribution == .morningEnds, legacyFetcher != nil, providers == nil {
                throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
            }
            accepted = ConnectedAppsFeature.isEnabled ? providers?.forCaptureOperation() : nil
            usesLegacyFetcher = accepted == nil && legacyFetcher != nil && context.sleepDayAttribution == .nightBegins
            let count = accepted?.connectedProviderCount ?? 0
            let capturedAuthority = accepted?.captureAuthority
            if let capturedAuthority {
                snapshot.externalProviderCaptureAuthority = capturedAuthority
            } else if count == 0 && !usesLegacyFetcher {
                snapshot.externalProviderCaptureAuthority = ExternalProviderCaptureAuthority(connections: [:])
            } else {
                snapshot.externalProviderCaptureAuthority = nil
            }
            if context.sleepDayAttribution == .morningEnds, snapshot.externalProviderCaptureAuthority == nil {
                throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
            }
        }
        let frozen = snapshot.makeAdvancedExportSettings()
        let fetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
        if let accepted, accepted.connectedProviderCount > 0 {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = context.timeZone
            fetcher = { await accepted.fetchDailyRecords(for: $0, calendar: calendar) }
        } else { fetcher = usesLegacyFetcher ? legacyFetcher : nil }
        if savedSnapshot == nil {
            snapshot = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(frozen,
                healthSubfolder: healthSubfolder, calendarTimeZone: context.timeZone,
                hasNativeOnlyCompanionAction: fetcher != nil,
                operationSurface: MacExportStreamingJobBuilder.connectedOperationSurface(protocolVersion: protocolVersion))
        }
        return AcceptedFileCapture(snapshot: snapshot, settings: snapshot.makeAdvancedExportSettings(),
            context: context, providers: accepted, fetchExternalRecords: fetcher)
    }

    static func restoreProviders(authority: ExternalProviderCaptureAuthority,
                                 providers: (any ExternalIntegrationDailyRecordProviding)?) throws -> (any ExternalIntegrationDailyRecordProviding)? {
        guard !authority.connections.isEmpty else { return nil }
        guard let providers else { throw ExternalProviderCaptureAuthority.RecoveryError.unavailable }
        let accepted = try providers.forCaptureOperation(authority: authority)
        guard accepted.captureAuthority == authority else { throw ExternalProviderCaptureAuthority.RecoveryError.unavailable }
        return accepted
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
        externalIntegrations: (any ExternalIntegrationDailyRecordProviding)? = nil,
        syncService: SyncService,
        origin: ConnectedCorpusOutboundOrigin = .interactiveIPhone,
        progress: ((IPhoneConnectedCorpusProgressUpdate) -> Void)? = nil
    ) async throws -> Result {
        let restoredJournal = IPhoneCorpusExportRecoveryManager.shared.journal(jobID: jobID)
        let savedSnapshot = restoredJournal?.exportManifest.settingsSnapshot ?? frozenSettingsSnapshot
        let capture = try await prepareFileCapture(settings: settings, savedSnapshot: savedSnapshot,
            healthSubfolder: savedSnapshot?.healthSubfolder ?? healthSubfolder,
            protocolVersion: negotiation.protocolVersion, healthKitManager: healthKitManager,
            providers: externalIntegrations, legacyFetcher: externalRecordFetcher,
            needsCapture: restoredJournal.map { $0.nextItemIndex < $0.totalItemCount } ?? true)
        let captureContext = capture.context
        let settings = capture.settings
        let externalRecordFetcher = capture.fetchExternalRecords
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
        let savedManifest = restoredJournal?.exportManifest
        let metadata = MacExportStreamingJobBuilder.metadata(
            startDate: savedManifest?.dateRangeStart ?? startDate,
            endDate: savedManifest?.dateRangeEnd ?? endDate,
            requestedDates: savedManifest?.requestedDates ?? requestedDates,
            rollupRequestedDates: savedManifest?.effectiveOriginalRequestedDates ?? originalRequestedDates,
            settings: settings, healthSubfolder: capture.snapshot.healthSubfolder ?? healthSubfolder,
            destinationDisplayName: savedManifest?.requestedTarget?.destinationDisplayName ?? destinationDisplayName,
            frozenSettingsSnapshot: capture.snapshot)
        capture.providers?.beginExportAction()
        var providerActionSucceeded = false
        defer { capture.providers?.endExportAction(succeeded: providerActionSucceeded) }
        let createdAt = Date()
        let sourceTimeZone = captureContext.timeZone
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = sourceCalendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = sourceTimeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var operationSnapshot = metadata.settingsSnapshot
        operationSnapshot.sleepCaptureContext = captureContext
        let exportManifest = savedManifest ?? ConnectedCorpusExportManifest(
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
            settingsSnapshot: operationSnapshot,
            appleExportEnginePin: metadata.settingsSnapshot.appleExportEnginePin,
            requestedTarget: metadata.requestedTarget
        )
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
            let detailPolicy = MacExportStreamingJobBuilder.detailPolicy(
                for: date,
                metadata: metadata,
                settings: settings
            )
            progress?(.prepared(
                itemIndex: index,
                totalDays: metadata.totalTransferDays,
                date: date,
                includesGranularData: detailPolicy.includesCanonicalArchive,
                transferredDays: transferredDays
            ))
        }
        let produceItem: ConnectedCorpusDurableSender.ItemProducer = { index, date in
            try Task.checkCancellation()
            let day = sourceCalendar.startOfDay(for: date)
            let isRequested = metadata.requestedDays.contains(day)
            let detailPolicy = MacExportStreamingJobBuilder.detailPolicy(
                for: date,
                metadata: metadata,
                settings: settings
            )
            progress?(.preparing(
                itemIndex: index,
                totalDays: metadata.totalTransferDays,
                date: date,
                includesGranularData: detailPolicy.includesCanonicalArchive,
                transferredDays: transferredDays
            ))
            let outcome = try await HealthKitDailyCapture.capture(
                date: date,
                detailPolicy: detailPolicy,
                metricSelection: settings.metricSelection,
                transform: .sanitizeGranular,
                emptyRecordPolicy: .retain,
                fetchExternalRecords: isRequested && !settings.summaryOnlyModeEnabled,
                failurePolicy: .connectedMac,
                fetchHealthData: { date, detailPolicy, metricSelection in
                    try await healthKitManager.fetchHealthData(
                        for: date,
                        detailPolicy: detailPolicy,
                        metricSelection: metricSelection,
                        timeZone: sourceTimeZone,
                        captureContext: captureContext
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
            providerActionSucceeded = senderResult.acknowledgement.accepted
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
        providerActionSucceeded = senderResult.acknowledgement.accepted
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
