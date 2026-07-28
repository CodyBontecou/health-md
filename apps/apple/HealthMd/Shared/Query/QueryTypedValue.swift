import Foundation

// MARK: - Portable typed values

/// JSON-shaped payload retained for a typed value introduced by a newer Health.md version.
/// Numbers are finite by construction; callers never have to interpret JSON null as zero.
nonisolated indirect enum HealthMdJSONValue: Codable, Equatable, Sendable {
    case null
    case string(String)
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case array([HealthMdJSONValue])
    case object([String: HealthMdJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(UInt64.self) { self = .unsignedInteger(value) }
        else if let value = try? container.decode(Double.self) {
            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            self = .number(value)
        } else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([HealthMdJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: HealthMdJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .string(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsignedInteger(let value): try container.encode(value)
        case .number(let value):
            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

nonisolated struct HealthMdCategoryValue: Codable, Equatable, Sendable {
    let identifier: String
    let display: String?
    let rawValue: Int64?

    init(identifier: String, display: String? = nil, rawValue: Int64? = nil) {
        self.identifier = identifier
        self.display = display
        self.rawValue = rawValue
    }
}

/// A compact, tagged health value. Floating-point values reject NaN and infinities.
nonisolated indirect enum HealthMdQueryValue: Equatable, Sendable {
    case quantity(value: Double, unit: String)
    case duration(seconds: Double)
    case count(Int64)
    case string(String)
    case category(HealthMdCategoryValue)
    case boolean(Bool)
    case timestamp(Date)
    /// An ISO `yyyy-MM-dd` calendar date, intentionally distinct from a timestamp.
    case date(String)
    case array([HealthMdQueryValue])
    /// A forward-compatible tagged value. The original tag and JSON-shaped payload survive decoding.
    case unknown(type: String, value: HealthMdJSONValue?)

    static func finiteQuantity(_ value: Double, unit: String) throws -> HealthMdQueryValue {
        guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
        return .quantity(value: value, unit: unit)
    }

    static func finiteDuration(seconds: Double) throws -> HealthMdQueryValue {
        guard seconds.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
        return .duration(seconds: seconds)
    }

    var finiteNumericValue: Double? {
        switch self {
        case .quantity(let value, _): return value.isFinite ? value : nil
        case .duration(let seconds): return seconds.isFinite ? seconds : nil
        case .count(let count): return Double(count)
        default: return nil
        }
    }

    var unit: String? {
        switch self {
        case .quantity(_, let unit): return unit
        case .duration: return "s"
        case .count: return "count"
        default: return nil
        }
    }
}

extension HealthMdQueryValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value, unit, seconds, identifier, display, rawValue = "raw_value" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "quantity":
            let value = try container.decode(Double.self, forKey: .value)
            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            self = .quantity(value: value, unit: try container.decode(String.self, forKey: .unit))
        case "duration":
            let seconds = try container.decode(Double.self, forKey: .seconds)
            guard seconds.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            self = .duration(seconds: seconds)
        case "count": self = .count(try container.decode(Int64.self, forKey: .value))
        case "string": self = .string(try container.decode(String.self, forKey: .value))
        case "category": self = .category(HealthMdCategoryValue(
            identifier: try container.decode(String.self, forKey: .identifier),
            display: try container.decodeIfPresent(String.self, forKey: .display),
            rawValue: try container.decodeIfPresent(Int64.self, forKey: .rawValue)
        ))
        case "boolean": self = .boolean(try container.decode(Bool.self, forKey: .value))
        case "timestamp": self = .timestamp(try container.decode(Date.self, forKey: .value))
        case "date": self = .date(try container.decode(String.self, forKey: .value))
        case "array": self = .array(try container.decode([HealthMdQueryValue].self, forKey: .value))
        default: self = .unknown(type: type, value: try container.decodeIfPresent(HealthMdJSONValue.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .quantity(let value, let unit):
            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            try container.encode("quantity", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encode(unit, forKey: .unit)
        case .duration(let seconds):
            guard seconds.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            try container.encode("duration", forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        case .count(let value):
            try container.encode("count", forKey: .type); try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode("string", forKey: .type); try container.encode(value, forKey: .value)
        case .category(let value):
            try container.encode("category", forKey: .type)
            try container.encode(value.identifier, forKey: .identifier)
            try container.encodeIfPresent(value.display, forKey: .display)
            try container.encodeIfPresent(value.rawValue, forKey: .rawValue)
        case .boolean(let value):
            try container.encode("boolean", forKey: .type); try container.encode(value, forKey: .value)
        case .timestamp(let value):
            try container.encode("timestamp", forKey: .type); try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type); try container.encode(value, forKey: .value)
        case .array(let value):
            try container.encode("array", forKey: .type); try container.encode(value, forKey: .value)
        case .unknown(let type, let value):
            try container.encode(type, forKey: .type); try container.encodeIfPresent(value, forKey: .value)
        }
    }
}

nonisolated enum HealthMdQueryContractError: Error, Equatable, Sendable {
    case nonFiniteNumber
    case invalidPageControls
    case invalidDateRange
    case invalidCursor
    case cursorDoesNotMatchQuery
    case staleCursor
    case singleItemExceedsPageBytes
    case unsupportedOperation
    case invalidAggregation(String)
    case scopeViolation(String)
}
