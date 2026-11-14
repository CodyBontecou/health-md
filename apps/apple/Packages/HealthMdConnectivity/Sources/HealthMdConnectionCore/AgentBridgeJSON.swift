import CryptoKit
import Foundation

/// Fixed, health-free failures. Never wrap a parser exception or rejected value.
public enum AgentBridgeValidationError: String, Error, Codable, Sendable, CustomStringConvertible, LocalizedError {
    case invalidRequest = "invalid_request"
    case unsupportedCapability = "unsupported_capability"
    case unsupportedMetric = "unsupported_metric"
    case permissionRequired = "permission_required"
    case historyUnverified = "history_unverified"
    case configurationProtected = "configuration_protected"
    case entitlementRequired = "entitlement_required"
    case nativeRebindRequired = "native_rebind_required"
    case revisionConflict = "revision_conflict"
    case approvalRequired = "approval_required"
    case bindingChanged = "binding_changed"
    case planExpired = "plan_expired"
    case unsafePath = "unsafe_path"
    case pathCollision = "path_collision"
    case queryBudgetExceeded = "query_budget_exceeded"
    case cursorInvalid = "cursor_invalid"
    case snapshotExpired = "snapshot_expired"
    case busy, cancelled
    case spoolMissingRestartRequired = "spool_missing_restart_required"
    case jobExpired = "job_expired"

    public var description: String { rawValue }
    public var errorDescription: String? { rawValue }
}

/// Pure v4 codec. It does not negotiate an installed connection, issue approval, or perform IO.
public enum AgentBridgeV4Codec {
    public static let maximumBytes = 2 * 1_024 * 1_024

    /// Codec agreement only: canonicalizing a tree does not authorize or validate a domain document.
    public static func canonicalize(_ bytes: Data) throws -> Data {
        try BridgeJSON.parse(bytes).canonicalBytes()
    }

    public static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from bytes: Data) throws -> T {
        guard let closedType = type as? any BridgeValueCodable.Type else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        let tree = try BridgeJSON.parse(bytes)
        guard let result = try closedType.init(bridgeJSON: tree) as? T else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return result
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        guard let closed = value as? any BridgeValueCodable else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        // Constructors and raw-byte decoding use the same closed grammar checks.
        _ = try type(of: closed).init(bridgeJSON: closed.bridgeJSON)
        let bytes = try closed.bridgeJSON.canonicalBytes()
        // Enforce the same recursive/outer limits for native constructors as wire input.
        _ = try BridgeJSON.parse(bytes)
        return bytes
    }

    public static func digest<T: Encodable>(_ value: T) throws -> String {
        sha256(try encode(value))
    }
}

