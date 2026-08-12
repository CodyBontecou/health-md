import Foundation

/// Detects app-hosted unit tests and UI-test launch arguments, and exposes
/// deterministic scenario configuration for test-mode dependency injection.
///
/// Usage in UI tests:
///   app.launchArguments += ["--uitesting"]
///   app.launchEnvironment["UITEST_HEALTH_AUTHORIZED"] = "true"
enum TestMode {

    /// True when the app was launched from UI tests.
    static let isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("--uitesting")

    /// True only for an XCTest-hosted app process, not the app launched by an XCUI test.
    static let isUnitTesting: Bool = !isUITesting && (
        env("XCTestConfigurationFilePath") != nil || env("XCTestBundlePath") != nil
    )

    static let suppressesRuntimeServices: Bool = isUITesting || isUnitTesting

    // MARK: - Scenario Configuration

    /// Whether the real first-run onboarding flow should remain visible in UI tests.
    static var showsOnboarding: Bool {
        env("UITEST_SHOW_ONBOARDING") == "true"
    }

    /// Deterministic persisted onboarding state for this UI-test launch.
    static var hasCompletedOnboarding: Bool {
        env("UITEST_HAS_COMPLETED_ONBOARDING") != "false"
    }

    /// Whether Notelet release notes should use their production presentation path in UI tests.
    static var showsReleaseNotes: Bool {
        env("UITEST_SHOW_RELEASE_NOTES") == "true"
    }

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

    /// Number of free exports already consumed (0-10).
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

    /// Simulated export result ("success", "intermediate-success", "partial", "fail", or nil for default).
    static var exportResult: String? {
        env("UITEST_EXPORT_RESULT")
    }

    /// Simulated connected-Mac destination state for iOS export-target UI tests.
    /// Supported values: "none", "ready", "noFolder", "accessDenied", "busy".
    static var macExportStatus: String {
        env("UITEST_MAC_EXPORT_STATUS") ?? "none"
    }

    /// Simulated connected-Mac destination path shown in target status and previews.
    static var macDestinationPath: String {
        env("UITEST_MAC_DESTINATION_PATH") ?? "/tmp/TestMacVault"
    }

    /// Whether export preview should use deterministic in-app HealthKit fixtures.
    static var useHealthKitExportPreviewFixtures: Bool {
        env("UITEST_HEALTHKIT_EXPORT_PREVIEW_FIXTURES") == "true"
    }

    /// Whether UI-test launch should start with every export format deselected.
    static var noExportFormats: Bool {
        env("UITEST_NO_EXPORT_FORMATS") == "true"
    }

    /// Whether UI-test launch should pre-enable ZIP export archives.
    static var archiveExports: Bool {
        env("UITEST_ARCHIVE_EXPORTS") == "true" || env("UITEST_ARCHIVE_MARKDOWN_EXPORTS") == "true"
    }

    /// Simulated pricing analytics transport. Supported values: "noop" or "offline".
    static var analyticsTransport: String {
        env("UITEST_ANALYTICS_TRANSPORT") ?? "noop"
    }

    /// Simulated remote-config state. Supported values: "available" or "offline".
    static var remoteConfig: String {
        env("UITEST_REMOTE_CONFIG") ?? "available"
    }

    // MARK: - Private

    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}
