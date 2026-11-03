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

    func testConcurrentCoordinatorsShareLiveSuccessAndFailure() async throws {
        for fails in [false, true] {
            let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
            let first = ClinicForegroundRefresh(store: try ClinicPrivateStore(root: root), enabled: { true })
            let retry = ClinicForegroundRefresh(store: try ClinicPrivateStore(root: root), enabled: { true })
            var release: CheckedContinuation<Void, Never>?
            var exports = 0; var reports: [ClinicRefreshRecord.State] = []; var authenticated = false
            let owner = Task { try await first.run(request: request, now: { self.now }, authenticate: {}, authorize: {},
                export: { check in
                    exports += 1
                    await withCheckedContinuation { release = $0 }
                    try await check()
                    if fails { throw ClinicNativeError.unavailable }
                    return "export_synthetic"
                }, report: { reports.append($0.state) }) }
            while release == nil { await Task.yield() }
            let duplicate = Task { try await retry.run(request: request, now: { self.now }, authenticate: { authenticated = true }, authorize: {},
                export: { _ in XCTFail("duplicate export"); return "unreachable" }, report: { _ in XCTFail("duplicate report") }) }
            while !authenticated { await Task.yield() }
            await Task.yield()
            XCTAssertTrue(reports.isEmpty)
            let changed = ClinicRefreshRequest(requestID: request.requestID, subjectID: request.subjectID, deviceID: request.deviceID,
                connectionID: request.connectionID, profileID: request.profileID, revision: "changed_synthetic",
                start: request.start, end: request.end, expiresAt: request.expiresAt)
            do {
                _ = try await retry.run(request: changed, now: { self.now }, authenticate: {}, authorize: {},
                    export: { _ in XCTFail("changed scope"); return "unreachable" }, report: { _ in })
                XCTFail("changed scope accepted")
            } catch { }
            release?.resume()
            if fails {
                do { _ = try await owner.value; XCTFail("export failed") } catch { }
                do { _ = try await duplicate.value; XCTFail("same failure") } catch { }
                XCTAssertEqual(reports, [.failed])
            } else {
                let original = try await owner.value; let joined = try await duplicate.value
                XCTAssertEqual(original, joined); XCTAssertEqual(reports, [.uploaded])
            }
            XCTAssertEqual(exports, 1)
        }
    }
    func testRevocationWhileExportSuspendsStopsPublicationAndRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = ClinicForegroundRefresh(store: try ClinicPrivateStore(root: root), enabled: { true })
        var release: CheckedContinuation<Void, Never>?
        var allowed = true; var publications = 0
        let operation = Task { try await coordinator.run(request: request, now: { self.now }, authenticate: {},
            authorize: { guard allowed else { throw ClinicNativeError.unavailable } }, export: { check in
                await withCheckedContinuation { release = $0 }
                try await check(); publications += 1; return "unreachable"
            }, report: { XCTAssertEqual($0.state, .failed) }) }
        while release == nil { await Task.yield() }
        allowed = false; release?.resume()
        do { _ = try await operation.value; XCTFail("revoked") } catch { }
        let retry = try await coordinator.run(request: request, now: { self.now }, authenticate: {}, authorize: {},
            export: { _ in XCTFail("must not retry revoked export"); return "unreachable" }, report: { _ in })
        XCTAssertEqual(retry.state, .failed); XCTAssertEqual(publications, 0)
    }

    func testCurrentDayOwnerScopeIsExplicitAndNeverRoundsTimestampConsent() throws {
        let clock = Date(timeIntervalSince1970: 1_793_709_296) // 2026-11-03 midday UTC
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: clock); let end = calendar.date(byAdding: .day, value: 1, to: start)!
        func scoped(_ end: Date, zone: String? = nil) -> ClinicRefreshRequest {
            ClinicRefreshRequest(requestID: "today_synthetic", subjectID: request.subjectID, deviceID: request.deviceID,
                connectionID: request.connectionID, profileID: request.profileID, revision: request.revision,
                start: start, end: end, expiresAt: clock.addingTimeInterval(300), ownerDayZone: zone)
        }
        let approved = scoped(end, zone: "UTC")
        XCTAssertEqual(try approved.ownerDates(timeZoneIdentifier: "UTC", now: clock), [start])
        XCTAssertThrowsError(try scoped(end).validate(now: clock)) // future timestamp is still forbidden
        let exact = scoped(clock)
        XCTAssertNoThrow(try exact.validate(now: clock))
        XCTAssertThrowsError(try exact.ownerDates(timeZoneIdentifier: "UTC", now: clock))
        XCTAssertThrowsError(try approved.ownerDates(timeZoneIdentifier: "America/New_York", now: clock))
        XCTAssertThrowsError(try scoped(end.addingTimeInterval(86400), zone: "UTC").validate(now: clock))
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try ClinicPrivateStore(root: root)
        try store.save(ClinicRefreshRecord(request: approved, state: .requested), key: "today_synthetic")
        XCTAssertEqual(try store.load(ClinicRefreshRecord.self, key: "today_synthetic")?.request, approved)
    }
    func testOwnerDayScopeKeepsDSTBoundary() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-11-01T04:00:00Z")!
        let end = formatter.date(from: "2026-11-02T05:00:00Z")!
        let clock = formatter.date(from: "2026-11-01T17:00:00Z")!
        let approved = ClinicRefreshRequest(requestID: "dst_synthetic", subjectID: request.subjectID, deviceID: request.deviceID,
            connectionID: request.connectionID, profileID: request.profileID, revision: request.revision,
            start: start, end: end, expiresAt: clock.addingTimeInterval(300), ownerDayZone: zone.identifier)
        XCTAssertEqual(try approved.ownerDates(timeZoneIdentifier: zone.identifier, now: clock), [start])
        XCTAssertEqual(end.timeIntervalSince(start), 25 * 3600)
    }

}
