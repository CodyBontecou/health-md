import Foundation
import Combine
import StoreKit
import Security

nonisolated enum HealthMdPurchaseOption: String, CaseIterable, Identifiable, Sendable {
    case monthly
    case yearly
    case individual
    case familyMonthly
    case familyYearly
    case family
    case familyUpgrade

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .monthly:
            return "com.codybontecou.obsidianhealth.pro.monthly"
        case .yearly:
            return "com.codybontecou.obsidianhealth.pro.yearly"
        case .individual:
            return "com.codybontecou.obsidianhealth.unlock"
        case .familyMonthly:
            return "com.codybontecou.obsidianhealth.pro.family.monthly"
        case .familyYearly:
            return "com.codybontecou.obsidianhealth.pro.family.yearly"
        case .family:
            return "com.codybontecou.obsidianhealth.unlock.family"
        case .familyUpgrade:
            return "com.codybontecou.obsidianhealth.unlock.family.upgrade"
        }
    }

    var analyticsProductID: PricingAnalyticsProductID {
        switch self {
        case .monthly:
            return .monthlySubscription
        case .yearly:
            return .yearlySubscription
        case .individual:
            return .lifetimeUnlock
        case .familyMonthly:
            return .familyMonthlySubscription
        case .familyYearly:
            return .familyYearlySubscription
        case .family:
            return .familyLifetimeUnlock
        case .familyUpgrade:
            return .familyLifetimeUpgrade
        }
    }

    var isSubscription: Bool {
        switch self {
        case .monthly, .yearly, .familyMonthly, .familyYearly:
            return true
        case .individual, .family, .familyUpgrade:
            return false
        }
    }

    var isFamilyPlan: Bool {
        switch self {
        case .familyMonthly, .familyYearly, .family, .familyUpgrade:
            return true
        case .monthly, .yearly, .individual:
            return false
        }
    }

    var displayTitle: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .individual: return "Lifetime"
        case .familyMonthly: return "Family Monthly"
        case .familyYearly: return "Family Yearly"
        case .family: return "Family Lifetime"
        case .familyUpgrade: return "Upgrade to Family Lifetime"
        }
    }

    var displaySubtitle: String {
        switch self {
        case .monthly: return "Flexible access for ongoing exports"
        case .yearly: return "Best value for scheduled exports"
        case .individual: return "Pay once on your Apple ID"
        case .familyMonthly: return "Flexible access for your Apple Family"
        case .familyYearly: return "Best value for your Apple Family"
        case .family: return "Pay once and share with up to 5 family members"
        case .familyUpgrade: return "Upgrade pricing for existing Lifetime owners"
        }
    }

    var badge: String? {
        switch self {
        case .yearly, .familyYearly:
            return "Best value"
        case .family, .familyUpgrade:
            return "Family"
        case .monthly, .familyMonthly, .individual:
            return nil
        }
    }

    var iconName: String {
        isFamilyPlan ? "person.3.fill" : "person.fill"
    }
}

