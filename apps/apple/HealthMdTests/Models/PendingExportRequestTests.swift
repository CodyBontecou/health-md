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

    func testUnsupportedSavedAuthorityNeverBecomesAnEmptyStoreOrGetsOverwritten() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(dates: [Date(timeIntervalSince1970: 1_793_505_600)], source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: TimeZone(identifier: "UTC")!, sleepDayAttribution: .nightBegins))
        try store.upsert(request)
        let initial = try XCTUnwrap(defaults.data(forKey: PendingExportStore.storageKey))
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: initial) as? [[String: Any]])
        var context = try XCTUnwrap(records[0]["sleepCaptureContext"] as? [String: Any])
        context["exportProfileID"] = "apple-v99"
        records[0]["sleepCaptureContext"] = context
        let unreadable = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
        defaults.set(unreadable, forKey: PendingExportStore.storageKey)
        XCTAssertThrowsError(try store.loadAll(), "Unsupported authority must not masquerade as an empty journal") {
            XCTAssertEqual($0 as? PendingExportStoreError, .unreadableJournal)
            XCTAssertFalse($0.localizedDescription.contains("apple-v99"))
        }
        let mutations: [() throws -> Void] = [
            { try store.upsert(PendingExportRequest(dates: [Date()], source: .shortcut)) },
            { try store.remove(id: request.id) },
            { try store.clearCompletedRequests(ids: [request.id]) },
        ]
        for mutation in mutations {
            defaults.set(unreadable, forKey: PendingExportStore.storageKey)
            XCTAssertThrowsError(try mutation())
            XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), unreadable)
        }
    }

    func testWakeDateJobSurvivesAnOlderWriterReplacingTheHistoricalQueue() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(
            dates: [date(year: 2026, month: 5, day: 14, hour: 7)], source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds),
            calendar: calendar
        )
        try store.upsert(request)
        // A downgraded binary knows only the original array key. Its empty-queue
        // fallback/new save must not erase a job whose ownership it cannot understand.
        defaults.set(Data("[]".utf8), forKey: PendingExportStore.storageKey)
        XCTAssertEqual(try PendingExportStore(userDefaults: defaults).loadAll(), [request])
    }

    func testDifferentAttributionsCoexistWithoutRewritingHistoricalQueueBytes() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let ownerDates = [date(year: 2026, month: 5, day: 14, hour: 7)]
        let night = PendingExportRequest(dates: ownerDates, source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .nightBegins),
            calendar: calendar)
        let morning = PendingExportRequest(dates: ownerDates, source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds),
            calendar: calendar)
        try store.upsert(night)
        let original = try XCTUnwrap(defaults.data(forKey: PendingExportStore.storageKey))
        try store.upsert(morning)
        XCTAssertEqual(Set(try store.loadAll().map(\.id)), Set([night.id, morning.id]))
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), original)
        try store.remove(id: morning.id)
        XCTAssertEqual(try store.loadAll(), [night])
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), original)
    }

    func testUnsupportedSuccessorJournalPreservesBothQueuesOnEveryMutation() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let night = PendingExportRequest(dates: [Date()], source: .shortcut)
        let morning = PendingExportRequest(dates: [Date()], source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds))
        try store.upsert(night)
        try store.upsert(morning)
        let originalNight = try XCTUnwrap(defaults.data(forKey: PendingExportStore.storageKey))
        let originalMorning = try XCTUnwrap(defaults.data(forKey: PendingExportStore.successorStorageKey))
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: originalMorning) as? [String: Any])
        future["version"] = 99
        let futureBytes = try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
        defaults.set(futureBytes, forKey: PendingExportStore.successorStorageKey)
        XCTAssertThrowsError(try store.loadAll()) {
            XCTAssertEqual($0 as? PendingExportStoreError, .unreadableJournal)
        }
        let mutations: [() throws -> Void] = [
            { try store.upsert(night) }, { try store.remove(id: morning.id) },
            { try store.clearCompletedRequests(ids: [night.id, morning.id]) },
        ]
        for mutation in mutations {
            XCTAssertThrowsError(try mutation())
            XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), originalNight)
            XCTAssertEqual(defaults.data(forKey: PendingExportStore.successorStorageKey), futureBytes)
        }
    }

    func testAnExistingJobCannotChangeItsAttributionOrCapturedClock() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let initial = PendingExportRequest(dates: [Date()], source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds),
            calendar: calendar)
        try store.upsert(initial)
        let original = try XCTUnwrap(defaults.data(forKey: PendingExportStore.successorStorageKey))
        let alternatives = [
            AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .nightBegins),
            AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Pacific/Honolulu")!, sleepDayAttribution: .morningEnds),
        ]
        for context in alternatives {
            let changed = PendingExportRequest(id: initial.id, dates: initial.dates, source: .shortcut,
                sleepCaptureContext: context, calendar: calendar)
            XCTAssertThrowsError(try store.upsert(changed)) {
                XCTAssertEqual($0 as? PendingExportStoreError, .incompatibleRequestAuthority)
            }
            XCTAssertEqual(try store.loadAll(), [initial])
            XCTAssertEqual(defaults.data(forKey: PendingExportStore.successorStorageKey), original)
            XCTAssertNil(defaults.object(forKey: PendingExportStore.storageKey))
        }
    }

    func testAlreadyPersistedDraftJobIsNotMovedOrUpgradedToTheNewNamespace() throws {
        let request = PendingExportRequest(dates: [Date()], source: .scheduled,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds))
        let bytes = try JSONEncoder().encode([request])
        defaults.set(bytes, forKey: PendingExportStore.storageKey)
        let store = PendingExportStore(userDefaults: defaults)
        XCTAssertEqual(try store.loadAll(), [request])
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), bytes)
        XCTAssertThrowsError(try request.recoveredSleepCaptureContext())
        let retry = request.markingAttempted(at: Date())
        try store.upsert(retry)
        XCTAssertEqual(try store.loadAll(), [retry])
        XCTAssertNil(defaults.object(forKey: PendingExportStore.successorStorageKey))
    }

    func testDuplicateIdentityAcrossQueuesRejectsMutationWithoutChoosingAProfile() throws {
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(dates: [Date()], source: .shortcut,
            sleepCaptureContext: AppleSleepCaptureContext(timeZone: calendar.timeZone, sleepDayAttribution: .morningEnds))
        try store.upsert(request)
        let original = try XCTUnwrap(defaults.data(forKey: PendingExportStore.successorStorageKey))
        let duplicate = try JSONEncoder().encode([request])
        defaults.set(duplicate, forKey: PendingExportStore.storageKey)
        XCTAssertThrowsError(try store.loadAll())
        XCTAssertThrowsError(try store.remove(id: request.id))
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), duplicate)
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.successorStorageKey), original)
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

    func testInitializerPreservesOriginalOwnerDatesInFrozenTimezone() throws {
        var originalCalendar = Calendar(identifier: .gregorian)
        originalCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var retryCalendar = Calendar(identifier: .gregorian)
        retryCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let originalOwnerDay = try XCTUnwrap(originalCalendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 14
        )))

        let request = PendingExportRequest(
            dates: [originalOwnerDay.addingTimeInterval(86_400)],
            originalRequestedDates: [originalOwnerDay],
            originalCalendarTimeZoneIdentifier: originalCalendar.timeZone.identifier,
            source: .scheduled,
            calendar: retryCalendar
        )

        XCTAssertEqual(request.originalRequestedDates, [originalOwnerDay])
        XCTAssertEqual(request.originalCalendarTimeZoneIdentifier, "America/Los_Angeles")
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
        XCTAssertEqual(decoded.originalRequestedDates, [persistedDate])
        XCTAssertNil(decoded.originalCalendarTimeZoneIdentifier)
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
        XCTAssertEqual(decoded.originalRequestedDates, request.originalRequestedDates)
        XCTAssertEqual(decoded.originalCalendarTimeZoneIdentifier, "America/Los_Angeles")
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

    func testAbsentJournalIsEmptyButUnexpectedStoredTypeCannotBeReplaced() throws {
        let store = PendingExportStore(userDefaults: defaults)
        XCTAssertEqual(try store.loadAll(), [])
        defaults.set("unsupported-storage-value", forKey: PendingExportStore.storageKey)
        XCTAssertThrowsError(try store.loadAll()) {
            XCTAssertEqual($0 as? PendingExportStoreError, .unreadableJournal)
        }
        XCTAssertThrowsError(try store.upsert(PendingExportRequest(dates: [Date()], source: .shortcut)))
        XCTAssertEqual(defaults.string(forKey: PendingExportStore.storageKey), "unsupported-storage-value")
    }

    func testCorruptPersistedDataFailsSafelyWithoutCrashing() throws {
        defaults.set(Data("not-json".utf8), forKey: PendingExportStore.storageKey)

        let store = PendingExportStore(userDefaults: defaults)

        XCTAssertThrowsError(try store.loadAll()) {
            XCTAssertEqual($0 as? PendingExportStoreError, .unreadableJournal)
        }
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), Data("not-json".utf8))
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
