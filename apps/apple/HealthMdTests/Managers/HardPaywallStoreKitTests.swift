#if os(iOS)
import XCTest
import StoreKit
import StoreKitTest
@testable import HealthMd

/// Local StoreKit integration; this does not claim Apple sandbox-account QA.
@MainActor
final class HardPaywallStoreKitTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HealthMd.storekit")
        let session = try SKTestSession(contentsOf: catalog)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.clearTransactions()
        addTeardownBlock { session.clearTransactions() }
        return session
    }

    private func manager() -> PurchaseManager {
        let keychain = FakeKeychainStore()
        keychain.writeInt(key: "freeExportsUsed", value: PurchaseManager.freeExportLimit)
        return PurchaseManager(keychain: keychain, defaults: FakeUserDefaults(),
                        productLoader: {
                            let products = try await Product.products(for: $0)
                            // Packaged runners can omit the scheme's catalog. Fail
                            // before purchasing if StoreKit falls back to sandbox.
                            guard products.filter({ $0.subscription != nil }).allSatisfy({
                                $0.subscription?.subscriptionGroupID == "healthmd-pro"
                            }) else { throw URLError(.badServerResponse) }
                            return products
                        })
    }

    func testCatalogUsesSevenDayTrialsAndNativeFamilySharing() async throws {
        let session = try session()
        defer { withExtendedLifetime(session) {} }
        let manager = manager()
        await manager.loadProduct()
        for option in HealthMdPurchaseOption.allCases {
            let product = try XCTUnwrap(manager.product(for: option))
            XCTAssertEqual(product.isFamilyShareable, option.isFamilyPlan)
            XCTAssertEqual(manager.trialEligibleProductIDs.contains(option.productID), option.isSubscription)
            if option.isSubscription {
                let subscription = try XCTUnwrap(product.subscription)
                let offer = try XCTUnwrap(subscription.introductoryOffer)
                XCTAssertEqual(offer.paymentMode, .freeTrial)
                XCTAssertTrue((offer.period.unit == .day && offer.period.value == 7) ||
                              (offer.period.unit == .week && offer.period.value == 1))
            } else {
                XCTAssertNil(product.subscription)
            }
        }
        XCTAssertFalse(manager.canExport)
    }

    func testCancelPendingAndOfflineRestoreDoNotGrantAccess() async throws {
        let session = try session()
        try await session.setSimulatedError(SKTestFailures.AppTransaction.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appTransaction)
        let manager = manager()
        await manager.loadProduct()
        try await session.setSimulatedError(SKTestFailures.Purchase.generic(.userCancelled), forAPI: .purchase)
        await manager.purchase(.weekly)
        XCTAssertFalse(manager.canExport)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        session.askToBuyEnabled = true
        await manager.purchase(.weekly)
        XCTAssertFalse(manager.canExport)
        session.askToBuyEnabled = false
        try await session.setSimulatedError(SKTestFailures.AppStoreSync.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        await manager.restore()
        XCTAssertFalse(manager.canExport)
        XCTAssertNotNil(manager.purchaseError)
    }

    func testTrialRestoreExpiryAndLifetimeFallback() async throws {
        let session = try session()
        // A subscription-only fixture must not inherit StoreKit's simulated
        // original paid-app ownership while checking expiry.
        try await session.setSimulatedError(SKTestFailures.AppTransaction.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appTransaction)
        let manager = manager()
        await manager.loadProduct()
        await manager.purchase(.weekly)
        XCTAssertTrue(manager.canExport, manager.purchaseError ?? "Trial purchase must grant access")
        let restored = self.manager()
        await restored.restore()
        XCTAssertTrue(restored.canExport, restored.purchaseError ?? "Restore must recover active access")
        let transaction = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == HealthMdPurchaseOption.weekly.productID })
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        try session.expireSubscription(productIdentifier: HealthMdPurchaseOption.weekly.productID)
        for _ in 0..<50 {
            await manager.refreshStatus()
            if !manager.canExport { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(manager.canExport, "Expired subscription must relock; legacy=\(manager.isLegacyUser), product=\(manager.unlockedProductID ?? "none")")
        await manager.purchase(.individual)
        XCTAssertTrue(manager.canExport)
        XCTAssertTrue(manager.canBuyFamilyUpgrade)
        await restored.restore()
        XCTAssertTrue(restored.canExport)
        XCTAssertTrue(restored.canBuyFamilyUpgrade)
    }

    /// Avoid StoreKit's simulated paid-app history granting legacy access.
    private func subscriptionSession() async throws -> SKTestSession {
        let session = try session()
        try await session.setSimulatedError(
            SKTestFailures.AppTransaction.generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .appTransaction)
        return session
    }

    private func refresh(_ manager: PurchaseManager, until predicate: () -> Bool) async throws {
        for _ in 0..<50 {
            await manager.refreshStatus()
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("StoreKit entitlement did not reach the expected state")
    }

    func testEverySubscriptionPurchasesAndRestoresWithoutPermanentAccess() async throws {
        let session = try await subscriptionSession()
        for option in HealthMdPurchaseOption.allCases where option.isSubscription {
            session.clearTransactions()
            let manager = manager()
            await manager.loadProduct()
            await manager.purchase(option)
            XCTAssertTrue(manager.canExport, manager.purchaseError ?? option.productID)
            XCTAssertEqual(manager.unlockedProductID, option.productID)
            XCTAssertEqual(manager.isFamilyUnlocked, option.isFamilyPlan)
            XCTAssertFalse(manager.canBuyFamilyUpgrade)
            XCTAssertFalse(manager.canShowPermanentAccessNotice)
            await manager.loadProduct()
            XCTAssertTrue(manager.trialEligibleProductIDs.isEmpty,
                          "A used trial removes eligibility across the subscription group")
            let restored = self.manager()
            await restored.restore()
            XCTAssertTrue(restored.canExport, restored.purchaseError ?? option.productID)
            XCTAssertEqual(restored.unlockedProductID, option.productID)
            XCTAssertFalse(restored.canShowPermanentAccessNotice)
        }
    }

    func testRenewalAndCancellationKeepAccessUntilExpiry() async throws {
        let session = try await subscriptionSession()
        // forceRenewal + expireSubscription can leave currentEntitlements with
        // the renewal's old future expiry. Advance through real test renewals.
        session.timeRate = .oneRenewalEveryTwoSeconds
        let manager = manager()
        await manager.loadProduct()
        await manager.purchase(.weekly)
        XCTAssertTrue(manager.canExport)
        let before = session.allTransactions().count
        for _ in 0..<100 {
            if session.allTransactions().count > before { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(session.allTransactions().count, before, "Renewal must create a new transaction")
        let transaction = try XCTUnwrap(session.allTransactions().max { $0.purchaseDate < $1.purchaseDate })
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        await manager.refreshStatus()
        XCTAssertTrue(manager.canExport, "Canceling renewal must preserve the current paid period")
        XCTAssertFalse(manager.canShowPermanentAccessNotice)
        try await refresh(manager, until: { !manager.canExport })
        let restored = self.manager()
        await restored.restore()
        XCTAssertFalse(restored.canExport, "Expired renewal history must not restore permanent access")
    }

    func testRefundRemovesSubscriptionAndRestoreCannotRegrantIt() async throws {
        let session = try await subscriptionSession()
        let manager = manager()
        await manager.loadProduct()
        await manager.purchase(.familyYearly)
        XCTAssertTrue(manager.isFamilyUnlocked)
        let transaction = try XCTUnwrap(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        try await refresh(manager, until: { !manager.canExport })
        XCTAssertFalse(manager.isFamilyUnlocked)
        let restored = self.manager()
        await restored.restore()
        XCTAssertFalse(restored.canExport)
        XCTAssertFalse(restored.canBuyFamilyUpgrade)
    }

    func testIndividualToFamilySubscriptionUpgradeUsesFamilyEntitlement() async throws {
        let session = try await subscriptionSession()
        defer { withExtendedLifetime(session) {} }
        let manager = manager()
        await manager.loadProduct()
        await manager.purchase(.weekly)
        XCTAssertFalse(manager.isFamilyUnlocked)
        await manager.purchase(.familyWeekly)
        try await refresh(manager, until: { manager.unlockedProductID == HealthMdPurchaseOption.familyWeekly.productID })
        XCTAssertTrue(manager.isFamilyUnlocked)
        XCTAssertFalse(manager.canBuyFamilyUpgrade)
        let restored = self.manager()
        await restored.restore()
        XCTAssertEqual(restored.unlockedProductID, HealthMdPurchaseOption.familyWeekly.productID)
    }

    func testPendingApprovalRequiresApprovedTransaction() async throws {
        let session = try await subscriptionSession()
        session.askToBuyEnabled = true
        let manager = manager()
        await manager.loadProduct()
        await manager.purchase(.yearly)
        XCTAssertFalse(manager.canExport)
        let pending = try XCTUnwrap(session.allTransactions().last)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        try await refresh(manager, until: { manager.canExport })
        XCTAssertEqual(manager.unlockedProductID, HealthMdPurchaseOption.yearly.productID)
        XCTAssertFalse(manager.canShowPermanentAccessNotice)
    }

    func testFamilyLifetimeUpgradeRestoresAndRefundFallsBackToIndividual() async throws {
        let session = try await subscriptionSession()
        let manager = manager()
        await manager.loadProduct()
        await manager.purchase(.individual)
        XCTAssertTrue(manager.canBuyFamilyUpgrade)
        await manager.purchase(.familyUpgrade)
        XCTAssertTrue(manager.isFamilyUnlocked)
        XCTAssertTrue(manager.canShowPermanentAccessNotice)
        let upgraded = self.manager()
        await upgraded.restore()
        XCTAssertTrue(upgraded.isFamilyUnlocked)
        let transaction = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == HealthMdPurchaseOption.familyUpgrade.productID
        })
        try session.refundTransaction(identifier: transaction.identifier)
        try await refresh(upgraded, until: { upgraded.isIndividualUnlocked })
        XCTAssertTrue(upgraded.canExport)
        XCTAssertTrue(upgraded.canBuyFamilyUpgrade)
        XCTAssertTrue(upgraded.canShowPermanentAccessNotice)
    }


    #if DEBUG
    func testSandboxQAUsesStoreKitWithoutErasingLegacyAccess() async throws {
        let session = try await subscriptionSession()
        let keychain = FakeKeychainStore()
        keychain.writeInt(key: "serverVerifiedLegacy", value: 1)
        keychain.writeInt(key: "freeExportsUsed", value: PurchaseManager.freeExportLimit)
        let manager = PurchaseManager(keychain: keychain, defaults: FakeUserDefaults(),
                                      productLoader: { try await Product.products(for: $0) })
        await manager.refreshStatus()
        XCTAssertTrue(manager.canExport)
        XCTAssertTrue(manager.isLegacyUser)

        manager.sandboxPurchaseQAEnabled = true
        await manager.refreshStatus()
        XCTAssertFalse(manager.canExport)
        XCTAssertFalse(manager.isLegacyUser)
        await manager.loadProduct()
        await manager.purchase(.weekly)
        XCTAssertTrue(manager.canExport, manager.purchaseError ?? "Sandbox trial must grant access")
        XCTAssertEqual(manager.unlockedProductID, HealthMdPurchaseOption.weekly.productID)
        XCTAssertFalse(manager.canShowPermanentAccessNotice)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        try session.expireSubscription(productIdentifier: HealthMdPurchaseOption.weekly.productID)
        try await refresh(manager, until: { !manager.canExport })
        await manager.restore()
        XCTAssertFalse(manager.canExport, "Expired sandbox access must not fall back to legacy")
        XCTAssertEqual(keychain.readInt(key: "serverVerifiedLegacy"), 1)

        manager.sandboxPurchaseQAEnabled = false
        await manager.refreshStatus()
        XCTAssertTrue(manager.canExport, "Normal launch must retain the existing legacy grant")
        XCTAssertTrue(manager.isLegacyUser)
    }
    #endif

}
#endif
