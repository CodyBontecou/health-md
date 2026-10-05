import Foundation
import CoreFoundation

/// One local persistence seam for native tolerant storage and strict setup transactions.
/// Presence of the envelope (even unreadable/wrong-typed) forbids legacy fallback.
/// These keys/versions are local storage, not the public Shared Setup grammar.
enum ExportProfilePersistence {
    static let legacyListKey = "exportProfiles.list"
    static let legacyActiveIDKey = "exportProfiles.activeProfileID"
    static let envelopeKey = "exportProfiles.v2.envelope"
    static let activeIDKey = "exportProfiles.v2.activeProfileID"

    struct Records {
        var profiles: [ExportProfile]
        var opaque: [Data]
    }

    static func hasEnvelope(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: envelopeKey) != nil
    }

    static func decode(_ data: Data, envelope: Bool) -> Records? {
        guard let records = recordObjects(data, envelope: envelope) else { return nil }
        var result = Records(profiles: [], opaque: [])
        for object in records {
            guard let bytes = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]
            ) else { return nil }
            guard let profile = try? JSONDecoder().decode(ExportProfile.self, from: bytes),
                  let encoded = try? JSONEncoder().encode(profile),
                  let known = try? JSONSerialization.jsonObject(with: encoded),
                  preservesKeys(object, known: known),
                  !result.profiles.contains(where: { $0.id == profile.id }) else {
                result.opaque.append(bytes)
                continue
            }
            result.profiles.append(profile)
        }
        return result
    }

    /// Transactions cannot prove preservation of opaque/corrupt/future records.
    static func transactionProfiles(_ data: Data?, envelope: Bool) throws -> [ExportProfile] {
        guard let data else { return [] }
        guard let records = decode(data, envelope: envelope), records.opaque.isEmpty else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        return records.profiles
    }

    static func encode(_ profiles: [ExportProfile], opaque: [Data] = [], envelope: Bool) throws -> Data {
        let objects = try profiles.map {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
        } + opaque.map {
            try JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed])
        }
        return try encodeObjects(objects, envelope: envelope)
    }

    /// Insert new records without reserializing any byte of the validated old
    /// array/envelope. String escapes and nested brackets cannot delimit records.
    static func appending<Record: Encodable>(_ profiles: [Record], to data: Data?, envelope: Bool) throws -> Data {
        let data = data ?? Data((envelope ? "{\"version\":2,\"records\":[]}" : "[]").utf8)
        guard let existing = recordObjects(data, envelope: envelope) else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        guard !profiles.isEmpty else { return data }
        var scanner = RawJSONScanner(bytes: Array(data))
        let end = try scanner.recordsArrayEnd(envelope: envelope)
        var insertion = Data()
        if !existing.isEmpty { insertion.append(0x2C) }
        let encoder = JSONEncoder()
        for (index, profile) in profiles.enumerated() {
            if index > 0 { insertion.append(0x2C) }
            insertion.append(try encoder.encode(profile))
        }
        var result = Data(data.prefix(end))
        result.append(insertion)
        result.append(data.suffix(from: end))
        return result
    }

    /// Used only after JSONSerialization has validated the complete grammar.
    /// This scanner finds the exact closing byte of the authoritative array.
    private struct RawJSONScanner {
        let bytes: [UInt8]
        var index = 0

        mutating func whitespace() {
            while index < bytes.count && [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func string() throws {
            guard index < bytes.count, bytes[index] == 0x22 else { throw SharedSetupV2TransactionError.invalidPersistedState }
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 0x22 { return }
                if byte == 0x5C { index += 1 }
            }
            throw SharedSetupV2TransactionError.invalidPersistedState
        }

        mutating func value() throws {
            whitespace()
            guard index < bytes.count else { throw SharedSetupV2TransactionError.invalidPersistedState }
            if bytes[index] == 0x22 { try string(); return }
            if bytes[index] == 0x5B || bytes[index] == 0x7B {
                // Iterative nesting avoids recursion on native persisted records.
                var depth = 0
                repeat {
                    guard index < bytes.count else { throw SharedSetupV2TransactionError.invalidPersistedState }
                    let byte = bytes[index]
                    if byte == 0x22 { try string(); continue }
                    if byte == 0x5B || byte == 0x7B { depth += 1 }
                    if byte == 0x5D || byte == 0x7D { depth -= 1 }
                    index += 1
                } while depth > 0
                return
            }
            while index < bytes.count && ![0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func recordsArrayEnd(envelope: Bool) throws -> Int {
            whitespace()
            if !envelope {
                guard index < bytes.count, bytes[index] == 0x5B else { throw SharedSetupV2TransactionError.invalidPersistedState }
                try value()
                return index - 1
            }
            index += 1 // validated root object
            var keys = Set<String>()
            var recordsEnd: Int?
            while index < bytes.count {
                whitespace()
                let start = index
                try string()
                let key = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                // JSONSerialization accepts duplicate keys. Never append into a
                // different array than the one it selected for admission.
                guard keys.insert(key).inserted else { throw SharedSetupV2TransactionError.invalidPersistedState }
                whitespace()
                index += 1 // colon
                whitespace()
                if key == "records" {
                    guard index < bytes.count, bytes[index] == 0x5B else { throw SharedSetupV2TransactionError.invalidPersistedState }
                    try value()
                    recordsEnd = index - 1
                } else {
                    try value()
                }
                whitespace()
                guard index < bytes.count else { throw SharedSetupV2TransactionError.invalidPersistedState }
                if bytes[index] == 0x7D, let recordsEnd { return recordsEnd }
                guard bytes[index] == 0x2C else { throw SharedSetupV2TransactionError.invalidPersistedState }
                index += 1
            }
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
    }

    private static func encodeObjects(_ records: [Any], envelope: Bool) throws -> Data {
        let root: Any = envelope ? ["version": 2, "records": records] : records
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func recordObjects(_ data: Data, envelope: Bool) -> [Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if !envelope { return object as? [Any] }
        guard let root = object as? [String: Any],
              Set(root.keys) == Set(["version", "records"]),
              let version = root["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: version.objCType)),
              version.intValue == 2 else { return nil }
        return root["records"] as? [Any]
    }

    /// Codable ignores unknown keys; doing so here would silently discard future
    /// destination/settings meaning. Missing optional known keys remain valid.
    static func preservesKeys(_ original: Any, known: Any, path: String = "") -> Bool {
        if let object = original as? [String: Any] {
            guard let known = known as? [String: Any] else { return false }
            // Recognized native migration/default-on fields are intentionally omitted
            // by today's encoder. Add retains their original record representation.
            let omitted: Set<String>
            switch path {
            case "":
                omitted = ["folderVaultID", "apiEndpointID", "googleDriveDestinationID"]
            case "settings":
                omitted = ["healthSubfolder", "includeDataDictionary", "appleExportEnginePin",
                           "calendarTimeZoneIdentifier", "archiveMarkdownExports",
                           "generateWeeklyRollups", "generateMonthlyRollups", "generateYearlyRollups"]
            default:
                omitted = []
            }
            guard Set(object.keys).isSubset(of: Set(known.keys).union(omitted)) else { return false }
            return object.allSatisfy { key, value in
                guard let counterpart = known[key] else { return omitted.contains(key) }
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                return preservesKeys(value, known: counterpart, path: childPath)
            }
        }
        if let array = original as? [Any], let known = known as? [Any], array.count == known.count {
            // Sets need not preserve encoder order; only object arrays have keys to prove.
            return zip(array, known).allSatisfy { preservesKeys($0, known: $1, path: path) }
        }
        return true
    }
}
