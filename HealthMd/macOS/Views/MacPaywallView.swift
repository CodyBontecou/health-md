#if os(macOS)
import SwiftUI
import StoreKit

struct MacPaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

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

                Button {
                    Task { await purchaseManager.purchase() }
                } label: {
                    HStack(spacing: 6) {
                        if purchaseManager.isPurchasing {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 13, weight: .medium))
                        }
                        Text(priceButtonLabel(purchaseManager.product))
                            .font(BrandTypography.bodyMedium())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                .accessibilityLabel(priceButtonLabel(purchaseManager.product))

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
        .frame(width: 360, minHeight: 460)
        .background(Color.bgSecondary)
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    // MARK: - Helpers

    private func priceButtonLabel(_ product: Product?) -> String {
        if let product {
            return "Unlock for \(product.displayPrice)"
        }
        return "Unlock Full Access"
    }
}

// MARK: - Feature Row

private struct MacPaywallFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
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
