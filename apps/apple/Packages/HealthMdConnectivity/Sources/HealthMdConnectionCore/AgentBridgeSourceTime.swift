import Foundation

public enum AgentBridgeTimePrecision: String, Codable, Sendable {
    case sourceNanoseconds = "source_nanoseconds", sourceMilliseconds = "source_milliseconds", sourceSeconds = "source_seconds", sourceBinary64Seconds = "source_binary64_seconds"
}

/// Exact source epoch pair. Explicit null offset is part of the grammar; absent offset is invalid.
public struct AgentBridgeExactTime: Codable, Equatable, Sendable, BridgeValueCodable {
    public let epochSecond: Int64
    public let nanosecond: Int64
    public let sourceOffsetSeconds: Int64?
    public let precision: AgentBridgeTimePrecision
    public let sourceBinary64Bits: String?
    public init(epochSecond: Int64, nanosecond: Int64, sourceOffsetSeconds: Int64?, precision: AgentBridgeTimePrecision, sourceBinary64Bits: String? = nil) throws {
        self.epochSecond = epochSecond; self.nanosecond = nanosecond; self.sourceOffsetSeconds = sourceOffsetSeconds; self.precision = precision; self.sourceBinary64Bits = sourceBinary64Bits
        try validate()
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["epoch_second", "nanosecond", "source_offset_seconds", "precision"], optional: ["source_binary64_bits"])
        epochSecond = try o.int("epoch_second", min: -62_135_596_800, max: 253_402_300_799)
        nanosecond = try o.int("nanosecond", min: 0, max: 999_999_999)
        sourceOffsetSeconds = try o.node("source_offset_seconds") == .null ? nil : o.int("source_offset_seconds", min: -64_800, max: 64_800)
        precision = try o.token("precision"); sourceBinary64Bits = try o.optionalText("source_binary64_bits", min: 16, max: 16)
        try validate()
    }
    var bridgeJSON: BridgeJSON { .object([("epoch_second", .int(epochSecond)), ("nanosecond", .int(nanosecond)), ("source_offset_seconds", sourceOffsetSeconds.map(BridgeJSON.int) ?? .null), ("precision", .string(precision.rawValue)), ("source_binary64_bits", sourceBinary64Bits.map(BridgeJSON.string))]) }
    private func validate() throws {
        guard (-62_135_596_800...253_402_300_799).contains(epochSecond), (0...999_999_999).contains(nanosecond), sourceOffsetSeconds.map({ (-64_800...64_800).contains($0) }) ?? true else { throw AgentBridgeValidationError.invalidRequest }
        if precision == .sourceBinary64Seconds {
            guard let text = sourceBinary64Bits else { throw AgentBridgeValidationError.invalidRequest }
            try bridgePattern(text, "\\A[0-9a-f]{16}\\z", max: 16)
            guard let bits = UInt64(text, radix: 16) else { throw AgentBridgeValidationError.invalidRequest }
            let pair = try Self.pair(bits)
            guard epochSecond == pair.0, nanosecond == pair.1 else { throw AgentBridgeValidationError.invalidRequest }
        } else {
            guard sourceBinary64Bits == nil else { throw AgentBridgeValidationError.invalidRequest }
            if precision == .sourceMilliseconds, nanosecond % 1_000_000 != 0 { throw AgentBridgeValidationError.invalidRequest }
            if precision == .sourceSeconds, nanosecond != 0 { throw AgentBridgeValidationError.invalidRequest }
        }
    }
    public static func binary64(bitPattern: UInt64, sourceOffsetSeconds: Int64? = nil) throws -> Self {
        let pair = try pair(bitPattern)
        return try .init(epochSecond: pair.0, nanosecond: pair.1, sourceOffsetSeconds: sourceOffsetSeconds, precision: .sourceBinary64Seconds, sourceBinary64Bits: String(format: "%016llx", bitPattern))
    }
    private static func pair(_ bits: UInt64) throws -> (Int64, Int64) {
        let source = Double(bitPattern: bits)
        // Only a coarse bound uses Double; the nanosecond result below uses the exact dyadic bits.
        guard source.isFinite, source >= -62_135_596_801, source < 253_402_300_800 else { throw AgentBridgeValidationError.invalidRequest }
        let negative = bits >> 63 != 0
        let exponent = Int((bits >> 52) & 0x7ff)
        let mantissa = (bits & 0x000f_ffff_ffff_ffff) | (exponent == 0 ? 0 : 1 << 52)
        let shift = exponent == 0 ? 1074 : 1075 - exponent
        let integral: UInt64
        let fraction: UInt64
        if shift <= 0 { integral = mantissa << (-shift); fraction = 0 }
        else if shift >= 64 { integral = 0; fraction = mantissa }
        else { integral = mantissa >> shift; fraction = mantissa & ((1 << shift) - 1) }
        let fractionalNanos = roundedFraction(fraction, shift: max(shift, 1))
        var seconds: Int64
        var nanos: Int64
        if negative, fraction != 0 {
            seconds = -Int64(integral) - 1; nanos = 1_000_000_000 - Int64(fractionalNanos)
        } else { seconds = negative ? -Int64(integral) : Int64(integral); nanos = Int64(fractionalNanos) }
        if nanos == 1_000_000_000 { seconds += 1; nanos = 0 }
        guard (-62_135_596_800...253_402_300_799).contains(seconds) else { throw AgentBridgeValidationError.invalidRequest }
        return (seconds, nanos)
    }
    private static func roundedFraction(_ fraction: UInt64, shift: Int) -> UInt64 {
        guard fraction != 0, shift < 128 else { return 0 }
        let product = fraction.multipliedFullWidth(by: 1_000_000_000)
        let quotient: UInt64
        if shift < 64 { quotient = (product.low >> shift) | (product.high << (64 - shift)) }
        else { quotient = product.high >> (shift - 64) }
        let halfIndex = shift - 1
        let half: Bool
        let lower: Bool
        if halfIndex < 64 {
            half = product.low & (1 << halfIndex) != 0
            lower = product.low & ((1 << halfIndex) - 1) != 0
        } else {
            half = product.high & (1 << (halfIndex - 64)) != 0
            lower = product.low != 0 || product.high & ((1 << (halfIndex - 64)) - 1) != 0
        }
        return quotient + (half && (lower || quotient & 1 != 0) ? 1 : 0)
    }
}
