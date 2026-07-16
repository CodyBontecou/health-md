import Foundation
import Combine
import CryptoKit
import MultipeerConnectivity
import Network
import os.log
#if os(iOS)
import UIKit
#endif

// MARK: - Connection State

enum SyncConnectionState: String, Equatable {
    case disconnected = "Disconnected"
    case connecting = "Connecting…"
    case connected = "Connected"
}

enum SyncTransportKind: String, Equatable {
    case multipeer
    case manualIP
}

// MARK: - Sync Service

/// Manages Multipeer Connectivity for syncing health data between iOS and macOS.
///
/// - iOS: Advertises as a data source (MCNearbyServiceAdvertiser)
/// - macOS: Browses for iPhones (MCNearbyServiceBrowser)
/// - Both: Sends and receives `SyncMessage` via MCSession
@MainActor
final class SyncService: NSObject, ObservableObject {

    // MARK: - Constants

    static let serviceType = "healthmd-sync" // 1-15 chars, lowercase + hyphens
    nonisolated static let manualIPPort: UInt16 = 17_646

    // MARK: - Published State

    @Published var connectionState: SyncConnectionState = .disconnected
    @Published var connectedPeerName: String?
    @Published var lastError: String?
    @Published var discoveredPeers: [MCPeerID] = []
    @Published private(set) var activeTransport: SyncTransportKind = .multipeer

    #if os(macOS)
    @Published private(set) var manualIPServerEnabled: Bool = UserDefaults.standard.bool(forKey: "manualIPServerEnabled")
    @Published private(set) var manualIPServerListening: Bool = false
    @Published private(set) var manualIPPairingCode: String?
    @Published private(set) var manualIPPairingCodeExpiresAt: Date?
    @Published private(set) var manualIPAddresses: [ManualIPNetworkAddress] = []
    #endif

    #if os(iOS)
    @Published private(set) var manualIPLastHost: String = UserDefaults.standard.string(forKey: "manualIPLastHost") ?? ""
    #endif

    /// Latest v2 capabilities announced by the connected peer, if any.
    @Published var remoteCapabilities: SyncPeerCapabilities?

    /// Latest macOS destination/readiness status announced to iOS.
    @Published var macDestinationStatus: MacDestinationStatus?

    /// Latest Mac export job response received by iOS.
    @Published private(set) var latestMacExportMessage: SyncMessage?

    /// Current Mac export-agent progress shown by the macOS destination UI.
    @Published var activeMacExportProgress: MacExportProgress?

    /// Most recent Mac export-agent result shown by the macOS destination UI.
    @Published var lastMacExportResult: MacExportResultPayload?

    /// Most recent Mac export-agent preflight/execution failure shown by the macOS destination UI.
    @Published var lastMacExportFailure: MacExportFailure?

    /// True when the connected peer has announced compatible v2 capabilities and
    /// the Mac destination is selected, accessible, and idle.
    var canExportToConnectedMac: Bool {
        guard connectionState == .connected else { return false }
        guard let remoteCapabilities,
              remoteCapabilities.platform == .macOS,
              remoteCapabilities.isCompatibleWithMacExportJobs else {
            return false
        }
        return macDestinationStatus?.canReceiveExports == true
    }

    /// User-facing reason the Mac export target is not currently available.
    var macExportReadinessMessage: String {
        guard connectionState == .connected else {
            return "Open Health.md on your Mac to connect"
        }
        guard let remoteCapabilities else {
            return "Waiting for Mac destination status"
        }
        guard remoteCapabilities.platform == .macOS,
              remoteCapabilities.isCompatibleWithMacExportJobs else {
            return "Update Health.md on Mac"
        }
        guard let macDestinationStatus else {
            return "Waiting for Mac destination status"
        }
        return macDestinationStatus.notReadyReason ?? "Ready to export to Mac"
    }

