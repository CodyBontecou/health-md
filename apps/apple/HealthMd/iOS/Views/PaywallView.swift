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
        return "Your 3 free exports are complete. Unlock unlimited private exports and daily automation."
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
        ZStack(alignment: .topTrailing) {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.s8) {
                    header

                    VStack(spacing: Spacing.s3) {
                        if isManagingPurchase {
                            PaywallFeatureRow(icon: "archivebox.fill", text: "Permanent health archive is active")
                            PaywallFeatureRow(icon: "clock.fill", text: "Automated daily notes included")
                            PaywallFeatureRow(icon: "person.3.fill", text: currentPlanFamilyFeatureText)
                            PaywallFeatureRow(icon: "lock.open.fill", text: "Existing premium access stays grandfathered forever")
                        } else {
                            PaywallFeatureRow(icon: "archivebox.fill", text: "Build a permanent Apple Health archive")
                            PaywallFeatureRow(icon: "calendar.badge.clock", text: "Wake up to fresh daily health notes")
                            PaywallFeatureRow(icon: "lock.shield", text: "Private local files — no account or health-data cloud")
                            PaywallFeatureRow(icon: "person.3.fill", text: "Individual and Family purchase options")
                        }
                    }

                    ctaSection
                }
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s16)
                .padding(.bottom, Spacing.s10)
                .frame(maxWidth: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.s4)
            .padding(.trailing, Spacing.s4)
            .accessibilityIdentifier(AccessibilityID.Paywall.dismissButton)
            .accessibilityLabel("Dismiss")
        }
        .accessibilityIdentifier(AccessibilityID.Paywall.view)
        .onAppear { trackPaywallShownOnce() }
        .task { await purchaseManager.loadProductsIfNeeded() }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && !isManagingPurchase { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.s6) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(spacing: Spacing.s2) {
                Text(titleText)
                    .font(Typography.displayLarge())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .tracking(-1)
                    .accessibilityIdentifier(AccessibilityID.Paywall.title)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitleText)
                    .font(Typography.bodyLarge())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)
            }
        }
    }

    @ViewBuilder
    private var ctaSection: some View {
        VStack(spacing: Spacing.s3) {
            if let error = purchaseManager.purchaseError {
                Text(error)
                    .font(Typography.caption())
                    .foregroundStyle(error.contains("cody@isolated.tech") ? Color.textMuted : Color.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.s3)
                    .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)
            } else if let productLoadError = purchaseManager.productLoadError, !purchaseManager.isLoadingProducts {
                VStack(spacing: Spacing.s2) {
                    Text(productLoadError)
                        .font(Typography.caption())
                        .foregroundStyle(Color.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.s3)
                        .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)

                    Button {
                        Task { await purchaseManager.loadProductsIfNeeded(force: true) }
                    } label: {
                        Text("Try Again")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain)
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
                        action: { Task { await purchaseManager.purchase(.familyUpgrade) } }
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
                            action: { Task { await purchaseManager.purchase(option) } }
                        )
                        .accessibilityIdentifier(option == .individual ? AccessibilityID.Paywall.unlockButton : (option == .family ? AccessibilityID.Paywall.familyUnlockButton : "paywall-option-\(option.rawValue)"))
                    }
                }
            }

            Button {
                Task { await purchaseManager.restore() }
            } label: {
                HStack(spacing: Spacing.s2) {
                    if purchaseManager.isRestoring {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }
                    Text("Restore Purchase")
                        .font(Typography.bodyEmphasis())
                }
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
            .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
            .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
            .accessibilityLabel("Restore previous purchase")

            if !isManagingPurchase {
                purchaseDisclosure
            }
        }
    }

    private var purchaseDisclosure: some View {
        VStack(spacing: Spacing.s2) {
            Text("Lifetime plans are one-time purchases charged to your Apple ID.")
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s4) {
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://healthmd.app/privacy-policy.html")!)
            }
            .font(Typography.caption())
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.top, Spacing.s1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lifetime plans are one-time purchases charged to your Apple ID. Terms and Privacy links are available.")
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

    private func trackPaywallShownOnce() {
        guard !didTrackPaywallShown else { return }
        didTrackPaywallShown = true
        analytics.trackPaywallShown(context: context, quotaState: purchaseManager.analyticsQuotaState)
    }
}

// MARK: - Current Plan

private struct PaywallCurrentPlanCard: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)

                Text(detail)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.s2)
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
        HStack(spacing: 0) {
            ForEach(PaywallPricingAudience.allCases) { audience in
                Button {
                    withAnimation(AnimationTimings.fast) {
                        selection = audience
                    }
                } label: {
                    Text(audience.title)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(selection == audience ? Color.bgPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selection == audience ? Color.geistGray1000 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audience.title)
                .accessibilityAddTraits(selection == audience ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan type")
    }
}

private struct PaywallPlanSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(Typography.label())
                .foregroundStyle(Color.textMuted)
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

// MARK: - Purchase Option

private struct PaywallPurchaseOptionButton: View {
    let title: String
    let subtitle: String
    let priceLabel: String?
    let icon: String
    let badge: String?
    let isPrimary: Bool
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(isPrimary ? Color.bgPrimary : Color.accent)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    HStack(spacing: Spacing.s2) {
                        Text(title)
                            .font(Typography.headline())
                            .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)

                        if let badge {
                            Text(badge)
                                .font(Typography.monoCaptionEmphasis())
                                .foregroundStyle(isPrimary ? Color.bgPrimary : Color.accent)
                                .padding(.horizontal, Spacing.s2)
                                .padding(.vertical, 2)
                                .background((isPrimary ? Color.bgPrimary : Color.accent).opacity(0.12), in: Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(Typography.body())
                        .foregroundStyle(isPrimary ? Color.bgPrimary.opacity(0.78) : Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.s2)

                if isLoading {
                    HStack(spacing: Spacing.s2) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isPrimary ? Color.bgPrimary : Color.accent))
                            .scaleEffect(0.85)
                            .accessibilityHidden(true)
                        Text(priceLabel ?? "Loading…")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    Text(priceLabel ?? "—")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity)
            .background(isPrimary ? Color.geistGray1000 : Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(isPrimary ? Color.geistGray1000 : Color.borderSubtle, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        if !isDisabled { return "Double tap to purchase" }
        return isLoading ? "Purchase options are loading" : "Purchase is currently unavailable"
    }

    private var accessibilityText: String {
        if let priceLabel { return "\(title), \(subtitle), \(priceLabel)" }
        return "\(title), \(subtitle)"
    }
}

// MARK: - Feature Row

private struct PaywallFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
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
