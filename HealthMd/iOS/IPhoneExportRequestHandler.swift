#if os(iOS)
import Combine
import Foundation
import UIKit

/// Handles Mac-initiated export requests while the iPhone app is open. The Mac
/// controls the date range, but the iPhone remains the HealthKit source of truth.
/// Requests may either use saved iPhone export settings exactly or apply a
/// temporary, non-persisted CLI policy that disables derived roll-up summaries.
@MainActor
final class IPhoneExportRequestHandler: ObservableObject {
    private struct PendingRequest {
        let request: IPhoneExportRequest
        let settings: AdvancedExportSettings
    }

    private var activeRequestID: UUID?
    private var pendingRequests: [UUID: PendingRequest] = [:]
    private var streamAbortMessages: [UUID: String] = [:]
    private var cancelledRequestIDs: Set<UUID> = []
    private var activeCorpusSessionID: UUID?
    private var activeCorpusTransferID: UUID?

    func handle(
        _ request: IPhoneExportRequest,
        syncService: SyncService,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil
    ) async {
        defer {
            if cancelledRequestIDs.remove(request.jobID) != nil {
                pendingRequests.removeValue(forKey: request.jobID)
                streamAbortMessages.removeValue(forKey: request.jobID)
                if activeRequestID == request.jobID { activeRequestID = nil }
                syncService.isSyncing = false
            }
        }

        guard activeRequestID == nil else {
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .requestAlreadyInProgress,
                message: "The iPhone is already preparing another export."
            )))
            return
        }

        if let rawProfile = request.rawProfile {
            guard request.responseMode == .rawJSON,
                  syncService.remoteCapabilities?.platform == .macOS,
                  syncService.remoteCapabilities?.supports(rawProfile: rawProfile) == true else {
                syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                    jobID: request.jobID,
                    reason: .unsupportedPeer,
                    message: "The connected Mac cannot use the requested raw export profile. Update Health.md on both devices."
                )))
                return
            }
        }

        let settings = IPhoneExportRequestSettingsResolver.settings(
            for: request,
            savedSettings: AdvancedExportSettings()
        )
        let healthSubfolder = VaultManager.savedHealthSubfolder()
        let sourceDateFormatter = DateFormatter()
        sourceDateFormatter.calendar = Calendar(identifier: .gregorian)
        sourceDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        sourceDateFormatter.timeZone = .current
        sourceDateFormatter.dateFormat = "yyyy-MM-dd"
        sourceDateFormatter.isLenient = false
        let dates: [Date]
        if let identifiers = request.requestedDateIdentifiers {
            dates = identifiers.compactMap { sourceDateFormatter.date(from: $0) }
            guard dates.count == identifiers.count,
                  dates == dates.sorted(),
                  Set(dates).count == dates.count else {
                syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                    jobID: request.jobID,
                    reason: .invalidDateRange,
                    message: "Requested source dates were malformed or duplicated."
                )))
                return
            }
        } else {
            dates = ExportOrchestrator.dateRange(from: request.dateRangeStart, to: request.dateRangeEnd)
        }
        guard !dates.isEmpty else {
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .invalidDateRange,
                message: "Choose a valid date range."
            )))
            return
        }

        guard healthKitManager.isAuthorized else {
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .healthKitNotAuthorized,
                message: "HealthKit access has not been granted on iPhone."
            )))
            return
        }

        await PurchaseManager.shared.refreshStatus()
        guard PurchaseManager.shared.canExport else {
            PricingAnalyticsClient.shared.trackExportBlockedByQuota(
                context: .macTarget,
                targetType: .connectedMac,
                quotaState: PurchaseManager.shared.analyticsQuotaState
            )
            syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                jobID: request.jobID,
                reason: .exportLimitReached,
                message: "Export limit reached. Unlock Full Access on iPhone to export more."
            )))
            return
        }

        if request.responseMode == .writeFiles {
            guard syncService.canExportToConnectedMac(requiring: settings) else {
                syncService.send(.iphoneExportRejected(IPhoneExportFailure(
                    jobID: request.jobID,
                    reason: .macDestinationUnavailable,
                    message: syncService.macExportReadinessMessage(requiring: settings)
                )))
                return
            }
        }

        activeRequestID = request.jobID
        pendingRequests[request.jobID] = PendingRequest(request: request, settings: settings)
        syncService.isSyncing = true
        syncService.send(.iphoneExportAccepted(IPhoneExportAcknowledgement(
            jobID: request.jobID,
            acceptedAt: Date(),
            message: "iPhone export request accepted."
        )))

        let dateFormatter = sourceDateFormatter
        let enabledExternalIntegrations: ExternalIntegrationDailyRecordProviding? = ConnectedAppsFeature.isEnabled ? externalIntegrations : nil
        let externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
        if let enabledExternalIntegrations, enabledExternalIntegrations.connectedProviderCount > 0 {
            externalRecordFetcher = { date in
                await enabledExternalIntegrations.fetchDailyRecords(for: date)
            }
        } else {
            externalRecordFetcher = nil
        }

        do {
            if (request.responseMode == .writeFiles || request.rawProfile == .canonicalSourceRecordsV1),
               let remote = syncService.remoteCapabilities,
               let negotiation = SyncPeerCapabilities.current(platform: .iOS)
                    .negotiateConnectedCorpusTransfer(with: remote) {
                try await sendPartitionedCorpusExport(
                    for: request,
                    dates: dates,
                    settings: settings,
                    healthSubfolder: healthSubfolder,
                    healthKitManager: healthKitManager,
                    externalRecordFetcher: externalRecordFetcher,
                    syncService: syncService,
                    dateFormatter: dateFormatter,
                    negotiation: negotiation
                )
                return
            }

            switch request.responseMode {
            case .writeFiles:
                if syncService.remoteCapabilities?.supportsSizeBoundedConnectedTransfers == true {
                    try await sendSizeBoundedMacExportJob(
                        for: request,
                        settings: settings,
                        healthSubfolder: healthSubfolder,
                        healthKitManager: healthKitManager,
                        externalRecordFetcher: externalRecordFetcher,
                        syncService: syncService,
                        dateFormatter: dateFormatter
                    )
                    return
                }

                if syncService.remoteCapabilities?.supportsChunkedMacExportJobs == true {
                    try await streamMacExportJob(
                        for: request,
                        settings: settings,
                        healthSubfolder: healthSubfolder,
                        healthKitManager: healthKitManager,
                        externalRecordFetcher: externalRecordFetcher,
                        syncService: syncService,
                        dateFormatter: dateFormatter
                    )
                    return
                }

                let job = try await MacExportJobBuilder.build(
                    jobID: request.jobID,
                    sourceDeviceName: UIDevice.current.name,
                    startDate: request.dateRangeStart,
                    endDate: request.dateRangeEnd,
                    settings: settings,
                    healthSubfolder: healthSubfolder,
                    destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                    fetchHealthData: { date, includeGranularData in
                        guard !self.cancelledRequestIDs.contains(request.jobID),
                              self.activeRequestID == request.jobID else {
                            throw CancellationError()
                        }
                        let record = try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: settings.metricSelection
                        )
                        guard !self.cancelledRequestIDs.contains(request.jobID),
                              self.activeRequestID == request.jobID else {
                            throw CancellationError()
                        }
                        return record
                    },
                    fetchExternalDailyRecords: externalRecordFetcher,
                    onProgress: { processed, total, date in
                        syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                            jobID: request.jobID,
                            processedDays: processed,
                            totalDays: total,
                            currentDate: date,
                            message: "Preparing \(dateFormatter.string(from: date)) on iPhone…"
                        )))
                    }
                )

                guard activeRequestID == request.jobID else { return }
                guard syncService.canExportToConnectedMac(requiring: settings) else {
                    failPreparation(
                        jobID: request.jobID,
                        syncService: syncService,
                        reason: .macDestinationUnavailable,
                        message: syncService.macExportReadinessMessage(requiring: settings)
                    )
                    return
                }

                guard syncService.sendLargePayload(.macExportRequest(job)) else {
                    failPreparation(
                        jobID: request.jobID,
                        syncService: syncService,
                        reason: .unknown,
                        message: syncService.lastError ?? "Failed to send export payload to the connected Mac."
                    )
                    return
                }
            case .rawJSON:
                let payload = try await buildRawDataPayload(
                    for: request,
                    dates: dates,
                    settings: settings,
                    healthSubfolder: healthSubfolder,
                    healthKitManager: healthKitManager,
                    externalIntegrations: enabledExternalIntegrations,
                    syncService: syncService,
                    dateFormatter: dateFormatter
                )
                guard activeRequestID == request.jobID else { return }

                if request.rawProfile == .canonicalSourceRecordsV1 {
                    guard let strictResult = payload.strictResult,
                          syncService.remoteCapabilities?.supportsStrictRawStreaming == true,
                          syncService.remoteCapabilities?.supportsSizeBoundedConnectedTransfers == true else {
                        failPreparation(
                            jobID: request.jobID,
                            syncService: syncService,
                            reason: .unsupportedPeer,
                            message: "The connected Mac cannot accept strict raw streaming. Update Health.md on both devices."
                        )
                        return
                    }
                    let preparedFile = try ConnectedTransferFile.encode(strictResult)
                    defer { preparedFile.remove() }
                    let transferResult = await syncService.sendConnectedTransfer(
                        preparedFile,
                        manifest: ConnectedTransferManifest(
                            kind: .canonicalRawResultV1,
                            jobID: request.jobID,
                            payloadSchemaVersion: CanonicalRawResultEnvelope.currentSchemaVersion
                        )
                    )
                    guard activeRequestID == request.jobID else { return }
                    switch transferResult {
                    case .success:
                        // Usage is recorded only after the Mac's final acceptance ACK.
                        completeRawRequest(payload, settings: settings, syncService: syncService)
                    case .failure(let abort):
                        failPreparation(
                            jobID: request.jobID,
                            syncService: syncService,
                            reason: abort.reason == .cancelled ? .cancelled : .unknown,
                            message: abort.message
                        )
                    }
                    return
                }

                // Legacy raw mode is intentionally unchanged.
                guard syncService.sendLargePayload(.iphoneExportRawData(payload)) else {
                    failPreparation(
                        jobID: request.jobID,
                        syncService: syncService,
                        reason: .unknown,
                        message: syncService.lastError ?? "Failed to send raw export payload to the connected Mac."
                    )
                    return
                }
                completeRawRequest(payload, settings: settings, syncService: syncService)
            }
        } catch is CancellationError {
            if !cancelledRequestIDs.contains(request.jobID) {
                failPreparation(
                    jobID: request.jobID,
                    syncService: syncService,
                    reason: .cancelled,
                    message: "iPhone export request was cancelled."
                )
            }
        } catch let error as HealthKitManager.HealthKitError {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .healthKitFetchFailed,
                message: HealthKitDailyCapture.failureMessage(for: error, policy: .connectedMac)
            )
        } catch {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .healthKitFetchFailed,
                message: "Failed to prepare HealthKit data on iPhone."
            )
        }
    }

    @discardableResult
    func complete(with payload: MacExportResultPayload) -> Bool {
        guard let pending = pendingRequests.removeValue(forKey: payload.jobID) else { return false }
        streamAbortMessages.removeValue(forKey: payload.jobID)
        activeRequestID = nil

        let result = ExportOrchestrator.ExportResult(
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            failedDateDetails: payload.failedDateDetails,
            formatsPerDate: payload.formatsPerDate,
            externalRecordFileCount: payload.externalRecordFileCount,
            dailyNoteUpdateCount: payload.dailyNoteUpdateCount,
            dailyNoteSkipCount: payload.dailyNoteSkipCount,
            wasCancelled: payload.status == .cancelled
        )

        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: pending.request.dateRangeStart,
            dateRangeEnd: pending.request.dateRangeEnd,
            targetLabel: payload.destinationDisplayName ?? "Mac",
            fileCount: payload.totalFilesWritten
        )

        if payload.successCount > 0 {
            PurchaseManager.shared.recordExportUse()
            PricingAnalyticsClient.shared.trackExportSucceeded(
                metadata: PricingAnalyticsExportMetadata(
                    targetType: .connectedMac,
                    formatCount: pending.settings.exportFormats.count,
                    metricCount: pending.settings.metricSelection.totalEnabledCount,
                    dateRangePreset: PricingAnalyticsDateRangePreset.custom,
                    startDate: pending.request.dateRangeStart,
                    endDate: pending.request.dateRangeEnd
                ),
                quotaState: PurchaseManager.shared.analyticsQuotaState
            )
        }
        return true
    }

    @discardableResult
    func complete(with failure: MacExportFailure) -> Bool {
        guard let jobID = failure.jobID,
              let pending = pendingRequests.removeValue(forKey: jobID) else { return false }
        streamAbortMessages.removeValue(forKey: jobID)
        activeRequestID = nil

        let failedDetail = FailedDateDetail(
            date: pending.request.dateRangeStart,
            reason: exportFailureReason(for: failure.reason),
            errorDetails: failure.underlyingError ?? failure.message
        )
        let result = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: max(ExportOrchestrator.dateRange(from: pending.request.dateRangeStart, to: pending.request.dateRangeEnd).count, 1),
            failedDateDetails: [failedDetail],
            formatsPerDate: pending.settings.looseFormatsPerDate,
            wasCancelled: failure.reason == .cancelled
        )
        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: pending.request.dateRangeStart,
            dateRangeEnd: pending.request.dateRangeEnd,
            targetLabel: "Mac",
            fileCount: 0
        )
        return true
    }

    func completeRejected(jobID: UUID?) {
        guard let jobID else { return }
        pendingRequests.removeValue(forKey: jobID)
        streamAbortMessages.removeValue(forKey: jobID)
        if activeRequestID == jobID { activeRequestID = nil }
    }

    @discardableResult
    func handleStreamChunkAck(_ ack: MacExportStreamChunkAck) -> Bool {
        guard activeRequestID == ack.jobID || pendingRequests[ack.jobID] != nil else { return false }
        guard !ack.accepted else { return true }
        streamAbortMessages[ack.jobID] = ack.message ?? "Mac rejected stream chunk \(ack.sequence)."
        return true
    }

    @discardableResult
    func handleConnectedTransferAbort(_ abort: ConnectedTransferAbort, syncService: SyncService) -> Bool {
        guard let jobID = abort.jobID,
              activeRequestID == jobID || pendingRequests[jobID] != nil else { return false }
        streamAbortMessages[jobID] = abort.message
        syncService.cancelConnectedTransferWaiters(transferID: abort.transferID)
        return true
    }

    @discardableResult
    func cancel(jobID: UUID, syncService: SyncService) -> Bool {
        guard activeRequestID == jobID || pendingRequests[jobID] != nil else { return false }
        cancelledRequestIDs.insert(jobID)
        streamAbortMessages[jobID] = "Mac cancelled the iPhone export request."
        syncService.cancelMacExportStreamAckWaiters(jobID: jobID)
        syncService.cancelConnectedTransferWaiters(transferID: jobID)
        if let transferID = activeCorpusTransferID {
            syncService.cancelConnectedTransferWaiters(transferID: transferID)
        }
        if let sessionID = activeCorpusSessionID {
            syncService.send(.connectedCorpusTransferCancelAck(ConnectedCorpusTransferCancelAck(
                sessionID: sessionID,
                jobID: jobID,
                accepted: true,
                acknowledgedAt: Date(),
                message: "iPhone stopped the corpus producer at a partition checkpoint."
            )))
        }
        activeCorpusTransferID = nil
        activeCorpusSessionID = nil
        syncService.send(.connectedTransferAbort(ConnectedTransferAbort(
            transferID: jobID,
            jobID: jobID,
            reason: .cancelled,
            message: "Mac cancelled the iPhone export request."
        )))
        pendingRequests.removeValue(forKey: jobID)
        if activeRequestID == jobID { activeRequestID = nil }
        return true
    }

    private func sendPartitionedCorpusExport(
        for request: IPhoneExportRequest,
        dates: [Date],
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        healthKitManager: HealthKitManager,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        dateFormatter: DateFormatter,
        negotiation: ConnectedCorpusTransferNegotiation
    ) async throws {
        let createdAt = Date()
        let mode: ConnectedCorpusExportMode = request.responseMode == .writeFiles ? .writeFiles : .strictRaw
        let metadata: MacExportStreamingJobBuilder.Metadata?
        let transferDates: [Date]
        let requestedDates: [Date]
        let settingsSnapshot: ExportSettingsSnapshot
        let requestedTarget: ExportTargetSnapshot?
        if mode == .writeFiles {
            let built = MacExportStreamingJobBuilder.metadata(
                startDate: request.dateRangeStart,
                endDate: request.dateRangeEnd,
                requestedDates: dates,
                settings: settings,
                healthSubfolder: healthSubfolder,
                destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName
            )
            metadata = built
            transferDates = built.transferDates
            requestedDates = built.requestedDates
            settingsSnapshot = built.settingsSnapshot
            requestedTarget = built.requestedTarget
        } else {
            metadata = nil
            transferDates = dates
            requestedDates = dates
            settingsSnapshot = ExportSettingsSnapshot.from(settings, healthSubfolder: healthSubfolder)
            requestedTarget = nil
        }

        let exportManifest = ConnectedCorpusExportManifest(
            mode: mode,
            createdAt: createdAt,
            sourceDeviceName: UIDevice.current.name,
            sourceTimeZoneIdentifier: TimeZone.current.identifier,
            dateRangeStart: requestedDates.first ?? request.dateRangeStart,
            dateRangeEnd: requestedDates.last ?? request.dateRangeEnd,
            requestedDates: requestedDates,
            requestedDateIdentifiers: request.requestedDateIdentifiers
                ?? requestedDates.map { dateFormatter.string(from: $0) },
            transferDates: transferDates,
            settingsSnapshot: settingsSnapshot,
            requestedTarget: requestedTarget
        )
        defer {
            activeCorpusTransferID = nil
            activeCorpusSessionID = nil
        }

        let requestedDaySet = Set(requestedDates.map { Calendar.current.startOfDay(for: $0) })
        let senderResult = try await ConnectedCorpusSender.send(
            configuration: ConnectedCorpusSender.Configuration(
                jobID: request.jobID,
                manifest: exportManifest,
                negotiation: negotiation
            ),
            transport: .syncService(syncService),
            checkCancellation: { [self] in
                try Task.checkCancellation()
                guard !self.cancelledRequestIDs.contains(request.jobID),
                      self.activeRequestID == request.jobID else {
                    throw CancellationError()
                }
            },
            onStateChange: { [self] state in
                switch state {
                case .sessionStarted(let sessionID):
                    self.activeCorpusSessionID = sessionID
                case .partitionStarted(let transferID, _):
                    self.activeCorpusTransferID = transferID
                case .partitionFinished(let transferID, _):
                    if self.activeCorpusTransferID == transferID {
                        self.activeCorpusTransferID = nil
                    }
                case .finished:
                    self.activeCorpusTransferID = nil
                }
            },
            onValidatedPartitionProgress: { descriptor, _, _ in
                let currentDate = descriptor.sourceDates.last
                let processedDays = currentDate.flatMap { transferDates.firstIndex(of: $0) }
                    .map { $0 + 1 } ?? 0
                syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                    jobID: request.jobID,
                    processedDays: processedDays,
                    totalDays: transferDates.count,
                    currentDate: currentDate,
                    message: "Transferring corpus partition \(descriptor.index + 1)…"
                )))
            },
            produceItems: { append in
                for (index, date) in transferDates.enumerated() {
                    try Task.checkCancellation()
                    guard !cancelledRequestIDs.contains(request.jobID),
                          activeRequestID == request.jobID else {
                        throw CancellationError()
                    }
                    syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                        jobID: request.jobID,
                        processedDays: index + 1,
                        totalDays: transferDates.count,
                        currentDate: date,
                        message: "Preparing \(dateFormatter.string(from: date)) for corpus transfer…"
                    )))

                    let item: ConnectedCorpusSpoolItem
                    switch mode {
                    case .writeFiles:
                        let day = Calendar.current.startOfDay(for: date)
                        let isRequested = requestedDaySet.contains(day)
                        let shouldIncludeGranular = metadata.map {
                            MacExportStreamingJobBuilder.shouldIncludeGranularData(
                                for: date,
                                metadata: $0,
                                settings: settings
                            )
                        } ?? false
                        let outcome = try await HealthKitDailyCapture.capture(
                            date: date,
                            includeGranularData: shouldIncludeGranular,
                            metricSelection: settings.metricSelection,
                            transform: .sanitizeGranular,
                            emptyRecordPolicy: .retain,
                            fetchExternalRecords: isRequested && settings.writesExternalProviderSidecars,
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
                        item = try ConnectedCorpusSpoolItem.encode(
                            payload,
                            kind: .macHealthDay,
                            sourceDate: date,
                            isRequestedDate: isRequested
                        )

                    case .strictRaw:
                        let dateString = dateFormatter.string(from: date)
                        let outcome = try await HealthKitDailyCapture.capture(
                            date: date,
                            includeGranularData: true,
                            metricSelection: settings.metricSelection,
                            transform: .sanitizeGranularAndFilter,
                            emptyRecordPolicy: .retain,
                            fetchExternalRecords: false,
                            failurePolicy: .connectedMac,
                            fetchHealthData: { date, includeGranularData, metricSelection in
                                try await healthKitManager.fetchHealthData(
                                    for: date,
                                    includeGranularData: includeGranularData,
                                    metricSelection: metricSelection
                                )
                            },
                            fetchExternalDailyRecords: nil
                        )
                        let rawDay: CanonicalRawDayResult
                        if let record = outcome.record {
                            do {
                                rawDay = try CanonicalRawDayResult.captured(
                                    record,
                                    customization: settings.formatCustomization
                                )
                            } catch {
                                rawDay = .failed(date: dateString, code: "healthkit_error")
                            }
                        } else {
                            rawDay = .failed(
                                date: dateString,
                                code: outcome.failure?.reason.rawValue ?? "healthkit_error"
                            )
                        }
                        item = try ConnectedCorpusSpoolItem.encode(
                            ConnectedCorpusRawDayPayload(sourceDate: date, day: rawDay),
                            kind: .strictRawDay,
                            sourceDate: date,
                            isRequestedDate: true
                        )
                    }
                    try await append(item)
                }
            }
        )

        if mode == .strictRaw {
            completeCorpusRawRequest(
                acknowledgement: senderResult.acknowledgement,
                request: request,
                settings: settings,
                syncService: syncService
            )
        }
    }

    private func completeCorpusRawRequest(
        acknowledgement: ConnectedCorpusTransferFinalAck,
        request: IPhoneExportRequest,
        settings: AdvancedExportSettings,
        syncService: SyncService
    ) {
        guard pendingRequests.removeValue(forKey: request.jobID) != nil else { return }
        streamAbortMessages.removeValue(forKey: request.jobID)
        activeRequestID = nil
        syncService.isSyncing = false
        let successCount = acknowledgement.successCount ?? 0
        let totalCount = acknowledgement.totalCount ?? ExportOrchestrator.dateRange(
            from: request.dateRangeStart,
            to: request.dateRangeEnd
        ).count
        let result = ExportOrchestrator.ExportResult(
            successCount: successCount,
            totalCount: totalCount,
            failedDateDetails: [],
            formatsPerDate: 0
        )
        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: request.dateRangeStart,
            dateRangeEnd: request.dateRangeEnd,
            targetLabel: "CLI raw response",
            fileCount: 0
        )
        guard successCount > 0 else { return }
        PurchaseManager.shared.recordExportUse()
        PricingAnalyticsClient.shared.trackExportSucceeded(
            metadata: PricingAnalyticsExportMetadata(
                targetType: .connectedMac,
                formatCount: 0,
                metricCount: settings.metricSelection.totalEnabledCount,
                dateRangePreset: PricingAnalyticsDateRangePreset.custom,
                startDate: request.dateRangeStart,
                endDate: request.dateRangeEnd
            ),
            quotaState: PurchaseManager.shared.analyticsQuotaState
        )
    }

    private func sendSizeBoundedMacExportJob(
        for request: IPhoneExportRequest,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        healthKitManager: HealthKitManager,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        dateFormatter: DateFormatter
    ) async throws {
        let job = try await MacExportJobBuilder.build(
            jobID: request.jobID,
            sourceDeviceName: UIDevice.current.name,
            startDate: request.dateRangeStart,
            endDate: request.dateRangeEnd,
            settings: settings,
            healthSubfolder: healthSubfolder,
            destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
            fetchHealthData: { date, includeGranularData in
                guard !self.cancelledRequestIDs.contains(request.jobID),
                      self.activeRequestID == request.jobID else { throw CancellationError() }
                return try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: includeGranularData,
                    metricSelection: settings.metricSelection
                )
            },
            fetchExternalDailyRecords: externalRecordFetcher,
            onProgress: { processed, total, date in
                syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                    jobID: request.jobID,
                    processedDays: processed,
                    totalDays: total,
                    currentDate: date,
                    message: "Preparing \(dateFormatter.string(from: date)) on iPhone…"
                )))
            }
        )
        guard activeRequestID == request.jobID else { return }
        let preparedFile = try ConnectedTransferFile.encode(job)
        defer { preparedFile.remove() }
        let result = await syncService.sendConnectedTransfer(
            preparedFile,
            manifest: ConnectedTransferManifest(
                kind: .macExportJobV1,
                jobID: request.jobID,
                payloadSchemaVersion: 1
            )
        )
        guard activeRequestID == request.jobID else { return }
        if case .failure(let abort) = result {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: abort.reason == .cancelled ? .cancelled : .unknown,
                message: abort.message
            )
        }
    }

    private func streamMacExportJob(
        for request: IPhoneExportRequest,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        healthKitManager: HealthKitManager,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        dateFormatter: DateFormatter
    ) async throws {
        let metadata = MacExportStreamingJobBuilder.metadata(
            startDate: request.dateRangeStart,
            endDate: request.dateRangeEnd,
            settings: settings,
            healthSubfolder: healthSubfolder,
            destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName
        )
        let chunks = MacExportStreamingJobBuilder.chunks(for: metadata.transferDates)

        guard activeRequestID == request.jobID else { return }
        guard syncService.canExportToConnectedMac(requiring: settings) else {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .macDestinationUnavailable,
                message: syncService.macExportReadinessMessage(requiring: settings)
            )
            return
        }

        let start = MacExportStreamStart(
            jobID: request.jobID,
            createdAt: Date(),
            sourceDeviceName: UIDevice.current.name,
            dateRangeStart: metadata.dateRangeStart,
            dateRangeEnd: metadata.dateRangeEnd,
            requestedDates: metadata.requestedDates,
            totalRequestedDays: metadata.totalRequestedDays,
            totalTransferDays: metadata.totalTransferDays,
            settingsSnapshot: metadata.settingsSnapshot,
            requestedTarget: metadata.requestedTarget,
            chunkStrategyVersion: MacExportStreamingJobBuilder.chunkStrategyVersion
        )
        let startAck = await syncService.sendMacExportStreamPayloadAndWaitForAck(
            .macExportStreamStart(start),
            jobID: request.jobID,
            sequence: -1
        )
        guard activeRequestID == request.jobID else { return }
        guard startAck?.accepted == true else {
            failPreparation(
                jobID: request.jobID,
                syncService: syncService,
                reason: .macDestinationUnavailable,
                message: startAck?.message
                    ?? syncService.lastError
                    ?? "Timed out waiting for the Mac to start the chunked export stream."
            )
            return
        }

        var failedDateDetails: [FailedDateDetail] = []
        var processedTransferDays = 0

        for chunk in chunks {
            try Task.checkCancellation()
            if let abortMessage = streamAbortMessages[request.jobID] {
                sendStreamAbort(jobID: request.jobID, message: abortMessage, syncService: syncService)
                return
            }

            var records: [HealthData] = []
            var externalDailyRecords: [ExternalDailyRecord] = []

            for date in chunk.dates {
                try Task.checkCancellation()
                let day = Calendar.current.startOfDay(for: date)
                let shouldIncludeGranularData = MacExportStreamingJobBuilder.shouldIncludeGranularData(
                    for: date,
                    metadata: metadata,
                    settings: settings
                )
                syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                    jobID: request.jobID,
                    processedDays: processedTransferDays + 1,
                    totalDays: metadata.totalTransferDays,
                    currentDate: date,
                    message: "Streaming \(dateFormatter.string(from: date)) from iPhone…"
                )))

                let outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: shouldIncludeGranularData,
                    metricSelection: settings.metricSelection,
                    transform: .sanitizeGranular,
                    emptyRecordPolicy: .retain,
                    fetchExternalRecords: metadata.requestedDays.contains(day)
                        && settings.writesExternalProviderSidecars,
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
                if let record = outcome.record {
                    records.append(record)
                    externalDailyRecords.append(contentsOf: outcome.externalDailyRecords)
                } else if let failure = outcome.failure {
                    failedDateDetails.append(failure)
                }

                processedTransferDays += 1
                if let abortMessage = streamAbortMessages[request.jobID] {
                    sendStreamAbort(jobID: request.jobID, message: abortMessage, syncService: syncService)
                    return
                }
            }

            let payload = MacExportStreamChunk(
                jobID: request.jobID,
                sequence: chunk.sequence,
                records: records,
                externalDailyRecords: externalDailyRecords,
                processedTransferDays: processedTransferDays,
                totalTransferDays: metadata.totalTransferDays
            )
            let chunkAck = await syncService.sendMacExportStreamPayloadAndWaitForAck(
                .macExportStreamChunk(payload),
                jobID: request.jobID,
                sequence: chunk.sequence
            )
            guard activeRequestID == request.jobID else { return }
            guard chunkAck?.accepted == true else {
                sendStreamAbort(
                    jobID: request.jobID,
                    message: chunkAck?.message
                        ?? syncService.lastError
                        ?? "Timed out waiting for the Mac to accept stream chunk \(chunk.sequence).",
                    syncService: syncService
                )
                return
            }
        }

        guard activeRequestID == request.jobID else { return }
        if let abortMessage = streamAbortMessages[request.jobID] {
            sendStreamAbort(jobID: request.jobID, message: abortMessage, syncService: syncService)
            return
        }

        guard syncService.sendLargePayload(.macExportStreamComplete(MacExportStreamComplete(
            jobID: request.jobID,
            totalChunks: chunks.count,
            iphoneFailedDateDetails: failedDateDetails
        ))) else {
            sendStreamAbort(
                jobID: request.jobID,
                message: syncService.lastError ?? "Could not send chunked export completion to Mac.",
                syncService: syncService
            )
            return
        }
    }

    private func sendStreamAbort(jobID: UUID, message: String, syncService: SyncService) {
        syncService.cancelMacExportStreamAckWaiters(jobID: jobID)
        streamAbortMessages.removeValue(forKey: jobID)
        cancelledRequestIDs.remove(jobID)
        pendingRequests.removeValue(forKey: jobID)
        if activeRequestID == jobID { activeRequestID = nil }
        syncService.isSyncing = false
        _ = syncService.sendLargePayload(.macExportStreamAbort(MacExportStreamAbort(
            jobID: jobID,
            reason: .cancelled,
            message: message
        )))
    }

    private func buildRawDataPayload(
        for request: IPhoneExportRequest,
        dates: [Date],
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?,
        syncService: SyncService,
        dateFormatter: DateFormatter
    ) async throws -> IPhoneExportRawDataPayload {
        var records: [HealthData] = []
        var externalDailyRecords: [ExternalDailyRecord] = []
        var failedDateDetails: [FailedDateDetail] = []
        var strictDays: [CanonicalRawDayResult] = []
        let isStrict = request.rawProfile == .canonicalSourceRecordsV1

        for (index, date) in dates.enumerated() {
            try Task.checkCancellation()
            guard !cancelledRequestIDs.contains(request.jobID), activeRequestID == request.jobID else {
                throw CancellationError()
            }
            let dateString = dateFormatter.string(from: date)
            syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                jobID: request.jobID,
                processedDays: index + 1,
                totalDays: dates.count,
                currentDate: date,
                message: "Fetching raw data for \(dateString) on iPhone…"
            )))

            let includesGranularData = ConnectedExportGranularMode.isEnabled(for: settings)
            let outcome = try await HealthKitDailyCapture.capture(
                date: date,
                includeGranularData: includesGranularData,
                metricSelection: settings.metricSelection,
                transform: .sanitizeGranularAndFilter,
                emptyRecordPolicy: isStrict ? .retain : .reportNoData,
                fetchExternalRecords: !isStrict && (externalIntegrations?.connectedProviderCount ?? 0) > 0,
                failurePolicy: .connectedMac,
                fetchHealthData: { date, includeGranularData, metricSelection in
                    try await healthKitManager.fetchHealthData(
                        for: date,
                        includeGranularData: includeGranularData,
                        metricSelection: metricSelection
                    )
                },
                fetchExternalDailyRecords: { date in
                    await externalIntegrations?.fetchDailyRecords(for: date) ?? []
                }
            )
            guard !cancelledRequestIDs.contains(request.jobID), activeRequestID == request.jobID else {
                throw CancellationError()
            }

            if let record = outcome.record {
                if isStrict {
                    do {
                        strictDays.append(try CanonicalRawDayResult.captured(
                            record,
                            customization: settings.formatCustomization
                        ))
                    } catch {
                        strictDays.append(.failed(date: dateString, code: "canonical_serialization_failed"))
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .healthKitError,
                            errorDetails: "Canonical daily response could not be serialized."
                        ))
                    }
                } else {
                    // Legacy raw mode intentionally keeps its prior omission and no-data semantics.
                    records.append(record)
                    externalDailyRecords.append(contentsOf: outcome.externalDailyRecords)
                }
            } else if let failure = outcome.failure {
                failedDateDetails.append(failure)
                if isStrict {
                    strictDays.append(.failed(date: dateString, code: failure.reason.rawValue))
                }
            }
        }

        let strictResult: CanonicalRawResultEnvelope? = isStrict
            ? CanonicalRawResultEnvelope(
                createdAt: Date(),
                sourceDeviceName: UIDevice.current.name,
                requestedDates: dates.map { dateFormatter.string(from: $0) },
                days: strictDays
            )
            : nil

        return IPhoneExportRawDataPayload(
            jobID: request.jobID,
            createdAt: Date(),
            sourceDeviceName: UIDevice.current.name,
            dateRangeStart: dates.first ?? Calendar.current.startOfDay(for: request.dateRangeStart),
            dateRangeEnd: dates.last ?? Calendar.current.startOfDay(for: request.dateRangeEnd),
            totalDays: dates.count,
            records: records,
            externalDailyRecords: externalDailyRecords,
            failedDateDetails: failedDateDetails,
            settingsSnapshot: ExportSettingsSnapshot.from(
                settings,
                healthSubfolder: healthSubfolder
            ),
            strictResult: strictResult
        )
    }

    private func completeRawRequest(
        _ payload: IPhoneExportRawDataPayload,
        settings: AdvancedExportSettings,
        syncService: SyncService
    ) {
        guard let pending = pendingRequests.removeValue(forKey: payload.jobID) else { return }
        streamAbortMessages.removeValue(forKey: payload.jobID)
        activeRequestID = nil
        syncService.isSyncing = false

        let retainedDayCount = payload.strictResult?.captureSummary.retainedDayCount ?? payload.records.count
        let result = ExportOrchestrator.ExportResult(
            successCount: retainedDayCount,
            totalCount: payload.totalDays,
            failedDateDetails: payload.failedDateDetails,
            formatsPerDate: 0,
            externalRecordFileCount: payload.externalDailyRecords.filter(\.shouldExport).count
        )
        ExportOrchestrator.recordResult(
            result,
            source: .macAgent,
            dateRangeStart: pending.request.dateRangeStart,
            dateRangeEnd: pending.request.dateRangeEnd,
            targetLabel: "CLI raw response",
            fileCount: 0
        )

        guard retainedDayCount > 0 else { return }
        PurchaseManager.shared.recordExportUse()
        PricingAnalyticsClient.shared.trackExportSucceeded(
            metadata: PricingAnalyticsExportMetadata(
                targetType: .connectedMac,
                formatCount: 0,
                metricCount: settings.metricSelection.totalEnabledCount,
                dateRangePreset: PricingAnalyticsDateRangePreset.custom,
                startDate: pending.request.dateRangeStart,
                endDate: pending.request.dateRangeEnd
            ),
            quotaState: PurchaseManager.shared.analyticsQuotaState
        )
    }

    private func failPreparation(
        jobID: UUID,
        syncService: SyncService,
        reason: IPhoneExportFailureReason,
        message: String,
        underlyingError: String? = nil
    ) {
        pendingRequests.removeValue(forKey: jobID)
        streamAbortMessages.removeValue(forKey: jobID)
        if activeRequestID == jobID { activeRequestID = nil }
        syncService.isSyncing = false
        syncService.send(.iphoneExportRejected(IPhoneExportFailure(
            jobID: jobID,
            reason: reason,
            message: message,
            underlyingError: underlyingError
        )))
    }

    private func exportFailureReason(for reason: MacExportFailureReason) -> ExportFailureReason {
        switch reason {
        case .noMacFolderSelected:
            return .noVaultSelected
        case .macFolderAccessDenied:
            return .accessDenied
        case .noHealthRecordsReceived:
            return .noHealthData
        case .noFormatsSelected, .payloadDecodeFailure, .exportWriteFailure:
            return .fileWriteError
        case .incompatibleProtocol, .macBusy:
            return .unknown
        case .cancelled:
            return .unknown
        }
    }
}
#endif
