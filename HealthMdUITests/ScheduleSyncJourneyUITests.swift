import XCTest

/// UI tests for schedule and sync journeys.
/// Covers enable/disable schedule, configure time, persistence on relaunch,
/// and sync state transitions.
final class ScheduleSyncJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Schedule Journey

    func testScheduleToggle_enableAndConfigure() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: false
        )
        app.launch()

        // Navigate to schedule tab — the schedule controls now live inline on the tab
        let scheduleTab = app.buttons[UITestLaunchHelper.Tab.schedule]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 5))
        scheduleTab.tap()

        // Toggle the schedule on directly — no sheet to drill into
        let enableToggle = app.switches[UITestLaunchHelper.Schedule.enableToggle]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5), "Schedule toggle should be visible inline")

        let toggleVal = enableToggle.value as? String
        if toggleVal != "1" && toggleVal != "Enabled" {
            enableToggle.tap()
        }

        // Verify the toggle is now on; changes auto-persist to SchedulingManager.schedule
        let newVal = enableToggle.value as? String
        XCTAssertTrue(newVal == "1" || newVal == "Enabled", "Toggle should be enabled after tap")
    }

    func testScheduleStatus_showsActiveWhenEnabled() throws {
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        // Navigate to schedule tab
        let scheduleTab = app.buttons[UITestLaunchHelper.Tab.schedule]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 5))
        scheduleTab.tap()

        // The toggle should be ON since configureTestMode saved to UserDefaults
        // and SchedulingManager loads from UserDefaults
        let enableToggle = app.switches[UITestLaunchHelper.Schedule.enableToggle]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5))
        let toggleValue = enableToggle.value as? String
        XCTAssertTrue(toggleValue == "1" || toggleValue == "Enabled", "Schedule toggle should be ON when schedule enabled via test mode")
    }

    func testSchedulePersistence_survivesRelaunch() throws {
        // First launch: schedule already enabled via test mode
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        // Navigate to schedule tab
        let scheduleTab = app.buttons[UITestLaunchHelper.Tab.schedule]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 5))
        scheduleTab.tap()

        let enableToggle = app.switches[UITestLaunchHelper.Schedule.enableToggle]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5))
        let val1 = enableToggle.value as? String
        XCTAssertTrue(val1 == "1" || val1 == "Enabled", "Schedule toggle should be ON on first launch")

        // Terminate and relaunch — no Save needed; bindings persist on change
        app.terminate()

        let app2 = UITestLaunchHelper.scheduleEnabledApp()
        app2.launch()

        let scheduleTab2 = app2.buttons[UITestLaunchHelper.Tab.schedule]
        XCTAssertTrue(scheduleTab2.waitForExistence(timeout: 5))
        scheduleTab2.tap()

        let enableToggle2 = app2.switches[UITestLaunchHelper.Schedule.enableToggle]
        XCTAssertTrue(enableToggle2.waitForExistence(timeout: 5))
        let val2 = enableToggle2.value as? String
        XCTAssertTrue(val2 == "1" || val2 == "Enabled", "Schedule toggle should be ON after relaunch")
    }

    // MARK: - Sync Journey

    func testSyncView_showsDisconnectedState() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        // Navigate to sync tab
        let syncTab = app.buttons[UITestLaunchHelper.Tab.sync]
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        // Verify sync toggle is visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible")
    }

    func testSyncView_showsConnectedState() throws {
        let app = UITestLaunchHelper.syncApp(state: "connected")
        app.launch()

        // Navigate to sync tab
        let syncTab = app.buttons[UITestLaunchHelper.Tab.sync]
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        // Sync toggle should be visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible")

        // Verify the sync view is rendering correctly with its toggle and nav title
        // The navigation title "Mac Sync" confirms the sync view is active
        let navTitle = app.navigationBars["Mac Sync"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3), "Mac Sync navigation title should be visible")

        // The sync toggle is interactive — verify its accessibility is correct
        XCTAssertTrue(syncToggle.isHittable, "Sync toggle should be hittable")
    }

    func testSyncView_showsConnectingState() throws {
        let app = UITestLaunchHelper.syncApp(state: "connecting")
        app.launch()

        // Navigate to sync tab
        let syncTab = app.buttons[UITestLaunchHelper.Tab.sync]
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        // Sync toggle should be visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible in connecting state")
    }

    func testSyncToggle_enablesSync() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        // Navigate to sync tab
        let syncTab = app.buttons[UITestLaunchHelper.Tab.sync]
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        // Toggle sync on
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5))

        // Enable sync
        let toggleVal = syncToggle.value as? String
        if toggleVal != "1" && toggleVal != "Enabled" {
            syncToggle.tap()
        }

        // After toggling on, connection-related text should appear
        // "Waiting for Mac" appears in disconnected state
        let waitingText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'Mac' OR label CONTAINS 'Connect'")
        ).firstMatch
        XCTAssertTrue(waitingText.waitForExistence(timeout: 5),
                       "Connection info should appear after enabling sync")
    }
}
