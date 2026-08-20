import XCTest
@testable import HealthMd

final class PendingExportRequestTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation state that
    // is unsafe during test teardown on some macOS runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        suiteName = "PendingExportRequestTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStoreReloadsRequestWithMultipleDates() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            dates: [
                date(year: 2026, month: 5, day: 12, hour: 9),
                date(year: 2026, month: 5, day: 13, hour: 18)
            ],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 14, hour: 10)
        )

        try store.upsert(request)

        let reloadedStore = PendingExportStore(userDefaults: defaults)
        XCTAssertEqual(try reloadedStore.loadAll(), [request])
    }

    func testRequestNormalizesDatesToStartOfDayAndSortedOrder() {
        let late = date(year: 2026, month: 5, day: 14, hour: 23, minute: 45)
        let early = date(year: 2026, month: 5, day: 13, hour: 6, minute: 15)

        let request = PendingExportRequest(
            dates: [late, early, late],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )

        XCTAssertEqual(request.dates, [
            calendar.startOfDay(for: early),
            calendar.startOfDay(for: late)
        ])
    }

    func testDecodingPreservesPersistedDatesWithoutRenormalizing() throws {
        let persistedDate = date(year: 2026, month: 5, day: 14, hour: 16, minute: 45)
        let payload = RawPendingExportRequestPayload(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            dates: [persistedDate],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 7),
            notificationMetadata: ["notification": "pending"]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PendingExportRequest.self, from: data)

        XCTAssertEqual(decoded.dates, [persistedDate])
        XCTAssertNil(decoded.exportTarget)
        XCTAssertNil(decoded.settingsSnapshot)
        XCTAssertTrue(decoded.usesLegacyMutableSettings)
    }

    func testScheduledRequestRoundTripsFrozenSettingsAndPin() throws {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let pin = try makeSyntheticAppleExportEnginePin()
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )
        let request = PendingExportRequest(
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            settingsSnapshot: snapshot
        )

        let decoded = try JSONDecoder().decode(
            PendingExportRequest.self,
            from: JSONEncoder().encode(request)
        )

        XCTAssertEqual(decoded.settingsSnapshot, snapshot)
        XCTAssertEqual(decoded.settingsSnapshot?.appleExportEnginePin, pin)
        XCTAssertFalse(decoded.usesLegacyMutableSettings)
    }

    func testScheduledRequestCanPersistExportTarget() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8),
            exportTarget: .apiEndpoint
        )

        try store.upsert(request)

        let reloaded = try PendingExportStore(userDefaults: defaults).loadAll()
        XCTAssertEqual(reloaded, [request])
        XCTAssertEqual(try XCTUnwrap(reloaded.first).exportTarget, .apiEndpoint)
    }

    func testReplacingSameScheduledOccurrenceDoesNotDuplicatePendingWork() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let fireDate = date(year: 2026, month: 5, day: 15, hour: 8)

        let first = PendingExportRequest(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let replacement = PendingExportRequest(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            dates: [date(year: 2026, month: 5, day: 13, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8, minute: 1)
        )

        try store.upsert(first)
        try store.upsert(replacement)

        XCTAssertEqual(try store.loadAll(), [replacement])
    }

    /// Same-minute replacement identity is per profile: two profiles (or a
    /// profile and the legacy schedule) firing at the same minute must
    /// coexist, and one profile's preserved retry must not be clobbered by
    /// another profile's (or the legacy schedule's) arming upsert. A clobbered
    /// request's stable-ID recovery notification would become a dead tap.
    func testSameMinuteScheduledRequestsAcrossProfilesAndLegacyCoexist() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let fireDate = date(year: 2026, month: 5, day: 15, hour: 8)
        let profileA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let profileB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        let legacy = PendingExportRequest(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let entryA = PendingExportRequest(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8),
            profileID: profileA,
            profileName: "A"
        )
        let preservedA = PendingExportRequest(
            id: entryA.id,
            dates: [date(year: 2026, month: 5, day: 15, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: entryA.createdAt,
            profileID: profileA,
            profileName: "A",
            attemptedAt: date(year: 2026, month: 5, day: 15, hour: 8, minute: 10)
        )
        let entryB = PendingExportRequest(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8),
            profileID: profileB,
            profileName: "B"
        )

        try store.upsert(legacy)
        try store.upsert(entryA)
        try store.upsert(entryB)
        try store.upsert(preservedA)
        let legacyRearm = PendingExportRequest(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            dates: legacy.dates,
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: legacy.createdAt
        )
        try store.upsert(legacyRearm)

        let stored = try store.loadAll()
        let ids = Set(stored.map(\.id))
        XCTAssertTrue(ids.contains(preservedA.id), "profile A's preserved retry must survive profile B's and legacy's same-minute upserts")
        XCTAssertTrue(ids.contains(entryB.id), "profile B's request must survive legacy's same-minute upsert")
        XCTAssertEqual(
            stored.count, 3,
            "legacy (replaced by its re-arm), profile A's retry, and profile B coexist"
        )
        XCTAssertTrue(ids.contains(legacyRearm.id), "the legacy re-arm replaced only the legacy request")
        XCTAssertEqual(
            try XCTUnwrap(stored.first { $0.id == preservedA.id }).attemptedAt,
            preservedA.attemptedAt
        )
    }

    func testAttemptedMarkerRoundTripsThroughPersistence() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let attemptedAt = date(year: 2026, month: 5, day: 15, hour: 8, minute: 30)
        let request = PendingExportRequest(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8),
            attemptedAt: attemptedAt
        )

        try store.upsert(request)

        XCTAssertEqual(
            try PendingExportStore(userDefaults: defaults).loadAll().first?.attemptedAt,
            attemptedAt
        )

        // A pre-marker persisted payload (no attemptedAt key) decodes as
        // never-attempted; the fallback-window heuristic classifies those.
        let encoded = try JSONEncoder().encode([request.markingAttempted(at: attemptedAt)])
        var payload = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        payload[0].removeValue(forKey: "attemptedAt")
        let legacy = try JSONDecoder().decode(
            [PendingExportRequest].self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertNil(legacy[0].attemptedAt)
    }

    func testReplacingSameShortcutDatesDoesNotDuplicatePendingWork() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let shortcutDates = [
            date(year: 2026, month: 5, day: 13, hour: 7),
            date(year: 2026, month: 5, day: 14, hour: 7)
        ]

        let first = PendingExportRequest(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            dates: shortcutDates,
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let replacement = PendingExportRequest(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            dates: shortcutDates.reversed(),
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8, minute: 1)
        )

        try store.upsert(first)
        try store.upsert(replacement)

        XCTAssertEqual(try store.loadAll(), [replacement])
    }

    func testRemovingOneRequestPreservesOtherRequests() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let scheduled = PendingExportRequest(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 15, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )
        let shortcut = PendingExportRequest(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            dates: [date(year: 2026, month: 5, day: 13, hour: 7)],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 9)
        )

        try store.upsert(scheduled)
        try store.upsert(shortcut)
        try store.remove(id: scheduled.id)

        XCTAssertEqual(try store.loadAll(), [shortcut])
    }

    func testClearCompletedRequestsRemovesOnlyCompletedIDs() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let completed = PendingExportRequest(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            dates: [date(year: 2026, month: 5, day: 12, hour: 7)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 5, day: 13, hour: 8),
            createdAt: date(year: 2026, month: 5, day: 13, hour: 8)
        )
        let pending = PendingExportRequest(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 8)
        )

        try store.upsert(completed)
        try store.upsert(pending)
        try store.clearCompletedRequests(ids: [completed.id])

        XCTAssertEqual(try store.loadAll(), [pending])
    }

    func testCorruptPersistedDataFailsSafelyWithoutCrashing() throws {
        defaults.set(Data("not-json".utf8), forKey: PendingExportStore.storageKey)

        let store = PendingExportStore(userDefaults: defaults)

        XCTAssertEqual(try store.loadAll(), [])
    }

    func testNotificationIdentifierIsDeterministicForRequest() {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)],
            source: .shortcut,
            createdAt: date(year: 2026, month: 5, day: 15, hour: 9)
        )

        XCTAssertEqual(
            store.notificationIdentifier(for: request),
            "healthmd.pending-export.66666666-6666-6666-6666-666666666666"
        )
    }

    private struct RawPendingExportRequestPayload: Encodable {
        let id: UUID
        let dates: [Date]
        let source: PendingExportSource
        let scheduledFireDate: Date?
        let createdAt: Date
        let notificationMetadata: [String: String]
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
