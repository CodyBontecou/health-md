#if os(iOS)
import SwiftUI

/// A component gallery, NOT the seven-step onboarding state machine or a billing
/// simulator. All actions are counters/local state; even legal URLs are handled
/// locally. No PurchaseManager, HealthKit, analytics or folder services are linked.
struct OnboardingA11yScenario: View {
    @Environment(\.locale) private var locale
    @State private var page = 0
    @State private var count = 0
    @State private var connected = false
    @State private var folderChosen = false
    @State private var audience: Audience = .individual
    @State private var busy = false

    private enum Audience: Int, CaseIterable, Identifiable {
        case individual, family
        var id: Self { self }
    }

    private var offer: (title: String, detail: String, price: String) {
        switch locale.language.languageCode?.identifier {
        case "de": return ("Lebenslanger Familienzugang", "Unbegrenzte private Exporte mit bis zu fünf Familienmitgliedern teilen.", "1.234.567,89 €")
        case "ar": return ("وصول عائلي مدى الحياة", "شارك عمليات التصدير الخاصة غير المحدودة مع ما يصل إلى خمسة أفراد من العائلة.", "١٬٢٣٤٬٥٦٧٫٨٩ ر.س.‏")
        case "ja": return ("ファミリー永久アクセス", "最大5人の家族と無制限のプライベート書き出しを共有できます。", "￥1,234,567")
        default: return ("Family Lifetime", "Share unlimited private exports with up to 5 family members.", "US$ 1,234.99")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: String(count))
                .font(Typography.label())
                .foregroundStyle(Color.textSecondary)
                .accessibilityIdentifier("a11y.onboarding.count")
            if page == 2 {
                paywall
            } else {
                OnboardingPageLayout(pageID: page) {
                    OnboardingNavigationHeader(current: page + 1, total: 7, canGoBack: true, showsMark: true) {
                        count += 16384
                        page = 0
                    }
                } content: {
                    if page == 0 { setupComponents } else { offerComponents }
                } footer: {
                    if page == 0 {
                        VStack(spacing: Spacing.s3) {
                            OnboardingPrimaryButton(title: connected ? "Continue Setup" : "Connect Apple Health", imageAsset: "AppleHealthIcon") {
                                if connected { page = 1 } else { connected = true; count += 1 }
                            }
                            .accessibilityIdentifier("a11y.onboarding.primary")
                            OnboardingSecondaryButton(title: "Skip for Now", icon: "forward") {
                                count += 128
                                page = 1
                            }
                            .accessibilityIdentifier("a11y.onboarding.skip")
                        }
                    } else {
                        VStack(spacing: Spacing.s3) {
                            OnboardingSecondaryButton(title: "Try 10 Free Exports", icon: "arrow.right") { count += 64 }
                                .accessibilityIdentifier("a11y.onboarding.free")
                            OnboardingSecondaryButton(title: "Show Paywall Components", icon: "rectangle.on.rectangle") { page = 2 }
                                .accessibilityIdentifier("a11y.onboarding.show-paywall")
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.textPrimary)
        .background(Color.bgPrimary)
        .environment(\.openURL, OpenURLAction { url in
            if url.host == "www.apple.com" { count += 512 }
            if url.host == "healthmd.app" { count += 1024 }
            return .handled
        })
    }

    private var setupComponents: some View {
        VStack(spacing: Spacing.s4) {
            OnboardingHeader(eyebrow: "Apple Health", title: "Choose What Health.md Can Read",
                             description: "Grant read access for the categories you want to export. You can adjust this later in the Health app.",
                             icon: "heart.fill", showsIcon: false)
            OnboardingChecklistRow(title: "Export Folder",
                                   detail: folderChosen ? "Synthetic Family Archive — complete selected folder name" : "Choose now or after previewing",
                                   isComplete: folderChosen, actionTitle: "Choose Folder") {
                folderChosen = true
                count += 2
            }
            OnboardingSecondaryButton(title: "Use a Shared Setup", icon: "doc.badge.gearshape") { count += 4 }
                .accessibilityIdentifier("a11y.onboarding.shared")
        }
    }

    private var audiencePicker: some View {
        OnboardingAudienceChoices(choices: Audience.allCases, selection: audience,
                                  title: { $0 == .individual ? "Individual Lifetime Access" : "Family Sharing Lifetime Access" }) {
            audience = $0
        }
        .accessibilityIdentifier("a11y.onboarding.audience")
    }

    private var offerComponents: some View {
        VStack(spacing: Spacing.s4) {
            audiencePicker
            OnboardingPurchaseButton(title: offer.title, subtitle: offer.detail,
                                     priceLabel: busy ? "Loading…" : offer.price, icon: "person.3.fill", badge: "Family",
                                     isPrimary: true, isLoading: busy, isDisabled: busy) { count += 32 }
                .accessibilityIdentifier("a11y.onboarding.purchase")
            OnboardingTextAction(title: "Restore Purchase", isLoading: busy, isDisabled: busy) { count += 8 }
                .accessibilityLabel("Restore previous purchase")
                .accessibilityIdentifier("a11y.onboarding.restore")
            OnboardingTextAction(title: "Try Again") { count += 16 }
                .accessibilityIdentifier("a11y.onboarding.retry")
            OnboardingSecondaryButton(title: "Toggle Loading State", icon: "clock") { busy.toggle() }
                .accessibilityIdentifier("a11y.onboarding.busy")
        }
    }

    private var paywall: some View {
        OnboardingPaywallLayout(onDismiss: { count += 256; page = 1 }, dismissIdentifier: "a11y.onboarding.dismiss") {
            VStack(spacing: Spacing.s4) {
                OnboardingPaywallHeader(title: "Purchases & Family", subtitle: "Family Lifetime active",
                                       titleIdentifier: "a11y.onboarding.paywall-title", subtitleIdentifier: "a11y.onboarding.paywall-subtitle")
                PaywallPurchaseOptionButton(title: offer.title, subtitle: offer.detail, priceLabel: offer.price,
                                            icon: "person.3.fill", badge: "Family", isPrimary: true,
                                            isLoading: false, isDisabled: false) { count += 4096 }
                    .accessibilityIdentifier("a11y.onboarding.paywall-purchase")
                OnboardingTextAction(title: "Restore Purchase") { count += 2048 }
                    .accessibilityLabel("Restore previous purchase")
                    .accessibilityIdentifier("a11y.onboarding.paywall-restore")
                OnboardingPurchaseDisclosure()
            }
        }
    }
}
#endif
