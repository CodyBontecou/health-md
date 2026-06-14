#if os(macOS)
import SwiftUI
import StoreKit

struct MacPaywallView: View {
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

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            VStack(spacing: 12) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.accent.opacity(0.3), radius: 16, x: 0, y: 8)
                    .padding(.top, 32)

                VStack(spacing: 6) {
                    Text("Unlock Health.md")
                        .font(BrandTypography.heading())
                        .foregroundStyle(Color.textPrimary)

                    Text("You've used your 3 free exports.")
                        .font(BrandTypography.body())
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            // MARK: - Features
            VStack(spacing: 8) {
                MacPaywallFeatureRow(icon: "arrow.up.doc.fill",  text: "Unlimited exports, forever")
                MacPaywallFeatureRow(icon: "clock.fill",         text: "Automated scheduled exports")
                MacPaywallFeatureRow(icon: "checkmark.shield",   text: "All future features included")
                MacPaywallFeatureRow(icon: "lock.open.fill",     text: "One-time payment — no subscription")
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer()

            // MARK: - CTA
            VStack(spacing: 10) {
                if let error = purchaseManager.purchaseError {
                    Text(error)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.error)
                        .multilineTextAlignment(.center)
                }

                MacPurchaseOptionButton(
                    title: "Individual Lifetime",
                    subtitle: "Unlock on your Apple ID",
                    priceLabel: displayPrice(for: .individual),
                    icon: "person.fill",
                    isPrimary: true,
                    isLoading: purchaseManager.purchasingOption == .individual,
                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                    action: {
                        Task { await purchaseManager.purchase(.individual) }
                    }
                )

                MacPurchaseOptionButton(
                    title: "Family Lifetime",
                    subtitle: "Share with up to 5 family members",
                    priceLabel: displayPrice(for: .family),
                    icon: "person.3.fill",
                    isPrimary: false,
                    isLoading: purchaseManager.purchasingOption == .family,
                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                    action: {
                        Task { await purchaseManager.purchase(.family) }
                    }
                )

                Button {
                    Task { await purchaseManager.restore() }
                } label: {
                    HStack(spacing: 4) {
                        if purchaseManager.isRestoring {
                            ProgressView().controlSize(.mini)
                        }
                        Text("Restore Purchase")
                            .font(BrandTypography.detail())
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                .accessibilityLabel("Restore previous purchase")

                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 380, height: 540)
        .background(Color.bgSecondary)
        .onAppear {
            trackPaywallShownOnce()
        }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    // MARK: - Helpers

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        purchaseManager.product(for: option)?.displayPrice
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

private struct MacPurchaseOptionButton: View {
    let title: String
    let subtitle: String
    let priceLabel: String?
    let icon: String
    let isPrimary: Bool
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote.weight(.medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BrandTypography.bodyMedium())
                    Text(subtitle)
                        .font(BrandTypography.caption())
                        .opacity(0.78)
                }

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(priceLabel ?? "—")
                        .font(BrandTypography.bodyMedium())
                }
            }
            .foregroundStyle(isPrimary ? .white : Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isPrimary ? Color.accent : Color.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isPrimary ? Color.white.opacity(0.12) : Color.borderSubtle, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let priceLabel {
            return "\(title), \(subtitle), \(priceLabel)"
        }
        return "\(title), \(subtitle)"
    }
}

// MARK: - Feature Row

private struct MacPaywallFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accent)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(BrandTypography.body())
                .foregroundStyle(Color.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#endif
