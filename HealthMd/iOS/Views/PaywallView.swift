#if os(iOS)
import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Header
                VStack(spacing: Spacing.lg) {
                    ZStack {
                        Image("AppIconImage")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .blur(radius: 28)
                            .opacity(0.4)
                            .accessibilityHidden(true)

                        Image("AppIconImage")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
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

                        Text("You've used your 3 free exports")
                            .font(Typography.body())
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
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

                Spacer()

                // MARK: - CTA
                VStack(spacing: Spacing.md) {
                    if let error = purchaseManager.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.md)
                    }

                    PrimaryButton(
                        priceButtonLabel(purchaseManager.product),
                        icon: "lock.open.fill",
                        isLoading: purchaseManager.isPurchasing,
                        isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                        action: {
                            Task { await purchaseManager.purchase() }
                        }
                    )

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
                    .accessibilityLabel("Restore previous purchase")
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }

            // MARK: - Dismiss Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
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
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.lg)
            .padding(.trailing, Spacing.lg)
            .accessibilityLabel("Dismiss")
        }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .preferredColorScheme(.dark)
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

private struct PaywallFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)

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
    PaywallView()
}

#endif
