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

/// User-configurable destination for direct iOS API exports.
@MainActor
final class APIExportSettings: ObservableObject {
    static let endpointURLStorageKey = "apiExport.endpointURL"
    private static let bearerTokenKeychainKey = "apiExport.bearerToken"

    @Published var endpointURLString: String {
        didSet { userDefaults.set(endpointURLString, forKey: Self.endpointURLStorageKey) }
    }

    @Published var bearerToken: String {
        didSet {
            let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                keychain.remove(key: Self.bearerTokenKeychainKey)
            } else {
                keychain.writeString(key: Self.bearerTokenKeychainKey, value: bearerToken)
            }
        }
    }

    private let userDefaults: UserDefaults
    private let keychain: SystemKeychainStore

    init(
        userDefaults: UserDefaults = .standard,
        keychain: SystemKeychainStore? = nil
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain ?? SystemKeychainStore()
        self.endpointURLString = userDefaults.string(forKey: Self.endpointURLStorageKey) ?? ""
        self.bearerToken = self.keychain.readString(key: Self.bearerTokenKeychainKey) ?? ""
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
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return APIExportDestinationSnapshot(
            endpointURL: endpointURL,
            authorizationHeaderValue: authorizationHeaderValue,
            displayName: displayName,
            redactedEndpointDescription: components?.url?.absoluteString ?? endpointURL.absoluteString
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
        guard let endpointURL else { return "No endpoint configured" }
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            return endpointURL.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? endpointURL.absoluteString
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
