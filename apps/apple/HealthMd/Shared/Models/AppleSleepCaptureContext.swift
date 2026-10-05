import Foundation

/// Internal acquisition authority, independent of portable setup and public
/// export profiles. One value belongs to the entire operation, not one day.
nonisolated struct AppleSleepCaptureContext: Codable, Equatable, Sendable {
    static let pinned = TaskLocal<AppleSleepCaptureContext?>(wrappedValue: nil)

    let calendarTimeZoneIdentifier: String
    let sleepDayAttribution: SleepDayAttribution

    init(timeZone: TimeZone, sleepDayAttribution: SleepDayAttribution) {
        self.calendarTimeZoneIdentifier = timeZone.identifier
        self.sleepDayAttribution = sleepDayAttribution
    }

    var timeZone: TimeZone { TimeZone(identifier: calendarTimeZoneIdentifier)! }

    static func resolve(timeZone: TimeZone? = nil,
                        attribution: @autoclosure () -> SleepDayAttribution) -> Self {
        pinned.wrappedValue ?? Self(timeZone: timeZone ?? .current, sleepDayAttribution: attribution())
    }

    /// A missing durable authority is not permission to use today's preference.
    /// Retain the journal and require a separately requested new operation.
    static func recovered(_ context: Self?) throws -> Self {
        guard let context else { throw AvailabilityError.missingDurableAttribution }
        try context.requireShippedProfile()
        return context
    }

    func requireShippedProfile() throws {
        guard sleepDayAttribution.isAvailableForShippedProfiles else { throw AvailabilityError.unapprovedAttribution }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .calendarTimeZoneIdentifier)
        guard let zone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorruptedError(forKey: .calendarTimeZoneIdentifier, in: container,
                                                   debugDescription: "Invalid capture timezone")
        }
        self.init(timeZone: zone, sleepDayAttribution: try container.decode(SleepDayAttribution.self, forKey: .sleepDayAttribution))
    }

    enum AvailabilityError: Error, LocalizedError, Equatable {
        case unapprovedAttribution
        case missingDurableAttribution

        var errorDescription: String? {
            switch self {
            case .unapprovedAttribution:
                return String(localized: "Morning ends is unavailable for current export profiles. Choose Night begins for a new export.")
            case .missingDurableAttribution:
                return String(localized: "This pending export has no immutable sleep attribution context. It cannot resume; start a new export without changing the saved job.")
            }
        }
    }
}
