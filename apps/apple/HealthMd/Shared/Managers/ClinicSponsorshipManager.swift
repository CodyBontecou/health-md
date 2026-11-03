import Combine
import Foundation
import Security

struct ClinicSponsorshipStatus: Equatable {
    var configured = false
    var active = false
    var clinicName: String?
    var endpoint: String?
    var sharingAuthorized = false
    var storageUnavailable = false
    var enrollmentPending = false
}

@MainActor
final class ClinicSponsorshipManager: ObservableObject {
    static let shared = ClinicSponsorshipManager()
    @Published private(set) var status = ClinicSponsorshipStatus()
    @Published private(set) var destinationSelectionRequestID: UUID?
    private var session: ClinicSponsorshipSession?
    private var client: (any ClinicLicensingServing)?
    private var revision: UInt64 = 0
    private var restoreSession: (() throws -> ClinicSponsorshipSession)?
    private var refreshTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var disconnectPending = false

    init(configuration: ClinicLicensingConfiguration? = nil,
         keychain: (any KeychainStoring)? = nil,
         client: (any ClinicLicensingServing)? = nil,
         clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) {
        guard let configuration = configuration ?? Self.bundledConfiguration() else { return }
        self.client = client ?? ClinicLicensingClient(configuration: configuration)
        status.configured = true
        let storage = keychain ?? SystemKeychainStore(service: "com.codybontecou.healthmd.clinic-sponsorship",
            accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        restoreSession = {
            try ClinicSponsorshipSession(verifier: configuration.verifier,
                read: { try storage.readStringOrThrow(key: "session.v1") },
                write: { try storage.writeStringOrThrow(key: "session.v1", value: $0) }, clock: clock)
        }
        recoverStorage()
        publish()
        expiryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.publish()
            }
        }
    }

    deinit { expiryTask?.cancel() }

    private func recoverStorage() {
        if disconnectPending {
            do { try session?.disconnect(); disconnectPending = false }
            catch { return }
        }
        if session == nil { session = try? restoreSession?() }
    }

    private static func bundledConfiguration() -> ClinicLicensingConfiguration? {
        guard let values = Bundle.main.object(forInfoDictionaryKey: "ClinicLicensing") as? [String: String],
              let value = values["URL"], let url = URL(string: value), let issuer = values["Issuer"] else { return nil }
        var keys: [String: Data] = [:]
        if let raw = values["TrustedKeysJSON"], !raw.isEmpty {
            guard let data = raw.data(using: .utf8),
                  let encoded = try? JSONDecoder().decode([String: String].self, from: data),
                  (1...4).contains(encoded.count) else { return nil }
            for (id, value) in encoded {
                guard let key = Data(base64Encoded: value), !id.isEmpty else { return nil }
                keys[id] = key
            }
        } else {
            guard let keyID = values["KeyID"], let encoded = values["PublicKeyDER"],
                  let key = Data(base64Encoded: encoded) else { return nil }
            keys[keyID] = key
        }
        return try? ClinicLicensingConfiguration(baseURL: url, issuer: issuer,
            audience: "healthmd-clinic-access", trustedKeys: keys)
    }

    private func publish() {
        guard !disconnectPending else {
            status = ClinicSponsorshipStatus(configured: client != nil, storageUnavailable: true)
            return
        }
        do {
            let grant = try session?.grant()
            status = ClinicSponsorshipStatus(configured: client != nil, active: grant != nil,
                clinicName: session?.clinicName, endpoint: grant?.endpoint,
                sharingAuthorized: try grant.map { try session?.authorize(endpoint: $0.endpoint).isAllowed == true } ?? false,
                storageUnavailable: client != nil && session == nil,
                enrollmentPending: session?.pendingEnrollment != nil)
        } catch { status = ClinicSponsorshipStatus(configured: true, storageUnavailable: true) }
    }

    func enroll(code: String) async throws {
        recoverStorage()
        guard !disconnectPending, let session else { throw ClinicSponsorshipError.inactive }
        _ = try session.beginEnrollment(code: code)
        revision &+= 1
        publish()
        try await resumeEnrollment()
    }

    func resumeEnrollment() async throws {
        guard !disconnectPending, let session, let pending = session.pendingEnrollment, let client else { return }
        let operation = revision
        do {
            let reply = try await client.redeem(code: pending.invitationCode,
                installationID: session.installationID, enrollmentSecret: pending.enrollmentSecret)
            guard operation == revision else { throw CancellationError() }
            try session.accept(grantToken: reply.grant, refreshToken: pending.enrollmentSecret,
                clinicName: reply.clinicName, completingEnrollmentSecret: pending.enrollmentSecret)
            publish()
        } catch {
            if operation == revision, case ClinicLicensingError.inactive = error {
                try session.cancelEnrollment(secret: pending.enrollmentSecret)
                publish()
            }
            throw error
        }
    }

    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        recoverStorage()
        publish()
        guard !disconnectPending else { return }
        if session?.pendingEnrollment != nil { try? await resumeEnrollment(); return }
        guard let session, let token = session.refreshToken, let client else { return }
        let operation = revision
        do {
            let reply = try await client.refresh(token: token, installationID: session.installationID)
            guard operation == revision else { return }
            try session.accept(grantToken: reply.grant, refreshToken: nil, clinicName: reply.clinicName)
            publish()
        } catch {
            guard operation == revision else { return }
            if case ClinicLicensingError.inactive = error {
                revision &+= 1
                do { try session.disconnect() }
                catch { disconnectPending = true }
            }
            publish()
        }
    }

    func setSharingAuthorized(_ authorized: Bool) throws {
        guard let session else { throw ClinicSponsorshipError.inactive }
        try session.setSharingAuthorized(authorized)
        publish()
    }

    func setUploadAuthorization(_ value: String) throws {
        guard let session else { throw ClinicSponsorshipError.inactive }
        try session.setUploadAuthorization(value)
    }

    func uploadAuthorization(endpoint: String) -> String? {
        guard !disconnectPending else { return nil }
        return try? session?.uploadAuthorization(endpoint: endpoint)
    }

    func requestClinicDestination() throws {
        guard status.active, status.sharingAuthorized else { throw ClinicSponsorshipError.inactive }
        destinationSelectionRequestID = UUID()
    }

    func consumeDestinationRequest(_ id: UUID) {
        if destinationSelectionRequestID == id { destinationSelectionRequestID = nil }
    }

    func authorizeCached(endpoint: String) -> ClinicExportDecision {
        guard !disconnectPending else { return .blockedAccessExpired }
        do {
            let result = try session?.authorize(endpoint: endpoint) ?? .blockedAccessExpired
            publish()
            return result
        } catch { return .blockedAccessExpired }
    }

    func disconnect() async throws {
        guard let session else { return }
        let tokens = Set([session.refreshToken, session.pendingEnrollment?.enrollmentSecret].compactMap { $0 })
        let identity = session.installationID
        revision &+= 1
        do { try session.disconnect() }
        catch { disconnectPending = true; publish(); throw error }
        publish()
        for token in tokens { try? await client?.disconnect(token: token, installationID: identity) }
    }

    /// Call with the frozen endpoint; generic PurchaseManager access remains personal-only.
    func authorizeExport(endpoint: String) async -> Bool {
        await refresh()
        return authorizeCached(endpoint: endpoint).isAllowed
    }
}
