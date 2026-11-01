#if os(iOS)
import SwiftUI
import StoreKit

/// PaywallG: plan picker plus a pinned glass purchase bar. Every purchase, restore and
/// disclosure path is the one `PurchaseManager` already exposes; this view only lays it out.
struct PaywallView: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedAudience: PaywallPricingAudience = .individual
    @State private var selectedOption: HealthMdPurchaseOption = .yearly

    private let context: PaywallContext
    private let allowsDismissal: Bool

    init(
        context: PaywallContext = .export,
        allowsDismissal: Bool = true
    ) {
        self.context = context
        self.allowsDismissal = allowsDismissal
    }

    // MARK: - State

    private var isManagingPurchase: Bool {
        context == .settings && purchaseManager.isUnlocked
    }

    private var titleText: String {
        isManagingPurchase ? String(localized: "Purchases & Family") : String(localized: "Keep Your Health Archive Growing")
    }

    private var subtitleText: String {
        if isManagingPurchase { return currentPlanTitle }
        return String(localized: "Choose a subscription or Lifetime access to begin your private health archive. Eligible subscriptions include a 7-day free trial.")
    }

    private var currentPlanTitle: String {
        purchaseManager.activePlanTitle
    }

    /// Display order follows the design: recommended plan first, Lifetime last.
    private var individualOptions: [HealthMdPurchaseOption] {
        [.yearly, .weekly, .individual]
    }

    private var familyOptions: [HealthMdPurchaseOption] {
        [.familyYearly, .familyWeekly, .family]
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
            return String(localized: "Family Sharing is enabled for this Apple ID.")
        }
        if canShowFamilyUpgradeOffer {
            return String(localized: "Your health archive has unlimited exports. Upgrade to Family Lifetime at upgrade pricing if you want to share Health.md with up to 5 family members.")
        }
        return String(localized: "You have unlimited exports.")
    }

    /// The option the pinned button buys, or nil when there is nothing to buy here.
    private var checkoutOption: HealthMdPurchaseOption? {
        if isManagingPurchase { return canShowFamilyUpgradeOffer ? .familyUpgrade : nil }
        return selectedOption
    }

    private var isBusy: Bool {
        purchaseManager.isPurchasing || purchaseManager.isRestoring
    }

    private var glassPalette: GlassPalette {
        .resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }

    // MARK: - Body

    var body: some View {
        glassBody
            .glassTheme()
            .accessibilityIdentifier(AccessibilityID.Paywall.view)
            .task { await purchaseManager.loadProductsIfNeeded() }
            .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
                if unlocked && !isManagingPurchase { dismiss() }
            }
            .onChange(of: selectedAudience) { _, audience in
                selectedOption = Self.option(matching: selectedOption, in: audience)
            }
    }

    private var glassBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    header
                    glassError

                    if isManagingPurchase {
                        managementContent
                    } else {
                        planPicker
                        Text("Family plans share access through Apple Family Sharing. Existing Lifetime and earlier permanent access stay valid.")
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(glassPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                        PaywallGlassDisclosure()
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, GlassMetrics.sectionGap)
            }
            .background(glassPalette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
            .toolbar {
                // The access gate presents this without dismissal: it is a hard paywall.
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text(titleText)
                .glassFont(.screenTitle)
                .foregroundStyle(glassPalette.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.Paywall.title)
            Text(subtitleText)
                .glassFont(.body)
                .foregroundStyle(glassPalette.sec)
                .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Errors

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

    // MARK: - Locked: plan picker

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            GlassSegmentedControl(
                segments: PaywallPricingAudience.allCases.map { .init(value: $0, title: $0.title) },
                selection: $selectedAudience
            )
            .disabled(isBusy)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Plan type"))

            VStack(spacing: 10) {
                ForEach(selectedOptions) { option in
                    PaywallPlanCard(
                        title: option.displayTitle,
                        badge: Self.isRecommended(option) ? String(localized: "Best Value") : nil,
                        subtitle: optionSubtitle(for: option),
                        price: purchaseButtonPriceLabel(for: option),
                        isSelected: selectedOption == option,
                        isLoading: isPurchaseOptionLoading(option)
                    ) {
                        selectedOption = option
                    }
                    .disabled(isBusy)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(selectedAudience.sectionTitle))
        }
    }

    // MARK: - Unlocked: plan management

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
                isLoading: isPurchaseOptionLoading(.familyUpgrade),
                action: nil
            )
        }
    }

    // MARK: - Pinned purchase bar

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            if let option = checkoutOption {
                checkoutButton(for: option)
            }
            HStack(spacing: 18) {
                restoreButton
                Link(
                    String(localized: "Manage Subscriptions"),
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

    private func checkoutButton(for option: HealthMdPurchaseOption) -> some View {
        let isInFlight = purchaseManager.purchasingOption == option
        return Button { purchase(option) } label: {
            HStack(spacing: 8) {
                if isInFlight {
                    ProgressView().tint(glassPalette.accentInk)
                }
                Text(checkoutTitle(for: option))
            }
        }
        .buttonStyle(GlassPrimaryButtonStyle())
        .disabled(isPurchaseButtonDisabled(for: option))
        .accessibilityIdentifier(checkoutIdentifier(for: option))
        .accessibilityValue(checkoutAccessibilityValue(for: option))
    }

    private var restoreButton: some View {
        Button {
            Task { await purchaseManager.restore(source: .paywall(context)) }
        } label: {
            HStack(spacing: 6) {
                if purchaseManager.isRestoring {
                    ProgressView().controlSize(.small).tint(glassPalette.accent)
                }
                Text(LocalizedStringKey("Restore Purchase"))
            }
        }
        .buttonStyle(.plain)
        .glassFont(.caption)
        .foregroundStyle(glassPalette.accent)
        .frame(minHeight: GlassMetrics.touchTarget)
        .disabled(isBusy)
        .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
        .accessibilityLabel("Restore previous purchase")
    }

    private func checkoutTitle(for option: HealthMdPurchaseOption) -> String {
        if option == .familyUpgrade { return String(localized: "Upgrade to Family Lifetime") }
        if isTrialEligible(option) { return String(localized: "Start Free Trial") }
        return String(localized: "Continue")
    }

    /// Existing identifiers move to the single purchase button: individual plans use the
    /// unlock button ID, family plans and the Family Lifetime upgrade the family one.
    private func checkoutIdentifier(for option: HealthMdPurchaseOption) -> String {
        option.isFamilyPlan ? AccessibilityID.Paywall.familyUnlockButton : AccessibilityID.Paywall.unlockButton
    }

    private func checkoutAccessibilityValue(for option: HealthMdPurchaseOption) -> String {
        guard let price = purchaseButtonPriceLabel(for: option) else { return option.displayTitle }
        return "\(option.displayTitle), \(price)"
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

    private func isTrialEligible(_ option: HealthMdPurchaseOption) -> Bool {
        option.isSubscription && purchaseManager.trialEligibleProductIDs.contains(option.productID)
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

    private func purchase(_ option: HealthMdPurchaseOption) {
        Task {
            await purchaseManager.purchase(option, source: .paywall(context))
        }
    }

    // MARK: - Selection mapping

    private static func isRecommended(_ option: HealthMdPurchaseOption) -> Bool {
        option == .yearly || option == .familyYearly
    }

    /// Keeps the chosen cadence (yearly, weekly, lifetime) when switching audience.
    private static func option(
        matching option: HealthMdPurchaseOption,
        in audience: PaywallPricingAudience
    ) -> HealthMdPurchaseOption {
        switch (option, audience) {
        case (.weekly, .family), (.familyWeekly, .family): return .familyWeekly
        case (.weekly, .individual), (.familyWeekly, .individual): return .weekly
        case (.individual, .family), (.family, .family), (.familyUpgrade, .family): return .family
        case (.individual, .individual), (.family, .individual), (.familyUpgrade, .individual): return .individual
        case (_, .family): return .familyYearly
        case (_, .individual): return .yearly
        }
    }
}

// MARK: - Plan card

/// A selectable plan in the radio group: radio, title (and badge), terms, price.
private struct PaywallPlanCard: View {
    let title: String
    let badge: String?
    let subtitle: String
    let price: String?
    let isSelected: Bool
    let isLoading: Bool
    /// Nil renders the card as a non-interactive summary (the pinned button buys it).
    let action: (() -> Void)?

    @Environment(\.glassPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    private let radius: CGFloat = 22

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        } else {
            card.accessibilityElement(children: .combine)
        }
    }

    private var card: some View {
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
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(isEnabled ? 1 : 0.6)
    }
}

// MARK: - Disclosure

/// Glass rendering of `OnboardingPurchaseDisclosure`: identical required terms copy and links.
private struct PaywallGlassDisclosure: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eligible subscriptions include a 7-day free trial, then renew automatically at the displayed price unless canceled at least 24 hours before the trial or current period ends. Payment is charged to your Apple ID. Manage or cancel in App Store subscriptions. Lifetime plans are charged immediately as one-time purchases with no trial. Deleting the app or buying Lifetime does not cancel an existing subscription.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            // Keep these independent links, including in VoiceOver traversal.
            HStack(spacing: 18) {
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    linkLabel("Terms")
                }
                Link(destination: URL(string: "https://healthmd.app/privacy-policy.html")!) {
                    linkLabel("Privacy")
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    private func linkLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .glassFont(.caption)
            .foregroundStyle(palette.accent)
            .underline()
            .frame(minHeight: GlassMetrics.touchTarget)
    }
}

private enum PaywallPricingAudience: String, CaseIterable, Identifiable {
    case individual
    case family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual: return String(localized: "Individual")
        case .family: return String(localized: "Family")
        }
    }

    var sectionTitle: String {
        switch self {
        case .individual: return String(localized: "Individual")
        case .family: return String(localized: "Family Sharing")
        }
    }
}

/// Root access boundary: unpaid users cannot reach tracking/setup through a
/// dismiss gesture or a deep link. Restore and store errors remain available.
struct PurchaseAccessGate<Content: View>: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if purchases.isUnlocked || (TestMode.isUITesting && TestMode.purchaseUnlocked) {
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
            Task { await purchases.refreshStatus() }
        }
    }
}

#Preview {
    PaywallView(context: .export)
}

#endif
