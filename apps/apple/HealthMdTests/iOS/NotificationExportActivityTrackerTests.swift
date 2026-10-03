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
        let operationID = UUID()
        let result = NotificationExportResult(
            status: .partialSuccess(exported: 1, total: 2),
            timestamp: Date(timeIntervalSince1970: 123),
            operationID: operationID
        )
        tracker.begin(
            operationID: operationID,
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

        let foreignResult = NotificationExportResult(
            status: .success(daysExported: 1),
            timestamp: Date(timeIntervalSince1970: 321),
            operationID: UUID()
        )
        tracker.finish(with: foreignResult)

        XCTAssertEqual(tracker.snapshot?.operationID, activeID)
        XCTAssertEqual(tracker.snapshot?.phase, .preparing)
        XCTAssertEqual(tracker.snapshot?.message, "Active")
        XCTAssertFalse(tracker.handles(foreignResult))
    }

    func testCancellationRequestIsOperationScopedAndCannotBeRepeated() {
        let operationID = UUID()
        tracker.begin(
            operationID: operationID,
            source: .scheduled,
            targetLabel: "API Endpoint",
            totalDays: 3,
            message: "Starting"
        )

        XCTAssertFalse(tracker.requestCancellation(operationID: UUID()))
        XCTAssertTrue(tracker.requestCancellation(operationID: operationID))
        XCTAssertEqual(tracker.snapshot?.phase, .cancelling)
        XCTAssertEqual(tracker.snapshot?.message, "Cancelling export…")
        XCTAssertTrue(tracker.keepsScreenAwake)
        XCTAssertFalse(tracker.requestCancellation(operationID: operationID))
    }

    func testCancelledResultBecomesTerminalAndSuppressesDuplicateAlert() {
        let operationID = UUID()
        let result = NotificationExportResult(
            status: .cancelled,
            timestamp: Date(timeIntervalSince1970: 456),
            operationID: operationID
        )
        tracker.begin(
            operationID: operationID,
            source: .shortcut,
            targetLabel: "Local iPhone Folder",
            totalDays: 2,
            message: "Starting"
        )
        XCTAssertTrue(tracker.requestCancellation(operationID: operationID))

        tracker.finish(with: result)

        XCTAssertEqual(tracker.snapshot?.phase, .cancelled)
        XCTAssertEqual(tracker.snapshot?.message, result.message)
        XCTAssertTrue(tracker.handles(result))
        XCTAssertFalse(tracker.keepsScreenAwake)
    }
}
#endif
