import Foundation

/// Detects UI-test launch arguments and exposes deterministic scenario
/// configuration for test-mode dependency injection.
///
/// Usage in UI tests:
///   app.launchArguments += ["--uitesting"]
///   app.launchEnvironment["UITEST_HEALTH_AUTHORIZED"] = "true"
enum TestMode {

    /// True when the app was launched from UI tests.
    static let isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("--uitesting")

    // MARK: - Scenario Configuration

    /// Whether HealthKit should report as authorized.
    static var healthAuthorized: Bool {
        env("UITEST_HEALTH_AUTHORIZED") == "true"
    }

    /// Whether a vault folder should appear selected.
    static var vaultSelected: Bool {
        env("UITEST_VAULT_SELECTED") == "true"
    }

    /// Whether the in-app purchase is unlocked.
    static var purchaseUnlocked: Bool {
        env("UITEST_PURCHASE_UNLOCKED") == "true"
    }

    /// Number of free exports already consumed (0-3).
    static var freeExportsUsed: Int {
        Int(env("UITEST_FREE_EXPORTS_USED") ?? "0") ?? 0
    }

    /// Simulated sync connection state.
    static var syncState: String {
        env("UITEST_SYNC_STATE") ?? "disconnected"
    }

    /// Whether the export schedule is enabled.
    static var scheduleEnabled: Bool {
        env("UITEST_SCHEDULE_ENABLED") == "true"
    }

    /// Simulated export result ("success", "partial", "fail", or nil for default).
    static var exportResult: String? {
        env("UITEST_EXPORT_RESULT")
    }

    // MARK: - Private

    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}