/// Manages StoreKit paid plans and the free-trial export quota.
/// Relies on Apple's StoreKit 2 infrastructure for paid entitlements.
@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // MARK: - Configuration

    /// Product IDs registered in App Store Connect.
    static let monthlyProductID = HealthMdPurchaseOption.monthly.productID
    static let yearlyProductID = HealthMdPurchaseOption.yearly.productID
    static let productID = HealthMdPurchaseOption.individual.productID
    static let familyMonthlyProductID = HealthMdPurchaseOption.familyMonthly.productID
    static let familyYearlyProductID = HealthMdPurchaseOption.familyYearly.productID
    static let familyProductID = HealthMdPurchaseOption.family.productID
    static let familyUpgradeProductID = HealthMdPurchaseOption.familyUpgrade.productID
    static let productIDs = HealthMdPurchaseOption.allCases.map(\.productID)

    /// Number of free export actions before a purchase is required.
    static let freeExportLimit = 3

    /// Single grandfather cutoff: anyone with `originalPurchaseDate` strictly
    /// before this is granted free access. Covers all earlier cohorts in one
    /// rule — pre-freemium paid users (v1.0–v1.6.x), v1.7.x freemium users,
    /// and the v1.8.0/v1.8.1 build-counter-reset leak cohort. Aligned with the
    /// date the auto-unlock regression fix shipped, so installs after that
    /// land past this date and go through the normal paywall.
    static let grandfatherCutoffDate: Date = makeUTCDate(year: 2026, month: 4, day: 26)

    private static func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// Base URL for the Cloudflare Worker that verifies legacy purchases.
    static let workerBaseURL = "https://healthmd-receipt-verifier.costream.workers.dev"

    /// Keychain service identifier.
    private static let keychainService = "com.codybontecou.obsidianhealth"

    // MARK: - Published State

    @Published private(set) var isUnlocked: Bool = false {
        didSet {
            // When status resolves to unlocked (purchase, grandfather, or
            // restore), clear any free-export count that accumulated during
            // the async refreshStatus() race on launch. Without this, a user
            // who exported before refreshStatus() settled could permanently
            // burn quota they were never supposed to spend.
            if isUnlocked && !oldValue {
                keychain.writeInt(key: freeExportsUsedKey, value: 0)
            }
        }
    }
    @Published private(set) var isLegacyUser: Bool = false
    @Published private(set) var product: Product? = nil
    @Published private(set) var familyProduct: Product? = nil
    @Published private(set) var familyUpgradeProduct: Product? = nil
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var productLoadError: String? = nil
    @Published private(set) var purchasingOption: HealthMdPurchaseOption? = nil
    @Published private(set) var unlockedProductID: String? = nil
    @Published private(set) var unlockedOwnershipDescription: String? = nil
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var purchaseError: String? = nil

    // MARK: - Free Export Quota
    //
    // Stored in the Keychain (not UserDefaults) so the count survives app
    // deletion and reinstallation, closing the "delete to get 3 more" exploit.

    private let freeExportsUsedKey             = "freeExportsUsed"
    private let serverVerifiedLegacyKey        = "serverVerifiedLegacy"
    private let serverVerificationAttemptedKey = "serverVerificationAttempted"
    private let appsFlyerLoggedTransactionsKey = "appsflyer.loggedTransactionIDs.v1"

    /// Total number of free export actions the user has consumed.
    var freeExportsUsed: Int {
        keychain.readInt(key: freeExportsUsedKey)
    }

    /// How many free exports remain before a purchase is required.
    var freeExportsRemaining: Int {
        if TestMode.isUITesting {
            return max(0, Self.freeExportLimit - TestMode.freeExportsUsed)
        }
        return max(0, Self.freeExportLimit - freeExportsUsed)
    }

    /// True when the user still has free exports left.
    var canExportFree: Bool {
        freeExportsRemaining > 0
    }

    /// True when the user may perform an export (unlocked or within free quota).
    var canExport: Bool {
        if TestMode.isUITesting {
            return TestMode.purchaseUnlocked || TestMode.freeExportsUsed < Self.freeExportLimit
        }
        return isUnlocked || canExportFree
    }

    // MARK: - Injected Dependencies

    private let keychain: KeychainStoring
    private let defaults: UserDefaultsStoring
    private let analytics: PricingAnalyticsClient
    private let productLoader: @MainActor ([String]) async throws -> [Product]
    private var productLoadTask: Task<Void, Never>? = nil

    // MARK: - Init

    private init() {
        self.keychain = SystemKeychainStore()
        self.defaults = SystemUserDefaults()
        self.analytics = .shared
        self.productLoader = { productIDs in
            try await Product.products(for: productIDs)
        }
        migrateUserDefaultsToKeychain()

        // In UI test / IAP review capture mode, skip all StoreKit interactions.
        // Test state is configured via configureTestMode() / configureIAPReviewMode().
        guard Self.usesLiveStoreKit else { return }

        Task {
            await loadProduct()
        }

        Task {
            await refreshStatus()
            // Silently attempt server verification once in the background for any
            // user who isn't unlocked yet and hasn't been checked before. This
            // catches legacy paid users whose AppTransaction check failed without
            // requiring them to discover and tap "Restore Purchase" themselves.
            await attemptSilentServerVerification()
        }
        startTransactionListener()
    }

    /// Testable initializer — skips async StoreKit setup and transaction listener.
    init(
        keychain: KeychainStoring,
        defaults: UserDefaultsStoring,
        analytics: PricingAnalyticsClient = .shared,
        productLoader: @MainActor @escaping ([String]) async throws -> [Product] = { _ in [] }
    ) {
        self.keychain = keychain
        self.defaults = defaults
        self.analytics = analytics
        self.productLoader = productLoader
        migrateUserDefaultsToKeychain()
    }

    private static var isIAPReviewCapture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-IAPReviewCapture")
        #else
        false
        #endif
    }

    private static var usesStaticPurchasePrices: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-StaticPurchasePrices"), idx + 1 < args.count else {
            return false
        }
        return args[idx + 1] == "1"
        #else
        false
        #endif
    }

    private static var usesLiveStoreKit: Bool {
        !TestMode.isUITesting && !isIAPReviewCapture && !usesStaticPurchasePrices
    }

    /// Test-only: directly set unlock state without StoreKit.
    func setUnlocked(_ value: Bool) {
        isUnlocked = value
    }

    /// Test-only: directly set the active entitlement product without StoreKit.
    func setUnlockedProductID(_ productID: String?) {
        unlockedProductID = productID
        unlockedOwnershipDescription = nil
        isUnlocked = productID != nil
    }

    /// Test-only: directly set legacy state without StoreKit.
    func setLegacyUser(_ value: Bool) {
        isLegacyUser = value
        if value {
            isUnlocked = true
        }
    }

    /// Test-only: set free exports used count without real keychain.
    func setFreeExportsUsed(_ count: Int) {
        keychain.writeInt(key: freeExportsUsedKey, value: count)
    }

    var analyticsQuotaState: PricingAnalyticsQuotaState {
        let used = TestMode.isUITesting ? TestMode.freeExportsUsed : freeExportsUsed
        return PricingAnalyticsQuotaState(
            freeExportsUsed: used,
            freeExportsRemaining: freeExportsRemaining
        )
    }

    var isIndividualUnlocked: Bool {
        unlockedProductID == Self.productID
    }

    var isSubscriptionUnlocked: Bool {
        guard let unlockedProductID,
              let option = Self.purchaseOption(for: unlockedProductID) else { return false }
        return option.isSubscription
    }

    var isFamilyUnlocked: Bool {
        guard let unlockedProductID else { return false }
        return Self.isFamilyEntitlement(productID: unlockedProductID)
    }

    /// App Store Connect cannot make one non-consumable depend on another, so
    /// Health.md gates the fixed-price Family Upgrade in-app. Family members who
    /// receive the shared upgrade entitlement are still treated as Family-unlocked
    /// even if they do not have the original individual purchase.
    var canBuyFamilyUpgrade: Bool {
        (isIndividualUnlocked || isLegacyUser) && !isFamilyUnlocked
    }

    func product(for option: HealthMdPurchaseOption) -> Product? {
        productsByID[option.productID]
    }

    func hasLoggedAppsFlyerPurchaseAttribution(transactionID: String) -> Bool {
        let transactionID = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transactionID.isEmpty else { return false }
        return appsFlyerLoggedTransactionIDs().contains(transactionID)
    }

    @discardableResult
    func markAppsFlyerPurchaseAttributionLogged(transactionID: String) -> Bool {
        let transactionID = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transactionID.isEmpty else { return false }

        var transactionIDs = appsFlyerLoggedTransactionIDs()
        guard !transactionIDs.contains(transactionID) else { return false }

        transactionIDs.append(transactionID)
        if transactionIDs.count > 100 {
            transactionIDs = Array(transactionIDs.suffix(100))
        }
        defaults.set(transactionIDs.joined(separator: "\n"), forKey: appsFlyerLoggedTransactionsKey)
        return true
    }

    private func appsFlyerLoggedTransactionIDs() -> [String] {
        defaults.string(forKey: appsFlyerLoggedTransactionsKey)?
            .split(separator: "\n")
            .map(String.init) ?? []
    }

    private func logAppsFlyerPurchaseIfNeeded(product: Product, transaction: Transaction) {
        #if os(iOS)
        guard transaction.ownershipType == .purchased else { return }
        let transactionID = String(transaction.id)
        guard !hasLoggedAppsFlyerPurchaseAttribution(transactionID: transactionID) else { return }

        let didQueueEvent = AppsFlyerManager.shared.logPurchase(
            revenue: product.price,
            currency: product.priceFormatStyle.currencyCode,
            orderID: transactionID,
            productID: product.id
        )
        if didQueueEvent {
            markAppsFlyerPurchaseAttributionLogged(transactionID: transactionID)
        }
        #else
        _ = product
        _ = transaction
        #endif
    }

    private static func purchaseOption(for productID: String) -> HealthMdPurchaseOption? {
        HealthMdPurchaseOption.allCases.first { $0.productID == productID }
    }

    private static func isFamilyEntitlement(productID: String) -> Bool {
        purchaseOption(for: productID)?.isFamilyPlan == true
    }

    private static let entitlementPriority: [String] = [
        familyProductID,
        familyUpgradeProductID,
        familyYearlyProductID,
        familyMonthlyProductID,
        productID,
        yearlyProductID,
        monthlyProductID,
    ]

    static func preferredEntitlementProductID<S: Sequence>(from productIDs: S) -> String? where S.Element == String {
        let availableIDs = Set(productIDs)
        return entitlementPriority.first { availableIDs.contains($0) }
    }

    private struct StoreKitEntitlementCandidate {
        let productID: String
        let ownershipDescription: String
        let source: String
    }

    private static func preferredEntitlement(from candidates: [StoreKitEntitlementCandidate]) -> StoreKitEntitlementCandidate? {
        guard let productID = preferredEntitlementProductID(from: candidates.map(\.productID)) else {
            return nil
        }
        return candidates.first { $0.productID == productID }
    }

    private func recordUnlockedProductID(_ productID: String, ownershipDescription: String? = nil) {
        if Self.isFamilyEntitlement(productID: productID) || !isFamilyUnlocked {
            unlockedProductID = productID
            unlockedOwnershipDescription = ownershipDescription
        }
    }

    private func recordUnlockedEntitlement(_ entitlement: StoreKitEntitlementCandidate) {
        recordUnlockedProductID(
            entitlement.productID,
            ownershipDescription: "\(entitlement.source): \(entitlement.ownershipDescription)"
        )
        isUnlocked = true
    }

    private func entitlementCandidate(from transaction: Transaction, source: String) -> StoreKitEntitlementCandidate? {
        guard let option = Self.purchaseOption(for: transaction.productID),
              transaction.revocationDate == nil else {
            return nil
        }

        // Historical transaction scans are safe for non-consumable lifetime unlocks,
        // but subscriptions must still be active. `currentEntitlements` already
        // filters expired renewals; this extra guard keeps the restore fallback from
        // reviving an expired monthly/yearly subscription from history.
        if option.isSubscription,
           let expirationDate = transaction.expirationDate,
           expirationDate <= Date() {
            return nil
        }

        return StoreKitEntitlementCandidate(
            productID: transaction.productID,
            ownershipDescription: String(describing: transaction.ownershipType),
            source: source
        )
    }

    private func currentStoreKitEntitlement() async -> StoreKitEntitlementCandidate? {
        var candidates: [StoreKitEntitlementCandidate] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let candidate = entitlementCandidate(from: transaction, source: "currentEntitlements") else {
                continue
            }
            candidates.append(candidate)
        }

        return Self.preferredEntitlement(from: candidates)
    }

    private func historicalStoreKitEntitlement() async -> StoreKitEntitlementCandidate? {
        var candidates: [StoreKitEntitlementCandidate] = []

        for await result in Transaction.all {
            guard case .verified(let transaction) = result,
                  let candidate = entitlementCandidate(from: transaction, source: "transactionHistory") else {
                continue
            }
            candidates.append(candidate)
        }

        return Self.preferredEntitlement(from: candidates)
    }

    // MARK: - Status Check

    /// Re-evaluates unlock status from StoreKit entitlements and AppTransaction.
    /// Called on init, after purchase, and after restore.
    func refreshStatus(includeHistoricalFallback: Bool = false) async {
        #if DEBUG
        // Debug override: set "debugOriginalAppVersion" in UserDefaults to simulate
        // any install version without needing a real App Store receipt.
        // This runs first so it works on dev builds deployed via Xcode (which have
        // no receipt, causing AppTransaction to throw).
        //
        // Hardcode in init() temporarily:
        //   UserDefaults.standard.set("1.6.0", forKey: "debugOriginalAppVersion")
        //   UserDefaults.standard.set(1577836800.0, forKey: "debugOriginalPurchaseDate")  // optional, ms since 1970
        // Remove by setting to nil or removing the key.
        if UserDefaults.standard.string(forKey: "debugOriginalAppVersion") != nil {
            // The version string itself is no longer used for the decision —
            // grandfathering is purely date-based. Set `debugOriginalPurchaseDate`
            // (seconds since 1970) to test specific dates; defaults to a
            // pre-cutoff date so the legacy branch fires.
            let debugDate: Date
            if let interval = UserDefaults.standard.object(forKey: "debugOriginalPurchaseDate") as? TimeInterval {
                debugDate = Date(timeIntervalSince1970: interval)
            } else {
                debugDate = Self.grandfatherCutoffDate.addingTimeInterval(-86_400 * 30)
            }
            if Self.isLegacyUnlock(originalPurchaseDate: debugDate) {
                isLegacyUser = true
                isUnlocked = true
            } else {
                isLegacyUser = false
                isUnlocked = false
            }
            return
        }

        // Debug override: set "debugSkipToServerVerification" = true to bypass steps
        // 1–3 and jump straight to the server receipt check. Use this to test the
        // Cloudflare Worker integration end-to-end on a device that isn't a legacy user.
        //
        // Hardcode in init() temporarily:
        //   UserDefaults.standard.set(true, forKey: "debugSkipToServerVerification")
        if UserDefaults.standard.bool(forKey: "debugSkipToServerVerification") {
            if await verifyLegacyWithServer() {
                keychain.writeInt(key: serverVerifiedLegacyKey, value: 1)
                isLegacyUser = true
                isUnlocked = true
            } else {
                isUnlocked = false
            }
            return
        }
        #endif

        unlockedProductID = nil
        unlockedOwnershipDescription = nil
        isLegacyUser = false

        // 1. Fast path: the user already has an active StoreKit entitlement.
        // Prefer full family over family-upgrade, and either family entitlement
        // over individual. Family-shared non-consumables are represented as
        // verified transactions with ownershipType == .familyShared, so they
        // follow the same path as direct purchases.
        if let entitlement = await currentStoreKitEntitlement() {
            recordUnlockedEntitlement(entitlement)
            return
        }

        // 1b. Restore-only fallback: after an explicit AppStore.sync(), also scan
        // StoreKit transaction history for our non-consumables. This helps with
        // occasional StoreKit cache misses where a valid non-consumable is present
        // in history but has not appeared in currentEntitlements yet. Revoked or
        // refunded transactions are ignored above.
        if includeHistoricalFallback,
           let entitlement = await historicalStoreKitEntitlement() {
            recordUnlockedEntitlement(entitlement)
            return
        }

        // 2. Server-verified legacy path: a previous call to verifyLegacyWithServer()
        //    confirmed this device originally purchased before v1.7.0 and cached the
        //    result in the Keychain. This survives app reinstalls.
        if keychain.readInt(key: serverVerifiedLegacyKey) > 0 {
            isLegacyUser = true
            isUnlocked = true
            return
        }

        // 3. Local legacy paid-user path: check the install date the app was first
        //    downloaded at via AppTransaction. Signed by Apple so it cannot be
        //    spoofed, but does not survive a delete-and-reinstall after v1.7.0.
        //    Step 2 above is the durable version of this check once the server
        //    has verified them at least once.
        do {
            let appTxResult = try await AppTransaction.shared
            switch appTxResult {
            case .verified(let appTx):
                if Self.isLegacyUnlock(originalPurchaseDate: appTx.originalPurchaseDate) {
                    isLegacyUser = true
                    isUnlocked = true
                    return
                }
            case .unverified(let appTx, _):
                // Local JWS verification failed (cert cache, clock skew, etc.) but the
                // data is still Apple-signed. Trust it for legacy detection — an attacker
                // who can forge AppTransaction responses already has device-level control
                // and could bypass any client-side check.
                if Self.isLegacyUnlock(originalPurchaseDate: appTx.originalPurchaseDate) {
                    isLegacyUser = true
                    isUnlocked = true
                    return
                }
            }
        } catch {
            // AppTransaction threw entirely — no data available. This happens on
            // sideloaded dev builds (no receipt) or after reinstall when StoreKit
            // hasn't synced yet. Fall through to server verification.
        }

        // 4. Automatic server verification — runs silently in the background for any
        //    user who reaches this point without being unlocked. This catches users who
        //    deleted and reinstalled after v1.7.0, breaking the local AppTransaction
        //    check (step 3). On success the result is cached in Keychain so the server
        //    is only ever called once per device regardless of future reinstalls.
        if await verifyLegacyWithServer() {
            keychain.writeInt(key: serverVerifiedLegacyKey, value: 1)
            isLegacyUser = true
            isUnlocked = true
            return
        }

        isUnlocked = false
    }

    // MARK: - Product Loading

    /// Reloads StoreKit products when a paywall appears or when the user asks to retry.
    /// Skips UI-test and marketing-capture modes, where prices are static and StoreKit
    /// should remain untouched.
    func loadProductsIfNeeded(force: Bool = false) async {
        guard Self.usesLiveStoreKit else { return }
        guard force || productsByID.isEmpty || productLoadError != nil else { return }
        await loadProduct()
    }

    /// Fetches the IAP product from App Store Connect (or the local .storekit config
    /// during development). Populates `product` so the UI can show the live price.
    func loadProduct() async {
        if let productLoadTask {
            await productLoadTask.value
            return
        }

        isLoadingProducts = true
        productLoadError = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isLoadingProducts = false
                self.productLoadTask = nil
            }

            do {
                let products = try await self.productLoader(Self.productIDs)
                let loadedProductsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
                guard !loadedProductsByID.isEmpty else {
                    if self.productsByID.isEmpty {
                        self.productLoadError = Self.productUnavailableMessage
                    }
                    return
                }

                self.productsByID = loadedProductsByID
                self.product = loadedProductsByID[Self.productID]
                self.familyProduct = loadedProductsByID[Self.familyProductID]
                self.familyUpgradeProduct = loadedProductsByID[Self.familyUpgradeProductID]
                self.productLoadError = nil
            } catch {
                if self.productsByID.isEmpty {
                    self.productLoadError = Self.productLoadFailureMessage
                }
            }
        }

        productLoadTask = task
        await task.value
    }

    private static var productLoadFailureMessage: String {
        String(
            localized: "Unable to load purchase options. Check your connection and try again.",
            comment: "Error shown when StoreKit products fail to load"
        )
    }

    private static var productUnavailableMessage: String {
        String(
            localized: "Purchase options are unavailable. Please try again later.",
            comment: "Error shown when StoreKit returns no purchase products"
        )
    }

    // MARK: - Purchase

    /// Initiates the StoreKit purchase flow. Sets `isUnlocked = true` on success.
    func purchase(_ option: HealthMdPurchaseOption = .individual) async {
        analytics.trackPurchaseStarted(
            productId: option.analyticsProductID,
            quotaState: analyticsQuotaState
        )

        if option == .familyUpgrade {
            guard canBuyFamilyUpgrade else {
                purchaseError = String(
                    localized: "Family Upgrade requires an existing Lifetime unlock.",
                    comment: "Error shown when the family-upgrade IAP is attempted without an eligible base purchase"
                )
                analytics.trackPurchaseFinished(
                    outcome: .failed,
                    errorCategory: .notUnlocked,
                    productId: option.analyticsProductID,
                    quotaState: analyticsQuotaState
                )
                return
            }
        }

        var selectedProduct = product(for: option)
        if selectedProduct == nil && Self.usesLiveStoreKit {
            await loadProduct()
            selectedProduct = product(for: option)
        }

        guard let selectedProduct else {
            purchaseError = String(
                localized: "Product unavailable. Please try again later.",
                comment: "IAP product unavailable error"
            )
            analytics.trackPurchaseFinished(
                outcome: .failed,
                errorCategory: .storeUnavailable,
                productId: option.analyticsProductID,
                quotaState: analyticsQuotaState
            )
            return
        }

        isPurchasing = true
        purchasingOption = option
        purchaseError = nil
        defer {
            isPurchasing = false
            purchasingOption = nil
        }

        do {
            let result = try await selectedProduct.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = String(
                        localized: "Purchase verification failed.",
                        comment: "IAP verification error"
                    )
                    analytics.trackPurchaseFinished(
                        outcome: .failed,
                        errorCategory: .verificationFailed,
                        productId: option.analyticsProductID,
                        quotaState: analyticsQuotaState
                    )
                    return
                }
                await tx.finish()
                recordUnlockedProductID(
                    tx.productID,
                    ownershipDescription: "purchase: \(String(describing: tx.ownershipType))"
                )
                isUnlocked = true
                logAppsFlyerPurchaseIfNeeded(product: selectedProduct, transaction: tx)
                analytics.trackPurchaseFinished(
                    outcome: .succeeded,
                    productId: option.analyticsProductID,
                    quotaState: analyticsQuotaState
                )

            case .pending:
                // Ask to Buy or parental approval pending — the transaction listener
                // will catch the approval and set isUnlocked when it arrives.
                analytics.trackPurchaseFinished(
                    outcome: .pending,
                    productId: option.analyticsProductID,
                    quotaState: analyticsQuotaState
                )
                break

            case .userCancelled:
                analytics.trackPurchaseFinished(
                    outcome: .cancelled,
                    errorCategory: .userCancelled,
                    productId: option.analyticsProductID,
                    quotaState: analyticsQuotaState
                )
                break

            @unknown default:
                analytics.trackPurchaseFinished(
                    outcome: .failed,
                    errorCategory: .unknown,
                    productId: option.analyticsProductID,
                    quotaState: analyticsQuotaState
                )
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            analytics.trackPurchaseFinished(
                outcome: .failed,
                errorCategory: analyticsErrorCategory(for: error),
                productId: option.analyticsProductID,
                quotaState: analyticsQuotaState
            )
        }
    }

    // MARK: - Restore

    static var restoreNotFoundMessage: String {
        String(
            localized: "No purchase found for this Apple ID.\n\nFor Family Lifetime, make sure the purchaser has Apple Family Purchase Sharing turned on, this device is signed into a member of that Apple Family, and Health.md is not hidden from purchase history. Then reopen Health.md and tap Restore Purchase again.\n\nIf you bought Health.md before v1.7.0, your access is restored automatically — try force-quitting and reopening the app. If the issue persists, contact us at cody@isolated.tech and we'll sort it out.",
            comment: "Restore purchase not found message"
        )
    }

    /// Restores access for both IAP purchasers and legacy paid-app users.
    ///
    /// Resolution order:
    ///   1. `AppStore.sync()` — re-surfaces IAP entitlements and refreshes the receipt.
    ///   2. `refreshStatus(includeHistoricalFallback:)` — catches IAP entitlements,
    ///      StoreKit history fallback, cached server result, and local AppTransaction check.
    ///   3. `verifyLegacyWithServer()` — sends the receipt to the Cloudflare Worker for
    ///      server-side verification. This is the reliable path for users who deleted and
    ///      reinstalled after v1.7.0, breaking the local AppTransaction check. On success
    ///      the result is cached in the Keychain so the server is only ever called once.
    func restore() async {
        analytics.trackRestoreStarted(quotaState: analyticsQuotaState)

        isRestoring = true
        purchaseError = nil
        defer { isRestoring = false }

        let syncError: Error?
        do {
            // Syncing also refreshes the on-device App Store receipt, which makes
            // the subsequent AppTransaction and server verification more reliable.
            try await AppStore.sync()
            syncError = nil
        } catch {
            // Even if the explicit sync fails, still re-read local StoreKit state.
            // Some devices already have cached family-shared entitlements, and
            // returning early would hide that valid access behind a sync error.
            syncError = error
        }

        // refreshStatus() now includes automatic server verification as its final
        // step, so a single call here covers all unlock paths including the server.
        // The restore path also enables the StoreKit history fallback for rare cases
        // where a valid non-consumable has synced to history but not currentEntitlements.
        await refreshStatus(includeHistoricalFallback: true)
        if isUnlocked {
            analytics.trackRestoreFinished(
                outcome: .succeeded,
                productId: unlockedProductID.flatMap { Self.purchaseOption(for: $0)?.analyticsProductID },
                quotaState: analyticsQuotaState
            )
            return
        }

        if let syncError {
            purchaseError = syncError.localizedDescription
            analytics.trackRestoreFinished(
                outcome: .failed,
                errorCategory: analyticsErrorCategory(for: syncError),
                quotaState: analyticsQuotaState
            )
            return
        }

        purchaseError = Self.restoreNotFoundMessage
        analytics.trackRestoreFinished(
            outcome: .failed,
            errorCategory: .verificationFailed,
            quotaState: analyticsQuotaState
        )
    }

    // MARK: - Silent Server Verification

    /// Maximum number of silent server verification attempts across app launches.
    /// Capped to avoid a network request on every launch indefinitely, while
    /// still allowing retries if the first attempt fails due to a transient
    /// network error or a server-side bug that is later fixed.
    private static let maxServerVerificationAttempts = 3

    /// Called on launch. If the user isn't already unlocked and the server
    /// hasn't been consulted too many times, sends the receipt to the worker
    /// silently. No UI, no spinner — it just unlocks in the background if Apple
    /// confirms they're a legacy paid user.
    private func attemptSilentServerVerification() async {
        guard !isUnlocked else { return }

        #if DEBUG
        // Honor the refreshStatus() debug override: when forcing a specific
        // install state for testing, don't let the silent worker check
        // re-unlock the user from a real prior purchase on this Apple ID.
        if UserDefaults.standard.string(forKey: "debugOriginalAppVersion") != nil {
            return
        }
        #endif

        let attempts = keychain.readInt(key: serverVerificationAttemptedKey)
        guard attempts < Self.maxServerVerificationAttempts else { return }

        let isLegacy = await verifyLegacyWithServer()
        if isLegacy {
            keychain.writeInt(key: serverVerifiedLegacyKey, value: 1)
            isLegacyUser = true
            isUnlocked = true
        }

        // Increment attempt counter after the call completes so transient
        // network failures still leave room for retries on the next launch.
        keychain.writeInt(key: serverVerificationAttemptedKey, value: attempts + 1)
    }

    // MARK: - Server Verification

    /// Attempts server-side legacy verification. Tries two approaches:
    /// 1. AppTransaction JWS token (works on TestFlight + App Store)
    /// 2. Legacy receipt file (works on App Store installs only)
    /// Returns `false` on any failure so the caller falls back gracefully.
    private func verifyLegacyWithServer() async -> Bool {
        // Approach 1: Send AppTransaction JWS to the worker.
        // Available on both TestFlight and App Store. The worker decodes the
        // signed payload and checks originalAppVersion without needing Apple's
        // deprecated verifyReceipt endpoint.
        if let jws = try? await AppTransaction.shared.jwsRepresentation {
            if await sendToWorker(path: "/verify-legacy-jws", body: ["jws": jws]) {
                return true
            }
        }

        // Approach 2: Legacy receipt file → Apple's verifyReceipt endpoint.
        // The receipt file exists on App Store installs but not TestFlight/dev.
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path),
           let receiptData = try? Data(contentsOf: receiptURL) {
            if await sendToWorker(path: "/verify-legacy", body: ["receipt": receiptData.base64EncodedString()]) {
                return true
            }
        }

        return false
    }

    /// Posts a JSON body to the worker and returns true if the response contains `isLegacy: true`.
    private func sendToWorker(path: String, body: [String: String]) async -> Bool {
        guard let url = URL(string: "\(Self.workerBaseURL)\(path)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["isLegacy"] as? Bool ?? false
        } catch {
            return false
        }
    }

    // MARK: - Free Export Tracking

    /// Resets the free-export counter to zero (debug/testing only).
    func resetFreeExports() {
        keychain.writeInt(key: freeExportsUsedKey, value: 0)
        objectWillChange.send()
    }

    /// Increments the free-export counter by one.
    /// Call once per successful export action (one button press = one use),
    /// regardless of how many files were written.
    /// No-op when the user is already unlocked.
    func recordExportUse() {
        guard !isUnlocked else { return }
        keychain.writeInt(key: freeExportsUsedKey, value: freeExportsUsed + 1)
        objectWillChange.send()
        analytics.trackFreeExportUsed(quotaState: analyticsQuotaState)
    }

    // MARK: - Transaction Listener

    /// Listens for incoming transactions in the background (deferred purchases,
    /// family sharing grants, revocations, etc.) and reconciles access when they arrive.
    private func startTransactionListener() {
        Task(priority: .background) { [weak self] in
            guard let self else { return }

            for await result in Transaction.updates {
                guard case .verified(let tx) = result,
                      Self.purchaseOption(for: tx.productID) != nil else { continue }
                await tx.finish()

                if let product = self.productsByID[tx.productID] {
                    self.logAppsFlyerPurchaseIfNeeded(product: product, transaction: tx)
                }

                if let entitlement = self.entitlementCandidate(from: tx, source: "transactionUpdates") {
                    self.recordUnlockedEntitlement(entitlement)
                } else {
                    await self.refreshStatus()
                }
            }
        }
    }

    // MARK: - UserDefaults → Keychain Migration

    /// One-time migration: copies any existing `freeExportsUsed` value from
    /// UserDefaults (pre-1.7.2) into the Keychain, then marks the migration done.
    /// This preserves the count for users who update rather than reinstall.
    private func migrateUserDefaultsToKeychain() {
        let migrationFlag = "freeExportsUsed_migratedToKeychain"
        guard !defaults.bool(forKey: migrationFlag) else { return }
        let existing = defaults.integer(forKey: freeExportsUsedKey)
        if existing > 0 {
            keychain.writeInt(key: freeExportsUsedKey, value: existing)
        }
        defaults.set(true, forKey: migrationFlag)
    }

    // MARK: - Debug

    private func debugLine(for transaction: Transaction) -> String {
        let revoked = transaction.revocationDate.map { String(describing: $0) } ?? "nil"
        return "\(transaction.productID) ownership=\(String(describing: transaction.ownershipType)) revoked=\(revoked) purchased=\(transaction.purchaseDate) id=\(transaction.id) originalID=\(transaction.originalID)"
    }

    /// Runs the full receipt → worker → Apple chain and returns a human-readable
    /// summary of every step. Only surfaced in the UI on DEBUG and TestFlight builds.
    func debugVerifyReceipt() async -> String {
        var lines: [String] = []

        lines.append("=== Purchase State ===")
        lines.append("isUnlocked:    \(isUnlocked)")
        lines.append("isLegacyUser:  \(isLegacyUser)")
        lines.append("unlockedProductID: \(unlockedProductID ?? "nil")")
        lines.append("ownership:     \(unlockedOwnershipDescription ?? "nil")")
        lines.append("serverCached:  \(keychain.readInt(key: serverVerifiedLegacyKey) > 0)")
        lines.append("")

        lines.append("=== StoreKit Products ===")
        let loadedProducts = productsByID.values.sorted { $0.id < $1.id }
        if loadedProducts.isEmpty {
            lines.append("No products loaded")
        } else {
            for product in loadedProducts {
                lines.append("\(product.id): price=\(product.displayPrice), familyShareable=\(product.isFamilyShareable)")
            }
        }
        lines.append("")

        lines.append("=== Receipt ===")

        // Detailed receipt path diagnostics
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            lines.append("URL: \(receiptURL.lastPathComponent)")
            lines.append("Exists: \(FileManager.default.fileExists(atPath: receiptURL.path))")
        } else {
            lines.append("URL: nil")
        }

        // AppTransaction info (the StoreKit 2 way to get original version)
        lines.append("")
        lines.append("=== AppTransaction ===")
        do {
            let appTxResult = try await AppTransaction.shared
            switch appTxResult {
            case .verified(let appTx):
                lines.append("✅ Verified")
                lines.append("originalAppVersion: \(appTx.originalAppVersion)")
                lines.append("appVersion: \(appTx.appVersion)")
                lines.append("environment: \(appTx.environment.rawValue)")
            case .unverified(let appTx, let error):
                lines.append("⚠️ Unverified: \(error)")
                lines.append("originalAppVersion: \(appTx.originalAppVersion)")
            @unknown default:
                lines.append("❓ Unknown result")
            }
        } catch {
            lines.append("❌ \(error.localizedDescription)")
        }

        lines.append("")
        lines.append("=== Current Entitlements (Health.md products) ===")
        var currentEntitlementCount = 0
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard Self.purchaseOption(for: transaction.productID) != nil else { continue }
                currentEntitlementCount += 1
                lines.append(debugLine(for: transaction))
            case .unverified(let transaction, let error):
                guard Self.purchaseOption(for: transaction.productID) != nil else { continue }
                currentEntitlementCount += 1
                lines.append("⚠️ unverified \(debugLine(for: transaction)) error=\(error)")
            }
        }
        if currentEntitlementCount == 0 {
            lines.append("No Health.md current entitlements")
        }

        lines.append("")
        lines.append("=== Transaction History (Health.md products) ===")
        var historyCount = 0
        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                guard Self.purchaseOption(for: transaction.productID) != nil else { continue }
                historyCount += 1
                lines.append(debugLine(for: transaction))
            case .unverified(let transaction, let error):
                guard Self.purchaseOption(for: transaction.productID) != nil else { continue }
                historyCount += 1
                lines.append("⚠️ unverified \(debugLine(for: transaction)) error=\(error)")
            }
        }
        if historyCount == 0 {
            lines.append("No Health.md transactions in history")
        }

        // Try refreshing receipt via AppStore.sync()
        lines.append("")
        lines.append("=== AppStore.sync() ===")
        do {
            try await AppStore.sync()
            lines.append("✅ Sync succeeded")
        } catch {
            lines.append("❌ Sync failed: \(error.localizedDescription)")
        }

        // Re-check receipt after sync
        let receiptExists: Bool
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path) {
            let receiptData = try? Data(contentsOf: receiptURL)
            lines.append("Receipt: ✅ \(receiptData?.count ?? 0) bytes")
            receiptExists = true
        } else {
            lines.append("Receipt file still not found after sync")
            receiptExists = false
        }
        lines.append("")

        // Test JWS server path (works on TestFlight + App Store)
        lines.append("=== Worker: JWS Path ===")
        do {
            let jws = try await AppTransaction.shared.jwsRepresentation
            lines.append("JWS: \(jws.prefix(40))…")
            let jwsResult = await sendToWorker(path: "/verify-legacy-jws", body: ["jws": jws])
            lines.append("isLegacy: \(jwsResult)")
        } catch {
            lines.append("❌ No JWS: \(error.localizedDescription)")
        }

        // Test receipt server path (App Store only)
        if receiptExists,
           let receiptURL = Bundle.main.appStoreReceiptURL,
           let receiptData = try? Data(contentsOf: receiptURL) {
            lines.append("")
            lines.append("=== Worker: Receipt Path ===")
            let receiptResult = await sendToWorker(path: "/verify-legacy", body: ["receipt": receiptData.base64EncodedString()])
            lines.append("isLegacy: \(receiptResult)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Legacy Unlock

    /// Returns `true` when the given install should be granted free access.
    ///
    /// Single rule: every install with `originalPurchaseDate` before the
    /// grandfather cutoff is honored. Driven by `originalPurchaseDate`
    /// (Apple-signed, immutable) so the decision is robust against build
    /// number reshuffles or any future scheme changes.
    static func isLegacyUnlock(originalPurchaseDate: Date) -> Bool {
        originalPurchaseDate < grandfatherCutoffDate
    }

    private func analyticsErrorCategory(for error: Error) -> PricingAnalyticsErrorCategory {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost:
                return .networkUnavailable
            default:
                return .unknown
            }
        }

        return .unknown
    }
}
