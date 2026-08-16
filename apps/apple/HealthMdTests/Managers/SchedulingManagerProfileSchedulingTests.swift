#if os(iOS)
import XCTest
@testable import HealthMd

/// Phase-3 SchedulingManager runtime wiring: scheduled entries own the
/// wake-up, run per profile with per-profile in-flight identity, adopt
/// destinations around profile runs, advance entry progress, and gate
/// pending profile requests on their entry's enabled state.
@MainActor
final class SchedulingManagerProfileSchedulingTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested
    // observation state that is unsafe during test teardown on some macOS
    // runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var keychain: FakeKeychainStore!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "SchedulingManagerProfileSchedulingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        keychain = FakeKeychainStore()
        calendar = Calendar.current
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        keychain = nil
        calendar = nil
        super.tearDown()
    }

    private func date(
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

    private final class ProfileSchedulingHarness {
        let pendingStore = InMemoryPendingExportStore()
        let notificationScheduler = InspectableExportNotificationScheduler()
        var runnerDates: [[Date]] = []
        var runnerTargets: [ExportTargetSelection] = []
        var adoptedProfiles: [String?] = []

        func makeManager(
            defaults: UserDefaults,
            keychain: FakeKeychainStore,
            now: @escaping () -> Date
        ) -> SchedulingManager {
            let harness = self
            return SchedulingManager(
                pendingExportStore: pendingStore,
                exportNotificationScheduler: notificationScheduler,
                initialSchedule: ExportSchedule(isEnabled: false),
                persistScheduleChanges: false,
                systemSideEffectsEnabled: false,
                scheduledTargetExportRunner: { dates, target in
                    harness.runnerDates.append(dates)
                    harness.runnerTargets.append(target)
                    return ExportOrchestrator.ExportResult(
                        successCount: dates.count,
                        totalCount: dates.count,
                        failedDateDetails: [],
                        completedDates: dates
                    )
                },
                now: now,
                scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults, now: now),
                scheduledProfileStore: ExportProfileStore(userDefaults: defaults, now: now),
                scheduledDestinationStore: ProfileDestinationStore(
                    userDefaults: defaults,
                    keychain: keychain
                ),
                scheduledProfileDestinationAdopter: { profile in
                    harness.adoptedProfiles.append(profile?.name)
                }
            )
        }
    }

    /// Builds one enabled daily entry + profile pair due at `now` (08:00 slot
    /// with catch-up work available).
    private func seedDueDailyProfile(
        defaults: UserDefaults,
        keychain: FakeKeychainStore,
        now: Date,
        profileName: String = "Daily",
        target: ExportTargetSelection = .apiEndpoint,
        configureEntry: (inout ScheduledExportEntry) -> Void = { _ in }
    ) -> UUID {
        let profileStore = ExportProfileStore(userDefaults: defaults)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let profile = profileStore.add(
            name: profileName,
            settings: ExportSettingsSnapshot.from(settings),
            target: target
        )
        let entryStore = ScheduledExportEntryStore(userDefaults: defaults)
        var entry = ScheduledExportEntry(
            profileID: profile.id,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8
        )
        entry.enabledAt = date(year: 2026, month: 8, day: 1)
        configureEntry(&entry)
        XCTAssertTrue(entryStore.upsert(entry))
        return profile.id
    }

    // MARK: - Wake-up evaluation

    func testDueProfileOccurrenceRunsProfileScopedExport() async throws {
        let harness = ProfileSchedulingHarness()
        // 2026-08-10 is a Monday; 08:00 slot has yesterday to export.
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let profileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now
        )

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )
        XCTAssertTrue(manager.hasEnabledProfileEntries)
        await manager.runDueProfileOccurrences()

        // One run: yesterday, via the profile's target, with destinations
        // adopted for the run profile and restored to the active profile.
        XCTAssertEqual(harness.runnerDates.count, 1)
        XCTAssertEqual(
            harness.runnerDates[0],
            [date(year: 2026, month: 8, day: 9)]
        )
        XCTAssertEqual(harness.runnerTargets, [ExportTargetSelection.apiEndpoint])
        XCTAssertEqual(harness.adoptedProfiles.first, "Daily")
        XCTAssertEqual(harness.adoptedProfiles.last, "Daily", "active profile restored")

        // The durable request carried profile identity (success clears the
        // persisted request, so assert against the captured notification).
        let scheduledRequests = harness.notificationScheduler.allScheduledRequests.map(\.profileName)
        XCTAssertEqual(scheduledRequests, ["Daily"])
        let captured = try XCTUnwrap(
            harness.notificationScheduler.allScheduledRequests.first
        )
        XCTAssertEqual(captured.profileID, profileID)
        XCTAssertEqual(captured.exportTarget, .apiEndpoint)
        XCTAssertTrue(try harness.pendingStore.loadAll().isEmpty, "full success clears the request")

        // Completed occurrences were recorded so the entry is no longer due.
        let entry = ScheduledExportEntryStore(userDefaults: defaults).entry(profileID: profileID)
        XCTAssertNotNil(entry?.lastExportDate)
        await manager.runDueProfileOccurrences()
        XCTAssertEqual(harness.runnerDates.count, 1, "entry no longer due")
    }

    func testTwoProfilesAtSameMinuteBothRun() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now,
            profileName: "Daily"
        )
        let weeklySettings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(weeklySettings)
        let profileStore = ExportProfileStore(userDefaults: defaults)
        let weekly = profileStore.add(
            name: "Weekly",
            settings: ExportSettingsSnapshot.from(weeklySettings),
            target: .apiEndpoint
        )
        let entryStore = ScheduledExportEntryStore(userDefaults: defaults)
        var weeklyEntry = ScheduledExportEntry(
            profileID: weekly.id,
            isEnabled: true,
            frequency: .weekly,
            weekday: 1,
            lookbackDays: 7
        )
        weeklyEntry.enabledAt = date(year: 2026, month: 8, day: 1)
        XCTAssertTrue(entryStore.upsert(weeklyEntry))

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )
        await manager.runDueProfileOccurrences()

        // Per-profile in-flight identity: both ran despite the shared minute.
        XCTAssertEqual(harness.runnerTargets.count, 2)
        let sortedDateCounts = harness.runnerDates.map { $0.count }.sorted()
        XCTAssertEqual(sortedDateCounts, [1, 7], "daily exports yesterday; weekly exports 7 days")
        let requestProfiles = harness.notificationScheduler.allScheduledRequests
            .compactMap(\.profileName)
            .sorted()
        XCTAssertEqual(requestProfiles, ["Daily", "Weekly"])
    }

    func testDisabledEntryNeverRuns() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let profileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now
        ) { entry in
            entry.isEnabled = false
        }

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )
        XCTAssertFalse(manager.hasEnabledProfileEntries)
        await manager.runDueProfileOccurrences()
        XCTAssertTrue(harness.runnerDates.isEmpty)
        _ = profileID
    }

    func testEntryWithMissingProfileIsDisabledNotRun() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        // Seed an entry with no matching profile.
        let orphanProfileID = UUID()
        let entryStore = ScheduledExportEntryStore(userDefaults: defaults)
        var entry = ScheduledExportEntry(
            profileID: orphanProfileID,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8
        )
        entry.enabledAt = date(year: 2026, month: 8, day: 1)
        XCTAssertTrue(entryStore.upsert(entry))

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )
        await manager.runDueProfileOccurrences()

        XCTAssertTrue(harness.runnerDates.isEmpty)
        XCTAssertFalse(
            ScheduledExportEntryStore(userDefaults: defaults)
                .entry(profileID: orphanProfileID)?.isEnabled ?? true,
            "orphaned entry disabled instead of running the wrong profile"
        )
    }

    // MARK: - Pending profile requests gate on their entry

    func testDrainSkipsPendingProfileRequestWhenEntryDisabled() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let profileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now
        )

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )

        // Queue a profile request with the entry disabled afterward.
        let request = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 9)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 10, hour: 8),
            profileID: profileID,
            profileName: "Daily"
        )
        try harness.pendingStore.upsert(request)
        ScheduledExportEntryStore(userDefaults: defaults).update(profileID: profileID) {
            $0.isEnabled = false
        }

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertTrue(harness.runnerDates.isEmpty, "disabled entry must not drain its pending request")
    }

    func testDrainRunsPendingProfileRequestWithDestinations() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let profileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now
        )

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )

        let request = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 9)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 10, hour: 8),
            exportTarget: .apiEndpoint,
            settingsSnapshot: ExportSettingsSnapshot.from(
                AdvancedExportSettings(userDefaults: defaults)
            ),
            profileID: profileID,
            profileName: "Daily"
        )
        Self.retainedSettings.append(AdvancedExportSettings(userDefaults: defaults))
        try harness.pendingStore.upsert(request)

        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertEqual(harness.runnerDates.count, 1)
        XCTAssertEqual(harness.adoptedProfiles.first, "Daily")
        XCTAssertEqual(harness.adoptedProfiles.last, "Daily", "active profile restored after drain")
    }
}
#endif
