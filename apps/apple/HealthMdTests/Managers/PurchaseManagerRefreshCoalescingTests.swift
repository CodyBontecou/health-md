import XCTest
@testable import HealthMd

/// `refreshStatus` resets shared entitlement state across awaits, so two
/// refreshes must never interleave (#342 review). These tests replace the
/// StoreKit body with a gated probe and drive concurrent callers.
@MainActor
final class PurchaseManagerRefreshCoalescingTests: XCTestCase {
    /// Records each refresh body run and holds it open until released.
    @MainActor
    private final class RefreshProbe {
        struct Run: Equatable { let historical: Bool; let server: Bool }
        private(set) var runs: [Run] = []
        private(set) var active = 0
        private(set) var maxActive = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []
        var onRun: ((PurchaseManager) -> Void)?

        func body(_ manager: PurchaseManager, historical: Bool, server: Bool) async {
            runs.append(Run(historical: historical, server: server))
            active += 1
            maxActive = max(maxActive, active)
            await withCheckedContinuation { waiting.append($0) }
            onRun?(manager)
            active -= 1
        }

        var pendingCount: Int { waiting.count }

        func releaseOne() {
            guard !waiting.isEmpty else { return }
            waiting.removeFirst().resume()
        }
    }

    private var keychain: FakeKeychainStore!
    private var defaults: FakeUserDefaults!

    override func setUp() {
        super.setUp()
        keychain = FakeKeychainStore()
        defaults = FakeUserDefaults()
    }

    private func makeManager(probe: RefreshProbe, reliable: Bool = false) -> PurchaseManager {
        let manager = PurchaseManager(
            keychain: keychain,
            defaults: defaults,
            entitlementReadIsReliable: { reliable },
            refreshWork: { manager, historical, server in
                await probe.body(manager, historical: historical, server: server)
            }
        )
        LifecycleHarness.retain(manager)
        return manager
    }

    /// Lets queued main-actor tasks reach their first suspension point.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testConcurrentEqualRefreshesShareOneRun() async {
        let probe = RefreshProbe()
        let manager = makeManager(probe: probe)
        let callers = (0..<3).map { _ in Task { await manager.refreshStatus() } }
        await settle()
        XCTAssertEqual(probe.pendingCount, 1, "Later callers wait for the running refresh")

        probe.releaseOne()
        for caller in callers { await caller.value }

        XCTAssertEqual(probe.runs.count, 1)
        XCTAssertEqual(probe.maxActive, 1)
    }

    func testStrongerRefreshRunsAfterTheWeakerOneFinishes() async {
        let probe = RefreshProbe()
        let manager = makeManager(probe: probe)
        let background = Task { await manager.refreshStatus(allowsServerVerification: false) }
        await settle()
        let restore = Task { await manager.refreshStatus(includeHistoricalFallback: true) }
        await settle()
        XCTAssertEqual(probe.runs.count, 1, "The stronger refresh must not start while one is running")

        probe.releaseOne()
        await background.value
        await settle()
        XCTAssertEqual(probe.runs.count, 2)
        probe.releaseOne()
        await restore.value

        XCTAssertEqual(probe.runs, [
            .init(historical: false, server: false),
            .init(historical: true, server: true),
        ])
        XCTAssertEqual(probe.maxActive, 1)
    }

    func testWeakerRefreshReusesARunningStrongerOne() async {
        let probe = RefreshProbe()
        let manager = makeManager(probe: probe)
        let launch = Task { await manager.refreshStatus() }
        await settle()
        let background = Task { await manager.refreshStatus(allowsServerVerification: false) }
        await settle()

        probe.releaseOne()
        await launch.value
        await background.value

        XCTAssertEqual(probe.runs.count, 1)
    }

    /// The #342 race: a background launch starts its StoreKit refresh, and the
    /// scheduled admission check arrives before that refresh has finished.
    func testScheduledAdmissionWaitsForTheInFlightLaunchRefresh() async {
        let probe = RefreshProbe()
        probe.onRun = { $0.recordStoreKitEntitlementForTesting(productID: PurchaseManager.productID) }
        let manager = makeManager(probe: probe)
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)

        let launch = Task { await manager.refreshStatus() }
        await settle()
        XCTAssertFalse(manager.isUnlocked, "Access is unresolved while the launch refresh runs")
        XCTAssertFalse(manager.canExport)

        let admission = Task { await manager.scheduledExportAccess(jobID: UUID()) }
        await settle()
        probe.releaseOne()
        await launch.value
        let decision = await admission.value

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(probe.runs.count, 1, "Admission reuses the launch refresh")
        XCTAssertEqual(manager.freeExportsUsed, PurchaseManager.freeExportLimit)
    }

    /// Documents the pre-fix behavior: reading `canExport` without awaiting the
    /// refresh treats a Lifetime owner with no free exports left as free.
    func testReadingCanExportBeforeTheRefreshFinishesMisreportsALifetimeOwner() async {
        let probe = RefreshProbe()
        probe.onRun = { $0.recordStoreKitEntitlementForTesting(productID: PurchaseManager.productID) }
        let manager = makeManager(probe: probe)
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)

        let launch = Task { await manager.refreshStatus() }
        await settle()
        let unawaitedDecision = manager.canExport
        probe.releaseOne()
        await launch.value

        XCTAssertFalse(unawaitedDecision, "The old scheduled check saw a paid owner as out of free exports")
        XCTAssertTrue(manager.canExport)
    }
}
