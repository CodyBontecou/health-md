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
                            Text("Unlock Health.md")
                                .font(Typography.displayMedium())
                                .foregroundStyle(Color.textPrimary)
                                .accessibilityIdentifier(AccessibilityID.Paywall.title)

                            Text("You've used your 3 free exports")
                                .font(Typography.body())
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // MARK: - Features
                    VStack(spacing: Spacing.sm) {
                        PaywallFeatureRow(icon: "arrow.up.doc.fill",  text: "Unlimited exports, forever")
                        PaywallFeatureRow(icon: "clock.fill",         text: "Automated scheduled exports")
                        PaywallFeatureRow(icon: "checkmark.shield",   text: "All future features included")
                        PaywallFeatureRow(icon: "lock.open.fill",     text: "One-time payment — no subscription")
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
            if unlocked { dismiss() }
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
