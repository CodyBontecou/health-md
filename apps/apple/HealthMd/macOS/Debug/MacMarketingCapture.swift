#if DEBUG && os(macOS)
import AppKit
import SwiftUI
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
        /// The CLI & MCP pane (AS_Mac_2).
        case cli

        var scrollTarget: String? {
            switch self {
            case .sync, .settings, .cli:
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
        switch screen {
        case .settings: return "settings"
        case .cli: return "cli"
        default: return "home"
        }
    }

    /// The App Store boards show the dark glass UI; `-MacMarketingAppearance light` keeps the
    /// earlier light set reproducible. Scoped to this DEBUG capture path only.
    static var isDarkAppearance: Bool {
        argumentValue(for: "-MacMarketingAppearance") != "light"
    }

    static var colorScheme: ColorScheme {
        isDarkAppearance ? .dark : .light
    }

    /// The boards frame a 1100 × 720 pt window, captured at 2× (2200 × 1440 px).
    static let windowSize = CGSize(width: 1_100, height: 720)

    static var scrollTarget: String? {
        screen.scrollTarget
    }

    static func configure(
        syncService: SyncService,
        vaultManager: VaultManager
    ) {
        guard isActive else { return }

        NSApp.appearance = NSAppearance(named: isDarkAppearance ? .darkAqua : .aqua)
        vaultManager.setMarketingCaptureVault()

        syncService.connectionState = .connected
        syncService.connectedPeerName = peerName
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

        // Size the whole window, title bar included, to the board's window frame.
        window.setContentSize(NSSize(width: windowSize.width, height: windowSize.height))
        let chromeHeight = window.frame.height - windowSize.height
        window.setContentSize(NSSize(width: windowSize.width, height: windowSize.height - chromeHeight))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        // A stale MCSession callback can arrive during launch. Re-apply the
        // fixture after the real window is settled, then capture the stable UI.
        configure(syncService: syncService, vaultManager: vaultManager)
        try? await Task.sleep(for: .milliseconds(600))
        // A late session callback can still reset the connection; set it once more just
        // before capturing so the paired-iPhone rows read as on the boards.
        configure(syncService: syncService, vaultManager: vaultManager)
        try? await Task.sleep(for: .milliseconds(150))

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

    // MARK: - MacHomeG fixture values (AS_Mac_1)

    /// Today at the given time in the capture's calendar.
    private static func today(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    /// "Last export: Today 11:02 PM · 1 file". In memory only; the user's export history is
    /// never read or written by the capture.
    static var lastExport: ExportHistoryEntry {
        let day = Calendar.current.startOfDay(for: Date())
        return ExportHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            timestamp: today(hour: 23, minute: 2),
            source: .macAgent,
            success: true,
            dateRangeStart: day,
            dateRangeEnd: day,
            successCount: 1,
            totalCount: 1,
            exportTarget: .connectedMac,
            fileCount: 1
        )
    }

    /// The manual IP section shows these fixed addresses (a private LAN address and a
    /// CGNAT/Tailscale-range address), never the capturing Mac's real interfaces. The
    /// live server is not started for the capture.
    static let manualIPAddresses = ["192.168.1.24", "100.64.0.12"]
    static let manualIPPairingCode = "4821"
    static let peerName = "Demo iPhone"
    static var manualIPPairingCodeExpiresAt: Date { today(hour: 23, minute: 40) }

    // MARK: - MacCLIG fixture values (AS_Mac_2)

    /// The encrypted query context status the CLI pane shows during a capture. The capture
    /// never opens the Keychain-backed store; the count is the board's sample.
    static let encryptedContextDayCount = 30

    /// MacHomeG's Activity rows, relative to the capture date and consistent with
    /// `lastExport`: "11:02 PM · Received <today> from Demo iPhone · 1 file", then yesterday,
    /// then nine days ago, one written file each.
    private static func fixtureEvents() -> [SyncEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func event(id: Int, daysAgo: Int, hour: Int, minute: Int, bytes: Int) -> SyncEvent {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let timestamp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return SyncEvent(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
                timestamp: timestamp,
                peerName: "Demo iPhone",
                kind: .macExportSucceeded,
                recordCount: 1,
                payloadByteEstimate: bytes,
                dateRangeStart: day,
                dateRangeEnd: day
            )
        }

        return [
            // Matches `lastExport` (today 11:02 PM, today's data, 1 file).
            event(id: 401, daysAgo: 0, hour: 23, minute: 2, bytes: 15_360),
            event(id: 402, daysAgo: 1, hour: 23, minute: 4, bytes: 14_848),
            event(id: 403, daysAgo: 9, hour: 23, minute: 1, bytes: 15_104)
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
