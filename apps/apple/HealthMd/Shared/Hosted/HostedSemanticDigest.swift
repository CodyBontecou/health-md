import CoreFoundation
import CryptoKit
import Foundation

nonisolated enum HostedSemanticDigestError: Error, Equatable {
  case invalidValue
}

/// A cross-language digest for parsed JSON values. Unlike serialized JSON text,
/// this representation is insensitive to Foundation/serde decimal formatting
/// while preserving array order, object keys, strings, booleans, nulls, and the
/// parsed integer-versus-floating-point number kind. Finite floating-point values
/// use their normalized IEEE-754 binary64 bit pattern, so equivalent exponent and
/// decimal spellings have one representation on every implementation.
nonisolated enum HostedSemanticDigest {
  private static let domain = Data("healthmd.hosted.semantic-json-digest.v1\0".utf8)

  static func sha256<Value: Encodable>(of value: Value) throws -> String {
    let encoded = try HealthMdQueryCanonicalSerializer.data(for: value)
    let object = try JSONSerialization.jsonObject(
      with: encoded,
      options: [.fragmentsAllowed]
    )
    var canonical = domain
    try append(object, to: &canonical)
    return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
  }

  private static func append(_ value: Any, to output: inout Data) throws {
    if value is NSNull {
      output.append(0)
      return
    }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        output.append(number.boolValue ? 2 : 1)
        return
      }
      output.append(3)
      let representation: String
      let decimal = number.stringValue
      if CFNumberIsFloatType(number)
        || (Int64(decimal) == nil && UInt64(decimal) == nil)
      {
        let double = number.doubleValue
        guard double.isFinite else { throw HostedSemanticDigestError.invalidValue }
        representation = normalizedFloatingPoint(double)
      } else {
        representation = decimal
      }
      appendBytes(Data(representation.utf8), to: &output)
      return
    }
    if let string = value as? String {
      output.append(4)
      appendBytes(Data(string.utf8), to: &output)
      return
    }
    if let values = value as? [Any] {
      output.append(5)
      appendLength(values.count, to: &output)
      for item in values { try append(item, to: &output) }
      return
    }
    if let values = value as? [String: Any] {
      output.append(6)
      let keys = values.keys.sorted { lhs, rhs in
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
      }
      appendLength(keys.count, to: &output)
      for key in keys {
        appendBytes(Data(key.utf8), to: &output)
        guard let item = values[key] else {
          throw HostedSemanticDigestError.invalidValue
        }
        try append(item, to: &output)
      }
      return
    }
    throw HostedSemanticDigestError.invalidValue
  }

  private static func normalizedFloatingPoint(_ value: Double) -> String {
    if value == 0 { return "0" }
    return String(format: "%016llx", value.bitPattern)
  }

  private static func appendBytes(_ bytes: Data, to output: inout Data) {
    appendLength(bytes.count, to: &output)
    output.append(bytes)
  }

  private static func appendLength(_ value: Int, to output: inout Data) {
    var length = UInt64(value).bigEndian
    withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
  }
}
