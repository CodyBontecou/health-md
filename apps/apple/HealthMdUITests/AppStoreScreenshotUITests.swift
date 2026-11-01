import XCTest

/// Captures the raw screens behind the App Store slides. Runs only when
/// `APPSTORE_SCREENSHOT_DIR` is set; files are prefixed with `APPSTORE_DEVICE` (default `iphone`).
final class AppStoreScreenshotUITests: XCTestCase {
    private var directory: String? { ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOT_DIR"] }

    private func save(_ name: String) {
        guard let directory else { return }
        let device = ProcessInfo.processInfo.environment["APPSTORE_DEVICE"] ?? "iphone"
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(device)-\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func launch() -> XCUIApplication {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            scheduleEnabled: true,
            useHealthKitExportPreviewFixtures: true,
            macExportStatus: "ready"
        )
        app.launchEnvironment["UITEST_SEED_COVERAGE"] = "true"
        app.launch()
        return app
    }

    /// Opens the first automation and, optionally, one of its pages by row title.
    private func openAutomation(_ app: XCUIApplication, row: String?) {
        let tab = app.buttons["glass.tab.automations"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let card = app.buttons["glass.automation.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        guard let row else { return }
        let target = app.staticTexts[row].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing row \(row)")
        target.tap()
    }

    private func switchOn(_ app: XCUIApplication, _ label: String) {
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        guard toggle.waitForExistence(timeout: 3) else { return }
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
    }

    private func capture(_ name: String, _ steps: (XCUIApplication) -> Void) {
        let app = launch()
        steps(app)
        sleep(2)
        save(name)
        app.terminate()
    }

    func testCaptureAppStoreScreens() throws {
        guard directory != nil else { throw XCTSkip("Set APPSTORE_SCREENSHOT_DIR to capture App Store screens.") }
        continueAfterFailure = true

        capture("archive") { app in
            XCTAssertTrue(app.buttons["glass.exportNow"].waitForExistence(timeout: 10))
            // Show the last full month of seeded coverage.
            let previous = app.buttons["Previous month"].firstMatch
            if previous.waitForExistence(timeout: 3) { previous.tap() }
        }
        capture("export-now") { app in
            let button = app.buttons["glass.exportNow"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            XCTAssertTrue(app.buttons["glass.exportNow.confirm"].waitForExistence(timeout: 5))
        }
        capture("export-preview") { app in
            let button = app.buttons["glass.exportNow"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            let preview = app.buttons["glass.exportNow.preview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            preview.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
                    .waitForExistence(timeout: 15)
            )
        }
        capture("automation") { app in openAutomation(app, row: nil) }
        capture("formats") { app in
            openAutomation(app, row: "Formats")
            // Unsaved: shows every format switched on, as on the slide.
            for name in ["Obsidian Bases", "JSON", "CSV"] { switchOn(app, name) }
        }
        capture("daily-notes") { app in
            openAutomation(app, row: "Daily notes")
            switchOn(app, "Merge into daily notes")
        }
        capture("metrics") { app in openAutomation(app, row: "Metrics") }
        capture("customize-format") { app in openAutomation(app, row: "Customize format") }
        capture("entries") { app in
            openAutomation(app, row: "Individual entries")
            switchOn(app, "One file per health event")
        }
        capture("schedule") { app in openAutomation(app, row: "Schedule") }
        capture("mac") { app in
            let tab = app.buttons["glass.tab.settings"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            let row = app.staticTexts["Mac Destination"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.descendants(matching: .any)["glass.macDestination"].waitForExistence(timeout: 5))
        }
    }
}