// This tree is private codec machinery, not a domain forwarding/authority API. Objects use
// byte-exact keys: Swift String equality deliberately equates NFC/NFD strings, which JSON does not.
indirect enum BridgeJSON: Equatable {
    struct Member: Equatable {
        let key: String
        let value: BridgeJSON
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value == rhs.value
        }
    }
    case object([Member]), array([BridgeJSON]), string(String), integer(String), bool(Bool), null

    static func object(_ fields: [(String, BridgeJSON?)]) -> Self {
        .object(fields.compactMap { key, value in value.map { Member(key: key, value: $0) } })
    }
    static func int(_ value: Int64) -> Self { .integer(String(value)) }
    static func strings(_ values: [String]) -> Self { .array(values.map(Self.string)) }
    static func values<T: BridgeValueCodable>(_ values: [T]) -> Self { .array(values.map(\.bridgeJSON)) }

    static func parse(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= AgentBridgeV4Codec.maximumBytes else {
            throw AgentBridgeValidationError.invalidRequest
        }
        var parser = BridgeJSONParser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }

    func removing(_ keys: [String]) -> Self {
        guard case .object(let members) = self else { return self }
        let excluded = Set(keys.map { Data($0.utf8) })
        return .object(members.filter { !excluded.contains(Data($0.key.utf8)) })
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.string(let a), .string(let b)), (.integer(let a), .integer(let b)): return a.utf8.elementsEqual(b.utf8)
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    func canonicalBytes() throws -> Data {
        var output = Data()
        try append(to: &output)
        return output
    }

    private func append(to output: inout Data) throws {
        func text(_ value: String) { output.append(contentsOf: value.utf8) }
        switch self {
        case .null: text("null")
        case .bool(let value): text(value ? "true" : "false")
        case .integer(let value): text(value == "-0" ? "0" : value)
        case .string(let value): Self.quote(value, into: &output)
        case .array(let values):
            text("[")
            for (index, value) in values.enumerated() {
                if index > 0 { text(",") }
                try value.append(to: &output)
            }
            text("]")
        case .object(let members):
            // Valid UTF-8 byte lexicographic order equals Unicode scalar/codepoint order.
            // No Foundation/locale/UTF-16 sorting and no normalization.
            let sorted = members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            var keys = Set<Data>()
            text("{")
            for (index, member) in sorted.enumerated() {
                guard keys.insert(Data(member.key.utf8)).inserted else { throw AgentBridgeValidationError.invalidRequest }
                if index > 0 { text(",") }
                Self.quote(member.key, into: &output)
                text(":")
                try member.value.append(to: &output)
            }
            text("}")
        }
        guard output.count <= AgentBridgeV4Codec.maximumBytes else { throw AgentBridgeValidationError.invalidRequest }
    }

    private static func quote(_ value: String, into output: inout Data) {
        output.append(0x22)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output.append(contentsOf: [0x5c, 0x22])
            case 0x5c: output.append(contentsOf: [0x5c, 0x5c])
            case 8: output.append(contentsOf: "\\b".utf8)
            case 9: output.append(contentsOf: "\\t".utf8)
            case 10: output.append(contentsOf: "\\n".utf8)
            case 12: output.append(contentsOf: "\\f".utf8)
            case 13: output.append(contentsOf: "\\r".utf8)
            case 0...31: output.append(contentsOf: String(format: "\\u%04x", scalar.value).utf8)
            default: output.append(contentsOf: String(scalar).utf8)
            }
        }
        output.append(0x22)
    }
}

private struct BridgeJSONParser {
    let bytes: [UInt8]
    var index = 0
    var nodes = 0

    mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    mutating func value(depth: Int) throws -> BridgeJSON {
        try count(depth: depth)
        whitespace()
        guard index < bytes.count else { throw AgentBridgeValidationError.invalidRequest }
        switch bytes[index] {
        case 0x7b:
            index += 1; whitespace()
            var result: [BridgeJSON.Member] = []
            var keys = Set<Data>()
            if take(0x7d) { return .object(result) }
            while true {
                try count(depth: depth + 1)
                whitespace()
                let key = try string()
                guard keys.insert(Data(key.utf8)).inserted, result.count < 512 else {
                    throw AgentBridgeValidationError.invalidRequest
                }
                whitespace(); guard take(0x3a) else { throw AgentBridgeValidationError.invalidRequest }
                result.append(.init(key: key, value: try value(depth: depth + 1)))
                whitespace()
                if take(0x7d) { break }
                guard take(0x2c) else { throw AgentBridgeValidationError.invalidRequest }
            }
            return .object(result)
        case 0x5b:
            index += 1; whitespace()
            var result: [BridgeJSON] = []
            if take(0x5d) { return .array(result) }
            while true {
                guard result.count < 4096 else { throw AgentBridgeValidationError.invalidRequest }
                result.append(try value(depth: depth + 1)); whitespace()
                if take(0x5d) { break }
                guard take(0x2c) else { throw AgentBridgeValidationError.invalidRequest }
            }
            return .array(result)
        case 0x22: return .string(try string())
        case 0x74: try literal("true"); return .bool(true)
        case 0x66: try literal("false"); return .bool(false)
        case 0x6e: try literal("null"); return .null
        case 0x2d, 0x30...0x39: return .integer(try integer())
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }

    private mutating func count(depth: Int) throws {
        nodes += 1
        guard depth <= 24, nodes <= 262_144 else { throw AgentBridgeValidationError.invalidRequest }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func literal(_ value: String) throws {
        for byte in value.utf8 {
            guard take(byte) else { throw AgentBridgeValidationError.invalidRequest }
        }
    }

    private mutating func integer() throws -> String {
        let start = index
        _ = take(0x2d)
        guard index < bytes.count else { throw AgentBridgeValidationError.invalidRequest }
        if take(0x30) {
            // A following digit/decimal/exponent is rejected by the enclosing syntax.
        } else {
            guard (0x31...0x39).contains(bytes[index]) else { throw AgentBridgeValidationError.invalidRequest }
            repeat { index += 1 } while index < bytes.count && (0x30...0x39).contains(bytes[index])
        }
        if index < bytes.count, [0x2e, 0x65, 0x45].contains(bytes[index]) {
            throw AgentBridgeValidationError.invalidRequest
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        return text == "-0" ? "0" : text
    }

    private mutating func string() throws -> String {
        guard take(0x22) else { throw AgentBridgeValidationError.invalidRequest }
        var result = String.UnicodeScalarView()
        var scalars = 0
        while index < bytes.count {
            if take(0x22) { return String(result) }
            let scalar: UInt32
            if take(0x5c) {
                guard index < bytes.count else { throw AgentBridgeValidationError.invalidRequest }
                let escape = bytes[index]; index += 1
                switch escape {
                case 0x22, 0x5c, 0x2f: scalar = UInt32(escape)
                case 0x62: scalar = 8
                case 0x66: scalar = 12
                case 0x6e: scalar = 10
                case 0x72: scalar = 13
                case 0x74: scalar = 9
                case 0x75:
                    let first = try hex4()
                    if (0xd800...0xdbff).contains(first) {
                        guard take(0x5c), take(0x75) else { throw AgentBridgeValidationError.invalidRequest }
                        let second = try hex4()
                        guard (0xdc00...0xdfff).contains(second) else { throw AgentBridgeValidationError.invalidRequest }
                        scalar = 0x10000 + ((first - 0xd800) << 10) + second - 0xdc00
                    } else { scalar = first }
                default: throw AgentBridgeValidationError.invalidRequest
                }
            } else {
                let first = bytes[index]; index += 1
                guard first >= 0x20 else { throw AgentBridgeValidationError.invalidRequest }
                if first < 0x80 { scalar = UInt32(first) }
                else {
                    let continuation: Int
                    let minimum: UInt32
                    var decoded: UInt32
                    switch first {
                    case 0xc2...0xdf: continuation = 1; minimum = 0x80; decoded = UInt32(first & 0x1f)
                    case 0xe0...0xef: continuation = 2; minimum = 0x800; decoded = UInt32(first & 0x0f)
                    case 0xf0...0xf4: continuation = 3; minimum = 0x10000; decoded = UInt32(first & 7)
                    default: throw AgentBridgeValidationError.invalidRequest
                    }
                    for _ in 0..<continuation {
                        guard index < bytes.count, (0x80...0xbf).contains(bytes[index]) else { throw AgentBridgeValidationError.invalidRequest }
                        decoded = (decoded << 6) | UInt32(bytes[index] & 0x3f); index += 1
                    }
                    guard decoded >= minimum else { throw AgentBridgeValidationError.invalidRequest }
                    scalar = decoded
                }
            }
            guard let valid = UnicodeScalar(scalar), !(0xd800...0xdfff).contains(scalar) else { throw AgentBridgeValidationError.invalidRequest }
            scalars += 1
            guard scalars <= 65_536 else { throw AgentBridgeValidationError.invalidRequest }
            result.append(valid)
        }
        throw AgentBridgeValidationError.invalidRequest
    }

    private mutating func hex4() throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            guard index < bytes.count else { throw AgentBridgeValidationError.invalidRequest }
            let byte = bytes[index]; index += 1
            let value: UInt32
            switch byte {
            case 0x30...0x39: value = UInt32(byte - 0x30)
            case 0x41...0x46: value = UInt32(byte - 0x41 + 10)
            case 0x61...0x66: value = UInt32(byte - 0x61 + 10)
            default: throw AgentBridgeValidationError.invalidRequest
            }
            result = result * 16 + value
        }
        return result
    }
}
