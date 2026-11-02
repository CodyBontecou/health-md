import XCTest

final class OnboardingJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReadyCTACompletesOnboardingAndOpensFirstExportPreview() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            showOnboarding: true,
            showReleaseNotes: true,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Connect Apple Health", in: app)

        // Health access, then the archive folder (OnboardingG phase 2).
        tapButton("Continue Setup", in: app)

        // Keep folder setup optional and verify the explicit skip path remains usable.
        tapButton("Skip for Now", in: app)

        // Sample export preview (phase 3, with the folded-in plugin promo), then ready.
        tapButton("Continue Setup", in: app)
        tapButton("Create My First Export", in: app)

        let markdownRow = app.descendants(matching: .any)[
            UITestLaunchHelper.ExportPreview.markdownFileRow
        ]
        XCTAssertTrue(
            markdownRow.waitForExistence(timeout: 15),
            "Completing onboarding should open the preconfigured first-export preview instead of unseen release notes."
        )
        XCTAssertFalse(
            app.staticTexts["whatsNew.title"].exists,
            "Release notes should not replace the first-export preview after initial onboarding."
        )
    }

    // Historical selector retained for existing test consumers. The access wall
    // now precedes onboarding; an unpaid install cannot reach the first preview.
    func testPostOnboardingPaywallAppearsAfterFirstPreviewCloses() throws {
        let app = UITestLaunchHelper.configuredApp(showOnboarding: true)
        app.launch()
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Paywall.title].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start Setup"].exists)
        XCTAssertFalse(app.buttons[UITestLaunchHelper.Paywall.dismissButton].exists)
    }

    func testWelcomeLeavesSharedSetupImportToSettings() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            purchaseUnlocked: true,
            analyticsTransport: "offline"
        )
        app.launch()

        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 8))
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

    func testSetupActionsArePrimaryAndReadyOffersRepairs() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            purchaseUnlocked: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Connect Apple Health", in: app)
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip for Now"].exists)
        tapButton("Skip for Now", in: app)

        // Paid-access setup keeps health and folder permissions repairable;
        // the root access gate has already been satisfied by this fixture.
        XCTAssertTrue(app.buttons["Select Export Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip for Now"].exists)
        tapButton("Skip for Now", in: app)

        // The sample-export preview follows the folder step.
        tapButton("Continue Setup", in: app)

        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Folder"].exists)
        XCTAssertTrue(app.buttons["Create My First Export"].exists)

        tapButton("Create My First Export", in: app)
        // Geist dialogs are in-tree SwiftUI overlays rather than native UIAlert instances.
        let setupPromptTitle = app.staticTexts["Finish Preview Setup"]
        XCTAssertTrue(setupPromptTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 3))
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