    func canExportToConnectedMac(requiring settings: AdvancedExportSettings) -> Bool {
        guard canExportToConnectedMac else { return false }
        return remoteCapabilities?.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: settings.rollupSummariesEnabled,
            summaryOnlyExportEnabled: settings.summaryOnlyModeEnabled,
            effectiveGranularDataEnabled: ConnectedExportGranularMode.isEnabled(for: settings)
        ) == true
    }

    func macExportReadinessMessage(requiring settings: AdvancedExportSettings) -> String {
        let baseMessage = macExportReadinessMessage
        guard canExportToConnectedMac else { return baseMessage }
        guard remoteCapabilities?.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: settings.rollupSummariesEnabled,
            summaryOnlyExportEnabled: settings.summaryOnlyModeEnabled,
            effectiveGranularDataEnabled: ConnectedExportGranularMode.isEnabled(for: settings)
        ) == true else {
            if settings.summaryOnlyModeEnabled {
                return "Update Health.md on Mac to export summary-only roll-ups"
            }
            if settings.rollupSummariesEnabled {
                return "Update Health.md on Mac to export roll-up summaries"
            }
            if ConnectedExportGranularMode.isEnabled(for: settings) {
                return "Update Health.md on Mac to export Lossless Health Records"
            }
            return "Update Health.md on Mac"
        }
        return baseMessage
    }

    /// Whether a sync operation is actively in progress.
    /// Setting this keeps the device awake (iOS) and requests background execution time.
    @Published var isSyncing: Bool = false {
        didSet {
            guard oldValue != isSyncing else { return }
            if isSyncing {
                beginKeepAwake()
            } else {
                endKeepAwake()
            }
        }
    }

    // MARK: - Keep-Awake State

    #if os(iOS)
    /// Background task identifier so the sync can finish if the app is briefly backgrounded.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    // MARK: - Callback

    /// Called when a `SyncMessage` is received from the connected peer.
    var onMessageReceived: ((SyncMessage) -> Void)?

    #if DEBUG
    /// Unit-test observation only. Production operational logging must never
    /// inspect raw payload contents.
    var testMessageSendObserver: ((SyncMessage) -> Void)?
    #endif

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.codybontecou.obsidianhealth", category: "SyncService")
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var connectedMultipeerPeerID: MCPeerID?

    private var manualConnection: NWConnection?
    private var manualReceiveBuffer = Data()
    private var manualSessionKey: SymmetricKey?
    private var manualConnectionHasPaired = false

    #if os(iOS)
    private var manualClientPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var manualClientNonce: Data?
    private var manualClientPairingCode: String?
    #endif

    #if os(macOS)
    private var manualListener: NWListener?
    private var manualServerPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    #endif

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var connectionHeartbeatTask: Task<Void, Never>?

    private struct MacExportStreamAckWaiterKey: Hashable {
        let jobID: UUID
        let sequence: Int
    }

    private var macExportStreamAckContinuations: [MacExportStreamAckWaiterKey: CheckedContinuation<MacExportStreamChunkAck?, Never>] = [:]
    private var macExportStreamAckTimeoutTasks: [MacExportStreamAckWaiterKey: Task<Void, Never>] = [:]

    private struct ConnectedTransferAckWaiterKey: Hashable {
        let transferID: UUID
        let sequence: Int
    }

    private var connectedTransferAckContinuations: [ConnectedTransferAckWaiterKey: CheckedContinuation<ConnectedTransferAck?, Never>] = [:]
    private var connectedTransferAckTimeoutTasks: [ConnectedTransferAckWaiterKey: Task<Void, Never>] = [:]
    private var connectedTransferFinalAckContinuations: [UUID: CheckedContinuation<ConnectedTransferFinalAck?, Never>] = [:]
    private var connectedTransferFinalAckTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var receivedConnectedTransferAborts: [UUID: ConnectedTransferAbort] = [:]

    // MARK: - Init

    override init() {
        #if os(iOS)
        let deviceName = UIDevice.current.name
        #elseif os(macOS)
        let deviceName = Host.current().localizedName ?? "Mac"
        #endif

        self.myPeerID = MCPeerID(displayName: deviceName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)

        super.init()

        // MCSessionDelegate is nonisolated — assign via nonisolated helper
        session.delegate = self
        configureForUITestingIfNeeded()
    }

    deinit {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        connectionHeartbeatTask?.cancel()
        manualConnection?.cancel()
        #if os(macOS)
        manualListener?.cancel()
        #endif
        session.disconnect()
    }

    // MARK: - iOS: Advertising

    /// Start advertising this device as a health data source (iOS).
    func startAdvertising() {
        guard advertiser == nil else { return }
        logger.info("Starting advertiser")
        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        self.advertiser = adv
    }

    /// Stop advertising.
    func stopAdvertising() {
        logger.info("Stopping advertiser")
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    // MARK: - macOS: Browsing

    /// Start browsing for nearby iPhones (macOS).
    func startBrowsing() {
        guard browser == nil else { return }
        logger.info("Starting browser")
        discoveredPeers = []
        let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        self.browser = br
    }

    /// Stop browsing.
    func stopBrowsing() {
        logger.info("Stopping browser")
        browser?.stopBrowsingForPeers()
        browser = nil
        discoveredPeers = []
    }

    /// Invite a discovered peer to connect (macOS → iOS).
    func connectToPeer(_ peer: MCPeerID) {
        logger.info("Inviting peer: \(peer.displayName)")
        cancelManualConnection(updatePublicState: false)
        activeTransport = .multipeer
        connectionState = .connecting
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    // MARK: - Disconnect

    func disconnect() {
        logger.info("Disconnecting session")
        isSyncing = false
        session.disconnect()
        cancelManualConnection(updatePublicState: false)
        stopConnectionHeartbeat()
        activeTransport = .multipeer
        connectedMultipeerPeerID = nil
        connectionState = .disconnected
        connectedPeerName = nil
        remoteCapabilities = nil
        macDestinationStatus = nil
        latestMacExportMessage = nil
        activeMacExportProgress = nil
        lastMacExportResult = nil
        lastMacExportFailure = nil
        cancelAllMacExportStreamAckWaiters()
        cancelAllConnectedTransferWaiters()
    }

    func publishMacExportMessage(_ message: SyncMessage) {
        latestMacExportMessage = message
    }

    /// Send one Mac-export stream message and wait for the Mac's application-level
    /// acknowledgement before allowing the next stream step to proceed.
    ///
    /// Multipeer `sendResource` is asynchronous: it only queues the transfer. For
    /// streamed exports we must wait for `macExportStreamChunkAck`, otherwise the
    /// final `macExportStreamComplete` data message can outrun resource transfers.
    func sendMacExportStreamPayloadAndWaitForAck(
        _ message: SyncMessage,
        jobID: UUID,
        sequence: Int,
        timeoutSeconds: TimeInterval = 15,
        maximumAttempts: Int = 3
    ) async -> MacExportStreamChunkAck? {
        for _ in 0..<max(maximumAttempts, 1) {
            if Task.isCancelled { return nil }
            if let acknowledgement = await sendMacExportStreamPayloadOnceAndWaitForAck(
                message,
                jobID: jobID,
                sequence: sequence,
                timeoutSeconds: timeoutSeconds
            ) {
                return acknowledgement
            }
        }
        return nil
    }

    private func sendMacExportStreamPayloadOnceAndWaitForAck(
        _ message: SyncMessage,
        jobID: UUID,
        sequence: Int,
        timeoutSeconds: TimeInterval
    ) async -> MacExportStreamChunkAck? {
        let key = MacExportStreamAckWaiterKey(jobID: jobID, sequence: sequence)
        return await withCheckedContinuation { continuation in
            resumeMacExportStreamAckWaiter(for: key, with: nil)

            macExportStreamAckContinuations[key] = continuation
            let timeoutNanoseconds = UInt64(max(timeoutSeconds, 0.001) * 1_000_000_000)
            macExportStreamAckTimeoutTasks[key] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                await MainActor.run {
                    self?.resumeMacExportStreamAckWaiter(for: key, with: nil)
                }
            }

            guard sendLargePayload(message) else {
                resumeMacExportStreamAckWaiter(for: key, with: nil)
                return
            }
        }
    }

    @discardableResult
    func resolveMacExportStreamChunkAck(_ ack: MacExportStreamChunkAck) -> Bool {
        let key = MacExportStreamAckWaiterKey(jobID: ack.jobID, sequence: ack.sequence)
        guard macExportStreamAckContinuations[key] != nil else { return false }
        resumeMacExportStreamAckWaiter(for: key, with: ack)
        return true
    }

    func cancelMacExportStreamAckWaiters(jobID: UUID) {
        let keys = macExportStreamAckContinuations.keys.filter { $0.jobID == jobID }
        for key in keys {
            resumeMacExportStreamAckWaiter(for: key, with: nil)
        }
    }

    func cancelAllMacExportStreamAckWaiters() {
        let keys = Array(macExportStreamAckContinuations.keys)
        for key in keys {
            resumeMacExportStreamAckWaiter(for: key, with: nil)
        }
    }

    private func resumeMacExportStreamAckWaiter(
        for key: MacExportStreamAckWaiterKey,
        with ack: MacExportStreamChunkAck?
    ) {
        guard let continuation = macExportStreamAckContinuations.removeValue(forKey: key) else { return }
        macExportStreamAckTimeoutTasks.removeValue(forKey: key)?.cancel()
        continuation.resume(returning: ack)
    }

    /// Sends a restricted temporary file as a stop-and-wait stream. Start, every
    /// chunk, and completion are retried a bounded number of times. The receiver
    /// validates and spools each chunk before its acknowledgement is accepted.
    func sendConnectedTransfer(
        _ preparedFile: ConnectedTransferPreparedFile,
        manifest: ConnectedTransferManifest,
        chunkBytes: Int = ConnectedTransferReceiver.maximumChunkBytes,
        acknowledgementTimeout: TimeInterval = 15,
        maximumAttempts: Int = 3,
        onValidatedProgress: ((_ acceptedChunks: Int, _ totalChunks: Int) -> Void)? = nil
    ) async -> ConnectedTransferSendResult {
        let transferID = manifest.jobID
        receivedConnectedTransferAborts.removeValue(forKey: transferID)
        guard remoteCapabilities?.supportsSizeBoundedConnectedTransfers == true else {
            return .failure(ConnectedTransferAbort(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .unsupported,
                message: "Connected peer does not support size-bounded transfers."
            ))
        }
        guard chunkBytes > 0,
              chunkBytes <= ConnectedTransferReceiver.maximumChunkBytes,
              preparedFile.totalBytes >= 0,
              preparedFile.totalBytes <= ConnectedTransferReceiver.maximumTotalBytes else {
            return .failure(ConnectedTransferAbort(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .sizeLimit,
                message: "Transfer exceeds the negotiated size limits."
            ))
        }

        let totalChunks = preparedFile.totalBytes == 0
            ? 0
            : Int((preparedFile.totalBytes + Int64(chunkBytes) - 1) / Int64(chunkBytes))
        guard totalChunks <= ConnectedTransferReceiver.maximumChunkCount else {
            return .failure(ConnectedTransferAbort(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .sizeLimit,
                message: "Transfer requires too many chunks."
            ))
        }

        let start = ConnectedTransferStart(
            protocolVersion: ConnectedTransferStart.currentProtocolVersion,
            transferID: transferID,
            manifest: manifest,
            totalBytes: preparedFile.totalBytes,
            totalChunks: totalChunks,
            chunkBytes: chunkBytes,
            sha256: preparedFile.sha256
        )
        let startMessage = SyncMessage.connectedTransferStart(start)
        guard let startAck = await sendConnectedTransferMessageWithRetry(
            startMessage,
            transferID: transferID,
            sequence: 0,
            expectedSHA256: preparedFile.sha256,
            timeout: acknowledgementTimeout,
            maximumAttempts: maximumAttempts
        ), startAck.accepted else {
            if let abort = receivedConnectedTransferAborts.removeValue(forKey: transferID) {
                return .failure(abort)
            }
            return abortConnectedTransfer(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .retriesExhausted,
                message: "Peer did not accept the transfer start after \(maximumAttempts) attempt(s)."
            )
        }
        onValidatedProgress?(0, totalChunks)

        do {
            let handle = try FileHandle(forReadingFrom: preparedFile.url)
            defer { try? handle.close() }
            if totalChunks > 0 {
                for sequence in 1...totalChunks {
                    try Task.checkCancellation()
                    guard let data = try handle.read(upToCount: chunkBytes), !data.isEmpty else {
                        return abortConnectedTransfer(
                            transferID: transferID,
                            jobID: manifest.jobID,
                            reason: .sizeLimit,
                            message: "Transfer source ended before its declared length."
                        )
                    }
                    let chunkHash = ConnectedTransferFile.sha256Hex(data)
                    let chunk = ConnectedTransferChunk(
                        transferID: transferID,
                        sequence: sequence,
                        data: data,
                        sha256: chunkHash
                    )
                    guard let acknowledgement = await sendConnectedTransferMessageWithRetry(
                        .connectedTransferChunk(chunk),
                        transferID: transferID,
                        sequence: sequence,
                        expectedSHA256: chunkHash,
                        timeout: acknowledgementTimeout,
                        maximumAttempts: maximumAttempts
                    ), acknowledgement.accepted else {
                        if let abort = receivedConnectedTransferAborts.removeValue(forKey: transferID) {
                            return .failure(abort)
                        }
                        return abortConnectedTransfer(
                            transferID: transferID,
                            jobID: manifest.jobID,
                            reason: .retriesExhausted,
                            message: "Peer did not accept transfer chunk \(sequence) after \(maximumAttempts) attempt(s)."
                        )
                    }
                    onValidatedProgress?(sequence, totalChunks)
                }
            }
        } catch is CancellationError {
            return abortConnectedTransfer(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .cancelled,
                message: "Connected transfer was cancelled."
            )
        } catch {
            return abortConnectedTransfer(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .applicationRejected,
                message: "Could not read the transfer source file."
            )
        }

        let complete = ConnectedTransferComplete(
            transferID: transferID,
            totalBytes: preparedFile.totalBytes,
            totalChunks: totalChunks,
            sha256: preparedFile.sha256
        )
        if let finalAck = await sendConnectedTransferCompletionWithRetry(
            complete,
            timeout: acknowledgementTimeout,
            maximumAttempts: maximumAttempts
        ) {
            receivedConnectedTransferAborts.removeValue(forKey: transferID)
            if finalAck.accepted, finalAck.sha256 == preparedFile.sha256 {
                return .success(finalAck)
            }
            return .failure(ConnectedTransferAbort(
                transferID: transferID,
                jobID: manifest.jobID,
                reason: .applicationRejected,
                message: finalAck.message ?? "Peer rejected the verified transfer."
            ))
        }
        if let abort = receivedConnectedTransferAborts.removeValue(forKey: transferID) {
            return .failure(abort)
        }
        return abortConnectedTransfer(
            transferID: transferID,
            jobID: manifest.jobID,
            reason: .retriesExhausted,
            message: "Peer did not finally accept the verified transfer after \(maximumAttempts) attempt(s)."
        )
    }

    @discardableResult
    func resolveConnectedTransferAck(_ acknowledgement: ConnectedTransferAck) -> Bool {
        let key = ConnectedTransferAckWaiterKey(
            transferID: acknowledgement.transferID,
            sequence: acknowledgement.sequence
        )
        guard connectedTransferAckContinuations[key] != nil else { return false }
        resumeConnectedTransferAckWaiter(for: key, with: acknowledgement)
        return true
    }

    @discardableResult
    func resolveConnectedTransferFinalAck(_ acknowledgement: ConnectedTransferFinalAck) -> Bool {
        guard let continuation = connectedTransferFinalAckContinuations.removeValue(forKey: acknowledgement.transferID) else {
            return false
        }
        connectedTransferFinalAckTimeoutTasks.removeValue(forKey: acknowledgement.transferID)?.cancel()
        continuation.resume(returning: acknowledgement)
        return true
    }

    func recordConnectedTransferAbort(_ abort: ConnectedTransferAbort) {
        receivedConnectedTransferAborts[abort.transferID] = abort
        cancelConnectedTransferWaiters(transferID: abort.transferID)
    }

    func cancelConnectedTransferWaiters(transferID: UUID) {
        let keys = connectedTransferAckContinuations.keys.filter { $0.transferID == transferID }
        for key in keys {
            resumeConnectedTransferAckWaiter(for: key, with: nil)
        }
        if let continuation = connectedTransferFinalAckContinuations.removeValue(forKey: transferID) {
            connectedTransferFinalAckTimeoutTasks.removeValue(forKey: transferID)?.cancel()
            continuation.resume(returning: nil)
        }
    }

    func cancelAllConnectedTransferWaiters() {
        receivedConnectedTransferAborts.removeAll()
        let keys = Array(connectedTransferAckContinuations.keys)
        for key in keys {
            resumeConnectedTransferAckWaiter(for: key, with: nil)
        }
        for transferID in Array(connectedTransferFinalAckContinuations.keys) {
            if let continuation = connectedTransferFinalAckContinuations.removeValue(forKey: transferID) {
                connectedTransferFinalAckTimeoutTasks.removeValue(forKey: transferID)?.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    private func sendConnectedTransferMessageWithRetry(
        _ message: SyncMessage,
        transferID: UUID,
        sequence: Int,
        expectedSHA256: String,
        timeout: TimeInterval,
        maximumAttempts: Int
    ) async -> ConnectedTransferAck? {
        for _ in 0..<max(maximumAttempts, 1) {
            if Task.isCancelled || receivedConnectedTransferAborts[transferID] != nil { return nil }
            guard let acknowledgement = await sendConnectedTransferMessageAndWait(
                message,
                transferID: transferID,
                sequence: sequence,
                timeout: timeout
            ) else { continue }
            guard acknowledgement.sha256 == expectedSHA256 else { return nil }
            return acknowledgement
        }
        return nil
    }

    private func sendConnectedTransferMessageAndWait(
        _ message: SyncMessage,
        transferID: UUID,
        sequence: Int,
        timeout: TimeInterval
    ) async -> ConnectedTransferAck? {
        let key = ConnectedTransferAckWaiterKey(transferID: transferID, sequence: sequence)
        return await withCheckedContinuation { continuation in
            resumeConnectedTransferAckWaiter(for: key, with: nil)
            connectedTransferAckContinuations[key] = continuation
            connectedTransferAckTimeoutTasks[key] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0.001) * 1_000_000_000))
                await MainActor.run {
                    self?.resumeConnectedTransferAckWaiter(for: key, with: nil)
                }
            }
            guard sendLargePayload(message) else {
                resumeConnectedTransferAckWaiter(for: key, with: nil)
                return
            }
        }
    }

    private func sendConnectedTransferCompletionWithRetry(
        _ complete: ConnectedTransferComplete,
        timeout: TimeInterval,
        maximumAttempts: Int
    ) async -> ConnectedTransferFinalAck? {
        for _ in 0..<max(maximumAttempts, 1) {
            if Task.isCancelled || receivedConnectedTransferAborts[complete.transferID] != nil { return nil }
            if let acknowledgement = await sendConnectedTransferCompletionAndWait(complete, timeout: timeout) {
                return acknowledgement
            }
        }
        return nil
    }

    private func sendConnectedTransferCompletionAndWait(
        _ complete: ConnectedTransferComplete,
        timeout: TimeInterval
    ) async -> ConnectedTransferFinalAck? {
        await withCheckedContinuation { continuation in
            if let existing = connectedTransferFinalAckContinuations.removeValue(forKey: complete.transferID) {
                connectedTransferFinalAckTimeoutTasks.removeValue(forKey: complete.transferID)?.cancel()
                existing.resume(returning: nil)
            }
            connectedTransferFinalAckContinuations[complete.transferID] = continuation
            connectedTransferFinalAckTimeoutTasks[complete.transferID] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0.001) * 1_000_000_000))
                await MainActor.run {
                    guard let self,
                          let continuation = self.connectedTransferFinalAckContinuations.removeValue(forKey: complete.transferID) else { return }
                    self.connectedTransferFinalAckTimeoutTasks.removeValue(forKey: complete.transferID)?.cancel()
                    continuation.resume(returning: nil)
                }
            }
            guard sendLargePayload(.connectedTransferComplete(complete)) else {
                if let continuation = connectedTransferFinalAckContinuations.removeValue(forKey: complete.transferID) {
                    connectedTransferFinalAckTimeoutTasks.removeValue(forKey: complete.transferID)?.cancel()
                    continuation.resume(returning: nil)
                }
                return
            }
        }
    }

    private func resumeConnectedTransferAckWaiter(
        for key: ConnectedTransferAckWaiterKey,
        with acknowledgement: ConnectedTransferAck?
    ) {
        guard let continuation = connectedTransferAckContinuations.removeValue(forKey: key) else { return }
        connectedTransferAckTimeoutTasks.removeValue(forKey: key)?.cancel()
        continuation.resume(returning: acknowledgement)
    }

    private func abortConnectedTransfer(
        transferID: UUID,
        jobID: UUID,
        reason: ConnectedTransferAbortReason,
        message: String
    ) -> ConnectedTransferSendResult {
        cancelConnectedTransferWaiters(transferID: transferID)
        let abort = ConnectedTransferAbort(
            transferID: transferID,
            jobID: jobID,
            reason: reason,
            message: message
        )
        _ = sendLargePayload(.connectedTransferAbort(abort))
        return .failure(abort)
    }

    /// Applies deterministic Sync/Mac-export state for UI tests without a real
    /// Multipeer connection. Safe no-op outside `--uitesting` launches.
    func configureForUITestingIfNeeded() {
        guard TestMode.isUITesting else { return }

        switch TestMode.syncState {
        case "connected":
            connectionState = .connected
            connectedPeerName = "Test Mac"
        case "connecting":
            connectionState = .connecting
            connectedPeerName = nil
            remoteCapabilities = nil
            macDestinationStatus = nil
        default:
            connectionState = .disconnected
            connectedPeerName = nil
            remoteCapabilities = nil
            macDestinationStatus = nil
        }

        guard connectionState == .connected,
              TestMode.macExportStatus != "none" else { return }

        let activeJobID = TestMode.macExportStatus == "busy"
            ? UUID(uuidString: "00000000-0000-0000-0000-000000000266")
            : nil
        let destinationFolderSelected = TestMode.macExportStatus != "noFolder"
        let folderAccessHealthy = TestMode.macExportStatus != "accessDenied"
        let isReadyForExports = TestMode.macExportStatus == "ready"
        let capabilities = SyncPeerCapabilities.current(platform: .macOS)

        remoteCapabilities = capabilities
        macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: isReadyForExports,
            destinationFolderSelected: destinationFolderSelected,
            folderAccessHealthy: folderAccessHealthy,
            destinationDisplayName: destinationFolderSelected ? "TestMacVault" : nil,
            destinationPathForDisplay: destinationFolderSelected ? TestMode.macDestinationPath : nil,
            lastError: TestMode.macExportStatus == "accessDenied" ? "Mac folder access denied" : nil,
            activeJobID: activeJobID,
            capabilities: capabilities
        )
    }

    // MARK: - Sending Messages

    /// Send a `SyncMessage` to all connected peers.
    func send(_ message: SyncMessage) {
        #if DEBUG
        testMessageSendObserver?(message)
        #endif
        if activeTransport == .manualIP {
            do {
                try sendManualMessage(message)
                logger.info("Sent manual IP message: \(message.operationalName, privacy: .public)")
            } catch {
                logger.error("Failed to send manual IP message: \(error.localizedDescription)")
                lastError = "Send failed: \(error.localizedDescription)"
            }
            return
        }

        guard !session.connectedPeers.isEmpty else {
            logger.warning("Cannot send — no connected peers")
            lastError = "No connected device"
            markMultipeerDisconnectedIfNeeded()
            return
        }

        do {
            let data = try encoder.encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            logger.info("Sent message: \(message.operationalName, privacy: .public)")
        } catch {
            logger.error("Failed to send message: \(error.localizedDescription)")
            lastError = "Send failed: \(error.localizedDescription)"
        }
    }

    /// Send a `SyncMessage` using streaming for large payloads.
    @discardableResult
    func sendLargePayload(_ message: SyncMessage) -> Bool {
        #if DEBUG
        testMessageSendObserver?(message)
        #endif
        if activeTransport == .manualIP {
            do {
                try sendManualMessage(message)
                logger.info("Sent manual IP payload: \(message.operationalName, privacy: .public)")
                return true
            } catch {
                logger.error("Failed to encode/send manual IP payload: \(error.localizedDescription)")
                lastError = "Send failed: \(error.localizedDescription)"
                return false
            }
        }

        guard let peer = session.connectedPeers.first else {
            logger.warning("Cannot send — no connected peers")
            lastError = "No connected device"
            markMultipeerDisconnectedIfNeeded()
            return false
        }

        do {
            let data = try encoder.encode(message)

            // For payloads > 100KB, use resource transfer for reliability
            if data.count > 100_000 {
                let tempURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "sync-resource")
                try data.write(to: tempURL)

                session.sendResource(at: tempURL, withName: "sync-payload", toPeer: peer) { error in
                    try? FileManager.default.removeItem(at: tempURL)
                    if let error {
                        Task { @MainActor in
                            self.logger.error("Resource send failed: \(error.localizedDescription)")
                            self.lastError = "Send failed: \(error.localizedDescription)"
                        }
                    }
                }
                logger.info("Sending large payload via resource transfer (\(data.count) bytes)")
            } else {
                try session.send(data, toPeers: [peer], with: .reliable)
                logger.info("Sent message (\(data.count) bytes)")
            }
            return true
        } catch {
            logger.error("Failed to encode/send message: \(error.localizedDescription)")
            lastError = "Send failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Keep-Awake Helpers

    /// Prevent the device from sleeping and request background execution time while syncing.
    private func beginKeepAwake() {
        #if os(iOS)
        logger.info("Sync started — disabling idle timer and requesting background time")
        UIApplication.shared.isIdleTimerDisabled = true

        // Request background execution time so the sync survives brief app-backgrounding
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "HealthMD-Sync") { [weak self] in
            // Expiration handler — system is about to kill background time
            Task { @MainActor in
                self?.logger.warning("Background time expiring — ending background task")
                self?.endBackgroundTask()
            }
        }
        #endif
    }

    /// Re-enable idle timer and end background task assertion.
    private func endKeepAwake() {
        #if os(iOS)
        logger.info("Sync finished — re-enabling idle timer")
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
        #endif
    }

    #if os(iOS)
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
    #endif

    // MARK: - Private Helpers

    private func handleReceivedData(_ data: Data, fromPeer peerID: MCPeerID? = nil) {
        do {
            let message = try decoder.decode(SyncMessage.self, from: data)
            logger.info("Received message: \(message.operationalName, privacy: .public)")
            Task { @MainActor in
                if let peerID,
                   self.restoreMultipeerConnectionIfNeeded(from: peerID) {
                    self.send(.hello(.current()))
                }
                self.onMessageReceived?(message)
            }
        } catch {
            logger.error("Failed to decode received message: \(error.localizedDescription)")
            Task { @MainActor in
                self.lastError = "Decode error: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func restoreMultipeerConnectionIfNeeded(from peerID: MCPeerID) -> Bool {
        guard activeTransport != .manualIP else { return false }

        let wasConnectedToSamePeer = connectionState == .connected
            && (connectedMultipeerPeerID?.isEqual(peerID) == true)
        let switchedPeer = connectedMultipeerPeerID != nil
            && connectedMultipeerPeerID?.isEqual(peerID) != true

        connectedMultipeerPeerID = peerID

        if switchedPeer {
            remoteCapabilities = nil
            macDestinationStatus = nil
        }

        guard !wasConnectedToSamePeer else { return false }

        let recoveredFromDisconnectedState = connectionState != .connected
        activeTransport = .multipeer
        connectionState = .connected
        connectedPeerName = peerID.displayName
        lastError = nil
        startConnectionHeartbeat()
        return recoveredFromDisconnectedState || switchedPeer
    }

    private func startConnectionHeartbeat() {
        guard connectionHeartbeatTask == nil else { return }
        connectionHeartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, self.connectionState == .connected else { break }
                self.send(.ping)
            }
            self?.connectionHeartbeatTask = nil
        }
    }

    private func stopConnectionHeartbeat() {
        connectionHeartbeatTask?.cancel()
        connectionHeartbeatTask = nil
    }

    private func markMultipeerDisconnectedIfNeeded() {
        guard activeTransport == .multipeer,
              connectionState == .connected,
              session.connectedPeers.isEmpty else { return }

        stopConnectionHeartbeat()
        connectedMultipeerPeerID = nil
        connectionState = .disconnected
        connectedPeerName = nil
        remoteCapabilities = nil
        macDestinationStatus = nil
        latestMacExportMessage = nil
        activeMacExportProgress = nil
        lastMacExportResult = nil
        lastMacExportFailure = nil
        cancelAllMacExportStreamAckWaiters()
        cancelAllConnectedTransferWaiters()
        if isSyncing {
            isSyncing = false
        }
    }

    // MARK: - Manual IP / Tailscale Transport

    private enum ManualIPSyncError: LocalizedError {
        case notConnected
        case notPaired
        case invalidFrame
        case frameTooLarge

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Manual IP connection is not active."
            case .notPaired: return "Manual IP connection is not paired yet."
            case .invalidFrame: return "Manual IP message frame is invalid."
            case .frameTooLarge: return "Manual IP message is too large."
            }
        }
    }

    private func isCurrentManualConnection(_ connection: NWConnection) -> Bool {
        manualConnection === connection
    }

    private func sendManualMessage(_ message: SyncMessage) throws {
        guard let manualConnection else { throw ManualIPSyncError.notConnected }
        guard let manualSessionKey, manualConnectionHasPaired else { throw ManualIPSyncError.notPaired }
        let data = try encoder.encode(message)
        let encryptedFrame = try ManualIPSyncSecurity.seal(data, using: manualSessionKey)
        try sendManualPacket(.encrypted(encryptedFrame), on: manualConnection)
    }

    private func sendManualPacket(_ packet: ManualIPSyncPacket, on connection: NWConnection) throws {
        let packetData = try encoder.encode(packet)
        guard packetData.count <= ManualIPSyncSecurity.maxFrameSize else {
            throw ManualIPSyncError.frameTooLarge
        }
        var framedData = Data()
        framedData.appendManualIPLengthPrefix(packetData.count)
        framedData.append(packetData)
        connection.send(content: framedData, completion: .contentProcessed { [weak self] error in
            guard let error, let strongSelf = self else { return }
            Task { @MainActor in
                guard strongSelf.isCurrentManualConnection(connection) else { return }
                strongSelf.logger.error("Manual IP send failed: \(error.localizedDescription)")
                strongSelf.lastError = "Manual IP send failed: \(error.localizedDescription)"
                strongSelf.handleManualConnectionEnded(errorMessage: error.localizedDescription)
            }
        })
    }

    private func startManualReceiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1_024) { [weak self] data, _, isComplete, error in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                guard strongSelf.isCurrentManualConnection(connection) else { return }
                if let data, !data.isEmpty {
                    strongSelf.manualReceiveBuffer.append(data)
                    strongSelf.processManualReceiveBuffer(connection: connection)
                }
                if let error {
                    strongSelf.logger.error("Manual IP receive failed: \(error.localizedDescription)")
                    strongSelf.handleManualConnectionEnded(errorMessage: error.localizedDescription)
                    return
                }
                if isComplete {
                    strongSelf.handleManualConnectionEnded(errorMessage: nil)
                    return
                }
                strongSelf.startManualReceiveLoop(on: connection)
            }
        }
    }

    private func processManualReceiveBuffer(connection: NWConnection) {
        while manualReceiveBuffer.count >= 8 {
            guard let packetLength = manualReceiveBuffer.manualIPLengthPrefix() else {
                lastError = "Manual IP frame has an invalid length."
                connection.cancel()
                return
            }
            guard packetLength <= ManualIPSyncSecurity.maxFrameSize else {
                lastError = "Manual IP frame is too large."
                connection.cancel()
                return
            }
            guard manualReceiveBuffer.count >= 8 + packetLength else { return }

            let packetData = manualReceiveBuffer.subdata(in: 8..<(8 + packetLength))
            manualReceiveBuffer.removeSubrange(0..<(8 + packetLength))
            do {
                let packet = try decoder.decode(ManualIPSyncPacket.self, from: packetData)
                handleManualPacket(packet, connection: connection)
            } catch {
                logger.error("Failed to decode manual IP packet: \(error.localizedDescription)")
                lastError = "Manual IP decode failed: \(error.localizedDescription)"
                connection.cancel()
                return
            }
        }
    }

    private func handleManualPacket(_ packet: ManualIPSyncPacket, connection: NWConnection) {
        switch packet {
        case .pairingRequest(let request):
            #if os(macOS)
            handleManualPairingRequest(request, connection: connection)
            #else
            lastError = "Unexpected pairing request from Mac."
            connection.cancel()
            #endif
        case .pairingResponse(let response):
            #if os(iOS)
            handleManualPairingResponse(response, connection: connection)
            #else
            lastError = "Unexpected pairing response from iPhone."
            connection.cancel()
            #endif
        case .pairingRejected(let rejection):
            lastError = rejection.reason
            handleManualConnectionEnded(errorMessage: rejection.reason)
        case .encrypted(let frame):
            handleManualEncryptedFrame(frame)
        }
    }

    private func handleManualEncryptedFrame(_ frame: ManualIPEncryptedFrame) {
        guard let manualSessionKey, manualConnectionHasPaired else {
            lastError = "Manual IP message arrived before pairing completed."
            manualConnection?.cancel()
            return
        }
        do {
            let plaintext = try ManualIPSyncSecurity.open(frame, using: manualSessionKey)
            handleReceivedData(plaintext)
        } catch {
            logger.error("Failed to decrypt manual IP message: \(error.localizedDescription)")
            lastError = "Manual IP decrypt failed: \(error.localizedDescription)"
            manualConnection?.cancel()
        }
    }

    private func cancelManualConnection(updatePublicState: Bool = true) {
        manualConnection?.cancel()
        manualConnection = nil
        manualReceiveBuffer.removeAll(keepingCapacity: false)
        manualSessionKey = nil
        manualConnectionHasPaired = false
        #if os(iOS)
        manualClientPrivateKey = nil
        manualClientNonce = nil
        manualClientPairingCode = nil
        #endif
        #if os(macOS)
        manualServerPrivateKey = nil
        #endif

        guard updatePublicState, activeTransport == .manualIP else { return }
        stopConnectionHeartbeat()
        activeTransport = .multipeer
        connectedMultipeerPeerID = nil
        connectionState = .disconnected
        connectedPeerName = nil
        remoteCapabilities = nil
        macDestinationStatus = nil
        latestMacExportMessage = nil
        activeMacExportProgress = nil
        lastMacExportResult = nil
        lastMacExportFailure = nil
        cancelAllConnectedTransferWaiters()
        if isSyncing {
            isSyncing = false
        }
    }

    private func handleManualConnectionEnded(errorMessage: String?) {
        if let errorMessage, activeTransport == .manualIP {
            lastError = "Manual IP disconnected: \(errorMessage)"
        }
        cancelManualConnection(updatePublicState: true)
    }

    private func completeManualPairing(peerName: String) {
        connectedMultipeerPeerID = nil
        activeTransport = .manualIP
        connectionState = .connected
        connectedPeerName = peerName
        manualConnectionHasPaired = true
        lastError = nil
        startConnectionHeartbeat()
        send(.hello(.current()))
    }

    #if os(iOS)
    func connectToManualMac(host: String, port: UInt16 = 17_646, pairingCode: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = ManualIPSyncSecurity.normalizedPairingCode(pairingCode)
        guard !trimmedHost.isEmpty else {
            lastError = "Enter your Mac's Tailscale IP address or hostname."
            return
        }
        guard normalizedCode.count >= 4 else {
            lastError = "Enter the pairing code shown on your Mac."
            return
        }

        UserDefaults.standard.set(trimmedHost, forKey: "manualIPLastHost")
        manualIPLastHost = trimmedHost

        cancelManualConnection(updatePublicState: false)
        session.disconnect()
        activeTransport = .manualIP
        connectionState = .connecting
        connectedPeerName = nil
        remoteCapabilities = nil
        macDestinationStatus = nil
        lastError = nil

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let clientNonce = ManualIPSyncSecurity.randomNonce()
        manualClientPrivateKey = privateKey
        manualClientNonce = clientNonce
        manualClientPairingCode = normalizedCode

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid manual IP port."
            connectionState = .disconnected
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(trimmedHost),
            port: endpointPort,
            using: .tcp
        )
        manualConnection = connection
        manualReceiveBuffer.removeAll(keepingCapacity: false)
        connection.stateUpdateHandler = { [weak self] state in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleManualClientStateUpdate(state, connection: connection)
            }
        }
        startManualReceiveLoop(on: connection)
        connection.start(queue: .main)
    }

    private func handleManualClientStateUpdate(_ state: NWConnection.State, connection: NWConnection) {
        guard isCurrentManualConnection(connection) else { return }
        switch state {
        case .ready:
            sendManualPairingRequest(on: connection)
        case .waiting(let error):
            lastError = "Waiting for manual IP connection: \(error.localizedDescription)"
        case .failed(let error):
            lastError = "Manual IP connection failed: \(error.localizedDescription)"
            handleManualConnectionEnded(errorMessage: error.localizedDescription)
        case .cancelled:
            handleManualConnectionEnded(errorMessage: nil)
        default:
            break
        }
    }

    private func sendManualPairingRequest(on connection: NWConnection) {
        guard let privateKey = manualClientPrivateKey,
              let clientNonce = manualClientNonce,
              let pairingCode = manualClientPairingCode else {
            connection.cancel()
            return
        }
        let publicKey = privateKey.publicKey.rawRepresentation
        let verifier = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: pairingCode,
            clientPublicKey: publicKey,
            clientNonce: clientNonce
        )
        let request = ManualIPPairingRequest(
            deviceName: myPeerID.displayName,
            clientPublicKey: publicKey,
            clientNonce: clientNonce,
            codeVerifier: verifier
        )
        do {
            try sendManualPacket(.pairingRequest(request), on: connection)
        } catch {
            lastError = "Manual IP pairing failed: \(error.localizedDescription)"
            connection.cancel()
        }
    }

    private func handleManualPairingResponse(_ response: ManualIPPairingResponse, connection: NWConnection) {
        guard response.protocolVersion == ManualIPSyncSecurity.protocolVersion else {
            lastError = "Manual IP protocol version is incompatible."
            connection.cancel()
            return
        }
        guard let privateKey = manualClientPrivateKey,
              let clientNonce = manualClientNonce else {
            lastError = "Manual IP pairing state was lost."
            connection.cancel()
            return
        }
        do {
            let serverPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: response.serverPublicKey)
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
            manualSessionKey = ManualIPSyncSecurity.sessionKey(
                sharedSecret: sharedSecret,
                clientNonce: clientNonce,
                serverNonce: response.serverNonce
            )
            completeManualPairing(peerName: response.macName)
        } catch {
            lastError = "Manual IP pairing failed: \(error.localizedDescription)"
            connection.cancel()
        }
    }
    #endif

    #if os(macOS)
    func setManualIPServerEnabled(_ enabled: Bool) {
        manualIPServerEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "manualIPServerEnabled")
        if enabled {
            startManualIPServer()
        } else {
            stopManualIPServer()
        }
    }

    func restoreManualIPServerIfNeeded() {
        refreshManualIPAddresses()
        if manualIPServerEnabled {
            startManualIPServer()
        }
    }

    func generateManualIPPairingCode() {
        manualIPPairingCode = ManualIPSyncSecurity.makePairingCode()
        manualIPPairingCodeExpiresAt = Date().addingTimeInterval(ManualIPSyncSecurity.pairingCodeLifetime)
    }

    func refreshManualIPAddresses() {
        manualIPAddresses = Self.currentManualIPAddresses()
    }

    func startManualIPServer() {
        guard manualListener == nil else {
            refreshManualIPAddresses()
            if manualIPPairingCode == nil { generateManualIPPairingCode() }
            return
        }
        refreshManualIPAddresses()
        if manualIPPairingCode == nil { generateManualIPPairingCode() }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: Self.manualIPPort) else {
                lastError = "Invalid manual IP port."
                return
            }
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                guard let strongSelf = self else { return }
                Task { @MainActor in
                    strongSelf.acceptManualIPConnection(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let strongSelf = self else { return }
                Task { @MainActor in
                    strongSelf.handleManualListenerStateUpdate(state)
                }
            }
            listener.start(queue: .main)
            manualListener = listener
        } catch {
            manualIPServerListening = false
            lastError = "Manual IP server failed to start: \(error.localizedDescription)"
        }
    }

    func stopManualIPServer() {
        manualListener?.cancel()
        manualListener = nil
        manualIPServerListening = false
        manualIPPairingCode = nil
        manualIPPairingCodeExpiresAt = nil
        cancelManualConnection(updatePublicState: true)
    }

    private func handleManualListenerStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            manualIPServerListening = true
            lastError = nil
            refreshManualIPAddresses()
        case .failed(let error):
            manualIPServerListening = false
            lastError = "Manual IP server failed: \(error.localizedDescription)"
            manualListener?.cancel()
            manualListener = nil
        case .cancelled:
            manualIPServerListening = false
        default:
            break
        }
    }

    private func acceptManualIPConnection(_ connection: NWConnection) {
        cancelManualConnection(updatePublicState: activeTransport == .manualIP)
        manualConnection = connection
        manualReceiveBuffer.removeAll(keepingCapacity: false)
        manualSessionKey = nil
        manualConnectionHasPaired = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleManualServerConnectionStateUpdate(state, connection: connection)
            }
        }
        startManualReceiveLoop(on: connection)
        connection.start(queue: .main)
    }

    private func handleManualServerConnectionStateUpdate(_ state: NWConnection.State, connection: NWConnection) {
        guard isCurrentManualConnection(connection) else { return }
        switch state {
        case .failed(let error):
            lastError = "Manual IP connection failed: \(error.localizedDescription)"
            handleManualConnectionEnded(errorMessage: error.localizedDescription)
        case .cancelled:
            handleManualConnectionEnded(errorMessage: nil)
        default:
            break
        }
    }

    private func handleManualPairingRequest(_ request: ManualIPPairingRequest, connection: NWConnection) {
        guard request.protocolVersion == ManualIPSyncSecurity.protocolVersion else {
            rejectManualPairing("Manual IP protocol version is incompatible.", connection: connection)
            return
        }
        guard let pairingCode = manualIPPairingCode,
              let expiresAt = manualIPPairingCodeExpiresAt,
              expiresAt > Date() else {
            rejectManualPairing("Pairing code expired. Generate a new code on your Mac.", connection: connection)
            return
        }
        guard ManualIPSyncSecurity.pairingVerifierIsValid(
            request.codeVerifier,
            pairingCode: pairingCode,
            clientPublicKey: request.clientPublicKey,
            clientNonce: request.clientNonce
        ) else {
            rejectManualPairing("Pairing code is incorrect.", connection: connection)
            return
        }

        do {
            let clientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: request.clientPublicKey)
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: clientPublicKey)
            let serverNonce = ManualIPSyncSecurity.randomNonce()
            manualServerPrivateKey = privateKey
            manualSessionKey = ManualIPSyncSecurity.sessionKey(
                sharedSecret: sharedSecret,
                clientNonce: request.clientNonce,
                serverNonce: serverNonce
            )
            let response = ManualIPPairingResponse(
                macName: myPeerID.displayName,
                serverPublicKey: privateKey.publicKey.rawRepresentation,
                serverNonce: serverNonce
            )
            try sendManualPacket(.pairingResponse(response), on: connection)
            manualIPPairingCode = nil
            manualIPPairingCodeExpiresAt = nil
            completeManualPairing(peerName: request.deviceName)
        } catch {
            rejectManualPairing("Pairing failed: \(error.localizedDescription)", connection: connection)
        }
    }

    private func rejectManualPairing(_ reason: String, connection: NWConnection) {
        lastError = reason
        try? sendManualPacket(.pairingRejected(ManualIPPairingRejected(reason: reason)), on: connection)
        connection.cancel()
    }

    private static func currentManualIPAddresses() -> [ManualIPNetworkAddress] {
        var results: [ManualIPNetworkAddress] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addressPointer = interface.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET) else { continue }

            var address = sockaddr_in()
            memcpy(&address, addressPointer, MemoryLayout<sockaddr_in>.size)
            let rawAddress = UInt32(bigEndian: address.sin_addr.s_addr)
            let firstOctet = (rawAddress >> 24) & 0xff
            let secondOctet = (rawAddress >> 16) & 0xff
            guard firstOctet != 127, firstOctet != 169 else { continue }

            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sinAddress = address.sin_addr
            guard inet_ntop(AF_INET, &sinAddress, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ipAddress = String(cString: buffer)
            let interfaceName = String(cString: interface.ifa_name)
            let isLikelyTailscale = firstOctet == 100 && (64...127).contains(Int(secondOctet))
            let candidate = ManualIPNetworkAddress(
                interfaceName: interfaceName,
                address: ipAddress,
                isLikelyTailscale: isLikelyTailscale
            )
            if !results.contains(candidate) {
                results.append(candidate)
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.isLikelyTailscale != rhs.isLikelyTailscale {
                return lhs.isLikelyTailscale && !rhs.isLikelyTailscale
            }
            return lhs.address < rhs.address
        }
    }
    #endif
}

