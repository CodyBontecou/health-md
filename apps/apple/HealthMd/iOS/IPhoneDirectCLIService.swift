#if os(iOS)
import Combine
import HealthMdConnectionCore
import Network
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

nonisolated struct IPhoneDirectCLIPairingLink: Equatable, Sendable {
    let host: String
    let port: UInt16
    let pairingCode: String

    init?(url: URL) {
        guard url.scheme?.lowercased() == "healthmd",
              url.host?.lowercased() == "direct-cli",
              url.path == "/pair",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 3 else { return nil }
        var values: [String: String] = [:]
        for item in queryItems {
            guard ["host", "port", "code"].contains(item.name),
                  values[item.name] == nil,
                  let value = item.value else { return nil }
            values[item.name] = value
        }
        guard let host = values["host"],
              host.utf8.count <= 45,
              IPv4Address(host) != nil,
              let portText = values["port"],
              let port = UInt16(portText),
              port > 0,
              let pairingCode = values["code"],
              pairingCode.utf8.count == 6,
              pairingCode.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        self.host = host
        self.port = port
        self.pairingCode = pairingCode
    }
}

enum IPhoneDirectCLIBackgroundAction: Equatable, Sendable {
    case disconnect
    case continueActiveExport
}

struct IPhoneDirectCLIBackgroundPolicy {
    nonisolated static func action(
        hasActiveExport: Bool,
        hasLiveChannel: Bool
    ) -> IPhoneDirectCLIBackgroundAction {
        hasActiveExport && hasLiveChannel ? .continueActiveExport : .disconnect
    }

    nonisolated static func allowsCancellation(
        requestedJobID: UUID,
        activeJobID: UUID?,
        appIsActive: Bool
    ) -> Bool {
        appIsActive || requestedJobID == activeJobID
    }
}

