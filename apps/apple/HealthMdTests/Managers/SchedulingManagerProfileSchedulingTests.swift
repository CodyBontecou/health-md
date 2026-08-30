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
    // STATIC RETENTION JUSTIFICATION: MainActor-isolated deinits take the
    // back-deployed task path on older runtimes (CI's iOS 26.2 simulator)
    // where nested store release aborts; retain for the process lifetime.
    private static var retainedInstances: [AnyObject] = []

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
        /// Optional per-run result override; nil returns full success. Used to
        /// simulate device-locked or partial outcomes (and suspend a run).
        var resultProvider: (@MainActor ([Date], ExportTargetSelection) async -> ExportOrchestrator.ExportResult)?

        func makeManager(
            defaults: UserDefaults,
            keychain: FakeKeychainStore,
            now: @escaping @Sendable () -> Date,
            schedule: ExportSchedule? = nil,
            systemSideEffectsEnabled: Bool = false
        ) -> SchedulingManager {
            let harness = self
            let manager = SchedulingManager(
                pendingExportStore: pendingStore,
                exportNotificationScheduler: notificationScheduler,
                initialSchedule: schedule ?? ExportSchedule(isEnabled: false),
                persistScheduleChanges: false,
                systemSideEffectsEnabled: systemSideEffectsEnabled,
                scheduledTargetExportRunner: { dates, target in
                    harness.runnerDates.append(dates)
                    harness.runnerTargets.append(target)
                    if let resultProvider = harness.resultProvider {
                        return await resultProvider(dates, target)
                    }
                    return ExportOrchestrator.ExportResult(
                        successCount: dates.count,
                        totalCount: dates.count,
                        failedDateDetails: [],
                        completedDates: dates
                    )
                },
                // Hermetic quota: the real PurchaseManager keychain counter
                // persists on the simulator across runs, and repeated suite
                // runs exhausted it, skipping every occurrence with
                // "free export limit reached". Quota semantics have their
                // own coverage in SchedulingManagerPendingExportsTests.
                scheduledExportQuotaAccess: { _ in true },
                scheduledExportQuotaRecorder: { _ in },
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
            SchedulingManagerProfileSchedulingTests.retainedInstances.append(manager)
            return manager
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
        folderVaultID: UUID? = nil,
        configureEntry: (inout ScheduledExportEntry) -> Void = { _ in }
    ) -> UUID {
        let profileStore = ExportProfileStore(userDefaults: defaults)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let profile = profileStore.add(
            name: profileName,
            settings: ExportSettingsSnapshot.from(settings),
            target: target,
            folderVaultID: folderVaultID
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

    func testDueLocalProfileHistoryCapturesProfileAndRefreshedFolderName() async throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }

        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let destinationStore = ProfileDestinationStore(
            userDefaults: defaults,
            keychain: keychain
        )
        let destination = destinationStore.upsertVault(
            name: "Old Folder Name",
            standardizedPath: "/private/health-exports",
            bookmarkData: Data("old-bookmark".utf8)
        )
        _ = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now,
            profileName: "Research",
            target: .localIPhoneFolder,
            folderVaultID: destination.id
        )

        let harness = ProfileSchedulingHarness()
        harness.resultProvider = { dates, _ in
            // Destination adoption can refresh a stale bookmark/name through
            // a separate store instance while SchedulingManager is alive.
            let refreshedStore = ProfileDestinationStore(
                userDefaults: self.defaults,
                keychain: self.keychain
            )
            refreshedStore.updateVault(
                id: destination.id,
                name: "Research Exports",
                standardizedPath: "/private/health-exports",
                bookmarkData: Data("refreshed-bookmark".utf8),
                identity: nil
            )
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: [],
                completedDates: dates
            )
        }
        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now }
        )

        await manager.runDueProfileOccurrences()

        let entry = try XCTUnwrap(history.history.first)
        XCTAssertEqual(entry.source, .scheduled)
        XCTAssertEqual(entry.exportTarget, .localIPhoneFolder)
        XCTAssertEqual(entry.profileName, "Research")
        XCTAssertEqual(entry.targetLabel, "iPhone: Research Exports")
        XCTAssertFalse(entry.targetLabel?.contains("/private/") == true)
        XCTAssertFalse(entry.targetLabel?.contains("bookmark") == true)
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

    /// Tapping a recovery notification whose profile entry was disabled
    /// reports why instead of returning silently (mirrors the legacy-disabled
    /// tap surface).
    func testTapWithDisabledProfileEntrySurfacesDisabledResult() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let profileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now
        )

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })

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

        await manager.performPendingExport(requestId: request.id, source: .scheduled)

        XCTAssertTrue(harness.runnerDates.isEmpty)
        guard case .failure(let reason) = manager.notificationExportResult?.status else {
            XCTFail("Expected a failure result for the disabled-entry tap")
            return
        }
        XCTAssertTrue(reason.contains("Daily"), "the result names the disabled profile: \(reason)")
    }

    func testDrainRunsPendingProfileRequestWithDestinations() async throws {
        let history = ExportHistoryManager.shared
        history.clearHistory()
        defer { history.clearHistory() }

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
        let recorded = try XCTUnwrap(history.history.first)
        XCTAssertEqual(recorded.profileName, "Daily")
        XCTAssertEqual(recorded.exportTarget, .apiEndpoint)
        XCTAssertNotNil(recorded.targetLabel)
        XCTAssertNotEqual(recorded.targetLabel, "Daily", "target provenance is not the profile name")
    }

    func testManagerObservesScheduleEditsSavedThroughSeparateStoreInstance() async throws {
        let harness = ProfileSchedulingHarness()
        // 2026-08-10 12:00: today's 08:00 slot has passed, so the seeded
        // daily 08:00 entry's next occurrence is tomorrow at 08:00.
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

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let tomorrow0800 = calendar.date(
            byAdding: .day,
            value: 1,
            to: date(year: 2026, month: 8, day: 10, hour: 8)
        )!
        XCTAssertEqual(
            manager.getNextExportDescription(),
            formatter.string(from: tomorrow0800),
            "baseline next occurrence is tomorrow 08:00"
        )

        // The UI coordinator saves an edit through its own store instance;
        // the manager's store must not keep serving its cached snapshot.
        let uiEntryStore = ScheduledExportEntryStore(userDefaults: defaults, now: { now })
        XCTAssertTrue(uiEntryStore.update(profileID: profileID) { entry in
            entry.preferredHour = 20
        })
        manager.refreshScheduledAutomation()

        let today2000 = date(year: 2026, month: 8, day: 10, hour: 20)
        XCTAssertEqual(
            manager.getNextExportDescription(),
            formatter.string(from: today2000),
            "next-export status must reflect the just-saved 20:00 edit"
        )

        // Disabling the entry through the UI-side store deactivates scheduling
        // on the manager's next evaluation without an intervening reload.
        XCTAssertTrue(uiEntryStore.update(profileID: profileID) { $0.isEnabled = false })
        manager.refreshScheduledAutomation()
        XCTAssertFalse(manager.hasEnabledProfileEntries)
        XCTAssertFalse(manager.isSchedulingActive)
        XCTAssertNil(manager.getNextExportDescription())
    }

    /// The +60s fallback notification armed for a profile occurrence must
    /// carry the profile's context. A legacy-shaped armed request can never
    /// run from a tap while the legacy schedule is off, which surfaced as
    /// "Export Failed — Scheduling is disabled" on notification tap.
    func testProfileOccurrenceFallbackNotificationIsProfileScopedAndRunsOnTap() async throws {
        let harness = ProfileSchedulingHarness()
        // Arming manager sees today 12:00 (today's 08:00 slot passed → arms
        // tomorrow 08:00); the tapping manager sees tomorrow 09:00, after the
        // armed occurrence fired.
        let armNow = date(year: 2026, month: 8, day: 10, hour: 12)
        let tapNow = date(year: 2026, month: 8, day: 11, hour: 9)
        let profileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: armNow
        )

        let armingManager = harness.makeManager(defaults: defaults, keychain: keychain, now: { armNow })
        armingManager.scheduleBackgroundTask()

        for _ in 0..<50 where harness.notificationScheduler.allScheduledRequests.isEmpty {
            await Task.yield()
        }
        let armed = try XCTUnwrap(
            harness.notificationScheduler.allScheduledRequests.last,
            "fallback notification must be armed for the profile occurrence"
        )
        XCTAssertEqual(armed.profileID, profileID)
        XCTAssertEqual(armed.profileName, "Daily")
        XCTAssertEqual(armed.exportTarget, .apiEndpoint)
        XCTAssertEqual(armed.scheduledFireDate, date(year: 2026, month: 8, day: 11, hour: 8))
        XCTAssertTrue(try harness.pendingStore.loadAll().contains { $0.id == armed.id })

        let tappingManager = harness.makeManager(defaults: defaults, keychain: keychain, now: { tapNow })
        let tracker = NotificationExportActivityTracker.shared
        tracker.clear()
        defer { tracker.clear() }

        await tappingManager.performPendingExport(requestId: armed.id, source: .scheduled)

        XCTAssertEqual(
            harness.runnerDates.map { $0.map { calendar.startOfDay(for: $0) } },
            [[calendar.startOfDay(for: date(year: 2026, month: 8, day: 10))]],
            "tap must export the profile occurrence's exact date window"
        )
        XCTAssertFalse(
            tappingManager.notificationExportResult.map { !$0.isSuccess } ?? false,
            "tap must not surface 'Scheduling is disabled' while entries are scheduled"
        )
        XCTAssertFalse(try harness.pendingStore.loadAll().contains { $0.id == armed.id })
        XCTAssertTrue(harness.notificationScheduler.canceledRequestIDs.contains(armed.id))
    }

    /// Tapping a stale legacy-shaped pending request while profile entries
    /// own scheduling discards the obsolete request and honors the tap with
    /// due profile work instead of failing with "Scheduling is disabled".
    func testTapOfLegacyPendingRequestWithProfileSchedulingDiscardsAndRunsDueWork() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)

        let legacyRequest = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 9)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 10, hour: 8),
            scheduledKind: .completedDay,
            createdAt: date(year: 2026, month: 8, day: 10, hour: 8),
            calendar: calendar
        )
        try harness.pendingStore.upsert(legacyRequest)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })

        await manager.performPendingExport(requestId: legacyRequest.id, source: .scheduled)

        XCTAssertEqual(harness.runnerDates.count, 1, "tap runs due profile work")
        XCTAssertNil(
            manager.notificationExportResult,
            "no failure modal while entries actively own scheduling"
        )
        XCTAssertFalse(try harness.pendingStore.loadAll().contains { $0.id == legacyRequest.id })
        XCTAssertTrue(harness.notificationScheduler.canceledRequestIDs.contains(legacyRequest.id))
    }

    /// The worker mirrors the coalesced entry schedule, so a silent push must
    /// wake entry evaluation even when the legacy schedule is off.
    func testSilentPushRunsDueProfileOccurrencesWhenLegacyScheduleDisabled() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })
        await manager.performSilentPushExport(fireDate: nil, kind: .completedDay)

        XCTAssertEqual(harness.runnerDates.count, 1, "silent push wakes due profile occurrences")
    }

    // MARK: - Preserved-retry survival (audit finding 1)

    /// A device-locked occurrence preserves its retry request and immediate
    /// recovery notification; the post-run re-arm must not destroy either.
    func testDeviceLockedProfileRetrySurvivesPostRunRearm() async throws {
        let harness = ProfileSchedulingHarness()
        // Occurrence fired 08:00; now 08:05 so the +60s fallback window has
        // already passed — the retry is a preserved request, not an armed one.
        let now = date(year: 2026, month: 8, day: 10, hour: 8, minute: 5)
        let profileID = seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)
        harness.resultProvider = { dates, _ in
            ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .deviceLocked) }
            )
        }

        // systemSideEffectsEnabled so runDueProfileOccurrences' re-arm line
        // actually executes (BGTaskScheduler.submit is skipped in unit tests).
        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now },
            systemSideEffectsEnabled: true
        )

        await manager.runDueProfileOccurrences()
        // Let the re-arm's fallback-arming Task settle.
        for _ in 0..<50 where harness.notificationScheduler.allScheduledRequests.isEmpty {
            await Task.yield()
        }

        let stored = try harness.pendingStore.loadAll()
        let retry = try XCTUnwrap(
            stored.first { $0.profileID == profileID },
            "device-locked retry request must survive the post-run re-arm"
        )
        XCTAssertEqual(retry.scheduledFireDate, date(year: 2026, month: 8, day: 10, hour: 8))
        XCTAssertNotNil(
            harness.notificationScheduler.immediateRequests[retry.id],
            "immediate recovery notification must remain armed"
        )
        XCTAssertTrue(
            harness.notificationScheduler.allScheduledRequests.contains { $0.profileID == profileID },
            "the re-arm still armed the next occurrence's fallback (re-arm ran)"
        )
    }

    /// A schedule edit re-arms automation (the refreshScheduledAutomation Task
    /// body); a preserved past retry must survive that re-arm.
    func testPreservedPastRetrySurvivesEditRearm() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)

        let preserved = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 8)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 9, hour: 8),
            scheduledKind: .completedDay,
            createdAt: date(year: 2026, month: 8, day: 9, hour: 9),
            exportTarget: .apiEndpoint,
            calendar: calendar
        )
        try harness.pendingStore.upsert(preserved)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })

        // The exact code refreshScheduledAutomation runs after an entry edit.
        manager.scheduleBackgroundTask()
        for _ in 0..<50 where harness.notificationScheduler.allScheduledRequests.isEmpty {
            await Task.yield()
        }

        XCTAssertTrue(
            try harness.pendingStore.loadAll().contains { $0.id == preserved.id },
            "a preserved retry whose fallback fired must survive the edit re-arm"
        )
        XCTAssertFalse(harness.notificationScheduler.canceledRequestIDs.contains(preserved.id))
    }

    /// Disabling automation (cancelBackgroundTask) still cancels fallbacks
    /// that have not fired yet, while a preserved retry stays recoverable.
    func testDisablePathCancelsArmedFutureFallbackButPreservesFiredRetry() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)

        let armedFuture = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 10)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 11, hour: 8),
            scheduledKind: .completedDay,
            createdAt: now,
            exportTarget: .apiEndpoint,
            calendar: calendar
        )
        let preservedRetry = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 8)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 9, hour: 8),
            scheduledKind: .completedDay,
            createdAt: date(year: 2026, month: 8, day: 9, hour: 9),
            exportTarget: .apiEndpoint,
            calendar: calendar
        )
        try harness.pendingStore.upsert(armedFuture)
        try harness.pendingStore.upsert(preservedRetry)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })
        manager.cancelBackgroundTask()

        let remaining = try harness.pendingStore.loadAll()
        XCTAssertFalse(remaining.contains { $0.id == armedFuture.id }, "armed-future fallback is canceled")
        XCTAssertTrue(harness.notificationScheduler.canceledRequestIDs.contains(armedFuture.id))
        XCTAssertTrue(remaining.contains { $0.id == preservedRetry.id }, "fired retry stays recoverable")
        XCTAssertFalse(harness.notificationScheduler.canceledRequestIDs.contains(preservedRetry.id))
    }

    // MARK: - Dual-mode wake-ups (audit finding 2)

    /// With the legacy schedule and a profile entry both enabled, one silent
    /// push runs both windows: the entry's dates and the legacy schedule's.
    /// A preserved retry marked attempted survives bulk fallback cancellation
    /// even while its fallback window is still open — the window heuristic
    /// alone could not distinguish a fresh retry from an armed fallback, so
    /// re-arms and edits within 60s of a device-locked run destroyed the
    /// recovery surface. An unmarked in-window request is still canceled.
    func testFreshPreservedRetryWithinFallbackWindowSurvivesBulkCancel() async throws {
        let harness = ProfileSchedulingHarness()
        // fireDate 11:50 → fallback window closes 11:51; now is 11:55 with an
        // armed-future fallback at 12:30 — both inside/across the boundary.
        let now = date(year: 2026, month: 8, day: 10, hour: 11, minute: 55)
        seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)

        let freshRetry = PendingExportRequest(
            id: UUID(uuidString: "C1C1C1C1-C1C1-C1C1-C1C1-C1C1C1C1C1C1")!,
            dates: [date(year: 2026, month: 8, day: 9)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 10, hour: 11, minute: 50),
            scheduledKind: .completedDay,
            createdAt: date(year: 2026, month: 8, day: 10, hour: 11, minute: 50),
            exportTarget: .apiEndpoint,
            attemptedAt: date(year: 2026, month: 8, day: 10, hour: 11, minute: 54),
            calendar: calendar
        )
        let armedFuture = PendingExportRequest(
            id: UUID(uuidString: "C2C2C2C2-C2C2-C2C2-C2C2-C2C2C2C2C2C2")!,
            dates: [date(year: 2026, month: 8, day: 10)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 11, hour: 8),
            scheduledKind: .completedDay,
            createdAt: now,
            exportTarget: .apiEndpoint,
            calendar: calendar
        )
        try harness.pendingStore.upsert(freshRetry)
        try harness.pendingStore.upsert(armedFuture)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })
        manager.scheduleBackgroundTask()
        for _ in 0..<50 where harness.notificationScheduler.allScheduledRequests.isEmpty {
            await Task.yield()
        }

        let stored = try harness.pendingStore.loadAll()
        XCTAssertTrue(
            stored.contains { $0.id == freshRetry.id },
            "an attempted retry must survive bulk cancel even inside its fallback window"
        )
        XCTAssertFalse(
            stored.contains { $0.id == armedFuture.id },
            "an unmarked armed-future fallback must still be cleared by re-arm"
        )
        XCTAssertFalse(harness.notificationScheduler.canceledRequestIDs.contains(freshRetry.id))
    }

    /// End-to-end reviewer scenario: a device-locked profile run preserves a
    /// retry seconds after its fire date; the wake-up's own re-arm (and a
    /// legacy didSet-driven refresh in the same wake-up) must not destroy it.
    func testDeviceLockedRunPreservesInWindowRetryAcrossDualModeRearm() async throws {
        let harness = ProfileSchedulingHarness()
        // Occurrence fired 08:00; now 08:01 — the +60s fallback window is
        // STILL OPEN, so only the attempted marker can protect the retry.
        let now = date(year: 2026, month: 8, day: 10, hour: 8, minute: 1)
        let profileID = seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now)
        harness.resultProvider = { dates, target in
            // The profile occurrence (API endpoint) fails device-locked; the
            // legacy occurrence (local folder) succeeds, driving the legacy
            // `schedule = updated` didSet re-arm with default bulk cancel.
            if target == .apiEndpoint {
                return ExportOrchestrator.ExportResult(
                    successCount: 0,
                    totalCount: dates.count,
                    failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .deviceLocked) }
                )
            }
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: [],
                completedDates: dates
            )
        }

        // Dual-mode: legacy schedule also enabled so the legacy leg's success
        // writes `schedule = updated` and didSet re-arms automation — the
        // exact path that previously destroyed the fresh profile retry.
        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now },
            schedule: ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8),
            systemSideEffectsEnabled: true
        )

        await manager.performSilentPushExport(fireDate: nil, kind: .completedDay)
        for _ in 0..<100 where harness.notificationScheduler.allScheduledRequests.isEmpty {
            await Task.yield()
        }

        let stored = try harness.pendingStore.loadAll()
        let retry = try XCTUnwrap(
            stored.first { $0.profileID == profileID },
            "the in-window device-locked retry must survive the dual-mode wake-up's re-arms"
        )
        XCTAssertNotNil(retry.attemptedAt, "the preserved retry is marked attempted")
        XCTAssertNotNil(
            harness.notificationScheduler.immediateRequests[retry.id],
            "immediate recovery notification must remain armed"
        )
    }

    func testSilentPushDualModeRunsEntryAndLegacyOccurrences() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        // Weekly entry (7-day window) beside a daily legacy schedule (1 day).
        seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now) { entry in
            entry.frequency = .weekly
            entry.weekday = 1
            entry.lookbackDays = 7
        }
        let legacySchedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            enabledAt: date(year: 2026, month: 8, day: 1)
        )

        let manager = harness.makeManager(
            defaults: defaults,
            keychain: keychain,
            now: { now },
            schedule: legacySchedule
        )

        await manager.performSilentPushExport(fireDate: nil, kind: .completedDay)

        XCTAssertEqual(harness.runnerDates.count, 2, "both entry and legacy occurrences run")
        let sortedDateCounts = harness.runnerDates.map { $0.count }.sorted()
        XCTAssertEqual(sortedDateCounts, [1, 7], "legacy daily exports 1 day; entry weekly exports 7")
        XCTAssertEqual(
            Set(harness.runnerTargets),
            Set([ExportTargetSelection.apiEndpoint, legacySchedule.target]),
            "entry runs its profile target; legacy runs the schedule target"
        )
    }

    // MARK: - Stale profile retries (audit finding 3)

    /// A retry preserved before an entry's current enabled period is
    /// discarded by the app-active drain; one fired after it still runs.
    func testDrainDiscardsStaleProfileRetryButRunsFreshOne() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 12)
        let profileID = seedDueDailyProfile(defaults: defaults, keychain: keychain, now: now) { entry in
            // Re-enabled this morning at 07:00.
            entry.enabledAt = date(year: 2026, month: 8, day: 10, hour: 7)
        }

        let staleRetry = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 6)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 7, hour: 8),
            scheduledKind: .completedDay,
            createdAt: date(year: 2026, month: 8, day: 7, hour: 9),
            exportTarget: .apiEndpoint,
            profileID: profileID,
            profileName: "Daily",
            calendar: calendar
        )
        let freshRetry = PendingExportRequest(
            dates: [date(year: 2026, month: 8, day: 9)],
            source: .scheduled,
            scheduledFireDate: date(year: 2026, month: 8, day: 10, hour: 8),
            scheduledKind: .completedDay,
            createdAt: date(year: 2026, month: 8, day: 10, hour: 9),
            exportTarget: .apiEndpoint,
            profileID: profileID,
            profileName: "Daily",
            calendar: calendar
        )
        try harness.pendingStore.upsert(staleRetry)
        try harness.pendingStore.upsert(freshRetry)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })
        await manager.drainPendingExportsIfNeeded(trigger: .appActive)

        XCTAssertEqual(harness.runnerDates.count, 1, "only the fresh retry runs")
        XCTAssertEqual(harness.runnerDates.first, [calendar.startOfDay(for: date(year: 2026, month: 8, day: 9))])
        let remaining = try harness.pendingStore.loadAll()
        XCTAssertFalse(remaining.contains { $0.id == staleRetry.id }, "stale retry discarded")
        XCTAssertTrue(harness.notificationScheduler.canceledRequestIDs.contains(staleRetry.id))
    }

    // MARK: - Per-profile pending dedupe (audit finding 4)

    /// Two profiles' retries at the same fire minute must not block each
    /// other: the occurrence gate is per profile, not a shared fire minute.
    func testConcurrentProfileRetriesAtSameFireMinuteBothRun() async throws {
        let harness = ProfileSchedulingHarness()
        let now = date(year: 2026, month: 8, day: 10, hour: 9)
        let firstProfileID = seedDueDailyProfile(
            defaults: defaults,
            keychain: keychain,
            now: now,
            profileName: "First"
        )
        let profileStore = ExportProfileStore(userDefaults: defaults)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let second = profileStore.add(
            name: "Second",
            settings: ExportSettingsSnapshot.from(settings),
            target: .apiEndpoint
        )
        let entryStore = ScheduledExportEntryStore(userDefaults: defaults)
        var secondEntry = ScheduledExportEntry(
            profileID: second.id,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8
        )
        // Explicit historical enable period: the default would stamp Date()
        // (test-host wall clock), which the enabledAt discard would treat the
        // retry as stale.
        secondEntry.enabledAt = date(year: 2026, month: 8, day: 1)
        XCTAssertTrue(entryStore.upsert(secondEntry))

        let fireMinute = date(year: 2026, month: 8, day: 10, hour: 8)
        func retry(profileID: UUID) -> PendingExportRequest {
            PendingExportRequest(
                dates: [date(year: 2026, month: 8, day: 9)],
                source: .scheduled,
                scheduledFireDate: fireMinute,
                scheduledKind: .completedDay,
                createdAt: date(year: 2026, month: 8, day: 10, hour: 8, minute: 30),
                exportTarget: .apiEndpoint,
                profileID: profileID,
                profileName: profileID == firstProfileID ? "First" : "Second",
                calendar: calendar
            )
        }
        let firstRetry = retry(profileID: firstProfileID)
        let secondRetry = retry(profileID: second.id)
        try harness.pendingStore.upsert(firstRetry)
        try harness.pendingStore.upsert(secondRetry)

        let manager = harness.makeManager(defaults: defaults, keychain: keychain, now: { now })

        var continuation: CheckedContinuation<Void, Never>?
        var suspendNextRunner = true
        harness.resultProvider = { dates, _ in
            if suspendNextRunner {
                suspendNextRunner = false
                await withCheckedContinuation { pending in
                    continuation = pending
                }
            }
            return ExportOrchestrator.ExportResult(
                successCount: dates.count,
                totalCount: dates.count,
                failedDateDetails: [],
                completedDates: dates
            )
        }

        let firstTask = Task { @MainActor in
            await manager.performPendingExport(requestId: firstRetry.id, source: .scheduled)
        }
        for _ in 0..<10 where continuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(continuation, "first retry's runner should suspend")

        let secondTask = Task { @MainActor in
            await manager.performPendingExport(requestId: secondRetry.id, source: .scheduled)
        }
        for _ in 0..<20 where harness.runnerDates.count < 2 {
            await Task.yield()
        }

        XCTAssertEqual(
            harness.runnerDates.count,
            2,
            "the second profile's retry at the same fire minute must not be blocked by the first"
        )

        continuation?.resume()
        await firstTask.value
        await secondTask.value
        XCTAssertEqual(harness.runnerDates.count, 2)
        XCTAssertTrue(try harness.pendingStore.loadAll().isEmpty, "both retries completed and cleared")
    }
}
#endif
