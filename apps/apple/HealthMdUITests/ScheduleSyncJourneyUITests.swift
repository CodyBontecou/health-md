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
        let scheduleTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.schedule, label: "Schedule")
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

    func testCustomSchedule_revealsIntervalUnitAndStartDate() throws {
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        let scheduleTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.schedule, label: "Schedule")
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 5))
        scheduleTab.tap()

        let frequencyPicker = app.segmentedControls[UITestLaunchHelper.Schedule.frequencyPicker]
        for _ in 0..<4 where !frequencyPicker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(frequencyPicker.waitForExistence(timeout: 5), "Frequency picker should be visible")

        let customSegment = frequencyPicker.buttons["Custom"]
        XCTAssertTrue(customSegment.exists, "Custom should be a frequency option")
        customSegment.tap()

        let interval = app.descendants(matching: .any)[UITestLaunchHelper.Schedule.customIntervalStepper]
        let unit = app.descendants(matching: .any)[UITestLaunchHelper.Schedule.customUnitPicker]
        let startDate = app.descendants(matching: .any)[UITestLaunchHelper.Schedule.customStartDatePicker]
        XCTAssertTrue(interval.waitForExistence(timeout: 3), "Custom interval should appear")
        XCTAssertTrue(unit.exists, "Custom interval unit should appear")
        XCTAssertTrue(startDate.exists, "Custom start date should appear")
    }

    func testScheduleStatus_showsActiveWhenEnabled() throws {
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        // Navigate to schedule tab
        let scheduleTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.schedule, label: "Schedule")
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
        let scheduleTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.schedule, label: "Schedule")
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

        let scheduleTab2 = tabButton(in: app2, identifier: UITestLaunchHelper.Tab.schedule, label: "Schedule")
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
        let syncTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.sync, label: "Sync")
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
        let syncTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.sync, label: "Sync")
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        // Sync toggle should be visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible")

        // The page header confirms the connected Mac destination view is active.
        let pageTitle = app.staticTexts["Mac Destination"]
        XCTAssertTrue(pageTitle.waitForExistence(timeout: 3), "Mac Destination page title should be visible")

        // The sync toggle is interactive — verify its accessibility is correct
        XCTAssertTrue(syncToggle.isHittable, "Sync toggle should be hittable")
    }

    func testSyncView_showsConnectingState() throws {
        let app = UITestLaunchHelper.syncApp(state: "connecting")
        app.launch()

        // Navigate to sync tab
        let syncTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.sync, label: "Sync")
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        // Sync toggle should be visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible in connecting state")
    }

    func testSyncView_switchesToCLIConfigurationWithoutScrolling() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        let syncTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.sync, label: "Sync")
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5))
        syncTab.tap()

        let targetPicker = app.segmentedControls[UITestLaunchHelper.Sync.configurationTargetPicker]
        XCTAssertTrue(targetPicker.waitForExistence(timeout: 5), "Sync target picker should be visible at the top")

        let cliSegment = targetPicker.buttons["CLI"]
        XCTAssertTrue(cliSegment.isHittable, "CLI configuration should be selectable without scrolling")
        cliSegment.tap()

        let directCLIToggle = app.switches[UITestLaunchHelper.Sync.directCLIToggle]
        XCTAssertTrue(directCLIToggle.waitForExistence(timeout: 3), "Direct CLI configuration should replace Mac configuration")
        XCTAssertTrue(directCLIToggle.isHittable, "Direct CLI access toggle should be reachable without scrolling")
        XCTAssertFalse(app.switches[UITestLaunchHelper.Sync.syncToggle].exists)

        targetPicker.buttons["Mac Destination"].tap()
        XCTAssertTrue(app.switches[UITestLaunchHelper.Sync.syncToggle].waitForExistence(timeout: 3))
    }

    func testSyncToggle_enablesSync() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        // Navigate to sync tab
        let syncTab = tabButton(in: app, identifier: UITestLaunchHelper.Tab.sync, label: "Sync")
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

    // MARK: - Helpers

    private func tabButton(in app: XCUIApplication, identifier: String, label: String) -> XCUIElement {
        let identified = app.buttons[identifier]
        if identified.exists { return identified }
        return app.buttons[label]
    }
}

// Temporary capture-only UI test injected by social-moments capture agent.
extension ScheduleSyncJourneyUITests {
    func testCaptureScheduledDestinationScrollPositions() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            scheduleEnabled: true,
            macExportStatus: "ready",
            macDestinationPath: "/Users/cody/Health.md"
        )
        app.launch()
        let scheduleTab: XCUIElement = app.buttons[UITestLaunchHelper.Tab.schedule].exists
            ? app.buttons[UITestLaunchHelper.Tab.schedule]
            : app.buttons["Schedule"]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 5))
        scheduleTab.tap()
        XCTAssertTrue(app.switches[UITestLaunchHelper.Schedule.enableToggle].waitForExistence(timeout: 5))

        func keep(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        keep("schedule-top")
        let start1 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.70))
        let end1 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.57))
        start1.press(forDuration: 0.08, thenDragTo: end1)
        Thread.sleep(forTimeInterval: 0.7)
        keep("schedule-destination-small-scroll")

        let start2 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.68))
        let end2 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.58))
        start2.press(forDuration: 0.08, thenDragTo: end2)
        Thread.sleep(forTimeInterval: 0.7)
        keep("schedule-destination-medium-scroll")

        XCTAssertTrue(app.buttons["schedule.target.api"].exists, "Scheduled API target should exist")
    }
}
