//
//  PurchaseManagerTests.swift
//  HealthMdTests
//
//  Tests for PurchaseManager state machine and business logic.
//  No StoreKit or network calls — uses injected fakes.
//

import XCTest
@testable import HealthMd

@MainActor
final class PurchaseManagerTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: PurchaseManager is an ObservableObject.
    // Static retention avoids macOS 26 / Swift 6 deinit crash.
    // See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [PurchaseManager] = []

    private var keychain: FakeKeychainStore!
    private var defaults: FakeUserDefaults!
    private var analyticsTransport: PurchaseManagerAnalyticsTransport!
    private var analyticsClient: PricingAnalyticsClient!

    override func setUp() {
        super.setUp()
        keychain = FakeKeychainStore()
        defaults = FakeUserDefaults()
        analyticsTransport = PurchaseManagerAnalyticsTransport()
        analyticsClient = PricingAnalyticsClient(
            transport: analyticsTransport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.purchase-manager.\(UUID().uuidString)",
            maxQueueSize: 10,
            isEnabled: true
        )
    }

    private func makeManager() -> PurchaseManager {
        let manager = PurchaseManager(keychain: keychain, defaults: defaults, analytics: analyticsClient)
        Self.retainedManagers.append(manager)
        return manager
    }

    // MARK: - Legacy Unlock Decision

    /// Build a UTC date for use in date-based assertions.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testIsLegacyUnlock_grandfathersAnyInstallBeforeCutoff() {
        // Pre-freemium paid era.
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 1, 1)))
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 3, 15)))
        // v1.7.x freemium era.
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 3, 25)))
        // v1.8.0 / v1.8.1 leak cohort (incl. Morgan, 2026-04-14).
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 4, 14)))
    }

    func testIsLegacyUnlock_doesNotGrandfatherInstallsAtOrAfterCutoff() {
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: PurchaseManager.grandfatherCutoffDate))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 9, 1)))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2027, 1, 15)))
    }

    func testIsLegacyUnlock_cutoffBoundaryIsStrict() {
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(
            originalPurchaseDate: PurchaseManager.grandfatherCutoffDate.addingTimeInterval(-1)
        ))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(
            originalPurchaseDate: PurchaseManager.grandfatherCutoffDate
        ))
    }

    // MARK: - Free Export Quota

    func testFreeExportsRemaining_defaultIsThree() {
        let manager = makeManager()
        XCTAssertEqual(manager.freeExportsRemaining, 3)
    }

    func testRecordExportUse_decrementsRemaining() {
        let manager = makeManager()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 2)
    }

    func testRecordExportUse_tracksFreeExportUsageAfterIncrement() async {
        let manager = makeManager()

        manager.recordExportUse()
        await analyticsClient.flushAndWait()

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.eventName, "pricing_free_export_used")
        XCTAssertEqual(payloads.first?.properties[.freeExportsUsed], .int(1))
        XCTAssertEqual(payloads.first?.properties[.freeExportsRemaining], .int(2))
    }

    func testRecordExportUse_stopsAtZero() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 0)

        // Extra call should not go negative
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 0)
    }

    func testResetFreeExports_restoresQuota() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 1)

        manager.resetFreeExports()
        XCTAssertEqual(manager.freeExportsRemaining, 3)
    }

    // MARK: - canExport

    func testCanExport_trueWhenFreeExportsAvailable() {
        let manager = makeManager()
        XCTAssertTrue(manager.canExport)
    }

    func testCanExport_falseWhenQuotaExhaustedAndNotUnlocked() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertFalse(manager.canExport)
    }

    func testRecordExportUse_noOpWhenUnlocked() {
        let manager = makeManager()
        manager.setUnlocked(true)
        manager.recordExportUse() // should be no-op
        XCTAssertEqual(manager.freeExportsUsed, 0, "Should not increment when unlocked")
    }

    func testRecordExportUse_doesNotTrackWhenUnlocked() async {
        let manager = makeManager()
        manager.setUnlocked(true)

        manager.recordExportUse()
        await analyticsClient.flushAndWait()

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads, [])
    }

    // MARK: - Purchase Analytics

    func testPurchaseRetriesProductLoadBeforeStoreUnavailableFailure() async throws {
        #if os(macOS)
        throw XCTSkip("The free macOS companion intentionally does not load StoreKit products.")
        #else
        var productLoadAttempts = 0
        let manager = PurchaseManager(
            keychain: keychain,
            defaults: defaults,
            analytics: analyticsClient,
            productLoader: { productIDs in
                productLoadAttempts += 1
                XCTAssertEqual(Set(productIDs), Set(PurchaseManager.productIDs))
                return []
            }
        )
        Self.retainedManagers.append(manager)

        await manager.purchase(.individual)
        await analyticsClient.flushAndWait()

        XCTAssertEqual(productLoadAttempts, 1)
        XCTAssertFalse(manager.isLoadingProducts)
        XCTAssertEqual(manager.purchaseError, "Product unavailable. Please try again later.")

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_purchase_started",
            "pricing_purchase_finished"
        ])
        XCTAssertEqual(payloads.last?.properties[.purchaseOutcome], .string("failed"))
        XCTAssertEqual(payloads.last?.properties[.errorCategory], .string("store_unavailable"))
        #endif
    }

    func testPurchaseUnavailableTracksStartedAndFailedOutcome() async {
        let manager = makeManager()

        await manager.purchase()
        await analyticsClient.flushAndWait()

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_purchase_started",
            "pricing_purchase_finished"
        ])
        XCTAssertEqual(payloads.first?.properties[.productId], .string(PurchaseManager.productID))
        XCTAssertEqual(payloads.first?.properties[.freeExportsUsed], .int(0))
        XCTAssertEqual(payloads.first?.properties[.freeExportsRemaining], .int(3))
        XCTAssertEqual(payloads.last?.properties[.purchaseOutcome], .string("failed"))
        XCTAssertEqual(payloads.last?.properties[.errorCategory], .string("store_unavailable"))
    }

    func testProductCatalogContainsOnlyLifetimeOptions() {
        XCTAssertEqual(
            Set(HealthMdPurchaseOption.allCases),
            Set([.individual, .family, .familyUpgrade])
        )
        XCTAssertEqual(
            Set(PurchaseManager.productIDs),
            Set([
                PurchaseManager.productID,
                PurchaseManager.familyProductID,
                PurchaseManager.familyUpgradeProductID,
            ])
        )
        XCTAssertFalse(PurchaseManager.productIDs.contains("com.codybontecou.obsidianhealth.pro.monthly"))
        XCTAssertFalse(PurchaseManager.productIDs.contains("com.codybontecou.obsidianhealth.pro.yearly"))
        XCTAssertFalse(PurchaseManager.productIDs.contains("com.codybontecou.obsidianhealth.pro.family.monthly"))
        XCTAssertFalse(PurchaseManager.productIDs.contains("com.codybontecou.obsidianhealth.pro.family.yearly"))
    }

    func testFamilyPurchaseUnavailableTracksFamilyProductID() async {
        let manager = makeManager()

        await manager.purchase(.family)
        await analyticsClient.flushAndWait()

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_purchase_started",
            "pricing_purchase_finished"
        ])
        XCTAssertEqual(payloads.first?.properties[.productId], .string(PurchaseManager.familyProductID))
        XCTAssertEqual(payloads.last?.properties[.productId], .string(PurchaseManager.familyProductID))
        XCTAssertEqual(payloads.last?.properties[.purchaseOutcome], .string("failed"))
        XCTAssertEqual(payloads.last?.properties[.errorCategory], .string("store_unavailable"))
    }

    func testFamilyUpgradeRequiresExistingIndividualOrLegacyUnlock() async {
        let manager = makeManager()

        await manager.purchase(.familyUpgrade)
        await analyticsClient.flushAndWait()

        XCTAssertFalse(manager.canBuyFamilyUpgrade)
        XCTAssertEqual(
            manager.purchaseError,
            "Family Upgrade requires an existing Lifetime unlock."
        )

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_purchase_started",
            "pricing_purchase_finished"
        ])
        XCTAssertEqual(payloads.first?.properties[.productId], .string(PurchaseManager.familyUpgradeProductID))
        XCTAssertEqual(payloads.last?.properties[.productId], .string(PurchaseManager.familyUpgradeProductID))
        XCTAssertEqual(payloads.last?.properties[.purchaseOutcome], .string("failed"))
        XCTAssertEqual(payloads.last?.properties[.errorCategory], .string("not_unlocked"))
    }

    func testFamilyUpgradeUnavailableTracksUpgradeProductIDWhenEligible() async {
        let manager = makeManager()
        manager.setUnlockedProductID(PurchaseManager.productID)

        await manager.purchase(.familyUpgrade)
        await analyticsClient.flushAndWait()

        let payloads = await analyticsTransport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_purchase_started",
            "pricing_purchase_finished"
        ])
        XCTAssertEqual(payloads.first?.properties[.productId], .string(PurchaseManager.familyUpgradeProductID))
        XCTAssertEqual(payloads.last?.properties[.productId], .string(PurchaseManager.familyUpgradeProductID))
        XCTAssertEqual(payloads.last?.properties[.purchaseOutcome], .string("failed"))
        XCTAssertEqual(payloads.last?.properties[.errorCategory], .string("store_unavailable"))
    }

    func testFamilyUpgradeEligibilityRequiresIndividualOrLegacyAndNoFamilyUnlock() {
        let individual = makeManager()
        individual.setUnlockedProductID(PurchaseManager.productID)
        XCTAssertTrue(individual.canBuyFamilyUpgrade)

        let legacy = makeManager()
        legacy.setLegacyUser(true)
        XCTAssertTrue(legacy.canBuyFamilyUpgrade)

        let genericUnlocked = makeManager()
        genericUnlocked.setUnlocked(true)
        XCTAssertFalse(
            genericUnlocked.canBuyFamilyUpgrade,
            "A generic unlocked state without an individual purchase or legacy grant must not expose the Family Upgrade."
        )

        let family = makeManager()
        family.setUnlockedProductID(PurchaseManager.familyProductID)
        XCTAssertFalse(family.canBuyFamilyUpgrade)
        XCTAssertTrue(family.isFamilyUnlocked)

        let upgrade = makeManager()
        upgrade.setUnlockedProductID(PurchaseManager.familyUpgradeProductID)
        XCTAssertFalse(upgrade.canBuyFamilyUpgrade)
        XCTAssertTrue(upgrade.isFamilyUnlocked)
    }

    func testPreferredEntitlement_prioritizesFamilyAndLifetimeAccess() {
        XCTAssertEqual(
            PurchaseManager.preferredEntitlementProductID(from: [
                PurchaseManager.productID,
                PurchaseManager.familyUpgradeProductID,
                PurchaseManager.familyProductID,
            ]),
            PurchaseManager.familyProductID
        )
        XCTAssertEqual(
            PurchaseManager.preferredEntitlementProductID(from: [
                PurchaseManager.productID,
                PurchaseManager.familyUpgradeProductID,
            ]),
            PurchaseManager.familyUpgradeProductID
        )
        XCTAssertEqual(
            PurchaseManager.preferredEntitlementProductID(from: [
                PurchaseManager.productID,
            ]),
            PurchaseManager.productID
        )
        XCTAssertNil(PurchaseManager.preferredEntitlementProductID(from: [
            "com.codybontecou.obsidianhealth.pro.monthly",
            "com.codybontecou.obsidianhealth.pro.yearly",
            "com.codybontecou.obsidianhealth.pro.family.monthly",
            "com.codybontecou.obsidianhealth.pro.family.yearly",
        ]))
        XCTAssertNil(PurchaseManager.preferredEntitlementProductID(from: ["com.example.unknown"]))
    }

    func testRestoreNotFoundMessageMentionsFamilyPurchaseSharing() {
        XCTAssertTrue(PurchaseManager.restoreNotFoundMessage.contains("Family Lifetime"))
        XCTAssertTrue(PurchaseManager.restoreNotFoundMessage.contains("Purchase Sharing"))
        XCTAssertTrue(PurchaseManager.restoreNotFoundMessage.contains("cody@isolated.tech"))
    }

    func testUnlockTransition_resetsAccumulatedFreeExports() {
        // Reproduces the launch-time race: refreshStatus() is async, so a
        // legacy/unlocked user can burn quota by exporting before isUnlocked
        // settles. Once status resolves, the accumulated count must reset
        // so a future status loss (network blip, server cold start) doesn't
        // leave them locked out with zero quota.
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsUsed, 2)

        manager.setUnlocked(true)
        XCTAssertEqual(manager.freeExportsUsed, 0, "Quota should reset on false→true transition")
        XCTAssertEqual(manager.freeExportsRemaining, 3)
    }

    func testUnlockTransition_doesNotResetWhenAlreadyUnlocked() {
        let manager = makeManager()
        manager.setUnlocked(true)
        manager.recordExportUse() // no-op, count stays 0
        manager.setUnlocked(true) // idempotent — no transition
        XCTAssertEqual(manager.freeExportsUsed, 0)
    }

    func testUnlockTransition_doesNotResetWhenSetToFalse() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.setUnlocked(false) // false→false, no reset
        XCTAssertEqual(manager.freeExportsUsed, 1, "Setting unlocked=false must not clear quota")
    }

    // MARK: - Keychain Migration

    func testMigration_copiesUserDefaultsToKeychain() {
        // Simulate pre-migration state: value in UserDefaults, not in keychain
        defaults.set(2, forKey: "freeExportsUsed")
        let manager = makeManager()

        XCTAssertEqual(manager.freeExportsUsed, 2, "Should migrate value from UserDefaults")
        XCTAssertTrue(defaults.bool(forKey: "freeExportsUsed_migratedToKeychain"), "Migration flag should be set")
    }

    func testMigration_doesNotRunTwice() {
        defaults.set(2, forKey: "freeExportsUsed")
        let _ = makeManager()

        // Reset keychain but keep migration flag
        keychain.storage = [:]
        let manager2 = makeManager()

        XCTAssertEqual(manager2.freeExportsUsed, 0, "Should not re-migrate since flag is set")
    }
}

private actor PurchaseManagerAnalyticsTransport: PricingAnalyticsTransport {
    private(set) var payloads: [PricingAnalyticsPayload] = []

    func send(_ payload: PricingAnalyticsPayload) async throws {
        payloads.append(payload)
    }

    func payloadsValue() -> [PricingAnalyticsPayload] {
        payloads
    }
}
