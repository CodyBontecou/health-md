import Combine
import Foundation

/// Per-record tolerant destination persistence. Unknown kinds and versions are retained verbatim
/// and stay visible to diagnostics, but can never be executed as a Drive destination.
@MainActor
final class GoogleDriveDestinationStore: ObservableObject {
    nonisolated deinit {}
    static let storageKey = "googleDrive.destinations.envelope"
    static let envelopeVersion = 1

    @Published private(set) var destinations: [GoogleDriveDestination] = []
    @Published private(set) var unknownRecordCount = 0

    private let userDefaults: UserDefaults
    private var opaqueRecords: [[String: Any]] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        reload()
    }

    func destination(id: UUID?) -> GoogleDriveDestination? {
        guard let id else { return nil }
        return destinations.first { $0.id == id }
    }

    func upsert(_ destination: GoogleDriveDestination) {
        guard destination.version == GoogleDriveDestination.currentVersion else { return }
        if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
            destinations[index] = destination
        } else {
            destinations.append(destination)
        }
        destinations.sort { $0.id.uuidString < $1.id.uuidString }
        persist()
    }

    func remove(id: UUID) {
        destinations.removeAll { $0.id == id }
        persist()
    }

    /// Refreshes records written by another application-scoped store instance (for example the
    /// profile coordinator). Drive execution calls this immediately before resolving authority so
    /// it never runs against a stale in-memory snapshot or falls back to another destination.
    func reload() {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [Any] else {
            destinations = []
            opaqueRecords = []
            unknownRecordCount = 0
            return
        }

        var known: [GoogleDriveDestination] = []
        var opaque: [[String: Any]] = []
        for value in records {
            guard let record = value as? [String: Any] else { continue }
            guard record["kind"] as? String == "google_drive",
                  let payload = record["payload"],
                  JSONSerialization.isValidJSONObject(payload),
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let destination = try? JSONDecoder().decode(GoogleDriveDestination.self, from: payloadData),
                  destination.version == GoogleDriveDestination.currentVersion,
                  known.contains(where: { $0.id == destination.id }) == false else {
                opaque.append(record)
                continue
            }
            known.append(destination)
        }
        destinations = known.sorted { $0.id.uuidString < $1.id.uuidString }
        opaqueRecords = opaque
        unknownRecordCount = opaque.count
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let known: [[String: Any]] = destinations.compactMap { destination in
            guard let data = try? encoder.encode(destination),
                  let payload = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return ["kind": "google_drive", "payload": payload]
        }
        let root: [String: Any] = [
            "version": Self.envelopeVersion,
            "records": known + opaqueRecords
        ]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
        unknownRecordCount = opaqueRecords.count
    }
}

@MainActor
struct GoogleDriveCredentialStore: Sendable {
    private let keychain: any KeychainStoring

    init(keychain: (any KeychainStoring)? = nil) {
        self.keychain = keychain ?? SystemKeychainStore()
    }

    func credential(referenceID: UUID) throws -> GoogleDriveTokenCredential? {
        guard let json = try keychain.readStringOrThrow(key: key(referenceID)),
              let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(GoogleDriveTokenCredential.self, from: data)
        } catch {
            throw GoogleDriveError(.reauthorizationRequired)
        }
    }

    func save(_ credential: GoogleDriveTokenCredential, referenceID: UUID) throws {
        guard credential.isDriveFileOnly else { throw GoogleDriveError(.permissionDenied) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(credential)
        guard let json = String(data: data, encoding: .utf8) else {
            throw GoogleDriveError(.reauthorizationRequired)
        }
        try keychain.writeStringOrThrow(key: key(referenceID), value: json)
        guard try self.credential(referenceID: referenceID) == credential else {
            throw GoogleDriveError(.reauthorizationRequired)
        }
    }

    func remove(referenceID: UUID) throws {
        try keychain.removeOrThrow(key: key(referenceID))
    }

    private func key(_ id: UUID) -> String {
        "googleDrive.oauth.\(id.uuidString.lowercased())"
    }
}

