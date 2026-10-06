import CryptoKit
import Foundation
import HealthMdConnectionCore
import LocalAuthentication
import Security

/// Non-wire copy of committed native pairing trust, NOT a session, grant or approval. Metadata
/// is available to the authorized in-process caller; formatting/reflection never exposes secrets.
nonisolated struct AgentBridgeExportNativeTrustSnapshot: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let ownerInstallationID: UUID
    let trustedMacInstallationID: UUID
    let displayName: String
    let host: String
    let port: UInt16
    let pairedAt: Date
    fileprivate let secretBytes: [UInt8]
    fileprivate let rawRecordSHA256: [UInt8]
    var reconnectSecret: Data { Data(secretBytes) }
    var description: String { "native_pairing_trust" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }

    fileprivate init(ownerInstallationID: UUID, trustedMac: ManualIPTrustedMac, rawRecordBytes: Data) {
        self.ownerInstallationID = ownerInstallationID
        trustedMacInstallationID = trustedMac.installationID
        displayName = trustedMac.displayName
        host = trustedMac.host
        port = trustedMac.port
        pairedAt = trustedMac.pairedAt
        secretBytes = Array(trustedMac.reconnectSecret)
        rawRecordSHA256 = Array(SHA256.hash(data: rawRecordBytes)) // Exact legacy bytes, NOT new canonical JSON/authority.
    }
}

