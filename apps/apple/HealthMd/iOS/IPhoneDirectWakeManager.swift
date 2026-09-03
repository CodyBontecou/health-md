import Combine
import CryptoKit
import Foundation
import HealthMdConnectionCore
import SwiftUI
import UserNotifications

/// RFC-0005 P2 wake enrollment for the paired computer.
///
/// Enabling the setting requests notification authorization, generates a fresh 256-bit wake key
/// used only for the worker HMAC, registers `wakeID`/verification hash/token with the consumer
/// notifications worker, and persists the material in the Keychain. The direct service forwards
/// the enrollment to the CLI whenever both sides advertised wake support. Every failure keeps
/// the feature honestly unavailable; nothing is persisted or advertised before a successful
/// worker registration, so the wait-only P1 window remains the deployed behavior until the
/// worker exists.
@MainActor
protocol IPhoneDirectWakeManaging: AnyObject {
    nonisolated var advertisesWake: Bool { get }
    nonisolated func currentEnrollment() -> DirectWakeEnrollment?
    func forgetAll() async
}

@MainActor
final class IPhoneDirectWakeManager: ObservableObject, IPhoneDirectWakeManaging {
    nonisolated static let notificationCategory = "HEALTHMD_DIRECT_WAKE"
    nonisolated static let enabledKey = "directCLIWakeEnabled"

    enum EnrollmentState: Equatable {
        case disabled
        case enrolling
        case enrolled
        case unavailable(reason: String)
    }

    @Published private(set) var state: EnrollmentState = .disabled

    private nonisolated(unsafe) let defaults: UserDefaults
    private nonisolated(unsafe) let keychain: any DirectWakeCredentialStoring
    private let worker: any DirectWakeWorkerRegistering
    private let pushRegistration: PushRegistrationManager
    private let requestNotificationAuthorization: @MainActor () async -> Bool

    init(
        defaults: UserDefaults = .standard,
        keychain: any DirectWakeCredentialStoring = DirectWakeKeychain(),
        worker: (any DirectWakeWorkerRegistering)? = nil,
        pushRegistration: PushRegistrationManager = .shared,
        requestNotificationAuthorization: (@MainActor () async -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.pushRegistration = pushRegistration
        self.worker = worker ?? DirectWakeWorkerClient(pushRegistration: pushRegistration)
        self.requestNotificationAuthorization = requestNotificationAuthorization ?? {
            let center = UNUserNotificationCenter.current()
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        if defaults.bool(forKey: Self.enabledKey), let credential = keychain.load() {
            state = .enrolled
        }
    }

    var isEnrolled: Bool { keychain.load() != nil }

    /// The enrollment to forward on the next direct connection, or `nil` to stay wait-only.
    /// Reads only thread-safe Keychain and defaults state so the direct service can call it
    /// from its connection task.
    nonisolated func currentEnrollment() -> DirectWakeEnrollment? {
        guard defaults.bool(forKey: Self.enabledKey) else { return nil }
        guard let credential = keychain.load() else { return nil }
        let enrollment = DirectWakeEnrollment(
            wakeID: credential.wakeID,
            wakeKey: credential.wakeKey.base64EncodedString()
        )
        return enrollment.isValid ? enrollment : nil
    }

    /// Whether the direct hello should advertise wake support at all.
    nonisolated var advertisesWake: Bool {
        defaults.bool(forKey: Self.enabledKey) && keychain.load() != nil
    }

    func enable() async {
        guard state != .enrolling else { return }
        state = .enrolling

        // The tap is the consent surface: without notification authorization there is no
        // wake to deliver, so the setting stays honestly unavailable.
        guard await requestNotificationAuthorization() else {
            state = .unavailable(reason: "Notification permission was not granted.")
            return
        }
        await pushRegistration.registerForRemoteNotificationsIfNeeded()

        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess, key.count == 32 else {
            state = .unavailable(reason: "The wake key could not be generated.")
            return
        }

        do {
            let wakeID = try await worker.register(verificationHash: SHA256.hash(data: key))
            keychain.save(DirectWakeCredential(wakeID: wakeID, wakeKey: key))
            defaults.set(true, forKey: Self.enabledKey)
            state = .enrolled
        } catch {
            state = .unavailable(
                reason: "The wake service is not available yet. The CLI keeps waiting without a notification."
            )
        }
    }

    func disable() async {
        if let credential = keychain.load() {
            try? await worker.unregister(wakeID: credential.wakeID)
        }
        keychain.clear()
        defaults.set(false, forKey: Self.enabledKey)
        state = .disabled
    }

    /// Unpairing removes the wake material with the pairing; the worker row goes with it.
    func forgetAll() async {
        await disable()
    }
}

struct DirectWakeCredential: Equatable {
    let wakeID: String
    let wakeKey: Data
}

protocol DirectWakeCredentialStoring: Sendable {
    func load() -> DirectWakeCredential?
    func save(_ credential: DirectWakeCredential)
    func clear()
}

/// Keychain-backed wake credential storage. The raw key never leaves the device except inside
/// the authenticated direct channel enrollment.
struct DirectWakeKeychain: DirectWakeCredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.codybontecou.obsidianhealth.direct-cli-ios-trust",
        account: String = "wake-state-v1"
    ) {
        self.service = service
        self.account = account
    }

