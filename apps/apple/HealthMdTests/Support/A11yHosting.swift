import SwiftUI
import XCTest
#if os(iOS)
import UIKit

/// Hosts the actual supplied production view. No app services, defaults or files.
/// Embedded probes opt out of inherited safe areas, then remeasure after attachment.
@MainActor
final class A11yHosting {
    let controller: UIHostingController<AnyView>
    let window: UIWindow
    private let settle: () -> Void

    init<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 320, height: 640),
        settle: @escaping () -> Void = {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    ) {
        self.settle = settle
        controller = UIHostingController(rootView: AnyView(view))
        controller.safeAreaRegions = []
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        layout()
    }

    func update<V: View>(_ view: V) {
        controller.rootView = AnyView(view)
        layout()
    }

    func layout() {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        settle()
        controller.view.layoutIfNeeded()
    }

    func measured(proposal: CGSize = CGSize(width: 1000, height: 10000)) -> CGSize {
        // Attachment and root-view updates already settle the host. Flush any
        // synchronous layout work without another fixed run-loop wait per probe.
        controller.view.layoutIfNeeded()
        return controller.sizeThatFits(in: proposal)
    }

    func capture() -> UIImage {
        layout()
        return UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
#endif
