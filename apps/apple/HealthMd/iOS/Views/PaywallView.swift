#if os(iOS)
import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedAudience: PaywallPricingAudience = .individual

    private let context: PaywallContext
    private let allowsDismissal: Bool

    init(
        context: PaywallContext = .export,
        allowsDismissal: Bool = true
    ) {
        self.context = context
        self.allowsDismissal = allowsDismissal
    }

    private var isManagingPurchase: Bool {
        context == .settings && purchaseManager.isUnlocked
    }

    private var titleText: String {
        isManagingPurchase ? String(localized: "Purchases & Family") : String(localized: "Keep Your Health Archive Growing")
    }

    private var subtitleText: String {
        if isManagingPurchase { return currentPlanTitle }
        return String(localized: "Choose a subscription or Lifetime access to begin your private health archive. Eligible subscriptions include a 7-day free trial.")
    }

    private var currentPlanTitle: String {
        purchaseManager.activePlanTitle
    }

    private var individualOptions: [HealthMdPurchaseOption] {
        [.weekly, .yearly, .individual]
    }

    private var familyOptions: [HealthMdPurchaseOption] {
        [.familyWeekly, .familyYearly, .family]
    }

    private var selectedOptions: [HealthMdPurchaseOption] {
        switch selectedAudience {
        case .individual: return individualOptions
        case .family: return familyOptions
        }
    }

    private var canShowFamilyUpgradeOffer: Bool {
        isManagingPurchase && purchaseManager.canBuyFamilyUpgrade
    }

    private var currentPlanDetail: String {
        if purchaseManager.isFamilyUnlocked {
            return String(localized: "Family Sharing is enabled for this Apple ID.")
        }
        if canShowFamilyUpgradeOffer {
            return String(localized: "Your health archive has unlimited exports. Upgrade to Family Lifetime at upgrade pricing if you want to share Health.md with up to 5 family members.")
        }
        return String(localized: "You have unlimited exports.")
    }

    var body: some View {
        glassBody
            .glassTheme()
            .accessibilityIdentifier(AccessibilityID.Paywall.view)
            .task { await purchaseManager.loadProductsIfNeeded() }
            .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
                if unlocked && !isManagingPurchase { dismiss() }
            }
    }

    private var glassPalette: GlassPalette {
        .resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }

    /// PaywallG, bound to the products `PurchaseManager` sells. Purchase, restore and
    /// disclosure paths are the ones the existing paywall uses.
    private var glassBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text(titleText)
                        .glassFont(.largeTitle)
                        .foregroundStyle(glassPalette.text)
                        .accessibilityIdentifier(AccessibilityID.Paywall.title)
                    Text(subtitleText)
                        .glassFont(.body)
                        .foregroundStyle(glassPalette.sec)
                        .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)

                    glassError

                    if isManagingPurchase {
                        GlassBanner(
                            title: currentPlanTitle,
                            message: currentPlanDetail,
                            systemImage: purchaseManager.isFamilyUnlocked ? "person.3.fill" : "checkmark.seal.fill",
                            tone: .success
                        )
                        if purchaseManager.canShowPermanentAccessNotice {
                            GlassBanner(
                                title: String(localized: "Your existing permanent access remains valid"),
                                systemImage: "lock.open.fill",
                                tone: .success
                            )
                        }
                        if canShowFamilyUpgradeOffer {
                            glassOption(
                                .familyUpgrade,
                                title: "Upgrade to Family Lifetime",
                                subtitle: "Upgrade pricing for existing Lifetime owners",
                                identifier: AccessibilityID.Paywall.familyUnlockButton
                            )
                        }
                    } else {
                        GlassSegmentedControl(
                            segments: PaywallPricingAudience.allCases.map {
                                .init(value: $0, title: String(localized: String.LocalizationValue($0.title)))
                            },
                            selection: $selectedAudience
                        )
                        ForEach(selectedOptions) { option in
                            glassOption(
                                option,
                                title: option.displayTitle,
                                subtitle: option.displaySubtitle,
                                identifier: option == .individual
                                    ? AccessibilityID.Paywall.unlockButton
                                    : AccessibilityID.Paywall.familyUnlockButton
                            )
                        }
                    }

                    if isManagingPurchase {
                        Link(
                            "Manage Subscriptions",
                            destination: URL(string: "https://apps.apple.com/account/subscriptions")!
                        )
                        .glassFont(.caption)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                    }

                    Button(LocalizedStringKey("Restore Purchase")) {
                        Task { await purchaseManager.restore(source: .paywall(context)) }
                    }
                    .buttonStyle(.plain)
                    .glassFont(.caption)
                    .foregroundStyle(glassPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                    .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                    .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
                    .accessibilityLabel("Restore previous purchase")

                    if !isManagingPurchase { purchaseDisclosure }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(glassPalette.bg.ignoresSafeArea())
            .toolbar {
                // The access gate presents this without dismissal: it is a hard paywall.
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close")) { dismiss() }
                            .accessibilityIdentifier(AccessibilityID.Paywall.dismissButton)
                    }
                }
            }
        }
    }

    @ViewBuilder private var glassError: some View {
        if let error = purchaseManager.purchaseError {
            GlassBanner(title: error, systemImage: "exclamationmark.triangle", tone: .warning)
                .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)
        } else if let productLoadError = purchaseManager.productLoadError, !purchaseManager.isLoadingProducts {
            GlassBanner(title: productLoadError, systemImage: "exclamationmark.triangle", tone: .warning)
                .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)
            Button(LocalizedStringKey("Try Again")) {
                Task { await purchaseManager.loadProductsIfNeeded(force: true) }
            }
            .frame(minHeight: GlassMetrics.touchTarget)
            .accessibilityLabel("Try loading purchase options again")
        }
    }

    private func glassOption(
        _ option: HealthMdPurchaseOption,
        title: String,
        subtitle: String,
        identifier: String
    ) -> some View {
        let isLoading = purchaseManager.purchasingOption == option || isPurchaseOptionLoading(option)
        return Button { purchase(option) } label: {
            GlassPanel {
                GlassRow(title: String(localized: String.LocalizationValue(title)), subtitle: String(localized: String.LocalizationValue(subtitle))) {
                    if isLoading { ProgressView() }
                    if let price = purchaseButtonPriceLabel(for: option) {
                        Text(price).glassFont(.navTitle).foregroundStyle(glassPalette.accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPurchaseButtonDisabled(for: option))
        .accessibilityIdentifier(identifier)
    }

    private var purchaseDisclosure: some View {
        OnboardingPurchaseDisclosure()
    }

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices {
            switch option {
            case .individual: return "$49.99"
            case .family: return "$89.99"
            case .familyUpgrade: return "$40.00"
            case .weekly: return "$0.99"
            case .yearly: return "$29.99"
            case .familyWeekly: return "$1.99"
            case .familyYearly: return "$49.99"
            }
        }
        #endif

        return purchaseManager.product(for: option)?.displayPrice
    }

    private func optionSubtitle(for option: HealthMdPurchaseOption) -> String {
        guard option.isSubscription,
              purchaseManager.trialEligibleProductIDs.contains(option.productID),
              let price = displayPrice(for: option) else { return option.displaySubtitle }
        return option == .weekly || option == .familyWeekly
            ? String(localized: "7 days free, then \(price) per week. Auto-renews; cancel anytime.")
            : String(localized: "7 days free, then \(price) per year. Auto-renews; cancel anytime.")
    }

    private func purchaseButtonPriceLabel(for option: HealthMdPurchaseOption) -> String? {
        if let price = displayPrice(for: option) { return price + option.priceSuffix }
        if TestMode.isUITesting { return displayPrice(for: option) }
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices { return displayPrice(for: option) }
        #endif
        if let price = displayPrice(for: option) { return price }
        if isPurchaseOptionLoading(option) { return String(localized: "Loading…") }
        if purchaseManager.productLoadError != nil || !purchaseManager.productsByID.isEmpty { return String(localized: "Unavailable") }
        return String(localized: "Loading…")
    }

    private func isPurchaseButtonDisabled(for option: HealthMdPurchaseOption) -> Bool {
        purchaseManager.isPurchasing
            || purchaseManager.isRestoring
            || isPurchaseOptionLoading(option)
            || !isPurchaseOptionAvailable(option)
    }

    private func isPurchaseOptionLoading(_ option: HealthMdPurchaseOption) -> Bool {
        if TestMode.isUITesting { return false }
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices { return false }
        #endif
        return purchaseManager.isLoadingProducts
    }

    private func isPurchaseOptionAvailable(_ option: HealthMdPurchaseOption) -> Bool {
        if TestMode.isUITesting { return true }
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices { return true }
        #endif
        return purchaseManager.product(for: option) != nil
    }

    private func purchase(_ option: HealthMdPurchaseOption) {
        Task {
            await purchaseManager.purchase(option, source: .paywall(context))
        }
    }

}

private enum PaywallPricingAudience: String, CaseIterable, Identifiable {
    case individual
    case family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual: return String(localized: "Individual")
        case .family: return String(localized: "Family")
        }
    }

    var sectionTitle: String {
        switch self {
        case .individual: return String(localized: "Individual")
        case .family: return String(localized: "Family Sharing")
        }
    }
}

/// Root access boundary: unpaid users cannot reach tracking/setup through a
/// dismiss gesture or a deep link. Restore and store errors remain available.
struct PurchaseAccessGate<Content: View>: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if purchases.isUnlocked || (TestMode.isUITesting && TestMode.purchaseUnlocked) {
                content()
            } else if purchases.isCheckingAccess && !TestMode.isUITesting {
                ProgressView("Checking purchases…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgPrimary)
            } else {
                PaywallView(context: .onboarding, allowsDismissal: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !TestMode.suppressesRuntimeServices else { return }
            Task { await purchases.refreshStatus() }
        }
    }
}

#Preview {
    PaywallView(context: .export)
}

#endif
