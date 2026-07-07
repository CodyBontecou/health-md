#if os(macOS)
import SwiftUI
import StoreKit

struct MacPaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didTrackPaywallShown = false
    @State private var selectedAudience: MacPricingAudience = .individual

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
                MacPaywallFeatureRow(icon: "arrow.up.doc.fill",  text: "Unlimited exports")
                MacPaywallFeatureRow(icon: "clock.fill",         text: "Automated scheduled exports")
                MacPaywallFeatureRow(icon: "checkmark.shield",   text: "All future features included")
                MacPaywallFeatureRow(icon: "person.3.fill",      text: "Individual and Family lifetime options")
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
                } else if let productLoadError = purchaseManager.productLoadError, !purchaseManager.isLoadingProducts {
                    VStack(spacing: 6) {
                        Text(productLoadError)
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.error)
                            .multilineTextAlignment(.center)

                        Button {
                            Task { await purchaseManager.loadProductsIfNeeded(force: true) }
                        } label: {
                            Text("Try Again")
                                .font(BrandTypography.detail())
                                .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Try loading purchase options again")
                    }
                }

                MacPricingAudiencePicker(selection: $selectedAudience)

                MacPlanSection(title: selectedAudience.sectionTitle) {
                    ForEach(selectedOptions) { option in
                        MacPurchaseOptionButton(
                            title: option.displayTitle,
                            subtitle: option.displaySubtitle,
                            priceLabel: purchaseButtonPriceLabel(for: option),
                            icon: option.iconName,
                            badge: option.badge,
                            isPrimary: option == .individual || option == .family,
                            isLoading: purchaseManager.purchasingOption == option || isPurchaseOptionLoading(option),
                            isDisabled: isPurchaseButtonDisabled(for: option),
                            action: { Task { await purchaseManager.purchase(option) } }
                        )
                    }
                }

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

                subscriptionDisclosure

                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 420, height: 820)
        .background(Color.bgSecondary)
        .onAppear {
            trackPaywallShownOnce()
        }
        .task { await purchaseManager.loadProductsIfNeeded() }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private var selectedOptions: [HealthMdPurchaseOption] {
        switch selectedAudience {
        case .individual: return [.individual]
        case .family: return [.family]
        }
    }

    // MARK: - Helpers

    private var subscriptionDisclosure: some View {
        VStack(spacing: 6) {
            Text("Lifetime plans are one-time purchases. Subscription options will return after App Store review approves them.")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://health.md.isolated.tech/privacy")!)
            }
            .font(BrandTypography.caption())
            .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lifetime plans are one-time purchases. Subscription options will return after App Store review approves them. Terms and Privacy links are available.")
    }

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        #if DEBUG
        if usesStaticPurchasePrices {
            switch option {
            case .monthly: return "$4.99/mo"
            case .yearly: return "$24.99/yr"
            case .individual: return "$14.99"
            case .familyMonthly: return "$7.99/mo"
            case .familyYearly: return "$39.99/yr"
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
        if usesStaticPurchasePrices { return displayPrice(for: option) }
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
        if usesStaticPurchasePrices { return false }
        #endif
        return purchaseManager.isLoadingProducts
    }

    private func isPurchaseOptionAvailable(_ option: HealthMdPurchaseOption) -> Bool {
        if TestMode.isUITesting { return true }
        #if DEBUG
        if usesStaticPurchasePrices { return true }
        #endif
        return purchaseManager.product(for: option) != nil
    }

    private var usesStaticPurchasePrices: Bool {
        #if DEBUG
        launchValue(for: "-StaticPurchasePrices") == "1"
            || launchValue(for: "-MarketingCapture") == "1"
            || launchValue(for: "-IAPReviewCapture") == "1"
        #else
        false
        #endif
    }

    private func launchValue(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: key), idx + 1 < args.count else { return nil }
        return args[idx + 1]
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

// MARK: - Plan Section

private enum MacPricingAudience: String, CaseIterable, Identifiable {
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

private struct MacPricingAudiencePicker: View {
    @Binding var selection: MacPricingAudience

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MacPricingAudience.allCases) { audience in
                Button {
                    withAnimation(AnimationTimings.fast) {
                        selection = audience
                    }
                } label: {
                    Text(audience.title)
                        .font(BrandTypography.detail())
                        .foregroundStyle(selection == audience ? Color.bgPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(selection == audience ? Color.geistGray1000 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audience.title)
                .accessibilityAddTraits(selection == audience ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan type")
    }
}

private struct MacPlanSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                content()
            }
        }
    }
}

// MARK: - Purchase Option

private struct MacPurchaseOptionButton: View {
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote.weight(.medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(BrandTypography.bodyMedium())
                        if let badge {
                            Text(badge)
                                .font(BrandTypography.caption())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isPrimary ? Color.bgPrimary : Color.accent).opacity(0.12), in: Capsule())
                        }
                    }
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
            .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isPrimary ? Color.accent : Color.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isPrimary ? Color.bgPrimary.opacity(0.12) : Color.borderSubtle, lineWidth: 1)
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
