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
        PurchaseManager(keychain: FakeKeychainStore(), defaults: FakeUserDefaults(),
                        productLoader: { try await Product.products(for: $0) })
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
}
#endif
