import XCTest
@testable import HealthMd

@MainActor
final class IdleTimerCoordinatorTests: XCTestCase {
    func testDisablesIdleTimerUntilEveryActivityEnds() {
        var updates: [Bool] = []
        let coordinator = IdleTimerCoordinator { updates.append($0) }
        let firstActivity = UUID()
        let secondActivity = UUID()

        coordinator.beginActivity(firstActivity)
        coordinator.beginActivity(secondActivity)
        coordinator.endActivity(firstActivity)

        XCTAssertTrue(coordinator.isIdleTimerDisabled)
        XCTAssertEqual(updates, [true])

        coordinator.endActivity(secondActivity)

        XCTAssertFalse(coordinator.isIdleTimerDisabled)
        XCTAssertEqual(updates, [true, false])
    }

    func testBeginningAndEndingAnActivityAreIdempotent() {
        var updates: [Bool] = []
        let coordinator = IdleTimerCoordinator { updates.append($0) }
        let activity = UUID()

        coordinator.beginActivity(activity)
        coordinator.beginActivity(activity)
        coordinator.endActivity(activity)
        coordinator.endActivity(activity)

        XCTAssertEqual(updates, [true, false])
    }

    func testEndingUnknownActivityDoesNotChangeIdleTimer() {
        var updates: [Bool] = []
        let coordinator = IdleTimerCoordinator { updates.append($0) }

        coordinator.endActivity(UUID())

        XCTAssertFalse(coordinator.isIdleTimerDisabled)
        XCTAssertTrue(updates.isEmpty)
    }
}
