import Foundation
import OSLog
import Security
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Bridges the iOS/macOS app to the Health.md notifications worker so
/// the server can drive scheduled exports via silent APNs pushes.
///
/// Lifecycle:
///   1. App enables a schedule → `registerForRemoteNotificationsIfNeeded()`
///      asks for notification permission and asks the system for a token.
///   2. App delegate forwards `didRegisterForRemoteNotificationsWithDeviceToken`
///      to `submitDeviceToken(_:)`, which POSTs `/devices/register`.
///   3. `SchedulingManager.schedule` didSet calls `syncSchedule(_:)` to upsert
///      `/schedules/upsert` (server computes next_fire_at). Disabling the
///      schedule sends an upsert with `isEnabled: false` so the server
///      drops the row.
final class PushRegistrationManager: @unchecked Sendable {
    static let shared = PushRegistrationManager()

    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "PushRegistration")
    private let remoteClient: any RemoteScheduleClient

    /// Keychain service identifier (matches PurchaseManager's so all
    /// HealthMd-related items live under the same service).
    private static let keychainService = "com.codybontecou.obsidianhealth"
    private static let userIdKeychainAccount = "pushRegistrationUserId"

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://healthmd-receipt-verifier.costream.workers.dev")!,
        remoteClient: (any RemoteScheduleClient)? = nil
    ) {
        self.remoteClient = remoteClient ?? URLSessionRemoteScheduleClient(baseURL: baseURL, session: session)
    }

    // MARK: - Identity

    /// Stable per-install user ID. Generated once and persisted to Keychain
    /// so it survives app deletion (Keychain entries persist across reinstalls
    /// on iOS by default with kSecAttrAccessibleAfterFirstUnlock).
    var userId: String {
        if let existing = readKeychainString(account: Self.userIdKeychainAccount) {
            return existing
        }
        let fresh = UUID().uuidString
        writeKeychainString(account: Self.userIdKeychainAccount, value: fresh)
        return fresh
    }

    private var platformString: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "com.codybontecou.obsidianhealth"
    }

    // MARK: - Registration

    /// Request notification authorization (if not yet granted) and ask the
    /// system for an APNs device token. Safe to call repeatedly.
    @MainActor
    func registerForRemoteNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                logger.error("Notification authorization request failed: \(error.localizedDescription)")
            }
        case .denied:
            logger.info("Notifications denied — skipping APNs registration")
            return
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Called by the app delegate from
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func submitDeviceToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        logger.info("APNs token captured: \(hex.prefix(8), privacy: .public)…")
        Task { await self.postRegisterDevice(apnsToken: hex) }
    }

    private func postRegisterDevice(apnsToken: String) async {
        let body = RemoteScheduleDeviceRegistrationPayload(
            userId: userId,
            platform: platformString,
            apnsToken: apnsToken,
            bundleId: bundleId
        )
        await postDeviceRegistration(body)
    }

    // MARK: - Schedule sync

    /// Upsert the schedule on the server. Sends `isEnabled: false` to drop
    /// the row when scheduling is turned off.
    func syncSchedule(_ schedule: ExportSchedule) {
        let timezone = TimeZone.current.identifier
        Task { await self.postUpsertSchedule(schedule, timezone: timezone) }
    }

    private func postUpsertSchedule(_ schedule: ExportSchedule, timezone: String) async {
        let timeZone = TimeZone(identifier: timezone) ?? .current
        let body = RemoteScheduleUpsertPayload(
            userId: userId,
            timezone: timezone,
            schedule: RemoteSchedulePayload(schedule: schedule.automationSchedule(timeZone: timeZone))
        )
        await postScheduleUpsert(body)
    }

    // MARK: - Networking

    private func postDeviceRegistration(_ body: RemoteScheduleDeviceRegistrationPayload) async {
        await post(label: "register", path: RemoteScheduleWorkerContract.deviceRegistrationPath) {
            try await remoteClient.registerDevice(body)
        }
    }

    private func postScheduleUpsert(_ body: RemoteScheduleUpsertPayload) async {
        await post(label: "schedule", path: RemoteScheduleWorkerContract.scheduleUpsertPath) {
            try await remoteClient.upsertSchedule(body)
        }
    }

    private func post(label: String, path: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            logger.info("POST \(path, privacy: .public) ok")
        } catch RemoteScheduleClientError.unsuccessfulStatusCode(let statusCode) {
            logger.error("POST \(path, privacy: .public) failed: HTTP \(statusCode)")
        } catch {
            logger.error("POST \(path, privacy: .public) \(label, privacy: .public) error: \(error.localizedDescription)")
        }
    }

    // MARK: - Keychain string storage (UUID)

    private func readKeychainString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func writeKeychainString(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
