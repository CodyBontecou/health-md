import XCTest
@testable import HealthMd

#if os(macOS)
final class MacEncryptedHealthContextManagerTests: XCTestCase {
    @MainActor
    func testExplicitRetentionAndDeleteAllAreIndependentStoreControls() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("context-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = InMemoryHealthContextEncryptionKeyProvider()
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: keys)
        try await store.upsert([
            day("2024-01-01"), day("2025-01-01"), day("2026-01-01")
        ])
        let manager = MacEncryptedHealthContextManager(store: store)

        await manager.refresh()
        XCTAssertEqual(manager.ownerDateCount, 3)
        XCTAssertEqual(manager.earliestOwnerDate, "2024-01-01")
        XCTAssertEqual(manager.latestOwnerDate, "2026-01-01")

        let removed = await manager.delete(before: "2025-01-01")
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(manager.ownerDateCount, 2)
        let retainedDates = try await store.listOwnerDates()
        XCTAssertEqual(retainedDates, ["2025-01-01", "2026-01-01"])

        await manager.deleteAll()
        XCTAssertEqual(manager.ownerDateCount, 0)
        let deletedDates = try await store.listOwnerDates()
        XCTAssertEqual(deletedDates, [])
        XCTAssertNil(try keys.existingKeyData())
    }

    private func day(_ ownerDate: String) -> HealthMdCompactContextDay {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "\(ownerDate)T00:00:00Z")!
        return HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZone: "UTC",
            source: HealthMdSourceDescriptor(
                schema: "healthmd.health_data",
                schemaVersion: 7,
                digest: String(repeating: "a", count: 64)
            ),
            status: .available
        )
    }
}
#endif
