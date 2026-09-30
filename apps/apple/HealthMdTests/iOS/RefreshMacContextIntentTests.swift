import XCTest
@testable import HealthMd

#if os(iOS)
@MainActor
final class RefreshMacContextIntentTests: XCTestCase {
    func testRequestBuilderPinsExplicitProfileScopeWithoutFileDestination() throws {
        let suite = "RefreshMacContextIntentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let request = IPhoneMacContextRefreshCoordinator.makeRequest(
            profile: nil,
            settings: settings,
            days: 30,
            allAvailable: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(request.dateSelection, .explicitRange)
        XCTAssertEqual(
            calendar.dateComponents([.day], from: request.dateRangeStart, to: request.dateRangeEnd).day,
            29
        )
        XCTAssertEqual(request.selection.sourceIDs, ["apple_health"])
        XCTAssertFalse(request.selection.metricIDs.isEmpty)
        XCTAssertTrue(request.selection.objectPaths.isEmpty)
        XCTAssertTrue(request.selection.fieldPointers.isEmpty)
    }

    func testDurableReceiptPersistsPendingAndTerminalStatus() throws {
        let suite = "RefreshMacContextIntentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let coordinator = IPhoneMacContextRefreshCoordinator(defaults: defaults)
        let jobID = UUID()
        let pending = IPhoneContextRefreshStatus(
            jobID: jobID,
            state: .pending,
            message: "Pending"
        )
        coordinator.handle(pending)
        XCTAssertEqual(coordinator.latestStatus, pending)

        let completed = IPhoneContextRefreshStatus(
            jobID: jobID,
            state: .completed,
            message: "Completed"
        )
        coordinator.handle(completed)

        XCTAssertEqual(coordinator.latestStatus, completed)
        XCTAssertEqual(
            IPhoneMacContextRefreshCoordinator(defaults: defaults).latestStatus,
            completed
        )
    }
}
#endif
