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
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        standardizedPath: String,
        bookmarkData: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.standardizedPath = standardizedPath
        self.bookmarkData = bookmarkData
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

    private let userDefaults: UserDefaults
    private let keychain: any KeychainStoring

    private enum Key {
        static let vaults = "exportProfileDestinations.vaults"
        static let apiEndpoints = "exportProfileDestinations.apiEndpoints"
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
    }

    // MARK: - Lookup

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

    // MARK: - Vault CRUD

    /// Adds a vault destination, or returns the existing destination that
    /// already points at the same standardized path. Sharing one destination
    /// row across profiles that use the same folder keeps re-selection
    /// idempotent.
    @discardableResult
    func upsertVault(
        name: String,
        standardizedPath: String,
        bookmarkData: Data
    ) -> SavedVaultDestination {
        if let existing = vault(standardizedPath: standardizedPath) {
            guard existing.bookmarkData != bookmarkData || existing.name != name else {
                return existing
            }
            var updated = existing
            updated.name = name
            updated.bookmarkData = bookmarkData
            if let index = vaults.firstIndex(where: { $0.id == existing.id }) {
                vaults[index] = updated
                persistVaults()
            }
            return updated
        }

        let destination = SavedVaultDestination(
            name: name,
            standardizedPath: standardizedPath,
            bookmarkData: bookmarkData
        )
        vaults.append(destination)
        persistVaults()
        return destination
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
}
