#if DEBUG && os(iOS)
import Foundation

/// App Store screenshot display state (UI tests only, never shipped): a paired healthmd CLI
/// (CLIDestG, SettingsGlass, iPadSettingsG) and a connected WHOOP account (SettingsGlass).
///
/// Display only. Nothing here writes the Keychain, a token store or a trust record, or starts
/// a network service: `IPhoneDirectCLIService` reports the fixture computer as its saved
/// pairing while its reconnect loop stays off, and `ExternalIntegrationManager` lists the
/// fixture account without a token, so no capture or refresh ever reaches WHOOP.
enum AppStoreScreenshotFixtures {
    static let pairedCLIEnvironmentKey = "UITEST_APPSTORE_PAIRED_CLI"
    static let connectedWHOOPEnvironmentKey = "UITEST_APPSTORE_CONNECTED_WHOOP"

    struct PairedCLI: Sendable {
        let name: String
        let pairedAt: Date
    }

    /// "Studio Mac", paired by QR earlier today, so CLIDestG reads
    /// "Paired via QR · last used today". Fixed for the life of the process.
    static let pairedCLI: PairedCLI? = {
        guard isRequested(pairedCLIEnvironmentKey) else { return nil }
        return PairedCLI(name: "Studio Mac", pairedAt: earlierToday())
    }()

    /// A WHOOP connection with no token and no successful export yet.
    static let connectedWHOOPAccount: ExternalIntegrationAccount? = {
        guard isRequested(connectedWHOOPEnvironmentKey) else { return nil }
        return ExternalIntegrationAccount(provider: .whoop, connectedAt: earlierToday())
    }()

    private static func isRequested(_ key: String) -> Bool {
        TestMode.isUITesting && ProcessInfo.processInfo.environment[key] == "true"
    }

    /// An hour ago, but never before today's midnight; whole seconds so persisted copies
    /// compare equal after a JSON round trip.
    private static func earlierToday(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let candidate = max(calendar.startOfDay(for: now), now.addingTimeInterval(-3600))
        return Date(timeIntervalSinceReferenceDate: candidate.timeIntervalSinceReferenceDate.rounded(.down))
    }
}
#endif
