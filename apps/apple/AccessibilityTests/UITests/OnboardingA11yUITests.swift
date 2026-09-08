import XCTest

/// ADDED / NOT RUN in the source-only lane. This launches the isolated component
/// gallery only; callback counters do not certify HealthKit, StoreKit or analytics.
final class OnboardingA11yUITests: A11yUITestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    private func app(size: String = "large", theme: String = "light", locale: String = "en_US",
                     width: CGFloat = 320, height: CGFloat = 640) -> XCUIApplication {
        let app = launchScenario("onboarding", size: size, theme: theme, locale: locale, width: width, height: height)
        XCTAssertTrue(app.staticTexts["a11y.onboarding.count"].waitForExistence(timeout: 10))
        return app
    }

    private func count(_ expected: Int, in app: XCUIApplication) {
        XCTAssertEqual(app.staticTexts["a11y.onboarding.count"].label, String(expected))
    }

    private func openOffers(in app: XCUIApplication) {
        tapEdge(app.buttons["a11y.onboarding.skip"], in: app)
        count(128, in: app)
    }

    func testSetupActionsGrowAndInvokeOnlyTheirOwnCallbacks() {
        let app = app()
        tapEdge(app.buttons["Choose Folder"], in: app)
        count(2, in: app)
        let fullFolder = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Synthetic Family Archive — complete selected folder name")
        ).firstMatch
        XCTAssertTrue(fullFolder.exists)
        tapEdge(app.buttons["a11y.onboarding.shared"], in: app)
        count(6, in: app)
        let primary = app.buttons["a11y.onboarding.primary"]
        XCTAssertEqual(primary.label, "Connect Apple Health")
        tapEdge(primary, in: app)
        count(7, in: app)
        XCTAssertEqual(primary.label, "Continue Setup")
        saveScreenshot(app, name: "onboarding-setup-large-light")
        tapEdge(primary, in: app)
        XCTAssertTrue(app.buttons["a11y.onboarding.purchase"].exists)
    }

    func testOfferActionsAtAllFourTextSizesInBothThemes() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            for theme in ["light", "dark"] {
                let app = app(size: size, theme: theme)
                openOffers(in: app)
                let family = app.buttons["Family Sharing Lifetime Access"]
                tapEdge(family, in: app)
                XCTAssertTrue(family.isSelected)
                XCTAssertFalse(app.buttons["Individual Lifetime Access"].isSelected)
                count(128, in: app)
                let purchase = app.buttons["a11y.onboarding.purchase"]
                XCTAssertEqual(purchase.label, "Family Lifetime, Share unlimited private exports with up to 5 family members., US$ 1,234.99")
                inspectAndTapOffer(purchase, in: app, name: "onboarding-offer-\(size)-\(theme)")
                count(160, in: app)
                tapEdge(app.buttons["a11y.onboarding.restore"], in: app)
                count(168, in: app)
                tapEdge(app.buttons["a11y.onboarding.retry"], in: app)
                count(184, in: app)
                tapEdge(app.buttons["a11y.onboarding.free"], in: app)
                count(248, in: app)
                app.terminate()
            }
        }
    }

    func testRegionalPaywallPricesLinksAndDismissalAtAX5InNarrowAndShortWindows() {
        for (locale, price) in [("de_DE", "1.234.567,89 €"), ("ar", "١٬٢٣٤٬٥٦٧٫٨٩ ر.س.‏"), ("ja_JP", "￥1,234,567")] {
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                let app = app(size: "accessibility5", theme: landscape ? "dark" : "light", locale: locale,
                              width: landscape ? 568 : 320, height: landscape ? 280 : 480)
                openOffers(in: app)
                tapEdge(app.buttons["a11y.onboarding.show-paywall"], in: app)
                let purchase = app.buttons["a11y.onboarding.paywall-purchase"]
                XCTAssertTrue(purchase.label.contains(price), "Keep the complete supplied regional price")
                inspectAndTapOffer(purchase, in: app, name: "paywall-\(locale)-\(landscape ? "short" : "narrow")")
                count(4224, in: app)
                tapEdge(app.buttons["a11y.onboarding.paywall-restore"], in: app)
                count(6272, in: app)
                // The gallery handles both real production URLs via OpenURLAction;
                // no browser/network operation takes place.
                tapEdge(link("Terms", in: app), in: app)
                count(6784, in: app)
                tapEdge(link("Privacy", in: app), in: app)
                count(7808, in: app)
                tapDismissInItsOwnRow(in: app)
                count(8064, in: app)
                app.terminate()
            }
        }
    }

    func testLoadingDisablesActualPurchaseAndRestoreControls() {
        let app = app(size: "accessibility1", theme: "dark", height: 480)
        openOffers(in: app)
        tapEdge(app.buttons["a11y.onboarding.busy"], in: app)
        let purchase = app.buttons["a11y.onboarding.purchase"]
        XCTAssertFalse(purchase.isEnabled)
        XCTAssertTrue(purchase.label.contains("Loading…"))
        inspectAndTapOffer(purchase, in: app, name: "onboarding-loading")
        count(128, in: app)
        let restore = app.buttons["a11y.onboarding.restore"]
        XCTAssertFalse(restore.isEnabled)
        tapEdge(restore, in: app)
        count(128, in: app)
        tapEdge(app.buttons["a11y.onboarding.busy"], in: app)
        XCTAssertTrue(purchase.isEnabled)
        inspectAndTapOffer(purchase, in: app, name: "onboarding-loading-finished")
        count(160, in: app)
    }

    func testSetupRepairsAndMeaningfulPrimaryActionRemainReachableInShortLandscapeAX5() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = app(size: "accessibility5", theme: "dark", width: 568, height: 280)
        tapEdge(app.buttons["Choose Folder"], in: app)
        count(2, in: app)
        tapEdge(app.buttons["a11y.onboarding.shared"], in: app)
        count(6, in: app)
        let primary = app.buttons["a11y.onboarding.primary"]
        XCTAssertEqual(primary.label, "Connect Apple Health")
        tapEdge(primary, in: app)
        count(7, in: app)
        XCTAssertEqual(primary.label, "Continue Setup")
        saveScreenshot(app, name: "onboarding-setup-AX5-short-landscape-dark")
        tapEdge(primary, in: app)
        tapEdge(app.buttons["a11y.onboarding.free"], in: app)
        count(71, in: app)
    }

    func testBackSkipAndSharedSetupAreIndependentTargets() {
        let app = app(size: "xxxLarge")
        openOffers(in: app)
        tapEdge(app.buttons["Back"], in: app)
        count(16512, in: app)
        XCTAssertEqual(app.buttons["a11y.onboarding.primary"].label, "Connect Apple Health")
        tapEdge(app.buttons["a11y.onboarding.shared"], in: app)
        count(16516, in: app)
        tapEdge(app.buttons["a11y.onboarding.primary"], in: app)
        count(16517, in: app)
    }

    private func link(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.links[title].exists ? app.links[title] : app.buttons[title]
    }

    private func tapDismissInItsOwnRow(in app: XCUIApplication) {
        let dismiss = app.buttons["a11y.onboarding.dismiss"]
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(dismiss.frame))
        XCTAssertLessThanOrEqual(dismiss.frame.maxY, app.scrollViews.firstMatch.frame.minY + 1,
                                 "Dismissal must not cover scrolled purchase text")
        // Not reveal()/tapEdge(): this action's owner is the separate header row.
        dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    /// A full offer can legitimately be taller than the viewport. Inspect it in
    /// overlapping native captures from title through price, then tap its actual
    /// bottom edge. Never demand that tall text fit/shrink into a single screen.
    private func inspectAndTapOffer(_ offer: XCUIElement, in app: XCUIApplication, name: String) {
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        func viewport() -> CGRect {
            scroll.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 0, dy: 4)
        }
        func drag(down: Bool) {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.3)))
        }
        for _ in 0..<60 {
            let visible = viewport()
            if offer.frame.minY >= visible.minY && offer.frame.minY < visible.maxY - 44 { break }
            drag(down: offer.frame.minY < visible.minY)
        }
        XCTAssertGreaterThanOrEqual(offer.frame.minY, viewport().minY)
        XCTAssertLessThan(offer.frame.minY, viewport().maxY - 44)
        XCTAssertGreaterThanOrEqual(offer.frame.width, 44)
        XCTAssertGreaterThanOrEqual(offer.frame.height, 44)
        XCTAssertGreaterThanOrEqual(offer.frame.minX, viewport().minX)
        XCTAssertLessThanOrEqual(offer.frame.maxX, viewport().maxX)
        saveScreenshot(app, name: "\(name)-title")
        var slice = 0
        while offer.frame.maxY > viewport().maxY && slice < 60 {
            drag(down: false)
            slice += 1
            saveScreenshot(app, name: "\(name)-slice-\(slice)")
        }
        XCTAssertLessThanOrEqual(offer.frame.maxY, viewport().maxY)
        XCTAssertGreaterThan(offer.frame.maxY, viewport().minY + 4)
        offer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
            .withOffset(CGVector(dx: 0, dy: -3)).tap()
    }
}
