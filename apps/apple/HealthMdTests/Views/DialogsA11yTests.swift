#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import HealthMd

/// Isolated tests host the actual production components,
/// not the app bootstrap. Native keyboard/VoiceOver journeys are separate gates.
@MainActor
final class DialogsA11yTests: XCTestCase {
    func testScrimResolvesToDocumentedBlackAlphaInBothThemes() {
        for (style, alpha) in [(UIUserInterfaceStyle.light, CGFloat(112.0 / 255)), (.dark, CGFloat(179.0 / 255))] {
            let color = UIColor(Color.dialogScrim).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            XCTAssertEqual(r, 0, accuracy: 0.002)
            XCTAssertEqual(g, 0, accuracy: 0.002)
            XCTAssertEqual(b, 0, accuracy: 0.002)
            XCTAssertEqual(a, alpha, accuracy: 0.002, "A transparent scrim neither dims nor receives native taps")
        }
    }

    func testActionRunsExactlyOnceBeforeClearingPresentation() {
        var presented = true
        var events: [String] = []
        let binding = Binding(get: { presented }, set: { presented = $0; events.append("dismiss") })
        let action = GeistDialogAction.action("Save") { events.append("handler:\(presented)") }
        GeistDialogInteraction(actions: [action]).perform(action, isPresented: binding)
        XCTAssertEqual(events, ["handler:true", "dismiss"])
        XCTAssertFalse(presented)
    }

    func testCancellationUsesFirstSecondaryWithoutInvokingOtherActions() {
        var presented = true
        var events: [String] = []
        let actions: [GeistDialogAction] = [
            .action("Save") { events.append("save") },
            .cancel("Keep Draft") { events.append("first:\(presented)") },
            .destructive("Remove") { events.append("remove") },
            .cancel("Other Cancel") { events.append("other") }
        ]
        GeistDialogInteraction(actions: actions).cancel(isPresented: Binding(
            get: { presented }, set: { presented = $0; events.append("dismiss") }
        ))
        XCTAssertEqual(events, ["first:true", "dismiss"])
        XCTAssertFalse(presented)
    }

    func testCancellationWithoutSecondaryDoesNotInvokePrimaryOrDestructive() {
        for hasActions in [false, true] {
            var presented = true
            var calls = 0
            let actions: [GeistDialogAction] = hasActions ? [
                .action("Save") { calls += 1 }, .destructive("Remove") { calls += 1 }
            ] : []
            GeistDialogInteraction(actions: actions).cancel(isPresented: Binding(
                get: { presented }, set: { presented = $0 }
            ))
            XCTAssertFalse(presented)
            XCTAssertEqual(calls, 0)
        }
    }

    func testVisualOrderingAndPrimaryChoicePreserveCallerOrderWithinRoles() {
        let interaction = GeistDialogInteraction(actions: [
            .destructive("Remove", accessibilityIdentifier: "remove"),
            .cancel("Keep", accessibilityIdentifier: "keep"),
            .action("Save", accessibilityIdentifier: "save"),
            .cancel("Other", accessibilityIdentifier: "other")
        ])
        XCTAssertEqual(interaction.orderedActions.compactMap(\.accessibilityIdentifier), ["keep", "other", "remove", "save"])
        XCTAssertEqual(interaction.primaryAction?.accessibilityIdentifier, "remove")
    }

    func testIOSNextTraversesDistinctIndicesAndOnlyFinalDoneSubmits() {
        var events: [String] = []
        let interaction = GeistDialogInteraction(actions: [
            .cancel { events.append("cancel") },
            .action("Save") { events.append("save") },
            .action("Reset") { events.append("reset") }
        ])
        for index in 0..<3 {
            interaction.submit(fieldIndex: index, fieldCount: 3, advancesFocus: true,
                               focus: { events.append("focus:\($0)") }, onAction: { $0.handler() })
        }
        XCTAssertEqual(events, ["focus:1", "focus:2", "save"])
    }

    func testDesktopReturnAndSingleIOSFieldStillSubmitFirstProminentAction() {
        for (index, count, advances) in [(0, 2, false), (1, 2, false), (0, 1, true)] {
            var saves = 0
            GeistDialogInteraction(actions: [.action("Save") { saves += 1 }])
                .submit(fieldIndex: index, fieldCount: count, advancesFocus: advances,
                        focus: { _ in XCTFail("Unexpected traversal") }, onAction: { $0.handler() })
            XCTAssertEqual(saves, 1)
        }
    }

    func testFinalDoneWithoutProminentActionStillDoesNotCancelOrDismiss() {
        var callbacks = 0
        GeistDialogInteraction(actions: [.cancel { callbacks += 1 }])
            .submit(fieldIndex: 1, fieldCount: 2, advancesFocus: true,
                    focus: { _ in XCTFail("Unexpected traversal") }, onAction: { $0.handler() })
        XCTAssertEqual(callbacks, 0)
    }