@MainActor
final class GoogleDriveConnectionManager: ObservableObject {
    nonisolated deinit {}

    @Published private(set) var readiness: GoogleDriveReadiness = .destinationMissing
    @Published private(set) var lastErrorID: GoogleDriveErrorID?

    let destinationStore: GoogleDriveDestinationStore
    private let configuration: GoogleDriveConfiguration?
    private let credentialStore: GoogleDriveCredentialStore
    private let tokenEndpoint: GoogleDriveTokenEndpoint
    private let api: any GoogleDriveAPIClientProtocol
    private let authorizer: any GoogleDriveWebAuthorizing
    private let now: @Sendable () -> Date

    init(
        configuration: GoogleDriveConfiguration? = .from(),
        destinationStore: GoogleDriveDestinationStore? = nil,
        credentialStore: GoogleDriveCredentialStore? = nil,
        tokenEndpoint: GoogleDriveTokenEndpoint = GoogleDriveTokenEndpoint(),
        api: any GoogleDriveAPIClientProtocol = GoogleDriveAPIClient(),
        authorizer: (any GoogleDriveWebAuthorizing)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.destinationStore = destinationStore ?? GoogleDriveDestinationStore()
        self.credentialStore = credentialStore ?? GoogleDriveCredentialStore()
        self.tokenEndpoint = tokenEndpoint
        self.api = api
        self.authorizer = authorizer ?? ASWebGoogleDriveAuthorizer()
        self.now = now
        refreshReadiness()
    }

    func refreshReadiness(destinationID: UUID? = nil) {
        guard configuration != nil else {
            readiness = .configurationMissing
            lastErrorID = .configurationMissing
            return
        }
        let destination = destinationID.flatMap(destinationStore.destination(id:))
            ?? destinationStore.destinations.first
        guard let destination else {
            readiness = .destinationMissing
            lastErrorID = .folderUnavailable
            return
        }
        do {
            guard try credentialStore.credential(referenceID: destination.credentialReferenceID) != nil else {
                readiness = .reauthorizationRequired
                lastErrorID = .reauthorizationRequired
                return
            }
            readiness = destination.canAddChildren ? .ready : .folderUnavailable
            lastErrorID = readiness.errorID
        } catch {
            readiness = .reauthorizationRequired
            lastErrorID = .reauthorizationRequired
        }
    }

    /// Foreground connect/reconnect. ASWebAuthenticationSession performs authorization-code PKCE
    /// and the mobile Picker. The destination is saved only after about.get and exact folder
    /// capability validation succeed.
    func connect(replacing destinationID: UUID? = nil) async throws -> GoogleDriveDestination {
        guard let configuration else {
            readiness = .configurationMissing
            throw GoogleDriveError(.configurationMissing)
        }
        let authRequest = try GoogleDriveAuthorizationRequest.make(configuration: configuration)
        let callbackURL = try await authorizer.authorize(authRequest)
        let callback = try GoogleDriveAuthorizationCallback.parse(
            url: callbackURL,
            expectedState: authRequest.state
        )
        let credential = try await tokenEndpoint.exchange(
            code: callback.code,
            pkceVerifier: authRequest.pkce.verifier,
            configuration: configuration
        )
        let permissionID = try await api.about(accessToken: credential.accessToken)
        let folder = try await api.metadata(
            id: callback.selection.folderID,
            resourceKey: callback.selection.resourceKey,
            accessToken: credential.accessToken
        )
        guard folder.mimeType == GoogleDriveFileMetadata.folderMIMEType,
              !folder.trashed,
              folder.canAddChildren == true,
              callback.selection.sharedDriveID == nil || callback.selection.sharedDriveID == folder.driveID else {
            throw GoogleDriveError(.folderUnavailable)
        }

        destinationStore.reload()
        let old = destinationID.flatMap(destinationStore.destination(id:))
        // Reauthorization may refresh only the exact existing account/folder authority. Choosing
        // another account or folder creates a new binding; the editor applies that new UUID only
        // to the profile being edited when Save is tapped, leaving every other profile untouched.
        let isExactReauthorization = Self.isExactReauthorization(
            old,
            permissionID: permissionID,
            folder: folder
        )
        let credentialReferenceID = isExactReauthorization ? old!.credentialReferenceID : UUID()
        let destination = GoogleDriveDestination(
            id: isExactReauthorization ? old!.id : UUID(),
            credentialReferenceID: credentialReferenceID,
            accountPermissionID: permissionID,
            folderID: folder.id,
            sharedDriveID: folder.driveID,
            resourceKey: callback.selection.resourceKey ?? folder.resourceKey,
            accountLabel: nil,
            folderLabel: callback.selection.folderLabel ?? folder.name,
            canAddChildren: true,
            lastValidatedAt: now()
        )
        try credentialStore.save(credential, referenceID: credentialReferenceID)
        destinationStore.upsert(destination)
        readiness = .ready
        lastErrorID = nil
        return destination
    }

