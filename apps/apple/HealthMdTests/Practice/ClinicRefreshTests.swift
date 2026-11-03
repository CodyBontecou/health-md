import XCTest
@testable import HealthMd

@MainActor
final class ClinicRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private var request: ClinicRefreshRequest {
        ClinicRefreshRequest(requestID: "request_synthetic", subjectID: "subject_synthetic", deviceID: "device_synthetic",
            connectionID: "connection_synthetic", profileID: "profile_synthetic", revision: "revision_synthetic",
            start: now.addingTimeInterval(-172800), end: now.addingTimeInterval(-86400), expiresAt: now.addingTimeInterval(300))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("clinic-synthetic-" + UUID().uuidString) }

    func testGateDefaultsOff() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = ClinicForegroundRefresh(store: try ClinicPrivateStore(root: root))
        do {
            _ = try await coordinator.run(request: request, now: { self.now }, authenticate: {}, authorize: {},
                export: { _ in XCTFail("must not export"); return "unreachable" }, report: { _ in })
            XCTFail("disabled")
        } catch { }
    }
    func testReceiptSurvivesRestartAcknowledgmentFailureAndHealthLock() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = ClinicForegroundRefresh(store: try ClinicPrivateStore(root: root), enabled: { true })
        var exports = 0
        do {
            _ = try await first.run(request: request, now: { self.now }, authenticate: {}, authorize: {},
                export: { check in try await check(); exports += 1; return "export_synthetic" },
                report: { _ in throw ClinicNativeError.unavailable })
            XCTFail("offline")
        } catch { }
        let replay = ClinicForegroundRefresh(store: try ClinicPrivateStore(root: root), enabled: { true })
        let result = try await replay.run(request: request, now: { self.now.addingTimeInterval(400) }, authenticate: {},
            authorize: { XCTFail("receipt reporting needs no Health access") },
            export: { _ in XCTFail("must not reexport"); return "unreachable" }, report: { _ in })
        XCTAssertEqual(result.state, .uploaded); XCTAssertEqual(result.exportID, "export_synthetic"); XCTAssertEqual(exports, 1)
    }
    func testInterruptedExecutionNeverRepeatsExport() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClinicPrivateStore(root: root)
        let key = ["refresh", request.subjectID, request.deviceID, request.requestID].joined(separator: "\u{0}")
        try store.save(ClinicRefreshRecord(request: request, state: .executing), key: key)
        let result = try await ClinicForegroundRefresh(store: store, enabled: { true }).run(request: request,
            now: { self.now }, authenticate: {}, authorize: {},
            export: { _ in XCTFail("must not repeat"); return "unreachable" }, report: { _ in })
        XCTAssertEqual(result.state, .failed)
    }
    func testCorruptJournalFailsClosed() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClinicPrivateStore(root: root)
        let key = ["refresh", request.subjectID, request.deviceID, request.requestID].joined(separator: "\u{0}")
        try store.save(ClinicRefreshRecord(request: request, state: .executing), key: key)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        try Data("corrupt_synthetic".utf8).write(to: file)
        XCTAssertThrowsError(try store.load(ClinicRefreshRecord.self, key: key))
    }
    func testPermissionAndEntitlementRemainIndependentFromConsent() async throws {
        let allowed = ClinicExportGates(subjectID: request.subjectID, deviceID: request.deviceID,
            connectionID: request.connectionID, foreground: true, sharingConsent: true,
            healthDataAvailable: true, consumerAllowsExport: true, verifiedClinicGrant: false)
        XCTAssertNoThrow(try allowed.require(for: request))
        let unqualifiedClinic = ClinicExportGates(subjectID: request.subjectID, deviceID: request.deviceID,
            connectionID: request.connectionID, foreground: true, sharingConsent: true,
            healthDataAvailable: true, consumerAllowsExport: false, verifiedClinicGrant: true)
        XCTAssertThrowsError(try unqualifiedClinic.require(for: request))
        let noConsent = ClinicExportGates(subjectID: request.subjectID, deviceID: request.deviceID,
            connectionID: request.connectionID, foreground: true, sharingConsent: false,
            healthDataAvailable: true, consumerAllowsExport: true, verifiedClinicGrant: true)
        XCTAssertThrowsError(try noConsent.require(for: request))
    }
    func testUnknownStorageVersionFailsClosed() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClinicPrivateStore(root: root)
        let key = ["refresh", request.subjectID, request.deviceID, request.requestID].joined(separator: "\u{0}")
        try store.save(ClinicRefreshRecord(request: request, state: .executing), key: key)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["storageVersion"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        XCTAssertThrowsError(try store.load(ClinicRefreshRecord.self, key: key))
    }

}
