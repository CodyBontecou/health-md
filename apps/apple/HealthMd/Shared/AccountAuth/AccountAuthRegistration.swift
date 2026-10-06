import Foundation

nonisolated enum AccountAuthAppleClient: String, Sendable, CaseIterable {
    case iOS = "synthetic-apple-ios", iPadOS = "synthetic-apple-ipados", macOS = "synthetic-apple-macos"
}

/// Private construction; reserved-domain registry only, never callback/token/caller endpoint discovery.
/// The decoder can study every pinned client. The Apple coordinator accepts ONLY AccountAuthAppleClient.
nonisolated struct AccountAuthRegistration: Sendable, Equatable {
    let issuer: String
    let environment: String
    let audience: String
    let clientID: String
    let callback: String

    private init(name: String) {
        issuer = "https://account-auth.synthetic.example"
        environment = "synthetic"
        audience = "urn:healthmd:account-config:synthetic:v1"
        clientID = "synthetic-\(name)"
        callback = "https://callbacks.account-sync.example/\(name)/return"
    }

    static func reviewedSynthetic(clientID: String, environment: String = "synthetic") throws -> Self {
        guard environment == "synthetic" else { throw AccountAuthSourceError.unavailable }
        let names = ["apple-ios", "apple-ipados", "apple-macos", "android-play", "android-fdroid"]
        guard let name = names.first(where: { clientID == "synthetic-\($0)" }) else {
            throw AccountAuthSourceError.unavailable
        }
        return Self(name: name)
    }

    static func reviewedSynthetic(apple: AccountAuthAppleClient) -> Self {
        // Every enum case is pinned above; no arbitrary environment/channel substitution.
        Self(name: String(apple.rawValue.dropFirst("synthetic-".count)))
    }
}

nonisolated struct AccountAuthCapture: Sendable, Equatable {
    let registration: AccountAuthRegistration
    let installationID: String
    let scope: String

    init(registration: AccountAuthRegistration, installationID: String, scope: String) throws {
        guard AccountAuthPKCE.isReference(installationID) else { throw AccountAuthSourceError.malformed }
        self.registration = registration
        self.installationID = installationID
        self.scope = try Self.canonicalScope(scope)
    }

    static func canonicalScope(_ scope: String) throws -> String {
        let allowed = ["account:sessions:read", "account:sessions:revoke:self",
                       "config:profiles:read", "config:profiles:write"]
        let parts = scope.components(separatedBy: " ")
        guard !parts.isEmpty, parts.allSatisfy(allowed.contains),
              Set(parts).sorted().joined(separator: " ") == scope,
              !parts.contains("config:profiles:write") || parts.contains("config:profiles:read") else {
            throw AccountAuthSourceError.malformed
        }
        return scope
    }
}
