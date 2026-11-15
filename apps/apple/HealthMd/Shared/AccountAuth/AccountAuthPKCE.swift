import Foundation
import CryptoKit

nonisolated protocol AccountAuthEntropy: Sendable {
    nonisolated func bytes(count: Int) throws -> Data
}
nonisolated protocol AccountAuthClock: Sendable {
    nonisolated func seconds() throws -> UInt64
}

nonisolated struct AccountAuthPKCE: Sendable, CustomStringConvertible, CustomReflectable {
    let state: String
    let verifier: String
    let challenge: String
    var description: String { "[account-auth PKCE redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func isReference(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 43, bytes.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }), let decoded = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "="), decoded.count == 32 else { return false }
        return base64URL(decoded) == value
    }
    static func challenge(verifier: String) throws -> String {
        let bytes = Array(verifier.utf8)
        guard (43...128).contains(bytes.count), bytes.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) ||
                [45, 46, 95, 126].contains($0)
        }) else { throw AccountAuthSourceError.malformed }
        return base64URL(Data(SHA256.hash(data: Data(bytes))))
    }
    static func reference(entropy: any AccountAuthEntropy) throws -> String {
        do {
            let bytes = try entropy.bytes(count: 32)
            guard bytes.count == 32 else { throw AccountAuthSourceError.entropy }
            return base64URL(bytes)
        } catch { throw AccountAuthSourceError.entropy } // No UUID/provider/random fallback.
    }
    static func make(entropy: any AccountAuthEntropy) throws -> Self {
        let state = try reference(entropy: entropy)
        let verifier = try reference(entropy: entropy)
        return Self(state: state, verifier: verifier, challenge: try challenge(verifier: verifier))
    }
}
