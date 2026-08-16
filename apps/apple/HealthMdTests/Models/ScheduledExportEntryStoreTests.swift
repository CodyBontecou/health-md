import XCTest
@testable import HealthMd

final class ScheduledExportEntryStoreTests: XCTestCase {
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
        ScheduledExportEntryStore(userDefaults: defaults, now: { self.fixedNow })
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

        let second = ScheduledExportEntryStore(userDefaults: defaults, now: { self.fixedNow })
        XCTAssertEqual(second.entries, first.entries)
        XCTAssertEqual(second.entry(profileID: idA)?.weekday, 3)
    }

    func testCorruptedDataStartsEmpty() {
        defaults.set(Data("garbage".utf8), forKey: "scheduledExportEntries.list")
        XCTAssertTrue(makeStore().entries.isEmpty)
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
        let otherStore = ScheduledExportEntryStore(userDefaults: otherDefaults, now: { self.fixedNow })
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

    // MARK: - Usage projection

    func testUsageProjectionCountsMainRunsAndRefreshes() {
        let dailyWithRefresh = makeEntry {
            $0.frequency = .daily
            $0.preferredHour = 8
            $0.todayRefreshEnabled = true
            $0.todayRefreshIntervalHours = 3
        }
        // Refresh slots from 8: 8, 11, 14, 17, 20, 23 → 6 refreshes + 1 run.
        let weekly = makeEntry { $0.frequency = .weekly }
        let disabled = makeEntry(enabled: false) { $0.frequency = .daily }

        let projections = ScheduledUsageProjection.projectedMonthlyActions(
            entries: [dailyWithRefresh, weekly, disabled]
        )
        let byProfile = Dictionary(uniqueKeysWithValues: projections.map { ($0.profileID, $0) })

        XCTAssertEqual(byProfile[dailyWithRefresh.profileID]?.monthlyTotal, 7 * 30)
        XCTAssertEqual(byProfile[weekly.profileID]?.monthlyTotal, Int((30.0 / 7.0).rounded(.up)))
        XCTAssertEqual(byProfile[disabled.profileID]?.monthlyTotal, 30)

        XCTAssertEqual(
            ScheduledUsageProjection.projectedMonthlyTotal(
                entries: [dailyWithRefresh, weekly, disabled]
            ),
            7 * 30 + 5
        )
    }

    func testUsageProjectionCustomCadence() {
        let everyOtherWeek = makeEntry {
            $0.frequency = .custom
            $0.customInterval = 2
            $0.customUnit = .week
        }
        // 1 run / 14 days → 30/14 ≈ 2.14 → ceil 3 per month.
        let projections = ScheduledUsageProjection.projectedMonthlyActions(entries: [everyOtherWeek])
        XCTAssertEqual(projections.first?.monthlyTotal, 3)
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
