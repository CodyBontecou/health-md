import XCTest

/// Shared by isolated production-component UI suites. All targets use synthetic
/// state; this does not launch the shipping Health.md app or change OS settings.
class A11yUITestCase: XCTestCase {
    private var recordingFailure = false

    override func record(_ issue: XCTIssue) {
        if !recordingFailure {
            recordingFailure = true
            let app = XCUIApplication()
            if app.state == .runningForeground {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Failure accessibility hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                saveScreenshot(app, name: "Failure visible screen")
            }
            recordingFailure = false
        }
        super.record(issue)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    /// Use the real software keyboard's AX key spelling (iOS 26 uses "next",
    /// identifier "Next:"). Dismiss only its known first-run typing tutorial.
    func keyboardKey(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.exists {
            let continuation = introduction.buttons["Continue"]
            XCTAssertTrue(continuation.isHittable)
            continuation.tap()
        }
        let key = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        return key
    }

    func assertKeyboardTarget(_ key: XCUIElement, in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard let window = app.windows.allElementsBoundByIndex.first(where: { $0.keyboards.firstMatch.exists }) else {
            XCTFail("No native keyboard owner window")
            return
        }
        // Native bottom-row AX hit slop extends 7pt below the SE window on iOS
        // 26.5. Require an actual visible >=44pt target, not the offscreen slop.
        let visible = key.frame.intersection(keyboard.frame).intersection(window.frame)
        XCTAssertGreaterThanOrEqual(visible.width, 44)
        XCTAssertGreaterThanOrEqual(visible.height, 44)
        XCTAssertTrue(key.isHittable)
    }

    func launchScenario(
        _ scenario: String = "foundation",
        size: String = "large",
        theme: String = "light",
        locale: String = "en_US",
        width: CGFloat? = nil,
        height: CGFloat? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["A11Y_SCENARIO"] = scenario
        app.launchEnvironment["A11Y_SIZE"] = size
        app.launchEnvironment["A11Y_THEME"] = theme
        app.launchEnvironment["A11Y_LOCALE"] = locale
        if let width { app.launchEnvironment["A11Y_WIDTH"] = String(describing: width) }
        if let height { app.launchEnvironment["A11Y_HEIGHT"] = String(describing: height) }
        app.launch()
        return app
    }

    func owningScroll(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement? {
        let match = NSPredicate(format: "identifier == %@ AND label == %@", element.identifier, element.label)
        // Keyboard predictions are also a ScrollView and can become firstMatch.
        // Resolve the actual ancestor; never turn a page drag into typed words.
        let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
        return containers.filter { $0.descendants(matching: element.elementType).matching(match).count > 0 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    func owningWindow(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let match = NSPredicate(format: "identifier == %@ AND label == %@", element.identifier, element.label)
        let frame = element.frame
        let windows = app.windows.allElementsBoundByIndex.filter {
            $0.descendants(matching: element.elementType).matching(match).allElementsBoundByIndex.contains { $0.frame == frame }
        }
        XCTAssertFalse(windows.isEmpty, "No actual window owns \(element)")
        return windows.first ?? app.windows.firstMatch
    }

    func scenarioViewport(in app: XCUIApplication) -> CGRect {
        let root = app.otherElements["a11y.scenario.viewport"]
        let values = (root.value as? String ?? "").split(separator: ",").compactMap { Double($0) }
        guard values.count == 4, values[2] > 0, values[3] > 0 else {
            XCTFail("Missing actual allocated scenario geometry: \(root.value ?? "nil")")
            return .zero
        }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func readingViewport(_ scroll: XCUIElement, in app: XCUIApplication, above obstruction: XCUIElement? = nil) -> CGRect {
        var viewport = scroll.frame.intersection(owningWindow(scroll, in: app).frame)
        let root = app.otherElements["a11y.scenario.viewport"]
        if root.descendants(matching: scroll.elementType).allElementsBoundByIndex.contains(where: { $0.frame == scroll.frame && $0.identifier == scroll.identifier }) {
            // A native navigation/scroll AX frame may include unsafe areas or
            // extend past an embedded proposal. Measure the real allocation.
            viewport = viewport.intersection(scenarioViewport(in: app))
        }
        for bar in app.navigationBars.allElementsBoundByIndex + app.statusBars.allElementsBoundByIndex {
            if bar.frame.intersects(viewport) && bar.frame.minY < viewport.midY {
                let bottom = viewport.maxY
                viewport.origin.y = max(viewport.minY, bar.frame.maxY)
                viewport.size.height = max(0, bottom - viewport.minY)
            }
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            var obstructions = [keyboard.frame]
            let predictions = app.otherElements["SystemInputAssistantView"]
            if predictions.exists { obstructions.append(predictions.frame) }
            obstructions += app.toolbars.allElementsBoundByIndex.map(\.frame).filter { $0.minY > viewport.minY }
            for frame in obstructions where frame.intersects(viewport) {
                viewport.size.height = max(0, frame.minY - viewport.minY)
            }
        }
        for bar in app.tabBars.allElementsBoundByIndex where bar.frame.intersects(viewport) {
            viewport.size.height = max(0, bar.frame.minY - viewport.minY)
        }
        if let obstruction, obstruction.exists, obstruction.frame.intersects(viewport) {
            viewport.size.height = max(0, obstruction.frame.minY - viewport.minY)
        }
        return viewport.insetBy(dx: 0, dy: 1)
    }

    func dragPage(_ scroll: XCUIElement, viewport: CGRect, downward: Bool, distance: CGFloat? = nil) {
        let panRegion = viewport.insetBy(dx: 3, dy: min(44, viewport.height * 0.2))
        let preferredY = min(panRegion.maxY, max(panRegion.minY,
            viewport.minY + viewport.height * (downward ? 0.2 : 0.8)))
        // Start on actual reading content, not the screen-edge back gesture or
        // transparent padding. A date picker's whole native surface can consume
        // a pan, including gaps outside its individual AX wheel columns.
        let embedded = (scroll.scrollViews.allElementsBoundByIndex + scroll.datePickers.allElementsBoundByIndex
                        + scroll.textViews.allElementsBoundByIndex).map(\.frame)
        let buttons = scroll.buttons.allElementsBoundByIndex.map(\.frame)
        let anchors = scroll.staticTexts.allElementsBoundByIndex.compactMap { text -> (point: CGPoint, priority: Int)? in
            let frame = text.frame
            // Partly visible glyphs beside system chrome can report valid AX
            // frames while repeated drags there move nothing (observed y34.5).
            // Start farther inside the reading region, not on that clipped edge.
            let visible = frame.intersection(panRegion)
            guard visible.width >= 8, visible.height >= 8 else { return nil }
            let point = CGPoint(x: visible.midX, y: visible.midY)
            guard !embedded.contains(where: { $0.contains(point) }),
                  (downward ? point.y < viewport.maxY - 24 : point.y > viewport.minY + 24) else { return nil }
            // Prefer fully visible content over a clipped line at the boundary.
            // A button's centered label is a valid page-pan start when it is the
            // only complete content; never mistake its left bounding-box edge
            // for the actual painted/touchable surface.
            let priority = (viewport.contains(frame) ? 0 : 2) + (buttons.contains { $0.contains(point) } ? 1 : 0)
            return (point, priority)
        }
        let point = anchors.min {
            $0.priority == $1.priority ? abs($0.point.y - preferredY) < abs($1.point.y - preferredY) : $0.priority < $1.priority
        }?.point ?? CGPoint(x: viewport.midX, y: preferredY)
        let start = scroll.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - scroll.frame.minX, dy: point.y - scroll.frame.minY))
        let room = downward ? viewport.maxY - point.y - 3 : point.y - viewport.minY - 3
        let travel = min(room, viewport.height * 0.6, max(20, (distance ?? viewport.height) + 12))
        let end = start.withOffset(CGVector(dx: 0, dy: travel * (downward ? 1 : -1)))
        // Finish stationary: a tap during deceleration correctly stops scrolling
        // instead of activating a child. This makes edge callbacks deterministic.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication, above obstruction: XCUIElement? = nil,
                requiresHittable: Bool = true) {
        if !requiresHittable { XCTAssertFalse(element.isEnabled, "Only explicit disabled no-op tests may omit hittability") }
        guard let scroll = owningScroll(element, in: app) else {
            XCTAssertTrue((!requiresHittable || element.isHittable) && owningWindow(element, in: app).frame.contains(element.frame),
                          "Unreachable non-scrolling control: \(element)")
            return
        }
        var previousFrame: CGRect?
        var stalledDrags = 0
        for _ in 0..<80 {
            let frame = element.frame
            stalledDrags = previousFrame == frame ? stalledDrags + 1 : 0
            previousFrame = frame
            let viewport = readingViewport(scroll, in: app, above: obstruction)
            let fitting = viewport.insetBy(dx: -1, dy: -1)
            if (!requiresHittable || element.isHittable) && fitting.contains(element.frame) { return }
            if element.frame.height > viewport.height {
                // A genuinely growing action can be taller than a short window.
                // Require its actual top 44pt (where tapEdge taps) to be visible,
                // rather than demanding impossible simultaneous full-height fit.
                // Reading suites still assert complete copy, wrapping and scrolling.
                var leadingTarget = element.frame
                leadingTarget.size.height = 44
                if (!requiresHittable || element.isHittable) && fitting.contains(leadingTarget) {
                    saveScreenshot(app, name: "growing-control-leading-target-\(element.identifier)")
                    return
                }
            }
            guard viewport.height >= 44 else { XCTFail("No usable reading viewport: \(viewport)"); return }
            let target = element.frame.height > viewport.height
                ? CGRect(x: element.frame.minX, y: element.frame.minY, width: element.frame.width, height: 44)
                : element.frame
            let downward = target.minY < viewport.minY
            let distance = downward ? viewport.minY - target.minY : target.maxY - viewport.maxY
            // Keep remaining-distance precision after movement, but retry an
            // unrecognized tiny pan with more travel. Do not repeat the same
            // stationary gesture 80 times or restore an oscillating fixed stride.
            let recognitionTravel = min(CGFloat(stalledDrags) * 20, 100)
            dragPage(scroll, viewport: viewport, downward: downward, distance: distance + recognitionTravel)
        }
        XCTFail("Target not fully reachable: \(element), target=\(element.frame), viewport=\(readingViewport(scroll, in: app, above: obstruction)), scroll=\(scroll.frame)")
    }

    func tapEdge(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    func tapDisabledEdge(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app, requiresHittable: false)
        XCTAssertFalse(element.isEnabled)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
