#if os(iOS)
import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didTrackPaywallShown = false

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
        isManagingPurchase ? "Purchases & Family" : "Unlock Health.md"
    }

    private var subtitleText: String {
        if isManagingPurchase { return currentPlanTitle }
        return "You've used your 3 free exports"
    }

    private var currentPlanTitle: String {
        if purchaseManager.isFamilyUnlocked { return "Family Lifetime active" }
        if purchaseManager.isIndividualUnlocked { return "Individual Lifetime active" }
        if purchaseManager.isLegacyUser { return "Full access active" }
        return "Full access active"
    }

    private var canShowFamilyUpgradeOffer: Bool {
        isManagingPurchase && purchaseManager.canBuyFamilyUpgrade
    }

    private var currentPlanDetail: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Sharing is enabled for this Apple ID."
        }
        if canShowFamilyUpgradeOffer {
            return "You have unlimited exports. Upgrade to Family Lifetime at upgrade pricing if you want to share Health.md with up to 5 family members."
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
                            PaywallFeatureRow(icon: "checkmark.seal.fill", text: "Unlimited exports are active")
                            PaywallFeatureRow(icon: "clock.fill", text: "Automated scheduled exports included")
                            PaywallFeatureRow(icon: "person.3.fill", text: currentPlanFamilyFeatureText)
                            PaywallFeatureRow(icon: "lock.open.fill", text: "One-time payment — no subscription")
                        } else {
                            PaywallFeatureRow(icon: "arrow.up.doc.fill", text: "Unlimited exports, forever")
                            PaywallFeatureRow(icon: "clock.fill", text: "Automated scheduled exports")
                            PaywallFeatureRow(icon: "checkmark.shield", text: "All future features included")
                            PaywallFeatureRow(icon: "lock.open.fill", text: "One-time payment — no subscription")
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
                        priceLabel: displayPrice(for: .familyUpgrade),
                        icon: "person.3.fill",
                        badge: "Family",
                        isPrimary: true,
                        isLoading: purchaseManager.purchasingOption == .familyUpgrade,
                        isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                        action: { Task { await purchaseManager.purchase(.familyUpgrade) } }
                    )
                    .accessibilityIdentifier(AccessibilityID.Paywall.familyUnlockButton)
                }
            } else {
                PaywallPurchaseOptionButton(
                    title: "Individual Lifetime",
                    subtitle: "Unlock on your Apple ID",
                    priceLabel: displayPrice(for: .individual),
                    icon: "person.fill",
                    badge: nil,
                    isPrimary: true,
                    isLoading: purchaseManager.purchasingOption == .individual,
                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                    action: { Task { await purchaseManager.purchase(.individual) } }
                )
                .accessibilityIdentifier(AccessibilityID.Paywall.unlockButton)

                PaywallPurchaseOptionButton(
                    title: "Family Lifetime",
                    subtitle: "Share with up to 5 family members",
                    priceLabel: displayPrice(for: .family),
                    icon: "person.3.fill",
                    badge: "Family",
                    isPrimary: false,
                    isLoading: purchaseManager.purchasingOption == .family,
                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                    action: { Task { await purchaseManager.purchase(.family) } }
                )
                .accessibilityIdentifier(AccessibilityID.Paywall.familyUnlockButton)
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
        }
    }

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        if let displayPrice = purchaseManager.product(for: option)?.displayPrice {
            return displayPrice
        }

        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices {
            switch option {
            case .individual: return "$14.99"
            case .family: return "$24.99"
            case .familyUpgrade: return nil
            }
        }
        #endif

        return nil
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
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isPrimary ? Color.bgPrimary : Color.accent))
                        .scaleEffect(0.85)
                        .accessibilityHidden(true)
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
        .accessibilityHint(isDisabled ? "Purchase is currently unavailable" : "Double tap to purchase")
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
