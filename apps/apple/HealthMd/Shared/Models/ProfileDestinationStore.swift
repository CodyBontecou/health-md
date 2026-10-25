import Foundation
import Combine

/// A saved local-folder destination (security-scoped bookmark) that an export
/// profile can bind to. Mirrors the fields `VaultManager` persists for its
/// single legacy destination so a profile-bound vault and the legacy vault
/// remain interchangeable.
struct SavedVaultDestination: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var standardizedPath: String
    var bookmarkData: Data
    /// Persistent identity evidence (volume UUID + file identifier) captured
    /// through the bookmark round-trip when the volume reports persistent IDs.
    /// Nil for legacy rows saved before identity capture and for identity-less
    /// file providers; adoption re-captures and heals it.
    var identity: VaultFolderIdentity?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        standardizedPath: String,
        bookmarkData: Data,
        identity: VaultFolderIdentity? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.standardizedPath = standardizedPath
        self.bookmarkData = bookmarkData
        self.identity = identity
        self.createdAt = createdAt
    }
}

/// A saved API endpoint destination. The bearer token is intentionally not
/// part of the Codable payload; it lives in the Keychain keyed by the
/// destination id.
struct SavedAPIEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var endpointURLString: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        endpointURLString: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.endpointURLString = endpointURLString
        self.createdAt = createdAt
    }
}

/// A saved Agent Data gateway destination. Gateways carry no credential in
/// v1, so the Codable payload is the whole configuration; the endpoint URL
/// is validated and displayed through `AgentDataGatewayEndpoint`'s
/// health-free helpers.
struct SavedAgentDataGateway: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var endpointURLString: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        endpointURLString: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.endpointURLString = endpointURLString
        self.createdAt = createdAt
    }
}

/// Multi-destination persistence for export profiles: any number of folder
/// bookmarks and API endpoints, each referenced by stable UUID from an
/// `ExportProfile`. The legacy single-vault/single-endpoint state remains
/// untouched; this store is additive.
///
/// Use from the main thread, matching `ExportProfileStore`.
final class ProfileDestinationStore: ObservableObject {

    /// `nonisolated deinit` keeps teardown off the MainActor back-deployed
    /// dealloc path, which trips a libmalloc
    /// POINTER_BEING_FREED_WAS_NOT_ALLOCATED abort on the iOS 26.2 runtime
    /// when nested ObservableObject stores are released (seen on CI
    /// simulators; fixed in newer runtimes). All state is already torn down
    /// by the time deinit runs, so no isolation is required.
    nonisolated deinit {}
    @Published private(set) var vaults: [SavedVaultDestination]
    @Published private(set) var apiEndpoints: [SavedAPIEndpoint]
    @Published private(set) var agentDataGateways: [SavedAgentDataGateway]
    /// Profile → gateway binding (profile id → gateway row id). The gateway
    /// binding deliberately lives in this additive native store rather than
    /// the `ExportProfile` Codable payload: the shared-setup apple profile
    /// field-coverage ledger in `packages/contracts` enumerates ExportProfile's
    /// stored fields, and the Agent Data gateway does not participate in
    /// shared setup bundles, so the binding is native-only state.
    @Published private(set) var agentDataGatewayBindings: [UUID: UUID]

    private let userDefaults: UserDefaults
    private let keychain: any KeychainStoring

    private enum Key {
        static let vaults = "exportProfileDestinations.vaults"
        static let apiEndpoints = "exportProfileDestinations.apiEndpoints"
        static let agentDataGateways = "exportProfileDestinations.agentDataGateways"
        static let agentDataGatewayBindings = "exportProfileDestinations.agentDataGatewayBindings"
    }

    private static func apiTokenKey(for id: UUID) -> String {
        "exportProfileDestinations.apiToken.\(id.uuidString)"
    }

    init(
        userDefaults: UserDefaults = .standard,
        keychain: (any KeychainStoring)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain ?? SystemKeychainStore()
        let now = now

        if let data = userDefaults.data(forKey: Key.vaults),
           let decoded = try? JSONDecoder().decode([SavedVaultDestination].self, from: data) {
            vaults = decoded
        } else {
            vaults = []
        }

        if let data = userDefaults.data(forKey: Key.apiEndpoints),
           let decoded = try? JSONDecoder().decode([SavedAPIEndpoint].self, from: data) {
            apiEndpoints = decoded
        } else {
            apiEndpoints = []
        }

        if let data = userDefaults.data(forKey: Key.agentDataGateways),
           let decoded = try? JSONDecoder().decode([SavedAgentDataGateway].self, from: data) {
            agentDataGateways = decoded
        } else {
            agentDataGateways = []
        }

        if let data = userDefaults.data(forKey: Key.agentDataGatewayBindings),
           let decoded = try? JSONDecoder().decode([UUID: UUID].self, from: data) {
            agentDataGatewayBindings = decoded
        } else {
            agentDataGatewayBindings = [:]
        }
    }