    static func isExactReauthorization(
        _ existing: GoogleDriveDestination?,
        permissionID: String,
        folder: GoogleDriveFileMetadata
    ) -> Bool {
        guard let existing else { return false }
        return existing.accountPermissionID == permissionID && existing.folderID == folder.id &&
            existing.sharedDriveID == folder.driveID
    }

    /// Silent refresh used by foreground and scheduled execution. It never opens UI or changes
    /// accounts; a failed refresh is represented as reauthorization_required.
    func accessToken(destination: GoogleDriveDestination) async throws -> String {
        guard let configuration else { throw GoogleDriveError(.configurationMissing) }
        guard var credential = try credentialStore.credential(referenceID: destination.credentialReferenceID),
              credential.isDriveFileOnly else {
            readiness = .reauthorizationRequired
            throw GoogleDriveError(.reauthorizationRequired)
        }
        if credential.expiresAt <= now() {
            do {
                credential = try await tokenEndpoint.refresh(
                    refreshToken: credential.refreshToken,
                    configuration: configuration
                )
                try credentialStore.save(credential, referenceID: destination.credentialReferenceID)
            } catch let error as GoogleDriveError {
                lastErrorID = error.id
                if error.id == .reauthorizationRequired {
                    readiness = .reauthorizationRequired
                }
                throw error
            } catch {
                lastErrorID = .ambiguousCommit
                throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
            }
        }
        do {
            let folder = try await api.validateFolder(destination, accessToken: credential.accessToken)
            guard folder.canAddChildren == true else { throw GoogleDriveError(.folderUnavailable) }
            readiness = .ready
            lastErrorID = nil
            return credential.accessToken
        } catch let error as GoogleDriveError {
            lastErrorID = error.id
            switch error.id {
            case .reauthorizationRequired, .accountMismatch:
                readiness = .reauthorizationRequired
            case .folderUnavailable, .permissionDenied:
                readiness = .folderUnavailable
            case .configurationMissing:
                readiness = .configurationMissing
            case .remoteConflict, .ambiguousCommit, .quotaExceeded, .rateLimited,
                 .checksumMismatch, .partialCompletion:
                break
            }
            throw error
        }
    }

    /// Removes local authority regardless of revocation network outcome. Remote files are untouched.
    func disconnect(destinationID: UUID) async throws {
        destinationStore.reload()
        guard let destination = destinationStore.destination(id: destinationID) else { return }
        // Refuse to destroy the only credential capable of reconciling an ambiguous/partial
        // operation. Completed acknowledged journals and their protected spools are removed.
        let journalStore = try GoogleDriveJournalStore()
        try await journalStore.cleanupForDisconnect(destinationID: destinationID)
        if let credential = try? credentialStore.credential(referenceID: destination.credentialReferenceID) {
            try? await tokenEndpoint.revoke(token: credential.refreshToken)
        }
        try credentialStore.remove(referenceID: destination.credentialReferenceID)
        destinationStore.remove(id: destinationID)
        try GoogleDriveManagedObjectStore().removeAll(destinationID: destinationID)
        refreshReadiness()
    }
}
