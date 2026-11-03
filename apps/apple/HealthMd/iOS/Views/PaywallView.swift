#if os(iOS)
import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

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

    private var currentPlanFamilyFeatureText: String {
        if purchaseManager.isFamilyUnlocked { return String(localized: "Family Sharing is active") }
        if canShowFamilyUpgradeOffer { return String(localized: "Family upgrade available") }
        return String(localized: "Family Sharing is not active")
    }

    var body: some View {
        Group {
            if isManagingPurchase {
                managementLayout
            } else {
                SignalPaywallCarousel(
                    purchaseManager: purchaseManager,
                    pricing: signalPricing,
                    allowsDismissal: allowsDismissal,
                    onDismiss: { dismiss() },
                    onPurchase: purchase,
                    onRestore: restore
                ) {
                    purchaseStatus
                }
            }
        }
        // A container keeps child identifiers (restore, purchase, dismiss) addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Paywall.view)
        .task { await purchaseManager.loadProductsIfNeeded() }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && !isManagingPurchase { dismiss() }
        }
    }

    private var signalPricing: SignalPaywallCarousel<AnyView>.Pricing {
        .init(
            priceLabel: purchaseButtonPriceLabel(for:),
            weeklyEquivalent: weeklyEquivalentPrice(for:),
            isTrialEligible: isTrialEligible,
            footerLine: { option in
                option.isSubscription ? optionSubtitle(for: option) : (purchaseButtonPriceLabel(for: option) ?? option.displaySubtitle)
            },
            isLoading: isPurchaseOptionLoading,
            isDisabled: isPurchaseButtonDisabled(for:)
        )
    }

    private var managementLayout: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            OnboardingPaywallLayout(onDismiss: { dismiss() }, dismissIdentifier: AccessibilityID.Paywall.dismissButton, allowsDismissal: allowsDismissal) {
                VStack(spacing: Spacing.s6) {
                    header

                    VStack(spacing: Spacing.s3) {
                        PaywallFeatureRow(icon: "archivebox.fill", text: String(localized: "Your health archive access is active"))
                        PaywallFeatureRow(icon: "clock.fill", text: String(localized: "Unlimited automated daily notes"))
                        PaywallFeatureRow(icon: "person.3.fill", text: currentPlanFamilyFeatureText)
                        if purchaseManager.canShowPermanentAccessNotice {
                            PaywallFeatureRow(icon: "lock.open.fill", text: String(localized: "Your existing permanent access remains valid"))
                        }
                    }

                    ctaSection
                }
            }
        }
    }

    private var header: some View {
        OnboardingPaywallHeader(
            title: titleText,
            subtitle: subtitleText,
            titleIdentifier: AccessibilityID.Paywall.title,
            subtitleIdentifier: AccessibilityID.Paywall.subtitle
        )
    }

    /// Store errors and catalog retry, shared by the carousel and management layout.
    private var purchaseStatus: AnyView {
        AnyView(Group {
            if let error = purchaseManager.purchaseError {
                Text(error)
                    .font(Typography.caption())
                    .foregroundStyle(error.contains("cody@isolated.tech") ? Color.textSecondary : Color.errorText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s3)
                    .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)
            } else if let productLoadError = purchaseManager.productLoadError, !purchaseManager.isLoadingProducts {
                VStack(spacing: Spacing.s2) {
                    Text(productLoadError)
                        .font(Typography.caption())
                        .foregroundStyle(Color.errorText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.s3)
                        .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)

                    OnboardingTextAction(title: "Try Again") {
                        Task { await purchaseManager.loadProductsIfNeeded(force: true) }
                    }
                    .accessibilityLabel("Try loading purchase options again")
                }
            }
        })
    }

    private var ctaSection: some View {
        VStack(spacing: Spacing.s3) {
            purchaseStatus

            PaywallCurrentPlanCard(
                title: currentPlanTitle,
                detail: currentPlanDetail,
                icon: purchaseManager.isFamilyUnlocked ? "person.3.fill" : "checkmark.seal.fill"
            )

            if canShowFamilyUpgradeOffer {
                PaywallPurchaseOptionButton(
                    title: String(localized: "Upgrade to Family Lifetime"),
                    subtitle: String(localized: "Upgrade pricing for existing Lifetime owners"),
                    priceLabel: purchaseButtonPriceLabel(for: .familyUpgrade),
                    icon: "person.3.fill",
                    badge: String(localized: "Family"),
                    isPrimary: true,
                    isLoading: purchaseManager.purchasingOption == .familyUpgrade || isPurchaseOptionLoading(.familyUpgrade),
                    isDisabled: isPurchaseButtonDisabled(for: .familyUpgrade),
                    action: { purchase(.familyUpgrade) }
                )
                .accessibilityIdentifier(AccessibilityID.Paywall.familyUnlockButton)
            }

            Link("Manage Subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                .font(Typography.caption())

            OnboardingTextAction(
                title: "Restore Purchase",
                isLoading: purchaseManager.isRestoring,
                isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring
            ) {
                restore()
            }
            .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
            .accessibilityLabel("Restore previous purchase")
        }
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
        guard isTrialEligible(option),
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

    private func isTrialEligible(_ option: HealthMdPurchaseOption) -> Bool {
        guard option.isSubscription else { return false }
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices { return true }
        #endif
        return purchaseManager.trialEligibleProductIDs.contains(option.productID)
    }

    /// Yearly plans show their weekly cost; StoreKit supplies the locale-correct format.
    private func weeklyEquivalentPrice(for option: HealthMdPurchaseOption) -> String? {
        guard option == .yearly || option == .familyYearly else { return nil }
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices { return option == .yearly ? "$0.58" : "$0.96" }
        #endif
        guard let product = purchaseManager.product(for: option) else { return nil }
        return (product.price / 52).formatted(product.priceFormatStyle)
    }

    private func purchase(_ option: HealthMdPurchaseOption) {
        Task {
            await purchaseManager.purchase(option, source: .paywall(context))
        }
    }

    private func restore() {
        Task {
            await purchaseManager.restore(source: .paywall(context))
        }
    }

}

// MARK: - Current Plan

private struct PaywallCurrentPlanCard: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            if !reading {
                Image(systemName: icon)
                    .font(Typography.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(minWidth: 28, minHeight: 28)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current plan: \(title). \(detail)")
    }
}

// MARK: - Feature Row

private struct PaywallFeatureRow: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            if !reading {
                Image(systemName: icon)
                    .font(Typography.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// Root access boundary: unpaid users cannot reach tracking/setup through a
/// dismiss gesture or a deep link. Restore and store errors remain available.
struct PurchaseAccessGate<Content: View>: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @ObservedObject private var clinic = ClinicSponsorshipManager.shared
    @State private var showClinicAccess = false
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if purchases.isUnlocked || clinic.status.active || (TestMode.isUITesting && TestMode.purchaseUnlocked) {
                content()
            } else if purchases.isCheckingAccess && !TestMode.isUITesting {
                ProgressView("Checking purchases…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgPrimary)
            } else {
                VStack(spacing: Spacing.s2) {
                    PaywallView(context: .onboarding, allowsDismissal: false)
                    if clinic.status.configured {
                        Button("Have a clinic invitation?") { showClinicAccess = true }
                            .accessibilityIdentifier("clinic-invitation-entry")
                            .padding(.bottom, Spacing.s4)
                    }
                }
            }
        }
        .sheet(isPresented: $showClinicAccess) { ClinicAccessView() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !TestMode.suppressesRuntimeServices else { return }
            Task { await purchases.refreshStatus(); await clinic.refresh() }
        }
    }
}

#Preview {
    PaywallView(context: .export)
}

#endif
