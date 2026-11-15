import Vision
import XCTest

final class ConnectedAppsLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProviderUsesFullReadingWidthAtDefaultTextSize() throws {
        try verifyProviderLayout(contentSize: "UICTContentSizeCategoryL", maximumLabelHeight: 28)
    }

    func testProviderReflowsAtLargeTextSize() throws {
        try verifyProviderLayout(contentSize: "UICTContentSizeCategoryXXXL", maximumLabelHeight: 44)
    }

    private func verifyProviderLayout(contentSize: String, maximumLabelHeight: CGFloat) throws {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, purchaseUnlocked: true)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        app.launch()
        defer { app.terminate() }

        // iPhone uses a tab button; iPad uses a selectable sidebar row.
        let settings = app.descendants(matching: .any)["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let integrations = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Third-Party Integrations")).firstMatch
        try XCTSkipUnless(integrations.exists, "The Third-Party Integrations entry is unavailable on this device/build")
        scrollTo(integrations, in: app)
        integrations.tap()

        let title = app.staticTexts["WHOOP"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        scrollTo(title, in: app)

        let summary = app.staticTexts["Recovery, strain, sleep need, HRV, respiratory rate, and workouts."].firstMatch
        let connect = app.buttons["Connect"].firstMatch
        scrollTo(connect, in: app)
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(connect.isHittable)

        // These catch the original side-by-side rail: WHOOP and Connect broke
        // mid-word and the description had only about a quarter of the screen.
        XCTAssertLessThanOrEqual(title.frame.height, maximumLabelHeight, "Provider name must remain on one line")
        let sheetWidth = app.navigationBars["Connected Apps"].frame.width
        // Text accessibility frames measure glyphs, not the full SwiftUI frame.
        XCTAssertGreaterThan(summary.frame.width, sheetWidth * 0.65, "The action must not take width from the description")
        XCTAssertGreaterThan(connect.frame.width, sheetWidth * 0.7)
        XCTAssertEqual(connect.frame.minX, summary.frame.minX, accuracy: 2)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
        XCTAssertLessThanOrEqual(app.staticTexts["Not Connected"].firstMatch.frame.height, maximumLabelHeight, "Status must not break mid-word")
        XCTAssertGreaterThanOrEqual(connect.frame.minY, summary.frame.maxY, "The action belongs below the description")

        let image = app.screenshot()
        let screenshot = XCTAttachment(screenshot: image)
        screenshot.name = "Connected Apps \(contentSize)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(try recognizedAction(in: image, frame: connect.frame, screen: app.frame).contains("Connect"), "The rendered action must be a single unbroken word")

        app.buttons["Done"].tap()
        XCTAssertTrue(integrations.waitForExistence(timeout: 5))
        XCTAssertFalse(connect.exists)
    }

    private func recognizedAction(in screenshot: XCUIScreenshot, frame: CGRect, screen: CGRect) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = CGRect(
            x: (frame.minX - screen.minX) / screen.width,
            y: 1 - (frame.maxY - screen.minY) / screen.height,
            width: frame.width / screen.width,
            height: frame.height / screen.height
        )
        let image = try XCTUnwrap(screenshot.image.cgImage)
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Could not reach \(element.label)")
    }
}
