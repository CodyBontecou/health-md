#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class CLIExportActivityTrackerTests: XCTestCase {
    private var tracker: CLIExportActivityTracker!

    override func setUp() {
        super.setUp()
        tracker = CLIExportActivityTracker()
    }

    override func tearDown() {
        tracker.clear()
        tracker = nil
        super.tearDown()
    }

    func testTracksProgressAndSuccessfulCompletion() {
        let jobID = UUID()
        tracker.begin(
            jobID: jobID,
            source: .direct,
            totalDays: 4,
            message: "Preparing"
        )
        tracker.update(
            jobID: jobID,
            source: .direct,
            phase: .capturing,
            processedDays: 2,
            totalDays: 4,
            currentDate: "Jul 23, 2026",
            committedPartitions: 1,
            committedBytes: 1_024,
            message: "Capturing"
        )

        XCTAssertEqual(tracker.snapshot?.fractionComplete, 0.5)
        XCTAssertEqual(tracker.snapshot?.committedBytes, 1_024)
        XCTAssertTrue(tracker.keepsScreenAwake)

        tracker.finish(
            jobID: jobID,
            phase: .completed,
            message: "Complete"
        )

        XCTAssertEqual(tracker.snapshot?.phase, .completed)
        XCTAssertEqual(tracker.snapshot?.fractionComplete, 1)
        XCTAssertFalse(tracker.keepsScreenAwake)
    }

    func testMacProgressMovesBannerIntoTransferPhase() {
        let jobID = UUID()
        tracker.begin(
            jobID: jobID,
            source: .macApp,
            totalDays: 3,
            message: "Preparing"
        )

        tracker.updateMac(MacExportProgress(
            jobID: jobID,
            phase: .writing,
            processedDays: 2,
            totalDays: 3,
            currentDate: nil,
            filesWritten: 2,
            message: "Writing files"
        ))

        XCTAssertEqual(tracker.snapshot?.phase, .transferring)
        XCTAssertEqual(tracker.snapshot?.fractionComplete, 2.0 / 3.0)
        XCTAssertEqual(tracker.snapshot?.message, "Writing files")
    }

    func testForeignJobCannotReplaceActiveProgress() {
        let activeJobID = UUID()
        tracker.begin(
            jobID: activeJobID,
            source: .macApp,
            totalDays: 1,
            message: "Active"
        )

        tracker.update(
            jobID: UUID(),
            source: .direct,
            phase: .transferring,
            processedDays: 1,
            totalDays: 1,
            currentDate: nil,
            message: "Foreign"
        )

        XCTAssertEqual(tracker.snapshot?.jobID, activeJobID)
        XCTAssertEqual(tracker.snapshot?.source, .macApp)
        XCTAssertEqual(tracker.snapshot?.message, "Active")
    }
}
#endif
