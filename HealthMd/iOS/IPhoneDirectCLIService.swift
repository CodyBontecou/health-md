#if os(iOS)
import Combine
import HealthMdConnectionCore
import UIKit

final class IPhoneDirectExportConnection: @unchecked Sendable {
    let channel: DirectSecureChannel
    private let inbox = IPhoneDirectExportMessageInbox()

    init(channel: DirectSecureChannel) {
        self.channel = channel
    }

    func send(_ message: DirectMessage) async throws {
        try await channel.send(message)
    }

    func sendBinaryTransferFrame(_ frame: Data) async throws {
        try await channel.sendBinaryTransferFrame(frame)
    }

    func receive() async throws -> DirectMessage {
        try await inbox.next()
    }

    func deliver(_ message: DirectMessage) async {
        await inbox.deliver(message)
    }

    func finish() async {
        await inbox.finish()
    }
}

private actor IPhoneDirectExportMessageInbox {
    private var buffered: [DirectMessage] = []
    private var waiter: CheckedContinuation<DirectMessage, Error>?
    private var isFinished = false

    func next() async throws -> DirectMessage {
        if !buffered.isEmpty { return buffered.removeFirst() }
        if isFinished { throw DirectChannelError.connectionClosed }
        guard waiter == nil else { throw DirectChannelError.malformedPacket }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func deliver(_ message: DirectMessage) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: message)
        } else if !isFinished, buffered.count < 32 {
            buffered.append(message)
        } else if !isFinished {
            finish()
        }
    }

    func finish() {
        isFinished = true
        buffered.removeAll()
        let pending = waiter
        waiter = nil
        pending?.resume(throwing: DirectChannelError.connectionClosed)
    }
}

struct IPhoneDirectCLIReconnectPolicy: Equatable, Sendable {
    let initialRetryDelayNanoseconds: UInt64
    let maximumRetryDelayNanoseconds: UInt64
    let connectedPollDelayNanoseconds: UInt64
    let manualConnectionTimeout: TimeInterval

    nonisolated static let production = IPhoneDirectCLIReconnectPolicy(
        initialRetryDelayNanoseconds: 250_000_000,
        maximumRetryDelayNanoseconds: 2_000_000_000,
        connectedPollDelayNanoseconds: 250_000_000,
        manualConnectionTimeout: 2
    )

    func nextRetryDelay(after delay: UInt64) -> UInt64 {
        guard delay < maximumRetryDelayNanoseconds else {
            return maximumRetryDelayNanoseconds
        }
        guard delay <= UInt64.max / 2 else {
            return maximumRetryDelayNanoseconds
        }
        return min(delay * 2, maximumRetryDelayNanoseconds)
    }
}

/// Opt-in, foreground-scoped client for a one-shot `healthmd --backend direct`
/// listener. iOS remains the HealthKit owner; this service only authenticates
/// the CLI and exposes control messages while the app is active.
@MainActor
final class IPhoneDirectCLIService: ObservableObject {
    static let enabledKey = "directCLIEnabled"
    static let hostKey = "directCLIHost"
    static let portKey = "directCLIPort"
    static let transportKey = "directCLITransport"
    static let installationIDKey = "directCLIInstallationID"

    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var connectedCLIName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var needsPairingCode = false

    var statusProvider: (() async -> DirectIPhoneStatus)?
    var exportRequestHandler: ((
        DirectExportRequest,
        DirectPeerBinding,
        DirectTransferNegotiation,
        IPhoneDirectExportConnection
    ) async -> Void)?
    var cancelHandler: ((UUID) -> Bool)?

    private let defaults: UserDefaults
    private let trustStore: ManualIPTrustStore
    private let installationID: UUID
    private let reconnectPolicy: IPhoneDirectCLIReconnectPolicy
    private lazy var client = DirectManualIPClient(
        installationID: installationID,
        displayName: UIDevice.current.name,
        trustStore: trustStore
    )
    private lazy var nearbyClient = DirectNearbyClient(
        installationID: installationID,
        displayName: UIDevice.current.name,
        trustStore: trustStore
    )
    private let idleTimerActivityID = UUID()
    private var reconnectTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var exportTask: Task<Void, Never>?
    private var activeExportOperationID: UUID?
    private var exportConnection: IPhoneDirectExportConnection?
    private var channel: DirectSecureChannel?
    private var remoteCapabilities: DirectPeerCapabilities?
    private var appIsActive = false
    private var reconnectGeneration = 0
    private var visibleConnectionAttemptID: UUID?

