#if os(iOS)
import Combine
import Foundation
import UIKit

/// Owns durable outbound corpus sessions independently of any view, request
/// continuation, or foreground task. A new app process can reconstruct daily
/// capture from the immutable manifest while retaining exact bytes for any item
/// that already crossed a partition boundary.
@MainActor
final class IPhoneCorpusExportRecoveryManager: ObservableObject {
    static let shared = IPhoneCorpusExportRecoveryManager()

    @Published private(set) var activeSnapshot: ConnectedCorpusProgressSnapshot?

    private let store: ConnectedCorpusOutboundStore
    private weak var syncService: SyncService?
    private weak var healthKitManager: HealthKitManager?
    private var externalIntegrations: ExternalIntegrationDailyRecordProviding?
    private var activeTask: Task<ConnectedCorpusDurableSender.Result, Error>?
    private var activeJobID: UUID?
    private var explicitlyCancelledJobIDs: Set<UUID> = []

    convenience init() {
        self.init(store: ConnectedCorpusOutboundStore())
    }

    init(store: ConnectedCorpusOutboundStore) {
        self.store = store
        _ = store.cleanupExpired()
        self.activeSnapshot = store.resumableJournals().lazy
            .compactMap(\.unrecordedProgressSnapshot)
            .first
    }

    func configure(
        syncService: SyncService,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) {
        self.syncService = syncService
        self.healthKitManager = healthKitManager
        self.externalIntegrations = ConnectedAppsFeature.isEnabled ? externalIntegrations : nil
        _ = store.cleanupExpired()
        refreshPublishedSnapshot()
    }

    var resumableSnapshots: [ConnectedCorpusProgressSnapshot] {
        store.resumableJournals().map(\.progressSnapshot)
    }

    func journal(jobID: UUID) -> ConnectedCorpusOutboundJournal? {
        try? store.load(jobID: jobID, allowExpired: true)
    }

    func send(
        origin: ConnectedCorpusOutboundOrigin,
        jobID: UUID,
        manifest: ConnectedCorpusExportManifest,
        macRequest: IPhoneExportRequest? = nil,
        durableNegotiation: ConnectedCorpusDurableNegotiation,
        syncService: SyncService,
        onCheckpoint: ((ConnectedCorpusOutboundJournal) -> Void)? = nil,
        onValidatedPartitionProgress: ((
            _ descriptor: ConnectedCorpusPartitionDescriptor,
            _ acceptedChunks: Int,
            _ totalChunks: Int
        ) -> Void)? = nil,
        produceItem: @escaping ConnectedCorpusDurableSender.ItemProducer
    ) async throws -> ConnectedCorpusDurableSender.Result {
        let fingerprint = try ConnectedCorpusRequestFingerprint.make(for: manifest)
        let session: ConnectedCorpusTransferSession
        if let existing = try store.load(jobID: jobID, allowExpired: true) {
            guard existing.isBound(
                sourceInstallationID: durableNegotiation.peerBinding.sourceInstallationID,
                destinationInstallationID: durableNegotiation.peerBinding.destinationInstallationID
            ) else {
                throw ConnectedCorpusOutboundStoreError.peerChanged
            }
            session = existing.session
        } else {
            session = ConnectedCorpusTransferSession(
                sessionID: UUID(),
                jobID: jobID,
                requestFingerprint: fingerprint,
                protocolVersion: durableNegotiation.protocolVersion,
                partitionTargetBytes: durableNegotiation.partitionTargetBytes,
                createdAt: manifest.createdAt,
                peerBinding: durableNegotiation.peerBinding
            )
        }
        let initial = try store.createOrRestore(
            origin: origin,
            session: session,
            manifest: manifest,
            macRequest: macRequest
        )
        publish(initial, through: syncService)
        onCheckpoint?(initial)
        return try await run(
            jobID: jobID,
            syncService: syncService,
            onCheckpoint: onCheckpoint,
            onValidatedPartitionProgress: onValidatedPartitionProgress,
            produceItem: produceItem
        )
    }

