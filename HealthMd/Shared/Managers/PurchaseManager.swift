import Foundation
import Combine
import StoreKit

/// Manages the one-time unlock IAP and free-trial export quota.
/// Relies entirely on Apple's StoreKit 2 infrastructure — no server required.
@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // MARK: - Configuration

    /// Product ID registered in App Store Connect.
    static let productID = "com.codybontecou.obsidianhealth.unlock"

    /// Number of free export actions before a purchase is required.
    static let freeExportLimit = 3

    /// First app version shipped as freemium (CFBundleShortVersionString).
    /// Any user whose `AppTransaction.originalAppVersion` is strictly less than
    /// this value downloaded the app when it was a paid upfront purchase and
    /// receives full access automatically — no action required from them.
    static let freemiumIntroVersion = "1.7.0"

    // MARK: - Published State

    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var isLegacyUser: Bool = false
    @Published private(set) var product: Product? = nil
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var purchaseError: String? = nil

    // MARK: - Free Export Quota

    private let freeExportsUsedKey = "freeExportsUsed"

    /// Total number of free export actions the user has consumed.
    var freeExportsUsed: Int {
        UserDefaults.standard.integer(forKey: freeExportsUsedKey)
    }

    /// How many free exports remain before a purchase is required.
    var freeExportsRemaining: Int {
        max(0, Self.freeExportLimit - freeExportsUsed)
    }

    /// True when the user still has free exports left.
    var canExportFree: Bool {
        freeExportsRemaining > 0
    }

    /// True when the user may perform an export (unlocked or within free quota).
    var canExport: Bool {
        isUnlocked || canExportFree
    }

    // MARK: - Init

    private init() {
        Task {
            await refreshStatus()
            await loadProduct()
        }
        startTransactionListener()
    }

    // MARK: - Status Check

    /// Re-evaluates unlock status from StoreKit entitlements and AppTransaction.
    /// Called on init, after purchase, and after restore.
    func refreshStatus() async {
        // 1. Fast path: the user already has an active entitlement for the IAP.
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productID {
                isUnlocked = true
                return
            }
        }

        // 2. Legacy paid-user path: check the version the app was first downloaded at.
        //    `AppTransaction.originalAppVersion` is the CFBundleShortVersionString at
        //    first download, signed by Apple — it cannot be spoofed by the user.
        do {
            let appTxResult = try await AppTransaction.shared
            if case .verified(let appTx) = appTxResult {
                if versionIsLessThan(appTx.originalAppVersion, Self.freemiumIntroVersion) {
                    isLegacyUser = true
                    isUnlocked = true
                    return
                }
            }
        } catch {
            // AppTransaction verification fails on sideloaded dev builds because
            // there is no App Store receipt. In production (App Store installs) the
            // receipt is always present and this branch is never hit.
        }

        isUnlocked = false
    }

    // MARK: - Product Loading

    /// Fetches the IAP product from App Store Connect (or the local .storekit config
    /// during development). Populates `product` so the UI can show the live price.
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            // Silently ignore — the UI falls back to "Unlock Full Access" with no price.
        }
    }

    // MARK: - Purchase

    /// Initiates the StoreKit purchase flow. Sets `isUnlocked = true` on success.
    func purchase() async {
        guard let product else {
            purchaseError = String(
                localized: "Product unavailable. Please try again later.",
                comment: "IAP product unavailable error"
            )
            return
        }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = String(
                        localized: "Purchase verification failed.",
                        comment: "IAP verification error"
                    )
                    return
                }
                await tx.finish()
                isUnlocked = true

            case .pending:
                // Ask to Buy or parental approval pending — the transaction listener
                // will catch the approval and set isUnlocked when it arrives.
                break

            case .userCancelled:
                break

            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    /// Restores any previous purchase by syncing with the App Store.
    func restore() async {
        isRestoring = true
        purchaseError = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Free Export Tracking

    /// Resets the free-export counter to zero (debug/testing only).
    func resetFreeExports() {
        UserDefaults.standard.set(0, forKey: freeExportsUsedKey)
        objectWillChange.send()
    }

    /// Increments the free-export counter by one.
    /// Call once per successful export action (one button press = one use),
    /// regardless of how many files were written.
    /// No-op when the user is already unlocked.
    func recordExportUse() {
        guard !isUnlocked else { return }
        let next = UserDefaults.standard.integer(forKey: freeExportsUsedKey) + 1
        UserDefaults.standard.set(next, forKey: freeExportsUsedKey)
        objectWillChange.send()
    }

    // MARK: - Transaction Listener

    /// Listens for incoming transactions in the background (deferred purchases,
    /// family sharing grants, etc.) and unlocks the app when one arrives.
    private func startTransactionListener() {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result,
                      tx.productID == PurchaseManager.productID else { continue }
                await tx.finish()
                await MainActor.run { self?.isUnlocked = true }
            }
        }
    }

    // MARK: - Version Comparison

    /// Returns `true` if `v1` (e.g. "1.6.3") is strictly less than `v2` (e.g. "1.7.0").
    private func versionIsLessThan(_ v1: String, _ v2: String) -> Bool {
        let a = v1.split(separator: ".").compactMap { Int($0) }
        let b = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return true }
            if x > y { return false }
        }
        return false
    }
}
