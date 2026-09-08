#if os(iOS)
import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didTrackPaywallShown = false
    @State private var selectedAudience: PaywallPricingAudience = .individual

    private let context: PricingAnalyticsPaywallContext
    private let analytics: PricingAnalyticsClient

    init(
        context: PricingAnalyticsPaywallContext = .export,
        analytics: PricingAnalyticsClient = .shared
    ) {
        self.context = context
        self.analytics = analytics
    }

    private var isManagingPurchase: Bool {
        context == .settings && purchaseManager.isUnlocked
    }

    private var titleText: String {
        isManagingPurchase ? "Purchases & Family" : "Keep Your Health Archive Growing"
    }

    private var subtitleText: String {
        if isManagingPurchase { return currentPlanTitle }
        return "Your \(PurchaseManager.freeExportLimit) free exports are complete. Unlock unlimited private exports, including scheduled runs."
    }

    private var currentPlanTitle: String {
        if let productID = purchaseManager.unlockedProductID,
           let option = HealthMdPurchaseOption.allCases.first(where: { $0.productID == productID }) {
            return "\(option.displayTitle) active"
        }
        if purchaseManager.isLegacyUser { return "Grandfathered Full Access active" }
        return "Full access active"
    }

    private var individualOptions: [HealthMdPurchaseOption] {
        [.individual]
    }

    private var familyOptions: [HealthMdPurchaseOption] {
        [.family]
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
            return "Family Sharing is enabled for this Apple ID."
        }
        if canShowFamilyUpgradeOffer {
            return "Your health archive has unlimited exports. Upgrade to Family Lifetime at upgrade pricing if you want to share Health.md with up to 5 family members."
        }
        return "You have unlimited exports."
    }

    private var currentPlanFamilyFeatureText: String {
        if purchaseManager.isFamilyUnlocked { return "Family Sharing is active" }
        if canShowFamilyUpgradeOffer { return "Family upgrade available" }
        return "Family Sharing is not active"
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            OnboardingPaywallLayout(onDismiss: { dismiss() }, dismissIdentifier: AccessibilityID.Paywall.dismissButton) {
                VStack(spacing: Spacing.s6) {
                    header

                    VStack(spacing: Spacing.s3) {
                        if isManagingPurchase {
                            PaywallFeatureRow(icon: "archivebox.fill", text: "Permanent health archive is active")
                            PaywallFeatureRow(icon: "clock.fill", text: "Unlimited automated daily notes")
                            PaywallFeatureRow(icon: "person.3.fill", text: currentPlanFamilyFeatureText)
                            PaywallFeatureRow(icon: "lock.open.fill", text: "Existing premium access stays grandfathered forever")
                        } else {
                            PaywallFeatureRow(icon: "archivebox.fill", text: "Build a permanent Apple Health archive")
                            PaywallFeatureRow(icon: "calendar.badge.clock", text: "Keep scheduled health notes running without limits")
                            PaywallFeatureRow(icon: "lock.shield", text: "Private local files — no account or health-data cloud")
                            PaywallFeatureRow(icon: "person.3.fill", text: "Individual and Family purchase options")
                        }
                    }

                    ctaSection
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Paywall.view)
        .onAppear { trackPaywallShownOnce() }
        .task { await purchaseManager.loadProductsIfNeeded() }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && !isManagingPurchase { dismiss() }
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

    @ViewBuilder
    private var ctaSection: some View {
        VStack(spacing: Spacing.s3) {
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

            if isManagingPurchase {
                PaywallCurrentPlanCard(
                    title: currentPlanTitle,
                    detail: currentPlanDetail,
                    icon: purchaseManager.isFamilyUnlocked ? "person.3.fill" : "checkmark.seal.fill"
                )

                if canShowFamilyUpgradeOffer {
                    PaywallPurchaseOptionButton(
                        title: "Upgrade to Family Lifetime",
                        subtitle: "Upgrade pricing for existing Lifetime owners",
                        priceLabel: purchaseButtonPriceLabel(for: .familyUpgrade),
                        icon: "person.3.fill",
                        badge: "Family",
                        isPrimary: true,
                        isLoading: purchaseManager.purchasingOption == .familyUpgrade || isPurchaseOptionLoading(.familyUpgrade),
                        isDisabled: isPurchaseButtonDisabled(for: .familyUpgrade),
                        action: { purchase(.familyUpgrade) }
                    )
                    .accessibilityIdentifier(AccessibilityID.Paywall.familyUnlockButton)
                }
            } else {
                PaywallPricingAudiencePicker(selection: $selectedAudience)

                PaywallPlanSection(title: selectedAudience.sectionTitle) {
                    ForEach(selectedOptions) { option in
                        PaywallPurchaseOptionButton(
                            title: option.displayTitle,
                            subtitle: option.displaySubtitle,
                            priceLabel: purchaseButtonPriceLabel(for: option),
                            icon: option.iconName,
                            badge: option.badge,
                            isPrimary: true,
                            isLoading: purchaseManager.purchasingOption == option || isPurchaseOptionLoading(option),
                            isDisabled: isPurchaseButtonDisabled(for: option),
                            action: { purchase(option) }
                        )
                        .accessibilityIdentifier(option == .individual ? AccessibilityID.Paywall.unlockButton : (option == .family ? AccessibilityID.Paywall.familyUnlockButton : "paywall-option-\(option.rawValue)"))
                    }
                }
            }

            OnboardingTextAction(
                title: "Restore Purchase",
                isLoading: purchaseManager.isRestoring,
                isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring
            ) {
                Task {
                    await purchaseManager.restore(source: .paywall(context))
                }
            }
            .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
            .accessibilityLabel("Restore previous purchase")

            if !isManagingPurchase {
                purchaseDisclosure
            }
        }
    }

    private var purchaseDisclosure: some View {
        OnboardingPurchaseDisclosure()
    }

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices {
            switch option {
            case .individual: return "$14.99"
            case .family: return "$24.99"
            case .familyUpgrade: return nil
            }
        }
        #endif

        return purchaseManager.product(for: option)?.displayPrice
    }

    private func purchaseButtonPriceLabel(for option: HealthMdPurchaseOption) -> String? {
        if TestMode.isUITesting { return displayPrice(for: option) }
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices { return displayPrice(for: option) }
        #endif
        if let price = displayPrice(for: option) { return price }
        if isPurchaseOptionLoading(option) { return "Loading…" }
        if purchaseManager.productLoadError != nil || !purchaseManager.productsByID.isEmpty { return "Unavailable" }
        return "Loading…"
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
        analytics.trackPaywallCTATapped(
            context: context,
            productId: option.analyticsProductID,
            quotaState: purchaseManager.analyticsQuotaState
        )
        Task {
            await purchaseManager.purchase(option, source: .paywall(context))
        }
    }

    private func trackPaywallShownOnce() {
        guard !didTrackPaywallShown else { return }
        didTrackPaywallShown = true
        analytics.trackPaywallShown(context: context, quotaState: purchaseManager.analyticsQuotaState)
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

// MARK: - Plan Section

private enum PaywallPricingAudience: String, CaseIterable, Identifiable {
    case individual
    case family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual: return "Individual"
        case .family: return "Family"
        }
    }

    var sectionTitle: String {
        switch self {
        case .individual: return "Individual"
        case .family: return "Family Sharing"
        }
    }
}

private struct PaywallPricingAudiencePicker: View {
    @Binding var selection: PaywallPricingAudience

    var body: some View {
        OnboardingAudienceChoices(choices: PaywallPricingAudience.allCases, selection: selection, title: { $0.title }) { audience in
            withAnimation(AnimationTimings.fast) {
                selection = audience
            }
        }
    }
}

private struct PaywallPlanSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(Typography.label())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textCase(.uppercase)
                .tracking(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Spacing.s3) {
                content()
            }
        }
        .padding(.top, Spacing.s2)
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

#Preview {
    PaywallView(context: .export)
}

#endif
