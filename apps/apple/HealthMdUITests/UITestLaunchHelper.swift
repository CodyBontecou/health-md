import XCTest

/// Reusable helper for configuring `XCUIApplication` launch arguments
/// and environment variables for deterministic UI test scenarios.
///
/// Mirror of `AccessibilityID` constants — keep identifiers in sync
/// with the main target's `AccessibilityIdentifiers.swift`.
enum UITestLaunchHelper {

    /// Establish navigation before asserting content in the destination. A
    /// missed tab tap must report as navigation failure, not missing profiles.
    static func openSettingsTab(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tab = app.tabBars.buttons["Settings"]
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"),
            object: tab
        )
        guard XCTWaiter().wait(for: [hittable], timeout: 10) == .completed else {
            XCTFail("Settings tab must be hittable before navigation", file: file, line: line)
            return
        }
        if !tab.isSelected { tab.tap() }
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: tab
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [selected], timeout: 10), .completed,
            "Settings tab must become selected before inspecting Settings content",
            file: file, line: line
        )
    }

    // MARK: - Accessibility Identifiers (mirrored from AccessibilityID)

    enum Tab {
        static let export = "tab.export"
        static let schedule = "tab.schedule"
        static let sync = "tab.sync"
        static let settings = "tab.settings"
    }

    enum Export {
        static let exportButton = "export.exportButton"
        static let previewButton = "export.previewButton"
        static let cancelExportButton = "export.cancelButton"
        static let healthBadge = "export.healthBadge"
        static let vaultBadge = "export.vaultBadge"
        static let freeExportsLabel = "export.freeExportsLabel"
        static let localTargetOption = "export.target.local"
        static let macTargetOption = "export.target.mac"
        static let datePresetTodayButton = "export.dateRange.preset.today"
        static let datePresetYesterdayButton = "export.dateRange.preset.yesterday"
        static let datePresetAllTimeButton = "export.dateRange.preset.allTime"
        static let datePresetCustomButton = "export.dateRange.preset.custom"
        static let customStartDatePicker = "export.dateRange.custom.startDate"
        static let customEndDatePicker = "export.dateRange.custom.endDate"
        static let pathPreview = "export.pathPreview"
        static let activityBanner = "export.activityBanner"
        static let filenameEditorButton = "export.filenameEditorButton"
        static let outputEditorSaveButton = "export.outputEditorSaveButton"
        static let sleepDayAttributionPicker = "export.sleepDayAttribution.picker"
    }

    enum Notification {
        static let exportActivity = "notification.exportActivity"
        static let cancelExportButton = "notification.cancelButton"
    }

    enum ExportModal {
        static let datePresetTodayButton = "exportModal.dateRange.preset.today"
        static let datePresetYesterdayButton = "exportModal.dateRange.preset.yesterday"
        static let datePresetAllTimeButton = "exportModal.dateRange.preset.allTime"
        static let datePresetCustomButton = "exportModal.dateRange.preset.custom"
        static let startDatePicker = "exportModal.startDate"
        static let endDatePicker = "exportModal.endDate"
        static let exportButton = "exportModal.exportButton"
        static let cancelButton = "exportModal.cancelButton"
    }

    enum Paywall {
        static let view = "paywall.view"
        static let unlockButton = "paywall.unlockButton"
        static let familyUnlockButton = "paywall.familyUnlockButton"
        static let restoreButton = "paywall.restoreButton"
        static let dismissButton = "paywall.dismissButton"
        static let title = "paywall.title"
        static let subtitle = "paywall.subtitle"
    }

    enum Schedule {
        static let enableToggle = "schedule.enableToggle"
        static let frequencyPicker = "schedule.frequencyPicker"
        static let customIntervalStepper = "schedule.custom.interval"
        static let customUnitPicker = "schedule.custom.unit"
        static let customStartDatePicker = "schedule.custom.startDate"
        static let hourPicker = "schedule.hourPicker"
        static let minutePicker = "schedule.minutePicker"
    }

    enum Sync {
        static let configurationTargetPicker = "sync.configurationTargetPicker"
        static let syncToggle = "sync.syncToggle"
        static let connectionStatus = "sync.connectionStatus"
        static let manualSyncButton = "sync.manualSyncButton"
        static let directCLIToggle = "sync.directCLIToggle"
    }

    enum ConfigurationProtection {
        static let toggle = "configurationProtection.toggle"
        static let section = "configurationProtection.section"
        static let protectedRegion = "configurationProtection.protectedRegion"
        static let toast = "configurationProtection.toast"
    }

    enum Status {
        static let exportStatusBadge = "status.exportBadge"
    }

    enum SharedSetup {
        static let configurationCard = "sharedSetup.configurationCard"
        static let use = "sharedSetup.use"
        static let share = "sharedSetup.share"
        static let review = "sharedSetup.review"
        static let apply = "sharedSetup.apply"
        static let success = "sharedSetup.success"
        static let undo = "sharedSetup.undo"
        static let finish = "sharedSetup.finish"
    }

    enum ExportedFile {
        static let viewer = "exportedFile.viewer"
        static let loading = "exportedFile.loading"
        static let rendered = "exportedFile.rendered"
        static let source = "exportedFile.source"
        static let displayMode = "exportedFile.displayMode"
        static let done = "exportedFile.done"
    }

    enum ExportPreview {
        static let exportButton = "exportPreview.exportButton"
        static let markdownFileRow = "exportPreview.fileRow.Markdown"
        static let fileContent = "exportPreview.fileContent"
    }

    // MARK: - Scenario Configuration

    /// Configures the app for a specific UI test scenario.
    /// Always adds `--uitesting` and resets state for a clean run.
    static func configuredApp(
        healthAuthorized: Bool = false,
        showOnboarding: Bool = false,
        showReleaseNotes: Bool = false,
        vaultSelected: Bool = false,
        purchaseUnlocked: Bool = false,
        freeExportsUsed: Int = 0,
        syncState: String = "disconnected",
        scheduleEnabled: Bool = false,
        duplicateExportProfile: Bool = false,
        configurationProtectionEnabled: Bool = false,
        useHealthKitExportPreviewFixtures: Bool = false,
        exportResult: String? = nil,
        macExportStatus: String = "none",
        macDestinationPath: String = "/tmp/TestMacVault",
        analyticsTransport: String? = nil,
        remoteConfig: String? = nil,
        showsPostOnboardingPaywall: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_HEALTH_AUTHORIZED": healthAuthorized ? "true" : "false",
            "UITEST_HAS_COMPLETED_ONBOARDING": showOnboarding ? "false" : "true",
            "UITEST_SHOW_ONBOARDING": showOnboarding ? "true" : "false",
            "UITEST_SHOW_RELEASE_NOTES": showReleaseNotes ? "true" : "false",
            "UITEST_VAULT_SELECTED": vaultSelected ? "true" : "false",
            "UITEST_PURCHASE_UNLOCKED": purchaseUnlocked ? "true" : "false",
            "UITEST_FREE_EXPORTS_USED": "\(freeExportsUsed)",
            "UITEST_SYNC_STATE": syncState,
            "UITEST_SCHEDULE_ENABLED": scheduleEnabled ? "true" : "false",
            "UITEST_DUPLICATE_EXPORT_PROFILE": duplicateExportProfile ? "true" : "false",
            "UITEST_CONFIGURATION_PROTECTION_ENABLED": configurationProtectionEnabled ? "true" : "false",
            "UITEST_HEALTHKIT_EXPORT_PREVIEW_FIXTURES": useHealthKitExportPreviewFixtures ? "true" : "false",
            "UITEST_MAC_EXPORT_STATUS": macExportStatus,
            "UITEST_MAC_DESTINATION_PATH": macDestinationPath,
            "UITEST_SHOW_POST_ONBOARDING_PAYWALL": showsPostOnboardingPaywall ? "true" : "false",
        ]
        if let exportResult {
            app.launchEnvironment["UITEST_EXPORT_RESULT"] = exportResult
        }
        if let analyticsTransport {
            app.launchEnvironment["UITEST_ANALYTICS_TRANSPORT"] = analyticsTransport
            app.launchEnvironment["PRICING_ANALYTICS_ENABLED"] = "1"
        }
        if let remoteConfig {
            app.launchEnvironment["UITEST_REMOTE_CONFIG"] = remoteConfig
        }
        return app
    }

    /// App configured for first-run export journey:
    /// Health authorized, vault selected, unlocked, ready to export.
    static func firstRunExportApp(duplicateExportProfile: Bool = false) -> XCUIApplication {
        configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            duplicateExportProfile: duplicateExportProfile
        )
    }

    /// App configured with free exports partially used.
    static func freeQuotaApp(exportsUsed: Int) -> XCUIApplication {
        configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            freeExportsUsed: exportsUsed
        )
    }

    /// App configured with schedule enabled.
    static func scheduleEnabledApp() -> XCUIApplication {
        configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
    }

    /// App configured with a specific sync state.
    static func syncApp(state: String) -> XCUIApplication {
        configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: state
        )
    }
}

extension XCUIElement {
    /// Avoid XCTest's initial polling interval for elements already present.
    /// Missing elements retain the full wait; normal XCTest idle synchronization
    /// and the caller's assertions and hittability checks remain enabled.
    func waitUntilExists(timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }
}
