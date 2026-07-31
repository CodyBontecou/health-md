#if DEBUG && os(macOS)
import XCTest
@testable import HealthMd

@MainActor
final class MacExportPerformanceLabControllerTests: XCTestCase {
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await ContinuousClock().sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func testRejectsNonAllowlistedMacLabLinks() throws {
        let invalid = [
            "healthmd://export-lab/mac-arm?run=../../private",
            "healthmd://export-lab/mac-arm?run=safe&path=/tmp",
            "healthmd://export-lab/mac-delete?run=safe",
            "https://export-lab/mac-arm?run=safe"
        ]
        for value in invalid {
            XCTAssertFalse(
                MacExportPerformanceLabController.shared.handle(
                    url: try XCTUnwrap(URL(string: value))
                )
            )
        }
    }

    func testPrivateInboxArmsAndEndsTelemetryWithoutURLRegistration() async throws {
        let runID = "mac-inbox-\(UUID().uuidString)"
        let binding = String(repeating: "a", count: 64)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "healthmd-mac-lab-test-\(UUID().uuidString)",
            isDirectory: true
        )
        let inbox = root.appendingPathComponent("MacInbox", isDirectory: true)
        let controller = MacExportPerformanceLabController(
            vaultVerifier: { $0 == binding },
            inboxDirectory: inbox
        )
        try FileManager.default.createDirectory(
            at: inbox,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer {
            controller.stopMonitoring()
            ExportPerformanceInstrumentation.endLabRun(runID: runID)
            let telemetryRoot = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("HealthMdPerformanceLab/Runs/\(runID)")
            try? FileManager.default.removeItem(at: telemetryRoot)
            try? FileManager.default.removeItem(at: root)
        }
        controller.startMonitoring()
        try Data("\(binding)\n".utf8).write(
            to: inbox.appendingPathComponent("\(runID).arm"),
            options: .atomic
        )
        let armed = await waitUntil {
            ExportPerformanceLabTelemetryStore.shared.activeContext
                == ExportPerformanceRunContext(runID: runID, target: .connectedMac)
        }
        XCTAssertTrue(armed)
        try Data("end\n".utf8).write(
            to: inbox.appendingPathComponent("\(runID).end"),
            options: .atomic
        )
        let ended = await waitUntil {
            ExportPerformanceLabTelemetryStore.shared.activeContext == nil
        }
        XCTAssertTrue(ended)
    }

    func testArmsAndEndsPrivateMacTelemetryRun() throws {
        let runID = "mac-controller-\(UUID().uuidString)"
        let binding = String(repeating: "b", count: 64)
        let controller = MacExportPerformanceLabController { $0 == binding }
        let armURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/mac-arm?run=\(runID)&binding=\(binding)"
        ))
        let endURL = try XCTUnwrap(URL(
            string: "healthmd://export-lab/mac-end?run=\(runID)"
        ))
        XCTAssertTrue(controller.handle(url: armURL))
        XCTAssertEqual(
            ExportPerformanceLabTelemetryStore.shared.activeContext,
            ExportPerformanceRunContext(runID: runID, target: .connectedMac)
        )
        XCTAssertTrue(controller.handle(url: endURL))
        XCTAssertNil(ExportPerformanceLabTelemetryStore.shared.activeContext)

        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("HealthMdPerformanceLab/Runs/\(runID)")
        try? FileManager.default.removeItem(at: root)
    }
}
#endif
