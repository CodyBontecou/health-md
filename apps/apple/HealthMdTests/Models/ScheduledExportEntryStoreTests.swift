import XCTest
@testable import HealthMd

final class ScheduledExportEntryStoreTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: MainActor-isolated deinits take the
    // back-deployed task path on older runtimes (CI's iOS 26.2 simulator)
    // where nested store release aborts; retain for the process lifetime.
    private static var retainedStores: [AnyObject] = []
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var calendar: Calendar!
    private var fixedNow: Date!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ScheduledExportEntryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        fixedNow = makeDate(year: 2026, month: 8, day: 10, hour: 12)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        calendar = nil
        fixedNow = nil
        super.tearDown()
    }

    private func makeStore() -> ScheduledExportEntryStore {
        let store = ScheduledExportEntryStore(userDefaults: defaults, now: { self.fixedNow })
        Self.retainedStores.append(store)
        return store
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute
            )
        )!
    }

    private func makeEntry(
        profileID: UUID = UUID(),
        enabled: Bool = true,
        configure: (inout ScheduledExportEntry) -> Void = { _ in }
    ) -> ScheduledExportEntry {
        var entry = ScheduledExportEntry(
            profileID: profileID,
            isEnabled: enabled
        )
        configure(&entry)
        return entry
    }

    // MARK: - Bounds and per-profile uniqueness

    func testUpsertEnforcesMaximumBound() {
        let store = makeStore()

        for index in 0..<ScheduledExportEntryStore.maximumScheduledEntries {
            let entry = makeEntry(profileID: UUID())
            XCTAssertTrue(store.upsert(entry), "entry \(index) should fit")
        }
        XCTAssertEqual(store.entries.count, ScheduledExportEntryStore.maximumScheduledEntries)

        // Beyond the bound: rejected for a new profile…
        XCTAssertFalse(store.upsert(makeEntry(profileID: UUID())))

        // …but replacing an existing profile's entry still works.
        let existingProfileID = store.entries[0].profileID
        XCTAssertTrue(store.upsert(makeEntry(profileID: existingProfileID)))
        XCTAssertEqual(store.entries.count, ScheduledExportEntryStore.maximumScheduledEntries)
    }

    func testUpsertReplacesEntryForSameProfile() {
        let store = makeStore()
        let profileID = UUID()

        store.upsert(
            makeEntry(profileID: profileID) { $0.preferredHour = 8; $0.lookbackDays = 1 }
        )
        store.upsert(
            makeEntry(profileID: profileID) { $0.preferredHour = 20; $0.lookbackDays = 7 }
        )

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entry(profileID: profileID)?.preferredHour, 20)
        XCTAssertEqual(store.entry(profileID: profileID)?.lookbackDays, 7)
    }

    func testPersistenceRoundTrip() {
        let first = makeStore()
        let idA = UUID()
        first.upsert(makeEntry(profileID: idA) { $0.frequency = .weekly; $0.weekday = 3 })
        first.upsert(
            makeEntry(profileID: UUID()) {
                $0.frequency = .custom
                $0.customInterval = 2
                $0.customUnit = .week
            }
        )

        let second = ScheduledExportEntryStore(userDefaults: defaults, now: { self.fixedNow }); Self.retainedStores.append(second)
        XCTAssertEqual(second.entries, first.entries)
        XCTAssertEqual(second.entry(profileID: idA)?.weekday, 3)
    }

    func testCorruptedDataStartsEmpty() {
        defaults.set(Data("garbage".utf8), forKey: "scheduledExportEntries.list")
        let reloaded = makeStore(); Self.retainedStores.append(reloaded); XCTAssertTrue(reloaded.entries.isEmpty)
    }

    func testDeleteAndRecordSuccess() {
        let store = makeStore()
        let profileID = UUID()
        store.upsert(makeEntry(profileID: profileID))
        let occurrence = makeDate(year: 2026, month: 8, day: 10, hour: 8)

        XCTAssertTrue(store.recordSuccess(profileID: profileID, kind: .completedDay, occurrenceDate: occurrence))
        XCTAssertEqual(store.entry(profileID: profileID)?.lastExportDate, occurrence)

        let refreshOccurrence = makeDate(year: 2026, month: 8, day: 10, hour: 14)
        XCTAssertTrue(store.recordSuccess(profileID: profileID, kind: .todayRefresh, occurrenceDate: refreshOccurrence))
        XCTAssertEqual(store.entry(profileID: profileID)?.lastTodayRefreshDate, refreshOccurrence)

        XCTAssertTrue(store.delete(profileID: profileID))
        XCTAssertFalse(store.delete(profileID: profileID))
        XCTAssertFalse(store.recordSuccess(profileID: profileID, kind: .completedDay, occurrenceDate: occurrence))
    }

    // MARK: - Legacy migration

    func testLegacyScheduleMigratesOnceIntoDefaultProfileEntry() {
        let store = makeStore()
        let defaultProfileID = UUID()
        var legacy = ExportSchedule(isEnabled: true)
        legacy.frequency = .weekly
        legacy.weekday = 2
        legacy.lookbackDays = 7
        legacy.preferredHour = 7
        legacy.preferredMinute = 30
        legacy.todayRefreshEnabled = true
        legacy.lastExportDate = makeDate(year: 2026, month: 8, day: 4, hour: 7, minute: 30)

        XCTAssertTrue(store.migrateLegacyScheduleIfNeeded(legacy: legacy, defaultProfileID: defaultProfileID))

        let entry = store.entry(profileID: defaultProfileID)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry?.isEnabled ?? false)
        XCTAssertEqual(entry?.frequency, .weekly)
        XCTAssertEqual(entry?.weekday, 2)
        XCTAssertEqual(entry?.lookbackDays, 7)
        XCTAssertEqual(entry?.preferredHour, 7)
        XCTAssertEqual(entry?.preferredMinute, 30)
        XCTAssertTrue(entry?.todayRefreshEnabled ?? false)
        XCTAssertEqual(entry?.lastExportDate, legacy.lastExportDate)

        // Second call with an unchanged legacy schedule is a no-op.
        XCTAssertFalse(store.migrateLegacyScheduleIfNeeded(legacy: legacy, defaultProfileID: defaultProfileID))
        XCTAssertEqual(store.entries.count, 1)

        // No enabled entries: nothing migrates.
        var otherSuiteName: String!
        var otherDefaults: UserDefaults!
        otherSuiteName = "disabled.\(UUID().uuidString)"
        otherDefaults = UserDefaults(suiteName: otherSuiteName)
        let otherStore = ScheduledExportEntryStore(userDefaults: otherDefaults, now: { self.fixedNow }); Self.retainedStores.append(otherStore)
        XCTAssertFalse(
            otherStore.migrateLegacyScheduleIfNeeded(
                legacy: ExportSchedule(isEnabled: false),
                defaultProfileID: UUID()
            )
        )
        XCTAssertTrue(otherStore.entries.isEmpty)
        otherDefaults.removePersistentDomain(forName: otherSuiteName)
        otherDefaults = nil
        otherSuiteName = nil
    }

    // MARK: - Coalesced due evaluation

    func testDueOccurrencesEvaluatesAllEnabledEntries() {
        let store = makeStore()
        let dailyProfile = UUID()
        let weeklyProfile = UUID()
        let disabledProfile = UUID()

        // Daily at 08:00 whose last success already covered today's slot.
        store.upsert(
            makeEntry(profileID: dailyProfile) {
                $0.frequency = .daily
                $0.preferredHour = 8
                $0.enabledAt = makeDate(year: 2026, month: 8, day: 1)
                $0.lastExportDate = makeDate(year: 2026, month: 8, day: 10, hour: 8)
            }
        )
        // Weekly Monday 08:00 — Monday Aug 10 2026 slot is due (no last run).
        store.upsert(
            makeEntry(profileID: weeklyProfile) {
                $0.frequency = .weekly
                $0.weekday = 1
                $0.preferredHour = 8
                $0.enabledAt = makeDate(year: 2026, month: 8, day: 1)
            }
        )
        // Disabled entries never surface occurrences.
        store.upsert(makeEntry(profileID: disabledProfile, enabled: false) {
            $0.frequency = .daily
            $0.preferredHour = 8
        })

        let due = store.dueOccurrences(now: fixedNow, calendar: calendar)

        XCTAssertTrue(due.contains {
            $0.profileID == weeklyProfile
                && $0.kind == .completedDay
                && !$0.exportDates.isEmpty
        })
        XCTAssertFalse(due.contains { $0.profileID == dailyProfile })
        XCTAssertFalse(due.contains { $0.profileID == disabledProfile })
    }

    func testDueOccurrencesIncludePerEntryTodayRefresh() {
        let store = makeStore()
        let profileID = UUID()

        store.upsert(
            makeEntry(profileID: profileID) {
                $0.frequency = .daily
                $0.preferredHour = 8
                $0.todayRefreshEnabled = true
                $0.todayRefreshIntervalHours = 3
                $0.enabledAt = makeDate(year: 2026, month: 8, day: 1)
                $0.lastExportDate = makeDate(year: 2026, month: 8, day: 10, hour: 8)
                // The 11:00 refresh already succeeded; at 15:00 the 14:00 slot is due.
                $0.lastTodayRefreshDate = makeDate(year: 2026, month: 8, day: 10, hour: 11)
            }
        )

        let now = makeDate(year: 2026, month: 8, day: 10, hour: 15)
        let due = store.dueOccurrences(now: now, calendar: calendar)

        XCTAssertTrue(
            due.contains {
                $0.profileID == profileID
                    && $0.kind == .todayRefresh
                    && $0.exportDates.isEmpty
                    && calendar.isDate(
                        $0.fireDate,
                        equalTo: makeDate(year: 2026, month: 8, day: 10, hour: 14),
                        toGranularity: .minute
                    )
            }
        )
        // The completed-day boundary at 08:00 already covered its work, so it
        // must not surface even though a refresh is due.
        XCTAssertFalse(
            due.contains { $0.profileID == profileID && $0.kind == .completedDay }
        )
    }

    // MARK: - Date-math projection fidelity

    func testProjectionMatchesEquivalentLegacyScheduleOccurrences() {
        let entry = makeEntry {
            $0.frequency = .custom
            $0.customInterval = 2
            $0.customUnit = .week
            $0.customAnchorDate = makeDate(year: 2026, month: 7, day: 6)
            $0.preferredHour = 9
            $0.enabledAt = makeDate(year: 2026, month: 7, day: 6)
        }
        let legacy = ExportSchedule(
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .week,
            customAnchorDate: makeDate(year: 2026, month: 7, day: 6),
            preferredHour: 9,
            enabledAt: makeDate(year: 2026, month: 7, day: 6)
        )

        XCTAssertEqual(
            ScheduleDateMath.nextScheduledOccurrences(
                schedule: entry.dateMathProjection,
                now: fixedNow,
                calendar: calendar
            ),
            ScheduleDateMath.nextScheduledOccurrences(
                schedule: legacy,
                now: fixedNow,
                calendar: calendar
            )
        )
    }
}

