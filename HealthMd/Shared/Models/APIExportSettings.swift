import Combine
import Foundation

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
        endpointURL != nil
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
