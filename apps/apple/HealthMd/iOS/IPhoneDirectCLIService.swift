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

nonisolated struct IPhoneDirectCLIIdleHeartbeatPolicy: Equatable, Sendable {
    /// Idle inbound time on a live channel before an application-level ping probes it.
    let pingIdleThreshold: Duration
    /// Time a ping may remain unanswered before the channel is declared unreachable.
    let pongTimeout: Duration

    nonisolated static let production = IPhoneDirectCLIIdleHeartbeatPolicy(
        // Legacy status clients wait ten seconds for StatusResponse and expect it to be the
        // next control message. Probe only after that compatibility window has elapsed.
        pingIdleThreshold: .seconds(11),
        pongTimeout: .seconds(5)
    )

    enum Action: Equatable, Sendable {
        case none
        case sendPing
        case declareUnreachable
    }

    nonisolated func action(
        lastInboundAt: ContinuousClock.Instant,
        pingSentAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> Action {
        guard lastInboundAt <= now else { return .none }
        if let pingSentAt {
            guard pingSentAt <= now else { return .none }
            return pingSentAt.duration(to: now) >= pongTimeout
                ? .declareUnreachable
                : .none
        }
        return lastInboundAt.duration(to: now) >= pingIdleThreshold
            ? .sendPing
            : .none
    }
}

nonisolated struct IPhoneDirectCLIPairingLink: Equatable, Sendable {
    let host: String
    let port: UInt16
    let pairingCode: String

    init?(url: URL) {
        let rawURL = url.absoluteString
        guard rawURL.utf8.count <= 512,
              rawURL.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
              !rawURL.contains("%"),
              rawURL.hasPrefix("healthmd://direct-cli/pair?"),
              url.scheme == "healthmd",
              url.host == "direct-cli",
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
              host.utf8.count <= 15,
              Self.isAllowedLocalPairingHost(host),
              let portText = values["port"],
              portText.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = UInt16(portText),
              port > 0,
              let pairingCode = values["code"],
              pairingCode.utf8.count == DirectPairingSecurity.sharedPairingCodeDigits,
              pairingCode.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        self.host = host
        self.port = port
        self.pairingCode = pairingCode
    }

    init?(scannedPayload: String) {
        guard !scannedPayload.isEmpty,
              scannedPayload.utf8.count <= 512,
              scannedPayload == scannedPayload.trimmingCharacters(in: .whitespacesAndNewlines),
              !scannedPayload.contains("%"),
              scannedPayload.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URL(string: scannedPayload) else { return nil }
        self.init(url: url)
    }

    private static func isAllowedLocalPairingHost(_ host: String) -> Bool {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for component in components {
            let digits = Array(component.utf8)
            guard (1...3).contains(digits.count),
                  digits.allSatisfy({ (48...57).contains($0) }),
                  digits.count == 1 || digits[0] != 48 else { return false }
            var value = 0
            for digit in digits {
                value = value * 10 + Int(digit - 48)
            }
            guard let octet = UInt8(exactly: value) else { return false }
            octets.append(octet)
        }
        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 100 && (64...127).contains(octets[1]))
    }
}

enum IPhoneDirectCLIPairingHandoffAction: Equatable, Sendable {
    case deferUntilActive
    case connect
    case waitForActiveOperation
    case expired
}

