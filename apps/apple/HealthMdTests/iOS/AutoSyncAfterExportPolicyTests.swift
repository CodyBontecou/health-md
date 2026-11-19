#if os(iOS)
import XCTest
@testable import HealthMd

/// v3.5 parity C-01: iPad "Auto-sync after export".
final class AutoSyncAfterExportPolicyTests: XCTestCase {
    func testTriggersOnlyWhenEveryThreePointFiveConditionHolds() {
        XCTAssertTrue(policy())
        XCTAssertFalse(policy(successCount: 0), "nothing was written")
        XCTAssertFalse(policy(connectionState: .connecting))
        XCTAssertFalse(policy(connectionState: .disconnected))
        XCTAssertFalse(policy(syncEnabled: false), "Mac destination is off")
        XCTAssertFalse(policy(autoSyncAfterExport: false), "the user turned auto-sync off")
        XCTAssertFalse(policy(idiom: .phone), "3.5 offered auto-sync on iPad only")
    }

    func testAvailabilityMatchesThreePointFiveIdioms() {
        XCTAssertTrue(AutoSyncAfterExportPolicy.isAvailable(idiom: .pad))
        XCTAssertFalse(AutoSyncAfterExportPolicy.isAvailable(idiom: .phone))
    }

    /// 3.5 registered `false`, which shadowed the `@AppStorage` fallback of `true`.
    /// An upgrader who never touched the toggle keeps it off; one who turned it on keeps it on.
    func testReadsStoredValueAndFallsBackToTheRegisteredDefault() throws {
        let suite = "AutoSyncAfterExportPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: [AutoSyncAfterExportPolicy.key: AutoSyncAfterExportPolicy.registeredDefault])
        defaults.set(true, forKey: "syncEnabled")

        XCTAssertFalse(AutoSyncAfterExportPolicy.registeredDefault)
        XCTAssertFalse(AutoSyncAfterExportPolicy.shouldAutoSync(
            successCount: 1, connectionState: .connected, defaults: defaults, idiom: .pad
        ))

        defaults.set(true, forKey: AutoSyncAfterExportPolicy.key)
        XCTAssertTrue(AutoSyncAfterExportPolicy.shouldAutoSync(
            successCount: 1, connectionState: .connected, defaults: defaults, idiom: .pad
        ))
        XCTAssertEqual(AutoSyncAfterExportPolicy.key, "autoSyncAfterExport", "the 3.5 key must not change")
    }

    private func policy(
        successCount: Int = 2,
        connectionState: SyncConnectionState = .connected,
        syncEnabled: Bool = true,
        autoSyncAfterExport: Bool = true,
        idiom: UIUserInterfaceIdiom = .pad
    ) -> Bool {
        AutoSyncAfterExportPolicy.shouldAutoSync(
            successCount: successCount,
            connectionState: connectionState,
            syncEnabled: syncEnabled,
            autoSyncAfterExport: autoSyncAfterExport,
            idiom: idiom
        )
    }
}
#endif
