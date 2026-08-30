import Combine
import Foundation

/// Immutable request-scoped destination used by every batch in one API export.
/// The authorization value is intentionally never Codable or logged.
struct APIExportDestinationSnapshot: Equatable {
    let endpointURL: URL
    let authorizationHeaderValue: String?
    let displayName: String
    let redactedEndpointDescription: String
}

enum APIExportSettingsPersistenceError: LocalizedError, Equatable {
    case verificationFailed

    var errorDescription: String? {
        "Health.md could not verify the saved endpoint credential."
    }
}

/// User-configurable destination for direct iOS API exports.
@MainActor
final class APIExportSettings: ObservableObject {
    // Keep deallocation on the releasing thread. Avoid Swift 6.2+'s crashing
    // isolated-deinit executor hop (swiftlang/swift#85663), which aborted CI
    // test processes on older iOS runtimes when the last release happened off
    // the main actor. Matches the AdvancedExportSettings convention.
    nonisolated deinit {}
    static let endpointURLStorageKey = "apiExport.endpointURL"
    private static let bearerTokenKeychainKey = "apiExport.bearerToken"

    @Published var endpointURLString: String {
        didSet { userDefaults.set(endpointURLString, forKey: Self.endpointURLStorageKey) }
    }

    @Published var bearerToken: String {
        didSet {
            guard !isSynchronizingVerifiedCredential else { return }
            let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                keychain.remove(key: Self.bearerTokenKeychainKey)
            } else {
                keychain.writeString(key: Self.bearerTokenKeychainKey, value: bearerToken)
            }
        }
    }

    private let userDefaults: UserDefaults
    private let keychain: any KeychainStoring
    private var isSynchronizingVerifiedCredential = false

    init(
        userDefaults: UserDefaults = .standard,
        keychain: (any KeychainStoring)? = nil
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain ?? SystemKeychainStore()
        self.endpointURLString = userDefaults.string(forKey: Self.endpointURLStorageKey) ?? ""
        self.bearerToken = self.keychain.readString(key: Self.bearerTokenKeychainKey) ?? ""
    }

    func sharedSetupPersistedBearerToken() throws -> String {
        try keychain.readStringOrThrow(key: Self.bearerTokenKeychainKey) ?? ""
    }

    func replaceBearerTokenVerifiably(_ value: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try keychain.removeOrThrow(key: Self.bearerTokenKeychainKey)
        } else {
            try keychain.writeStringOrThrow(key: Self.bearerTokenKeychainKey, value: value)
        }
        guard try sharedSetupPersistedBearerToken() == (value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value) else {
            throw APIExportSettingsPersistenceError.verificationFailed
        }
        isSynchronizingVerifiedCredential = true
        defer { isSynchronizingVerifiedCredential = false }
        bearerToken = value
    }

    func replaceEndpointURLVerifiably(_ value: String) throws {
        endpointURLString = value
        guard (userDefaults.string(forKey: Self.endpointURLStorageKey) ?? "") == value else {
            throw APIExportSettingsPersistenceError.verificationFailed
        }
    }

    var endpointURL: URL? {
        let trimmed = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    var isConfigured: Bool {
        destinationSnapshot != nil
    }

    var destinationSnapshot: APIExportDestinationSnapshot? {
        guard let endpointURL else { return nil }
        let displayName = endpointURL.host.flatMap { $0.isEmpty ? nil : $0 }
            ?? endpointURL.absoluteString
        return APIExportDestinationSnapshot(
            endpointURL: endpointURL,
            authorizationHeaderValue: authorizationHeaderValue,
            displayName: displayName,
            redactedEndpointDescription: Self.redactedEndpointDescription(
                for: endpointURL.absoluteString
            )
        )
    }

    var displayName: String {
        guard let url = endpointURL else { return "Configure endpoint" }
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }

    var redactedEndpointDescription: String {
        Self.redactedEndpointDescription(for: endpointURLString)
    }

    /// A privacy-safe endpoint label for history and diagnostics. User info,
    /// query parameters, and fragments can contain credentials and are never
    /// copied into persisted display metadata.
    nonisolated static func redactedEndpointDescription(
        for rawValue: String,
        fallback: String = "No endpoint configured"
    ) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.isEmpty == false,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return fallback
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? components.host ?? fallback
    }

    var authorizationHeaderValue: String? {
        let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.localizedCaseInsensitiveContains("Bearer ") || trimmed.localizedCaseInsensitiveContains("Basic ") {
            return trimmed
        }
        return "Bearer \(trimmed)"
    }
}