struct IPhoneDirectCLIPairingHandoffPolicy {
    nonisolated static func action(
        appIsActive: Bool,
        hasActiveOperation: Bool,
        receivedAt: Date,
        now: Date = Date()
    ) -> IPhoneDirectCLIPairingHandoffAction {
        let age = now.timeIntervalSince(receivedAt)
        guard age >= 0, age < DirectPairingSecurity.pairingCodeLifetime else {
            return .expired
        }
        guard appIsActive else { return .deferUntilActive }
        return hasActiveOperation ? .waitForActiveOperation : .connect
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
    private struct ProvisionalPairingTrust {
        let sessionID: UUID
        let previousServer: ManualIPTrustedMac?
    }

    struct PairingConfigurationSnapshot: Codable {
        let host: String?
        let port: String?
        let transport: String?
        let enabled: Bool?
        let previousTrustedMacInstallationID: UUID?
        let previousTrustedMacPairedAt: Date?

        func stillHasPreviousTrust(_ trustedMac: ManualIPTrustedMac?) -> Bool {
            guard let previousTrustedMacInstallationID,
                  let previousTrustedMacPairedAt else {
                return trustedMac == nil
            }
            guard let trustedMac else { return true }
            return trustedMac.installationID == previousTrustedMacInstallationID
                && trustedMac.pairedAt == previousTrustedMacPairedAt
        }
    }

    static let enabledKey = "directCLIEnabled"
    static let hostKey = "directCLIHost"
    static let portKey = "directCLIPort"
    static let transportKey = "directCLITransport"
    static let installationIDKey = "directCLIInstallationID"
    private static let pendingPairingConfigurationKey =
        "directCLIPendingPairingConfigurationV1"

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
    private let heartbeatPolicy: IPhoneDirectCLIIdleHeartbeatPolicy
    private let heartbeatClock = ContinuousClock()
    private let protocolAuthority: AppleDirectProtocolAuthority
    private let wakeManager: (any IPhoneDirectWakeManaging)?
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
    private var lastInboundActivityAt: ContinuousClock.Instant?
    private var heartbeatPingSentAt: ContinuousClock.Instant?
    private var backgroundExportTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundExportContinuationID: UUID?
    private var reconnectGeneration = 0
    private var visibleConnectionAttemptID: UUID?
    private var shouldAutoConnectPendingPairingLink = false
    private var pendingPairingLinkReceivedAt: Date?
    private var pendingPairingAttemptHasStarted = false
    private var pendingPairingExpiryTask: Task<Void, Never>?
    private var provisionalPairingTrust: ProvisionalPairingTrust?
    private var pairingConfigurationSnapshot: PairingConfigurationSnapshot?

    init(
        defaults: UserDefaults = .standard,
        reconnectPolicy: IPhoneDirectCLIReconnectPolicy = .production,
        heartbeatPolicy: IPhoneDirectCLIIdleHeartbeatPolicy = .production,
        protocolAuthority: AppleDirectProtocolAuthority = .shared,
        wakeManager: (any IPhoneDirectWakeManaging)? = nil
    ) {
        self.defaults = defaults
        self.reconnectPolicy = reconnectPolicy
        self.heartbeatPolicy = heartbeatPolicy
        self.protocolAuthority = protocolAuthority
        self.wakeManager = wakeManager
        self.installationID = Self.loadOrCreateInstallationID(defaults: defaults)
        let trustStore = ManualIPTrustStore(
            service: "com.codybontecou.obsidianhealth.direct-cli-ios-trust",
            account: "trust-state-v1"
        )
        self.trustStore = trustStore
        var trustState = trustStore.loadState(ownerInstallationID: installationID)
        if defaults.data(forKey: Self.pendingPairingConfigurationKey) != nil {
            if let interruptedPairing = Self.loadPendingPairingConfiguration(defaults: defaults),
               interruptedPairing.stillHasPreviousTrust(trustState.trustedMac) {
                Self.restorePairingConfiguration(interruptedPairing, defaults: defaults)
            }
            defaults.removeObject(forKey: Self.pendingPairingConfigurationKey)
        }
        if trustState.provisionalTrustedMac != nil {
            trustState.provisionalTrustedMac = nil
            try? trustStore.saveState(trustState)
        }
        self.needsPairingCode = trustState.trustedMac == nil
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

    var isPairingHandoffWaitingForActiveOperation: Bool {
        pendingPairingLink != nil
            && shouldAutoConnectPendingPairingLink
            && (exportTask != nil || queryTask != nil)
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

    func rejectExternalPairingLink() {
        guard pendingPairingLink == nil, !isConnecting else { return }
        lastError = "For secure pairing, open the Sync tab and use Scan Pairing QR inside Health.md."
    }

    func handleScannedPairingLink(_ pairingLink: IPhoneDirectCLIPairingLink) {
        if pendingPairingLink == pairingLink,
           isConnecting
            || shouldAutoConnectPendingPairingLink
            || pendingPairingAttemptHasStarted {
            return
        }
        guard !isConnecting, !pendingPairingAttemptHasStarted else {
            lastError = "Wait for the current QR pairing attempt before opening another code."
            return
        }
        pendingPairingLink = pairingLink
        let receivedAt = Date()
        pendingPairingLinkReceivedAt = receivedAt
        pendingPairingAttemptHasStarted = false
        shouldAutoConnectPendingPairingLink = true
        lastError = nil
        schedulePendingPairingLinkExpiry(pairingLink, receivedAt: receivedAt)
        beginPendingPairingLinkIfReady()
    }

    func retryPendingPairingLink() {
        guard pendingPairingLink != nil else { return }
        shouldAutoConnectPendingPairingLink = true
        lastError = nil
        beginPendingPairingLinkIfReady()
    }

    private func schedulePendingPairingLinkExpiry(
        _ pairingLink: IPhoneDirectCLIPairingLink,
        receivedAt: Date
    ) {
        pendingPairingExpiryTask?.cancel()
        pendingPairingExpiryTask = Task { [weak self] in
            let nanoseconds = UInt64(
                DirectPairingSecurity.pairingCodeLifetime * 1_000_000_000
            )
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self,
                  self.pendingPairingLink == pairingLink,
                  self.pendingPairingLinkReceivedAt == receivedAt else { return }
            let shouldDisconnect = self.pendingPairingAttemptHasStarted
            self.clearPendingPairingLinkState()
            if shouldDisconnect {
                self.disconnect(clearError: false)
            }
            self.needsPairingCode = self.client.savedServer() == nil
            self.lastError = "This pairing QR expired. Scan a fresh QR code."
        }
    }

    private func clearPendingPairingLinkState() {
        pendingPairingExpiryTask?.cancel()
        pendingPairingExpiryTask = nil
        pendingPairingLink = nil
        pendingPairingLinkReceivedAt = nil
        pendingPairingAttemptHasStarted = false
        shouldAutoConnectPendingPairingLink = false
    }

    private func capturePairingConfigurationIfNeeded() -> Bool {
        guard pairingConfigurationSnapshot == nil else { return true }
        let previousServer = client.savedServer()
        let snapshot = PairingConfigurationSnapshot(
            host: defaults.object(forKey: Self.hostKey) as? String,
            port: defaults.object(forKey: Self.portKey) as? String,
            transport: defaults.object(forKey: Self.transportKey) as? String,
            enabled: defaults.object(forKey: Self.enabledKey) as? Bool,
            previousTrustedMacInstallationID: previousServer?.installationID,
            previousTrustedMacPairedAt: previousServer?.pairedAt
        )
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(encoded, forKey: Self.pendingPairingConfigurationKey)
        pairingConfigurationSnapshot = snapshot
        return true
    }

    private static func loadPendingPairingConfiguration(
        defaults: UserDefaults
    ) -> PairingConfigurationSnapshot? {
        guard let encoded = defaults.data(forKey: pendingPairingConfigurationKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PairingConfigurationSnapshot.self, from: encoded)
    }

    private static func restorePairingConfiguration(
        _ snapshot: PairingConfigurationSnapshot,
        defaults: UserDefaults
    ) {
        restoreDefault(snapshot.host, forKey: hostKey, defaults: defaults)
        restoreDefault(snapshot.port, forKey: portKey, defaults: defaults)
        restoreDefault(snapshot.transport, forKey: transportKey, defaults: defaults)
        restoreDefault(snapshot.enabled, forKey: enabledKey, defaults: defaults)
    }

    private func restorePairingConfigurationIfNeeded() {
        guard let snapshot = pairingConfigurationSnapshot else { return }
        pairingConfigurationSnapshot = nil
        Self.restorePairingConfiguration(snapshot, defaults: defaults)
        defaults.removeObject(forKey: Self.pendingPairingConfigurationKey)
    }

    private static func restoreDefault(
        _ value: Any?,
        forKey key: String,
        defaults: UserDefaults
    ) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func beginPendingPairingLinkIfReady() {
        guard shouldAutoConnectPendingPairingLink,
              let pairingLink = pendingPairingLink,
              let receivedAt = pendingPairingLinkReceivedAt else { return }
        switch IPhoneDirectCLIPairingHandoffPolicy.action(
            appIsActive: appIsActive,
            hasActiveOperation: exportTask != nil || queryTask != nil,
            receivedAt: receivedAt
        ) {
        case .deferUntilActive:
            return
        case .waitForActiveOperation:
            lastError = nil
        case .expired:
            let shouldDisconnect = pendingPairingAttemptHasStarted
            clearPendingPairingLinkState()
            if shouldDisconnect {
                disconnect(clearError: false)
            }
            needsPairingCode = client.savedServer() == nil
            lastError = "This pairing QR expired. Scan a fresh QR code."
        case .connect:
            shouldAutoConnectPendingPairingLink = false
            pendingPairingAttemptHasStarted = true
            disconnect(clearError: true)
            guard capturePairingConfigurationIfNeeded() else {
                clearPendingPairingLinkState()
                lastError = "Pairing could not preserve the current Direct CLI settings. Try again."
                return
            }
            defaults.set(DirectTransportKind.manualIP.rawValue, forKey: Self.transportKey)
            connect(
                host: pairingLink.host,
                port: pairingLink.port,
                pairingCode: pairingLink.pairingCode
            )
        }
    }

    func cancelPendingPairingLink() {
        let shouldDisconnectPairingAttempt = pendingPairingAttemptHasStarted
        clearPendingPairingLinkState()
        if shouldDisconnectPairingAttempt {
            disconnect(clearError: true)
        } else {
            lastError = nil
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
        disconnect(clearError: true)
        clearPendingPairingLinkState()
        if let wakeManager {
            Task { await wakeManager.forgetAll() }
        }
        do {
            try client.forgetServer()
            needsPairingCode = true
        } catch {
            needsPairingCode = client.savedServer() == nil
            lastError = error.localizedDescription
        }
    }

    func applicationDidBecomeActive() {
        appIsActive = true
        endBackgroundExportContinuation()
        updateIdleTimer()
        IPhoneDirectExportCoordinator.shared.cleanupExpiredJobs()
        beginPendingPairingLinkIfReady()
        startReconnectLoopIfNeeded()
    }

    func applicationWillResignActive() {
        appIsActive = false
        updateIdleTimer()
    }

    func applicationDidEnterBackground() {
        appIsActive = false
        updateIdleTimer()
        if queryTask != nil {
            disconnectForBackground()
            return
        }

        switch IPhoneDirectCLIBackgroundPolicy.action(
            hasActiveExport: exportTask != nil,
            hasLiveChannel: channel != nil
        ) {
        case .continueActiveExport:
            stopReconnectLoop()
            if !beginBackgroundExportContinuation() {
                disconnectForBackground()
            }
        case .disconnect:
            disconnectForBackground()
        }
    }

    private func disconnectForBackground() {
        let shouldResumePendingPairing = pendingPairingLink != nil && lastError == nil
        disconnect(clearError: false)
        if shouldResumePendingPairing, lastError == nil {
            pendingPairingAttemptHasStarted = false
            shouldAutoConnectPendingPairingLink = true
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
        guard isEnabled,
              appIsActive,
              reconnectTask == nil,
              pendingPairingLink == nil else { return }
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
                    let heartbeatNow = self.heartbeatClock.now
                    switch self.evaluateIdleHeartbeat(now: heartbeatNow) {
                    case .none:
                        break
                    case .sendPing:
                        if let channel = self.channel {
                            self.heartbeatPingSentAt = heartbeatNow
                            try? await channel.send(.ping)
                        }
                    case .declareUnreachable:
                        // A silent peer (sleep, network roam, process death without a clean
                        // close) leaves the channel half-open. Kernel keepalives cover most
                        // cases; this watchdog bounds the rest, including Nearby. Cancelling
                        // the channel fails the pending session receive, teardown clears the
                        // stale state, and this loop dials again without user action.
                        self.channel?.cancel()
                    }
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

    private func evaluateIdleHeartbeat(
        now: ContinuousClock.Instant
    ) -> IPhoneDirectCLIIdleHeartbeatPolicy.Action {
        guard let lastInboundActivityAt else { return .none }
        return heartbeatPolicy.action(
            lastInboundAt: lastInboundActivityAt,
            pingSentAt: heartbeatPingSentAt,
            now: now
        )
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
        let isCodePairing = pairingCode?.isEmpty == false
        let savedServerBeforePairing = isCodePairing ? client.savedServer() : nil
        var provisionalChannel: DirectSecureChannel?
        var pairingTrustWasWritten = false
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
            pairingTrustWasWritten = isCodePairing
            provisionalChannel = connected
            try await connected.send(.hello(DirectPeerCapabilities(
                protocolVersions: [
                    HealthMdDirectProtocol.currentVersion,
                    HealthMdDirectProtocol.queryVersion
                ],
                platform: .iOS,
                installationID: installationID,
                query: .current,
                wake: wakeManager?.advertisesWake == true
                    ? DirectWakeCapabilities(supported: true)
                    : nil
            )))
            guard !Task.isCancelled,
                  isEnabled,
                  appIsActive,
                  channel == nil,
                  configuredTransport == transport,
                  configuredHost == host,
                  configuredPort == port else {
                connected.cancel()
                if pairingTrustWasWritten {
                    do {
                        try client.restoreSavedServer(savedServerBeforePairing)
                    } catch {
                        clearPendingPairingLinkState()
                        if reportErrors {
                            lastError = "Pairing stopped and previous CLI trust could not be restored. Forget the paired CLI before trying again."
                        }
                    }
                }
                if isCodePairing {
                    pendingPairingAttemptHasStarted = false
                    restorePairingConfigurationIfNeeded()
                }
                return
            }
            channel = connected
            provisionalChannel = nil
            isConnected = true
            connectedCLIName = connected.peerDisplayName
            needsPairingCode = false
            lastError = nil
            beginSession(
                on: connected,
                pairingTrustWasWritten: pairingTrustWasWritten,
                previousServer: savedServerBeforePairing
            )
        } catch {
            provisionalChannel?.cancel()
            var trustRestoreFailed = false
            if isCodePairing {
                do {
                    try client.restoreSavedServer(savedServerBeforePairing)
                } catch {
                    trustRestoreFailed = true
                }
                pendingPairingAttemptHasStarted = false
                restorePairingConfigurationIfNeeded()
            }
            if trustRestoreFailed {
                clearPendingPairingLinkState()
                lastError = "Pairing did not complete and previous CLI trust could not be restored. Forget the paired CLI and scan a fresh QR code."
            }
            guard !Task.isCancelled else { return }
            if reportErrors, !trustRestoreFailed {
                lastError = error.localizedDescription
            }
            if client.savedServer() == nil { needsPairingCode = true }
        }
    }

    private func commitProvisionalPairingTrustIfNeeded(for sessionID: UUID) throws {
        guard provisionalPairingTrust?.sessionID == sessionID else { return }
        guard appIsActive else {
            let trustWasRestored = rollbackProvisionalPairingTrustIfNeeded(for: sessionID)
            guard trustWasRestored else {
                throw DirectChannelError.authenticationFailed(
                    "Pairing stopped and previous CLI trust could not be restored. Forget the paired CLI before trying again."
                )
            }
            shouldAutoConnectPendingPairingLink = true
            throw DirectChannelError.authenticationFailed(
                "Keep Health.md foreground while pairing completes."
            )
        }
        guard let receivedAt = pendingPairingLinkReceivedAt,
              IPhoneDirectCLIPairingHandoffPolicy.action(
                appIsActive: true,
                hasActiveOperation: false,
                receivedAt: receivedAt
              ) != .expired else {
            let trustWasRestored = rollbackProvisionalPairingTrustIfNeeded(for: sessionID)
            guard trustWasRestored else {
                throw DirectChannelError.authenticationFailed(
                    "Pairing expired and previous CLI trust could not be restored. Forget the paired CLI before trying again."
                )
            }
            clearPendingPairingLinkState()
            throw DirectChannelError.authenticationFailed(
                "This pairing QR expired. Scan a fresh QR code."
            )
        }
        try client.commitProvisionalServer()
        provisionalPairingTrust = nil
        pairingConfigurationSnapshot = nil
        defaults.removeObject(forKey: Self.pendingPairingConfigurationKey)
        clearPendingPairingLinkState()
        needsPairingCode = false
    }

    @discardableResult
    private func rollbackProvisionalPairingTrustIfNeeded(for sessionID: UUID? = nil) -> Bool {
        guard let provisionalPairingTrust,
              sessionID == nil || provisionalPairingTrust.sessionID == sessionID else {
            return true
        }
        self.provisionalPairingTrust = nil
        pendingPairingAttemptHasStarted = false
        restorePairingConfigurationIfNeeded()
        do {
            try client.restoreSavedServer(provisionalPairingTrust.previousServer)
            needsPairingCode = client.savedServer() == nil
            return true
        } catch {
            clearPendingPairingLinkState()
            lastError = "Pairing did not complete and previous CLI trust could not be restored. Forget the paired CLI before trying again."
            return false
        }
    }

    private func beginSession(
        on connected: DirectSecureChannel,
        pairingTrustWasWritten: Bool,
        previousServer: ManualIPTrustedMac?
    ) {
        let sessionID = UUID()
        activeSessionID = sessionID
        lastInboundActivityAt = heartbeatClock.now
        heartbeatPingSentAt = nil
        sessionTask?.cancel()
        if pairingTrustWasWritten {
            provisionalPairingTrust = ProvisionalPairingTrust(
                sessionID: sessionID,
                previousServer: previousServer
            )
        }
        let exportConnection = IPhoneDirectExportConnection(channel: connected)
        self.exportConnection = exportConnection
        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let payload = try await connected.receive()
                    lastInboundActivityAt = heartbeatClock.now
                    heartbeatPingSentAt = nil
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
                        exportConnection: exportConnection,
                        sessionID: sessionID
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
            let pairingWasIncomplete = self.provisionalPairingTrust?.sessionID == sessionID
            let pairingTrustWasRestored = self.rollbackProvisionalPairingTrustIfNeeded(
                for: sessionID
            )
            if pairingWasIncomplete,
               pairingTrustWasRestored,
               self.lastError == nil {
                self.lastError = "Pairing did not complete. Keep Health.md open and retry with the current QR, or scan a fresh code."
            }
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
            self.beginPendingPairingLinkIfReady()
            self.startReconnectLoopIfNeeded()
        }
    }

    private func handle(
        _ message: DirectMessage,
        on channel: DirectSecureChannel,
        exportConnection: IPhoneDirectExportConnection,
        sessionID: UUID
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
            try commitProvisionalPairingTrustIfNeeded(for: sessionID)
            // RFC-0005 P2: only a CLI that advertised wake support reads the enrollment, and
            // only a phone with valid material sends it — the deterministic handshake keeps
            // older CLIs (no wake advertisement) byte-compatible and fail-closed.
            if capabilities.wake?.supported == true,
               let wakeManager,
               let enrollment = wakeManager.currentEnrollment() {
                try await channel.send(.wakeEnrollment(enrollment))
            }
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
             .completionConfirmed, .cancelAcknowledged, .pong, .wakeEnrollment:
            // Only the phone sends wake enrollments; receiving one here is a protocol violation.
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
        } else {
            beginPendingPairingLinkIfReady()
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
        } else {
            beginPendingPairingLinkIfReady()
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
        let pairingTrustWasRestored = rollbackProvisionalPairingTrustIfNeeded()
        restorePairingConfigurationIfNeeded()
        stopReconnectLoop()
        lastInboundActivityAt = nil
        heartbeatPingSentAt = nil
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
        if clearError, pairingTrustWasRestored { lastError = nil }
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
