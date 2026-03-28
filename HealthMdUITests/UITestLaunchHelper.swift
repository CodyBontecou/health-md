import XCTest

/// Reusable helper for configuring `XCUIApplication` launch arguments
/// and environment variables for deterministic UI test scenarios.
///
/// Mirror of `AccessibilityID` constants — keep identifiers in sync
/// with the main target's `AccessibilityIdentifiers.swift`.
enum UITestLaunchHelper {

    // MARK: - Accessibility Identifiers (mirrored from AccessibilityID)

    enum Tab {
        static let export = "tab.export"
        static let schedule = "tab.schedule"
        static let sync = "tab.sync"
        static let settings = "tab.settings"
    }

    enum Export {
        static let exportButton = "export.exportButton"
        static let cancelExportButton = "export.cancelButton"
        static let healthBadge = "export.healthBadge"
        static let vaultBadge = "export.vaultBadge"
        static let freeExportsLabel = "export.freeExportsLabel"
    }

    enum ExportModal {
        static let exportButton = "exportModal.exportButton"
        static let cancelButton = "exportModal.cancelButton"
    }

    enum Paywall {
        static let view = "paywall.view"
        static let unlockButton = "paywall.unlockButton"
        static let restoreButton = "paywall.restoreButton"
        static let dismissButton = "paywall.dismissButton"
        static let title = "paywall.title"
        static let subtitle = "paywall.subtitle"
    }

    enum Schedule {
        static let setupButton = "schedule.setupButton"
        static let statusText = "schedule.statusText"
        static let enableToggle = "schedule.enableToggle"
        static let frequencyPicker = "schedule.frequencyPicker"
        static let hourPicker = "schedule.hourPicker"
        static let minutePicker = "schedule.minutePicker"
        static let saveButton = "schedule.saveButton"
        static let cancelButton = "schedule.cancelButton"
    }

    enum Sync {
        static let syncToggle = "sync.syncToggle"
        static let connectionStatus = "sync.connectionStatus"
        static let manualSyncButton = "sync.manualSyncButton"
    }

    enum Status {
        static let exportStatusBadge = "status.exportBadge"
    }

    // MARK: - Scenario Configuration

    /// Configures the app for a specific UI test scenario.
    /// Always adds `--uitesting` and resets state for a clean run.
    static func configuredApp(
        healthAuthorized: Bool = false,
        vaultSelected: Bool = false,
        purchaseUnlocked: Bool = false,
        freeExportsUsed: Int = 0,
        syncState: String = "disconnected",
        scheduleEnabled: Bool = false,
        exportResult: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_HEALTH_AUTHORIZED": healthAuthorized ? "true" : "false",
            "UITEST_VAULT_SELECTED": vaultSelected ? "true" : "false",
            "UITEST_PURCHASE_UNLOCKED": purchaseUnlocked ? "true" : "false",
            "UITEST_FREE_EXPORTS_USED": "\(freeExportsUsed)",
            "UITEST_SYNC_STATE": syncState,
            "UITEST_SCHEDULE_ENABLED": scheduleEnabled ? "true" : "false",
        ]
        if let exportResult {
            app.launchEnvironment["UITEST_EXPORT_RESULT"] = exportResult
        }
        return app
    }

    /// App configured for first-run export journey:
    /// Health authorized, vault selected, unlocked, ready to export.
    static func firstRunExportApp() -> XCUIApplication {
        configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true
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