    init(
        defaults: UserDefaults = .standard,
        reconnectPolicy: IPhoneDirectCLIReconnectPolicy = .production
    ) {
        self.defaults = defaults
        self.reconnectPolicy = reconnectPolicy
        self.installationID = Self.loadOrCreateInstallationID(defaults: defaults)
        let trustStore = ManualIPTrustStore(
            service: "com.codybontecou.obsidianhealth.direct-cli-ios-trust",
            account: "trust-state-v1"
        )
        self.trustStore = trustStore
        self.needsPairingCode = trustStore.loadState(
            ownerInstallationID: installationID
        ).trustedMac == nil
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var pairedCLIName: String? {
        client.savedServer()?.displayName
    }

    var hasPairedCLI: Bool {
        client.savedServer() != nil
    }

    var configuredHost: String {
        defaults.string(forKey: Self.hostKey) ?? client.savedServer()?.host ?? ""
    }

    var configuredTransport: DirectTransportKind {
        DirectTransportKind(
            rawValue: defaults.string(forKey: Self.transportKey) ?? ""
        ) ?? .manualIP
    }

    var configuredPort: UInt16 {
        if let value = defaults.string(forKey: Self.portKey), let port = UInt16(value) {
            return port
        }
        return client.savedServer()?.port ?? HealthMdDirectProtocol.defaultManualIPPort
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        updateIdleTimer()
        if enabled {
            startReconnectLoopIfNeeded()
        } else {
            disconnect(clearError: true)
        }
    }

    func updateEndpoint(host: String, port: UInt16) {
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.hostKey)
        defaults.set(String(port), forKey: Self.portKey)
    }

    func updateTransport(_ transport: DirectTransportKind) {
        defaults.set(transport.rawValue, forKey: Self.transportKey)
        disconnect(clearError: true)
        startReconnectLoopIfNeeded()
    }

