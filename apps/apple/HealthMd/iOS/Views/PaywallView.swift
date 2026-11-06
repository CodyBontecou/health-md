#if os(iOS)
import SwiftUI
import StoreKit

/// Locked: the Signal purchase story (`SignalPaywallCarousel`) in the glass theme.
/// Unlocked from Settings: glass plan management with a pinned purchase bar. Every
/// purchase, restore and disclosure path is the one `PurchaseManager` already exposes.
struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @ObservedObject private var clinic = ClinicSponsorshipManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showClinicAccess = false

    private let context: PaywallContext
    private let allowsDismissal: Bool
    /// Lets Clinic access offer the user's automations as the clinic destination.
    private let profileCoordinator: ExportProfileCoordinator?

    init(
        context: PaywallContext = .export,
        allowsDismissal: Bool = true,
        profileCoordinator: ExportProfileCoordinator? = nil
    ) {
        self.context = context
        self.allowsDismissal = allowsDismissal
        self.profileCoordinator = profileCoordinator
    }

    // MARK: - State

    private var isManagingPurchase: Bool {
        context == .settings && purchaseManager.isUnlocked
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

    private var isBusy: Bool {
        purchaseManager.isPurchasing || purchaseManager.isRestoring
    }

    private var glassPalette: GlassPalette {
        .resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }

    // MARK: - Body

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
        .glassTheme()
        // A container keeps child identifiers (restore, purchase, dismiss) addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Paywall.view)
        .task { await purchaseManager.loadProductsIfNeeded() }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && !isManagingPurchase { dismiss() }
        }
        .sheet(isPresented: $showClinicAccess) {
            NavigationStack {
                GlassClinicAccessScreen(coordinator: profileCoordinator)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Done")) { showClinicAccess = false }
                        }
                    }
            }
            .glassTheme()
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

    /// Store errors, catalog retry and the clinic invitation entry, shown in the carousel footer.
    private var purchaseStatus: AnyView {
        AnyView(VStack(alignment: .leading, spacing: 4) {
            glassError
            if ClinicAccessFeature.isEnabled && clinic.status.configured && !clinic.status.active {
                Button(String(localized: "Have a clinic invitation?")) { showClinicAccess = true }
                    .buttonStyle(.plain)
                    .glassFont(.caption)
                    .foregroundStyle(glassPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                    .accessibilityIdentifier("clinic-invitation-entry")
            }
        })
    }

    // MARK: - Unlocked: plan management

    private var managementLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    header
                    glassError
                    managementContent
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, GlassMetrics.sectionGap)
            }
            .background(glassPalette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
            .toolbar {
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close")) { dismiss() }
                            .tint(glassPalette.accent)
                            .accessibilityIdentifier(AccessibilityID.Paywall.dismissButton)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text(String(localized: "Purchases & Family"))
                .glassFont(.screenTitle)
                .foregroundStyle(glassPalette.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.Paywall.title)
            Text(currentPlanTitle)
                .glassFont(.body)
                .foregroundStyle(glassPalette.sec)
                .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder private var glassError: some View {
        if let error = purchaseManager.purchaseError {
            GlassBanner(title: error, systemImage: "exclamationmark.triangle", tone: .warning)
                .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)
        } else if let productLoadError = purchaseManager.productLoadError, !purchaseManager.isLoadingProducts {
            VStack(alignment: .leading, spacing: 4) {
                GlassBanner(title: productLoadError, systemImage: "exclamationmark.triangle", tone: .warning)
                    .accessibilityIdentifier(AccessibilityID.Paywall.errorMessage)
                Button(LocalizedStringKey("Try Again")) {
                    Task { await purchaseManager.loadProductsIfNeeded(force: true) }
                }
                .buttonStyle(.plain)
                .glassFont(.caption)
                .foregroundStyle(glassPalette.accent)
                .padding(.horizontal, 4)
                .frame(minHeight: GlassMetrics.touchTarget)
                .accessibilityLabel("Try loading purchase options again")
            }
        }
    }

    @ViewBuilder private var managementContent: some View {
        GlassBanner(
            title: currentPlanTitle,
            message: currentPlanDetail,
            systemImage: purchaseManager.isFamilyUnlocked ? "person.3.fill" : "checkmark.seal.fill",
            tone: .success
        )
        if purchaseManager.canShowPermanentAccessNotice {
            GlassBanner(
                title: String(localized: "Your existing permanent access remains valid"),
                systemImage: "lock.open.fill",
                tone: .success
            )
        }
        if canShowFamilyUpgradeOffer {
            PaywallPlanCard(
                title: String(localized: "Upgrade to Family Lifetime"),
                badge: HealthMdPurchaseOption.familyUpgrade.badge,
                subtitle: String(localized: "Upgrade pricing for existing Lifetime owners"),
                price: purchaseButtonPriceLabel(for: .familyUpgrade),
                isSelected: true,
                isLoading: isPurchaseOptionLoading(.familyUpgrade)
            )
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            if canShowFamilyUpgradeOffer {
                Button { purchase(.familyUpgrade) } label: {
                    HStack(spacing: 8) {
                        if purchaseManager.purchasingOption == .familyUpgrade {
                            ProgressView().tint(glassPalette.accentInk)
                        }
                        Text(String(localized: "Upgrade to Family Lifetime"))
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(isPurchaseButtonDisabled(for: .familyUpgrade))
                .accessibilityIdentifier(AccessibilityID.Paywall.familyUnlockButton)
            }
            HStack(spacing: 18) {
                Button(action: restore) {
                    HStack(spacing: 6) {
                        if purchaseManager.isRestoring {
                            ProgressView().controlSize(.small).tint(glassPalette.accent)
                        }
                        Text(String(localized: "Restore"))
                    }
                }
                .buttonStyle(.plain)
                .glassFont(.caption)
                .foregroundStyle(glassPalette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)
                .disabled(isBusy)
                .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
                .accessibilityLabel("Restore previous purchase")
                Link(
                    String(localized: "Manage subscriptions"),
                    destination: URL(string: "https://apps.apple.com/account/subscriptions")!
                )
                .glassFont(.caption)
                .foregroundStyle(glassPalette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, GlassMetrics.screenMargin)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background {
            Color.clear
                .glassSurface(in: Rectangle(), style: .strong)
                .overlay(alignment: .top) {
                    Rectangle().fill(glassPalette.edge).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Pricing

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
        if isPurchaseOptionLoading(option) { return String(localized: "Loading…") }
        if purchaseManager.productLoadError != nil || !purchaseManager.productsByID.isEmpty { return String(localized: "Unavailable") }
        return String(localized: "Loading…")
    }

    private func isPurchaseButtonDisabled(for option: HealthMdPurchaseOption) -> Bool {
        isBusy
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

// MARK: - Plan card

/// The Family Lifetime upgrade summary in plan management (the pinned button buys it).
private struct PaywallPlanCard: View {
    let title: String
    let badge: String?
    let subtitle: String
    let price: String?
    let isSelected: Bool
    let isLoading: Bool

    @Environment(\.glassPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    private let radius: CGFloat = 22

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(isSelected ? palette.accent : palette.muted, lineWidth: isSelected ? 7 : 2)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .fontWeight(.bold)
                        .glassFont(.navTitle)
                        .foregroundStyle(palette.text)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.accentInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(palette.accent))
                    }
                }
                Text(subtitle)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView().controlSize(.small)
            } else if let price {
                Text(price)
                    .fontWeight(.bold)
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowWithSubtitleMinHeight, alignment: .leading)
        .glassSurface(cornerRadius: radius)
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isSelected ? palette.accent : Color.clear, lineWidth: 2)
        }
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

/// Root access boundary: unpaid users cannot reach tracking/setup through a
/// dismiss gesture or a deep link. Restore, store errors and clinic enrollment remain available.
struct PurchaseAccessGate<Content: View>: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @ObservedObject private var clinic = ClinicSponsorshipManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if purchases.isUnlocked || clinic.status.active || (TestMode.isUITesting && TestMode.purchaseUnlocked) {
                content()
            } else if purchases.isCheckingAccess && !TestMode.isUITesting {
                ProgressView("Checking purchases…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
                            .bg.ignoresSafeArea()
                    )
            } else {
                PaywallView(context: .onboarding, allowsDismissal: false)
            }
        }
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
