import Foundation

/// Destination behavior for an independently negotiated capture-scoped note.
/// This value never establishes source authority without the accepted job and patch.
public struct DirectScopedDailyNotePolicy: Codable, Equatable, Sendable {
    public let version: Int
    public let recordProfile: String
    public let ownerDate: String
    public let calendarTimezone: String
    public let createIfMissing: Bool
    public let injectSections: Bool

    public enum ValidationError: Error { case invalidPolicy }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case recordProfile = "record_profile"
        case ownerDate = "owner_date"
        case calendarTimezone = "calendar_timezone"
        case createIfMissing = "create_if_missing"
        case injectSections = "inject_sections"
    }

    public init(version: Int = 1, recordProfile: String, ownerDate: String,
                calendarTimezone: String, createIfMissing: Bool, injectSections: Bool) throws {
        guard version == 1,
              ["apple-v8", "apple-v11", "android-frozen-v4", "android-analytical-v5", "android-sleep-v6"].contains(recordProfile),
              Self.validOwnerDate(ownerDate),
              calendarTimezone.utf8.count <= 128,
              calendarTimezone == "UTC" || calendarTimezone == "GMT"
                || TimeZone.knownTimeZoneIdentifiers.contains(calendarTimezone) else {
            throw ValidationError.invalidPolicy
        }
        self.version = version
        self.recordProfile = recordProfile
        self.ownerDate = ownerDate
        self.calendarTimezone = calendarTimezone
        self.createIfMissing = createIfMissing
        self.injectSections = injectSections
    }

    public init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: PolicyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard all.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ValidationError.invalidPolicy
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(version: values.decode(Int.self, forKey: .version),
            recordProfile: values.decode(String.self, forKey: .recordProfile),
            ownerDate: values.decode(String.self, forKey: .ownerDate),
            calendarTimezone: values.decode(String.self, forKey: .calendarTimezone),
            createIfMissing: values.decode(Bool.self, forKey: .createIfMissing),
            injectSections: values.decode(Bool.self, forKey: .injectSections))
    }

    private static func validOwnerDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in index == 4 || index == 7 || (48...57).contains(byte) }),
              let year = Int(value.prefix(4)), year > 0,
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)) else { return false }
        guard (1...12).contains(month), day > 0 else { return false }
        let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= lengths[month - 1]
    }
}

private struct PolicyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
