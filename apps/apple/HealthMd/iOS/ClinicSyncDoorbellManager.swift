import Combine
import CryptoKit
import Foundation
import os.log
import UserNotifications

/// Clinic sync requests (clinic-sponsorship contract, "delegated doorbell").
///
/// When the patient separately allows it, the phone registers a `delegated-sync` doorbell with
/// the RFC-0005 wake service and hands its key to the approved clinic endpoint. The clinic can
/// then ring it; the wake service shows a fixed, device-localized notification, and only the
/// patient's tap runs a clinic export. The wake service never learns about the clinic, and a
/// ring never uploads, changes settings, or grants access by itself.
@MainActor
final class ClinicSyncDoorbellManager: ObservableObject {
    static let shared = ClinicSyncDoorbellManager(observeClinicStatus: true)

    nonisolated static let notificationCategory = "HEALTHMD_SYNC_REQUEST"
    nonisolated static let notificationKind = "delegated-sync-request"
    nonisolated static let messageType = "clinic-sync-doorbell.v1"
    nonisolated static let wakeService = "https://healthmd-wake.costream.workers.dev"
    static let pendingRevocationKey = "clinicSyncDoorbellPendingRevocation"

    enum State: Equatable {
        case disabled
        case updating
        case enabled
        case unavailable(reason: String)
    }

    @Published private(set) var state: State = .disabled