    /// Resumes the oldest job bound to the currently connected Mac. This includes
    /// Mac-initiated work: the Mac may already be terminal while its final ACK was
    /// lost, so waiting for it to resend the request would strand the iPhone spool.
    /// Called after hello and whenever the iPhone becomes active.
    @discardableResult
    func resumeEligibleJob() -> UUID? {
        guard activeTask == nil,
              let syncService,
              syncService.connectionState == .connected,
              let remote = syncService.remoteCapabilities,
              remote.supportsDurableConnectedExportRecovery,
              let remoteInstallationID = remote.installationID else { return nil }
        let localInstallationID = syncService.installationID
        guard let journal = store.resumableJournals().first(where: {
            $0.isBound(
                sourceInstallationID: localInstallationID,
                destinationInstallationID: remoteInstallationID
            )
        }) else {
            refreshPublishedSnapshot()
            return nil
        }
        let producer = makeRecoveredProducer(for: journal)
        let jobID = journal.jobID
        activeJobID = jobID
        activeTask = Task { [weak self, weak syncService] in
            guard let self, let syncService else { throw CancellationError() }
            return try await self.runSender(
                jobID: jobID,
                syncService: syncService,
                onCheckpoint: nil,
                onValidatedPartitionProgress: nil,
                produceItem: producer
            )
        }
        Task { [weak self] in
            guard let self, let task = self.activeTask else { return }
            _ = try? await task.value
            if self.activeJobID == jobID {
                self.activeTask = nil
                self.activeJobID = nil
                self.explicitlyCancelledJobIDs.remove(jobID)
                self.refreshPublishedSnapshot()
            }
        }
        return jobID
    }

    func handlePeerConnected() {
        _ = store.cleanupExpired()
        refreshPublishedSnapshot()
        _ = resumeEligibleJob()
    }

    func handlePeerDisconnected() {
        activeTask?.cancel()
        if let jobID = activeJobID,
           let paused = try? store.updateState(
               jobID: jobID,
               state: .paused,
               message: "Waiting for the same Mac to reconnect…"
           ) {
            publish(paused, through: nil)
        }
    }

    func applicationDidBecomeActive() {
        _ = store.cleanupExpired()
        refreshPublishedSnapshot()
        _ = resumeEligibleJob()
    }

    @discardableResult
    func cancel(
        jobID: UUID,
        message: String = "User cancelled the durable export.",
        notifyPeer: Bool = true
    ) async -> Bool {
        guard let journal = try? store.load(jobID: jobID, allowExpired: true),
              !journal.state.isTerminal else { return false }
        explicitlyCancelledJobIDs.insert(jobID)
        if activeJobID == jobID { activeTask?.cancel() }
        try? store.cancel(jobID: jobID)
        refreshPublishedSnapshot()
        if notifyPeer, let syncService {
            _ = await syncService.sendConnectedCorpusCancelAndWait(ConnectedCorpusTransferCancel(
                sessionID: journal.sessionID,
                jobID: jobID,
                reason: .userRequested,
                message: message,
                requestedAt: Date()
            ))
        }
        return true
    }

    func acknowledgeRemoteCancellation(
        _ cancellation: ConnectedCorpusTransferCancel,
        syncService: SyncService
    ) async {
        let accepted = await cancel(
            jobID: cancellation.jobID,
            message: cancellation.message ?? "Mac cancelled the durable export.",
            notifyPeer: false
        )
        syncService.send(.connectedCorpusTransferCancelAck(ConnectedCorpusTransferCancelAck(
            sessionID: cancellation.sessionID,
            jobID: cancellation.jobID,
            accepted: accepted,
            acknowledgedAt: Date(),
            message: accepted
                ? "iPhone removed the durable sender checkpoint."
                : "No matching durable iPhone checkpoint was active."
        )))
    }