    func connect(host: String, port: UInt16, pairingCode: String) {
        updateEndpoint(host: host, port: port)
        defaults.set(true, forKey: Self.enabledKey)
        updateIdleTimer()
        reconnectGeneration += 1
        let generation = reconnectGeneration
        let attemptID = UUID()
        visibleConnectionAttemptID = attemptID
        isConnecting = true
        lastError = nil
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let timeout: TimeInterval? = self.configuredTransport == .nearby ? 15 : 10
            await self.connectOnce(
                pairingCode: pairingCode,
                timeout: timeout,
                reportErrors: true
            )
            if self.visibleConnectionAttemptID == attemptID {
                self.visibleConnectionAttemptID = nil
                self.isConnecting = false
            }
            guard self.reconnectGeneration == generation else { return }
            self.reconnectTask = nil
            self.startReconnectLoopIfNeeded()
        }
    }

    func forgetPairedCLI() {
        try? client.forgetServer()
        disconnect(clearError: true)
        needsPairingCode = true
    }

    func applicationDidBecomeActive() {
        appIsActive = true
        updateIdleTimer()
        IPhoneDirectExportCoordinator.shared.cleanupExpiredJobs()
        startReconnectLoopIfNeeded()
    }

    func applicationDidEnterBackground() {
        appIsActive = false
        updateIdleTimer()
        disconnect(clearError: false)
    }

    private func updateIdleTimer() {
        if isEnabled && appIsActive {
            IdleTimerCoordinator.shared.beginActivity(idleTimerActivityID)
        } else {
            IdleTimerCoordinator.shared.endActivity(idleTimerActivityID)
        }
    }

    private func startReconnectLoopIfNeeded() {
        guard isEnabled, appIsActive, reconnectTask == nil else { return }
        guard client.savedServer() != nil else {
            needsPairingCode = true
            return
        }
        reconnectGeneration += 1
        let generation = reconnectGeneration
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var retryDelay = self.reconnectPolicy.initialRetryDelayNanoseconds
            while !Task.isCancelled, self.isEnabled, self.appIsActive {
                if self.channel != nil {
                    retryDelay = self.reconnectPolicy.initialRetryDelayNanoseconds
                    try? await Task.sleep(
                        nanoseconds: self.reconnectPolicy.connectedPollDelayNanoseconds
                    )
                    continue
                }
                let transport = self.configuredTransport
                await self.connectOnce(
                    pairingCode: nil,
                    timeout: transport == .nearby
                        ? nil : self.reconnectPolicy.manualConnectionTimeout,
                    reportErrors: false
                )
                if self.channel == nil, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: retryDelay)
                    retryDelay = self.reconnectPolicy.nextRetryDelay(after: retryDelay)
                }
            }
            guard self.reconnectGeneration == generation else { return }
            self.reconnectTask = nil
        }
    }

    private func connectOnce(
        pairingCode: String?,
        timeout: TimeInterval?,
        reportErrors: Bool
    ) async {
        guard channel == nil, appIsActive else { return }
        let transport = configuredTransport
        let host = configuredHost
        let port = configuredPort
        if transport == .manualIP, host.isEmpty {
            needsPairingCode = true
            if reportErrors {
                lastError = "Enter the Mac address shown by healthmd direct pair."
            }
            return
        }
        var provisionalChannel: DirectSecureChannel?
        do {
            let connected: DirectSecureChannel
            switch transport {
            case .manualIP:
                connected = try await client.connect(
                    host: host,
                    port: port,
                    pairingCode: pairingCode,
                    timeout: timeout ?? 10
                )
            case .nearby:
                if let timeout {
                    connected = try await nearbyClient.connect(
                        pairingCode: pairingCode,
                        timeout: timeout
                    )
                } else {
                    connected = try await nearbyClient.connectWaitingForServer(
                        pairingCode: pairingCode
                    )
                }
            }
            provisionalChannel = connected
            try await connected.send(.hello(DirectPeerCapabilities(
                platform: .iOS,
                installationID: installationID
            )))
            guard !Task.isCancelled,
                  isEnabled,
                  appIsActive,
                  channel == nil,
                  configuredTransport == transport,
                  configuredHost == host,
                  configuredPort == port else {
                connected.cancel()
                return
            }
            channel = connected
            provisionalChannel = nil
            isConnected = true
            connectedCLIName = connected.peerDisplayName
            needsPairingCode = false
            lastError = nil
            beginSession(on: connected)
        } catch {
            provisionalChannel?.cancel()
            guard !Task.isCancelled else { return }
            if reportErrors { lastError = error.localizedDescription }
            if client.savedServer() == nil { needsPairingCode = true }
        }
    }

    private func beginSession(on connected: DirectSecureChannel) {
        let sessionID = UUID()
        activeSessionID = sessionID
        sessionTask?.cancel()
        let exportConnection = IPhoneDirectExportConnection(channel: connected)
        self.exportConnection = exportConnection
        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let payload = try await connected.receive()
                    guard case .message(let message) = payload else {
                        continue
                    }
                    guard !Task.isCancelled,
                          self.activeSessionID == sessionID,
                          self.channel === connected else {
                        break
                    }
                    try await self.handle(
                        message,
                        on: connected,
                        exportConnection: exportConnection
                    )
                }
            } catch {
                if !Task.isCancelled,
                   (error as? DirectChannelError) != .connectionClosed,
                   self.activeSessionID == sessionID {
                    self.lastError = error.localizedDescription
                }
            }
            await exportConnection.finish()
            guard self.activeSessionID == sessionID else { return }
            self.exportTask?.cancel()
            self.exportTask = nil
            self.activeExportOperationID = nil
            if self.channel === connected {
                self.channel = nil
                self.remoteCapabilities = nil
                self.isConnected = false
                self.connectedCLIName = nil
            }
            self.exportConnection = nil
            self.sessionTask = nil
            self.activeSessionID = nil
            self.startReconnectLoopIfNeeded()
        }
    }

    private func handle(
        _ message: DirectMessage,
        on channel: DirectSecureChannel,
        exportConnection: IPhoneDirectExportConnection
    ) async throws {
        switch message {
        case .hello(let capabilities):
            guard capabilities.platform == .macOSCLI,
                  capabilities.installationID == channel.peerInstallationID,
                  DirectPeerCapabilities(
                    platform: .iOS,
                    installationID: installationID
                  ).negotiatedProtocolVersion(with: capabilities) != nil else {
                throw DirectChannelError.authenticationFailed(
                    "The connected CLI is not protocol compatible."
                )
            }
            remoteCapabilities = capabilities
        case .statusRequest:
            let status = await statusProvider?() ?? DirectIPhoneStatus(
                name: UIDevice.current.name,
                appActive: appIsActive,
                protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
                exportInProgress: false,
                canTriggerRawExports: exportRequestHandler != nil,
                canTriggerFileExports: false,
                message: exportRequestHandler == nil
                    ? "Direct export support is not enabled in this build yet." : nil
            )
            try await channel.send(.statusResponse(status))
        case .exportRequest(let request):
            if let exportRequestHandler,
               exportTask == nil,
               let remoteCapabilities,
               let negotiation = DirectTransferCapabilities.current.negotiated(
                with: remoteCapabilities.transfer
               ) {
                let binding = DirectPeerBinding(
                    sourceInstallationID: installationID,
                    destinationInstallationID: channel.peerInstallationID
                )
                let operationID = UUID()
                activeExportOperationID = operationID
                exportTask = Task { [weak self] in
                    await exportRequestHandler(
                        request,
                        binding,
                        negotiation,
                        exportConnection
                    )
                    guard self?.activeExportOperationID == operationID else { return }
                    self?.exportTask = nil
                    self?.activeExportOperationID = nil
                }
            } else {
                try await channel.send(.exportRejected(DirectExportFailure(
                    jobID: request.jobID,
                    reason: exportTask == nil ? .unsupportedPeer : .requestInProgress,
                    message: exportTask == nil
                        ? "Direct exports are not enabled in this build yet."
                        : "Another direct export is already active."
                )))
            }
        case .cancel(let jobID):
            if cancelHandler?(jobID) == true {
                try await channel.send(.cancelAcknowledged(jobID: jobID))
                if exportTask != nil, await statusProvider?().activeJobID == jobID {
                    await exportConnection.deliver(message)
                }
            } else {
                try await channel.send(.exportRejected(DirectExportFailure(
                    jobID: jobID,
                    reason: .invalidRequest,
                    message: "The iPhone has no matching direct export job."
                )))
            }
        case .ping:
            try await channel.send(.pong)
        case .transferDisposition, .transferChunkAcknowledgement,
             .transferPartitionAcknowledgement, .transferFinalAcknowledgement:
            await exportConnection.deliver(message)
        case .statusResponse, .exportAccepted, .exportProgress, .exportRejected,
             .transferSession, .rawDayManifest, .fileManifest, .transferOpen,
             .transferChunk, .transferPartitionComplete, .transferFinalize,
             .completionConfirmed, .cancelAcknowledged, .pong:
            break
        }
    }

    private func disconnect(clearError: Bool) {
        reconnectGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        visibleConnectionAttemptID = nil
        activeSessionID = nil
        sessionTask?.cancel()
        sessionTask = nil
        activeExportOperationID = nil
        exportTask?.cancel()
        exportTask = nil
        if let exportConnection {
            Task { await exportConnection.finish() }
        }
        self.exportConnection = nil
        channel?.cancel()
        channel = nil
        remoteCapabilities = nil
        isConnected = false
        isConnecting = false
        connectedCLIName = nil
        if clearError { lastError = nil }
    }

    private static func loadOrCreateInstallationID(defaults: UserDefaults) -> UUID {
        if let value = defaults.string(forKey: installationIDKey),
           let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString.lowercased(), forKey: installationIDKey)
        return identifier
    }
}
#endif