    private let store: any ClinicSyncDoorbellStoring
    private let worker: any ClinicSyncWakeServing
    private let messenger: any ClinicSyncControlSending
    private let defaults: UserDefaults
    private let deviceToken: @MainActor () -> String?
    private let requestNotificationAuthorization: @MainActor () async -> Bool
    private let registerForPushNotifications: @MainActor () async -> Void
    private let clinicStatus: @MainActor () -> ClinicSponsorshipStatus
    private let runClinicExport: @MainActor (_ endpoint: String) async -> String
    private let postResult: @MainActor (_ message: String) async -> Void
    private var statusObservation: AnyCancellable?
    private var reconciling = false
    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "ClinicSync")

    init(
        store: any ClinicSyncDoorbellStoring = ClinicSyncDoorbellKeychain(),
        worker: (any ClinicSyncWakeServing)? = nil,
        messenger: (any ClinicSyncControlSending)? = nil,
        defaults: UserDefaults = .standard,
        deviceToken: (@MainActor () -> String?)? = nil,
        requestNotificationAuthorization: (@MainActor () async -> Bool)? = nil,
        registerForPushNotifications: (@MainActor () async -> Void)? = nil,
        clinicStatus: (@MainActor () -> ClinicSponsorshipStatus)? = nil,
        runClinicExport: (@MainActor (String) async -> String)? = nil,
        postResult: (@MainActor (String) async -> Void)? = nil,
        observeClinicStatus: Bool = false
    ) {
        let push = PushRegistrationManager.shared
        self.store = store
        self.worker = worker ?? DirectWakeWorkerClient(pushRegistration: push)
        self.messenger = messenger ?? APIExportClinicControlSender()
        self.defaults = defaults
        self.deviceToken = deviceToken ?? { push.lastDeviceTokenHex }
        self.requestNotificationAuthorization = requestNotificationAuthorization ?? {
            let center = UNUserNotificationCenter.current()
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        self.registerForPushNotifications = registerForPushNotifications ?? {
            await push.registerForRemoteNotificationsIfNeeded()
        }
        self.clinicStatus = clinicStatus ?? { ClinicSponsorshipManager.shared.status }
        self.runClinicExport = runClinicExport ?? ClinicSyncDoorbellManager.exportClinicProfile
        self.postResult = postResult ?? ClinicSyncDoorbellManager.postLocalResult
        if store.load() != nil { state = .enabled }
        if observeClinicStatus {
            statusObservation = ClinicSponsorshipManager.shared.$status
                .removeDuplicates()
                .sink { [weak self] _ in Task { @MainActor in await self?.reconcile() } }
        }
    }

    var isEnabled: Bool { store.load() != nil }

    /// Requests are possible only for an active sponsorship with authorized sharing.
    var canEnable: Bool {
        let status = clinicStatus()
        return status.active && status.sharingAuthorized && status.endpoint != nil
    }

    func enable() async {
        guard state != .updating, store.load() == nil else { return }
        let status = clinicStatus()
        guard status.active, status.sharingAuthorized, let endpoint = status.endpoint,
              let endpointURL = URL(string: endpoint) else {
            state = .unavailable(reason: String(localized: "Allow sharing with this clinic first."))
            return
        }
        state = .updating

        guard await requestNotificationAuthorization() else {
            state = .unavailable(reason: String(localized: "Notification permission was not granted. Allow notifications for Health.md in Settings."))
            return
        }
        await registerForPushNotifications()
        guard let token = deviceToken() else {
            state = .unavailable(reason: String(localized: "Notifications are not ready yet. Try again in a moment."))
            return
        }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            state = .unavailable(reason: String(localized: "The request key could not be generated."))
            return
        }

        let wakeID: String
        do {
            wakeID = try await worker.registerDelegatedSync(verificationHash: SHA256.hash(data: key),
                                                             existingWakeID: nil)
        } catch {
            state = .unavailable(reason: String(localized: "The notification service is not available. Try again later."))
            return
        }
        do {
            let message = ClinicSyncDoorbellMessage.enroll(wakeID: wakeID, wakeKey: key)
            try await messenger.send(try message.encoded(), endpoint: endpointURL)
        } catch {
            // The clinic never received the key: leave no doorbell behind.
            try? await worker.unregister(wakeID: wakeID)
            state = .unavailable(reason: String(localized: "Your clinic could not be reached. Try again later."))
            return
        }
        guard store.save(ClinicSyncDoorbell(wakeID: wakeID, wakeKey: key, endpoint: endpoint, deviceToken: token)) else {
            try? await worker.unregister(wakeID: wakeID)
            state = .unavailable(reason: String(localized: "Unlock your phone and try again. The request key could not be stored securely."))
            return
        }
        state = .enabled
    }

    /// Revokes at the wake service before forgetting local state. A failed revocation is retried
    /// on the next reconcile; until then a ring is ignored because no local doorbell matches.
    func disable() async {
        guard let doorbell = store.load() else {
            state = .disabled
            return
        }
        state = .updating
        do {
            try await worker.unregister(wakeID: doorbell.wakeID)
        } catch {
            defaults.set(doorbell.wakeID, forKey: Self.pendingRevocationKey)
        }
        if let endpointURL = URL(string: doorbell.endpoint),
           let body = try? ClinicSyncDoorbellMessage.revoke(wakeID: doorbell.wakeID).encoded() {
            try? await messenger.send(body, endpoint: endpointURL)
        }
        store.clear()
        state = .disabled
    }

    /// Keeps the doorbell bound to the current clinic consent and push token.
    func reconcile() async {
        guard !reconciling else { return }
        reconciling = true
        defer { reconciling = false }

        if let pending = defaults.string(forKey: Self.pendingRevocationKey),
           (try? await worker.unregister(wakeID: pending)) != nil {
            defaults.removeObject(forKey: Self.pendingRevocationKey)
        }
        guard let doorbell = store.load() else {
            if case .enabled = state { state = .disabled }
            return
        }
        let status = clinicStatus()
        guard status.active, status.sharingAuthorized, status.endpoint == doorbell.endpoint else {
            await disable()
            return
        }
        if let token = deviceToken(), token != doorbell.deviceToken {
            do {
                _ = try await worker.registerDelegatedSync(verificationHash: SHA256.hash(data: doorbell.wakeKey),
                                                           existingWakeID: doorbell.wakeID)
                _ = store.save(ClinicSyncDoorbell(wakeID: doorbell.wakeID, wakeKey: doorbell.wakeKey,
                                                  endpoint: doorbell.endpoint, deviceToken: token))
            } catch {
                logger.error("Clinic sync doorbell token rotation failed; retrying later")
            }
        }
        state = .enabled
    }

    /// Returns `true` when the payload is a clinic sync request; the export then runs only for
    /// the doorbell this phone currently holds.
    nonisolated static func requestedWakeID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let healthmd = userInfo["healthmd"] as? [String: Any],
              healthmd["kind"] as? String == notificationKind,
              let wakeID = healthmd["wakeId"] as? String, !wakeID.isEmpty else { return nil }
        return wakeID
    }

    func handleSyncRequestTap(wakeID: String) async {
        guard let doorbell = store.load(), doorbell.wakeID == wakeID else {
            logger.info("Ignored a sync request for a doorbell this phone no longer holds")
            return
        }
        let status = clinicStatus()
        guard status.active, status.sharingAuthorized, status.endpoint == doorbell.endpoint else {
            await disable()
            await postResult(String(localized: "Clinic sharing is off, so nothing was sent."))
            return
        }
        await postResult(await runClinicExport(doorbell.endpoint))
    }

    // MARK: - Production effects

    private static func exportClinicProfile(endpoint: String) async -> String {
        await SchedulingManager.shared.waitForScheduledExportDependencies()
        let profiles = ExportProfileStore()
        let destinations = ProfileDestinationStore()
        guard let profile = profiles.profiles.first(where: {
            $0.target == .apiEndpoint && destinations.apiEndpoint(id: $0.apiEndpointID)?.endpointURLString == endpoint
        }) else {
            return String(localized: "Open Health.md and choose “Use clinic destination” in Clinic access first.")
        }
        guard profiles.profile(named: profile.name)?.id == profile.id else {
            return String(localized: "Another export profile is named “\(profile.name)”. Rename it, then try again.")
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates = [calendar.date(byAdding: .day, value: -1, to: today) ?? today, today]
        let outcome = await ExportIntentRunner.run(dates: dates, source: .manual, profileName: profile.name)
        if case .success = outcome {
            return String(localized: "Your latest data was sent to your clinic.")
        }
        return ExportIntentRunner.dialog(for: outcome)
    }

    private static func postLocalResult(_ message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Health.md"
        content.body = message
        let request = UNNotificationRequest(identifier: "clinic-sync-result", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Clinic control message

nonisolated struct ClinicSyncDoorbellMessage: Encodable, Equatable {
    let type = "healthmd.clinic_sync_doorbell"
    let version = 1
    let action: String
    let wakeService: String?
    let wakeId: String
    let wakeKey: String?

    static func enroll(wakeID: String, wakeKey: Data) -> Self {
        Self(action: "enroll", wakeService: ClinicSyncDoorbellManager.wakeService,
             wakeId: wakeID, wakeKey: base64url(wakeKey))
    }

    static func revoke(wakeID: String) -> Self {
        Self(action: "revoke", wakeService: nil, wakeId: wakeID, wakeKey: nil)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case type, version, action, wakeService, wakeId, wakeKey
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

protocol ClinicSyncControlSending: Sendable {
    @MainActor func send(_ body: Data, endpoint: URL) async throws
}

struct APIExportClinicControlSender: ClinicSyncControlSending {
    @MainActor func send(_ body: Data, endpoint: URL) async throws {
        try await APIExportClient().sendClinicControlMessage(body, messageType: ClinicSyncDoorbellManager.messageType,
                                                            endpoint: endpoint)
    }
}

// MARK: - Wake service

protocol ClinicSyncWakeServing: Sendable {
    func registerDelegatedSync(verificationHash: SHA256.Digest, existingWakeID: String?) async throws -> String
    func unregister(wakeID: String) async throws
}

extension DirectWakeWorkerClient: ClinicSyncWakeServing {}

// MARK: - Storage

nonisolated struct ClinicSyncDoorbell: Codable, Equatable {
    let wakeID: String
    let wakeKey: Data
    /// Canonical clinic endpoint the key was delivered to; any binding change revokes it.
    let endpoint: String
    /// APNs token registered with the wake service, for rotation.
    let deviceToken: String
}

nonisolated protocol ClinicSyncDoorbellStoring: Sendable {
    func load() -> ClinicSyncDoorbell?
    @discardableResult func save(_ doorbell: ClinicSyncDoorbell) -> Bool
    func clear()
}

nonisolated struct ClinicSyncDoorbellKeychain: ClinicSyncDoorbellStoring {
    private let service = "com.codybontecou.healthmd.clinic-sync-doorbell"
    private let account = "doorbell.v1"

    func load() -> ClinicSyncDoorbell? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let blob = item as? Data else { return nil }
        return try? JSONDecoder().decode(ClinicSyncDoorbell.self, from: blob)
    }

    @discardableResult
    func save(_ doorbell: ClinicSyncDoorbell) -> Bool {
        guard let blob = try? JSONEncoder().encode(doorbell) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = blob
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
