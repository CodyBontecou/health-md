import XCTest
@testable import HealthMd

/// Issue #457: scheduled profiles that only rewrite days whose Health data changed.
final class IncrementalScheduledExportTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation
    // state that is unsafe during test teardown on some runtimes. See
    // docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private var utc: Calendar!
    private var tempDirectory: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrementalScheduledExportTests-\(UUID().uuidString)", isDirectory: true)
        defaultsSuiteName = "IncrementalScheduledExportTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        tempDirectory = nil
        utc = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func day(_ day: Int, month: Int = 11, hour: Int = 0, minute: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Nov 1 ... Nov 30 2026 (30-day window, as a 30-day look-back on Dec 1).
    private var november: [Date] { (1...30).map { day($0) } }

    private func makeProfile(
        id: UUID = UUID(),
        configure: (AdvancedExportSettings) -> Void = { _ in }
    ) -> ExportProfile {
        // A fresh suite per profile: settings persist to their defaults, and edits made
        // for one profile must not leak into the next.
        let suite = "\(defaultsSuiteName!).profile.\(UUID().uuidString)"
        let settings = AdvancedExportSettings(userDefaults: UserDefaults(suiteName: suite)!)
        Self.retainedSettings.append(settings)
        configure(settings)
        UserDefaults().removePersistentDomain(forName: suite)
        return ExportProfile(
            id: id,
            name: "Daily",
            settings: ExportSettingsSnapshot.from(settings),
            target: .localIPhoneFolder,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Nil means the test calendar's own identifier (Foundation reports UTC as "GMT").
    private func fingerprint(_ profile: ExportProfile, timeZone: String? = nil) -> IncrementalExportSettingsFingerprint {
        IncrementalExportSettingsFingerprint(
            profile: profile, calendarTimeZoneIdentifier: timeZone ?? utc.timeZone.identifier,
            lookbackDays: 30, includeToday: false)
    }

    private func sample(_ start: Date, _ end: Date, uuid: UUID = UUID()) -> IncrementalSampleChange {
        IncrementalSampleChange(uuid: uuid, startDate: start, endDate: end)
    }

    private func changes(
        _ type: String = "HKQuantityTypeIdentifierStepCount",
        fresh: Bool = false,
        added: [IncrementalSampleChange] = [],
        deleted: [UUID] = [],
        anchor: String = "anchor-2"
    ) -> IncrementalTypeChanges {
        IncrementalTypeChanges(
            typeIdentifier: type, startedWithoutAnchor: fresh,
            added: added, deletedUUIDs: deleted, newAnchor: Data(anchor.utf8))
    }

    /// A committed state as a first full run over November would save.
    private func committedState(
        for profile: ExportProfile,
        samples: [IncrementalSampleChange]
    ) -> IncrementalExportCommittedState {
        let first = IncrementalExportPlanner.plan(.init(
            windowDates: november, calendar: utc, now: day(1, month: 12, hour: 8),
            previous: nil, fingerprint: fingerprint(profile),
            changes: [changes(fresh: true, added: samples, anchor: "anchor-1")]
        ))
        return first.nextState!
    }

    private func plan(
        previous: IncrementalExportCommittedState?,
        profile: ExportProfile,
        changes: [IncrementalTypeChanges]?,
        missing: Set<Date> = [],
        timeZone: String? = nil
    ) -> IncrementalExportPlan {
        IncrementalExportPlanner.plan(.init(
            windowDates: november, calendar: utc, now: day(1, month: 12, hour: 8),
            previous: previous, fingerprint: fingerprint(profile, timeZone: timeZone),
            changes: changes, missingFileDays: missing
        ))
    }

    // MARK: - Day mapping

    func testSampleWithinOneDayMapsToThatDay() {
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: day(18, hour: 9), end: day(18, hour: 10), calendar: utc),
            [day(18)]
        )
    }

    func testMidnightSpanningSampleMapsToEveryDayItTouches() {
        // Sleep from 22:30 on Nov 17 to 06:45 on Nov 18.
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: day(17, hour: 22, minute: 30), end: day(18, hour: 6, minute: 45), calendar: utc),
            [day(17), day(18)]
        )
        // A 50-hour sample touches three days.
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: day(17, hour: 23), end: day(20, hour: 1), calendar: utc),
            [day(17), day(18), day(19), day(20)]
        )
    }

    func testSampleEndingExactlyAtMidnightDoesNotTouchNextDay() {
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: day(17, hour: 23), end: day(18), calendar: utc),
            [day(17)]
        )
    }

    func testInstantaneousAndInvertedSamplesBelongToTheirStartDay() {
        XCTAssertEqual(IncrementalExportDayMapper.days(start: day(18, hour: 12), end: day(18, hour: 12), calendar: utc), [day(18)])
        XCTAssertEqual(IncrementalExportDayMapper.days(start: day(18, hour: 12), end: day(18, hour: 11), calendar: utc), [day(18)])
    }

    func testDayMappingUsesTheProfileTimezone() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 03:00–04:00 UTC on Nov 18 is the evening of Nov 17 in Los Angeles and
        // midday on Nov 18 in Tokyo.
        let start = day(18, hour: 3)
        let end = day(18, hour: 4)
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: start, end: end, calendar: losAngeles),
            [day(17, calendar: losAngeles)]
        )
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: start, end: end, calendar: tokyo),
            [day(18, calendar: tokyo)]
        )
        // A sample that is one UTC day spans two Los Angeles days.
        XCTAssertEqual(
            IncrementalExportDayMapper.days(start: day(18, hour: 6), end: day(18, hour: 10), calendar: losAngeles),
            [day(17, calendar: losAngeles), day(18, calendar: losAngeles)]
        )
    }

    func testDayMappingAcrossDaylightSavingTransition() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // DST ends Nov 1 2026 (a 25-hour day). Overnight Oct 31 → Nov 2 touches 3 days.
        let start = newYork.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 22))!
        let end = newYork.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 1))!
        XCTAssertEqual(IncrementalExportDayMapper.days(start: start, end: end, calendar: newYork), [
            newYork.date(from: DateComponents(year: 2026, month: 10, day: 31))!,
            newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))!,
            newYork.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        ])
    }

    func testDayKeyRoundTripsInTheCalendarTimezone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let tokyoDay = day(18, calendar: tokyo)
        XCTAssertEqual(IncrementalExportDayMapper.dayKey(for: tokyoDay, calendar: tokyo), "2026-11-18")
        XCTAssertEqual(IncrementalExportDayMapper.date(forDayKey: "2026-11-18", calendar: tokyo), tokyoDay)
        XCTAssertNil(IncrementalExportDayMapper.date(forDayKey: "garbage", calendar: tokyo))
    }

    // MARK: - Settings fingerprint

    func testFingerprintIsStableAcrossEncodingAndIdenticalProfiles() throws {
        let profile = makeProfile()
        let fingerprint = fingerprint(profile)
        let decoded = try JSONDecoder().decode(
            IncrementalExportSettingsFingerprint.self,
            from: JSONEncoder().encode(fingerprint))
        XCTAssertEqual(decoded, fingerprint)
        XCTAssertEqual(self.fingerprint(profile), fingerprint)
    }

    func testFingerprintChangesWithOutputAffectingSettings() {
        let id = UUID()
        let base = fingerprint(makeProfile(id: id))
        XCTAssertNotEqual(fingerprint(makeProfile(id: id) { $0.filenameFormat = "health-{date}" }), base, "template")
        XCTAssertNotEqual(fingerprint(makeProfile(id: id) { $0.folderStructure = "{year}/{month}" }), base, "folder")
        XCTAssertNotEqual(fingerprint(makeProfile(id: id) { $0.exportFormats = [.json] }), base, "formats")

        var rebound = makeProfile(id: id)
        rebound.folderVaultID = UUID()
        XCTAssertNotEqual(fingerprint(rebound), base, "destination")

        XCTAssertNotEqual(fingerprint(makeProfile(id: id), timeZone: "Asia/Tokyo"), base, "timezone")
        var longer = base
        longer.lookbackDays = 7
        XCTAssertNotEqual(longer, base, "window")
    }

    // MARK: - Planner

    func testFirstRunWithoutSavedStateExportsTheWholeWindow() {
        let profile = makeProfile()
        let plan = plan(previous: nil, profile: profile, changes: [changes(fresh: true, added: [sample(day(5, hour: 9), day(5, hour: 10))])])
        XCTAssertEqual(plan.mode, .full)
        XCTAssertEqual(plan.fullReason, .noSavedState)
        XCTAssertEqual(plan.datesToExport, november)
        XCTAssertEqual(plan.nextState?.anchors["HKQuantityTypeIdentifierStepCount"], Data("anchor-2".utf8))
        XCTAssertEqual(plan.nextState?.sampleDays["HKQuantityTypeIdentifierStepCount"]?["2026-11-05"]?.count, 1)
    }

    func testRunWithoutHealthChangesWritesOnlyTheSafetyWindowAndReportsZeroChanged() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [sample(day(5, hour: 9), day(5, hour: 10))])
        let plan = plan(previous: previous, profile: profile, changes: [changes()])

        XCTAssertEqual(plan.mode, .incremental)
        // The run happens on Dec 1: today is outside the November window, so the
        // safety window contributes only yesterday (Nov 30).
        XCTAssertEqual(plan.datesToExport, [day(30)])
        XCTAssertEqual(plan.dataChangedDays, [])
        XCTAssertEqual(plan.unchangedDayCount, 29)
        let summary = plan.summary(runAt: day(1, month: 12, hour: 8), calendarTimeZoneIdentifier: "UTC")
        XCTAssertEqual(summary.changedDayCount, 0)
        XCTAssertTrue(summary.statusText.hasPrefix("0 changed"), summary.statusText)
        XCTAssertEqual(plan.nextState?.anchors["HKQuantityTypeIdentifierStepCount"], Data("anchor-2".utf8))
    }

    func testAddedSampleOnPastDayReExportsExactlyThatDay() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes(added: [sample(day(18, hour: 7), day(18, hour: 8))])])
        XCTAssertEqual(plan.mode, .incremental)
        XCTAssertEqual(plan.dataChangedDays, [day(18)])
        XCTAssertEqual(plan.datesToExport, [day(18), day(30)])
        XCTAssertEqual(plan.unchangedDayCount, 28)
    }

    func testDeletedSampleReExportsTheDaysItCovered() {
        let profile = makeProfile()
        let sleep = UUID()
        let previous = committedState(for: profile, samples: [
            sample(day(20, hour: 23), day(21, hour: 6), uuid: sleep),
            sample(day(10, hour: 9), day(10, hour: 10))
        ])
        let plan = plan(previous: previous, profile: profile, changes: [changes(deleted: [sleep])])
        XCTAssertEqual(plan.dataChangedDays, [day(20), day(21)])
        XCTAssertEqual(plan.datesToExport, [day(20), day(21), day(30)])
        let index = plan.nextState?.sampleDays["HKQuantityTypeIdentifierStepCount"] ?? [:]
        XCTAssertNil(index["2026-11-20"], "deleted sample leaves the index")
        XCTAssertEqual(index["2026-11-10"]?.count, 1)
    }

    func testDeletionOfUnknownSampleChangesNothing() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes(deleted: [UUID()])])
        XCTAssertEqual(plan.dataChangedDays, [])
        XCTAssertEqual(plan.datesToExport, [day(30)])
    }

    func testChangesOutsideTheWindowAreIgnoredAndNotIndexed() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes(added: [sample(day(15, month: 10), day(15, month: 10, hour: 1))])])
        XCTAssertEqual(plan.dataChangedDays, [])
        XCTAssertEqual(plan.nextState?.sampleDays["HKQuantityTypeIdentifierStepCount"]?["2026-10-15"], nil)
    }

    func testSettingsChangeForcesOneFullReExport() {
        let id = UUID()
        let original = makeProfile(id: id)
        let previous = committedState(for: original, samples: [])
        let edited = makeProfile(id: id) { $0.filenameFormat = "health-{date}" }

        let afterEdit = plan(previous: previous, profile: edited, changes: [changes()])
        XCTAssertEqual(afterEdit.mode, .full)
        XCTAssertEqual(afterEdit.fullReason, .settingsChanged)
        XCTAssertEqual(afterEdit.datesToExport, november)

        // Once that run commits, the next run is incremental again.
        let nextRun = plan(previous: afterEdit.nextState, profile: edited, changes: [changes()])
        XCTAssertEqual(nextRun.mode, .incremental)
        XCTAssertEqual(nextRun.datesToExport, [day(30)])
    }

    func testTimezoneChangeForcesFullReExport() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes()], timeZone: "Asia/Tokyo")
        XCTAssertEqual(plan.fullReason, .settingsChanged)
    }

    func testLostAnchorFallsBackToFullExport() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        // HealthKit reset / undecodable anchor: the source re-queries the window from scratch.
        let plan = plan(previous: previous, profile: profile, changes: [changes(fresh: true, added: [sample(day(3, hour: 1), day(3, hour: 2))])])
        XCTAssertEqual(plan.mode, .full)
        XCTAssertEqual(plan.fullReason, .anchorUnavailable)
        XCTAssertEqual(plan.datesToExport, november)
        XCTAssertNotNil(plan.nextState?.anchors["HKQuantityTypeIdentifierStepCount"])
    }

    func testNewlyEnabledTypeFallsBackToFullExport() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [
            changes(),
            changes("HKQuantityTypeIdentifierHeartRate", fresh: true)
        ])
        XCTAssertEqual(plan.fullReason, .anchorUnavailable)
    }

    func testFailedChangeQueryExportsEverythingAndKeepsSavedState() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: nil)
        XCTAssertEqual(plan.mode, .full)
        XCTAssertEqual(plan.fullReason, .changeQueryFailed)
        XCTAssertEqual(plan.datesToExport, november)
        XCTAssertNil(plan.nextState)
    }

    func testMissingFileDaysAreReExportedWithoutDataChanges() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes()], missing: [day(12), day(5, month: 10)])
        XCTAssertEqual(plan.missingFileDays, [day(12)], "days outside the window are dropped")
        XCTAssertEqual(plan.datesToExport, [day(12), day(30)])
        XCTAssertEqual(plan.summary(runAt: Date(), calendarTimeZoneIdentifier: "UTC").changedDayCount, 1)
    }

    func testSafetyWindowIncludesTodayWhenTheWindowDoes() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = IncrementalExportPlanner.plan(.init(
            windowDates: november, calendar: utc, now: day(30, hour: 20),
            previous: previous, fingerprint: fingerprint(profile), changes: [changes()]))
        XCTAssertEqual(plan.datesToExport, [day(29), day(30)])
    }

    func testIndexIsPrunedToTheWindowAndQueriedTypes() {
        let profile = makeProfile()
        var previous = committedState(for: profile, samples: [sample(day(2, hour: 1), day(2, hour: 2))])
        previous.sampleDays["HKQuantityTypeIdentifierStepCount"]?["2026-10-01"] = [UUID()]
        previous.sampleDays["HKCategoryTypeIdentifierSleepAnalysis"] = ["2026-11-03": [UUID()]]
        previous.anchors["HKCategoryTypeIdentifierSleepAnalysis"] = Data("old".utf8)
        let plan = plan(previous: previous, profile: profile, changes: [changes()])
        XCTAssertEqual(Set(plan.nextState?.sampleDays.keys ?? [:].keys), ["HKQuantityTypeIdentifierStepCount"])
        XCTAssertNil(plan.nextState?.sampleDays["HKQuantityTypeIdentifierStepCount"]?["2026-10-01"])
        XCTAssertNotNil(plan.nextState?.sampleDays["HKQuantityTypeIdentifierStepCount"]?["2026-11-02"])
        XCTAssertNil(plan.nextState?.anchors["HKCategoryTypeIdentifierSleepAnalysis"])
    }

    // MARK: - Range summaries

    func testRangeSummaryIsRebuiltFromTheWholeWindow() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes(added: [sample(day(18, hour: 7), day(18, hour: 8))])])
        XCTAssertEqual(IncrementalExportPlanner.rollupDates(plan: plan, windowDates: november, rollupPeriods: [.range]), november)
    }

    func testHistoricalCalendarSummariesRebuildOnlyPeriodsWithAChangedDay() {
        let profile = makeProfile()
        let previous = committedState(for: profile, samples: [])
        let plan = plan(previous: previous, profile: profile, changes: [changes(added: [sample(day(18, hour: 7), day(18, hour: 8))])])
        let rollup = IncrementalExportPlanner.rollupDates(plan: plan, windowDates: november, rollupPeriods: [.weekly, .monthly])
        XCTAssertEqual(rollup, [day(18), day(30)])
        // The orchestrator expands each to its period: the weeks of Nov 18 and Nov 30, and November.
        let expanded = Set(ExportOrchestrator.rollupSourceDates(
            for: rollup, periods: [.weekly], calendar: utc, latestAllowedDate: day(1, month: 12)))
        XCTAssertTrue(expanded.contains(day(16)) && expanded.contains(day(22)))
        XCTAssertFalse(expanded.contains(day(5)), "a week without changes is not rebuilt")
    }

    func testFullRunRebuildsEverySummary() {
        let plan = plan(previous: nil, profile: makeProfile(), changes: [changes(fresh: true)])
        XCTAssertEqual(IncrementalExportPlanner.rollupDates(plan: plan, windowDates: november, rollupPeriods: [.weekly]), november)
    }

    // MARK: - Status text

    func testStatusTextListsUpdatedDaysCompactly() {
        let summary = IncrementalRunSummary(
            runAt: day(24), mode: .incremental, fullReason: nil,
            updatedDays: [day(18), day(21), day(23)], changedDayCount: 1, unchangedDayCount: 27,
            calendarTimeZoneIdentifier: "UTC")
        XCTAssertEqual(
            IncrementalRunSummary.dayList(summary.updatedDays, timeZoneIdentifier: "UTC", locale: Locale(identifier: "en_US")),
            "Nov 18, 21, 23")
        XCTAssertEqual(
            IncrementalRunSummary.dayList([day(30), day(1, month: 12)], timeZoneIdentifier: "UTC", locale: Locale(identifier: "en_US")),
            "Nov 30, Dec 1")
        XCTAssertTrue(summary.statusText.contains("Updated 3 days"), summary.statusText)
        XCTAssertTrue(summary.statusText.contains("27 unchanged"), summary.statusText)
    }

    func testFullRunStatusNamesItsReason() {
        let summary = IncrementalRunSummary(
            runAt: day(24), mode: .full, fullReason: .settingsChanged,
            updatedDays: november, changedDayCount: 30, unchangedDayCount: 0, calendarTimeZoneIdentifier: "UTC")
        XCTAssertEqual(summary.statusText, "Exported all 30 days (export settings changed)")
    }

    // MARK: - Persistence

    func testStagedStateCommitsOnlyForItsRequest() throws {
        let store = IncrementalScheduledExportStore(directory: tempDirectory)
        let profile = makeProfile()
        let state = committedState(for: profile, samples: [])
        let summary = plan(previous: nil, profile: profile, changes: [changes(fresh: true)])
            .summary(runAt: day(1, month: 12), calendarTimeZoneIdentifier: "UTC")
        let request = UUID()
        try store.stage(.init(requestID: request, state: state, summary: summary), for: profile.id)
        XCTAssertNil(store.record(for: profile.id).committed, "staging alone saves nothing")

        XCTAssertNil(try store.commit(requestID: UUID(), for: profile.id), "another request cannot commit")
        XCTAssertNil(store.record(for: profile.id).committed)

        XCTAssertEqual(try store.commit(requestID: request, for: profile.id), summary)
        let record = store.record(for: profile.id)
        XCTAssertEqual(record.committed, state)
        XCTAssertEqual(record.lastSummary, summary)
        XCTAssertNil(record.staged)
    }

    func testCorruptOrFutureStateReadsAsNoStateSoTheNextRunIsFull() throws {
        let store = IncrementalScheduledExportStore(directory: tempDirectory)
        let profile = makeProfile()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: tempDirectory.appendingPathComponent("\(profile.id.uuidString.lowercased()).json"))
        XCTAssertNil(store.record(for: profile.id).committed)

        var future = committedState(for: profile, samples: [])
        future.version = IncrementalExportCommittedState.currentVersion + 1
        try store.save(.init(committed: future), for: profile.id)
        XCTAssertNil(store.record(for: profile.id).committed)

        // The planner then treats the run as a first run.
        let plan = plan(previous: store.record(for: profile.id).committed, profile: profile, changes: [changes()])
        XCTAssertEqual(plan.fullReason, .noSavedState)
    }

    func testReExportEverythingClearsSavedStateButKeepsLastStatus() throws {
        let store = IncrementalScheduledExportStore(directory: tempDirectory)
        let profile = makeProfile()
        let summary = plan(previous: nil, profile: profile, changes: [changes(fresh: true)])
            .summary(runAt: day(1, month: 12), calendarTimeZoneIdentifier: "UTC")
        try store.save(.init(committed: committedState(for: profile, samples: []), lastSummary: summary), for: profile.id)
        try store.reset(profileID: profile.id)
        XCTAssertNil(store.record(for: profile.id).committed)
        XCTAssertEqual(store.record(for: profile.id).lastSummary, summary)
    }

    func testRuntimeSavesAnchorsOnlyAfterCommit() async throws {
        let source = FakeChangeSource()
        let runtime = IncrementalScheduledExportRuntime(
            store: IncrementalScheduledExportStore(directory: tempDirectory), changeSource: source)
        let profile = makeProfile()
        let entry = ScheduledExportEntry(profileID: profile.id, lookbackDays: 30)
        source.next = [changes(fresh: true, anchor: "first")]

        let firstRequest = UUID()
        let first = await runtime.prepare(
            profile: profile, entry: entry, settings: profile.settings, requestID: firstRequest,
            windowDates: november, calendar: utc, now: day(1, month: 12, hour: 8), missingFileDays: { _ in [] })
        XCTAssertEqual(first.plan.mode, .full)
        XCTAssertTrue(runtime.nextRunIsFull(profileID: profile.id), "a failed run must not advance anchors")

        // The first run failed; the next occurrence starts from the same (no) anchors.
        source.next = [changes(fresh: true, anchor: "second")]
        let secondRequest = UUID()
        _ = await runtime.prepare(
            profile: profile, entry: entry, settings: profile.settings, requestID: secondRequest,
            windowDates: november, calendar: utc, now: day(1, month: 12, hour: 9), missingFileDays: { _ in [] })
        XCTAssertEqual(source.receivedAnchors.last, [:])
        XCTAssertNil(runtime.commit(requestID: firstRequest, profileID: profile.id), "superseded run")
        XCTAssertNotNil(runtime.commit(requestID: secondRequest, profileID: profile.id))
        XCTAssertFalse(runtime.nextRunIsFull(profileID: profile.id))

        source.next = [changes(anchor: "third")]
        let third = await runtime.prepare(
            profile: profile, entry: entry, settings: profile.settings, requestID: UUID(),
            windowDates: november, calendar: utc, now: day(1, month: 12, hour: 10), missingFileDays: { _ in [] })
        XCTAssertEqual(source.receivedAnchors.last?["HKQuantityTypeIdentifierStepCount"], Data("second".utf8))
        XCTAssertEqual(third.plan.mode, .incremental)
    }

    func testRuntimeAsksForMissingFilesOnlyAmongDaysWithData() async throws {
        let source = FakeChangeSource()
        let store = IncrementalScheduledExportStore(directory: tempDirectory)
        let runtime = IncrementalScheduledExportRuntime(store: store, changeSource: source)
        let profile = makeProfile()
        let entry = ScheduledExportEntry(profileID: profile.id, lookbackDays: 30)
        try store.save(.init(committed: committedState(for: profile, samples: [sample(day(9, hour: 9), day(9, hour: 10))])), for: profile.id)
        source.next = [changes()]
        var asked: Set<Date> = []
        let prepared = await runtime.prepare(
            profile: profile, entry: entry, settings: profile.settings, requestID: UUID(),
            windowDates: november, calendar: utc, now: day(1, month: 12, hour: 8),
            missingFileDays: { days in asked = days; return days })
        XCTAssertEqual(asked, [day(9)])
        XCTAssertEqual(prepared.plan.datesToExport, [day(9), day(30)])
    }

    // MARK: - Missing files

    func testMissingFileCheckFindsDeletedDailyNotes() throws {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.markdown]
        let vault = tempDirectory.appendingPathComponent("Vault", isDirectory: true)
        let present = day(10)
        let target = try XCTUnwrap(ExportPathPlanner.aggregateOutputTargets(
            vaultURL: vault, healthSubfolder: "Health", settings: settings, date: present).first)
        try FileManager.default.createDirectory(at: target.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("note".utf8).write(to: target.url)

        let missing = IncrementalExportMissingFiles.missingDays(
            windowDates: [day(10), day(11), day(12)],
            daysWithData: [day(10), day(11)],
            settings: settings, vaultURL: vault, healthSubfolder: "Health",
            fileExists: { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(missing, [day(11)], "Nov 12 has no data, so no file is expected")
    }

    func testMissingFileCheckSkipsArchives() {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.markdown]
        settings.archiveExportFiles = true
        XCTAssertEqual(IncrementalExportMissingFiles.missingDays(
            windowDates: [day(10)], daysWithData: [day(10)], settings: settings,
            vaultURL: tempDirectory, healthSubfolder: "Health", fileExists: { _ in false }), [])
    }

    // MARK: - Schedule entry setting

    func testNewEntriesOptInAndExistingEntriesKeepFullWindowBehavior() throws {
        let entry = ScheduledExportEntry(profileID: UUID())
        XCTAssertTrue(entry.onlyUpdateChangedDays)
        let roundTripped = try JSONDecoder().decode(ScheduledExportEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertTrue(roundTripped.onlyUpdateChangedDays)

        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        legacyJSON.removeValue(forKey: "onlyUpdateChangedDays")
        let legacy = try JSONDecoder().decode(
            ScheduledExportEntry.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        XCTAssertFalse(legacy.onlyUpdateChangedDays)
    }
}

private final class FakeChangeSource: IncrementalHealthChangeSource {
    var next: [IncrementalTypeChanges]?
    var receivedAnchors: [[String: Data]] = []

    func sampleTypeIdentifiers(for settings: ExportSettingsSnapshot) -> [String] {
        (next ?? []).map(\.typeIdentifier)
    }

    func changes(typeIdentifiers: [String], anchors: [String: Data], windowStart: Date) async throws -> [IncrementalTypeChanges] {
        receivedAnchors.append(anchors)
        guard let next else { throw UnavailableIncrementalHealthChangeSource.Unavailable() }
        return next
    }
}
