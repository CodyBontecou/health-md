import XCTest

final class OnboardingJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Onboarding v2: Welcome → Packs → Apple Health → Folder → First note →
    /// Make it daily, landing on the configured "Daily note" automation.
    func testPackFlowReachesFirstNoteAndLandsOnDailyNoteAutomation() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            showOnboarding: true,
            showReleaseNotes: true,
            purchaseUnlocked: false,
            useHealthKitExportPreviewFixtures: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Get started", in: app)

        // Sleep, Activity and Heart are preselected; Cycle Tracking stays opt-in.
        XCTAssertTrue(app.buttons["onboarding.pack.sleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.pack.sleep"].isSelected)
        XCTAssertFalse(app.buttons["onboarding.pack.cycle"].isSelected)
        tapButton("Connect Apple Health", in: app)

        // Already authorized in this fixture, so the step offers Continue.
        tapButton("Continue", in: app)

        // Skipping the folder keeps the free export unused.
        tapButton("Skip for now", in: app)

        XCTAssertTrue(app.buttons["onboarding.firstNote.rawToggle"].waitForExistence(timeout: 15))
        app.buttons["onboarding.firstNote.rawToggle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.firstNote.raw"].waitForExistence(timeout: 5))
        tapButton("Finish setup", in: app)

        XCTAssertTrue(app.staticTexts["Make it daily?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
        tapButton("Not now, I'll export manually", in: app)

        // The existing Default automation is configured, not a second one.
        XCTAssertTrue(app.staticTexts["Daily note"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["glass.automation.tryFree"].exists)
        XCTAssertFalse(app.staticTexts["whatsNew.title"].exists)
    }

    func testUnpaidUserReachesSetupWithoutAPaywall() throws {
        let app = UITestLaunchHelper.configuredApp(showOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }

    func testWelcomeLeavesSharedSetupImportToSettings() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            purchaseUnlocked: true,
            analyticsTransport: "offline"
        )
        app.launch()

        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.descendants(matching: .any)[UITestLaunchHelper.SharedSetup.use].exists,
            "OnboardingG's welcome has no shared-setup link; import stays in Settings."
        )
    }

    func testSettingsProvidesSharedSetupConfigurationCard() throws {
        let app = UITestLaunchHelper.configuredApp(purchaseUnlocked: true, analyticsTransport: "offline")
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }
        let controls = openSharedSetupSettings(in: app)

        controls.use.tap()
        XCTAssertTrue(
            app.staticTexts["Recents"].waitForExistence(timeout: 5) ||
                app.staticTexts["Browse"].waitForExistence(timeout: 2) ||
                app.buttons["Cancel"].waitForExistence(timeout: 2),
            "The Settings configuration card should present the native document picker."
        )
    }

    func testSettingsShareMenuPresentsNativeFileExporter() throws {
        let app = UITestLaunchHelper.configuredApp(purchaseUnlocked: true, analyticsTransport: "offline")
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }
        let controls = openSharedSetupSettings(in: app)

        controls.share.tap()
        let saveToFiles = app.buttons["Save to Files"]
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 3))
        saveToFiles.tap()
        XCTAssertTrue(
            app.buttons["Save"].waitForExistence(timeout: 5),
            "Save to Files should present the native file exporter."
        )
    }

    func testSettingsShareMenuPresentsSystemShareSheet() throws {
        let app = UITestLaunchHelper.configuredApp(purchaseUnlocked: true, analyticsTransport: "offline")
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }
        let controls = openSharedSetupSettings(in: app)

        controls.share.tap()
        let systemShare = app.buttons["System Share"]
        XCTAssertTrue(systemShare.waitForExistence(timeout: 3))
        systemShare.tap()
        XCTAssertTrue(
            app.staticTexts["AirDrop"].waitForExistence(timeout: 5) ||
                app.buttons["AirDrop"].waitForExistence(timeout: 2) ||
                app.otherElements["ActivityListView"].waitForExistence(timeout: 2),
            "System Share should present the native activity sheet."
        )
    }

    func testReleaseNotesStillAppearForReturningUsers() throws {
        let app = UITestLaunchHelper.configuredApp(showReleaseNotes: true, purchaseUnlocked: true)
        app.launch()

        XCTAssertTrue(
            app.staticTexts["whatsNew.title"].waitForExistence(timeout: 8),
            "Returning users should still receive the current release notes for an unseen app version."
        )
        app.buttons["whatsNew.continue"].tap()
        XCTAssertTrue(app.staticTexts["whatsNew.title"].waitForNonExistence(timeout: 5))
    }

    func testHealthAndFolderStepsCanBeSkippedAndRepairedLater() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            purchaseUnlocked: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Get started", in: app)
        tapButton("Connect Apple Health", in: app)

        XCTAssertTrue(app.buttons["Continue to Apple Health"].waitForExistence(timeout: 5))
        tapButton("Skip for now", in: app)

        XCTAssertTrue(app.buttons["Choose a folder"].waitForExistence(timeout: 5))
        tapButton("Skip for now", in: app)

        // Without Health access the first note is an explicitly labelled sample.
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.firstNote.sampleNotice"].waitForExistence(timeout: 10))
        tapButton("Finish setup", in: app)

        // Paid access: the schedule can be turned on directly, no trial copy.
        XCTAssertTrue(app.buttons["Turn on daily notes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start 7-day free trial"].exists)
    }

    private func openSharedSetupSettings(
        in app: XCUIApplication
    ) -> (use: XCUIElement, share: XCUIElement) {
        UITestLaunchHelper.openSettingsTab(in: app)

        let configurationCard = app.descendants(matching: .any)[
            UITestLaunchHelper.SharedSetup.configurationCard
        ]
        let use = app.descendants(matching: .any)[UITestLaunchHelper.SharedSetup.use]
        for _ in 0..<8 where !use.isHittable {
            app.swipeUp()
        }
        let share = app.descendants(matching: .any)[UITestLaunchHelper.SharedSetup.share]

        XCTAssertTrue(configurationCard.waitForExistence(timeout: 5))
        XCTAssertTrue(use.exists)
        XCTAssertTrue(use.isHittable)
        XCTAssertTrue(share.exists)
        XCTAssertTrue(share.isHittable)
        XCTAssertEqual(use.elementType, .button)
        XCTAssertEqual(share.elementType, .button)
        XCTAssertGreaterThanOrEqual(use.frame.height, 40)
        XCTAssertGreaterThanOrEqual(share.frame.height, 40)
        return (use, share)
    }

    private func tapButton(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Expected onboarding button: \(label)")
        XCTAssertTrue(button.isHittable, "Onboarding button should be tappable: \(label)")
        button.tap()
    }
}
