import XCTest
@testable import HealthMd

@MainActor
final class ClinicInboxTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    func testConsentRequiredAndExactReviewDigestUsed() async {
        let transport = SyntheticClinicInboxTransport(now: now)
        let model = ClinicInboxModel(transport: transport, enabled: { true }, now: { self.now })
        await model.load(); XCTAssertEqual(transport.exports, 0)
        model.openReview("setup_synthetic")
        XCTAssertFalse(model.canApply)
        let denied = await model.apply(); XCTAssertFalse(denied)
        XCTAssertEqual(transport.value.reviews.count, 1)
        model.consent = true
        let applied = await model.apply(); XCTAssertTrue(applied)
        XCTAssertTrue(transport.value.reviews.isEmpty)
        XCTAssertFalse(model.consent); XCTAssertNil(model.review)
    }
    func testReceiptReportingNeverExportsAgainOrClaimsClinicProcessing() async {
        let transport = SyntheticClinicInboxTransport(now: now)
        let model = ClinicInboxModel(transport: transport, enabled: { true }, now: { self.now })
        await model.load(); await model.export("refresh_synthetic")
        XCTAssertEqual(model.snapshot.refreshes.first?.status, .uploaded)
        await model.export("refresh_synthetic")
        await model.reportReceipt("refresh_synthetic")
        XCTAssertEqual(transport.exports, 1); XCTAssertEqual(transport.receiptsReported, 1)
        XCTAssertEqual(model.snapshot.refreshes.first?.status, .uploaded)
        XCTAssertFalse(model.snapshot.refreshes.first?.receiptPending ?? true)
        await model.revoke("connection_synthetic")
        XCTAssertEqual(model.snapshot.refreshes.first?.status, .uploaded)
        XCTAssertFalse(model.snapshot.refreshes.first?.sharingActive ?? true)
    }
    func testExpiredReviewAndChangedAccountCannotApply() async {
        let transport = SyntheticClinicInboxTransport(now: now)
        var date = now
        let model = ClinicInboxModel(transport: transport, enabled: { true }, now: { date })
        await model.load(); model.openReview("setup_synthetic"); model.consent = true
        date = now.addingTimeInterval(901)
        XCTAssertFalse(model.canApply)
        let expired = await model.apply(); XCTAssertFalse(expired)
        date = now; model.openReview("setup_synthetic"); model.consent = true
        transport.sessionID = nil
        XCTAssertFalse(model.canApply)
        let loggedOut = await model.apply(); XCTAssertFalse(loggedOut)
        XCTAssertTrue(model.snapshot.refreshes.isEmpty); XCTAssertEqual(transport.exports, 0)
    }
    func testCancelAndRevocationAreExplicitActions() async {
        let transport = SyntheticClinicInboxTransport(now: now)
        let model = ClinicInboxModel(transport: transport, enabled: { true }, now: { self.now })
        await model.load(); await model.cancel("refresh_synthetic")
        XCTAssertEqual(model.snapshot.refreshes.first?.status, .cancelled)
        await model.revoke("connection_synthetic")
        XCTAssertEqual(model.snapshot.refreshes.first?.status, .cancelled)
        XCTAssertFalse(model.snapshot.refreshes.first?.sharingActive ?? true)
        XCTAssertEqual(transport.exports, 0)
    }
    func testDefaultGateLeavesTransportDormant() async {
        let transport = SyntheticClinicInboxTransport(now: now)
        let model = ClinicInboxModel(transport: transport)
        await model.load()
        XCTAssertTrue(model.unavailable); XCTAssertTrue(model.snapshot.reviews.isEmpty)
        XCTAssertEqual(transport.exports, 0)
    }
    func testStaleLoadCannotOverwriteNewerState() async {
        let transport = SuspendedClinicInboxTransport(now: now)
        let model = ClinicInboxModel(transport: transport, enabled: { true }, now: { self.now })
        let old = Task { await model.load() }
        while transport.pending == nil { await Task.yield() }
        model.clear(); await model.load()
        transport.pending?.resume(returning: transport.base.value)
        transport.pending = nil; await old.value
        XCTAssertTrue(model.snapshot.reviews.isEmpty); XCTAssertEqual(model.snapshot.refreshes.count, 1); XCTAssertFalse(model.loading)
    }
    func testUncertainActionRequiresReloadBeforeRetry() async {
        let transport = SuspendedClinicInboxTransport(now: now)
        transport.suspendFirstLoad = false
        let model = ClinicInboxModel(transport: transport, enabled: { true }, now: { self.now })
        await model.load(); await model.export("refresh_synthetic"); await model.export("refresh_synthetic")
        XCTAssertTrue(model.error); XCTAssertEqual(transport.base.exports, 1)
    }

}


@MainActor
private final class SuspendedClinicInboxTransport: ClinicInboxTransport {
    let base: SyntheticClinicInboxTransport
    var sessionID: String? { base.sessionID }
    var pending: CheckedContinuation<ClinicInboxSnapshot, Never>?
    var suspendFirstLoad = true
    var offline = false
    var newerLoadIsEmpty = false
    init(now: Date) { base = SyntheticClinicInboxTransport(now: now) }
    func load() async throws -> ClinicInboxSnapshot {
        if suspendFirstLoad { suspendFirstLoad = false; newerLoadIsEmpty = true; return await withCheckedContinuation { pending = $0 } }
        if offline { throw ClinicInboxError.unavailable }
        return newerLoadIsEmpty ? ClinicInboxSnapshot(refreshes: base.value.refreshes) : base.value
    }
    func applySetup(id: String, reviewedDigest: String) async throws { try await base.applySetup(id: id, reviewedDigest: reviewedDigest) }
    func export(id: String) async throws { try await base.export(id: id); offline = true }
    func reportReceipt(id: String) async throws { try await base.reportReceipt(id: id) }
    func cancel(id: String) async throws { try await base.cancel(id: id) }
    func revoke(connectionID: String) async throws { try await base.revoke(connectionID: connectionID) }
}
