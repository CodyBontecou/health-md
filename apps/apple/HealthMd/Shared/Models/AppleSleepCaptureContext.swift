import Foundation

/// Internal acquisition authority, excluded from portable setup. The explicit
/// successor discriminator prevents draft jobs from gaining approval on upgrade.
/// One value belongs to the entire operation, not one day.
nonisolated struct AppleSleepCaptureContext: Codable, Equatable, Sendable {
    static let pinned = TaskLocal<AppleSleepCaptureContext?>(wrappedValue: nil)

    let calendarTimeZoneIdentifier: String
    let sleepDayAttribution: SleepDayAttribution
    /// Explicit authority for new wake-date operations. Historical night contexts
    /// omit this field; decoding a draft-era morning context must not invent it.
    let exportProfileID: String?

    init(timeZone: TimeZone, sleepDayAttribution: SleepDayAttribution) {
        self.calendarTimeZoneIdentifier = timeZone.identifier
        self.sleepDayAttribution = sleepDayAttribution
        self.exportProfileID = sleepDayAttribution == .morningEnds ? "apple-v11" : nil
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
        if sleepDayAttribution == .morningEnds && exportProfileID != "apple-v11" {
            throw AvailabilityError.unversionedAttribution
        }
        guard sleepDayAttribution.isAvailableForShippedProfiles else { throw AvailabilityError.unapprovedAttribution }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .calendarTimeZoneIdentifier)
        guard let zone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorruptedError(forKey: .calendarTimeZoneIdentifier, in: container,
                                                   debugDescription: "Invalid capture timezone")
        }
        self.calendarTimeZoneIdentifier = zone.identifier
        self.sleepDayAttribution = try container.decode(SleepDayAttribution.self, forKey: .sleepDayAttribution)
        self.exportProfileID = try container.decodeIfPresent(String.self, forKey: .exportProfileID)
        if let profile = exportProfileID {
            let expected = sleepDayAttribution == .morningEnds ? "apple-v11" : "apple-v8"
            guard profile == expected || (sleepDayAttribution == .morningEnds && profile == "apple-v10") else {
                throw DecodingError.dataCorruptedError(forKey: .exportProfileID, in: container,
                                                       debugDescription: "Invalid capture export profile")
            }
        }
    }

    enum AvailabilityError: Error, LocalizedError, Equatable {
        case unapprovedAttribution
        case unversionedAttribution
        case missingDurableAttribution

        var errorDescription: String? {
            switch self {
            case .unapprovedAttribution:
                return String(localized: "Morning ends is unavailable for current export profiles. Choose Night begins for a new export.")
            case .unversionedAttribution:
                return String(localized: "This saved sleep attribution has no supported export profile. It cannot resume; start a new export without changing the saved job.")
            case .missingDurableAttribution:
                return String(localized: "This pending export has no immutable sleep attribution context. It cannot resume; start a new export without changing the saved job.")
            }
        }
    }
}
