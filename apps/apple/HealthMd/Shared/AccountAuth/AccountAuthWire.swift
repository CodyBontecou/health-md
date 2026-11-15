import Foundation

/// Closed raw wire codec, NOT authenticated transport/current-attempt/secure-store authority.
nonisolated enum AccountAuthWire {
    static let maximumSafeInteger: UInt64 = 9_007_199_254_740_991
    private static let successKeys: Set<String> = ["token_type", "access_token", "expires_in", "refresh_token",
        "session_id", "scope", "issuer", "environment", "audience", "client_id", "installation_id",
        "account_id", "session_generation"]

    static func decodeSession(_ bytes: Data, captured: AccountAuthCapture) throws -> AccountAuthSession {
        let fields = try object(bytes, keys: successKeys)
        func text(_ key: String) throws -> String {
            guard case .text(let value) = fields[key] else { throw AccountAuthSourceError.malformed }
            return value
        }
        func integer(_ key: String) throws -> UInt64 {
            guard case .integer(let value) = fields[key] else { throw AccountAuthSourceError.malformed }
            return value
        }
        let r = captured.registration
        let type = try text("token_type"), issuer = try text("issuer"), env = try text("environment")
        let audience = try text("audience"), client = try text("client_id"), install = try text("installation_id")
        let scope = try text("scope"), account = try text("account_id"), family = try text("session_id")
        let ttl = try integer("expires_in"), generation = try integer("session_generation")
        guard type == "Bearer", issuer == r.issuer, env == r.environment, audience == r.audience,
              client == r.clientID, install == captured.installationID, scope == captured.scope,
              try AccountAuthCapture.canonicalScope(scope) == scope,
              (1...300).contains(ttl), AccountAuthPKCE.isReference(family), opaqueAccountID(account) else {
            throw AccountAuthSourceError.malformed
        }
        return AccountAuthSession(tokenType: type, access: try AccountAuthSecret(text("access_token"), kind: .access),
            expiresIn: ttl, refresh: try AccountAuthSecret(text("refresh_token"), kind: .refresh),
            sessionID: family, scope: scope,
            namespace: AccountAuthNamespace(issuer: issuer, environment: env, accountID: account),
            audience: audience, clientID: client, installationID: install, serverGeneration: generation)
    }

    static func validateInitial(_ session: AccountAuthSession) throws {
        guard session.serverGeneration == 0 else { throw AccountAuthSourceError.malformed }
    }
    static func validateRefresh(_ session: AccountAuthSession, previous: AccountAuthSession) throws {
        guard previous.serverGeneration < maximumSafeInteger,
              session.serverGeneration == previous.serverGeneration + 1,
              session.namespace == previous.namespace, session.audience == previous.audience,
              session.clientID == previous.clientID, session.installationID == previous.installationID,
              session.sessionID == previous.sessionID, session.scope == previous.scope,
              session.access != previous.access, session.refresh != previous.refresh else {
            throw AccountAuthSourceError.malformed
        }
    }
    static func decodeFailure(_ bytes: Data) throws -> AccountAuthFailure {
        let fields = try object(bytes, keys: ["error"])
        guard case .text(let value) = fields["error"], let code = AccountAuthFailure(rawValue: value) else {
            throw AccountAuthSourceError.malformed
        }
        return code
    }
    static func decodeRevokeAcknowledgement(_ bytes: Data) throws {
        let fields = try object(bytes, keys: ["revoked"])
        guard case .boolean(true) = fields["revoked"] else { throw AccountAuthSourceError.malformed }
    }
    static func opaqueAccountID(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$", options: .regularExpression) != nil ||
            value.range(of: "^synthetic-account-[a-z0-9]{1,32}$", options: .regularExpression) != nil
    }

    private enum Atom { case text(String), integer(UInt64), boolean(Bool) }
    private static func object(_ bytes: Data, keys: Set<String>) throws -> [String: Atom] {
        guard !bytes.isEmpty, bytes.count <= 8192, !bytes.starts(with: [0xEF, 0xBB, 0xBF]),
              let text = String(data: bytes, encoding: .utf8), text.unicodeScalars.first?.value != 0xFEFF else {
            throw AccountAuthSourceError.malformed
        }
        var reader = Reader(scalars: Array(text.unicodeScalars))
        return try reader.object(keys: keys)
    }

    /// Parses strings losslessly (including paired surrogate escapes) BEFORE checking decoded duplicates.
    /// Integers use lexical canonical unsigned decimal, not NSNumber/Double coercion. No nested/null atoms.
    private struct Reader {
        let scalars: [Unicode.Scalar]
        var offset = 0
        var peek: UInt32? { offset < scalars.count ? scalars[offset].value : nil }
        mutating func space() {
            while let c = peek, [0x20, 0x09, 0x0A, 0x0D].contains(c) { offset += 1 }
        }
        mutating func take(_ c: UInt32) throws {
            guard peek == c else { throw AccountAuthSourceError.malformed }
            offset += 1
        }
        mutating func hex4() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let c = peek else { throw AccountAuthSourceError.malformed }
                let digit: UInt32
                switch c {
                case 48...57: digit = c - 48
                case 65...70: digit = c - 55
                case 97...102: digit = c - 87
                default: throw AccountAuthSourceError.malformed
                }
                value = value * 16 + digit
                offset += 1
            }
            return value
        }
        mutating func string() throws -> String {
            try take(34)
            var result = String.UnicodeScalarView()
            while let c = peek {
                offset += 1
                if c == 34 { return String(result) }
                var decoded = c
                if c == 92 {
                    guard let escape = peek else { throw AccountAuthSourceError.malformed }
                    offset += 1
                    switch escape {
                    case 34, 92, 47: decoded = escape
                    case 98: decoded = 8
                    case 102: decoded = 12
                    case 110: decoded = 10
                    case 114: decoded = 13
                    case 116: decoded = 9
                    case 117:
                        decoded = try hex4()
                        if (0xD800...0xDBFF).contains(decoded) {
                            try take(92); try take(117)
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw AccountAuthSourceError.malformed }
                            decoded = 0x10000 + (decoded - 0xD800) * 0x400 + low - 0xDC00
                        } else if (0xDC00...0xDFFF).contains(decoded) { throw AccountAuthSourceError.malformed }
                    default: throw AccountAuthSourceError.malformed
                    }
                } else if c < 0x20 { throw AccountAuthSourceError.malformed }
                guard decoded >= 0x20, !(0x7F...0x9F).contains(decoded),
                      let scalar = Unicode.Scalar(decoded), result.count < 4096 else {
                    throw AccountAuthSourceError.malformed
                }
                result.append(scalar)
            }
            throw AccountAuthSourceError.malformed
        }
        mutating func atom() throws -> Atom {
            if peek == 34 { return .text(try string()) }
            if peek == 116 || peek == 102 {
                let value = peek == 116
                for c in (value ? "true" : "false").unicodeScalars { try take(c.value) }
                return .boolean(value)
            }
            guard let first = peek, (48...57).contains(first) else { throw AccountAuthSourceError.malformed }
            var value: UInt64 = 0
            offset += 1
            value = UInt64(first - 48)
            if first == 48 {
                if let c = peek, (48...57).contains(c) { throw AccountAuthSourceError.malformed }
            } else {
                while let c = peek, (48...57).contains(c) {
                    guard value <= (AccountAuthWire.maximumSafeInteger - UInt64(c - 48)) / 10 else {
                        throw AccountAuthSourceError.malformed
                    }
                    value = value * 10 + UInt64(c - 48)
                    offset += 1
                }
            }
            return .integer(value)
        }
        mutating func object(keys: Set<String>) throws -> [String: Atom] {
            space(); try take(123); space()
            var fields: [String: Atom] = [:]
            if peek != 125 {
                while true {
                    let key = try string()
                    guard fields[key] == nil, keys.contains(key), fields.count < keys.count else {
                        throw AccountAuthSourceError.malformed
                    }
                    space(); try take(58); space()
                    fields[key] = try atom()
                    space()
                    if peek == 125 { break }
                    try take(44); space()
                }
            }
            try take(125); space()
            guard offset == scalars.count, Set(fields.keys) == keys else { throw AccountAuthSourceError.malformed }
            return fields
        }
    }
}
