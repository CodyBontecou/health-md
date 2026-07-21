import XCTest
@testable import HealthMd

#if os(macOS)
final class HealthContextProfileManagerTests: XCTestCase {
    @MainActor
    func testExplicitFullAccessCreationPersistsUnlimitedPolicy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-context-profile-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HealthContextProfileStore(rootURL: root)
        let manager = HealthContextProfileManager(store: store)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let profile = try await manager.createFullAccessProfile(now: now)

        XCTAssertEqual(profile.metricScope, .allAvailable)
        XCTAssertEqual(profile.dataSourceScope, .allAvailable)
        XCTAssertEqual(profile.detailLevel, .lossless)
        XCTAssertEqual(profile.datePolicy, .allHistory)
        XCTAssertTrue(profile.allowedCallers.contains(.registeredAgent))
        XCTAssertTrue(profile.allowedSurfaces.contains(.mcpStdio))
        let storedProfiles = try await store.loadProfiles()
        XCTAssertEqual(storedProfiles, [profile])
    }

    @MainActor
    func testRepeatedFullAccessCreationKeepsDistinctDurableProfiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-context-profile-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = HealthContextProfileManager(
            store: HealthContextProfileStore(rootURL: root)
        )

        let first = try await manager.createFullAccessProfile()
        let second = try await manager.createFullAccessProfile()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(manager.profiles.map(\.name), ["All Health Data", "All Health Data 2"])
    }
}
#endif
