#if DEBUG && canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - Core utilities

enum MarketingCapture {

    // MARK: Launch argument

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-MarketingCapture") &&
        value(for: "-MarketingCapture") == "1"
    }

    private static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: key), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    // MARK: Locale

    /// Folder name for per-locale output. Read from the -MarketingLocale
    /// launch argument so it exactly matches the shell script's LOCALES array.
    static var localeFolder: String {
        value(for: "-MarketingLocale")
            ?? Locale.current.language.languageCode?.identifier
            ?? Locale.current.identifier
    }

    // MARK: Priming vars

    /// Which sub-screen to auto-navigate to within AdvancedSettingsView.
    /// Set by the coordinator before presenting the sheet.
    enum AdvancedSubscreen {
        case metricSelection
        case formatCustomization
        case individualTracking
        case dailyNoteInjection
    }

    static var pendingAdvancedSubscreen: AdvancedSubscreen?

    // MARK: Dismiss broadcast

    static let dismissSheetNotification = Notification.Name("MarketingCapture.dismissSheet")

    // MARK: Output

    static var outputRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs
            .appendingPathComponent("marketing", isDirectory: true)
            .appendingPathComponent(localeFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func writePNG(_ image: UIImage, name: String, subfolder: String? = nil) {
        var dir = outputRoot
        if let subfolder {
            dir = dir.appendingPathComponent(subfolder, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent("\(name).png")
        guard let data = image.pngData() else {
            print("[MarketingCapture] failed to encode \(name)")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            print("[MarketingCapture] wrote \(url.path)")
        } catch {
            print("[MarketingCapture] write failed: \(error)")
        }
    }

    static func writeSentinel() {
        let url = outputRoot.appendingPathComponent("_done")
        try? Data().write(to: url)
    }

    // MARK: Window snapshot

    @MainActor
    static func snapshotKeyWindow() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - Step-based coordinator

struct CaptureStep {
    let name: String
    let navigate: @MainActor () -> Void
    let settle: Duration
    let cleanup: (@MainActor () -> Void)?

    init(
        name: String,
        settle: Duration = .milliseconds(1800),
        navigate: @escaping @MainActor () -> Void,
        cleanup: (@MainActor () -> Void)? = nil
    ) {
        self.name = name
        self.navigate = navigate
        self.settle = settle
        self.cleanup = cleanup
    }
}

@MainActor
final class MarketingCaptureCoordinator {
    static let shared = MarketingCaptureCoordinator()
    private init() {}

    var minimumSettle: Duration = .milliseconds(1800)

    func run(steps: [CaptureStep]) async {
        print("[MarketingCapture] run for locale=\(MarketingCapture.localeFolder)")

        for step in steps {
            step.navigate()
            let settle = max(step.settle, minimumSettle)
            try? await Task.sleep(for: settle)

            guard let image = MarketingCapture.snapshotKeyWindow() else {
                print("[MarketingCapture] snapshot failed: \(step.name)")
                continue
            }
            MarketingCapture.writePNG(image, name: step.name)

            if let cleanup = step.cleanup {
                cleanup()
                try? await Task.sleep(for: .milliseconds(3000))
            }
        }

        MarketingCapture.writeSentinel()
        print("[MarketingCapture] done for locale=\(MarketingCapture.localeFolder)")
    }
}

// MARK: - Marketing Sheet Wrapper

/// Wraps marketing capture sheets with a dismiss listener so the coordinator
/// can reliably dismiss them via NotificationCenter between capture steps.
struct MarketingSheetWrapper<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .onReceive(NotificationCenter.default.publisher(for: MarketingCapture.dismissSheetNotification)) { _ in
            dismiss()
        }
    }
}
#endif
