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

    enum StartError: Error, LocalizedError, Equatable {
        case exportAlreadyInProgress(
            jobID: UUID,
            origin: ConnectedCorpusOutboundOrigin?
        )

        var errorDescription: String? {
            switch self {
            case .exportAlreadyInProgress(_, .interactiveIPhone):
                return "Your previous Mac export is still finishing. Try again shortly."
            case .exportAlreadyInProgress(_, .scheduledIPhone):
                return "A scheduled iPhone export is already in progress. Try again after it finishes."
            case .exportAlreadyInProgress(_, .macInitiated):
                return "A Mac-requested export is already in progress. Try again after it finishes."
            case .exportAlreadyInProgress(_, nil):
                return "Another iPhone export is already in progress. Try again after it finishes."
            }
        }
    }

    /// Progress owned by the interactive iPhone Export screen. Scheduled and
    /// Mac-initiated jobs continue recovering without taking over that UI.
    @Published private(set) var activeSnapshot: ConnectedCorpusProgressSnapshot?

    private let store: ConnectedCorpusOutboundStore
    private let cliActivityTracker: CLIExportActivityTracker
    private let transportProvider: @MainActor (SyncService) -> ConnectedCorpusSender.Transport
    private let connectedPeerProvider: @MainActor (SyncService) -> SyncPeerCapabilities?
    private weak var syncService: SyncService?
    private weak var healthKitManager: HealthKitManager?
    private var externalIntegrations: ExternalIntegrationDailyRecordProviding?
    private var activeTask: Task<ConnectedCorpusDurableSender.Result, Error>?
    private var activeJobID: UUID?
    private var explicitlyCancelledJobIDs: Set<UUID> = []
    /// Retained across disconnect/pause/resume attempts so unresolved physical
    /// HealthKit workers and their open circuits stay bounded for the full job.
    private var queryExecutionControllers: [UUID: HealthKitQueryExecutionController] = [:]
    private var resumeWhenActiveTaskFinishes = false
    private var publishedCLIJobID: UUID?

    convenience init() {
        self.init(
            store: ConnectedCorpusOutboundStore(),
            cliActivityTracker: .shared
        )
    }

    init(
        store: ConnectedCorpusOutboundStore,
        cliActivityTracker: CLIExportActivityTracker,
        transportProvider: @escaping @MainActor (SyncService) -> ConnectedCorpusSender.Transport = {
            .syncService($0)
        },
        connectedPeerProvider: @escaping @MainActor (SyncService) -> SyncPeerCapabilities? = {
            $0.connectionState == .connected ? $0.remoteCapabilities : nil
        }
    ) {
        self.store = store
        self.cliActivityTracker = cliActivityTracker
        self.transportProvider = transportProvider
        self.connectedPeerProvider = connectedPeerProvider
        self.activeSnapshot = nil
        cleanupExpiredJournals()
        pauseInterruptedJournals()
        refreshPublishedSnapshot()
    }

    convenience init(
        store: ConnectedCorpusOutboundStore,
        transportProvider: @escaping @MainActor (SyncService) -> ConnectedCorpusSender.Transport = {
            .syncService($0)
        },
        connectedPeerProvider: @escaping @MainActor (SyncService) -> SyncPeerCapabilities? = {
            $0.connectionState == .connected ? $0.remoteCapabilities : nil
        }
    ) {
        self.init(
            store: store,
            cliActivityTracker: .shared,
            transportProvider: transportProvider,
            connectedPeerProvider: connectedPeerProvider
        )
    }

    func configure(
        syncService: SyncService,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) {
        self.syncService = syncService
        self.healthKitManager = healthKitManager
        self.externalIntegrations = ConnectedAppsFeature.isEnabled ? externalIntegrations : nil
        cleanupExpiredJournals()
        if connectedPeerProvider(syncService) == nil {
            pauseInterruptedJournals()
        }
        refreshPublishedSnapshot()
    }

    var resumableSnapshots: [ConnectedCorpusProgressSnapshot] {
        store.resumableJournals().map(\.progressSnapshot)
    }

    var hasRunningExport: Bool { activeTask != nil }

    /// Reconciles the shared keep-awake/background assertion after a caller-owned
    /// sender returns. A latched recovery task may already own the durable job.
    func reconcileExecutionAssertion(on syncService: SyncService) {
        if hasRunningExport {
            syncService.isSyncing = true
            syncService.reassertExecutionAssertionIfSyncing()
        } else {
            syncService.isSyncing = false
        }
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
        try rejectConflictingExport(
            origin: origin,
            jobID: jobID,
            peerBinding: durableNegotiation.peerBinding
        )

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
            origin: origin,
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
        if activeTask != nil {
            if let syncService, connectedPeerProvider(syncService) != nil {
                syncService.isSyncing = true
                syncService.reassertExecutionAssertionIfSyncing()
                // A reconnect can beat sender teardown whether the old task is
                // cooperatively cancelled or has already returned `.paused`.
                // Always latch a follow-up attempt; a successful/terminal task
                // has no resumable journal, so the extra lookup is harmless.
                resumeWhenActiveTaskFinishes = true
            }
            return activeJobID
        }
        guard let syncService,
              let remote = connectedPeerProvider(syncService),
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
        syncService.isSyncing = true
        syncService.reassertExecutionAssertionIfSyncing()
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
        Task { [weak self, weak syncService] in
            guard let self, let task = self.activeTask else { return }
            _ = try? await task.value
            if self.activeJobID == jobID {
                let shouldResume = self.resumeWhenActiveTaskFinishes
                    && syncService.map { self.connectedPeerProvider($0) != nil } == true
                self.resumeWhenActiveTaskFinishes = false
                self.activeTask = nil
                self.activeJobID = nil
                self.explicitlyCancelledJobIDs.remove(jobID)
                syncService?.isSyncing = false
                self.refreshPublishedSnapshot()
                if shouldResume { _ = self.resumeEligibleJob() }
            }
        }
        return jobID
    }

    func handlePeerConnected() {
        cleanupExpiredJournals()
        refreshPublishedSnapshot()
        _ = resumeEligibleJob()
    }

    func handlePeerDisconnected() {
        activeTask?.cancel()
        pauseInterruptedJournals()
        refreshPublishedSnapshot()
    }

    func applicationDidBecomeActive() {
        cleanupExpiredJournals()
        if syncService.map({ connectedPeerProvider($0) }) == nil {
            pauseInterruptedJournals()
        }
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
        if activeJobID == jobID {
            activeTask?.cancel()
        } else {
            queryExecutionControllers.removeValue(forKey: jobID)
        }
        try? store.cancel(jobID: jobID)
        if journal.cliUIProgressSnapshot != nil {
            cliActivityTracker.finish(
                jobID: jobID,
                phase: .cancelled,
                message: message
            )
        }
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
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        ExportOrchestrator.recordResult(
            result,
            source: journal.origin == .scheduledIPhone ? .scheduled : .macAgent,
            dateRangeStart: journal.exportManifest.dateRangeStart,
            dateRangeEnd: journal.exportManifest.dateRangeEnd,
            targetLabel: payload.destinationDisplayName ?? "Mac",
            fileCount: payload.isTotalFilesWrittenAuthoritative
                ? payload.totalFilesWritten : nil,
            appleExportEnginePin: journal.exportManifest.effectiveAppleExportEnginePin
        )
        if payload.successCount > 0 { PurchaseManager.shared.recordExportUse() }
        if journal.macRequest?.requestedBy == .cli {
            let phase: CLIExportActivityTracker.Phase
            switch payload.status {
            case .success: phase = .completed
            case .partialSuccess: phase = .completedWithWarnings
            case .failure: phase = .failed
            case .cancelled: phase = .cancelled
            }
            cliActivityTracker.finish(
                jobID: payload.jobID,
                phase: phase,
                message: payload.status == .partialSuccess
                    ? "The CLI export completed with missing data."
                    : (payload.status == .success
                        ? "The CLI export completed successfully."
                        : "The CLI export \(payload.status == .cancelled ? "was cancelled" : "failed").")
            )
        }
        refreshPublishedSnapshot()
    }

    func markCompletionRecorded(jobID: UUID) {
        _ = try? store.markCompletionRecorded(jobID: jobID)
        refreshPublishedSnapshot()
    }

    private func run(
        origin: ConnectedCorpusOutboundOrigin,
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
            if origin == .interactiveIPhone {
                let activeJournal = activeJobID.flatMap {
                    try? store.load(jobID: $0, allowExpired: true)
                }
                throw StartError.exportAlreadyInProgress(
                    jobID: activeJobID ?? jobID,
                    origin: activeJournal?.origin
                )
            }
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
                let shouldResume = resumeWhenActiveTaskFinishes
                    && connectedPeerProvider(syncService) != nil
                resumeWhenActiveTaskFinishes = false
                activeTask = nil
                activeJobID = nil
                explicitlyCancelledJobIDs.remove(jobID)
                syncService.isSyncing = false
                refreshPublishedSnapshot()
                if shouldResume { _ = resumeEligibleJob() }
            }
        }
        return try await task.value
    }

    private func rejectConflictingExport(
        origin: ConnectedCorpusOutboundOrigin,
        jobID: UUID,
        peerBinding: ConnectedCorpusPeerBinding
    ) throws {
        guard origin == .interactiveIPhone else { return }
        if let activeJobID, activeJobID != jobID, activeTask != nil {
            let origin = (try? store.load(jobID: activeJobID, allowExpired: true))?.origin
            throw StartError.exportAlreadyInProgress(
                jobID: activeJobID,
                origin: origin
            )
        }
        guard activeTask == nil,
              let conflict = store.resumableJournals().first(where: {
                  $0.jobID != jobID
                      && $0.origin == .interactiveIPhone
                      && $0.session.peerBinding == peerBinding
              }) else { return }
        throw StartError.exportAlreadyInProgress(
            jobID: conflict.jobID,
            origin: conflict.origin
        )
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
        let queryController = queryExecutionControllers[jobID]
            ?? HealthKitQueryExecutionController()
        queryExecutionControllers[jobID] = queryController
        defer {
            if let journal = try? store.load(jobID: jobID, allowExpired: true),
               journal.state.isTerminal {
                queryExecutionControllers.removeValue(forKey: jobID)
            }
        }
        return try await HealthKitQueryExecutionController.withController(queryController) {
            try await ConnectedCorpusDurableSender.send(
                configuration: .init(jobID: jobID),
                store: store,
                transport: transportProvider(syncService),
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
    }

    private func publish(_ journal: ConnectedCorpusOutboundJournal, through service: SyncService?) {
        if let cliSnapshot = journal.cliUIProgressSnapshot {
            publishCLIActivity(cliSnapshot)
        }
        if let snapshot = journal.interactiveUIProgressSnapshot {
            activeSnapshot = snapshot
        } else {
            refreshPublishedSnapshot()
        }
        guard let service,
              service.connectionState == .connected,
              service.remoteCapabilities?.supportsDurableConnectedExportRecovery == true else { return }
        service.send(.connectedCorpusStatus(journal.progressSnapshot))
    }

    private func refreshPublishedSnapshot() {
        let journals = store.resumableJournals()
        if let activeJobID,
           let journal = try? store.load(jobID: activeJobID, allowExpired: true),
           let snapshot = journal.interactiveUIProgressSnapshot {
            activeSnapshot = snapshot
        } else {
            activeSnapshot = journals.lazy
                .compactMap(\.interactiveUIProgressSnapshot)
                .first
        }

        if let cliSnapshot = journals.lazy
            .compactMap(\.cliUIProgressSnapshot)
            .first(where: { $0.state != .paused }) {
            publishCLIActivity(cliSnapshot)
            return
        }

        let ownedJobID = publishedCLIJobID ?? managerOwnedCLIJobIDInTracker()
        guard let ownedJobID else { return }
        if let current = cliActivityTracker.snapshot,
           current.jobID == ownedJobID,
           current.source == .macApp,
           !current.phase.isTerminal {
            cliActivityTracker.clear(jobID: ownedJobID)
        }
        publishedCLIJobID = nil
    }

    private func publishCLIActivity(_ snapshot: ConnectedCorpusProgressSnapshot) {
        if let publishedCLIJobID, publishedCLIJobID != snapshot.jobID {
            cliActivityTracker.clear(jobID: publishedCLIJobID)
        }
        publishedCLIJobID = snapshot.jobID
        cliActivityTracker.updateConnected(snapshot)
    }

    private func managerOwnedCLIJobIDInTracker() -> UUID? {
        guard let snapshot = cliActivityTracker.snapshot,
              snapshot.source == .macApp,
              let journal = try? store.load(jobID: snapshot.jobID, allowExpired: true),
              journal.origin == .macInitiated,
              journal.macRequest?.requestedBy == .cli,
              journal.macRequest?.responseMode != .contextStore else { return nil }
        return snapshot.jobID
    }

    private func cleanupExpiredJournals() {
        for jobID in store.cleanupExpired() {
            cliActivityTracker.finish(
                jobID: jobID,
                phase: .failed,
                message: "The CLI export expired before completion."
            )
        }
    }

    private func pauseInterruptedJournals() {
        for journal in store.resumableJournals() where journal.state != .paused {
            _ = try? store.updateState(
                jobID: journal.jobID,
                state: .paused,
                message: "Waiting for the same Mac to reconnect…"
            )
        }
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
                destinationDisplayName: journal.exportManifest.requestedTarget?.displayName,
                frozenSettingsSnapshot: journal.exportManifest.settingsSnapshot
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
                return try await ConnectedCorpusSpoolItem.encodeHealthDay(
                    ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: isRequested,
                        record: outcome.record,
                        externalDailyRecords: outcome.externalDailyRecords,
                        failure: outcome.failure
                    ),
                    sourceDate: date,
                    isRequestedDate: isRequested,
                    protocolVersion: journal.session.protocolVersion
                )

            case .encryptedContext:
                let selectedSourceIDs = Set(
                    journal.macRequest?.canonicalSelection?.sourceIDs ?? ["apple_health"]
                )
                let allowedProviderIDs = selectedSourceIDs.subtracting(["apple_health"])
                let includesAppleHealth = selectedSourceIDs.contains("apple_health")
                let externalFetcher: HealthKitDailyCapture.ExternalDailyRecordFetcher?
                if !allowedProviderIDs.isEmpty,
                   let integrations {
                    externalFetcher = { date in
                        await integrations.fetchDailyRecords(
                            for: date,
                            providerIDs: allowedProviderIDs
                        )
                    }
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
                        if includesAppleHealth {
                            return try await healthKitManager.fetchHealthData(
                                for: date,
                                includeGranularData: includeGranularData,
                                metricSelection: selection
                            )
                        }
                        return HealthData(
                            date: date,
                            healthKitRecordCaptureStatus: .notRequested
                        )
                    },
                    fetchExternalDailyRecords: externalFetcher
                )
                return try await ConnectedCorpusSpoolItem.encodeHealthDay(
                    ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: true,
                        record: outcome.record,
                        externalDailyRecords: outcome.externalDailyRecords,
                        failure: outcome.failure
                    ),
                    sourceDate: date,
                    isRequestedDate: true,
                    protocolVersion: journal.session.protocolVersion
                )

            case .strictRaw:
                let expectsLosslessArchive = settings.includeGranularData
                let outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: expectsLosslessArchive,
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
                if let record = outcome.record,
                   ConnectedCorpusApplicationItemCodec.usesStreamableItems(
                    protocolVersion: journal.session.protocolVersion
                   ) {
                    let captured = try CanonicalRawDayResult.capturedSpool(
                        record,
                        customization: settings.formatCustomization,
                        expectsLosslessArchive: expectsLosslessArchive
                    )
                    defer { captured.remove() }
                    return try ConnectedCorpusSpoolItem.encodeRawDay(
                        sourceDate: date,
                        captured: captured,
                        protocolVersion: journal.session.protocolVersion
                    )
                }
                let day: CanonicalRawDayResult
                if let record = outcome.record {
                    do {
                        day = try CanonicalRawDayResult.captured(
                            record,
                            customization: settings.formatCustomization,
                            expectsLosslessArchive: expectsLosslessArchive
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
                    isRequestedDate: true,
                    protocolVersion: journal.session.protocolVersion
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
