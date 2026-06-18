#if os(iOS)
import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var appIconSize: CGFloat = 72
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
        if isManagingPurchase {
            return currentPlanTitle
        }
        return "You've used your 3 free exports"
    }

    private var currentPlanTitle: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Lifetime active"
        }
        if purchaseManager.isIndividualUnlocked {
            return "Individual Lifetime active"
        }
        if purchaseManager.isLegacyUser {
            return "Full access active"
        }
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
        if purchaseManager.isFamilyUnlocked {
            return "Family Sharing is active"
        }
        if canShowFamilyUpgradeOffer {
            return "Family upgrade available"
        }
        return "Family Sharing is not active"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Header
                    VStack(spacing: Spacing.lg) {
                        ZStack {
                            Image("AppIconImage")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: appIconSize, height: appIconSize)
                                .blur(radius: 28)
                                .opacity(0.4)
                                .accessibilityHidden(true)

                            Image("AppIconImage")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: appIconSize, height: appIconSize)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.25), Color.clear],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: Color.accent.opacity(0.35), radius: 20, x: 0, y: 10)
                        }
                        .padding(.top, Spacing.xl + Spacing.sm)

                        VStack(spacing: Spacing.xs) {
                            Text(titleText)
                                .font(Typography.displayMedium())
                                .foregroundStyle(Color.textPrimary)
                                .accessibilityIdentifier(AccessibilityID.Paywall.title)

                            Text(subtitleText)
                                .font(Typography.body())
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // MARK: - Features
                    VStack(spacing: Spacing.sm) {
                        if isManagingPurchase {
                            PaywallFeatureRow(icon: "checkmark.seal.fill", text: "Unlimited exports are active")
                            PaywallFeatureRow(icon: "clock.fill",          text: "Automated scheduled exports included")
                            PaywallFeatureRow(icon: "person.3.fill",       text: currentPlanFamilyFeatureText)
                            PaywallFeatureRow(icon: "lock.open.fill",      text: "One-time payment — no subscription")
                        } else {
                            PaywallFeatureRow(icon: "arrow.up.doc.fill",  text: "Unlimited exports, forever")
                            PaywallFeatureRow(icon: "clock.fill",         text: "Automated scheduled exports")
                            PaywallFeatureRow(icon: "checkmark.shield",   text: "All future features included")
                            PaywallFeatureRow(icon: "lock.open.fill",     text: "One-time payment — no subscription")
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xl)

                    Spacer(minLength: Spacing.xl)

                    // MARK: - CTA
                    VStack(spacing: Spacing.md) {
                        if let error = purchaseManager.purchaseError {
                            Text(error)
                                .font(.caption)
                                // Restore "not found" messages are informational — use a
                                // softer muted colour. True errors (network, verification)
                                // stay red so the user knows something went wrong.
                                .foregroundStyle(
                                    error.contains("cody@isolated.tech")
                                        ? Color.textMuted
                                        : Color.error
                                )
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.md)
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
                                    badge: "FAMILY",
                                    isPrimary: true,
                                    isLoading: purchaseManager.purchasingOption == .familyUpgrade,
                                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                                    action: {
                                        Task { await purchaseManager.purchase(.familyUpgrade) }
                                    }
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
                                action: {
                                    Task { await purchaseManager.purchase(.individual) }
                                }
                            )
                            .accessibilityIdentifier(AccessibilityID.Paywall.unlockButton)

                            PaywallPurchaseOptionButton(
                                title: "Family Lifetime",
                                subtitle: "Share with up to 5 family members",
                                priceLabel: displayPrice(for: .family),
                                icon: "person.3.fill",
                                badge: "FAMILY",
                                isPrimary: false,
                                isLoading: purchaseManager.purchasingOption == .family,
                                isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                                action: {
                                    Task { await purchaseManager.purchase(.family) }
                                }
                            )
                            .accessibilityIdentifier(AccessibilityID.Paywall.familyUnlockButton)
                        }

                        Button {
                            Task { await purchaseManager.restore() }
                        } label: {
                            HStack(spacing: 6) {
                                if purchaseManager.isRestoring {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(Color.textMuted)
                                }
                                Text("Restore Purchase")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                        .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
                        .accessibilityLabel("Restore previous purchase")
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
                .frame(maxWidth: .infinity)
            }

            // MARK: - Dismiss Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textMuted)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.lg)
            .padding(.trailing, Spacing.lg)
            .accessibilityIdentifier(AccessibilityID.Paywall.dismissButton)
            .accessibilityLabel("Dismiss")
        }
        .accessibilityIdentifier(AccessibilityID.Paywall.view)
        .onAppear {
            trackPaywallShownOnce()
        }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && !isManagingPurchase { dismiss() }
        }
    }

    // MARK: - Helpers

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        if let displayPrice = purchaseManager.product(for: option)?.displayPrice {
            return displayPrice
        }

        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices {
            switch option {
            case .individual: return "$14.99"
            case .family: return "$24.99"
            case .familyUpgrade: return "$9.99"
            }
        }
        #endif

        return nil
    }

    private func trackPaywallShownOnce() {
        guard !didTrackPaywallShown else { return }
        didTrackPaywallShown = true
        analytics.trackPaywallShown(
            context: context,
            quotaState: purchaseManager.analyticsQuotaState
        )
    }
}

// MARK: - Current Plan

private struct PaywallCurrentPlanCard: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accent.opacity(0.28), lineWidth: 1)
        )
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
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isPrimary ? Color.white : Color.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isPrimary ? Color.white : Color.textPrimary)

                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(isPrimary ? Color.white : Color.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill((isPrimary ? Color.white : Color.accent).opacity(0.14))
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isPrimary ? Color.white.opacity(0.82) : Color.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isPrimary ? .white : Color.accent))
                        .scaleEffect(0.85)
                } else {
                    Text(priceLabel ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isPrimary ? Color.white : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(backgroundShape)
            .overlay(borderShape)
            .opacity(isDisabled ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isDisabled ? "Purchase is currently unavailable" : "Double tap to purchase")
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isPrimary ? Color.accent.opacity(0.78) : Color.clear)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isPrimary ? Color.white.opacity(0.1) : Color.accent.opacity(0.28),
                lineWidth: 1
            )
    }

    private var accessibilityText: String {
        if let priceLabel {
            return "\(title), \(subtitle), \(priceLabel)"
        }
        return "\(title), \(subtitle)"
    }
}

// MARK: - Feature Row

private struct PaywallFeatureRow: View {
    let icon: String
    let text: String
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.accent)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview {
    PaywallView(context: .export)
}

#endif
