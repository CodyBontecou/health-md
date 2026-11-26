#if os(macOS) && !DEBUG
import Foundation
import Combine

nonisolated enum HealthMdPurchaseOption: String, CaseIterable, Identifiable, Sendable {
    case individual, family, familyUpgrade
    case weekly, yearly, familyWeekly, familyYearly

    var id: String { rawValue }
    var productID: String { rawValue }
    var isFamilyPlan: Bool { false }
    var displayTitle: String { rawValue }
    var displaySubtitle: String { "Health.md for Mac is free." }
    var badge: String? { nil }
    var iconName: String { "checkmark.seal.fill" }
}

/// Release macOS builds are a free companion app and must not initialize StoreKit.
@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    static let productID = HealthMdPurchaseOption.individual.productID
    static let familyProductID = HealthMdPurchaseOption.family.productID
    static let familyUpgradeProductID = HealthMdPurchaseOption.familyUpgrade.productID
    static let productIDs = HealthMdPurchaseOption.allCases.map(\.productID)
    static let freeExportLimit = 5
    static let grandfatherCutoffDate = Date.distantPast

    @Published private(set) var isUnlocked = true
    @Published private(set) var isLegacyUser = false
    @Published private(set) var unlockedProductID: String? = nil
    @Published private(set) var unlockedOwnershipDescription: String? = nil

    var freeExportsUsed: Int { 0 }
    var freeExportsRemaining: Int { 0 }
    var canExportFree: Bool { true }
    var canExport: Bool { true }
    func canExport(jobID: UUID) -> Bool { true }

    var isIndividualUnlocked: Bool { false }
    var isFamilyUnlocked: Bool { false }
    var canBuyFamilyUpgrade: Bool { false }
    var activePlanTitle: String { "Full access active" }
    var canShowPermanentAccessNotice: Bool { false }

    private init() {}

    func setUnlocked(_ value: Bool) { isUnlocked = true }
    func setUnlockedProductID(_ productID: String?) {}
    func setLegacyUser(_ value: Bool) { isLegacyUser = value }
    func setFreeExportsUsed(_ count: Int) {}
    func recordExportUse(offerGuidance: Bool = true) {}
    func recordExportUse(jobID: UUID) throws {}
    func loadProductsIfNeeded(force: Bool = false) async {}
    func purchase(
        _ option: HealthMdPurchaseOption = .individual,
        source: PurchasePresentationSource? = nil
    ) async {}
    func restore(source: PurchasePresentationSource? = nil) async {}
    func refreshStatus(includeHistoricalFallback: Bool = false, allowsServerVerification: Bool = true) async { isUnlocked = true }
    func scheduledExportAccess(jobID: UUID?, now: Date = Date()) async -> ScheduledExportAccessDecision { .allowed }
    func attemptSilentServerVerification() async {}
    static func isLegacyUnlock(originalPurchaseDate: Date) -> Bool { true }
    static func preferredEntitlementProductID<S: Sequence>(from productIDs: S) -> String? where S.Element == String { nil }
}

#else
import Foundation
import Combine
import StoreKit
import Security
#if os(iOS)
import UIKit
#endif

nonisolated enum HealthMdPurchaseOption: String, CaseIterable, Identifiable, Sendable {
    // Preserve the shipped non-consumable IDs for every existing owner.
    case individual, family, familyUpgrade
    case weekly, yearly, familyWeekly, familyYearly

    var id: String { rawValue }

    var productID: String {
        let prefix = "com.codybontecou.obsidianhealth."
        switch self {
        case .individual: return prefix + "unlock"
        case .family: return prefix + "unlock.family"
        case .familyUpgrade: return prefix + "unlock.family.upgrade"
        case .weekly: return prefix + "pro.weekly"
        case .yearly: return prefix + "pro.yearly.v2"
        case .familyWeekly: return prefix + "pro.family.weekly"
        case .familyYearly: return prefix + "pro.family.yearly.v2"
        }
    }

    var isSubscription: Bool {
        switch self {
        case .weekly, .yearly, .familyWeekly, .familyYearly: return true
        default: return false
        }
    }

    var isFamilyPlan: Bool {
        switch self {
        case .family, .familyUpgrade, .familyWeekly, .familyYearly: return true
        default: return false
        }
    }

    var displayTitle: String {
        switch self {
        case .individual: return String(localized: "Lifetime")
        case .family: return String(localized: "Family Lifetime")
        case .familyUpgrade: return String(localized: "Upgrade to Family Lifetime")
        case .weekly: return String(localized: "Weekly")
        case .yearly: return String(localized: "Yearly")
        case .familyWeekly: return String(localized: "Family Weekly")
        case .familyYearly: return String(localized: "Family Yearly")
        }
    }

    var displaySubtitle: String {
        if isSubscription { return isFamilyPlan ? String(localized: "Auto-renewing access for your Apple Family") : String(localized: "Auto-renewing unlimited private exports") }
        switch self {
        case .family: return String(localized: "Pay once and share with up to 5 family members")
        case .familyUpgrade: return String(localized: "Upgrade pricing for existing Lifetime owners")
        default: return String(localized: "One purchase, charged today")
        }
    }

    var badge: String? { isFamilyPlan ? String(localized: "Family") : nil }
    var iconName: String { isFamilyPlan ? "person.3.fill" : "person.fill" }

    /// The billing period spelled out after every price, so no plan label leaves the
    /// renewal term implicit (App Review guideline 3.1.2): "/week", "/year" or " one-time".
    var priceSuffix: String {
        switch self {
        case .weekly, .familyWeekly: return String(localized: "/week")
        case .yearly, .familyYearly: return String(localized: "/year")
        case .individual, .family, .familyUpgrade: return String(localized: " one-time")
        }
    }

    /// A StoreKit display price with its billing period, e.g. "$29.99/year".
    func priceLabel(displayPrice: String) -> String {
        displayPrice + priceSuffix
    }
}

