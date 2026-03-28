import XCTest

/// UI tests for the first-run export journey: auth -> vault -> export.
/// Uses test-mode DI hooks to simulate authorized state and vault selection.
final class ExportJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - First-Run Export Journey

    func testFirstRunExportJourney_showsExportButton_andCompletesExport() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // Verify app launched and is on the export tab (default)
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export button should be visible on launch")

        // Verify health badge shows connected (CompactStatusBadge is a Button)
        let healthBadge = app.buttons[UITestLaunchHelper.Export.healthBadge]
        XCTAssertTrue(healthBadge.waitForExistence(timeout: 3), "Health badge should be visible")

        // Verify vault badge shows connected
        let vaultBadge = app.buttons[UITestLaunchHelper.Export.vaultBadge]
        XCTAssertTrue(vaultBadge.waitForExistence(timeout: 3), "Vault badge should be visible")

        // Tap export button — should show export modal (no paywall since unlocked)
        // In test mode, simulateTestExport runs immediately (bypasses export modal)
        exportButton.tap()

        // After the simulated export, the status badge should appear
        // ExportStatusBadge is a complex view — use descendants query
        let statusBadge = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 10), "Export status badge should appear after export")
    }

    func testExportButton_disabledWithoutHealthAuth() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: false,
            vaultSelected: true,
            purchaseUnlocked: true
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertFalse(exportButton.isEnabled, "Export button should be disabled without health authorization")
    }

    func testExportButton_disabledWithoutVault() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertFalse(exportButton.isEnabled, "Export button should be disabled without vault selected")
    }

    // MARK: - Tab Navigation

    func testTabNavigation_switchesBetweenTabs() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // Start on export tab
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Navigate to schedule tab
        let scheduleTab = app.buttons[UITestLaunchHelper.Tab.schedule]
        XCTAssertTrue(scheduleTab.exists, "Schedule tab should exist")
        scheduleTab.tap()

        let scheduleSetup = app.buttons[UITestLaunchHelper.Schedule.setupButton]
        XCTAssertTrue(scheduleSetup.waitForExistence(timeout: 3), "Schedule setup button should appear")

        // Navigate to sync tab
        let syncTab = app.buttons[UITestLaunchHelper.Tab.sync]
        syncTab.tap()

        // Navigate back to export
        let exportTab = app.buttons[UITestLaunchHelper.Tab.export]
        exportTab.tap()
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
    }
}
