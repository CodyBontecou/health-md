#if os(macOS)
import SwiftUI
import UserNotifications

// MARK: - Window Manager (bridges SwiftUI openWindow to AppKit)

final class WindowManager {
    static let shared = WindowManager()
    /// Captured from the SwiftUI environment so AppKit code can open the main window.
    var openMainWindow: (() -> Void)?
    private init() {}
}

// MARK: - macOS App Delegate

class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Notification permission is requested when the user enables a schedule.
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Perform catch-up export if the schedule was missed while the app was inactive
        Task { @MainActor in
            await SchedulingManager.shared.performCatchUpExportIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Re-open the main window when the user clicks the Dock icon while no windows are visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.openMainWindow?()
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.contains("export") {
            NSApp.activate(ignoringOtherApps: true)
            WindowManager.shared.openMainWindow?()
        }
        completionHandler()
    }

    // MARK: - Remote notifications (server-driven scheduled exports)

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrationManager.shared.submitDeviceToken(deviceToken)
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Dev builds without the entitlement may fail here; the server simply
        // won't push to this device.
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        guard userInfo["type"] as? String == "scheduled-export" else { return }
        Task { @MainActor in
            await SchedulingManager.shared.performCatchUpExportIfNeeded()
        }
    }
}

// MARK: - macOS Main App

