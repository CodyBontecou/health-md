import XCTest

/// UI tests for schedule and sync journeys.
/// Covers enable/disable schedule, configure time, persistence on relaunch,
/// and sync state transitions.
final class ScheduleSyncJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Schedule Journey

    /// ScheduleG's "Run on a schedule": the former master switch, per automation.
    private static let scheduleSwitch = "glass.schedule.enabled"

    func testScheduleToggle_enableAndConfigure() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: false
        )
        app.launch()

        // Open the first automation's schedule (ScheduleG)
        XCTAssertTrue(UITestLaunchHelper.openScheduleTab(in: app))

        // Turn the automation's schedule on
        let enableToggle = app.switches[Self.scheduleSwitch]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5), "Run on a schedule should be visible")

        let toggleVal = enableToggle.value as? String
        if toggleVal != "1" && toggleVal != "Enabled" {
            enableToggle.tap()
        }

        // Verify the switch is now on; ScheduleG saves as it changes
        let newVal = enableToggle.value as? String
        XCTAssertTrue(newVal == "1" || newVal == "Enabled", "Toggle should be enabled after tap")
    }

    func testCustomSchedule_revealsIntervalUnitAndStartDate() throws {
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        XCTAssertTrue(UITestLaunchHelper.openScheduleTab(in: app))

        // ScheduleG's Repeat control is a glass segmented control of native buttons.
        let customSegment = app.buttons["Custom"].firstMatch
        XCTAssertTrue(customSegment.waitForExistence(timeout: 5), "Custom should be a frequency option")
        customSegment.tap()

        let interval = app.staticTexts["Every"].firstMatch
        let startDate = app.buttons["glass.schedule.starting"]
        XCTAssertTrue(interval.waitForExistence(timeout: 3), "Custom interval should appear")
        XCTAssertTrue(startDate.waitForExistence(timeout: 3), "Custom start date should appear")
    }

    func testScheduleStatus_showsActiveWhenEnabled() throws {
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        // Open the first automation's schedule (ScheduleG)
        XCTAssertTrue(UITestLaunchHelper.openScheduleTab(in: app))

        // The toggle should be ON since configureTestMode saved to UserDefaults
        // and SchedulingManager loads from UserDefaults
        let enableToggle = app.switches[Self.scheduleSwitch]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5))
        let toggleValue = enableToggle.value as? String
        XCTAssertTrue(toggleValue == "1" || toggleValue == "Enabled", "Schedule toggle should be ON when schedule enabled via test mode")
    }

    func testSchedulePersistence_survivesRelaunch() throws {
        // First launch: schedule already enabled via test mode
        let app = UITestLaunchHelper.scheduleEnabledApp()
        app.launch()

        // Open the first automation's schedule (ScheduleG)
        XCTAssertTrue(UITestLaunchHelper.openScheduleTab(in: app))

        let enableToggle = app.switches[Self.scheduleSwitch]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 5))
        let val1 = enableToggle.value as? String
        XCTAssertTrue(val1 == "1" || val1 == "Enabled", "Schedule toggle should be ON on first launch")

        // Terminate and relaunch — no Save needed; bindings persist on change
        app.terminate()

        let app2 = UITestLaunchHelper.scheduleEnabledApp()
        app2.launch()

        XCTAssertTrue(UITestLaunchHelper.openScheduleTab(in: app2))

        let enableToggle2 = app2.switches[Self.scheduleSwitch]
        XCTAssertTrue(enableToggle2.waitForExistence(timeout: 5))
        let val2 = enableToggle2.value as? String
        XCTAssertTrue(val2 == "1" || val2 == "Enabled", "Schedule toggle should be ON after relaunch")
    }

    // MARK: - Sync Journey

    func testSyncView_showsDisconnectedState() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        // Navigate to sync tab
        openDestination("Mac Destination", in: app)

        // Verify sync toggle is visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible")
    }

    func testSyncView_showsConnectedState() throws {
        let app = UITestLaunchHelper.syncApp(state: "connected")
        app.launch()

        // Navigate to sync tab
        openDestination("Mac Destination", in: app)

        // Sync toggle should be visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible")

        // The page header confirms the connected Mac destination view is active.
        let pageTitle = app.staticTexts["Health.md for Mac"]
        XCTAssertTrue(pageTitle.waitForExistence(timeout: 3), "Health.md for Mac page title should be visible")

        // The sync toggle is interactive — verify its accessibility is correct
        XCTAssertTrue(syncToggle.isHittable, "Sync toggle should be hittable")
    }

    func testSyncView_showsConnectingState() throws {
        let app = UITestLaunchHelper.syncApp(state: "connecting")
        app.launch()

        // Navigate to sync tab
        openDestination("Mac Destination", in: app)

        // Sync toggle should be visible
        let syncToggle = app.switches[UITestLaunchHelper.Sync.syncToggle]
        XCTAssertTrue(syncToggle.waitForExistence(timeout: 5), "Sync toggle should be visible in connecting state")
    }

    func testSyncView_switchesToCLIConfigurationWithoutScrolling() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        openDestination("Mac Destination", in: app)

        // Mac Destination and CLI are separate Settings pages now, both one tap from Settings.
        XCTAssertTrue(app.switches[UITestLaunchHelper.Sync.syncToggle].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches[UITestLaunchHelper.Sync.directCLIToggle].exists)
        app.navigationBars.buttons.firstMatch.tap()
        openDestination("CLI", in: app)
        let directCLIToggle = app.switches[UITestLaunchHelper.Sync.directCLIToggle]
        XCTAssertTrue(directCLIToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(directCLIToggle.isHittable, "Direct CLI access toggle should be reachable without scrolling")
    }

    func testSyncToggle_enablesSync() throws {
        let app = UITestLaunchHelper.syncApp(state: "disconnected")
        app.launch()

        // Navigate to sync tab
        openDestination("Mac Destination", in: app)

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

    private func openDestination(_ title: String, in app: XCUIApplication) {
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        // Row titles follow live state (a connected Mac shows its name), so use identifiers.
        let identifiers = ["Mac Destination": "glass.settings.mac", "CLI": "glass.settings.cli"]
        let row = identifiers[title].map { app.buttons[$0] }
            ?? app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(title) must be reachable from Settings")
        row.tap()
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
        XCTAssertTrue(UITestLaunchHelper.openScheduleTab(in: app))
        XCTAssertTrue(app.switches[Self.scheduleSwitch].waitForExistence(timeout: 5))

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

        // ScheduleG has no destination list: an automation's destination is chosen in
        // Output (OutputG "Where"), which its scheduled runs use.
        app.navigationBars["Schedule"].buttons.firstMatch.tap()
        let output = app.buttons["glass.automation.output"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        output.tap()
        let destination = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Destination")
        ).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Output must offer a destination choice")
        destination.tap()
        keep("output-destination-menu")
        XCTAssertTrue(app.buttons["API Endpoint"].waitForExistence(timeout: 5), "Scheduled API target should exist")
    }
}