/// Manages StoreKit trials, subscriptions, and permanent paid access.
/// Relies on Apple's StoreKit 2 infrastructure for paid entitlements.
@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // MARK: - Configuration

    /// Product IDs expected by the rollout; store activation is a release prerequisite.
    static let productID = HealthMdPurchaseOption.individual.productID
    static let familyProductID = HealthMdPurchaseOption.family.productID
    static let familyUpgradeProductID = HealthMdPurchaseOption.familyUpgrade.productID
    static let productIDs = HealthMdPurchaseOption.allCases.map(\.productID)

    /// Let users generate their first export before choosing paid access.
    /// Historical usage remains in the same durable ledger.
    static let freeExportLimit = 1

    /// Free-export counts after which a soft, non-blocking upgrade prompt is
    /// surfaced ("value moments"). Distinct from the hard quota block.
    static let upgradePromptMilestones: Set<Int> = []

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
            // Preserve the first-export ledger through purchase, restore, and expiry.
            if isUnlocked && !oldValue {
                pendingUpgradePrompt = nil
            }
        }
    }
    @Published private(set) var isLegacyUser: Bool = false {
        didSet { if isLegacyUser { activeEntitlementExpiration = nil } }
    }
    @Published private(set) var product: Product? = nil
    @Published private(set) var familyProduct: Product? = nil
    @Published private(set) var familyUpgradeProduct: Product? = nil
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var trialEligibleProductIDs: Set<String> = []
    @Published private(set) var isCheckingAccess = true
    private var entitlementExpirationTask: Task<Void, Never>?
    private var activeEntitlementExpiration: Date?
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var productLoadError: String? = nil
    @Published private(set) var purchasingOption: HealthMdPurchaseOption? = nil
    @Published private(set) var unlockedProductID: String? = nil
    @Published private(set) var unlockedOwnershipDescription: String? = nil
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var purchaseError: String? = nil

    // MARK: - Soft Value Moments

    /// Non-nil after the first (schedule guidance) or third (lifetime offer)
    /// completed free export. Observed by the iOS and iPad
    /// UIs; App Intent / background exports simply leave it set until the
    /// next foreground visit.
    @Published private(set) var pendingUpgradePrompt: Int? = nil

    private let upgradePromptShownDefaultsKey = "pricing.upgradePrompt.shown.v1"

    // MARK: - Free Export Quota
    //
    // Stored in the Keychain (not UserDefaults) so the count survives app
    // deletion and reinstallation, preventing quota resets through reinstalling.

    private let freeExportsUsedKey             = "freeExportsUsed"
    // Keep the original Keychain key name so existing direct-export usage and
    // newly recorded scheduled jobs share one durable, migration-free ledger.
    private let durableExportUseIDsKey          = "directExportUseIDs"
    private var uiTestExportUses = 0
    private let serverVerifiedLegacyKey        = "serverVerifiedLegacy"
    private let serverVerificationAttemptedKey = "serverVerificationAttempted"
    /// Last entitlement confirmed by StoreKit or legacy verification. Read only
    /// as a fallback when StoreKit cannot be read reliably (background launch
    /// with the iPhone locked), so paid owners are never treated as free there.
    private let lastKnownEntitlementKey        = "lastKnownEntitlement.v1"

    /// Total number of free export actions the user has consumed.
    var freeExportsUsed: Int {
        if TestMode.isUITesting { return TestMode.freeExportsUsed + uiTestExportUses }
        return keychain.readInt(key: freeExportsUsedKey) + durableExportUseIDs.count
    }

    private var durableExportUseIDs: Set<String> {
        Set(
            (keychain.readString(key: durableExportUseIDsKey) ?? "")
                .split(separator: ",")
                .map(String.init)
        )
    }

    /// How many free exports remain before a purchase is required.
    var freeExportsRemaining: Int {
        return max(0, Self.freeExportLimit - freeExportsUsed)
    }

    /// True when the user still has free exports left.
    var canExportFree: Bool {
        freeExportsRemaining > 0
    }

    /// True when the user may perform an export (unlocked or within free quota).
    var canExport: Bool {
        if TestMode.isUITesting {
            return TestMode.purchaseUnlocked || freeExportsUsed < Self.freeExportLimit
        }
        return canExportFree || (isUnlocked && (activeEntitlementExpiration.map { $0 > Date() } ?? true))
    }

    /// Durable jobs use the same allowance at admission, including resume.
    /// A receipt does not grant another free action after the allowance is used.
    func canExport(jobID: UUID) -> Bool {
        if TestMode.isUITesting {
            return canExport
        }
        return canExport
    }

    #if DEBUG
    /// Isolate real sandbox purchases from this device's preserved legacy grant.
    /// StoreKit entitlements still resolve normally; no saved state is erased.
    var sandboxPurchaseQAEnabled = ProcessInfo.processInfo.arguments.contains("-SandboxPurchasesQA")
    #endif

    // MARK: - Injected Dependencies

    private let keychain: KeychainStoring
    private let defaults: UserDefaultsStoring
    private let productLoader: @MainActor ([String]) async throws -> [Product]
    private var productLoadTask: Task<Void, Never>? = nil
    /// Re-reads entitlement state before a scheduled export admission check.
    /// Production skips the legacy server POSTs to protect the background budget.
    private let statusRefresher: @MainActor (PurchaseManager) async -> Void
    /// Whether a negative entitlement read can be trusted. StoreKit's local
    /// transaction store may be unreadable while the device is locked.
    private let entitlementReadIsReliable: @MainActor () -> Bool
    /// False in UI-test, IAP-review and static-price modes, whose configured
    /// purchase state must not be overwritten by a live StoreKit read.
    private let refreshesBeforeScheduledAdmission: Bool
    /// Test seam for the body of one refresh; nil runs the StoreKit refresh.
    /// Arguments: includeHistoricalFallback, allowsServerVerification.
    private let refreshWork: (@MainActor (PurchaseManager, Bool, Bool) async -> Void)?

    // MARK: - Init

    private init() {
        self.keychain = SystemKeychainStore()
        self.defaults = SystemUserDefaults()
        self.productLoader = { productIDs in
            try await Product.products(for: productIDs)
        }
        self.statusRefresher = { await $0.refreshStatus(allowsServerVerification: false) }
        self.entitlementReadIsReliable = Self.liveEntitlementReadIsReliable
        self.refreshesBeforeScheduledAdmission = Self.usesLiveStoreKit
        self.refreshWork = nil
        migrateUserDefaultsToKeychain()

        #if os(macOS)
        // The Mac app is a free companion/destination. Paid access is enforced
        // only where Apple Health exports originate: the iOS/iPadOS app.
        isUnlocked = true
        return
        #endif

        // In UI test / IAP review capture mode, skip all StoreKit interactions.
        // Test state is configured via configureTestMode() / configureIAPReviewMode().
        guard Self.usesLiveStoreKit else {
            isCheckingAccess = false
            return
        }

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
        productLoader: @MainActor @escaping ([String]) async throws -> [Product] = { _ in [] },
        statusRefresher: (@MainActor (PurchaseManager) async -> Void)? = nil,
        entitlementReadIsReliable: @MainActor @escaping () -> Bool = { true },
        refreshWork: (@MainActor (PurchaseManager, Bool, Bool) async -> Void)? = nil
    ) {
        self.keychain = keychain
        self.defaults = defaults
        self.productLoader = productLoader
        self.statusRefresher = statusRefresher ?? { await $0.refreshStatus(allowsServerVerification: false) }
        self.entitlementReadIsReliable = entitlementReadIsReliable
        self.refreshesBeforeScheduledAdmission = true
        self.refreshWork = refreshWork
        migrateUserDefaultsToKeychain()
    }

    private static func liveEntitlementReadIsReliable() -> Bool {
        #if os(iOS)
        return UIApplication.shared.isProtectedDataAvailable
        #else
        return true
        #endif
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
        #if os(macOS)
        return false
        #else
        return !TestMode.isUITesting && !isIAPReviewCapture && !usesStaticPurchasePrices
        #endif
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

    /// Test-only: record a StoreKit entitlement through the production path,
    /// including the last-known-entitlement persistence.
    func recordStoreKitEntitlementForTesting(productID: String, expirationDate: Date? = nil) {
        recordUnlockedEntitlement(StoreKitEntitlementCandidate(
            productID: productID, ownershipDescription: "test", source: "test", expirationDate: expirationDate))
    }

    /// Test-only: record a grandfathered unlock through the production path.
    func recordLegacyUnlockForTesting() {
        recordLegacyUnlock()
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
        keychain.writeString(key: durableExportUseIDsKey, value: "")
    }

    var isIndividualUnlocked: Bool {
        unlockedProductID == Self.productID
    }

    var isFamilyUnlocked: Bool {
        guard let unlockedProductID else { return false }
        return Self.isFamilyEntitlement(productID: unlockedProductID)
    }

    /// Shared settings copy; a Family subscription is not Family Lifetime.
    var activePlanTitle: String {
        guard isUnlocked else { return "Unlock Full Access" }
        if let productID = unlockedProductID,
           let option = Self.purchaseOption(for: productID) {
            let title = option == .familyUpgrade ? HealthMdPurchaseOption.family.displayTitle : option.displayTitle
            return "\(title) active"
        }
        if isLegacyUser { return "Grandfathered Full Access active" }
        return "Full access active"
    }

    /// Presentation only: an unlocked flag alone cannot justify a forever claim.
    /// Use the existing recognized non-consumable or verified legacy evidence.
    var canShowPermanentAccessNotice: Bool {
        guard isUnlocked else { return false }
        if isLegacyUser { return true }
        guard let productID = unlockedProductID,
              let option = Self.purchaseOption(for: productID) else { return false }
        return !option.isSubscription
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

    private static func purchaseOption(for productID: String) -> HealthMdPurchaseOption? {
        HealthMdPurchaseOption.allCases.first { $0.productID == productID }
    }

    private static func isFamilyEntitlement(productID: String) -> Bool {
        purchaseOption(for: productID)?.isFamilyPlan == true
    }

    private static let entitlementPriority: [String] = [
        familyProductID, familyUpgradeProductID, productID,
        HealthMdPurchaseOption.familyYearly.productID,
        HealthMdPurchaseOption.familyWeekly.productID,
        HealthMdPurchaseOption.yearly.productID,
        HealthMdPurchaseOption.weekly.productID,
    ]

    static func preferredEntitlementProductID<S: Sequence>(from productIDs: S) -> String? where S.Element == String {
        let availableIDs = Set(productIDs)
        return entitlementPriority.first { availableIDs.contains($0) }
    }

    private struct StoreKitEntitlementCandidate {
        let productID: String
        let ownershipDescription: String
        let source: String
        let expirationDate: Date?
    }

    static func isActiveEntitlement(
        option: HealthMdPurchaseOption, expirationDate: Date?,
        revocationDate: Date?, isUpgraded: Bool, now: Date = Date()
    ) -> Bool {
        guard revocationDate == nil, !isUpgraded else { return false }
        return !option.isSubscription || expirationDate.map { $0 > now } == true
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
        activeEntitlementExpiration = entitlement.expirationDate
        persistLastKnownEntitlement(productID: entitlement.productID, expiresAt: entitlement.expirationDate)
        entitlementExpirationTask?.cancel()
        if let expiration = entitlement.expirationDate {
            entitlementExpirationTask = Task { [weak self] in
                let seconds = max(0, expiration.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.refreshStatus()
            }
        }
    }

    private func entitlementCandidate(from transaction: Transaction, source: String) -> StoreKitEntitlementCandidate? {
        guard let option = Self.purchaseOption(for: transaction.productID),
              Self.isActiveEntitlement(option: option, expirationDate: transaction.expirationDate,
                                       revocationDate: transaction.revocationDate,
                                       isUpgraded: transaction.isUpgraded) else { return nil }

        return StoreKitEntitlementCandidate(
            productID: transaction.productID,
            ownershipDescription: String(describing: transaction.ownershipType),
            source: source,
            expirationDate: transaction.expirationDate
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
                  Self.purchaseOption(for: transaction.productID)?.isSubscription == false,
                  let candidate = entitlementCandidate(from: transaction, source: "transactionHistory") else {
                continue
            }
            candidates.append(candidate)
        }

        return Self.preferredEntitlement(from: candidates)
    }

    // MARK: - Status Check

    private struct InFlightRefresh {
        let id: UInt64
        let task: Task<Void, Never>
        let includeHistoricalFallback: Bool
        let allowsServerVerification: Bool

        func covers(includeHistoricalFallback: Bool, allowsServerVerification: Bool) -> Bool {
            (self.includeHistoricalFallback || !includeHistoricalFallback)
                && (self.allowsServerVerification || !allowsServerVerification)
        }
    }

    private var inFlightRefresh: InFlightRefresh?
    private var nextRefreshID: UInt64 = 0

    /// Re-evaluates unlock status from StoreKit entitlements and AppTransaction.
    /// Called on init, after purchase, after restore, and before background
    /// export admission.
    ///
    /// Refreshes never interleave: the body resets shared state across awaits,
    /// so a concurrent caller waits for the running refresh and reuses its
    /// result when that refresh did at least as much work.
    /// - Parameter allowsServerVerification: `false` skips the legacy receipt
    ///   POSTs (step 4), for background callers with a limited time budget.
    func refreshStatus(includeHistoricalFallback: Bool = false, allowsServerVerification: Bool = true) async {
        while let running = inFlightRefresh {
            await running.task.value
            // A waiter can resume before the refresh's own caller does; clear the
            // finished entry here so the loop never re-awaits a completed task.
            if inFlightRefresh?.id == running.id { inFlightRefresh = nil }
            if running.covers(includeHistoricalFallback: includeHistoricalFallback,
                              allowsServerVerification: allowsServerVerification) {
                return
            }
        }
        nextRefreshID &+= 1
        let id = nextRefreshID
        let task = Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            if let refreshWork = self.refreshWork {
                await refreshWork(self, includeHistoricalFallback, allowsServerVerification)
                self.isCheckingAccess = false
                return
            }
            await self.performRefreshStatus(
                includeHistoricalFallback: includeHistoricalFallback,
                allowsServerVerification: allowsServerVerification
            )
            #if os(iOS)
            await self.refreshTrialReminder()
            #endif
        }
        inFlightRefresh = InFlightRefresh(
            id: id,
            task: task,
            includeHistoricalFallback: includeHistoricalFallback,
            allowsServerVerification: allowsServerVerification
        )
        await task.value
        if inFlightRefresh?.id == id { inFlightRefresh = nil }
    }

    private func performRefreshStatus(includeHistoricalFallback: Bool, allowsServerVerification: Bool) async {
        defer { isCheckingAccess = false }
        #if os(macOS)
        isUnlocked = true
        return
        #endif
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
        if !sandboxPurchaseQAEnabled,
           UserDefaults.standard.string(forKey: "debugOriginalAppVersion") != nil {
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
                recordLegacyUnlock()
            } else {
                isLegacyUser = false
                isUnlocked = false
                recordConfirmedNoEntitlement()
            }
            return
        }

        // Debug override: set "debugSkipToServerVerification" = true to bypass steps
        // 1–3 and jump straight to the server receipt check. Use this to test the
        // Cloudflare Worker integration end-to-end on a device that isn't a legacy user.
        //
        // Hardcode in init() temporarily:
        //   UserDefaults.standard.set(true, forKey: "debugSkipToServerVerification")
        if !sandboxPurchaseQAEnabled,
           UserDefaults.standard.bool(forKey: "debugSkipToServerVerification") {
            if await verifyLegacyWithServer() {
                keychain.writeInt(key: serverVerifiedLegacyKey, value: 1)
                recordLegacyUnlock()
            } else {
                isUnlocked = false
                recordConfirmedNoEntitlement()
            }
            return
        }
        #endif

        unlockedProductID = nil
        unlockedOwnershipDescription = nil
        entitlementExpirationTask?.cancel()
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

        #if DEBUG
        // A fresh sandbox tester on a long-lived QA phone must be able to test
        // subscription-only access while retaining the phone's legacy rights.
        if sandboxPurchaseQAEnabled {
            // A debug override must never be masked by the background fallback.
            activeEntitlementExpiration = nil
            isUnlocked = false
            recordConfirmedNoEntitlement()
            return
        }
        #endif

        // 2. Server-verified legacy path: a previous call to verifyLegacyWithServer()
        //    confirmed this device originally purchased before v1.7.0 and cached the
        //    result in the Keychain. This survives app reinstalls.
        if keychain.readInt(key: serverVerifiedLegacyKey) > 0 {
            recordLegacyUnlock()
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
                    recordLegacyUnlock()
                    return
                }
            case .unverified(let appTx, _):
                // Local JWS verification failed (cert cache, clock skew, etc.) but the
                // data is still Apple-signed. Trust it for legacy detection — an attacker
                // who can forge AppTransaction responses already has device-level control
                // and could bypass any client-side check.
                if Self.isLegacyUnlock(originalPurchaseDate: appTx.originalPurchaseDate) {
                    recordLegacyUnlock()
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
        if allowsServerVerification, await verifyLegacyWithServer() {
            keychain.writeInt(key: serverVerifiedLegacyKey, value: 1)
            recordLegacyUnlock()
            return
        }

        concludeNoEntitlement(cachedEntitlementRevoked: await cachedEntitlementWasRevoked())
    }

    /// Final refresh outcome when no access path matched.
    ///
    /// An empty read cannot end a still-valid cached entitlement:
    /// `Transaction.currentEntitlements` and `AppTransaction` can come back
    /// empty on a background launch, even on an unlocked device. A cached
    /// entitlement ends only when its term does (`expiresAt`, which already
    /// covers a cancelled subscription) or on evidence that it was revoked —
    /// a refund or a family-sharing removal — seen by a reliable read.
    ///
    /// With nothing valid cached, a reliable read (device unlocked) records a
    /// confirmed "none"; an unreliable one locks without recording anything.
    private func concludeNoEntitlement(cachedEntitlementRevoked: Bool) {
        let reliable = entitlementReadIsReliable()
        if case .entitlement(let cached) = lastKnownAccess(), cached.isValid(at: Date()),
           !(reliable && cachedEntitlementRevoked) {
            restoreLastKnownEntitlement(cached)
            return
        }
        isUnlocked = false
        if reliable { recordConfirmedNoEntitlement() }
    }

    /// True when StoreKit history shows the cached product was revoked and
    /// holds no active transaction for it (for example after a re-purchase).
    /// For a subscription only a revocation of the cached period counts, so a
    /// refund of an earlier period does not end a later one.
    private func cachedEntitlementWasRevoked() async -> Bool {
        guard case .entitlement(let cached) = lastKnownAccess(),
              cached.productID != Self.legacyEntitlementMarker else { return false }
        var revoked = false
        for await result in Transaction.all {
            guard case .verified(let transaction) = result,
                  transaction.productID == cached.productID else { continue }
            if transaction.revocationDate != nil {
                if Self.revocationEndsCachedTerm(cachedExpiresAt: cached.expiresAt,
                                                 revokedExpiresAt: transaction.expirationDate) {
                    revoked = true
                }
            } else if entitlementCandidate(from: transaction, source: "transactionHistory") != nil {
                return false
            }
        }
        return revoked
    }

    /// A lifetime revocation always applies; a subscription revocation applies
    /// when it covers the cached period's end.
    static func revocationEndsCachedTerm(cachedExpiresAt: Date?, revokedExpiresAt: Date?) -> Bool {
        guard let cachedExpiresAt else { return true }
        guard let revokedExpiresAt else { return false }
        return revokedExpiresAt >= cachedExpiresAt
    }

    /// Test-only: apply the "no entitlement found" refresh outcome without StoreKit.
    func concludeNoEntitlementForTesting(cachedEntitlementRevoked: Bool = false) {
        concludeNoEntitlement(cachedEntitlementRevoked: cachedEntitlementRevoked)
    }

    /// The one way a grandfathered owner is unlocked, so every legacy path
    /// also records the background fallback.
    private func recordLegacyUnlock() {
        isLegacyUser = true
        persistLastKnownEntitlement(productID: Self.legacyEntitlementMarker, expiresAt: nil)
        isUnlocked = true
    }

    private func restoreLastKnownEntitlement(_ cached: LastKnownEntitlement) {
        if cached.productID == Self.legacyEntitlementMarker {
            isLegacyUser = true
        } else {
            recordUnlockedProductID(cached.productID, ownershipDescription: "lastKnownEntitlement")
            activeEntitlementExpiration = cached.expiresAt
        }
        isUnlocked = true
    }

    // MARK: - Last-Known Entitlement

    /// Marker stored for grandfathered owners, who have no StoreKit product.
    private static let legacyEntitlementMarker = "legacy"
    /// Stored after a reliable read found no access.
    private static let confirmedNoEntitlementMarker = "none"

    private struct LastKnownEntitlement: Codable {
        let productID: String
        let expiresAt: Date?

        /// Lifetime and legacy access have no expiry; subscriptions keep theirs.
        func isValid(at now: Date) -> Bool {
            expiresAt.map { $0 > now } ?? true
        }
    }

    private enum LastKnownAccess {
        /// No reliable read has been recorded on this device yet.
        case unknown
        /// The last reliable read found no access.
        case confirmedNone
        case entitlement(LastKnownEntitlement)
    }

    private func lastKnownAccess() -> LastKnownAccess {
        guard !TestMode.isUITesting,
              let value = keychain.readString(key: lastKnownEntitlementKey) else { return .unknown }
        if value == Self.confirmedNoEntitlementMarker { return .confirmedNone }
        guard let data = value.data(using: .utf8),
              let entitlement = try? JSONDecoder().decode(LastKnownEntitlement.self, from: data) else {
            return .unknown
        }
        return .entitlement(entitlement)
    }

    private func persistLastKnownEntitlement(productID: String, expiresAt: Date?) {
        guard let data = try? JSONEncoder().encode(LastKnownEntitlement(productID: productID, expiresAt: expiresAt)),
              let value = String(data: data, encoding: .utf8) else { return }
        keychain.writeString(key: lastKnownEntitlementKey, value: value)
    }

    private func recordConfirmedNoEntitlement() {
        keychain.writeString(key: lastKnownEntitlementKey, value: Self.confirmedNoEntitlementMarker)
    }

    /// True when a previously confirmed entitlement is still within its term.
    func hasValidLastKnownEntitlement(now: Date = Date()) -> Bool {
        guard case .entitlement(let cached) = lastKnownAccess() else { return false }
        return cached.isValid(at: now)
    }

    // MARK: - Scheduled Export Admission

    /// Admission check for scheduled (background) exports. Awaits a fresh
    /// entitlement read first: `isUnlocked` starts `false` and a background
    /// launch can reach this before the launch refresh has finished. The
    /// refresh restores a cached entitlement when StoreKit can't be read.
    ///
    /// When nothing grants access, the limit is reported only if absence is
    /// known: the read was reliable, or the last reliable read on this device
    /// found no access. Otherwise (no reliable read yet, or a cached
    /// subscription that may have renewed) the caller defers.
    func scheduledExportAccess(jobID: UUID?, now: Date = Date()) async -> ScheduledExportAccessDecision {
        guard refreshesBeforeScheduledAdmission else {
            return canExport ? .allowed : .limitReached
        }
        await statusRefresher(self)
        let quotaAllows = jobID.map(canExport(jobID:)) ?? canExport
        if quotaAllows || hasValidLastKnownEntitlement(now: now) { return .allowed }
        if entitlementReadIsReliable() { return .limitReached }
        if case .confirmedNone = lastKnownAccess() { return .limitReached }
        return .entitlementUnresolved
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
                var eligible: Set<String> = []
                for product in products {
                    if let subscription = product.subscription,
                       let offer = subscription.introductoryOffer,
                       offer.paymentMode == .freeTrial,
                       ((offer.period.unit == .day && offer.period.value == 7) ||
                        (offer.period.unit == .week && offer.period.value == 1)),
                       await subscription.isEligibleForIntroOffer {
                        eligible.insert(product.id)
                    }
                }
                self.trialEligibleProductIDs = eligible
                self.product = loadedProductsByID[Self.productID]
                self.familyProduct = loadedProductsByID[Self.familyProductID]
                self.familyUpgradeProduct = loadedProductsByID[Self.familyUpgradeProductID]
                let saleOptions = HealthMdPurchaseOption.allCases.filter { $0 != .familyUpgrade }
                self.productLoadError = saleOptions.allSatisfy { loadedProductsByID[$0.productID] != nil }
                    ? nil : Self.productUnavailableMessage
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
    func purchase(
        _ option: HealthMdPurchaseOption = .individual,
        source: PurchasePresentationSource? = nil
    ) async {

        if option == .familyUpgrade {
            guard canBuyFamilyUpgrade else {
                purchaseError = String(
                    localized: "Family Upgrade requires an existing Lifetime unlock.",
                    comment: "Error shown when the family-upgrade IAP is attempted without an eligible base purchase"
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
                    return
                }
                await tx.finish()
                #if os(iOS)
                // The trial timeline promised a reminder before the first charge.
                // The prompt waits on the user, so it must never hold up the purchase.
                if TrialReminderNotification.isIntroductoryOffer(tx) {
                    Task { await TrialReminderNotification.requestPermissionIfUndetermined() }
                }
                #endif
                // Reconcile all current entitlements: an expired/upgraded subscription
                // must never become a permanent unlock via a purchase callback.
                await refreshStatus()

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

    /// Whether a StoreKit error only reports that the person dismissed the
    /// Apple Account prompt, which should leave the paywall silent.
    nonisolated static func isUserCancellation(_ error: Error) -> Bool {
        if case StoreKitError.userCancelled = error { return true }
        if let skError = error as? SKError, skError.code == .paymentCancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

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
    func restore(source: PurchasePresentationSource? = nil) async {

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
            return
        }

        if let syncError {
            // Cancelling the Apple Account sign-in is the user's choice, not a failure.
            if !Self.isUserCancellation(syncError) {
                purchaseError = syncError.localizedDescription
            }
            return
        }

        purchaseError = Self.restoreNotFoundMessage
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
        if sandboxPurchaseQAEnabled ||
           UserDefaults.standard.string(forKey: "debugOriginalAppVersion") != nil {
            return
        }
        #endif

        let attempts = keychain.readInt(key: serverVerificationAttemptedKey)
        guard attempts < Self.maxServerVerificationAttempts else { return }

        let isLegacy = await verifyLegacyWithServer()
        if isLegacy {
            keychain.writeInt(key: serverVerifiedLegacyKey, value: 1)
            recordLegacyUnlock()
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
        #if DEBUG
        guard !sandboxPurchaseQAEnabled else { return false }
        #endif
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
        keychain.writeString(key: durableExportUseIDsKey, value: "")
        objectWillChange.send()
    }

    /// Increments the free-export counter by one.
    /// Call once per successful export action or scheduled occurrence,
    /// regardless of how many dates or files were written.
    /// No-op when the user is already unlocked.
    func recordExportUse(offerGuidance: Bool = true) {
        guard !isUnlocked, !hasValidLastKnownEntitlement(), freeExportsUsed < Self.freeExportLimit else { return }
        if TestMode.isUITesting {
            guard !TestMode.purchaseUnlocked else { return }
            uiTestExportUses += 1
        } else {
            keychain.writeInt(
                key: freeExportsUsedKey,
                value: keychain.readInt(key: freeExportsUsedKey) + 1
            )
        }
        objectWillChange.send()
        if offerGuidance { evaluateUpgradePrompt() }
    }

    /// Records one durable export operation exactly once by job identity.
    /// The complete ID set is one atomic Keychain value and contributes to the
    /// computed quota, so direct and scheduled jobs remain safe to retry.
    func recordExportUse(jobID: UUID) throws {
        guard !isUnlocked, !hasValidLastKnownEntitlement() else { return }
        var identifiers = durableExportUseIDs
        let identifier = jobID.uuidString.lowercased()
        guard !identifiers.contains(identifier), freeExportsUsed < Self.freeExportLimit else { return }
        identifiers.insert(identifier)
        try keychain.writeStringOrThrow(
            key: durableExportUseIDsKey,
            value: identifiers.sorted().joined(separator: ",")
        )
        objectWillChange.send()
        evaluateUpgradePrompt()
    }

    /// Marks the milestone prompt as handled and clears the pending state.
    /// Called when the UI presents the prompt (so it never replays) or when
    /// the user dismisses it.
    func consumeUpgradePrompt() {
        if let milestone = pendingUpgradePrompt {
            markUpgradePromptShown(milestone)
        }
        pendingUpgradePrompt = nil
    }

    private func evaluateUpgradePrompt() {
        guard !isUnlocked, pendingUpgradePrompt == nil else { return }
        let used = freeExportsUsed
        guard Self.upgradePromptMilestones.contains(used), !upgradePromptAlreadyShown(used) else { return }
        pendingUpgradePrompt = used
    }

    private func upgradePromptAlreadyShown(_ milestone: Int) -> Bool {
        if TestMode.isUITesting {
            return TestMode.suppressedUpgradePromptMilestones.contains(String(milestone))
        }
        return defaults.bool(forKey: "\(upgradePromptShownDefaultsKey).\(milestone)")
    }

    private func markUpgradePromptShown(_ milestone: Int) {
        guard !TestMode.isUITesting else { return }
        defaults.set(true, forKey: "\(upgradePromptShownDefaultsKey).\(milestone)")
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

                await self.refreshStatus()
            }
        }
    }

    #if os(iOS)
    /// Schedules, replaces or removes the reminder before a renewing trial is billed.
    private func refreshTrialReminder() async {
        let prices = productsByID.mapValues(\.displayPrice)
        let trial = await TrialReminderNotification.currentTrial { prices[$0] }
        TrialReminderNotification.refresh(trial: trial)
    }
    #endif

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

}

#endif

/// Outcome of the scheduled-export entitlement check. A scheduled export runs
/// in the background, where StoreKit can be unreadable (for example while the
/// iPhone is locked), so "unknown" must never be reported as "limit reached".
enum ScheduledExportAccessDecision: Equatable, Sendable {
    /// Full access or free allowance is available; run the export.
    case allowed
    /// The entitlement was read reliably and no allowance remains.
    case limitReached
    /// The entitlement could not be confirmed right now; defer the export.
    case entitlementUnresolved
}