    func testReducedMotionPolicyRemovesPresentationAndPressAnimation() {
        XCTAssertNil(GeistDialogMotion.presentationAnimation(reduceMotion: true))
        XCTAssertNil(GeistDialogMotion.pressAnimation(reduceMotion: true))
        XCTAssertNotNil(GeistDialogMotion.presentationAnimation(reduceMotion: false))
        XCTAssertNotNil(GeistDialogMotion.pressAnimation(reduceMotion: false))
        // Do not assign EnvironmentValues.accessibilityReduceMotion: it is read-only.
    }

    func testRealCardStaysBoundedAndScrollsInShortNarrowHosts() throws {
        for size in [CGSize(width: 320, height: 200), CGSize(width: 280, height: 160), CGSize(width: 568, height: 200)] {
            for category in [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility5] {
                let host = A11yHosting(card(maximumHeight: size.height - 16, fields: [
                    GeistDialogField(placeholder: "Field Name", text: .constant("synthetic_key")),
                    GeistDialogField(placeholder: "Field Value", text: .constant("synthetic_value"))
                ])
                    .frame(width: min(420, size.width - 16))
                    .environment(\.dynamicTypeSize, category), size: size)
                defer { host.close() }
                let measured = host.measured(proposal: size)
                XCTAssertLessThanOrEqual(measured.width, size.width)
                XCTAssertLessThanOrEqual(measured.height, size.height - 16)
                let scroll = try XCTUnwrap(subviews(of: host.controller.view).compactMap { $0 as? UIScrollView }.first)
                assertBounded(scroll, in: host)
                XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
                XCTAssertTrue([UIScrollView.KeyboardDismissMode.interactive, .interactiveWithAccessory].contains(scroll.keyboardDismissMode),
                              "Actual native dismissal mode: \(scroll.keyboardDismissMode.rawValue)")
                // Exercise the production scroll view all the way to the action end.
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                XCTAssertGreaterThan(scroll.contentOffset.y, 0)
                XCTAssertEqual(scroll.contentOffset.y + scroll.bounds.height, scroll.contentSize.height, accuracy: 1)
            }
        }
    }