    func recordRecoveredCompletion(_ payload: MacExportResultPayload) {
        guard let journal = try? store.load(jobID: payload.jobID, allowExpired: true),
              journal.state == .completed,
              (try? store.markCompletionRecorded(jobID: payload.jobID)) == true else { return }
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
            source: journal.origin == .scheduledIPhone ? .scheduled : .macAgent,
            dateRangeStart: journal.exportManifest.dateRangeStart,
            dateRangeEnd: journal.exportManifest.dateRangeEnd,
            targetLabel: payload.destinationDisplayName ?? "Mac",
            fileCount: payload.totalFilesWritten
        )
        if payload.successCount > 0 { PurchaseManager.shared.recordExportUse() }
        refreshPublishedSnapshot()
    }

    func markCompletionRecorded(jobID: UUID) {
        _ = try? store.markCompletionRecorded(jobID: jobID)
        refreshPublishedSnapshot()
    }

    private func run(
        jobID: UUID,
        syncService: SyncService,
        onCheckpoint: ((ConnectedCorpusOutboundJournal) -> Void)?,
        onValidatedPartitionProgress: ((
            _ descriptor: ConnectedCorpusPartitionDescriptor,
            _ acceptedChunks: Int,
            _ totalChunks: Int
        ) -> Void)?,
        produceItem: @escaping ConnectedCorpusDurableSender.ItemProducer
    ) async throws -> ConnectedCorpusDurableSender.Result {
        if activeJobID == jobID, let activeTask { return try await activeTask.value }
        guard activeTask == nil else {
            throw ConnectedCorpusDurableSender.DurableSenderError.paused(
                "Another durable iPhone export is currently active."
            )
        }
        activeJobID = jobID
        let task = Task { [weak self, weak syncService] in
            guard let self, let syncService else { throw CancellationError() }
            return try await self.runSender(
                jobID: jobID,
                syncService: syncService,
                onCheckpoint: onCheckpoint,
                onValidatedPartitionProgress: onValidatedPartitionProgress,
                produceItem: produceItem
            )
        }
        activeTask = task
        defer {
            if activeJobID == jobID {
                activeTask = nil
                activeJobID = nil
                explicitlyCancelledJobIDs.remove(jobID)
                refreshPublishedSnapshot()
            }
        }
        return try await task.value
    }

    private func runSender(
        jobID: UUID,
        syncService: SyncService,
        onCheckpoint: ((ConnectedCorpusOutboundJournal) -> Void)?,
        onValidatedPartitionProgress: ((
            _ descriptor: ConnectedCorpusPartitionDescriptor,
            _ acceptedChunks: Int,
            _ totalChunks: Int
        ) -> Void)?,
        produceItem: @escaping ConnectedCorpusDurableSender.ItemProducer
    ) async throws -> ConnectedCorpusDurableSender.Result {
        externalIntegrations?.beginExportAction()
        defer { externalIntegrations?.endExportAction() }
        return try await ConnectedCorpusDurableSender.send(
            configuration: .init(jobID: jobID),
            store: store,
            transport: .syncService(syncService),
            isExplicitlyCancelled: { [weak self] in
                self?.explicitlyCancelledJobIDs.contains(jobID) == true
            },
            onCheckpoint: { [weak self, weak syncService] journal in
                guard let self else { return }
                self.publish(journal, through: syncService)
                onCheckpoint?(journal)
            },
            onValidatedPartitionProgress: onValidatedPartitionProgress,
            produceItem: produceItem
        )
    }

    private func publish(_ journal: ConnectedCorpusOutboundJournal, through service: SyncService?) {
        activeSnapshot = journal.unrecordedProgressSnapshot
        guard let service,
              service.connectionState == .connected,
              service.remoteCapabilities?.supportsDurableConnectedExportRecovery == true else { return }
        service.send(.connectedCorpusStatus(journal.progressSnapshot))
    }

    private func refreshPublishedSnapshot() {
        if let activeJobID,
           let journal = try? store.load(jobID: activeJobID, allowExpired: true) {
            activeSnapshot = journal.unrecordedProgressSnapshot
            return
        }
        activeSnapshot = store.resumableJournals().lazy
            .compactMap(\.unrecordedProgressSnapshot)
            .first
    }

    private func makeRecoveredProducer(
        for journal: ConnectedCorpusOutboundJournal
    ) -> ConnectedCorpusDurableSender.ItemProducer {
        let settings = journal.exportManifest.settingsSnapshot.makeAdvancedExportSettings()
        let requestedDays = Set(journal.exportManifest.requestedDates.map {
            Calendar.current.startOfDay(for: $0)
        })
        let metadata: MacExportStreamingJobBuilder.Metadata? = journal.exportManifest.mode == .writeFiles
            ? MacExportStreamingJobBuilder.metadata(
                startDate: journal.exportManifest.dateRangeStart,
                endDate: journal.exportManifest.dateRangeEnd,
                requestedDates: journal.exportManifest.requestedDates,
                settings: settings,
                healthSubfolder: journal.exportManifest.settingsSnapshot.healthSubfolder ?? "",
                destinationDisplayName: journal.exportManifest.requestedTarget?.displayName
            )
            : nil
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = journal.exportManifest.sourceTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        let healthKitManager = self.healthKitManager
        let integrations = self.externalIntegrations

        return { index, date in
            guard let healthKitManager else {
                throw HealthKitManager.HealthKitError.dataNotAvailable
            }
            let isRequested = requestedDays.contains(Calendar.current.startOfDay(for: date))
            switch journal.exportManifest.mode {
            case .writeFiles:
                let includeGranular = metadata.map {
                    MacExportStreamingJobBuilder.shouldIncludeGranularData(
                        for: date,
                        metadata: $0,
                        settings: settings
                    )
                } ?? settings.includeGranularData
                let externalFetcher: HealthKitDailyCapture.ExternalDailyRecordFetcher?
                if isRequested,
                   settings.writesExternalProviderSidecars,
                   let integrations,
                   integrations.connectedProviderCount > 0 {
                    externalFetcher = { date in await integrations.fetchDailyRecords(for: date) }
                } else {
                    externalFetcher = nil
                }
                let outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: includeGranular,
                    metricSelection: settings.metricSelection,
                    transform: .sanitizeGranular,
                    emptyRecordPolicy: .retain,
                    fetchExternalRecords: externalFetcher != nil,
                    failurePolicy: .connectedMac,
                    fetchHealthData: { date, includeGranularData, selection in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: selection
                        )
                    },
                    fetchExternalDailyRecords: externalFetcher
                )
                return try ConnectedCorpusSpoolItem.encode(
                    ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: isRequested,
                        record: outcome.record,
                        externalDailyRecords: outcome.externalDailyRecords,
                        failure: outcome.failure
                    ),
                    kind: .macHealthDay,
                    sourceDate: date,
                    isRequestedDate: isRequested
                )

            case .encryptedContext:
                let externalFetcher: HealthKitDailyCapture.ExternalDailyRecordFetcher?
                if journal.macRequest?.profileExecutionPolicy?.request.sourceIDs.contains(where: {
                    $0 != "apple_health"
                }) == true,
                   let integrations,
                   integrations.connectedProviderCount > 0 {
                    externalFetcher = { date in await integrations.fetchDailyRecords(for: date) }
                } else {
                    externalFetcher = nil
                }
                let outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection,
                    transform: .sanitizeGranular,
                    emptyRecordPolicy: .retain,
                    fetchExternalRecords: externalFetcher != nil,
                    failurePolicy: .connectedMac,
                    fetchHealthData: { date, includeGranularData, selection in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: selection
                        )
                    },
                    fetchExternalDailyRecords: externalFetcher
                )
                return try ConnectedCorpusSpoolItem.encode(
                    ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: true,
                        record: outcome.record,
                        externalDailyRecords: outcome.externalDailyRecords,
                        failure: outcome.failure
                    ),
                    kind: .macHealthDay,
                    sourceDate: date,
                    isRequestedDate: true
                )

            case .strictRaw:
                let outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: true,
                    metricSelection: settings.metricSelection,
                    transform: .sanitizeGranularAndFilter,
                    emptyRecordPolicy: .retain,
                    fetchExternalRecords: false,
                    failurePolicy: .connectedMac,
                    fetchHealthData: { date, includeGranularData, selection in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: selection
                        )
                    },
                    fetchExternalDailyRecords: nil
                )
                let day: CanonicalRawDayResult
                if let record = outcome.record {
                    do {
                        day = try CanonicalRawDayResult.captured(
                            record,
                            customization: settings.formatCustomization
                        )
                    } catch {
                        day = .failed(date: formatter.string(from: date), code: "healthkit_error")
                    }
                } else {
                    day = .failed(
                        date: journal.exportManifest.requestedDateIdentifiers?[safe: index]
                            ?? formatter.string(from: date),
                        code: outcome.failure?.reason.rawValue ?? "healthkit_error"
                    )
                }
                return try ConnectedCorpusSpoolItem.encode(
                    ConnectedCorpusRawDayPayload(sourceDate: date, day: day),
                    kind: .strictRawDay,
                    sourceDate: date,
                    isRequestedDate: true
                )
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
