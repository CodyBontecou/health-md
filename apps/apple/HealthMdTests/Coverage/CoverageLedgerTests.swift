import SwiftUI
import XCTest
@testable import HealthMd

final class CoverageLedgerTests: XCTestCase {
    private var calendar: Calendar!
    private let profileID = UUID()

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    }

    private func date(_ day: Int, month: Int = 10, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func run(
        _ start: Int,
        _ end: Int? = nil,
        at timestamp: Date? = nil,
        success: Int? = nil,
        total: Int? = nil,
        reason: String? = nil,
        failed: [CoverageRun.DateIssue] = [],
        warnings: [Date] = [],
        files: Int? = nil,
        writer: CoverageWriter = .schedule,
        completed: [Date]? = nil
    ) -> CoverageRun {
        let last = end ?? start
        let count = last - start + 1
        return CoverageRun(
            timestamp: timestamp ?? date(last + 1, hour: 8),
            rangeStart: date(start),
            rangeEnd: date(last),
            writer: writer,
            successCount: success ?? count,
            totalCount: total ?? count,
            fileCount: files,
            dailyNoteUpdateCount: 0,
            dailyNoteSkipCount: 0,
            runFailureReason: reason,
            failedDates: failed,
            warningDates: warnings,
            completedDates: completed
        )
    }

    private func applied(_ runs: CoverageRun..., now: Date? = nil) -> CoverageLedger {
        var ledger = CoverageLedger(startedAt: date(1))
        for run in runs {
            ledger.apply(run, profileID: profileID, now: now ?? date(31, hour: 12), calendar: calendar)
        }
        return ledger
    }

    private func record(_ ledger: CoverageLedger, _ day: Int) -> CoverageDateRecord? {
        ledger.profiles[profileID]?[CoverageDateKey.key(for: date(day), calendar: calendar)]
    }

    private func input(
        _ ledger: CoverageLedger,
        entry: ScheduledExportEntry? = nil,
        now: Date? = nil,
        active: Bool = false
    ) -> CoverageProjection.Input {
        CoverageProjection.Input(
            profileID: profileID,
            entry: entry,
            ledger: ledger,
            now: now ?? date(31, hour: 12),
            calendar: calendar,
            hasActiveJob: active
        )
    }

    private func daily(enabledAt: Date? = nil, todayRefresh: Bool = false) -> ScheduledExportEntry {
        ScheduledExportEntry(
            profileID: profileID,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 7,
            preferredMinute: 30,
            lookbackDays: 1,
            todayRefreshEnabled: todayRefresh,
            enabledAt: enabledAt ?? date(1)
        )
    }

    private func status(_ ledger: CoverageLedger, _ day: Int, entry: ScheduledExportEntry?) -> CoverageStatus {
        CoverageProjection.day(for: date(day), input: input(ledger, entry: entry)).status
    }

    // MARK: - Merge

    func testSuccessfulRunMarksEveryDateComplete() {
        let ledger = applied(run(10, 12, files: 3))
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertEqual(record(ledger, 12)?.settledOutcome, .complete)
        XCTAssertEqual(record(ledger, 12)?.filesWritten, 1)
        XCTAssertEqual(record(ledger, 12)?.filesWrittenIsExact, false)
        XCTAssertNil(record(ledger, 13))
    }

    func testSingleDateFileCountIsExact() {
        XCTAssertEqual(record(applied(run(10, files: 4)), 10)?.filesWrittenIsExact, true)
    }

    func testLookBackHealsMissingDate() {
        let failed = run(19, at: date(20, hour: 8), success: 0, reason: "device_locked")
        let healed = run(19, 20, at: date(21, hour: 8))
        let ledger = applied(failed, healed)
        XCTAssertEqual(record(ledger, 19)?.settledOutcome, .complete)
        XCTAssertNil(record(ledger, 19)?.issueReason)
        XCTAssertEqual(status(ledger, 19, entry: daily()), .complete)
    }

    func testLaterFailureNeverDowngradesWrittenDate() {
        let good = run(10)
        let bad = run(10, at: date(12, hour: 8), success: 0, reason: "file_write_error")
        let ledger = applied(good, bad)
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertNil(record(ledger, 10)?.issueReason)
    }

    func testPerDateFailureKeepsOtherDatesComplete() {
        let issue = CoverageRun.DateIssue(date: date(11), reason: "healthkit_error")
        let ledger = applied(run(10, 12, success: 2, total: 3, failed: [issue]))
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertEqual(record(ledger, 11)?.settledOutcome, .failed)
        XCTAssertEqual(record(ledger, 11)?.issueReason, "healthkit_error")
    }

    func testWarningOnDateIsPartial() {
        let ledger = applied(run(10, 11, warnings: [date(11)]))
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertEqual(record(ledger, 11)?.settledOutcome, .partial)
    }

    func testCompletedDatesAreAuthoritative() {
        let ledger = applied(run(10, 11, reason: "task_expired", completed: [date(10)]))
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertEqual(record(ledger, 11)?.settledOutcome, .failed)
    }

    func testShortfallWithoutPerDateDetailClaimsNoCompleteDate() {
        let ledger = applied(run(10, 11, success: 1, total: 2))
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .partial)
        XCTAssertEqual(record(ledger, 11)?.settledOutcome, .partial)
    }

    func testNoHealthDataDateIsCompleteWithNote() {
        let issue = CoverageRun.DateIssue(date: date(10), reason: "no_health_data")
        let ledger = applied(run(10, success: 0, failed: [issue]))
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertEqual(record(ledger, 10)?.hadNoData, true)
    }

    func testRetentionDropsOldDatesAndBoundsLongRanges() {
        var long = run(1, 1)
        long = CoverageRun(
            timestamp: long.timestamp,
            rangeStart: date(1, month: 1).addingTimeInterval(-3_000 * 86_400),
            rangeEnd: date(30),
            writer: .manual,
            successCount: 4_000,
            totalCount: 4_000,
            fileCount: nil,
            dailyNoteUpdateCount: 0,
            dailyNoteSkipCount: 0,
            runFailureReason: nil,
            failedDates: [],
            warningDates: [],
            completedDates: nil
        )
        let ledger = applied(long)
        let count = ledger.profiles[profileID]?.count ?? 0
        XCTAssertGreaterThan(count, 300)
        XCTAssertLessThanOrEqual(count, CoverageLedger.retentionDays + 1)
    }

    // MARK: - Projection

    func testNoRecordAfterFiredOccurrenceIsMissing() {
        XCTAssertEqual(status(applied(run(2)), 19, entry: daily()), .missing)
    }

    func testDateIsNotMissingBeforeItsRunFires() {
        let ledger = applied(run(2))
        let morning = date(31, hour: 6)
        let yesterday = CoverageProjection.day(for: date(30), input: input(ledger, entry: daily(), now: morning))
        XCTAssertEqual(yesterday.status, .notDue)
    }

    func testDatesBeforeHistoryAreNotGaps() {
        var ledger = CoverageLedger(startedAt: date(20))
        ledger.apply(run(25), profileID: profileID, now: date(31, hour: 12), calendar: calendar)
        let day = CoverageProjection.day(for: date(10), input: input(ledger, entry: daily()))
        XCTAssertEqual(day.status, .notDue)
        XCTAssertTrue(day.predatesHistory)
    }

    func testWeeklyDatesWaitForTheirRunThenShareItsResult() {
        // October 25, 2026 is a Sunday. ISO weekday 7.
        let weekly = ScheduledExportEntry(
            profileID: profileID,
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            preferredMinute: 0,
            weekday: 7,
            lookbackDays: 7,
            enabledAt: date(1)
        )
        let ledger = applied(run(18, 24, at: date(25, hour: 8)))
        XCTAssertEqual(status(ledger, 18, entry: weekly), .complete)
        XCTAssertEqual(status(ledger, 24, entry: weekly), .complete)
        XCTAssertEqual(status(ledger, 27, entry: weekly), .notDue)
        XCTAssertEqual(status(ledger, 11, entry: weekly), .missing)
    }

    func testPausedDatesFromPauseEvent() {
        var ledger = applied(run(5))
        ledger.recordScheduleTransition(profileID: profileID, isEnabled: false, at: date(22, hour: 9))
        var entry = daily()
        entry.isEnabled = false
        XCTAssertEqual(status(ledger, 21, entry: entry), .missing)
        XCTAssertEqual(status(ledger, 22, entry: entry), .paused)
        XCTAssertEqual(status(ledger, 30, entry: entry), .paused)
        XCTAssertEqual(status(ledger, 31, entry: entry), .paused)
    }

    func testResumeEndsPause() {
        var ledger = applied(run(5))
        ledger.recordScheduleTransition(profileID: profileID, isEnabled: false, at: date(10, hour: 9))
        ledger.recordScheduleTransition(profileID: profileID, isEnabled: true, at: date(20, hour: 9))
        let entry = daily(enabledAt: date(20, hour: 9))
        XCTAssertEqual(status(ledger, 15, entry: entry), .paused)
        XCTAssertEqual(status(ledger, 25, entry: entry), .missing)
    }

    func testManualExportDuringPauseStillShows() {
        var ledger = applied(run(25, writer: .manual))
        ledger.recordScheduleTransition(profileID: profileID, isEnabled: false, at: date(22, hour: 9))
        var entry = daily()
        entry.isEnabled = false
        XCTAssertEqual(status(ledger, 25, entry: entry), .complete)
    }

    func testTodayIsInProgressWhenScheduledOrRunning() {
        let ledger = applied(run(5))
        XCTAssertEqual(status(ledger, 31, entry: daily()), .inProgress)
        XCTAssertEqual(status(ledger, 31, entry: nil), .notDue)
        let active = CoverageProjection.day(for: date(31), input: input(ledger, active: true))
        XCTAssertEqual(active.status, .inProgress)
    }

    func testFeedCountsRecordedRefreshAttempts() {
        let entry = daily(todayRefresh: true)
        let sent = run(15, at: date(15, hour: 9))
        let failed = run(15, at: date(15, hour: 11), success: 0, reason: "api_upload_failed")
        let partial = CoverageProjection.day(for: date(15), input: input(applied(sent, sent, failed), entry: entry))
        XCTAssertEqual(partial.status, .partial)
        XCTAssertEqual(partial.refreshes?.sent, 2)
        XCTAssertEqual(partial.refreshes?.attempted, 3)

        XCTAssertEqual(status(applied(sent, sent), 15, entry: entry), .complete)
        XCTAssertEqual(status(applied(failed, failed), 15, entry: entry), .missing)
    }

    func testCompletedDayRunHealsPartialFeedDate() {
        let entry = daily(todayRefresh: true)
        let sent = run(15, at: date(15, hour: 9))
        let failed = run(15, at: date(15, hour: 11), success: 0, reason: "api_upload_failed")
        let healed = run(15, at: date(16, hour: 7))
        XCTAssertEqual(status(applied(sent, failed, healed), 15, entry: entry), .complete)
    }

    // MARK: - Aggregation

    private func days(_ statuses: CoverageStatus...) -> [ArchiveAggregation.ProfileDay] {
        statuses.map { ArchiveAggregation.ProfileDay(profileID: UUID(), status: $0) }
    }

    func testAllAggregationPrecedence() {
        XCTAssertEqual(ArchiveAggregation.aggregate(days(.complete, .partial, .missing), isToday: false), .missing)
        XCTAssertEqual(ArchiveAggregation.aggregate(days(.complete, .partial, .notDue), isToday: false), .partial)
        XCTAssertEqual(ArchiveAggregation.aggregate(days(.complete, .paused, .notDue), isToday: false), .complete)
        XCTAssertEqual(ArchiveAggregation.aggregate(days(.paused, .notDue), isToday: false), .notDue)
        XCTAssertEqual(ArchiveAggregation.aggregate(days(.missing), isToday: true), .inProgress)
    }

    func testIssueDotsCapAtThree() {
        let result = ArchiveAggregation.issueDots(days(.partial, .complete, .missing, .partial, .missing))
        XCTAssertEqual(result.dots.map(\.isFilled), [true, false, true])
        XCTAssertTrue(result.hasOverflow)
        XCTAssertFalse(ArchiveAggregation.issueDots(days(.partial)).hasOverflow)
    }

    func testOnTrackExcludesProfilesNotDue() {
        let result = ArchiveAggregation.onTrack(days(.complete, .inProgress, .missing, .paused, .notDue))
        XCTAssertEqual(result.onTrack, 2)
        XCTAssertEqual(result.due, 3)
    }

    func testDayActions() {
        XCTAssertEqual(ArchiveAggregation.action(for: .partial, hasTodayRefresh: true)?.action, .retry)
        XCTAssertEqual(ArchiveAggregation.action(for: .partial, hasTodayRefresh: false)?.action, .reExport)
        XCTAssertEqual(ArchiveAggregation.action(for: .missing, hasTodayRefresh: false)?.action, .backfill)
        XCTAssertEqual(ArchiveAggregation.action(for: .complete, hasTodayRefresh: false)?.isProminent, false)
        XCTAssertNil(ArchiveAggregation.action(for: .paused, hasTodayRefresh: false))
    }

    func testStatsStreakSkipsNotDueAndStopsAtGap() {
        let input: [(date: Date, status: CoverageStatus)] = [
            (date(25), .complete), (date(26), .missing), (date(27), .complete), (date(28), .notDue),
            (date(29), .paused), (date(30), .partial), (date(31), .inProgress)
        ]
        let stats = ArchiveAggregation.stats(days: input, today: date(31), calendar: calendar)
        XCTAssertEqual(stats.archivedCount, 3)
        XCTAssertEqual(stats.gapCount, 1)
        XCTAssertEqual(stats.streak, 2)
        XCTAssertEqual(stats.earliestGap, date(26))
    }

    func testWeeklyStatsCountWeeks() {
        var input: [(date: Date, status: CoverageStatus)] = (11...24).map { (date($0), .complete) }
        input[1].status = .missing
        let stats = ArchiveAggregation.stats(
            days: input,
            unit: .weeks(anchorFireDay: date(25)),
            today: date(31),
            calendar: calendar
        )
        XCTAssertEqual(stats.archivedCount, 1)
        XCTAssertEqual(stats.gapCount, 1)
        XCTAssertEqual(stats.streak, 1)
        XCTAssertEqual(stats.earliestGap, date(12))
    }

    // MARK: - Attribution and seed

    private func entry(
        source: ExportSource,
        name: String? = nil,
        start: Int = 10
    ) -> ExportHistoryEntry {
        ExportHistoryEntry(
            timestamp: date(start + 1, hour: 8),
            source: source,
            success: true,
            dateRangeStart: date(start),
            dateRangeEnd: date(start),
            successCount: 1,
            totalCount: 1,
            profileName: name
        )
    }

    private func profile(_ name: String, id: UUID = UUID()) -> ExportProfile {
        let suite = "CoverageLedgerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedStores.append(settings)
        return ExportProfile(
            id: id,
            name: name,
            settings: ExportSettingsSnapshot.from(settings),
            target: .localIPhoneFolder
        )
    }

    func testAttributionOrder() {
        let named = profile("Daily")
        let active = UUID()
        let explicit = UUID()
        func resolve(_ candidate: ExportHistoryEntry, explicitID: UUID? = nil) -> UUID? {
            CoverageAttribution.profileID(
                explicitID: explicitID,
                entry: candidate,
                profiles: [named],
                activeProfileID: active
            )
        }
        XCTAssertEqual(resolve(entry(source: .scheduled, name: "Daily"), explicitID: explicit), explicit)
        XCTAssertEqual(resolve(entry(source: .scheduled, name: "Daily")), named.id)
        XCTAssertEqual(resolve(entry(source: .manual)), active)
        XCTAssertNil(resolve(entry(source: .manual, name: "Renamed")))
        XCTAssertNil(resolve(entry(source: .scheduled)))
    }

    func testSeedRunsOnceAndRecordsLostPauses() {
        let only = profile("Daily", id: profileID)
        let paused = ScheduledExportEntry(
            profileID: UUID(), isEnabled: false, lastExportDate: date(3)
        )
        var ledger = CoverageLedger(startedAt: date(31))
        ledger.seedIfNeeded(
            history: [entry(source: .manual)],
            profiles: [only],
            scheduleEntries: [paused],
            now: date(31),
            calendar: calendar
        )
        XCTAssertEqual(record(ledger, 10)?.settledOutcome, .complete)
        XCTAssertEqual(ledger.scheduleEvents[paused.profileID]?.last?.isEnabled, false)

        ledger.seedIfNeeded(
            history: [entry(source: .manual, start: 12)],
            profiles: [only],
            scheduleEntries: [],
            now: date(31),
            calendar: calendar
        )
        XCTAssertNil(record(ledger, 12))
    }

    func testSeedSkipsUnnamedRunsWhenProfilesAreAmbiguous() {
        var ledger = CoverageLedger(startedAt: date(31))
        ledger.seedIfNeeded(
            history: [entry(source: .manual)],
            profiles: [profile("A"), profile("B")],
            scheduleEntries: [],
            now: date(31),
            calendar: calendar
        )
        XCTAssertTrue(ledger.profiles.isEmpty)
    }

    // MARK: - Persistence

    private func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("coverage-ledger.json")
    }

    private func makeStore(_ url: URL) -> CoverageLedgerStore {
        let store = CoverageLedgerStore(fileURL: url, now: { [unowned self] in date(31) })
        Self.retainedStores.append(store)
        return store
    }

    // See ScheduledExportEntryStoreTests: stores outlive each test on older runtimes.
    private static var retainedStores: [AnyObject] = []

    func testStoreRoundTripsScheduleEvents() {
        let url = temporaryURL()
        let store = makeStore(url)
        store.recordScheduleTransition(profileID: profileID, isEnabled: false)
        store.flush()
        XCTAssertEqual(makeStore(url).ledger.scheduleEvents[profileID]?.count, 1)
    }

    func testCorruptFileStartsEmptyWithoutThrowing() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(makeStore(url).ledger.profiles.isEmpty)
    }

    func testNewerFileIsLeftUntouched() throws {
        let url = temporaryURL()
        var newer = CoverageLedger(startedAt: date(1))
        newer.version = CoverageLedger.currentVersion + 1
        let original = try JSONEncoder().encode(newer)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try original.write(to: url)
        let store = makeStore(url)
        store.recordScheduleTransition(profileID: profileID, isEnabled: false)
        store.clear()
        store.flush()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testClearRestartsHistorySoClearedDatesAreNotGaps() {
        let store = makeStore(temporaryURL())
        store.recordScheduleTransition(profileID: profileID, isEnabled: true)
        store.clear()
        XCTAssertTrue(store.ledger.scheduleEvents.isEmpty)
        XCTAssertTrue(store.ledger.didSeedFromHistory)
        XCTAssertEqual(store.ledger.startedAt, date(31))
    }

    // MARK: - Flag and tokens

    func testFlagDefaultsOffAndAcceptsOverride() {
        XCTAssertFalse(NewExperienceFeature.isEnabled(infoDictionary: [:]))
        XCTAssertFalse(NewExperienceFeature.isEnabled(infoDictionary: [NewExperienceFeature.flagKey: "NO"]))
        XCTAssertTrue(NewExperienceFeature.isEnabled(infoDictionary: [NewExperienceFeature.flagKey: "YES"]))
        XCTAssertFalse(
            NewExperienceFeature.isEnabled(
                infoDictionary: [NewExperienceFeature.flagKey: "YES"],
                debugOverride: false
            )
        )
    }

    func testShippedBundleLeavesFlagOff() {
        XCTAssertFalse(NewExperienceFeature.isEnabled(infoDictionary: Bundle.main.infoDictionary ?? [:]))
    }

    func testPaletteResolution() {
        XCTAssertEqual(GlassPalette.resolved(colorScheme: .dark, reduceTransparency: false), .dark)
        XCTAssertEqual(GlassPalette.resolved(colorScheme: .light, reduceTransparency: false), .light)
        XCTAssertEqual(GlassPalette.resolved(colorScheme: .dark, reduceTransparency: true), .reduceTransparencyDark)
        XCTAssertEqual(GlassPalette.solid(colorScheme: .light), .reduceTransparencyLight)
        XCTAssertNotEqual(GlassPalette.dark.glass, GlassPalette.reduceTransparencyDark.glass)
    }

    func testCalendarCellsHonourFirstWeekday() {
        var sunday = calendar!
        sunday.firstWeekday = 1
        var monday = calendar!
        monday.firstWeekday = 2
        // October 1, 2026 is a Thursday.
        let sundayCells = MonthCalendarGrid<EmptyView>.cells(month: date(15), calendar: sunday)
        XCTAssertEqual(sundayCells.prefix { $0 == nil }.count, 4)
        XCTAssertEqual(sundayCells.compactMap { $0 }.count, 31)
        XCTAssertEqual(MonthCalendarGrid<EmptyView>.cells(month: date(15), calendar: monday).prefix { $0 == nil }.count, 3)
    }
}
