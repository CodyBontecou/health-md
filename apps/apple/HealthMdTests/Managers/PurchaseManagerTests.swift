import XCTest
@testable import HealthMd

@MainActor
final class PurchaseManagerTests: XCTestCase {
    private var keychain: FakeKeychainStore!
    private var defaults: FakeUserDefaults!

    override func setUp() {
        super.setUp()
        keychain = FakeKeychainStore()
        defaults = FakeUserDefaults()
    }

    private func makeManager() -> PurchaseManager {
        let manager = PurchaseManager(keychain: keychain, defaults: defaults)
        LifecycleHarness.retain(manager)
        return manager
    }

    func testLegacyCutoffIsUnchangedAndStrict() {
        let cutoff = PurchaseManager.grandfatherCutoffDate
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: cutoff.addingTimeInterval(-1)))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: cutoff))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: cutoff.addingTimeInterval(1)))
    }

    func testFirstExportIsFreeAndFurtherExportsRequireAccess() {
        let manager = makeManager()
        XCTAssertEqual(PurchaseManager.freeExportLimit, 1)
        XCTAssertEqual(manager.freeExportsRemaining, 1)
        XCTAssertTrue(manager.canExportFree)
        XCTAssertTrue(manager.canExport)
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsUsed, 1)
        XCTAssertFalse(manager.canExport)
        XCTAssertFalse(manager.canExport(jobID: UUID()))
        XCTAssertNil(manager.pendingUpgradePrompt)
    }

    func testDurableExportConsumesOneFreeActionAndCannotBeReplayedForFree() throws {
        let id = UUID()
        let manager = makeManager()
        XCTAssertTrue(manager.canExport(jobID: id))
        try manager.recordExportUse(jobID: id)
        try manager.recordExportUse(jobID: id)
        XCTAssertEqual(manager.freeExportsUsed, 1)
        XCTAssertFalse(makeManager().canExport(jobID: id))
        XCTAssertFalse(makeManager().canExport(jobID: UUID()))
    }

    func testHistoricalUsageIsPreservedButNeverGrantsAccess() {
        let manager = makeManager()
        manager.setFreeExportsUsed(8)
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsUsed, 8)
        XCTAssertEqual(manager.freeExportsRemaining, 0)
        XCTAssertFalse(manager.canExport)
        manager.resetFreeExports()
        XCTAssertEqual(manager.freeExportsUsed, 0)
        XCTAssertTrue(manager.canExport)
    }

    func testOldDurableQuotaReceiptCannotBypassPaywall() {
        let id = UUID()
        keychain.writeString(key: "directExportUseIDs", value: id.uuidString.lowercased())
        XCTAssertFalse(makeManager().canExport(jobID: id))
    }

    private func makeScheduledManager(
        reliable: @escaping @MainActor () -> Bool,
        refresh: @escaping @MainActor (PurchaseManager) -> Void
    ) -> PurchaseManager {
        let manager = PurchaseManager(
            keychain: keychain,
            defaults: defaults,
            statusRefresher: { refresh($0) },
            entitlementReadIsReliable: reliable
        )
        LifecycleHarness.retain(manager)
        return manager
    }

    func testScheduledAccessAwaitsEntitlementRefreshBeforeQuotaCheck() async {
        let manager = makeScheduledManager(reliable: { false }) {
            $0.recordStoreKitEntitlementForTesting(productID: PurchaseManager.productID)
        }
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        XCTAssertFalse(manager.isUnlocked, "A background launch starts locked until StoreKit resolves")
        let decision = await manager.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .allowed)
    }

    func testScheduledAccessHonorsLastKnownLifetimeWhenBackgroundReadFails() async {
        var storeKitReadable = true
        let manager = makeScheduledManager(reliable: { storeKitReadable }) { manager in
            if storeKitReadable {
                manager.recordStoreKitEntitlementForTesting(productID: PurchaseManager.familyProductID)
            } else {
                manager.setUnlocked(false)
            }
        }
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let first = await manager.scheduledExportAccess(jobID: nil)
        XCTAssertEqual(first, .allowed)

        storeKitReadable = false
        // The persisted entitlement survives a relaunch into the background.
        let relaunched = makeScheduledManager(reliable: { false }) { $0.setUnlocked(false) }
        let decision = await relaunched.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .allowed)
        try? relaunched.recordExportUse(jobID: UUID())
        relaunched.recordExportUse()
        XCTAssertEqual(relaunched.freeExportsUsed, PurchaseManager.freeExportLimit,
                       "A known owner is never charged a free export")
    }

    func testScheduledAccessIsUnresolvedRatherThanLimitedWhenReadIsUnreliable() async {
        let manager = makeScheduledManager(reliable: { false }) { $0.setUnlocked(false) }
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let decision = await manager.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .entitlementUnresolved)
    }

    func testReliableNegativeReadRevokesLastKnownEntitlement() async {
        let owner = makeScheduledManager(reliable: { true }) {
            $0.recordStoreKitEntitlementForTesting(productID: PurchaseManager.productID)
        }
        _ = await owner.scheduledExportAccess(jobID: nil)
        XCTAssertTrue(owner.hasValidLastKnownEntitlement())

        // A locked-device read that finds nothing keeps the cached entitlement...
        let locked = makeScheduledManager(reliable: { false }) { $0.concludeNoEntitlementForTesting() }
        locked.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let lockedDecision = await locked.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(lockedDecision, .allowed)

        // ...but a refund observed by a reliable read on an unlocked device revokes it.
        let refunded = makeScheduledManager(reliable: { true }) {
            $0.concludeNoEntitlementForTesting(cachedEntitlementRevoked: true)
        }
        let decision = await refunded.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .limitReached)
        XCTAssertFalse(refunded.hasValidLastKnownEntitlement())
    }

    /// Regression: a lifetime owner got "Free Export Limit Reached" from a
    /// scheduled export when StoreKit returned no entitlements on a background
    /// launch of an unlocked device, and the empty read erased the cache.
    func testReliableEmptyReadWithoutRevocationKeepsLifetimeOwner() async {
        for product in [PurchaseManager.productID, PurchaseManager.familyProductID, PurchaseManager.familyUpgradeProductID] {
            keychain = FakeKeychainStore()
            makeManager().recordStoreKitEntitlementForTesting(productID: product)

            let relaunched = makeScheduledManager(reliable: { true }) { $0.concludeNoEntitlementForTesting() }
            relaunched.setFreeExportsUsed(PurchaseManager.freeExportLimit)
            let decision = await relaunched.scheduledExportAccess(jobID: UUID())

            XCTAssertEqual(decision, .allowed, product)
            XCTAssertTrue(relaunched.isUnlocked, product)
            XCTAssertTrue(relaunched.canExport, product)
            XCTAssertTrue(relaunched.hasValidLastKnownEntitlement(), "\(product): an empty read must not erase the cache")
        }
    }

    func testReliableEmptyReadKeepsLegacyOwner() async {
        makeManager().recordLegacyUnlockForTesting()
        let relaunched = makeScheduledManager(reliable: { true }) { $0.concludeNoEntitlementForTesting() }
        relaunched.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let decision = await relaunched.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .allowed)
        XCTAssertTrue(relaunched.isLegacyUser)
        XCTAssertTrue(relaunched.hasValidLastKnownEntitlement())
    }

    func testReliableEmptyReadKeepsAnUnexpiredSubscription() async {
        makeManager().recordStoreKitEntitlementForTesting(
            productID: HealthMdPurchaseOption.yearly.productID,
            expirationDate: Date().addingTimeInterval(86_400))
        let relaunched = makeScheduledManager(reliable: { true }) { $0.concludeNoEntitlementForTesting() }
        relaunched.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let decision = await relaunched.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .allowed)
        XCTAssertTrue(relaunched.isUnlocked)
        XCTAssertEqual(relaunched.unlockedProductID, HealthMdPurchaseOption.yearly.productID)
        XCTAssertTrue(relaunched.hasValidLastKnownEntitlement(), "An empty read must not erase the cache")
    }

    func testReliableRevocationEndsAnUnexpiredSubscription() async {
        makeManager().recordStoreKitEntitlementForTesting(
            productID: HealthMdPurchaseOption.yearly.productID,
            expirationDate: Date().addingTimeInterval(86_400))
        let refunded = makeScheduledManager(reliable: { true }) {
            $0.concludeNoEntitlementForTesting(cachedEntitlementRevoked: true)
        }
        refunded.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let decision = await refunded.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .limitReached)
        XCTAssertFalse(refunded.isUnlocked)
        XCTAssertFalse(refunded.hasValidLastKnownEntitlement())
    }

    func testLockedReadDefersRevocationUntilAReliableRead() async {
        makeManager().recordStoreKitEntitlementForTesting(
            productID: HealthMdPurchaseOption.yearly.productID,
            expirationDate: Date().addingTimeInterval(86_400))
        let locked = makeScheduledManager(reliable: { false }) {
            $0.concludeNoEntitlementForTesting(cachedEntitlementRevoked: true)
        }
        locked.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let decision = await locked.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .allowed)
        XCTAssertTrue(locked.hasValidLastKnownEntitlement())
    }

    func testOnlyARevocationOfTheCachedPeriodEndsASubscription() {
        let end = Date()
        // Lifetime: any revocation of the product ends it.
        XCTAssertTrue(PurchaseManager.revocationEndsCachedTerm(cachedExpiresAt: nil, revokedExpiresAt: nil))
        // The cached period itself was refunded.
        XCTAssertTrue(PurchaseManager.revocationEndsCachedTerm(cachedExpiresAt: end, revokedExpiresAt: end))
        // An earlier period was refunded before a resubscribe.
        XCTAssertFalse(PurchaseManager.revocationEndsCachedTerm(
            cachedExpiresAt: end, revokedExpiresAt: end.addingTimeInterval(-30 * 86_400)))
        XCTAssertFalse(PurchaseManager.revocationEndsCachedTerm(cachedExpiresAt: end, revokedExpiresAt: nil))
    }

    func testExpiredSubscriptionIsNotALastKnownEntitlement() async {
        let now = Date()
        let manager = makeScheduledManager(reliable: { false }) {
            $0.recordStoreKitEntitlementForTesting(
                productID: HealthMdPurchaseOption.yearly.productID,
                expirationDate: now.addingTimeInterval(60))
        }
        _ = await manager.scheduledExportAccess(jobID: nil)
        XCTAssertTrue(manager.hasValidLastKnownEntitlement(now: now))
        XCTAssertFalse(manager.hasValidLastKnownEntitlement(now: now.addingTimeInterval(120)))
    }

    func testUnreliableEmptyReadKeepsAnUnlockedOwnerUnlockedForEveryCaller() {
        let owner = makeManager()
        owner.recordStoreKitEntitlementForTesting(productID: PurchaseManager.productID)
        owner.setFreeExportsUsed(PurchaseManager.freeExportLimit)

        // A locked background refresh in a later launch finds nothing in StoreKit.
        let relaunched = makeScheduledManager(reliable: { false }) { _ in }
        relaunched.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        relaunched.concludeNoEntitlementForTesting()

        // Shortcuts, Direct and API-endpoint paths only read canExport after
        // refreshStatus(), so the restore must land in the published state.
        XCTAssertTrue(relaunched.isUnlocked)
        XCTAssertTrue(relaunched.canExport)
        XCTAssertEqual(relaunched.unlockedProductID, PurchaseManager.productID)
    }

    func testUnreliableEmptyReadRestoresLegacyOwner() {
        makeManager().recordLegacyUnlockForTesting()
        let relaunched = makeScheduledManager(reliable: { false }) { _ in }
        relaunched.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        relaunched.concludeNoEntitlementForTesting()
        XCTAssertTrue(relaunched.isUnlocked)
        XCTAssertTrue(relaunched.isLegacyUser)
        XCTAssertTrue(relaunched.canExport)
    }

    func testUnreliableEmptyReadWithoutCacheStaysLocked() {
        let manager = makeScheduledManager(reliable: { false }) { _ in }
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        manager.concludeNoEntitlementForTesting()
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertFalse(manager.canExport)
    }

    func testUnreliableReadDoesNotRestoreAnExpiredSubscription() async {
        makeManager().recordStoreKitEntitlementForTesting(
            productID: HealthMdPurchaseOption.weekly.productID,
            expirationDate: Date().addingTimeInterval(-60))
        let relaunched = makeScheduledManager(reliable: { false }) { $0.concludeNoEntitlementForTesting() }
        relaunched.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let decision = await relaunched.scheduledExportAccess(jobID: UUID())
        XCTAssertFalse(relaunched.isUnlocked)
        // The subscription may have renewed; only a reliable read can say no.
        XCTAssertEqual(decision, .entitlementUnresolved)
    }

    func testFreeUserConfirmedByAReliableReadSeesTheLimitWhileLocked() async {
        let unlockedRead = makeScheduledManager(reliable: { true }) { $0.concludeNoEntitlementForTesting() }
        unlockedRead.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        let first = await unlockedRead.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(first, .limitReached)

        // Later runs while locked keep reporting the limit instead of deferring forever.
        let locked = makeScheduledManager(reliable: { false }) { $0.concludeNoEntitlementForTesting() }
        let decision = await locked.scheduledExportAccess(jobID: UUID())
        XCTAssertEqual(decision, .limitReached)
    }

    func testPurchaseAfterConfirmedNoneReplacesTheMarker() async {
        let free = makeScheduledManager(reliable: { true }) { $0.concludeNoEntitlementForTesting() }
        _ = await free.scheduledExportAccess(jobID: nil)
        free.recordStoreKitEntitlementForTesting(productID: PurchaseManager.familyProductID)
        XCTAssertTrue(free.hasValidLastKnownEntitlement())
    }

    func testEveryLifetimeProductAndLegacyOwnerRetainsAccess() {
        for product in [PurchaseManager.productID, PurchaseManager.familyProductID, PurchaseManager.familyUpgradeProductID] {
            let manager = makeManager()
            manager.setUnlockedProductID(product)
            XCTAssertTrue(manager.isUnlocked)
            XCTAssertTrue(manager.canExport)
            XCTAssertTrue(manager.canExport(jobID: UUID()))
        }
        let manager = makeManager()
        manager.setLegacyUser(true)
        XCTAssertTrue(manager.canExport)
    }

    func testCatalogContainsWeeklyYearlyAndExistingLifetimeIDsButNoMonthly() {
        XCTAssertEqual(Set(HealthMdPurchaseOption.allCases), Set([
            .weekly, .yearly, .individual, .familyWeekly, .familyYearly, .family, .familyUpgrade,
        ]))
        XCTAssertEqual(PurchaseManager.productID, "com.codybontecou.obsidianhealth.unlock")
        XCTAssertEqual(PurchaseManager.familyProductID, "com.codybontecou.obsidianhealth.unlock.family")
        XCTAssertEqual(PurchaseManager.familyUpgradeProductID, "com.codybontecou.obsidianhealth.unlock.family.upgrade")
        XCTAssertEqual(PurchaseManager.productIDs.count, 7)
        XCTAssertEqual(HealthMdPurchaseOption.yearly.productID, "com.codybontecou.obsidianhealth.pro.yearly.v2")
        XCTAssertEqual(HealthMdPurchaseOption.familyYearly.productID, "com.codybontecou.obsidianhealth.pro.family.yearly.v2")
        XCTAssertFalse(PurchaseManager.productIDs.contains { $0.contains("monthly") })
    }

    func testSubscriptionExpirationRevocationAndUpgradeAreNotPermanentGrants() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for option in HealthMdPurchaseOption.allCases.filter(\.isSubscription) {
            XCTAssertTrue(PurchaseManager.isActiveEntitlement(option: option,
                expirationDate: now.addingTimeInterval(1), revocationDate: nil, isUpgraded: false, now: now))
            for expiration in [nil, now, now.addingTimeInterval(-1)] as [Date?] {
                XCTAssertFalse(PurchaseManager.isActiveEntitlement(option: option,
                    expirationDate: expiration, revocationDate: nil, isUpgraded: false, now: now))
            }
            XCTAssertFalse(PurchaseManager.isActiveEntitlement(option: option,
                expirationDate: now.addingTimeInterval(1), revocationDate: now, isUpgraded: false, now: now))
            XCTAssertFalse(PurchaseManager.isActiveEntitlement(option: option,
                expirationDate: now.addingTimeInterval(1), revocationDate: nil, isUpgraded: true, now: now))
        }
    }

    func testLifetimeDoesNotExpireButRevocationsAreHonored() {
        for option in HealthMdPurchaseOption.allCases.filter({ !$0.isSubscription }) {
            XCTAssertTrue(PurchaseManager.isActiveEntitlement(option: option,
                expirationDate: nil, revocationDate: nil, isUpgraded: false))
            XCTAssertFalse(PurchaseManager.isActiveEntitlement(option: option,
                expirationDate: nil, revocationDate: Date(), isUpgraded: false))
        }
    }

    func testPreferredEntitlementKeepsLifetimeAheadOfSubscriptions() {
        XCTAssertEqual(PurchaseManager.preferredEntitlementProductID(from: PurchaseManager.productIDs), PurchaseManager.familyProductID)
        XCTAssertEqual(PurchaseManager.preferredEntitlementProductID(from: [
            HealthMdPurchaseOption.familyYearly.productID, PurchaseManager.productID,
        ]), PurchaseManager.productID)
        XCTAssertEqual(PurchaseManager.preferredEntitlementProductID(from: [
            HealthMdPurchaseOption.weekly.productID, HealthMdPurchaseOption.familyWeekly.productID,
        ]), HealthMdPurchaseOption.familyWeekly.productID)
        XCTAssertNil(PurchaseManager.preferredEntitlementProductID(from: ["unknown"]))
    }

    func testFamilyUpgradeRequiresPermanentIndividualOrLegacyAccess() {
        let manager = makeManager()
        XCTAssertFalse(manager.canBuyFamilyUpgrade)
        manager.setUnlockedProductID(HealthMdPurchaseOption.weekly.productID)
        XCTAssertFalse(manager.canBuyFamilyUpgrade)
        manager.setUnlockedProductID(PurchaseManager.productID)
        XCTAssertTrue(manager.canBuyFamilyUpgrade)
        manager.setUnlockedProductID(PurchaseManager.familyProductID)
        XCTAssertFalse(manager.canBuyFamilyUpgrade)
        XCTAssertTrue(manager.isFamilyUnlocked)
        let legacy = makeManager()
        legacy.setLegacyUser(true)
        XCTAssertTrue(legacy.canBuyFamilyUpgrade)
    }

    func testActivePlanTitlesDistinguishSubscriptionsAndLifetimeAccess() {
        let expected: [HealthMdPurchaseOption: String] = [
            .weekly: "Weekly active",
            .yearly: "Yearly active",
            .familyWeekly: "Family Weekly active",
            .familyYearly: "Family Yearly active",
            .individual: "Lifetime active",
            .family: "Family Lifetime active",
            .familyUpgrade: "Family Lifetime active",
        ]
        XCTAssertEqual(Set(expected.keys), Set(HealthMdPurchaseOption.allCases))
        for (option, title) in expected {
            let manager = makeManager()
            manager.setUnlockedProductID(option.productID)
            XCTAssertEqual(manager.activePlanTitle, title, option.rawValue)
            XCTAssertEqual(manager.canShowPermanentAccessNotice, !option.isSubscription, option.rawValue)
        }
        let legacy = makeManager()
        legacy.setLegacyUser(true)
        XCTAssertEqual(legacy.activePlanTitle, "Grandfathered Full Access active")
        XCTAssertTrue(legacy.canShowPermanentAccessNotice)
    }

    func testPermanentAccessNoticeRequiresKnownActivePermanentEvidence() {
        let manager = makeManager()
        XCTAssertEqual(manager.activePlanTitle, "Unlock Full Access")
        XCTAssertFalse(manager.canShowPermanentAccessNotice)
        manager.setUnlocked(true)
        XCTAssertFalse(manager.canShowPermanentAccessNotice, "An unlocked flag is not permanent purchase evidence")
        manager.setUnlockedProductID("unknown.product")
        XCTAssertFalse(manager.canShowPermanentAccessNotice)
        manager.setUnlockedProductID(PurchaseManager.familyUpgradeProductID)
        XCTAssertTrue(manager.canShowPermanentAccessNotice)
        manager.setUnlocked(false)
        XCTAssertFalse(manager.canShowPermanentAccessNotice, "A stale Lifetime product ID must not show the notice")
        XCTAssertEqual(manager.activePlanTitle, "Unlock Full Access")

        let legacy = makeManager()
        legacy.setLegacyUser(true)
        legacy.setUnlockedProductID(HealthMdPurchaseOption.yearly.productID)
        XCTAssertTrue(legacy.canShowPermanentAccessNotice, "Independent legacy access remains permanent")
        legacy.setLegacyUser(false)
        XCTAssertFalse(legacy.canShowPermanentAccessNotice, "Subscription access alone is not permanent")
        legacy.setLegacyUser(true)
        legacy.setUnlocked(false)
        XCTAssertFalse(legacy.canShowPermanentAccessNotice, "Inactive legacy state must not show the notice")
    }

    func testSettingsSurfacesUseSharedPlanCopyAndGuardPermanentNotice() throws {
        let appleRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["HealthMd/iOS/NewExperience/Settings/SettingsScreen.swift", "HealthMd/iOS/Views/PaywallView.swift"] {
            let source = try String(contentsOf: appleRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("purchaseManager.activePlanTitle"), path)
            XCTAssertFalse(source.contains("return \"Family Lifetime active\""), path)
        }
        let paywall = try String(contentsOf: appleRoot.appendingPathComponent("HealthMd/iOS/Views/PaywallView.swift"), encoding: .utf8)
        XCTAssertTrue(paywall.contains("if purchaseManager.canShowPermanentAccessNotice {"))
        XCTAssertTrue(paywall.contains("Your existing permanent access remains valid"))
        XCTAssertTrue(paywall.contains("Upgrade pricing for existing Lifetime owners"))
    }

    func testFamilySharedSubscriptionIsFamilyAccess() {
        let manager = makeManager()
        manager.setUnlockedProductID(HealthMdPurchaseOption.familyYearly.productID)
        XCTAssertTrue(manager.isFamilyUnlocked)
        XCTAssertFalse(manager.canBuyFamilyUpgrade)
    }

    func testPurchaseAndRestoreErrorsDoNotUnlock() async {
        let manager = makeManager()
        await manager.purchase(.weekly)
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertNotNil(manager.purchaseError)
        await manager.purchase(.familyUpgrade)
        XCTAssertEqual(manager.purchaseError, "Family Upgrade requires an existing Lifetime unlock.")
        XCTAssertFalse(manager.isUnlocked)
    }

    func testPurchaseRetriesProductLoading() async throws {
        #if os(macOS)
        throw XCTSkip("The free macOS companion does not load StoreKit products.")
        #else
        var attempts = 0
        let manager = PurchaseManager(keychain: keychain, defaults: defaults, productLoader: { ids in
            attempts += 1
            XCTAssertEqual(Set(ids), Set(PurchaseManager.productIDs))
            return []
        })
        LifecycleHarness.retain(manager)
        await manager.purchase(.yearly)
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(manager.isLoadingProducts)
        XCTAssertFalse(manager.isUnlocked)
        #endif
    }

    func testUnlockPreservesUsageThroughRelocking() {
        let manager = makeManager()
        manager.setFreeExportsUsed(3)
        manager.setUnlocked(true)
        XCTAssertEqual(manager.freeExportsUsed, 3)
        XCTAssertTrue(manager.canExport)
        manager.setUnlocked(false)
        XCTAssertFalse(manager.canExport)
        XCTAssertEqual(manager.freeExportsRemaining, 0)
    }

    func testLegacyUsageMigrationStillRunsExactlyOnce() {
        defaults.set(2, forKey: "freeExportsUsed")
        XCTAssertEqual(makeManager().freeExportsUsed, 2)
        XCTAssertTrue(defaults.bool(forKey: "freeExportsUsed_migratedToKeychain"))
        keychain.storage = [:]
        XCTAssertEqual(makeManager().freeExportsUsed, 0)
    }

    func testCachedDirectQueriesRecheckAccessBeforeSnapshotReuse() throws {
        let appleRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: appleRoot.appendingPathComponent("HealthMd/iOS/IPhoneDirectQueryCoordinator.swift"), encoding: .utf8)
        let admission = try XCTUnwrap(source.range(of: "guard PurchaseManager.shared.canExport else"))
        let cache = try XCTUnwrap(source.range(of: "let snapshot = try await snapshotForQuery"))
        XCTAssertLessThan(admission.lowerBound, cache.lowerBound,
                          "Cached pages must not bypass trial/subscription admission.")
    }

    func testRestoreHelpRetainsLegacyAndFamilyGuidance() {
        XCTAssertTrue(PurchaseManager.restoreNotFoundMessage.contains("Purchase Sharing"))
        XCTAssertTrue(PurchaseManager.restoreNotFoundMessage.contains("cody@isolated.tech"))
    }
}