/// Load-only native Direct CLI trust dependency for a FUTURE authenticated-session adapter.
/// It neither invokes the repairing legacy store nor establishes foreground/BFU/channel authority.
nonisolated struct AgentBridgeExportNativeTrust: Sendable {
    typealias CopyMatching = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    private let copyMatching: CopyMatching
    private static let service = "com.codybontecou.obsidianhealth.direct-cli-ios-trust"
    private static let account = "trust-state-v1"

    init(copyMatching: @escaping CopyMatching = { SecItemCopyMatching($0, $1) }) {
        self.copyMatching = copyMatching
    }

    /// Nil is clean absence (missing record, or the writer's empty/unpaired state). Invalid,
    /// inaccessible, foreign or provisional state throws one fixed failure without error causes.
    func loadExistingTrust(ownerInstallationID: UUID) throws -> AgentBridgeExportNativeTrustSnapshot? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: 2 // Bounded ambiguity detection, never unrestricted enumeration.
        ]
        var result: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound && result == nil { return nil }
        guard status == errSecSuccess,
              let records = result as? [Any], records.count == 1,
              let record = records[0] as? [String: Any],
              record[kSecClass as String] as? String == kSecClassGenericPassword as String,
              record[kSecAttrService as String] as? String == Self.service,
              record[kSecAttrAccount as String] as? String == Self.account,
              record[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
              Self.isExplicitFalse(record[kSecAttrSynchronizable as String]),
              record[kSecAttrIsNegative as String] == nil || Self.isExplicitFalse(record[kSecAttrIsNegative as String]),
              let data = record[kSecValueData as String] as? Data, !data.isEmpty, data.count <= 16 * 1024 else {
            throw AgentBridgeValidationError.permissionRequired
        }
        do {
            var preflight = try NativePairingTrustPreflight(data)
            try preflight.validate()
            let state = try JSONDecoder().decode(ManualIPTrustState.self, from: data)
            guard state.ownerInstallationID == ownerInstallationID, state.provisionalTrustedMac == nil,
                  state.trustedClients.isEmpty else { throw AgentBridgeValidationError.permissionRequired }
            guard let mac = state.trustedMac else { return nil }
            guard mac.reconnectSecret.count == DirectPairingSecurity.reconnectSecretByteCount,
                  mac.pairedAt.timeIntervalSinceReferenceDate.isFinite,
                  mac.pairedAt.timeIntervalSinceReferenceDate.bitPattern == preflight.pairedAt?.bitPattern,
                  mac.reconnectSecret.base64EncodedString() == preflight.reconnectSecret,
                  Self.validText(mac.displayName), Self.validText(mac.host) else { throw AgentBridgeValidationError.permissionRequired }
            return .init(ownerInstallationID: ownerInstallationID, trustedMac: mac, rawRecordBytes: data)
        } catch { throw AgentBridgeValidationError.permissionRequired }
    }

    /// The caller supplies ORIGINAL authenticated native inputs, never a newly selected peer or
    /// credential. Holding a snapshot is insufficient: every call reloads current backing trust.
    func requireCurrent(original: AgentBridgeExportNativeTrustSnapshot, nativeSourceInstallationID: UUID,
                        authenticatedHostInstallationID: UUID, originalReconnectSecret: Data) throws {
        guard let current = try loadExistingTrust(ownerInstallationID: nativeSourceInstallationID),
              original.ownerInstallationID == nativeSourceInstallationID,
              original.trustedMacInstallationID == authenticatedHostInstallationID,
              current.trustedMacInstallationID == authenticatedHostInstallationID,
              current.rawRecordSHA256 == original.rawRecordSHA256,
              current.pairedAt.timeIntervalSinceReferenceDate.bitPattern == original.pairedAt.timeIntervalSinceReferenceDate.bitPattern,
              originalReconnectSecret.count == DirectPairingSecurity.reconnectSecretByteCount,
              Self.sameSecret(original.secretBytes, Array(originalReconnectSecret)),
              Self.sameSecret(original.secretBytes, current.secretBytes) else { throw AgentBridgeValidationError.permissionRequired }
        // Even display/endpoint or byte-only replacement rejects. A future native adapter must
        // independently establish a fresh context; this reader cannot renew/retarget the original.
        // Raw SHA is not authority, native Keychain item identity or privileged anti-rollback.
    }

    private static func sameSecret(_ left: [UInt8], _ right: [UInt8]) -> Bool {
        guard left.count == DirectPairingSecurity.reconnectSecretByteCount,
              right.count == DirectPairingSecurity.reconnectSecretByteCount else { return false }
        var difference: UInt8 = 0
        for index in 0..<DirectPairingSecurity.reconnectSecretByteCount { difference |= left[index] ^ right[index] }
        return difference == 0
    }
    private static func isExplicitFalse(_ value: Any?) -> Bool {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return false }
        return CFEqual(value as CFTypeRef, kCFBooleanFalse)
    }
    private static func validText(_ value: String) -> Bool {
        value.unicodeScalars.count <= 1024 && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

/// ONLY the legacy iPhone ManualIPTrustState/ManualIPTrustedMac grammar, not a general JSON tree
/// or v4 codec. No serialization/canonicalization: original writer bytes go to JSONDecoder intact.
/// Fixed shapes bound depth (two objects), members (three/six), strings (1024 scalars/4096 UTF8
/// bytes) and numeric text (64 bytes); the reader bounds the entire record at 16 KiB first.
nonisolated private struct NativePairingTrustPreflight {
    private enum ObjectKind { case state, mac }
    private let bytes: [UInt8]
    private var position = 0
    private(set) var pairedAt: Double?
    private(set) var reconnectSecret: String?

    init(_ data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else { throw AgentBridgeValidationError.permissionRequired }
        bytes = Array(data)
    }
    mutating func validate() throws {
        try object(.state)
        whitespace()
        guard position == bytes.count else { throw AgentBridgeValidationError.permissionRequired }
    }
    private mutating func object(_ kind: ObjectKind) throws {
        try expect(0x7b)
        var keys = Set<String>()
        if !consume(0x7d) {
            while true {
                let key = try string()
                guard keys.insert(key).inserted else { throw AgentBridgeValidationError.permissionRequired }
                try expect(0x3a)
                switch (kind, key) {
                case (.state, "ownerInstallationID"), (.mac, "installationID"):
                    let value = try string()
                    guard value.utf8.count == 36, UUID(uuidString: value) != nil else { throw AgentBridgeValidationError.permissionRequired }
                case (.state, "trustedMac"):
                    try object(.mac)
                case (.state, "trustedClients"):
                    // This fixed iPhone purpose is a client with one Mac, NOT the Mac's client store.
                    try expect(0x5b); try expect(0x5d)
                case (.mac, "displayName"), (.mac, "host"):
                    _ = try string()
                case (.mac, "reconnectSecret"):
                    reconnectSecret = try string()
                case (.mac, "port"):
                    let value = try number()
                    guard value.utf8.allSatisfy({ (0x30...0x39).contains($0) }), UInt16(value) != nil else { throw AgentBridgeValidationError.permissionRequired }
                    // Native Nearby writer uses port0. This is metadata, not transport admission.
                case (.mac, "pairedAt"):
                    let value = try number()
                    guard let date = Double(value), date.isFinite else { throw AgentBridgeValidationError.permissionRequired }
                    pairedAt = date // Date's DEFAULT writer uses binary64 reference-date seconds.
                default:
                    // Unknown or provisional members (including null) never become committed trust.
                    throw AgentBridgeValidationError.permissionRequired
                }
                if consume(0x7d) { break }
                try expect(0x2c)
            }
        }
        let required: Set<String> = kind == .state ? ["ownerInstallationID", "trustedClients"]
            : ["installationID", "displayName", "host", "port", "reconnectSecret", "pairedAt"]
        guard required.isSubset(of: keys) else { throw AgentBridgeValidationError.permissionRequired }
    }
    private mutating func string() throws -> String {
        try expect(0x22)
        var decoded = [UInt8]()
        while position < bytes.count {
            let byte = bytes[position]; position += 1
            if byte == 0x22 {
                guard let value = String(bytes: decoded, encoding: .utf8), value.unicodeScalars.count <= 1024 else { throw AgentBridgeValidationError.permissionRequired }
                return value
            }
            guard byte >= 0x20 else { throw AgentBridgeValidationError.permissionRequired }
            if byte != 0x5c { decoded.append(byte) }
            else {
                guard position < bytes.count else { throw AgentBridgeValidationError.permissionRequired }
                let escaped = bytes[position]; position += 1
                switch escaped {
                case 0x22, 0x5c, 0x2f: decoded.append(escaped)
                case 0x62: decoded.append(0x08)
                case 0x66: decoded.append(0x0c)
                case 0x6e: decoded.append(0x0a)
                case 0x72: decoded.append(0x0d)
                case 0x74: decoded.append(0x09)
                case 0x75:
                    var value = try hexQuad()
                    if (0xd800...0xdbff).contains(value) {
                        guard position + 2 <= bytes.count, bytes[position] == 0x5c, bytes[position + 1] == 0x75 else { throw AgentBridgeValidationError.permissionRequired }
                        position += 2
                        let low = try hexQuad()
                        guard (0xdc00...0xdfff).contains(low) else { throw AgentBridgeValidationError.permissionRequired }
                        value = 0x10000 + (value - 0xd800) * 1024 + low - 0xdc00
                    }
                    guard let scalar = UnicodeScalar(value) else { throw AgentBridgeValidationError.permissionRequired }
                    decoded.append(contentsOf: String(scalar).utf8)
                default: throw AgentBridgeValidationError.permissionRequired
                }
            }
            guard decoded.count <= 4096 else { throw AgentBridgeValidationError.permissionRequired }
        }
        throw AgentBridgeValidationError.permissionRequired
    }
    private mutating func hexQuad() throws -> UInt32 {
        guard position + 4 <= bytes.count else { throw AgentBridgeValidationError.permissionRequired }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[position]; position += 1
            let digit: UInt8
            switch byte {
            case 0x30...0x39: digit = byte - 0x30
            case 0x41...0x46: digit = byte - 0x41 + 10
            case 0x61...0x66: digit = byte - 0x61 + 10
            default: throw AgentBridgeValidationError.permissionRequired
            }
            value = value * 16 + UInt32(digit)
        }
        return value
    }
    private mutating func number() throws -> String {
        whitespace()
        let start = position
        if peek == 0x2d { position += 1 }
        if peek == 0x30 { position += 1 }
        else {
            guard let byte = peek, (0x31...0x39).contains(byte) else { throw AgentBridgeValidationError.permissionRequired }
            try digits()
        }
        if peek == 0x2e { position += 1; try digits() }
        if peek == 0x65 || peek == 0x45 {
            position += 1
            if peek == 0x2b || peek == 0x2d { position += 1 }
            try digits()
        }
        guard position - start <= 64 else { throw AgentBridgeValidationError.permissionRequired }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }
    private mutating func digits() throws {
        let start = position
        while let byte = peek, (0x30...0x39).contains(byte) {
            position += 1
            guard position - start <= 64 else { throw AgentBridgeValidationError.permissionRequired }
        }
        guard position > start else { throw AgentBridgeValidationError.permissionRequired }
    }
    private var peek: UInt8? { position < bytes.count ? bytes[position] : nil }
    private mutating func whitespace() {
        while let byte = peek, [0x20, 0x09, 0x0a, 0x0d].contains(byte) { position += 1 }
    }
    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard peek == byte else { return false }
        position += 1
        return true
    }
    private mutating func expect(_ byte: UInt8) throws {
        guard consume(byte) else { throw AgentBridgeValidationError.permissionRequired }
    }
}