/// Opt-in client for a one-shot `healthmd --backend direct` listener. New CLI
/// connections remain foreground-scoped, while an already-active export may
/// use finite iOS background execution time to finish or reach a durable pause.
/// iOS remains the HealthKit owner.
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
    @Published private(set) var pendingPairingLink: IPhoneDirectCLIPairingLink?

    var statusProvider: (() async -> DirectIPhoneStatus)?
    var exportRequestHandler: ((
        DirectExportRequest,
        DirectPeerBinding,
        DirectTransferNegotiation,
        IPhoneDirectExportConnection,
        AppleDirectProtocolAuthority
    ) async -> Void)?
    var cancelHandler: ((UUID) -> Bool)?
    var queryRequestHandler: ((DirectQueryRequest, DirectSecureChannel) async -> Void)?

    private let defaults: UserDefaults
    private let trustStore: ManualIPTrustStore
    private let installationID: UUID
    private let reconnectPolicy: IPhoneDirectCLIReconnectPolicy
    private let protocolAuthority: AppleDirectProtocolAuthority
    private lazy var client = DirectManualIPClient(
        installationID: installationID,
        displayName: UIDevice.current.name,
        trustStore: trustStore,
        messageCanonicalizer: protocolAuthority
    )
    private lazy var nearbyClient = DirectNearbyClient(
        installationID: installationID,
        displayName: UIDevice.current.name,
        trustStore: trustStore,
        messageCanonicalizer: protocolAuthority
    )
    private let idleTimerActivityID = UUID()
    private var reconnectTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var exportTask: Task<Void, Never>?
    private var activeExportOperationID: UUID?
    private var activeExportJobID: UUID?
    private var queryTask: Task<Void, Never>?
    private var activeQueryOperationID: UUID?
    private var activeQueryRequestID: UUID?
    private var exportConnection: IPhoneDirectExportConnection?
    private var channel: DirectSecureChannel?
    private var remoteCapabilities: DirectPeerCapabilities?
    private var appIsActive = false
    private var backgroundExportTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundExportContinuationID: UUID?
    private var reconnectGeneration = 0
    private var visibleConnectionAttemptID: UUID?

    init(
        defaults: UserDefaults = .standard,
        reconnectPolicy: IPhoneDirectCLIReconnectPolicy = .production,
        protocolAuthority: AppleDirectProtocolAuthority = .shared
    ) {
        self.defaults = defaults
        self.reconnectPolicy = reconnectPolicy
        self.protocolAuthority = protocolAuthority
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

    func prepare(pairingLink: IPhoneDirectCLIPairingLink) {
        pendingPairingLink = pairingLink
        lastError = nil
    }

    func approvePendingPairingLink() {
        guard let pairingLink = pendingPairingLink else { return }
        guard exportTask == nil, queryTask == nil else {
            lastError = "Wait for the active direct operation before changing pairing."
            return
        }
        defaults.set(DirectTransportKind.manualIP.rawValue, forKey: Self.transportKey)
        disconnect(clearError: true)
        connect(
            host: pairingLink.host,
            port: pairingLink.port,
            pairingCode: pairingLink.pairingCode
        )
    }

    func cancelPendingPairingLink() {
        pendingPairingLink = nil
        if isConnecting, client.savedServer() == nil {
            disconnect(clearError: true)
        }
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
        pendingPairingLink = nil
        disconnect(clearError: true)
        needsPairingCode = true
    }

    func applicationDidBecomeActive() {
        appIsActive = true
        endBackgroundExportContinuation()
        updateIdleTimer()
        IPhoneDirectExportCoordinator.shared.cleanupExpiredJobs()
        startReconnectLoopIfNeeded()
    }

    func applicationDidEnterBackground() {
        appIsActive = false
        updateIdleTimer()
        if queryTask != nil {
            disconnect(clearError: false)
            return
        }

        switch IPhoneDirectCLIBackgroundPolicy.action(
            hasActiveExport: exportTask != nil,
            hasLiveChannel: channel != nil
        ) {
        case .continueActiveExport:
            stopReconnectLoop()
            if !beginBackgroundExportContinuation() {
                disconnect(clearError: false)
            }
        case .disconnect:
            disconnect(clearError: false)
        }
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
            try protocolAuthority.assertCompatible()
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
                protocolVersions: [
                    HealthMdDirectProtocol.currentVersion,
                    HealthMdDirectProtocol.queryVersion
                ],
                platform: .iOS,
                installationID: installationID,
                query: .current
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
            pendingPairingLink = nil
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
            self.protocolAuthority.endOperation()
            guard self.activeSessionID == sessionID else { return }
            self.exportTask?.cancel()
            self.exportTask = nil
            self.activeExportOperationID = nil
            self.activeExportJobID = nil
            self.queryTask?.cancel()
            self.queryTask = nil
            self.activeQueryOperationID = nil
            self.activeQueryRequestID = nil
            self.endBackgroundExportContinuation()
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
                    protocolVersions: [
                        HealthMdDirectProtocol.currentVersion,
                        HealthMdDirectProtocol.queryVersion
                    ],
                    platform: .iOS,
                    installationID: installationID,
                    query: .current
                  ).negotiatedProtocolVersion(with: capabilities) != nil else {
                throw DirectChannelError.authenticationFailed(
                    "The connected CLI is not protocol compatible."
                )
            }
            _ = try protocolAuthority.negotiateTransfer(peer: capabilities.transfer)
            remoteCapabilities = capabilities
            protocolAuthority.beginBootstrap()
        case .statusRequest:
            if !appIsActive {
                try await channel.send(.statusResponse(DirectIPhoneStatus(
                    name: UIDevice.current.name,
                    appActive: false,
                    protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
                    exportInProgress: exportTask != nil,
                    canTriggerRawExports: false,
                    canTriggerFileExports: false,
                    queryInProgress: queryTask != nil,
                    canTriggerQueries: false,
                    activeJobID: activeExportJobID,
                    activeQueryRequestID: activeQueryRequestID,
                    message: "An active direct operation is using finite background time. Reopen Health.md before starting another command."
                )))
                break
            }
            let status = await statusProvider?() ?? DirectIPhoneStatus(
                name: UIDevice.current.name,
                appActive: true,
                protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
                exportInProgress: false,
                canTriggerRawExports: exportRequestHandler != nil,
                canTriggerFileExports: false,
                queryInProgress: queryTask != nil,
                canTriggerQueries: queryRequestHandler != nil && queryTask == nil && exportTask == nil,
                activeQueryRequestID: activeQueryRequestID,
                message: exportRequestHandler == nil
                    ? "Direct export support is not enabled in this build yet." : nil
            )
            try await channel.send(.statusResponse(status))
        case .exportRequest(let request):
            guard appIsActive else {
                try await channel.send(.exportRejected(DirectExportFailure(
                    jobID: request.jobID,
                    reason: .invalidRequest,
                    message: "Reopen Health.md before starting another direct export."
                )))
                break
            }
            if let exportRequestHandler,
               exportTask == nil,
               queryTask == nil,
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
                activeExportJobID = request.jobID
                _ = beginBackgroundExportContinuation()
                exportTask = Task { [weak self] in
                    guard let self else { return }
                    await exportRequestHandler(
                        request,
                        binding,
                        negotiation,
                        exportConnection,
                        self.protocolAuthority
                    )
                    self.finishExportOperation(operationID)
                }
            } else {
                try await channel.send(.exportRejected(DirectExportFailure(
                    jobID: request.jobID,
                    reason: exportRequestHandler == nil ? .unsupportedPeer : .requestInProgress,
                    message: exportRequestHandler == nil
                        ? "Direct exports are not enabled in this build yet."
                        : "Another direct operation is already active."
                )))
            }
        case .queryRequest(let request):
            guard appIsActive else {
                try await channel.send(.queryRejected(DirectQueryFailure(
                    requestID: request.requestID,
                    code: "query_unavailable",
                    message: "Reopen Health.md before starting another direct query.",
                    retryable: true
                )))
                break
            }
            guard request.protocolVersion == HealthMdDirectProtocol.queryVersion,
                  remoteCapabilities?.protocolVersions.contains(HealthMdDirectProtocol.queryVersion) == true,
                  remoteCapabilities?.query != nil,
                  let queryRequestHandler,
                  exportTask == nil,
                  queryTask == nil else {
                try await channel.send(.queryRejected(DirectQueryFailure(
                    requestID: request.requestID,
                    code: exportTask == nil && queryTask == nil
                        ? "query_unsupported" : "request_in_progress",
                    message: exportTask == nil && queryTask == nil
                        ? "The connected CLI and iPhone did not negotiate direct queries."
                        : "Another direct operation is already active.",
                    retryable: exportTask != nil || queryTask != nil
                )))
                break
            }
            let operationID = UUID()
            activeQueryOperationID = operationID
            activeQueryRequestID = request.requestID
            queryTask = Task { [weak self] in
                guard let self else { return }
                await queryRequestHandler(request, channel)
                self.finishQueryOperation(operationID)
            }
        case .cancel(let jobID):
            guard IPhoneDirectCLIBackgroundPolicy.allowsCancellation(
                requestedJobID: jobID,
                activeJobID: activeExportJobID,
                appIsActive: appIsActive
            ) else {
                try await channel.send(.exportRejected(DirectExportFailure(
                    jobID: jobID,
                    reason: .invalidRequest,
                    message: "Only the active export can be cancelled while Health.md is in the background."
                )))
                break
            }
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
        case .statusResponse, .queryResponse, .queryRejected,
             .exportAccepted, .exportProgress, .exportRejected,
             .transferSession, .rawDayManifest, .fileManifest, .transferOpen,
             .transferChunk, .transferPartitionComplete, .transferFinalize,
             .completionConfirmed, .cancelAcknowledged, .pong:
            break
        }
    }

    private func finishQueryOperation(_ operationID: UUID) {
        guard activeQueryOperationID == operationID else { return }
        queryTask = nil
        activeQueryOperationID = nil
        activeQueryRequestID = nil
        endBackgroundExportContinuation()
        if !appIsActive {
            disconnect(clearError: false)
        }
    }

    private func finishExportOperation(_ operationID: UUID) {
        guard activeExportOperationID == operationID else { return }
        exportTask = nil
        activeExportOperationID = nil
        activeExportJobID = nil
        endBackgroundExportContinuation()
        if !appIsActive {
            disconnect(clearError: false)
        }
    }

    @discardableResult
    private func beginBackgroundExportContinuation() -> Bool {
        guard backgroundExportTaskID == .invalid else { return true }
        let continuationID = UUID()
        backgroundExportContinuationID = continuationID
        backgroundExportTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "HealthMD-DirectCLIExport"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.backgroundExportContinuationID == continuationID,
                      !self.appIsActive else { return }
                self.endBackgroundExportContinuation()
                self.disconnect(clearError: false)
            }
        }
        if backgroundExportTaskID == .invalid {
            backgroundExportContinuationID = nil
            return false
        }
        return true
    }

    private func endBackgroundExportContinuation() {
        backgroundExportContinuationID = nil
        guard backgroundExportTaskID != .invalid else { return }
        let taskID = backgroundExportTaskID
        backgroundExportTaskID = .invalid
        UIApplication.shared.endBackgroundTask(taskID)
    }

    private func stopReconnectLoop() {
        reconnectGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        visibleConnectionAttemptID = nil
        isConnecting = false
    }

    private func disconnect(clearError: Bool) {
        stopReconnectLoop()
        activeSessionID = nil
        sessionTask?.cancel()
        sessionTask = nil
        activeExportOperationID = nil
        activeExportJobID = nil
        exportTask?.cancel()
        exportTask = nil
        activeQueryOperationID = nil
        activeQueryRequestID = nil
        queryTask?.cancel()
        queryTask = nil
        if let exportConnection {
            Task { await exportConnection.finish() }
        }
        self.exportConnection = nil
        channel?.cancel()
        channel = nil
        remoteCapabilities = nil
        protocolAuthority.endOperation()
        isConnected = false
        isConnecting = false
        connectedCLIName = nil
        endBackgroundExportContinuation()
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
