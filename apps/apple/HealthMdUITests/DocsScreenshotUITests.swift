import XCTest

/// Captures the iPhone first-export guide screenshots. Runs only when
/// `DOCS_SCREENSHOT_DIR` is set, optionally with `DOCS_LANGUAGE` (e.g. `es`).
final class DocsScreenshotUITests: XCTestCase {
    private var directory: String? { ProcessInfo.processInfo.environment["DOCS_SCREENSHOT_DIR"] }
    private var language: String? { ProcessInfo.processInfo.environment["DOCS_LANGUAGE"] }

    private func save(_ name: String) {
        guard let directory else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func localized(_ app: XCUIApplication) {
        guard let language else { return }
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
    }

    func testCaptureFirstExportGuide() throws {
        guard directory != nil else { throw XCTSkip("Set DOCS_SCREENSHOT_DIR to capture docs screenshots.") }
        continueAfterFailure = false

        let onboarding = UITestLaunchHelper.configuredApp(healthAuthorized: true, showOnboarding: true, purchaseUnlocked: true)
        localized(onboarding)
        onboarding.launch()
        sleep(3)
        save("onboarding-start")
        onboarding.terminate()

        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true
        )
        localized(app)
        app.launch()
        let exportNow = app.buttons["glass.exportNow"]
        XCTAssertTrue(exportNow.waitForExistence(timeout: 10))
        exportNow.tap()
        XCTAssertTrue(app.buttons["glass.exportNow.confirm"].waitForExistence(timeout: 5))
        sleep(1)
        save("export-now")

        let preview = app.buttons["glass.exportNow.preview"]
        if preview.waitForExistence(timeout: 3) {
            preview.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
                    .waitForExistence(timeout: 15)
            )
            sleep(1)
            save("export-preview")
        }
        app.terminate()

        let metricsApp = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, purchaseUnlocked: true)
        localized(metricsApp)
        metricsApp.launch()
        let tab = metricsApp.buttons["glass.tab.automations"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let card = metricsApp.buttons["glass.automation.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let metrics = metricsApp.buttons["glass.automation.metrics"]
        XCTAssertTrue(metrics.waitForExistence(timeout: 5))
        metrics.tap()
        XCTAssertTrue(metricsApp.descendants(matching: .any)["glass.metrics"].waitForExistence(timeout: 5))
        sleep(1)
        save("metric-selection")
    }
}
