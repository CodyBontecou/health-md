#if os(macOS)
import Foundation

/// The Mac destination's System status rows: receiver version and listening state, folder
/// permission, and when discovery last checked. Restores the 3.5 System Status card in the
/// 4.0 glass layout; kept free of SwiftUI so the copy and tones are unit-testable.
struct MacDestinationSystemStatus: Equatable {
    var appVersion: String
    var receivingPaused: Bool
    var folderAccessHealthy: Bool
    var hasActiveExport: Bool
    var isConnected: Bool

    /// "Version 4.0.0 · Listening", or "· Paused" while receiving is paused.
    var receiverValue: String {
        let version = String(localized: "Version \(appVersion)")
        let state = receivingPaused ? String(localized: "Paused") : String(localized: "Listening")
        return "\(version) · \(state)"
    }

    var receiverIsHealthy: Bool { !receivingPaused }

    /// "Folder Access · Granted" once the destination is writable, otherwise
    /// "Select Folder · Needs Access".
    var permissionsValue: String {
        folderAccessHealthy
            ? "\(String(localized: "Folder Access")) · \(String(localized: "Granted"))"
            : "\(String(localized: "Select Folder")) · \(String(localized: "Needs Access"))"
    }

    var permissionsGranted: Bool { folderAccessHealthy }

    var lastCheckValue: String {
        if hasActiveExport { return String(localized: "In Progress") }
        if isConnected { return String(localized: "Just Now") }
        return receivingPaused ? String(localized: "Paused") : String(localized: "Scanning")
    }

    static var bundleAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#endif
