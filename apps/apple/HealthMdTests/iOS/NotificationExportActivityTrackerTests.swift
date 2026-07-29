#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class NotificationExportActivityTrackerTests: XCTestCase {
    private var tracker: NotificationExportActivityTracker!

    override func setUp() {
        super.setUp()
        tracker = NotificationExportActivityTracker()
    }

    override func tearDown() {
        tracker.clear()
        tracker = nil
        super.tearDown()
    }

    func testTracksNotificationExportTargetAndProgress() {
        let operationID = UUID()
        tracker.begin(
            operationID: operationID,
            source: .scheduled,
            targetLabel: "Mac Vault",
            totalDays: 4,
            message: "Starting"
        )

        tracker.update(
            operationID: operationID,
            phase: .transferring,
            processedDays: 2,
            totalDays: 4,
            message: "Sending"
        )

        XCTAssertEqual(tracker.snapshot?.source, .scheduled)
        XCTAssertEqual(tracker.snapshot?.targetLabel, "Mac Vault")
        XCTAssertEqual(tracker.snapshot?.phase, .transferring)
        XCTAssertEqual(tracker.snapshot?.fractionComplete, 0.5)
        XCTAssertTrue(tracker.keepsScreenAwake)
    }

    func testPartialResultBecomesWarningAndSuppressesDuplicateAlert() {
        let result = NotificationExportResult(
            status: .partialSuccess(exported: 1, total: 2),
            timestamp: Date(timeIntervalSince1970: 123)
        )
        tracker.begin(
            operationID: UUID(),
            source: .shortcut,
            targetLabel: "Local iPhone Folder",
            totalDays: 2,
            message: "Starting"
        )

        tracker.finish(with: result)

        XCTAssertEqual(tracker.snapshot?.phase, .completedWithWarnings)
        XCTAssertEqual(tracker.snapshot?.fractionComplete, 1)
        XCTAssertEqual(tracker.snapshot?.message, result.message)
        XCTAssertTrue(tracker.handles(result))
        XCTAssertFalse(tracker.keepsScreenAwake)
    }

    func testForeignOperationCannotReplaceActiveToast() {
        let activeID = UUID()
        tracker.begin(
            operationID: activeID,
            source: .scheduled,
            targetLabel: "API Endpoint",
            totalDays: 1,
            message: "Active"
        )

        tracker.begin(
            operationID: UUID(),
            source: .shortcut,
            targetLabel: "Local iPhone Folder",
            totalDays: 1,
            message: "Foreign"
        )

        XCTAssertEqual(tracker.snapshot?.operationID, activeID)
        XCTAssertEqual(tracker.snapshot?.message, "Active")
    }
}
#endif