    func load() -> DirectWakeCredential? {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let blob = item as? Data,
              let payload = try? JSONDecoder().decode(
                  DirectWakeCredentialPayload.self, from: blob
              ) else { return nil }
        return DirectWakeCredential(wakeID: payload.wakeID, wakeKey: payload.wakeKey)
    }

    func save(_ credential: DirectWakeCredential) {
        let payload = DirectWakeCredentialPayload(
            wakeID: credential.wakeID, wakeKey: credential.wakeKey
        )
        guard let blob = try? JSONEncoder().encode(payload) else { return }
        var query = Self.baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = blob
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() {
        let query = Self.baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

private struct DirectWakeCredentialPayload: Codable {
    let wakeID: String
    let wakeKey: Data
}

protocol DirectWakeWorkerRegistering: Sendable {
    func register(verificationHash: SHA256.Digest) async throws -> String
    func unregister(wakeID: String) async throws
}

/// Client for the consumer notifications worker wake endpoints
/// ([RFC-0005 worker spec](https://healthmd.dev)). No health data, dates, metric identity, or
/// request contents ever appear in a request.
struct DirectWakeWorkerClient: DirectWakeWorkerRegistering {
    private let baseURL: URL
    private let pushRegistration: PushRegistrationManager
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://healthmd-receipt-verifier.costream.workers.dev")!,
        pushRegistration: PushRegistrationManager,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.pushRegistration = pushRegistration
        self.session = session
    }

    func register(verificationHash: SHA256.Digest) async throws -> String {
        struct Payload: Encodable {
            let userId: String
            let deviceToken: String
            let wakeKeyVerificationHash: String
        }
        struct Response: Decodable {
            let wakeId: String
        }
        guard let deviceToken = pushRegistration.lastDeviceTokenHex else {
            throw DirectWakeWorkerError.missingDeviceToken
        }
        let body = Payload(
            userId: pushRegistration.userId,
            deviceToken: deviceToken,
            wakeKeyVerificationHash: Data(verificationHash).map { String(format: "%02x", $0) }.joined()
        )
        let data = try await post(path: "/wake/register", body: body)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard (1...128).contains(response.wakeId.utf8.count) else {
            throw DirectWakeWorkerError.invalidResponse
        }
        return response.wakeId
    }

    func unregister(wakeID: String) async throws {
        struct Payload: Encodable {
            let userId: String
            let wakeId: String
        }
        let body = Payload(userId: pushRegistration.userId, wakeId: wakeID)
        _ = try await post(path: "/wake/register", body: body, method: "DELETE")
    }

    private func post<B: Encodable>(path: String, body: B, method: String = "POST") async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DirectWakeWorkerError.unexpectedStatus
        }
        return data
    }
}

enum DirectWakeWorkerError: Error {
    case missingDeviceToken
    case invalidResponse
    case unexpectedStatus
}