// MARK: - MCSessionDelegate

extension SyncService: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peerName = peerID.displayName
        Task { @MainActor in
            if self.activeTransport == .manualIP {
                return
            }
            switch state {
            case .notConnected:
                let remainingPeers = session.connectedPeers.filter { !$0.isEqual(peerID) }
                if !remainingPeers.isEmpty {
                    self.logger.info("Peer disconnected: \(peerName); \(remainingPeers.count) peer(s) remain connected")
                    if self.connectedMultipeerPeerID == nil
                        || self.connectedMultipeerPeerID?.isEqual(peerID) == true
                        || self.connectedPeerName == nil {
                        if let remainingPeer = remainingPeers.first {
                            self.connectedMultipeerPeerID = remainingPeer
                            self.connectionState = .connected
                            self.connectedPeerName = remainingPeer.displayName
                            self.remoteCapabilities = nil
                            self.macDestinationStatus = nil
                            self.startConnectionHeartbeat()
                            self.send(.hello(.current()))
                        }
                    }
                    return
                }

                if self.connectionState == .connected,
                   let connectedMultipeerPeerID = self.connectedMultipeerPeerID,
                   !connectedMultipeerPeerID.isEqual(peerID) {
                    self.logger.info("Ignoring disconnect for non-current peer: \(peerName)")
                    return
                }

                self.logger.info("Peer disconnected: \(peerName)")
                self.stopConnectionHeartbeat()
                self.connectedMultipeerPeerID = nil
                self.connectionState = .disconnected
                self.connectedPeerName = nil
                self.remoteCapabilities = nil
                self.macDestinationStatus = nil
                self.latestMacExportMessage = nil
                self.activeMacExportProgress = nil
                self.lastMacExportResult = nil
                self.lastMacExportFailure = nil
                self.cancelAllMacExportStreamAckWaiters()
                self.cancelAllConnectedTransferWaiters()
                if self.isSyncing {
                    self.logger.warning("Peer disconnected during active sync — cleaning up")
                    self.isSyncing = false
                }
            case .connecting:
                if !session.connectedPeers.isEmpty {
                    self.logger.info("Peer connecting: \(peerName); keeping existing connected peer")
                    return
                }
                self.logger.info("Connecting to: \(peerName)")
                self.stopConnectionHeartbeat()
                self.activeTransport = .multipeer
                self.connectedMultipeerPeerID = nil
                self.connectionState = .connecting
                self.connectedPeerName = nil
                self.remoteCapabilities = nil
                self.macDestinationStatus = nil
            case .connected:
                self.logger.info("Connected to: \(peerName)")
                let switchedPeer = self.connectedMultipeerPeerID != nil
                    && self.connectedMultipeerPeerID?.isEqual(peerID) != true
                self.connectedMultipeerPeerID = peerID
                if switchedPeer {
                    self.remoteCapabilities = nil
                    self.macDestinationStatus = nil
                }
                self.activeTransport = .multipeer
                self.connectionState = .connected
                self.connectedPeerName = peerName
                self.lastError = nil
                self.startConnectionHeartbeat()
                self.send(.hello(.current()))
            @unknown default:
                self.logger.warning("Unknown session state for: \(peerName)")
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.handleReceivedData(data, fromPeer: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used — we use data messages and resource transfers
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            self.logger.info("Receiving resource: \(resourceName) from \(peerID.displayName)")
        }
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard let localURL, error == nil else {
            Task { @MainActor in
                self.logger.error("Resource receive failed: \(error?.localizedDescription ?? "unknown")")
                self.lastError = "Receive failed: \(error?.localizedDescription ?? "unknown")"
            }
            return
        }

        do {
            let data = try Data(contentsOf: localURL)
            try? FileManager.default.removeItem(at: localURL)
            Task { @MainActor in
                self.handleReceivedData(data, fromPeer: peerID)
            }
        } catch {
            Task { @MainActor in
                self.logger.error("Failed to read received resource: \(error.localizedDescription)")
                self.lastError = "Read error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate (iOS)

extension SyncService: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from peers using our service type
        Task { @MainActor in
            self.logger.info("Received invitation from: \(peerID.displayName) — auto-accepting")
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.logger.error("Failed to start advertising: \(error.localizedDescription)")
            self.lastError = "Advertising failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (macOS)

extension SyncService: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.logger.info("Discovered peer: \(peerID.displayName)")
            if !self.discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
                self.discoveredPeers.append(peerID)
            }

            // Auto-connect to the first discovered peer if not already connected.
            // Manual IP/Tailscale connections are mutually exclusive with nearby
            // Multipeer handoff for the public SyncService state.
            if self.connectionState == .disconnected && self.activeTransport != .manualIP {
                self.connectToPeer(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.logger.info("Lost peer: \(peerID.displayName)")
            self.discoveredPeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.logger.error("Failed to start browsing: \(error.localizedDescription)")
            self.lastError = "Browsing failed: \(error.localizedDescription)"
        }
    }
}
