import Foundation

// Codable witnesses route through the same closed typed field readers. The raw-byte public codec
// runs its strict parser first; Foundation is used only for Codable interoperability, never preflight.
protocol BridgeValueCodable: Codable {
    init(bridgeJSON: BridgeJSON) throws
    var bridgeJSON: BridgeJSON { get }
}

extension BridgeValueCodable {
    public init(from decoder: Decoder) throws {
        do { self = try Self(bridgeJSON: BridgeJSON(from: decoder)) }
        catch let error as AgentBridgeValidationError { throw error }
        catch { throw AgentBridgeValidationError.invalidRequest }
    }
    public func encode(to encoder: Encoder) throws {
        // Foundation output is interoperable, not canonical, but invalid native constructors must
        // still fail the same closed grammar and bounded semantic checks.
        let bytes = try AgentBridgeV4Codec.encode(self)
        try BridgeJSON.parse(bytes).encode(to: encoder)
    }
}

extension BridgeJSON: Codable {
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: Key.self) {
            self = .object(try object.allKeys.map { .init(key: $0.stringValue, value: try object.decode(Self.self, forKey: $0)) })
        } else if var array = try? decoder.unkeyedContainer() {
            var values: [Self] = []
            while !array.isAtEnd { values.append(try array.decode(Self.self)) }
            self = .array(values)
        } else {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { self = .null }
            else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
            else if let integer = try? value.decode(Int64.self) { self = .int(integer) }
            else if let integer = try? value.decode(UInt64.self) { self = .integer(String(integer)) }
            else if let text = try? value.decode(String.self) { self = .string(text) }
            else { throw AgentBridgeValidationError.invalidRequest }
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let members):
            var object = encoder.container(keyedBy: Key.self)
            for member in members { try object.encode(member.value, forKey: Key(stringValue: member.key)) }
        case .array(let values):
            var array = encoder.unkeyedContainer()
            for value in values { try array.encode(value) }
        default:
            var value = encoder.singleValueContainer()
            switch self {
            case .null: try value.encodeNil()
            case .bool(let bool): try value.encode(bool)
            case .string(let text): try value.encode(text)
            case .integer(let text):
                if let integer = Int64(text) { try value.encode(integer) }
                else if let integer = UInt64(text) { try value.encode(integer) }
                else { throw AgentBridgeValidationError.invalidRequest }
            default: throw AgentBridgeValidationError.invalidRequest
            }
        }
    }
}