    // MARK: - Lookup

    /// Other runtime coordinators may refresh a profile destination through a
    /// separate store instance. Scheduled execution calls this before resolving
    /// provenance so history uses the destination actually adopted for the run.
    func reloadPersistedDestinations() {
        if let data = userDefaults.data(forKey: Key.vaults),
           let decoded = try? JSONDecoder().decode([SavedVaultDestination].self, from: data),
           decoded != vaults {
            vaults = decoded
        }

        if let data = userDefaults.data(forKey: Key.apiEndpoints),
           let decoded = try? JSONDecoder().decode([SavedAPIEndpoint].self, from: data),
           decoded != apiEndpoints {
            apiEndpoints = decoded
        }

        if let data = userDefaults.data(forKey: Key.agentDataGateways),
           let decoded = try? JSONDecoder().decode([SavedAgentDataGateway].self, from: data),
           decoded != agentDataGateways {
            agentDataGateways = decoded
        }

        if let data = userDefaults.data(forKey: Key.agentDataGatewayBindings),
           let decoded = try? JSONDecoder().decode([UUID: UUID].self, from: data),
           decoded != agentDataGatewayBindings {
            agentDataGatewayBindings = decoded
        }
    }

    func vault(id: UUID?) -> SavedVaultDestination? {
        guard let id else { return nil }
        return vaults.first { $0.id == id }
    }

    func vault(standardizedPath: String) -> SavedVaultDestination? {
        vaults.first { $0.standardizedPath == standardizedPath }
    }

    func apiEndpoint(id: UUID?) -> SavedAPIEndpoint? {
        guard let id else { return nil }
        return apiEndpoints.first { $0.id == id }
    }

    func agentDataGateway(id: UUID?) -> SavedAgentDataGateway? {
        guard let id else { return nil }
        return agentDataGateways.first { $0.id == id }
    }

    /// The gateway row a profile is bound to, or nil when unbound.
    func agentDataGatewayBinding(profileID: UUID?) -> UUID? {
        guard let profileID else { return nil }
        return agentDataGatewayBindings[profileID]
    }

    // MARK: - Vault CRUD

    /// Adds a vault destination, or returns the existing destination that
    /// already points at the same standardized path. Sharing one destination
    /// row across profiles that use the same folder keeps re-selection
    /// idempotent.
    @discardableResult
    func upsertVault(
        name: String,
        standardizedPath: String,
        bookmarkData: Data,
        identity: VaultFolderIdentity? = nil
    ) -> SavedVaultDestination {
        if let existing = vault(standardizedPath: standardizedPath) {
            guard existing.bookmarkData != bookmarkData || existing.name != name || existing.identity != identity else {
                return existing
            }
            var updated = existing
            updated.name = name
            updated.bookmarkData = bookmarkData
            updated.identity = identity
            if let index = vaults.firstIndex(where: { $0.id == existing.id }) {
                vaults[index] = updated
                persistVaults()
            }
            return updated
        }

        let destination = SavedVaultDestination(
            name: name,
            standardizedPath: standardizedPath,
            bookmarkData: bookmarkData,
            identity: identity
        )
        vaults.append(destination)
        persistVaults()
        return destination
    }

    /// Persists refreshed destination metadata for a row in place, without
    /// changing its id or any profile binding. Used after profile adoption:
    /// rows saved without identity evidence (legacy rows, pre-identity-capture
    /// app versions) heal their evidence through adoption's bookmark round-trip,
    /// and moved or stale bookmarks refresh the row's bookmark, standardized
    /// path, and display name so the next adoption starts from the verified
    /// state instead of re-resolving a stale bookmark every launch (issue #143).
    func updateVault(
        id: UUID,
        name: String,
        standardizedPath: String,
        bookmarkData: Data,
        identity: VaultFolderIdentity?
    ) {
        guard let index = vaults.firstIndex(where: { $0.id == id }) else { return }
        var updated = vaults[index]
        updated.name = name
        updated.standardizedPath = standardizedPath
        updated.bookmarkData = bookmarkData
        updated.identity = identity
        guard updated != vaults[index] else { return }
        vaults[index] = updated
        persistVaults()
    }

    /// Removes a vault destination. Profiles still referencing its id resolve
    /// to nil at runtime, which callers treat as "unbound" rather than an
    /// error. Referencing profiles can be rebound explicitly by the caller.
    func deleteVault(id: UUID) {
        vaults.removeAll { $0.id == id }
        persistVaults()
    }

    // MARK: - API endpoint CRUD

