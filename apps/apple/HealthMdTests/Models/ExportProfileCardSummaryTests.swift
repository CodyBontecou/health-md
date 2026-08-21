import XCTest
@testable import HealthMd

final class ExportProfileCardSummaryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var fixedNow: Date!

    // STATIC RETENTION JUSTIFICATION: ObservableObject-backed settings use
    // STATIC RETENTION JUSTIFICATION: Combine machinery; retain for the process lifetime to avoid
    // platform-specific deinit aborts while the test process tears down
    // (matches the pattern in ExportProfileStoreTests).
    private static var retainedSettings: [AdvancedExportSettings] = []

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ExportProfileCardSummaryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        fixedNow = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeSettings() -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeSnapshot(
        formats: Set<ExportFormat> = [.json],
        metricIDs: Set<String> = ["heart-rate", "steps"]
    ) -> ExportSettingsSnapshot {
        let settings = makeSettings()
        settings.exportFormats = formats
        settings.metricSelection.enabledMetrics = metricIDs
        return ExportSettingsSnapshot.from(settings)
    }

    private func makeProfile(
        target: ExportTargetSelection = .localIPhoneFolder,
        formats: Set<ExportFormat> = [.json],
        metricIDs: Set<String> = ["heart-rate", "steps"]
    ) -> ExportProfile {
        ExportProfile(
            name: "Daily",
            settings: makeSnapshot(formats: formats, metricIDs: metricIDs),
            target: target,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private func makeEntry(
        profileID: UUID,
        isEnabled: Bool = true,
        frequency: ScheduleFrequency = .daily,
        hour: Int = 8,
        minute: Int = 30,
        weekday: Int = 1,
        customInterval: Int = 1,
        customUnit: ScheduleIntervalUnit = .day,
        lookback: Int = 1
    ) -> ScheduledExportEntry {
        ScheduledExportEntry(
            profileID: profileID,
            isEnabled: isEnabled,
            frequency: frequency,
            customInterval: customInterval,
            customUnit: customUnit,
            customAnchorDate: fixedNow,
            preferredHour: hour,
            preferredMinute: minute,
            weekday: weekday,
            lookbackDays: lookback
        )
    }

    // MARK: - Format ordering

    func testSortedFormatsUsesCatalogueOrder() {
        let sorted = ExportProfileCardSummary.sortedFormats([.csv, .markdown, .json])
        XCTAssertEqual(sorted, [.markdown, .json, .csv])
    }

    func testSortedFormatsOmitsUnselectedFormats() {
        let sorted = ExportProfileCardSummary.sortedFormats([.obsidianBases])
        XCTAssertEqual(sorted, [.obsidianBases])
    }

    // MARK: - Destination resolution

    func testDestinationBoundVaultName() {
        let profile = makeProfile()
        let vault = SavedVaultDestination(name: "Obsidian Vault", standardizedPath: "/obsidian", bookmarkData: Data([1]))
        let summary = ExportProfileDestinationSummary.from(
            profile: profile,
            vault: vault,
            endpoint: nil
        )
        XCTAssertEqual(summary, .localFolder(vaultName: "Obsidian Vault"))
    }

    func testDestinationUnboundFolderFollowsExportTab() {
        let profile = makeProfile()
        let summary = ExportProfileDestinationSummary.from(profile: profile, vault: nil, endpoint: nil)
        XCTAssertEqual(summary, .localFolder(vaultName: nil))
    }

    func testDestinationConnectedMacIgnoresBindings() {
        let profile = makeProfile(target: .connectedMac)
        let summary = ExportProfileDestinationSummary.from(profile: profile, vault: nil, endpoint: nil)
        XCTAssertEqual(summary, .connectedMac)
    }

    func testDestinationAPIEndpointResolvesBoundURL() {
        let profile = makeProfile(target: .apiEndpoint)
        let endpoint = SavedAPIEndpoint(name: "Notebook", endpointURLString: "https://example.test/hook")
        let summary = ExportProfileDestinationSummary.from(
            profile: profile,
            vault: nil,
            endpoint: endpoint
        )
        XCTAssertEqual(summary, .apiEndpoint(url: "https://example.test/hook"))
    }

    func testDestinationAPIEndpointWithoutBinding() {
        let profile = makeProfile(target: .apiEndpoint)
        let summary = ExportProfileDestinationSummary.from(profile: profile, vault: nil, endpoint: nil)
        XCTAssertEqual(summary, .apiEndpoint(url: nil))
    }

    // MARK: - Schedule status

    func testScheduleStatusNotConfiguredWithoutEntry() {
        XCTAssertEqual(ExportProfileScheduleStatus.from(nil), .notConfigured)
    }

    func testScheduleStatusPausedForDisabledEntry() {
        let profile = makeProfile()
        let entry = makeEntry(profileID: profile.id, isEnabled: false)
        XCTAssertEqual(ExportProfileScheduleStatus.from(entry), .paused)
    }

    func testScheduleStatusScheduledForEnabledEntry() {
        let profile = makeProfile()
        let entry = makeEntry(profileID: profile.id, isEnabled: true)
        XCTAssertEqual(ExportProfileScheduleStatus.from(entry), .scheduled)
    }

    // MARK: - Cadence facts

    func testCadenceDailyCarriesTimeAndLookbackOnly() {
        let profile = makeProfile()
        let entry = makeEntry(profileID: profile.id, frequency: .daily, hour: 8, minute: 30, lookback: 2)
        let cadence = ExportProfileCadenceSummary.from(entry)

        XCTAssertEqual(cadence.frequencyDescription, ScheduleFrequency.daily.description)
        XCTAssertEqual(cadence.lookbackDays, 2)
        XCTAssertNil(cadence.weekdayIndex)
        XCTAssertNil(cadence.customInterval)
        XCTAssertNil(cadence.customUnit)
    }

    func testCadenceWeeklyCarriesWeekday() {
        let profile = makeProfile()
        let entry = makeEntry(profileID: profile.id, frequency: .weekly, weekday: 3)
        let cadence = ExportProfileCadenceSummary.from(entry)

        XCTAssertEqual(cadence.weekdayIndex, 3)
        XCTAssertNil(cadence.customInterval)
    }

    func testCadenceCustomCarriesIntervalAndUnit() {
        let profile = makeProfile()
        let entry = makeEntry(
            profileID: profile.id,
            frequency: .custom,
            customInterval: 2,
            customUnit: .week
        )
        let cadence = ExportProfileCadenceSummary.from(entry)

        XCTAssertEqual(cadence.customInterval, 2)
        XCTAssertEqual(cadence.customUnit, .week)
        XCTAssertNil(cadence.weekdayIndex)
    }

    func testTimeLabelUsesInjectedLocale() {
        let label = ExportProfileCadenceSummary.timeLabel(
            hour: 20,
            minute: 5,
            locale: Locale(identifier: "en_US")
        )
        // DateFormatter emits a narrow no-break space (U+202F or U+00A0,
        // ICU-version dependent) before the meridiem; compare with all
        // whitespace stripped while the display string keeps the formatter's
        // spacing.
        let normalized = label.filter { !$0.isWhitespace }
        XCTAssertEqual(normalized, "8:05PM")
    }

    func testWeekdayNameMapsISOWeekdaysToGregorianSymbols() {
        let monday = ExportProfileCadenceSummary.weekdayName(1, locale: Locale(identifier: "en_US"))
        let sunday = ExportProfileCadenceSummary.weekdayName(7, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(monday, "Monday")
        XCTAssertEqual(sunday, "Sunday")
    }

    // MARK: - Card summary assembly

    func testCardSummaryCarriesFrozenFacts() {
        let profile = makeProfile(formats: [.markdown, .csv], metricIDs: ["heart-rate"])
        let entry = makeEntry(profileID: profile.id, isEnabled: true, frequency: .weekly, weekday: 5)
        let summary = ExportProfileCardSummary(
            profile: profile,
            isActive: false,
            destination: .localFolder(vaultName: nil),
            scheduleStatus: .from(entry),
            cadence: ExportProfileCadenceSummary.from(entry),
            formats: ExportProfileCardSummary.sortedFormats(profile.settings.exportFormats),
            enabledMetricCount: profile.settings.metricSelection.enabledMetricIDs.count
        )

        XCTAssertFalse(summary.isActive)
        XCTAssertEqual(summary.formats, [.markdown, .csv])
        XCTAssertEqual(summary.enabledMetricCount, 1)
        XCTAssertEqual(summary.scheduleStatus, .scheduled)
        XCTAssertEqual(summary.cadence?.weekdayIndex, 5)
    }
}