struct BridgeObject {
    private let fields: [String: BridgeJSON]
    init(_ json: BridgeJSON, _ required: [String], optional: [String] = []) throws {
        guard case .object(let members) = json else { throw AgentBridgeValidationError.invalidRequest }
        let requiredKeys = Set(required.map { Data($0.utf8) })
        let allowed = requiredKeys.union(optional.map { Data($0.utf8) })
        let actual = members.map { Data($0.key.utf8) }
        guard Set(actual).count == actual.count, Set(actual).isSubset(of: allowed), requiredKeys.isSubset(of: Set(actual)) else {
            throw AgentBridgeValidationError.invalidRequest
        }
        // All domain keys in this edition are closed ASCII, so String equality is safe here.
        self.fields = Dictionary(uniqueKeysWithValues: members.map { ($0.key, $0.value) })
    }
    func has(_ key: String) -> Bool { fields[key] != nil }
    func strings(_ key: String, min: Int = 0, max: Int = 4096, minLength: Int = 0, maxLength: Int = 65_536) throws -> [String] {
        try array(key, min: min, max: max).map {
            guard case .string(let text) = $0, (minLength...maxLength).contains(text.unicodeScalars.count) else { throw AgentBridgeValidationError.invalidRequest }
            return text
        }
    }
    func node(_ key: String) throws -> BridgeJSON {
        guard let value = fields[key] else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func value<T: BridgeValueCodable>(_ key: String) throws -> T { try T(bridgeJSON: node(key)) }
    func optional<T: BridgeValueCodable>(_ key: String) throws -> T? {
        guard let value = fields[key] else { return nil }
        guard value != .null else { throw AgentBridgeValidationError.invalidRequest }
        return try T(bridgeJSON: value)
    }
    func text(_ key: String, min: Int = 0, max: Int = 65_536) throws -> String {
        guard case .string(let value) = try node(key), (min...max).contains(value.unicodeScalars.count) else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func optionalText(_ key: String, min: Int = 1, max: Int = 256) throws -> String? {
        guard fields[key] != nil else { return nil }
        return try text(key, min: min, max: max)
    }
    func int(_ key: String, min: Int64 = 0, max: Int64 = Int64.max) throws -> Int64 {
        guard case .integer(let text) = try node(key), let value = Int64(text), (min...max).contains(value) else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func bool(_ key: String) throws -> Bool {
        guard case .bool(let value) = try node(key) else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func token<T: RawRepresentable>(_ key: String) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: try text(key)) else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func array(_ key: String, min: Int = 0, max: Int = 4096) throws -> [BridgeJSON] {
        guard case .array(let value) = try node(key), (min...max).contains(value.count) else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func list<T: BridgeValueCodable>(_ key: String, min: Int = 0, max: Int = 4096) throws -> [T] {
        try array(key, min: min, max: max).map { try T(bridgeJSON: $0) }
    }
    func tokens<T: RawRepresentable>(_ key: String, min: Int = 0, max: Int = 4096) throws -> [T] where T.RawValue == String {
        try array(key, min: min, max: max).map {
            guard case .string(let text) = $0, let value = T(rawValue: text) else { throw AgentBridgeValidationError.invalidRequest }
            return value
        }
    }
    func constant(_ key: String, _ value: BridgeJSON) throws {
        guard try node(key) == value else { throw AgentBridgeValidationError.invalidRequest }
    }
    func schema(_ schema: String) throws {
        try constant("schema", .string(schema)); try constant("schema_version", .int(1))
    }
}

public protocol AgentBridgeTextRule: Sendable {
    static func validate(_ value: String) throws
}

public struct AgentBridgeText<Rule: AgentBridgeTextRule>: Codable, Equatable, Hashable, Sendable, BridgeValueCodable {
    public let rawValue: String
    public init(_ value: String) throws { try Rule.validate(value); rawValue = value }
    init(bridgeJSON: BridgeJSON) throws {
        guard case .string(let value) = bridgeJSON else { throw AgentBridgeValidationError.invalidRequest }
        try self.init(value)
    }
    var bridgeJSON: BridgeJSON { .string(rawValue) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8) }
    public func hash(into hasher: inout Hasher) { hasher.combine(Data(rawValue.utf8)) }
}

func bridgePattern(_ value: String, _ pattern: String, max: Int) throws {
    guard value.unicodeScalars.count <= max, value.range(of: pattern, options: .regularExpression) != nil else { throw AgentBridgeValidationError.invalidRequest }
}
public enum AgentBridgeUUIDRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws {
        try bridgePattern(value, "\\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\z", max: 36)
    }
}
public enum AgentBridgeDigestRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws { try bridgePattern(value, "\\A[0-9a-f]{64}\\z", max: 64) }
}
public enum AgentBridgeIDRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws { try bridgePattern(value, "\\A[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\\z", max: 128) }
}
public enum AgentBridgeNativeTypeRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws { try bridgePattern(value, "\\A[A-Za-z_][A-Za-z0-9_.:$-]{0,255}\\z", max: 256) }
}
public enum AgentBridgeDateRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws {
        try bridgePattern(value, "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}\\z", max: 10)
        guard let date = bridgeDate(value), bridgeCivil(date) == value else { throw AgentBridgeValidationError.invalidRequest }
    }
}
public enum AgentBridgeUTCRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws {
        try bridgePattern(value, "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z", max: 20)
        guard let date = bridgeInstant(value), bridgeUTC(date) == value else { throw AgentBridgeValidationError.invalidRequest }
    }
}
public enum AgentBridgeZoneRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws {
        guard !value.isEmpty, value.unicodeScalars.count <= 128,
              value == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(value)
                || (value.contains("/") && TimeZone(identifier: value) != nil) else { throw AgentBridgeValidationError.invalidRequest }
    }
}
public typealias AgentBridgeUUID = AgentBridgeText<AgentBridgeUUIDRule>
public typealias AgentBridgeDigest = AgentBridgeText<AgentBridgeDigestRule>
public typealias AgentBridgeID = AgentBridgeText<AgentBridgeIDRule>
public typealias AgentBridgeNativeType = AgentBridgeText<AgentBridgeNativeTypeRule>
public typealias AgentBridgeDate = AgentBridgeText<AgentBridgeDateRule>
public typealias AgentBridgeUTC = AgentBridgeText<AgentBridgeUTCRule>
public typealias AgentBridgeZone = AgentBridgeText<AgentBridgeZoneRule>

// Proleptic Gregorian civil arithmetic. DateFormatter's historical cutover must not affect
// contract dates, day windows, expiry comparisons, or path prediction.
func bridgeDate(_ text: String) -> Date? {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...9999).contains(y), (1...12).contains(m) else { return nil }
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
    let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...monthDays[m - 1]).contains(d) else { return nil }
    let year = y - (m <= 2 ? 1 : 0)
    let era = year / 400
    let yearOfEra = year - era * 400
    let dayOfYear = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
    let days = era * 146097 + yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear - 719468
    return Date(timeIntervalSince1970: Double(days) * 86_400)
}
func bridgeCivil(_ date: Date) -> String {
    let z = Int(floor(date.timeIntervalSince1970 / 86_400)) + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let dayOfEra = z - era * 146097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let mp = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * mp + 2) / 5 + 1
    let month = mp + (mp < 10 ? 3 : -9)
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return String(format: "%04d-%02d-%02d", year, month, day)
}
func bridgeInstant(_ text: String) -> Date? {
    guard text.utf8.count == 20, let day = bridgeDate(String(text.prefix(10))) else { return nil }
    let clock = text.dropFirst(11).dropLast().split(separator: ":")
    guard clock.count == 3, let h = Int(clock[0]), let m = Int(clock[1]), let s = Int(clock[2]), (0...23).contains(h), (0...59).contains(m), (0...59).contains(s) else { return nil }
    return day.addingTimeInterval(Double(h * 3600 + m * 60 + s))
}
func bridgeUTC(_ date: Date) -> String {
    let seconds = Int(date.timeIntervalSince1970 - floor(date.timeIntervalSince1970 / 86_400) * 86_400)
    return bridgeCivil(date) + String(format: "T%02d:%02d:%02dZ", seconds / 3600, seconds / 60 % 60, seconds % 60)
}

func bridgeSortedUnique(_ values: [String]) throws {
    let keys = values.map { Data($0.utf8) }
    guard Set(keys).count == keys.count, keys == keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) else { throw AgentBridgeValidationError.invalidRequest }
}
func bridgeUnique(_ values: [String]) throws {
    guard Set(values.map { Data($0.utf8) }).count == values.count else { throw AgentBridgeValidationError.invalidRequest }
}
func bridgeTokens<T: RawRepresentable>(_ values: [T]) -> BridgeJSON where T.RawValue == String { .strings(values.map(\.rawValue)) }
