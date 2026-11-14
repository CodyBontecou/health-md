import Foundation

nonisolated struct AccountAuthPending: Sendable, CustomStringConvertible, CustomReflectable {
    let captured: AccountAuthCapture
    let pkce: AccountAuthPKCE
    let localGeneration: UInt64
    let expiresAt: UInt64
    var description: String { "[account-auth pending attempt redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

nonisolated enum AccountAuthCallback: Sendable, CustomStringConvertible, CustomReflectable {
    case code(AccountAuthSecret), denied
    var description: String { "[account-auth callback redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Literal raw bytes first. Do not pass a URL/URLComponents-normalized callback here.
    static func decode(_ raw: Data, pending: AccountAuthPending?, localGeneration: UInt64,
                       now: UInt64) throws -> Self {
        guard let p = pending, p.localGeneration == localGeneration, now < p.expiresAt,
              now <= AccountAuthWire.maximumSafeInteger, !raw.isEmpty, raw.count <= 4096,
              raw.allSatisfy({ $0 > 32 && $0 < 127 && ![35, 37, 92].contains($0) }),
              let text = String(data: raw, encoding: .utf8), AccountAuthPKCE.isReference(p.pkce.state) else {
            throw AccountAuthSourceError.malformed
        }
        let parts = text.components(separatedBy: "?")
        guard parts.count == 2, parts[0] == p.captured.registration.callback else {
            throw AccountAuthSourceError.malformed
        }
        var values: [String: String] = [:]
        for pair in parts[1].components(separatedBy: "&") {
            let bits = pair.components(separatedBy: "=")
            guard bits.count == 2, ["code", "error", "state", "iss"].contains(bits[0]),
                  values[bits[0]] == nil else { throw AccountAuthSourceError.malformed }
            values[bits[0]] = bits[1]
        }
        guard values.count == 3, values["state"] == p.pkce.state,
              values["iss"] == p.captured.registration.issuer else { throw AccountAuthSourceError.malformed }
        if Set(values.keys) == ["code", "state", "iss"], let code = values["code"] {
            return .code(try AccountAuthSecret(code, kind: .code))
        }
        if Set(values.keys) == ["error", "state", "iss"], values["error"] == "access_denied" { return .denied }
        throw AccountAuthSourceError.malformed
    }
}

/// A synthetic request plan, NOT a system-browser consent page or presentation adapter.
nonisolated struct AccountAuthAuthorizationPlan: Sendable, CustomStringConvertible, CustomReflectable {
    private let raw: String
    init(pending: AccountAuthPending) throws {
        let p = pending, r = p.captured.registration
        let query = [("client_id", r.clientID), ("redirect_uri", r.callback), ("response_type", "code"),
            ("scope", p.captured.scope), ("state", p.pkce.state), ("code_challenge", p.pkce.challenge),
            ("code_challenge_method", "S256"), ("audience", r.audience)]
        var encoded: [String] = []
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for (key, value) in query {
            guard let value = value.addingPercentEncoding(withAllowedCharacters: unreserved) else {
                throw AccountAuthSourceError.malformed
            }
            encoded.append("\(key)=\(value)")
        }
        raw = r.issuer + "/account/authorize?" + encoded.joined(separator: "&")
        guard raw.utf8.count <= 4096 else { throw AccountAuthSourceError.malformed }
    }
    func syntheticReviewURL() -> String { raw }
    var description: String { "[synthetic authorization metadata request redacted; no browser adapter]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
