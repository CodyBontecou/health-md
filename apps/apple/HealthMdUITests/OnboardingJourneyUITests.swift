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
            useHealthKitExportPreviewFixtures: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Start Setup", in: app)

        // Health, sample export, and Obsidian plugin screens.
        tapButton("Continue Setup", in: app)
        tapButton("Continue Setup", in: app)
        tapButton("Continue Setup", in: app)

        // Keep folder setup optional and verify the explicit skip path remains usable.
        tapButton("Skip for Now", in: app)
        tapButton("Try 10 Free Exports", in: app)
        tapButton("Create My First Export", in: app)

        let markdownRow = app.descendants(matching: .any)[
            UITestLaunchHelper.ExportPreview.markdownFileRow
        ]
        XCTAssertTrue(
            markdownRow.waitForExistence(timeout: 15),
            "Completing onboarding should open the preconfigured first-export preview instead of unseen release notes."
        )
        XCTAssertFalse(
            app.staticTexts["Clearer, more reliable exports"].exists,
            "Release notes should not replace the first-export preview after initial onboarding."
        )
    }

    func testUseSharedSetupSecondaryActionPresentsNativeDocumentPicker() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            analyticsTransport: "offline"
        )
        app.launch()

        let useSharedSetup = app.descendants(matching: .any)[UITestLaunchHelper.SharedSetup.use]
        XCTAssertTrue(useSharedSetup.waitForExistence(timeout: 8))
        XCTAssertTrue(useSharedSetup.isHittable)
        useSharedSetup.tap()

        let recents = app.staticTexts["Recents"]
        let browse = app.staticTexts["Browse"]
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(
            recents.waitForExistence(timeout: 5) ||
                browse.waitForExistence(timeout: 2) ||
                cancel.waitForExistence(timeout: 2),
            "Use a Shared Setup should present the native document picker."
        )

        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(useSharedSetup.waitForExistence(timeout: 3))
        useSharedSetup.tap()
        XCTAssertTrue(
            app.staticTexts["Recents"].waitForExistence(timeout: 5) ||
                app.staticTexts["Browse"].waitForExistence(timeout: 2) ||
                app.buttons["Cancel"].waitForExistence(timeout: 2),
            "Cancelling should leave the shared setup importer reusable."
        )
    }

    func testSettingsProvidesSharedSetupConfigurationCard() throws {
        let app = UITestLaunchHelper.configuredApp(analyticsTransport: "offline")
        app.launch()
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
        let app = UITestLaunchHelper.configuredApp(analyticsTransport: "offline")
        app.launch()
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
        let app = UITestLaunchHelper.configuredApp(analyticsTransport: "offline")
        app.launch()
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
        let app = UITestLaunchHelper.configuredApp(showReleaseNotes: true)
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Wake requests and a clearer Sync tab"].waitForExistence(timeout: 8),
            "Returning users should still receive the current release notes for an unseen app version."
        )
    }

    func testSetupActionsArePrimaryAndReadyOffersRepairs() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Start Setup", in: app)
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip for Now"].exists)
        tapButton("Skip for Now", in: app)

        tapButton("Continue Setup", in: app)
        tapButton("Continue Setup", in: app)

        XCTAssertTrue(app.buttons["Select Export Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip for Now"].exists)
        tapButton("Skip for Now", in: app)
        tapButton("Try 10 Free Exports", in: app)

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
        if app.windows.firstMatch.frame.width > 600 {
            let settingsSidebarItem = app.staticTexts["Settings"]
            XCTAssertTrue(settingsSidebarItem.waitForExistence(timeout: 10))
            settingsSidebarItem.tap()
        } else {
            let identifiedSettingsTab = app.buttons[UITestLaunchHelper.Tab.settings]
            if identifiedSettingsTab.waitForExistence(timeout: 3) {
                identifiedSettingsTab.tap()
            } else {
                let labeledSettingsTab = app.buttons["Settings"]
                XCTAssertTrue(labeledSettingsTab.waitForExistence(timeout: 7))
                labeledSettingsTab.tap()
            }
        }

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
        return (use, share)
    }

    private func tapButton(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Expected onboarding button: \(label)")
        XCTAssertTrue(button.isHittable, "Onboarding button should be tappable: \(label)")
        button.tap()
    }
}