/// Phase-3 additive identity on durable pending requests: legacy persisted
/// JSON decodes as profile-free; new fields round-trip; shortcut requests
/// never carry profile identity.
final class PendingExportRequestProfileIdentityTests: XCTestCase {
    func testLegacyJSONWithoutProfileFieldsDecodesAsProfileFree() throws {
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "dates": [770236800],
          "source": "scheduled",
          "scheduledFireDate": 770240000,
          "scheduledKind": "completed-day",
          "createdAt": 770236000,
          "notificationMetadata": {},
          "exportTarget": "localIPhoneFolder",
          "settingsSnapshot": null
        }
        """

        let decoded = try JSONDecoder().decode(
            PendingExportRequest.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertNil(decoded.profileID)
        XCTAssertNil(decoded.profileName)
        XCTAssertTrue(decoded.usesLegacyMutableSettings)
    }

    func testProfileIdentityRoundTripsForScheduledRequestsOnly() throws {
        let profileID = UUID()
        let scheduled = PendingExportRequest(
            dates: [Date()],
            source: .scheduled,
            profileID: profileID,
            profileName: "Weekly Sleep"
        )
        let shortcut = PendingExportRequest(
            dates: [Date()],
            source: .shortcut,
            profileID: profileID,
            profileName: "Weekly Sleep"
        )

        let encoder = JSONEncoder()
        let decodedScheduled = try JSONDecoder().decode(
            PendingExportRequest.self,
            from: encoder.encode(scheduled)
        )
        XCTAssertEqual(decodedScheduled.profileID, profileID)
        XCTAssertEqual(decodedScheduled.profileName, "Weekly Sleep")

        let decodedShortcut = try JSONDecoder().decode(
            PendingExportRequest.self,
            from: encoder.encode(shortcut)
        )
        XCTAssertNil(decodedShortcut.profileID)
        XCTAssertNil(decodedShortcut.profileName)
    }
}

/// The coalesced worker record picks the earliest preferred time among
/// enabled schedules so the silent-push nudge precedes every entry's run.
final class WorkerScheduleCoalescingTests: XCTestCase {
    private func entry(
        profileID: UUID = UUID(),
        enabled: Bool = true,
        hour: Int,
        minute: Int = 0
    ) -> ScheduledExportEntry {
        var e = ScheduledExportEntry(
            profileID: profileID,
            isEnabled: enabled,
            frequency: .daily,
            preferredHour: hour,
            preferredMinute: minute
        )
        e.enabledAt = Date.distantPast
        return e
    }

    func testEarliestEnabledEntryWins() {
        let early = entry(hour: 6)
        let late = entry(hour: 20, minute: 30)

        let coalesced = PushRegistrationManager.coalescedWorkerSchedule(
            entries: [late, early],
            legacy: nil
        )

        XCTAssertEqual(coalesced?.preferredHour, 6)
        XCTAssertEqual(coalesced?.preferredMinute, 0)
    }

    func testDisabledEntriesAndDisabledLegacyAreIgnored() {
        var legacy = ExportSchedule(isEnabled: false)
        legacy.preferredHour = 5

        let coalesced = PushRegistrationManager.coalescedWorkerSchedule(
            entries: [entry(enabled: false, hour: 6), entry(enabled: false, hour: 7)],
            legacy: legacy
        )

        XCTAssertNil(coalesced)
    }

    func testEnabledLegacyCompetesWithEntries() {
        var legacy = ExportSchedule(isEnabled: true)
        legacy.preferredHour = 21

        let coalesced = PushRegistrationManager.coalescedWorkerSchedule(
            entries: [entry(hour: 9), entry(hour: 15)],
            legacy: legacy
        )

        XCTAssertEqual(coalesced?.preferredHour, 9)
    }

    func testLegacyAloneStillSyncs() {
        var legacy = ExportSchedule(isEnabled: true)
        legacy.preferredHour = 7
        legacy.preferredMinute = 45

        let coalesced = PushRegistrationManager.coalescedWorkerSchedule(
            entries: [],
            legacy: legacy
        )

        XCTAssertEqual(coalesced?.preferredHour, 7)
        XCTAssertEqual(coalesced?.preferredMinute, 45)
    }
}