@main
struct HealthMdApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @StateObject private var syncService = SyncService()
    @StateObject private var healthDataStore = HealthDataStore()
    @StateObject private var healthContextProfileManager = HealthContextProfileManager()
    @StateObject private var agentAccessManager = MacAgentAccessManager()
    @StateObject private var iphoneExportRequestCoordinator = MacIPhoneExportRequestCoordinator()
    @StateObject private var controlServer = HealthMdControlServer()
    private let macExportJobExecutor = MacExportJobExecutor()
    private let macCorpusExportSessionManager = MacCorpusExportSessionManager()
    private let connectedTransferReceiver = ConnectedTransferReceiver()
    private let macExportProgressThrottler = MacExportProgressThrottler()

    init() {
        Task { @MainActor in
            if SchedulingManager.shared.schedule.isEnabled {
                SchedulingManager.shared.rescheduleTimer()
            }
        }
    }

    var body: some Scene {
        Window("Mac Destination", id: "main-window") {
            MacContentView()
                .environmentObject(schedulingManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .environmentObject(syncService)
                .environmentObject(healthDataStore)
                .environmentObject(healthContextProfileManager)
                .environmentObject(agentAccessManager)
                .frame(minWidth: 1_100, minHeight: 680)
                        .tint(Color.accent)
                .task {
                    setupSyncMessageHandler()
                    setupControlServer()
                    syncService.startBrowsing()
                    syncService.restoreManualIPServerIfNeeded()
                }
                .onChange(of: syncService.connectionState) { _, newState in
                    if newState == .connected {
                        publishMacDestinationStatus()
                    } else if newState == .disconnected {
                        connectedTransferReceiver.cancelAll(reason: .disconnected)
                        iphoneExportRequestCoordinator.handlePeerDisconnectForResume()
                        suspendCorpusSessionForDisconnect()
                        cancelOrphanedStreamIfNeeded(message: "iPhone disconnected before completing the Mac export.")
                    }
                }
                .onChange(of: vaultManager.vaultURL) { _, _ in
                    publishMacDestinationStatus()
                }
                .onChange(of: syncService.lastError) { _, _ in
                    publishMacDestinationStatus()
                }
                .withWindowManagerBridge()
                .gradientMatchedTitleBar()
        }
        .defaultSize(width: 1_360, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            MainWindowCommands()
        }

        MenuBarExtra("Health.md", systemImage: "heart.text.square") {
            MacMenuBarView()
                .environmentObject(schedulingManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .environmentObject(syncService)
                .environmentObject(healthDataStore)
                .environmentObject(healthContextProfileManager)
                .environmentObject(agentAccessManager)
                .tint(Color.accent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsWindow()
                .environmentObject(schedulingManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .environmentObject(syncService)
                .environmentObject(healthDataStore)
                .environmentObject(healthContextProfileManager)
                .environmentObject(agentAccessManager)
                        .tint(Color.accent)
        }
    }

    // MARK: - Sync Message Handling

    private func setupSyncMessageHandler() {
        iphoneExportRequestCoordinator.onRequestTermination = { jobID, notifyPeer in
            _ = connectedTransferReceiver.cancel(
                jobID: jobID,
                reason: .cancelled,
                message: "Mac terminated the connected export transfer."
            )
            if let (acknowledgement, result) = macCorpusExportSessionManager.cancel(
                jobID: jobID,
                vaultManager: vaultManager
            ) {
                if notifyPeer {
                    syncService.send(.connectedCorpusTransferCancel(ConnectedCorpusTransferCancel(
                        sessionID: acknowledgement.sessionID,
                        jobID: jobID,
                        reason: .userRequested,
                        message: "Mac cancelled the corpus export request.",
                        requestedAt: Date()
                    )))
                    if let result { syncService.send(.macExportResult(result)) }
                }
                if !acknowledgement.accepted { syncService.lastError = acknowledgement.message }
            }
            syncService.isSyncing = false
        }
        connectedTransferReceiver.onTimeout = { abort in
            syncService.isSyncing = false
            syncService.send(.connectedTransferAbort(abort))
            handleConnectedTransferAbort(abort)
            publishMacDestinationStatus()
        }
        syncService.onMessageReceived = { message in
            // Start/chunk handling must remain synchronous with SyncService's
            // ordered ingress queue. Spawning one task per chunk can reorder
            // reliable Multipeer frames before the strict disk spool accepts them.
            switch message {
            case .connectedTransferStart(let start):
                handleConnectedTransferStart(start)
                return
            case .connectedTransferChunk(let chunk):
                handleConnectedTransferChunk(chunk)
                return
            case .connectedTransferAbort(let abort):
                handleConnectedTransferAbort(abort)
                _ = connectedTransferReceiver.cancel(
                    transferID: abort.transferID,
                    reason: abort.reason,
                    message: abort.message
                )
                return
            default:
                break
            }
            Task { @MainActor in
                switch message {
                case .healthData(let payload):
                    healthDataStore.store(payload.healthRecords, fromDevice: payload.deviceName)
                    SyncEventHistoryManager.shared.record(syncEvent(from: payload))
                case .syncProgress(let progress):
                    healthDataStore.updateSyncProgress(progress)
                    if progress.isComplete {
                        SyncEventHistoryManager.shared.record(
                            SyncEvent(
                                peerName: syncService.connectedPeerName ?? "iPhone",
                                kind: .progressComplete,
                                recordCount: progress.processedDays
                            )
                        )
                    }
                case .pong:
                    publishMacDestinationStatus()
                case .ping:
                    syncService.send(.pong)
                    publishMacDestinationStatus()
                case .hello(let capabilities):
                    syncService.remoteCapabilities = capabilities
                    syncService.send(.macStatus(makeMacDestinationStatus()))
                    iphoneExportRequestCoordinator.resumePausedJobsAfterHello(
                        syncService: syncService,
                        destinationStatus: makeMacDestinationStatus()
                    )
                case .macExportRequest(let job):
                    await executeMacExportJob(job)
                case .macExportStreamStart(let start):
                    syncService.isSyncing = true
                    syncService.activeMacExportProgress = nil
                    syncService.lastMacExportResult = nil
                    syncService.lastMacExportFailure = nil
                    publishMacDestinationStatus(activeJobID: start.jobID)
                    let result = macExportJobExecutor.startStream(
                        start,
                        vaultManager: vaultManager,
                        progress: { progress in
                            publishMacExportProgress(progress)
                        }
                    )
                    switch result {
                    case .success(let ack):
                        syncService.send(.macExportStreamChunkAck(ack))
                    case .failure(let failure):
                        syncService.isSyncing = false
                        syncService.lastMacExportFailure = failure
                        _ = iphoneExportRequestCoordinator.complete(with: failure)
                        syncService.send(.macExportFailed(failure))
                        publishMacDestinationStatus()
                    }
                case .macExportStreamChunk(let chunk):
                    let result = await macExportJobExecutor.receiveChunk(
                        chunk,
                        vaultManager: vaultManager,
                        progress: { progress in
                            publishMacExportProgress(progress)
                        }
                    )
                    switch result {
                    case .success(let ack):
                        syncService.send(.macExportStreamChunkAck(ack))
                    case .failure(let failure):
                        syncService.isSyncing = false
                        syncService.lastMacExportFailure = failure
                        _ = iphoneExportRequestCoordinator.complete(with: failure)
                        syncService.send(.macExportFailed(failure))
                        publishMacDestinationStatus()
                    }
                case .macExportStreamComplete(let complete):
                    let result = await macExportJobExecutor.completeStream(
                        complete,
                        vaultManager: vaultManager,
                        progress: { progress in
                            publishMacExportProgress(progress)
                        }
                    )
                    syncService.isSyncing = false
                    switch result {
                    case .success(let payload):
                        syncService.lastMacExportResult = payload
                        syncService.lastMacExportFailure = nil
                        _ = iphoneExportRequestCoordinator.complete(with: payload)
                        syncService.send(.macExportResult(payload))
                    case .failure(let failure):
                        syncService.lastMacExportFailure = failure
                        syncService.lastMacExportResult = nil
                        _ = iphoneExportRequestCoordinator.complete(with: failure)
                        syncService.send(.macExportFailed(failure))
                    }
                    publishMacDestinationStatus()
                case .macExportStreamAbort(let abort):
                    macExportJobExecutor.abortStream(
                        abort,
                        progress: { progress in
                            publishMacExportProgress(progress)
                        }
                    )
                    syncService.isSyncing = false
                    let failure = MacExportFailure(
                        jobID: abort.jobID,
                        reason: abort.reason,
                        message: abort.message
                    )
                    syncService.lastMacExportFailure = failure
                    _ = iphoneExportRequestCoordinator.complete(with: failure)
                    syncService.send(.macExportFailed(failure))
                    publishMacDestinationStatus()
                case .macExportCancel(jobID: let jobID):
                    if let failure = macExportJobExecutor.cancel(
                        jobID: jobID,
                        message: "Mac export cancelled from iPhone.",
                        progress: { progress in
                            publishMacExportProgress(progress)
                        }
                    ) {
                        syncService.isSyncing = false
                        syncService.lastMacExportFailure = failure
                        _ = iphoneExportRequestCoordinator.complete(with: failure)
                        syncService.send(.macExportFailed(failure))
                    }
                    publishMacDestinationStatus(activeJobID: macExportJobExecutor.currentJobID)
                case .macStatus(let status):
                    syncService.macDestinationStatus = status
                case .iphoneExportAccepted(let acknowledgement):
                    iphoneExportRequestCoordinator.handleAccepted(acknowledgement)
                case .iphoneExportPreparationProgress(let progress):
                    iphoneExportRequestCoordinator.handlePreparationProgress(progress)
                case .iphoneExportRawData(let payload):
                    _ = iphoneExportRequestCoordinator.complete(with: payload)
                case .connectedTransferStart(let start):
                    handleConnectedTransferStart(start)
                case .connectedTransferChunk(let chunk):
                    handleConnectedTransferChunk(chunk)
                case .connectedTransferComplete(let complete):
                    await handleConnectedTransferComplete(complete)
                case .connectedTransferAbort(let abort):
                    handleConnectedTransferAbort(abort)
                    _ = connectedTransferReceiver.cancel(
                        transferID: abort.transferID,
                        reason: abort.reason,
                        message: abort.message
                    )
                case .iphoneExportRejected(let failure):
                    if let jobID = failure.jobID,
                       macCorpusExportSessionManager.activeJobID == jobID,
                       let sessionID = macCorpusExportSessionManager.activeSessionID {
                        _ = macCorpusExportSessionManager.cancel(
                            sessionID: sessionID,
                            jobID: jobID,
                            vaultManager: vaultManager
                        )
                    }
                    _ = iphoneExportRequestCoordinator.complete(with: failure)
                case .macExportAccepted, .macExportProgress, .macExportResult, .macExportFailed,
                     .macExportStreamChunkAck, .connectedTransferAck, .connectedTransferFinalAck:
                    break // macOS only sends these acknowledgements/results
                case .iphoneExportRequest, .iphoneExportCancel:
                    break // iOS receives these requests
                case .connectedCorpusTransferOpen(let open):
                    let isDirectFileExport = iphoneExportRequestCoordinator.activeJobID == nil
                        && open.exportManifest?.mode == .writeFiles
                    guard isDirectFileExport || iphoneExportRequestCoordinator.accepts(
                        open,
                        localInstallationID: syncService.installationID,
                        remoteInstallationID: syncService.remoteCapabilities?.installationID
                    ) else {
                        syncService.send(.connectedCorpusTransferDisposition(ConnectedCorpusTransferDisposition(
                            sessionID: open.session.sessionID,
                            jobID: open.session.jobID,
                            partitionIndex: open.partition.index,
                            partitionSHA256: open.partition.sha256,
                            disposition: .reject,
                            nextPartitionIndex: 0,
                            message: "Corpus session does not match the active Mac request."
                        )))
                        break
                    }
                    let disposition = macCorpusExportSessionManager.open(
                        open,
                        vaultManager: vaultManager,
                        localInstallationID: syncService.installationID,
                        remoteInstallationID: syncService.remoteCapabilities?.installationID
                    )
                    if disposition.disposition != .reject {
                        syncService.isSyncing = true
                        iphoneExportRequestCoordinator.handleCorpusSession(open, disposition: disposition)
                        iphoneExportRequestCoordinator.handleValidatedTransferProgress(jobID: open.session.jobID)
                        publishMacDestinationStatus(activeJobID: open.session.jobID)
                    }
                    syncService.send(.connectedCorpusTransferDisposition(disposition))
                case .connectedCorpusTransferFinalize(let finalize):
                    await finalizeConnectedCorpus(finalize)
                case .connectedCorpusTransferCancel(let cancel):
                    let (acknowledgement, result) = macCorpusExportSessionManager.cancel(
                        sessionID: cancel.sessionID,
                        jobID: cancel.jobID,
                        vaultManager: vaultManager
                    )
                    if let result {
                        _ = iphoneExportRequestCoordinator.complete(with: result)
                        // Match finalization ordering: publish exact durable file
                        // results before releasing the producer's cancel waiter.
                        syncService.send(.macExportResult(result))
                    }
                    syncService.send(.connectedCorpusTransferCancelAck(acknowledgement))
                    syncService.isSyncing = false
                    publishMacDestinationStatus()
                case .connectedCorpusStatus(let snapshot):
                    iphoneExportRequestCoordinator.handleCorpusStatus(
                        snapshot,
                        syncService: syncService
                    )
                    publishMacDestinationStatus(
                        activeJobID: iphoneExportRequestCoordinator.activeJobID
                    )
                case .connectedCorpusTransferDisposition, .connectedCorpusTransferFinalAck,
                     .connectedCorpusTransferCancelAck:
                    break // macOS sends these corpus acknowledgements.
                case .requestData, .requestAllData:
                    break // macOS doesn't serve data — only iOS does
                }
            }
        }
    }

    private func handleConnectedTransferStart(_ start: ConnectedTransferStart) {
        guard syncService.remoteCapabilities?.supportsSizeBoundedConnectedTransfers == true else {
            let abort = ConnectedTransferAbort(
                transferID: start.transferID,
                jobID: start.manifest.jobID,
                reason: .unsupported,
                message: "Connected peer did not negotiate size-bounded transfers."
            )
            syncService.send(.connectedTransferAbort(abort))
            handleConnectedTransferAbort(abort)
            return
        }

        let manifestAccepted: Bool
        switch start.manifest.kind {
        case .canonicalRawResultV1:
            manifestAccepted = syncService.remoteCapabilities?.supportsStrictRawStreaming == true
                && iphoneExportRequestCoordinator.accepts(start.manifest)
        case .macExportJobV1:
            let activeTransfers = connectedTransferReceiver.activeTransferIDs
            manifestAccepted = start.manifest.payloadSchemaVersion == 1
                && !macExportJobExecutor.isBusy
                && (activeTransfers.isEmpty || activeTransfers == [start.transferID])
        case .connectedCorpusPartitionV1:
            let isActiveTransportRetry = connectedTransferReceiver.activeTransferIDs.contains(start.transferID)
            manifestAccepted = syncService.remoteCapabilities?.supportsPartitionedConnectedExports == true
                && start.protocolVersion == ConnectedTransferStart.corpusPartitionProtocolVersion
                && start.manifest.payloadSchemaVersion == ConnectedCorpusPartitionFileManifest.currentVersion
                && (isActiveTransportRetry
                    || start.manifest.corpusPartition.map(
                        macCorpusExportSessionManager.consumeAdmission(for:)
                    ) == true)
        }
        guard manifestAccepted else {
            let abort = ConnectedTransferAbort(
                transferID: start.transferID,
                jobID: start.manifest.jobID,
                reason: .invalidManifest,
                message: "Transfer manifest does not match an accepted request or available Mac job."
            )
            syncService.send(.connectedTransferAbort(abort))
            handleConnectedTransferAbort(abort)
            return
        }

        switch connectedTransferReceiver.receive(start) {
        case .acknowledgement(let acknowledgement):
            syncService.isSyncing = true
            iphoneExportRequestCoordinator.handleValidatedTransferProgress(jobID: start.manifest.jobID)
            publishMacDestinationStatus(activeJobID: start.manifest.jobID)
            syncService.send(.connectedTransferAck(acknowledgement))
        case .abort(let abort):
            syncService.send(.connectedTransferAbort(abort))
            handleConnectedTransferAbort(abort)
        }
    }

    private func handleConnectedTransferChunk(_ chunk: ConnectedTransferChunk) {
        switch connectedTransferReceiver.receive(chunk) {
        case .acknowledgement(let acknowledgement):
            iphoneExportRequestCoordinator.handleValidatedTransferProgress(
                jobID: macCorpusExportSessionManager.activeJobID ?? chunk.transferID
            )
            syncService.send(.connectedTransferAck(acknowledgement))
        case .abort(let abort):
            syncService.send(.connectedTransferAbort(abort))
            handleConnectedTransferAbort(abort)
        }
    }

    private func handleConnectedTransferComplete(_ complete: ConnectedTransferComplete) async {
        switch connectedTransferReceiver.receive(complete) {
        case .pending:
            break // The original completion path will send the post-persistence final ACK.
        case .replay(let acknowledgement):
            syncService.send(.connectedTransferFinalAck(acknowledgement))
        case .abort(let abort):
            syncService.send(.connectedTransferAbort(abort))
            handleConnectedTransferAbort(abort)
        case .ready(let ready):
            do {
                if ready.start.manifest.kind == .connectedCorpusPartitionV1 {
                    guard let descriptor = ready.start.manifest.corpusPartition else {
                        rejectReadyConnectedTransfer(
                            ready,
                            reason: .invalidManifest,
                            message: "Corpus partition descriptor is missing."
                        )
                        return
                    }
                    try await macCorpusExportSessionManager.applyPartition(
                        fileURL: ready.fileURL,
                        descriptor: descriptor,
                        vaultManager: vaultManager
                    )
                    guard let acknowledgement = connectedTransferReceiver.finish(
                        transferID: ready.start.transferID,
                        accepted: true
                    ) else { return }
                    iphoneExportRequestCoordinator.handleValidatedTransferProgress(jobID: descriptor.jobID)
                    syncService.send(.connectedTransferFinalAck(acknowledgement))
                    return
                }

                let data = try Data(contentsOf: ready.fileURL, options: [.mappedIfSafe])
                let decoder = JSONDecoder()
                switch ready.start.manifest.kind {
                case .canonicalRawResultV1:
                    let result = try decoder.decode(CanonicalRawResultEnvelope.self, from: data)
                    guard result.schema == CanonicalRawResultEnvelope.schemaIdentifier,
                          result.schemaVersion == ready.start.manifest.payloadSchemaVersion,
                          iphoneExportRequestCoordinator.complete(
                            with: result,
                            jobID: ready.start.manifest.jobID
                          ) else {
                        rejectReadyConnectedTransfer(
                            ready,
                            reason: .applicationRejected,
                            message: "Strict raw result did not match the pending request."
                        )
                        return
                    }
                    guard let acknowledgement = connectedTransferReceiver.finish(
                        transferID: ready.start.transferID,
                        accepted: true
                    ) else { return }
                    syncService.isSyncing = false
                    syncService.send(.connectedTransferFinalAck(acknowledgement))
                    publishMacDestinationStatus()
                case .macExportJobV1:
                    let job = try decoder.decode(MacExportJob.self, from: data)
                    guard job.jobID == ready.start.manifest.jobID else {
                        rejectReadyConnectedTransfer(
                            ready,
                            reason: .invalidManifest,
                            message: "Decoded Mac export job identifier did not match its manifest."
                        )
                        return
                    }
                    guard let acknowledgement = connectedTransferReceiver.finish(
                        transferID: ready.start.transferID,
                        accepted: true
                    ) else { return }
                    syncService.send(.connectedTransferFinalAck(acknowledgement))
                    await executeMacExportJob(job)
                case .connectedCorpusPartitionV1:
                    break // Handled without whole-file mapping above.
                }
            } catch {
                rejectReadyConnectedTransfer(
                    ready,
                    reason: .decodeFailure,
                    message: "Verified connected transfer could not be decoded."
                )
            }
        }
    }

    private func finalizeConnectedCorpus(_ finalize: ConnectedCorpusTransferFinalize) async {
        do {
            let outcome = try await macCorpusExportSessionManager.finalize(
                finalize,
                vaultManager: vaultManager,
                progress: { processed, total, date in
                    let progress = MacExportProgress(
                        jobID: finalize.jobID,
                        phase: .writing,
                        processedDays: processed,
                        totalDays: max(total, 1),
                        currentDate: date,
                        filesWritten: 0,
                        message: "Finalizing partitioned corpus outputs…"
                    )
                    publishMacExportProgress(progress)
                    iphoneExportRequestCoordinator.handleMacExportProgress(progress)
                }
            )
            syncService.isSyncing = false
            switch outcome {
            case .inProgress:
                syncService.isSyncing = true
                iphoneExportRequestCoordinator.handleValidatedTransferProgress(jobID: finalize.jobID)
            case .replay(let acknowledgement, let fileResult):
                if let fileResult {
                    syncService.lastMacExportResult = fileResult
                    syncService.lastMacExportFailure = nil
                    _ = iphoneExportRequestCoordinator.complete(with: fileResult)
                    syncService.send(.macExportResult(fileResult))
                }
                syncService.send(.connectedCorpusTransferFinalAck(acknowledgement))
            case .files(let result, let acknowledgement):
                syncService.lastMacExportResult = result
                syncService.lastMacExportFailure = nil
                _ = iphoneExportRequestCoordinator.complete(with: result)
                syncService.send(.macExportResult(result))
                syncService.send(.connectedCorpusTransferFinalAck(acknowledgement))
            case .strictRaw(let spool, let acknowledgement):
                guard await iphoneExportRequestCoordinator.complete(
                    with: spool,
                    jobID: finalize.jobID
                ) else {
                    spool.remove()
                    syncService.send(.connectedCorpusTransferFinalAck(ConnectedCorpusTransferFinalAck(
                        sessionID: finalize.sessionID,
                        jobID: finalize.jobID,
                        accepted: false,
                        requestFingerprint: finalize.requestFingerprint,
                        finalPartitionSHA256: finalize.finalPartitionSHA256,
                        message: "Strict raw corpus no longer matches an active control request."
                    )))
                    publishMacDestinationStatus()
                    return
                }
                syncService.send(.connectedCorpusTransferFinalAck(acknowledgement))
            }
            publishMacDestinationStatus()
        } catch {
            _ = macCorpusExportSessionManager.cancel(
                sessionID: finalize.sessionID,
                jobID: finalize.jobID,
                vaultManager: vaultManager
            )
            syncService.isSyncing = false
            let acknowledgement = ConnectedCorpusTransferFinalAck(
                sessionID: finalize.sessionID,
                jobID: finalize.jobID,
                accepted: false,
                requestFingerprint: finalize.requestFingerprint,
                finalPartitionSHA256: finalize.finalPartitionSHA256,
                message: "Mac could not finalize the partitioned corpus export."
            )
            syncService.send(.connectedCorpusTransferFinalAck(acknowledgement))
            let failure = MacExportFailure(
                jobID: finalize.jobID,
                reason: .exportWriteFailure,
                message: "Mac could not finalize the partitioned corpus export."
            )
            syncService.lastMacExportFailure = failure
            _ = iphoneExportRequestCoordinator.complete(with: failure)
            syncService.send(.macExportFailed(failure))
            publishMacDestinationStatus()
        }
    }

    private func rejectReadyConnectedTransfer(
        _ ready: ConnectedTransferReceiver.ReadyTransfer,
        reason: ConnectedTransferAbortReason,
        message: String
    ) {
        if let acknowledgement = connectedTransferReceiver.finish(
            transferID: ready.start.transferID,
            accepted: false,
            reason: reason,
            message: message
        ) {
            syncService.send(.connectedTransferFinalAck(acknowledgement))
        }
        syncService.isSyncing = false
        handleConnectedTransferAbort(ConnectedTransferAbort(
            transferID: ready.start.transferID,
            jobID: ready.start.manifest.jobID,
            reason: reason,
            message: message
        ))
        publishMacDestinationStatus()
    }

    private func handleConnectedTransferAbort(_ abort: ConnectedTransferAbort) {
        guard let jobID = abort.jobID else { return }
        if macCorpusExportSessionManager.activeJobID == jobID,
           abort.transferID != jobID {
            // A physical partition may be retried with the same descriptor and
            // transfer ID. Do not terminate the durable parent session merely
            // because one transport attempt aborted.
            iphoneExportRequestCoordinator.handleValidatedTransferProgress(jobID: jobID)
            publishMacDestinationStatus(activeJobID: jobID)
            return
        }
        let isRelevant = iphoneExportRequestCoordinator.activeJobID == jobID
            || macExportJobExecutor.currentJobID == jobID
            || macCorpusExportSessionManager.activeJobID == jobID
            || connectedTransferReceiver.activeTransferIDs.contains(abort.transferID)
        guard isRelevant else { return }
        syncService.isSyncing = false
        let failure = MacExportFailure(
            jobID: jobID,
            reason: abort.reason == .cancelled ? .cancelled : .payloadDecodeFailure,
            message: abort.message
        )
        syncService.lastMacExportFailure = failure
        _ = iphoneExportRequestCoordinator.complete(with: failure)
        publishMacDestinationStatus()
    }

    private func executeMacExportJob(_ job: MacExportJob) async {
        if !macExportJobExecutor.isBusy,
           vaultManager.vaultURL != nil,
           vaultManager.canAccessSelectedVaultFolder(),
           job.settingsSnapshot.hasFileDestinationOutput,
           !job.records.isEmpty {
            syncService.send(.macExportAccepted(MacExportAcknowledgement(
                jobID: job.jobID,
                acceptedAt: Date(),
                message: "Mac export accepted."
            )))
        }
        syncService.isSyncing = true
        syncService.activeMacExportProgress = nil
        syncService.lastMacExportResult = nil
        syncService.lastMacExportFailure = nil
        publishMacDestinationStatus(activeJobID: job.jobID)
        let result = await macExportJobExecutor.execute(
            job,
            vaultManager: vaultManager,
            progress: { progress in
                publishMacExportProgress(progress)
                iphoneExportRequestCoordinator.handleMacExportProgress(progress)
            }
        )
        syncService.isSyncing = false
        switch result {
        case .success(let payload):
            syncService.lastMacExportResult = payload
            syncService.lastMacExportFailure = nil
            recordMacAgentHistory(for: job, result: payload)
            recordMacAgentActivity(for: job, result: payload)
            _ = iphoneExportRequestCoordinator.complete(with: payload)
            syncService.send(.macExportResult(payload))
        case .failure(let failure):
            syncService.lastMacExportFailure = failure
            syncService.lastMacExportResult = nil
            recordMacAgentHistory(for: job, failure: failure)
            recordMacAgentActivity(for: job, failure: failure)
            _ = iphoneExportRequestCoordinator.complete(with: failure)
            syncService.send(.macExportFailed(failure))
        }
        publishMacDestinationStatus()
    }

    private func publishMacExportProgress(_ progress: MacExportProgress) {
        syncService.activeMacExportProgress = progress
        if macExportProgressThrottler.shouldPublish(progress) {
            syncService.send(.macExportProgress(progress))
        }
    }

    private func publishMacDestinationStatus(activeJobID: UUID? = nil) {
        guard syncService.connectionState == .connected else { return }
        syncService.send(.macStatus(makeMacDestinationStatus(activeJobID: activeJobID)))
    }

    private func suspendCorpusSessionForDisconnect() {
        macCorpusExportSessionManager.suspendForDisconnect()
        syncService.isSyncing = false
    }

    private func cancelOrphanedStreamIfNeeded(message: String) {
        guard let jobID = macExportJobExecutor.currentJobID,
              let failure = macExportJobExecutor.cancel(
                jobID: jobID,
                message: message,
                progress: { progress in
                    syncService.activeMacExportProgress = progress
                }
              ) else { return }

        syncService.isSyncing = false
        syncService.lastMacExportFailure = failure
        // The local legacy stream is not resumable, but the durable request is.
        // Keep it paused so reconnect/hello can resend the exact request.
    }

    private func setupControlServer() {
        controlServer.start(
            statusProvider: { makeControlStatus() },
            exportHandler: { request in
                await iphoneExportRequestCoordinator.requestExport(
                    request,
                    syncService: syncService,
                    destinationStatus: makeMacDestinationStatus(activeJobID: iphoneExportRequestCoordinator.activeJobID)
                )
            },
            jobStatusHandler: { jobID in
                iphoneExportRequestCoordinator.jobResponse(jobID: jobID)
            },
            resumeExportHandler: { jobID, timeout in
                await iphoneExportRequestCoordinator.resumeExport(
                    jobID: jobID,
                    waitTimeoutSeconds: timeout,
                    syncService: syncService,
                    destinationStatus: makeMacDestinationStatus(activeJobID: nil)
                )
            },
            explicitCancelExportHandler: { jobID in
                iphoneExportRequestCoordinator.cancelExport(jobID: jobID, syncService: syncService)
            },
            cancelExportHandler: { jobID in
                iphoneExportRequestCoordinator.cancelRequestForDisconnectedClient(jobID: jobID)
            }
        )
    }

    private func makeControlStatus() -> HealthMdControlServer.StatusResponse {
        let durableJobID = iphoneExportRequestCoordinator.activeJobID
        let durableResponse = durableJobID.map { iphoneExportRequestCoordinator.jobResponse(jobID: $0) }
        let destinationStatus = makeMacDestinationStatus(activeJobID: durableJobID)
        let canTriggerRaw = syncService.connectionState == .connected
            && (syncService.remoteCapabilities?.platform == .iOS)
            && (syncService.remoteCapabilities?.supportsIPhoneExportRequests == true)
            && (syncService.remoteCapabilities?.supports(rawProfile: .canonicalSourceRecordsV1) == true)
            && iphoneExportRequestCoordinator.activeJobID == nil
            && macExportJobExecutor.currentJobID == nil
            && macCorpusExportSessionManager.activeJobID == nil
        let canTrigger = canTriggerRaw && destinationStatus.canReceiveExports
        return HealthMdControlServer.StatusResponse(
            macApp: "running",
            iphone: HealthMdControlServer.StatusResponse.IPhone(
                connected: syncService.connectionState == .connected,
                name: syncService.connectedPeerName,
                canTriggerExports: canTrigger,
                canTriggerRawExports: canTriggerRaw
            ),
            destination: HealthMdControlServer.StatusResponse.Destination(
                selected: vaultManager.isVaultConfigured,
                writable: vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder(),
                path: vaultManager.vaultURL?.path,
                displayName: vaultManager.vaultURL == nil ? nil : vaultManager.vaultName
            ),
            activeExport: iphoneExportRequestCoordinator.activeJobID == nil
                && macExportJobExecutor.currentJobID == nil
                && macCorpusExportSessionManager.activeJobID == nil
                ? nil
                : HealthMdControlServer.StatusResponse.ActiveExport(
                    jobID: durableJobID
                        ?? macExportJobExecutor.currentJobID
                        ?? macCorpusExportSessionManager.activeJobID,
                    message: durableResponse?.message
                        ?? iphoneExportRequestCoordinator.latestProgress?.message
                        ?? syncService.activeMacExportProgress?.message,
                    fractionComplete: durableResponse?.fractionComplete
                        ?? iphoneExportRequestCoordinator.latestProgress?.fractionComplete
                        ?? syncService.activeMacExportProgress?.fractionComplete,
                    durable: durableResponse?.durable,
                    paused: durableResponse?.paused,
                    processedDays: durableResponse?.processedDays,
                    totalDays: durableResponse?.totalCount,
                    expiresAt: durableResponse?.expiresAt,
                    state: durableResponse?.durableState,
                    sessionID: durableResponse?.sessionID,
                    committedPartitions: durableResponse?.committedPartitions,
                    committedBytes: durableResponse?.committedBytes
                )
        )
    }

    private func makeMacDestinationStatus(activeJobID: UUID? = nil) -> MacDestinationStatus {
        let effectiveActiveJobID = activeJobID
            ?? macExportJobExecutor.currentJobID
            ?? macCorpusExportSessionManager.activeJobID
            ?? iphoneExportRequestCoordinator.activeJobID
        let hasDestination = vaultManager.isVaultConfigured
        let folderAccessHealthy = vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
        let destinationError = hasDestination && !folderAccessHealthy
            ? "Reconnect or re-select the destination folder on this Mac to restore export access."
            : syncService.lastError

        return MacDestinationStatus(
            isConnected: syncService.connectionState == .connected,
            isReadyForExports: hasDestination && folderAccessHealthy && effectiveActiveJobID == nil,
            destinationFolderSelected: hasDestination,
            folderAccessHealthy: folderAccessHealthy,
            destinationDisplayName: hasDestination ? vaultManager.vaultName : nil,
            destinationPathForDisplay: vaultManager.vaultURL?.path,
            lastError: destinationError,
            activeJobID: effectiveActiveJobID,
            capabilities: .current(platform: .macOS)
        )
    }

    private func recordMacAgentHistory(for job: MacExportJob, result: MacExportResultPayload) {
        let exportResult = ExportOrchestrator.ExportResult(
            successCount: result.successCount,
            totalCount: result.totalCount,
            failedDateDetails: result.failedDateDetails,
            formatsPerDate: result.formatsPerDate,
            externalRecordFileCount: result.externalRecordFileCount,
            dailyNoteUpdateCount: result.dailyNoteUpdateCount,
            dailyNoteSkipCount: result.dailyNoteSkipCount,
            wasCancelled: result.status == .cancelled
        )
        ExportOrchestrator.recordResult(
            exportResult,
            source: .macAgent,
            dateRangeStart: job.dateRangeStart,
            dateRangeEnd: job.dateRangeEnd,
            targetLabel: job.requestedTarget?.destinationDisplayName ?? job.requestedTarget?.displayName ?? "Mac",
            fileCount: result.totalFilesWritten
        )
    }

    private func recordMacAgentHistory(for job: MacExportJob, failure: MacExportFailure) {
        let failedDetail = FailedDateDetail(
            date: job.dateRangeStart,
            reason: exportFailureReason(for: failure.reason),
            errorDetails: failure.underlyingError ?? failure.message
        )
        let totalCount = max(ExportOrchestrator.dateRange(from: job.dateRangeStart, to: job.dateRangeEnd).count, 1)
        let exportResult = ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: totalCount,
            failedDateDetails: [failedDetail],
            formatsPerDate: job.settingsSnapshot.makeAdvancedExportSettings().looseFormatsPerDate,
            wasCancelled: failure.reason == .cancelled
        )
        ExportOrchestrator.recordResult(
            exportResult,
            source: .macAgent,
            dateRangeStart: job.dateRangeStart,
            dateRangeEnd: job.dateRangeEnd,
            targetLabel: job.requestedTarget?.destinationDisplayName ?? job.requestedTarget?.displayName ?? "Mac",
            fileCount: 0
        )
    }

    private func recordMacAgentActivity(for job: MacExportJob, result: MacExportResultPayload) {
        SyncEventHistoryManager.shared.record(SyncEvent(
            peerName: job.sourceDeviceName,
            kind: syncEventKind(for: result.status),
            recordCount: max(result.totalFilesWritten, result.dailyNoteUpdateCount),
            dateRangeStart: job.dateRangeStart,
            dateRangeEnd: job.dateRangeEnd,
            failureMessage: activityFailureMessage(for: result)
        ))
    }

    private func recordMacAgentActivity(for job: MacExportJob, failure: MacExportFailure) {
        SyncEventHistoryManager.shared.record(SyncEvent(
            peerName: job.sourceDeviceName,
            kind: failure.reason == .cancelled ? .macExportCancelled : .macExportFailed,
            recordCount: 0,
            dateRangeStart: job.dateRangeStart,
            dateRangeEnd: job.dateRangeEnd,
            failureMessage: failure.message
        ))
    }

    private func syncEventKind(for status: MacExportResultStatus) -> SyncEventKind {
        switch status {
        case .success:
            return .macExportSucceeded
        case .partialSuccess:
            return .macExportPartialSuccess
        case .failure:
            return .macExportFailed
        case .cancelled:
            return .macExportCancelled
        }
    }

    private func activityFailureMessage(for result: MacExportResultPayload) -> String? {
        switch result.status {
        case .success:
            return nil
        case .partialSuccess:
            if result.dailyNoteSkipCount > 0,
               result.completedDates?.count == result.totalCount {
                return "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) missing daily note(s); no export files were created."
            }
            return "Mac export wrote \(result.totalFilesWritten) file(s); \(result.failedDateDetails.count) date(s) need attention."
        case .failure:
            return result.failedDateDetails.first?.reason.shortDescription ?? "Mac export failed"
        case .cancelled:
            return result.successCount > 0
                ? "Mac export stopped after writing \(result.totalFilesWritten) file(s)."
                : "Mac export cancelled"
        }
    }

    private func exportFailureReason(for reason: MacExportFailureReason) -> ExportFailureReason {
        switch reason {
        case .noMacFolderSelected:
            return .noVaultSelected
        case .macFolderAccessDenied:
            return .accessDenied
        case .noHealthRecordsReceived:
            return .noHealthData
        case .exportWriteFailure:
            return .fileWriteError
        case .cancelled:
            return .unknown
        case .incompatibleProtocol, .noFormatsSelected, .payloadDecodeFailure, .macBusy:
            return .unknown
        }
    }

    private func syncEvent(from payload: SyncPayload) -> SyncEvent {
        let dates = payload.healthRecords.map(\.date)
        let byteEstimate = (try? JSONEncoder().encode(payload).count) ?? 0
        return SyncEvent(
            timestamp: payload.syncTimestamp,
            peerName: payload.deviceName,
            kind: .dataReceived,
            recordCount: payload.healthRecords.count,
            payloadByteEstimate: byteEstimate,
            dateRangeStart: dates.min(),
            dateRangeEnd: dates.max()
        )
    }
}

// MARK: - Window Manager Bridge

/// Captures the SwiftUI `openWindow` action and stores it in the shared
/// `WindowManager` so that AppKit code (app delegate, menu bar extra) can
/// re-open the main window reliably.
private struct WindowManagerBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowManager.shared.openMainWindow = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main-window")
                }
            }
    }
}

extension View {
    func withWindowManagerBridge() -> some View {
        modifier(WindowManagerBridge())
    }

    func gradientMatchedTitleBar() -> some View {
        background(GradientMatchedTitleBarConfigurator())
    }
}

private struct GradientMatchedTitleBarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        // Keep the titlebar transparent to Health.md's own content, not to the
        // desktop behind the window. This fallback color matches the top of the
        // Mac destination backdrop if AppKit paints before SwiftUI fills in.
        window.backgroundColor = NSColor(
            calibratedRed: 0x17 / 255,
            green: 0x17 / 255,
            blue: 0x1F / 255,
            alpha: 1
        )
        window.isOpaque = true
    }
}

// MARK: - Commands

private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File ▸ Show Health.md  (⌘0) — always available even when Window menu is empty
        CommandGroup(after: .newItem) {
            Button("Show Health.md") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main-window")
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        // Window ▸ Health.md — standard location users expect
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Health.md") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main-window")
            }
            .keyboardShortcut("1", modifiers: .command)
        }
    }
}

#endif
