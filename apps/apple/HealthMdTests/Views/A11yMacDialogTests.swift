#if os(macOS)
import AppKit
import SwiftUI
import XCTest
#if A11Y_ISOLATED_MAC
@testable import HealthMdMac
#else
@testable import HealthMd
#endif

/// Actual shared production components in a hostless test bundle. No shipping
/// Mac app bootstrap, persistent stores, cleanup, transport or scheduling.
@MainActor
final class A11yMacDialogTests: XCTestCase {
    func testDesktopScrimRetainsDocumentedBlackAlpha() throws {
        for (name, alpha) in [(NSAppearance.Name.aqua, CGFloat(112.0 / 255)), (.darkAqua, CGFloat(179.0 / 255))] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let color = NSColor(Color.dialogScrim).usingColorSpace(.sRGB)!
                XCTAssertEqual(color.redComponent, 0, accuracy: 0.002)
                XCTAssertEqual(color.greenComponent, 0, accuracy: 0.002)
                XCTAssertEqual(color.blueComponent, 0, accuracy: 0.002)
                XCTAssertEqual(color.alphaComponent, alpha, accuracy: 0.002)
            }
        }
    }

    func testDesktopDialogRemainsBoundedInShortReadingWindows() {
        for width: CGFloat in [240, 320, 420] {
            let host = NSHostingView(rootView: GeistDialogCard(
                title: Text("A Complete Desktop Dialog Title"),
                message: Text(String(repeating: "Synthetic explanation remains available. ", count: 20)),
                messageAccessibilityIdentifier: nil,
                actions: [.cancel(), .action("Save Synthetic Fields")], fields: [],
                maximumHeight: 160, onAction: { _ in }, onCancel: {}
            ).frame(width: width))
            host.frame = CGRect(x: 0, y: 0, width: width, height: 160)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, width, accuracy: 1)
            XCTAssertGreaterThan(host.fittingSize.height, 0)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 160)
        }
    }

    func testDesktopActionRetainsFortyPointMinimumAndWrapsCompleteLabels() {
        func measure(_ title: LocalizedStringKey) -> CGSize {
            let host = NSHostingView(rootView: GeistDialogActionButton(
                action: .action(title), onAction: { _ in }
            ).frame(width: 240))
            return host.fittingSize
        }
        let short = measure("Save")
        let long = measure("Save Synthetic Fields Without Changing Any Other Configuration Values")
        XCTAssertEqual(short.height, 40, accuracy: 1, "Keep desktop sizing separate from iOS touch conventions")
        XCTAssertGreaterThan(long.height, short.height)
        XCTAssertEqual(long.width, 240, accuracy: 1)
    }

    func testDesktopReturnAndCancelKeepTheirOriginalDispatchPolicy() {
        var presented = true
        var events: [String] = []
        let binding = Binding(get: { presented }, set: { presented = $0; events.append("dismiss") })
        let interaction = GeistDialogInteraction(actions: [
            .cancel { events.append("cancel:\(presented)") },
            .action("Save") { events.append("save:\(presented)") }
        ])
        interaction.submit(fieldIndex: 0, fieldCount: 2, advancesFocus: false,
                           focus: { _ in XCTFail("Desktop Return must not become iOS Next") },
                           onAction: { interaction.perform($0, isPresented: binding) })
        XCTAssertEqual(events, ["save:true", "dismiss"])
        XCTAssertFalse(presented)
        presented = true
        events = []
        interaction.cancel(isPresented: binding)
        XCTAssertEqual(events, ["cancel:true", "dismiss"])
        XCTAssertFalse(presented)
        // The shared .onExitCommand wiring is built, not a physical-key claim.
    }
}
#endif
