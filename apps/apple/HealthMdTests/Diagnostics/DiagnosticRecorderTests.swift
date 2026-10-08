import Foundation
import XCTest
@testable import HealthMd

final class DiagnosticRecorderTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testSharedPrivacyFixtureAndUnknownFieldsFailClosed() throws {
        var repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: repository.appendingPathComponent("packages/contracts").path) && repository.path != "/" { repository.deleteLastPathComponent() }
        let data = try Data(contentsOf: repository.appendingPathComponent("packages/contracts/diagnostics/v1/fixtures/privacy.json"))
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["input"]))
        let event = try JSONDecoder().decode(DiagnosticEvent.self, from: input)
        for (privateContext, key) in [(false, "expected_operational"), (true, "expected_private")] {
            let actual = try XCTUnwrap(event.filtered(includePrivate: privateContext))
            let actualJSON = try JSONSerialization.jsonObject(with: DiagnosticRecorder.encoder().encode(actual)) as! NSDictionary
            XCTAssertEqual(actualJSON, fixture[key] as? NSDictionary)
            XCTAssertFalse(actual.jsonLine.contains("SYNTHETIC_HEALTH_SENTINEL"))
            XCTAssertFalse(actual.jsonLine.contains("SYNTHETIC_SECRET_SENTINEL"))
        }
    }

    func testPrivateFieldsAreNotPersistedWithoutRecordingConsent() throws {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.peerDiscovered, fields: [.peerName: .text("SYNTHETIC_PRIVATE_PEER"), .state: .text("SYNTHETIC_SECRET_SENTINEL")])
        let snapshot = recorder.snapshot(includePrivate: true)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].omitted_fields["peer_name"], "not_recorded")
        XCTAssertEqual(snapshot.events[0].omitted_fields["state"], "invalid")
        let bytes = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertFalse(bytes.contains("SYNTHETIC_PRIVATE_PEER"))
        XCTAssertFalse(bytes.contains("SYNTHETIC_SECRET_SENTINEL"))
    }

    func testRecordingAndSharingAreIndependentAndStopDoesNotEraseEvidence() {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.startPrivateContextRecording()
        recorder.record(.peerDiscovered, fields: [.peerName: .text("SYNTHETIC_PRIVATE_PEER")])
        recorder.stopPrivateContextRecording()
        recorder.record(.peerLost, fields: [.peerName: .text("SYNTHETIC_NOT_RECORDED")])
        XCTAssertTrue(recorder.snapshot(includePrivate: true).events.contains { $0.fields["peer_name"] == .text("SYNTHETIC_PRIVATE_PEER") })
        XCTAssertFalse(recorder.snapshot().events.map(\.jsonLine).joined().contains("SYNTHETIC_PRIVATE_PEER"))
        XCTAssertFalse(recorder.snapshot(includePrivate: true).events.map(\.jsonLine).joined().contains("SYNTHETIC_NOT_RECORDED"))
        XCTAssertTrue(recorder.snapshot().events.contains { $0.omitted_fields["peer_name"] == "redacted" })
    }

    func testNativeErrorNeverIncludesLocalizedDescriptionOrUserInfo() {
        let native = NSError(domain: "SYNTHETIC_PRIVATE_DOMAIN", code: 42, userInfo: [NSLocalizedDescriptionKey: "SYNTHETIC_HEALTH_SENTINEL", "access_token": "SYNTHETIC_SECRET_SENTINEL"])
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.transportError, fields: DiagnosticRecorder.errorFields(native))
        let event = recorder.snapshot().events[0]
        XCTAssertEqual(event.fields["error_code"], .integer(42))
        XCTAssertEqual(event.fields["error_domain"], .text("unknown"))
        XCTAssertFalse(event.jsonLine.contains("SYNTHETIC_"))
    }

    func testDisableFlushesAndClearDeletesPrivateRecordingAndBundles() throws {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.appStarted)
        XCTAssertEqual(recorder.snapshot().events.count, 1)
        let prepared = try DiagnosticBundleBuilder.prepare(recorder: recorder)
        recorder.configure(enabled: false, verbosity: .trace)
        recorder.record(.nativeLifecycle)
        XCTAssertEqual(recorder.snapshot().events.count, 1)
        recorder.clear()
        XCTAssertTrue(recorder.snapshot().events.isEmpty)
        XCTAssertEqual(recorder.settings.privateContextUntil, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.directory.path))
        XCTAssertFalse(DiagnosticRecorder(directory: root).settings.enabled)
    }

    func testByteBudgetAndVerbosityAreIndependentOfPrivacy() throws {
        let recorder = DiagnosticRecorder(directory: root, byteLimit: 2048)
        recorder.configure(enabled: true, verbosity: .info)
        recorder.record(.messageSent)
        XCTAssertTrue(recorder.snapshot().events.isEmpty)
        for _ in 0..<40 { recorder.record(.appStarted) }
        let snapshot = recorder.snapshot()
        XCTAssertFalse(snapshot.events.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension == "jsonl" }
        let total = try files.reduce(0) { $0 + ((try $1.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(total, 2048)
    }

    func testExpiredSegmentsAndSymlinksAreNotRead() throws {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.appStarted)
        _ = recorder.snapshot()
        let expired = root.appendingPathComponent("operational-1-\(UUID().uuidString).jsonl")
        try Data("SYNTHETIC_HEALTH_SENTINEL".utf8).write(to: expired)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("SYNTHETIC_SECRET_SENTINEL".utf8).write(to: outside)
        let link = root.appendingPathComponent("operational-\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertEqual(recorder.snapshot().events.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "SYNTHETIC_SECRET_SENTINEL")
    }

    func testOriginalAttachmentFreezeDisclosureAndTamperDetection() throws {
        let recorder = DiagnosticRecorder(directory: root.appendingPathComponent("recorder"))
        let source = root.appendingPathComponent("synthetic-original.json")
        let original = Data("{\"synthetic\":\"EXPLICIT_ATTACHMENT_SENTINEL\",\"unicode\":\"🙂\"}".utf8)
        try original.write(to: source)
        let prepared = try DiagnosticBundleBuilder.prepare(recorder: recorder, attachments: [source])
        XCTAssertEqual(prepared.manifest.health_content, "possible")
        XCTAssertTrue(prepared.manifest.contains_private_context)
        XCTAssertEqual(try Data(contentsOf: prepared.directory.appendingPathComponent("attachments/attachment-1.json")), original)
        try Data("changed source".utf8).write(to: source)
        XCTAssertEqual(try Data(contentsOf: prepared.directory.appendingPathComponent("attachments/attachment-1.json")), original)
        XCTAssertEqual(try prepared.verifiedURL(), prepared.zipURL)
        let cut = try XCTUnwrap(original.firstIndex(of: 0xF0)) + 1
        let preview = try prepared.preview("attachments/attachment-1.json", maximumBytes: cut)
        XCTAssertTrue(preview.truncated, "A UTF-8 boundary cut must still disclose a bounded preview")
        try Data("changed zip".utf8).write(to: prepared.zipURL)
        XCTAssertThrowsError(try prepared.verifiedURL())
    }

    func testOperationalBundleHasNoHealthContentAndNoSelectedAttachmentRead() throws {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.appStarted)
        let prepared = try DiagnosticBundleBuilder.prepare(recorder: recorder)
        XCTAssertEqual(prepared.manifest.health_content, "not_included")
        XCTAssertFalse(prepared.manifest.contains_private_context)
        XCTAssertFalse(prepared.manifest.files.contains { $0.privacy == "user_attachment" })
        XCTAssertTrue(try prepared.preview("manifest.json").text.contains("healthmd.diagnostic_bundle"))
        XCTAssertThrowsError(try prepared.preview("../../settings.json"))
    }

    func testPrivateExpiryAndAdmissionTimestamps() throws {
        let clock = DiagnosticTestClock(Date())
        let recorder = DiagnosticRecorder(directory: root, clock: clock.now)
        recorder.startPrivateContextRecording()
        recorder.record(.peerDiscovered, fields: [.peerName: .text("SYNTHETIC_PRIVATE_PEER")])
        _ = recorder.snapshot(includePrivate: true)
        clock.advance(16 * 60)
        let admitted = clock.now()
        recorder.record(.peerLost, fields: [.peerName: .text("SYNTHETIC_NOT_RECORDED")])
        clock.advance(60)
        let snapshot = recorder.snapshot(includePrivate: true)
        let lost = try XCTUnwrap(snapshot.events.first { $0.event_id == .peerLost })
        XCTAssertEqual(lost.timestamp, DiagnosticRecorder.timestamp(admitted))
        XCTAssertEqual(lost.omitted_fields["peer_name"], "not_recorded")
        clock.advance(DiagnosticRecorder.privateRetentionSeconds)
        XCTAssertFalse(recorder.snapshot(includePrivate: true).events.map(\.jsonLine).joined().contains("SYNTHETIC_PRIVATE_PEER"))
    }

    func testMalformedShapesDuplicateEventsAndUnavailableFields() throws {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.connectionChanged, fields: [.state: .text("connected")], unavailable: [.transport])
        let event = try XCTUnwrap(recorder.snapshot().events.first)
        XCTAssertEqual(event.omitted_fields["transport"], "unavailable")
        let duplicate = root.appendingPathComponent("operational-\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).jsonl")
        try Data((event.jsonLine + "\n").utf8).write(to: duplicate)
        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.invalidEventCount, 1)
        var raw = try JSONSerialization.jsonObject(with: Data(event.jsonLine.utf8)) as! [String: Any]
        raw["fields"] = ["state": ["nested": "SYNTHETIC_HEALTH_SENTINEL"]]
        let nested = try JSONDecoder().decode(DiagnosticEvent.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(nested.filtered(includePrivate: false)?.omitted_fields["state"], "invalid")
    }

    func testStorageFailureIsReportedWithoutChangingCallerOutcome() throws {
        let blocked = root.appendingPathComponent("file-not-directory")
        try Data().write(to: blocked)
        let recorder = DiagnosticRecorder(directory: blocked)
        recorder.record(.appStarted)
        let snapshot = recorder.snapshot()
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertGreaterThan(snapshot.droppedEventCount, 0)
    }

    func testChangingPreviewContentInvalidatesReviewedArchive() throws {
        let recorder = DiagnosticRecorder(directory: root)
        recorder.record(.appStarted)
        let prepared = try DiagnosticBundleBuilder.prepare(recorder: recorder)
        try Data("SYNTHETIC_MODIFIED_REVIEW".utf8).write(to: prepared.directory.appendingPathComponent("events.jsonl"))
        XCTAssertThrowsError(try prepared.preview("events.jsonl"))
        XCTAssertThrowsError(try prepared.verifiedURL())
    }

    func testSymlinkAttachmentFailsWithoutLeavingPartialBundle() throws {
        let source = root.appendingPathComponent("original.txt")
        try Data("explicit user attachment".utf8).write(to: source)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let recorder = DiagnosticRecorder(directory: root.appendingPathComponent("recorder"))
        XCTAssertThrowsError(try DiagnosticBundleBuilder.prepare(recorder: recorder, attachments: [link]))
        let bundles = recorder.directory.appendingPathComponent("bundles")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: bundles, includingPropertiesForKeys: nil).isEmpty)
    }
}

nonisolated private final class DiagnosticTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); defer { lock.unlock() }; value = value.addingTimeInterval(seconds) }
}