    @discardableResult
    func upsertAPIEndpoint(
        name: String,
        endpointURLString: String,
        bearerToken: String?
    ) -> SavedAPIEndpoint {
        let trimmedURL = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = apiEndpoints.first(where: {
            $0.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedURL) == .orderedSame
        }) {
            if existing.endpointURLString != trimmedURL || existing.name != name {
                var updated = existing
                updated.name = name
                updated.endpointURLString = trimmedURL
                if let index = apiEndpoints.firstIndex(where: { $0.id == existing.id }) {
                    apiEndpoints[index] = updated
                    persistAPIEndpoints()
                }
            }
            if let bearerToken {
                setToken(bearerToken, for: existing.id)
            }
            return existing
        }

        let endpoint = SavedAPIEndpoint(name: name, endpointURLString: trimmedURL)
        apiEndpoints.append(endpoint)
        if let bearerToken {
            setToken(bearerToken, for: endpoint.id)
        }
        persistAPIEndpoints()
        return endpoint
    }

    func token(for endpointID: UUID) -> String? {
        keychain.readString(key: Self.apiTokenKey(for: endpointID))
    }

    func setToken(_ token: String, for endpointID: UUID) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychain.remove(key: Self.apiTokenKey(for: endpointID))
        } else {
            keychain.writeString(key: Self.apiTokenKey(for: endpointID), value: trimmed)
        }
    }

    /// Removes an endpoint and its Keychain token. Profiles still referencing
    /// its id resolve to nil at runtime.
    func deleteAPIEndpoint(id: UUID) {
        apiEndpoints.removeAll { $0.id == id }
        keychain.remove(key: Self.apiTokenKey(for: id))
        persistAPIEndpoints()
    }

    // MARK: - Agent Data gateway CRUD

    /// Adds or updates a gateway destination keyed by the normalized endpoint
    /// URL. Re-entering an already-saved URL reuses its gateway row. Gateways
    /// carry no credential in v1, so there is no Keychain slot to maintain.
    @discardableResult
    func upsertAgentDataGateway(
        name: String,
        endpointURLString: String
    ) -> SavedAgentDataGateway {
        let trimmedURL = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = agentDataGateways.first(where: {
            $0.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedURL) == .orderedSame
        }) {
            if existing.endpointURLString != trimmedURL || existing.name != name {
                var updated = existing
                updated.name = name
                updated.endpointURLString = trimmedURL
                if let index = agentDataGateways.firstIndex(where: { $0.id == existing.id }) {
                    agentDataGateways[index] = updated
                    persistAgentDataGateways()
                }
            }
            return existing
        }

        let gateway = SavedAgentDataGateway(name: name, endpointURLString: trimmedURL)
        agentDataGateways.append(gateway)
        persistAgentDataGateways()
        return gateway
    }

    /// Removes a gateway destination and every profile binding that
    /// referenced it. Profiles whose binding is removed resolve to unbound
    /// at runtime.
    func deleteAgentDataGateway(id: UUID) {
        agentDataGateways.removeAll { $0.id == id }
        let references = agentDataGatewayBindings.filter { $0.value == id }.map(\.key)
        for profileID in references {
            agentDataGatewayBindings.removeValue(forKey: profileID)
        }
        persistAgentDataGateways()
    }

    /// Binds (or unbinds, with nil) a profile to a gateway row. Bindings for
    /// unknown profiles are still persisted: like folder/endpoint bindings,
    /// rows referencing profiles that no longer exist resolve to unbound at
    /// runtime and never error.
    func setAgentDataGatewayBinding(profileID: UUID, gatewayID: UUID?) {
        if let gatewayID {
            guard agentDataGatewayBindings[profileID] != gatewayID else { return }
            agentDataGatewayBindings[profileID] = gatewayID
        } else {
            guard agentDataGatewayBindings[profileID] != nil else { return }
            agentDataGatewayBindings.removeValue(forKey: profileID)
        }
        persistAgentDataGateways()
    }

    // MARK: - Persistence

    private func persistVaults() {
        if let encoded = try? JSONEncoder().encode(vaults) {
            userDefaults.set(encoded, forKey: Key.vaults)
        }
    }

    private func persistAPIEndpoints() {
        if let encoded = try? JSONEncoder().encode(apiEndpoints) {
            userDefaults.set(encoded, forKey: Key.apiEndpoints)
        }
    }

    private func persistAgentDataGateways() {
        if let encoded = try? JSONEncoder().encode(agentDataGateways) {
            userDefaults.set(encoded, forKey: Key.agentDataGateways)
        }
        if let encoded = try? JSONEncoder().encode(agentDataGatewayBindings) {
            userDefaults.set(encoded, forKey: Key.agentDataGatewayBindings)
        }
    }
}