    func testActualPresentationOverlayDoesNotOverflowItsHost() throws {
        for size in [CGSize(width: 320, height: 200), CGSize(width: 280, height: 160), CGSize(width: 568, height: 200)] {
            let host = A11yHosting(Color.bgPrimary.geistDialog(
                isPresented: .constant(true), title: Text("Long Synthetic Dialog"),
                message: Text(verbatim: longMessage), actions: [.cancel(), .action("Save Fields")],
                fields: [
                    GeistDialogField(placeholder: "Field Name", text: .constant("synthetic_key")),
                    GeistDialogField(placeholder: "Field Value", text: .constant("synthetic_value"))
                ]
            ).environment(\.dynamicTypeSize, .accessibility5), size: size)
            defer { host.close() }
            _ = host.measured(proposal: size)
            let scroll = try XCTUnwrap(subviews(of: host.controller.view).compactMap { $0 as? UIScrollView }.first)
            assertBounded(scroll, in: host)
            XCTAssertLessThan(scroll.bounds.height, size.height)
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
            let attachment = XCTAttachment(image: host.capture())
            attachment.name = "production-dialog-overlay-\(Int(size.width))x\(Int(size.height))-ax5"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testRealFieldsKeepExactValuesAndGrowAfterLiveTextSizeChange() throws {
        let originals = ["  synthetic_key_without_any_normalization  ", "Synthetic first line\nSynthetic second line"]
        var values = originals
        var writes = 0
        let fields = originals.indices.map { index in
            GeistDialogField(placeholder: index == 0 ? "Field name with a complete external explanation" : "Value with a different external explanation",
                             text: Binding(get: { values[index] }, set: {
                                 // Native focus may echo the unchanged value. Count
                                 // actual text changes, not identical round-trips.
                                 if values[index] != $0 { writes += 1 }
                                 values[index] = $0
                             }))
        }
        // Native single-line TextField renders newlines as spaces. Compare the
        // production editor with that actual native control, while separately
        // proving raw bindings are never rewritten during layout/reflow.
        let reference = A11yHosting(VStack {
            ForEach(originals.indices, id: \.self) { index in
                TextField("Reference", text: .constant(originals[index]))
            }
        })
        defer { reference.close() }
        let nativeValues = subviews(of: reference.controller.view).compactMap { ($0 as? UITextField)?.text }
        XCTAssertEqual(nativeValues.count, 2)
        func view(_ size: DynamicTypeSize) -> some View {
            card(maximumHeight: 400, fields: fields).frame(width: 304).environment(\.dynamicTypeSize, size)
        }
        let host = A11yHosting(view(.large))
        defer { host.close() }
        _ = host.measured()
        let before = subviews(of: host.controller.view).compactMap { $0 as? UITextField }
        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(before.compactMap(\.text), nativeValues)
        XCTAssertEqual(values, originals)
        XCTAssertEqual(writes, 0)
        let oldFontSize = try XCTUnwrap(before.first?.font?.pointSize)
        let scroll = try XCTUnwrap(subviews(of: host.controller.view).compactMap { $0 as? UIScrollView }.first)
        let oldContentHeight = scroll.contentSize.height
        host.update(view(.accessibility5))
        _ = host.measured()
        let after = subviews(of: host.controller.view).compactMap { $0 as? UITextField }
        XCTAssertEqual(after.compactMap(\.text), nativeValues)
        XCTAssertEqual(values, originals)
        XCTAssertEqual(writes, 0)
        XCTAssertGreaterThan(try XCTUnwrap(after.first?.font?.pointSize), oldFontSize)
        XCTAssertGreaterThan(scroll.contentSize.height, oldContentHeight)
    }

    func testLongUnbrokenValuesGetARealWrappingReadingSurface() {
        for category in [DynamicTypeSize.large, .accessibility5] {
            let short = A11yHosting(DialogsFieldReadingProbe(value: "tag").environment(\.dynamicTypeSize, category))
            defer { short.close() }
            let shortSize = short.measured(proposal: CGSize(width: 240, height: 4000))
            let raw = "  synthetic_identifier_that_stays_complete_without_trimming_or_shrinking  "
            let long = A11yHosting(DialogsFieldReadingProbe(value: raw).environment(\.dynamicTypeSize, category))
            defer { long.close() }
            let longSize = long.measured(proposal: CGSize(width: 240, height: 4000))
            XCTAssertLessThanOrEqual(longSize.width, 240)
            XCTAssertGreaterThan(longSize.height, shortSize.height + 30)
            XCTAssertEqual(subviews(of: long.controller.view).compactMap { $0 as? UITextField }.first?.text, raw)
        }
    }

    func testProductionActionLabelsWrapAndGrowInsideTheirTargets() {
        var previousHeight: CGFloat = 0
        for category in [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility5] {
            let host = A11yHosting(GeistDialogActionButton(
                action: .action("Save Synthetic Fields Without Changing Other Values"), onAction: { _ in }
            ).environment(\.dynamicTypeSize, category))
            defer { host.close() }
            let size = host.measured(proposal: CGSize(width: 240, height: 2000))
            XCTAssertLessThanOrEqual(size.width, 240)
            XCTAssertGreaterThanOrEqual(size.width, 44)
            XCTAssertGreaterThanOrEqual(size.height, 44)
            XCTAssertGreaterThan(size.height, previousHeight)
            previousHeight = size.height
        }
    }

    func testNativeAccessibilityEscapeInvokesTheActualOverlayCancelRoute() throws {
        var presented = true
        var cancels = 0
        var saves = 0
        let host = A11yHosting(Color.bgPrimary.geistDialog(
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            title: Text("Synthetic Escape"), actions: [
                .action("Save") { saves += 1 },
                .cancel { XCTAssertTrue(presented); cancels += 1 }
            ]
        ))
        defer { host.close() }
        _ = host.measured()
        // SwiftUI owns AX identifiers on its representable wrapper. Locate the
        // genuine UIKit modal boundary by its public semantic property instead.
        let modals = accessibilityObjects(in: host.window).filter { $0.accessibilityViewIsModal }
        XCTAssertEqual(modals.count, 1)
        let card = try XCTUnwrap(modals.first)
        XCTAssertTrue(card.accessibilityViewIsModal)
        XCTAssertTrue(card.accessibilityPerformEscape())
        XCTAssertFalse(presented)
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(saves, 0)
    }

    private var longMessage: String {
        String(repeating: "Synthetic explanation remains available at the chosen text size. ", count: 12)
    }

    private func card(maximumHeight: CGFloat, fields: [GeistDialogField] = []) -> some View {
        GeistDialogCard(title: Text("Synthetic Dialog With a Complete Title"),
                        message: Text(verbatim: longMessage), messageAccessibilityIdentifier: "dialogs.test.message",
                        actions: [.cancel(), .action("Save Fields")], fields: fields, maximumHeight: maximumHeight,
                        onAction: { _ in }, onCancel: {})
    }

    private func subviews(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { subviews(of: $0) }
    }

    private func assertBounded(_ scroll: UIScrollView, in host: A11yHosting, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = scroll.convert(scroll.bounds, to: host.controller.view)
        XCTAssertGreaterThan(bounds.width, 0, file: file, line: line)
        XCTAssertGreaterThan(bounds.height, 0, file: file, line: line)
        XCTAssertTrue(host.controller.view.bounds.insetBy(dx: -1, dy: -1).contains(bounds), "\(bounds)", file: file, line: line)
    }

    /// Public UIKit accessibility containers, not private SwiftUI implementation types.
    private func accessibilityObjects(in root: NSObject) -> [NSObject] {
        var seen: Set<ObjectIdentifier> = []
        var pending = [root]
        var result: [NSObject] = []
        while let object = pending.popLast() {
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            result.append(object)
            if let view = object as? UIView { pending.append(contentsOf: view.subviews) }
            if let children = object.accessibilityElements as? [NSObject] { pending.append(contentsOf: children) }
            let count = object.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return result
    }
}

private struct DialogsFieldReadingProbe: View {
    let value: String
    @FocusState private var focus: Int?

    var body: some View {
        GeistDialogLabeledField(field: GeistDialogField(placeholder: "Field Name", text: .constant(value)),
                                index: 0, isLast: true, focus: $focus, onSubmit: {})
    }
}
#endif
