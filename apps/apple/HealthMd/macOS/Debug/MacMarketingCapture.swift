#if DEBUG && os(macOS)
import AppKit
import HealthMdConnectionCore

/// Deterministic, DEBUG-only state and window capture used by the Mac App Store
/// screenshot pipeline. Release builds cannot activate or compile this path.
@MainActor
enum MacMarketingCapture {
    enum Screen: String, CaseIterable {
        case sync
        case destination
        case readiness
        case activity
        case settings

        var scrollTarget: String? {
            switch self {
            case .sync, .settings:
                return nil
            case .destination:
                return "marketing-destination"
            case .readiness:
                return "marketing-system-status"
            case .activity:
                return "marketing-activity"
            }
        }
    }

    static var isActive: Bool {
        argumentValue(for: "-MacMarketingCapture") == "1"
    }

    static var screen: Screen {
        Screen(rawValue: argumentValue(for: "-MacMarketingScreen") ?? "sync") ?? .sync
    }

    static var localeFolder: String {
        argumentValue(for: "-MacMarketingLocale") ?? "en-US"
    }

    static var initialSidebarDestination: String {
        screen == .settings ? "settings" : "home"
    }

    static var scrollTarget: String? {
        screen.scrollTarget
    }

    static func configure(
        syncService: SyncService,
        vaultManager: VaultManager
    ) {
        guard isActive else { return }

        NSApp.appearance = NSAppearance(named: .aqua)
        vaultManager.setMarketingCaptureVault()

        syncService.connectionState = .connected
        syncService.connectedPeerName = "Demo iPhone"
        syncService.remoteCapabilities = SyncPeerCapabilities.current(platform: .iOS)
        syncService.lastError = nil
        syncService.isSyncing = false
        syncService.activeMacExportProgress = nil
        syncService.lastMacExportResult = nil
        syncService.lastMacExportFailure = nil

        SyncEventHistoryManager.shared.configureForMarketingCapture(
            Self.fixtureEvents()
        )
    }

    static func captureWindowAndTerminate(
        syncService: SyncService,
        vaultManager: VaultManager
    ) async {
        guard isActive else { return }

        // Let SwiftUI apply the fixture, navigation selection, scroll target,
        // fonts, and window resize before caching the real app window.
        try? await Task.sleep(for: .seconds(2.4))

        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "main-window" || $0.title == "Mac Destination"
        }) ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let contentView = window.contentView else {
            fail("Could not find the main Mac window")
            return
        }

        window.setContentSize(NSSize(width: 1_100, height: 700))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        // A stale MCSession callback can arrive during launch. Re-apply the
        // fixture after the real window is settled, then capture the stable UI.
        configure(syncService: syncService, vaultManager: vaultManager)
        try? await Task.sleep(for: .milliseconds(600))

        guard let windowImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            fail("Could not capture the app window surface")
            return
        }

        let bitmap = NSBitmapImageRep(cgImage: windowImage)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fail("Could not encode the window capture")
            return
        }

        let outputURL = captureOutputURL()
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: outputURL, options: .atomic)
            print("[MacMarketingCapture] wrote \(outputURL.path)")
            NSApp.terminate(nil)
        } catch {
            fail("Could not write \(outputURL.path): \(error.localizedDescription)")
        }
    }

    private static func fixtureEvents() -> [SyncEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        func date(day: Int, hour: Int, minute: Int) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = 2026
            components.month = 8
            components.day = day
            components.hour = hour
            components.minute = minute
            return components.date!
        }

        return [
            SyncEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                timestamp: date(day: 8, hour: 10, minute: 30),
                peerName: "Demo iPhone",
                kind: .macExportSucceeded,
                recordCount: 12,
                payloadByteEstimate: 184_320,
                dateRangeStart: date(day: 1, hour: 12, minute: 0),
                dateRangeEnd: date(day: 7, hour: 12, minute: 0)
            ),
            SyncEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
                timestamp: date(day: 7, hour: 10, minute: 30),
                peerName: "Demo iPhone",
                kind: .macExportSucceeded,
                recordCount: 4,
                payloadByteEstimate: 61_440,
                dateRangeStart: date(day: 6, hour: 12, minute: 0),
                dateRangeEnd: date(day: 6, hour: 12, minute: 0)
            ),
            SyncEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
                timestamp: date(day: 6, hour: 10, minute: 30),
                peerName: "Demo iPhone",
                kind: .macExportSucceeded,
                recordCount: 4,
                payloadByteEstimate: 58_368,
                dateRangeStart: date(day: 5, hour: 12, minute: 0),
                dateRangeEnd: date(day: 5, hour: 12, minute: 0)
            )
        ]
    }

    private static func captureOutputURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mac-app-store-captures", isDirectory: true)
            .appendingPathComponent(localeFolder, isDirectory: true)
            .appendingPathComponent("\(screen.rawValue).png")
    }

    private static func argumentValue(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func fail(_ message: String) {
        fputs("[MacMarketingCapture] \(message)\n", stderr)
        NSApp.terminate(nil)
    }
}
#endif
