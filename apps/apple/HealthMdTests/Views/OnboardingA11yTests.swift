#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import HealthMd

/// Production display/action components only. These tests do not initialize
/// PurchaseManager, HealthKit, analytics, destinations or onboarding persistence.
@MainActor
final class OnboardingA11yTests: XCTestCase {
    private let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility5]
    private let offers = [
        ("en_US", "Family Lifetime", "Share unlimited private exports with up to 5 family members.", "US$ 1,234.99"),
        ("de_DE", "Lebenslanger Familienzugang", "Unbegrenzte private Exporte mit bis zu fünf Familienmitgliedern teilen.", "1.234.567,89 €"),
        ("ar", "وصول عائلي مدى الحياة", "شارك عمليات التصدير الخاصة غير المحدودة مع ما يصل إلى خمسة أفراد من العائلة.", "١٬٢٣٤٬٥٦٧٫٨٩ ر.س.‏"),
        ("ja_JP", "ファミリー永久アクセス", "最大5人の家族と無制限のプライベート書き出しを共有できます。", "￥1,234,567")
    ]

    private func measure<V: View>(_ view: V, width: CGFloat = 288, size: DynamicTypeSize, locale: String = "en_US") -> CGSize {
        let host = A11yHosting(view
            .environment(\.dynamicTypeSize, size)
            .environment(\.onboardingReadingLayout, true)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.layoutDirection, locale == "ar" ? .rightToLeft : .leftToRight))
        defer { host.close() }
        return host.measured(proposal: CGSize(width: width, height: 10000))
    }

    private func textHeight(_ text: String, font: Font, width: CGFloat, size: DynamicTypeSize, locale: String = "en_US") -> CGFloat {
        measure(Text(text).font(font).fixedSize(horizontal: false, vertical: true),
                width: width, size: size, locale: locale).height
    }

    func testReadingLayoutRespondsToStandardEnlargementAndShortNarrowWindows() {
        XCTAssertFalse(OnboardingReadingLayout.isNeeded(size: CGSize(width: 390, height: 740), textSize: .large))
        XCTAssertTrue(OnboardingReadingLayout.isNeeded(size: CGSize(width: 390, height: 740), textSize: .xLarge))
        XCTAssertTrue(OnboardingReadingLayout.isNeeded(size: CGSize(width: 320, height: 640), textSize: .large))
        XCTAssertTrue(OnboardingReadingLayout.isNeeded(size: CGSize(width: 568, height: 280), textSize: .large))
        XCTAssertTrue(OnboardingReadingLayout.isNeeded(size: CGSize(width: 1024, height: 768), textSize: .accessibility5))
    }

    func testLiveOnboardingPrimaryAndSecondaryButtonsGrowWithoutShrinkingLabels() {
        let title = "Connect Apple Health and continue your private export setup"
        for primary in [true, false] {
            var previousHeight: CGFloat = 0
            for size in sizes {
                let button = primary
                    ? AnyView(OnboardingPrimaryButton(title: title, imageAsset: "AppleHealthIcon", action: {}))
                    : AnyView(OnboardingSecondaryButton(title: title, icon: "doc.badge.gearshape", action: {}))
                let actual = measure(button, size: size)
                let font = primary ? Typography.scaled(size: 16, weight: .medium) : Typography.bodyEmphasis()
                let fullLabelHeight = textHeight(title, font: font, width: 288 - 2 * Spacing.s3, size: size)
                XCTAssertGreaterThanOrEqual(actual.height, max(primary ? 48 : 44, fullLabelHeight + 2 * Spacing.s2) - 1)
                XCTAssertGreaterThan(actual.height, previousHeight, "Actual action label must grow: \(size)")
                XCTAssertGreaterThanOrEqual(actual.width, 44)
                XCTAssertLessThanOrEqual(actual.width, 288)
                previousHeight = actual.height
            }
        }
    }

    func testPurchaseButtonsReserveTheFullStackedTitleSubtitleAndRegionalPrice() {
        for (locale, title, subtitle, price) in offers {
            for size in sizes {
                for paywall in [false, true] {
                    let button = paywall
                        ? AnyView(PaywallPurchaseOptionButton(title: title, subtitle: subtitle, priceLabel: price,
                                                             icon: "person.3.fill", badge: nil, isPrimary: true,
                                                             isLoading: false, isDisabled: false, action: {}))
                        : AnyView(OnboardingPurchaseButton(title: title, subtitle: subtitle, priceLabel: price,
                                                           icon: "person.3.fill", isPrimary: true,
                                                           isLoading: false, isDisabled: false, action: {}))
                    let actual = measure(button, size: size, locale: locale)
                    let innerWidth: CGFloat = 288 - 2 * Spacing.s3
                    let fullTextHeight = textHeight(title, font: Typography.headline(), width: innerWidth, size: size, locale: locale)
                        + textHeight(subtitle, font: paywall ? Typography.body() : Typography.caption(), width: innerWidth, size: size, locale: locale)
                        + textHeight(price, font: Typography.bodyEmphasis(), width: innerWidth, size: size, locale: locale)
                    XCTAssertGreaterThanOrEqual(actual.height, fullTextHeight + 2 * Spacing.s3 + 2 * Spacing.s2 - 1,
                                                "No price/title/subtitle truncation: \(locale) \(size) paywall=\(paywall)")
                    XCTAssertLessThanOrEqual(actual.width, 288)
                }
            }
        }
    }

    func testLongAudienceLabelsGrowAsSeparateMinimumTargets() {
        struct Choice: Hashable, Identifiable { let id: Int; let title: String }
        // Long enough to wrap even at default: shorter labels legitimately stay
        // inside the 44pt minimum at both default and standard enlarged sizes.
        let choices = [Choice(id: 0, title: "Individual Lifetime Access For A Complete Private Health Archive"),
                       Choice(id: 1, title: "Family Sharing Lifetime Access For Everyone In The Household")]
        var previousHeight: CGFloat = 0
        for size in sizes {
            let picker = OnboardingAudienceChoices(choices: choices, selection: choices[1], title: { $0.title }, onSelect: { _ in })
            let actual = measure(picker, size: size)
            let labelHeight = choices.reduce(CGFloat.zero) {
                $0 + max(44, textHeight($1.title, font: Typography.bodyEmphasis(), width: 288 - 8 - 2 * Spacing.s2, size: size) + 2 * Spacing.s2)
            }
            XCTAssertGreaterThanOrEqual(actual.height, labelHeight + 8 + Spacing.s1 - 1)
            XCTAssertGreaterThan(actual.height, previousHeight)
            XCTAssertLessThanOrEqual(actual.width, 288)
            previousHeight = actual.height
        }
    }

    func testRestoreRetryRepairAndDismissHaveGrowingNativeLabelsAndMinimumBounds() {
        for size in sizes {
            for view in [
                AnyView(OnboardingTextAction(title: "Restore Purchase", action: {})),
                AnyView(OnboardingTextAction(title: "Try Again", action: {})),
                AnyView(OnboardingTextAction(title: "Restore Purchase", isLoading: true, isDisabled: true, action: {})),
                AnyView(OnboardingDismissButton(action: {}))
            ] {
                let actual = measure(view, size: size)
                XCTAssertGreaterThanOrEqual(actual.width, 44)
                XCTAssertGreaterThanOrEqual(actual.height, 44)
                XCTAssertLessThanOrEqual(actual.width, 288)
            }
            let detail = "My complete private family health archive folder with a long selected name"
            let row = OnboardingChecklistRow(title: "Export Folder", detail: detail, isComplete: false,
                                             actionTitle: "Choose Folder", action: {})
            let actual = measure(row, size: size)
            let detailHeight = textHeight(detail, font: Typography.body(), width: 288 - 2 * Spacing.s3, size: size)
            XCTAssertGreaterThan(actual.height, detailHeight + 44)
            XCTAssertLessThanOrEqual(actual.width, 288)
        }
    }

    func testExistingActionRespondsToLiveTextSizeUpdates() {
        let button = OnboardingPrimaryButton(title: "Create My First Export", icon: "arrow.right", action: {})
        let host = A11yHosting(button.environment(\.dynamicTypeSize, .large))
        defer { host.close() }
        let proposal = CGSize(width: 288, height: 10000)
        let before = host.measured(proposal: proposal)
        host.update(button.environment(\.dynamicTypeSize, .accessibility5))
        XCTAssertGreaterThan(host.measured(proposal: proposal).height, before.height)
        host.update(button.environment(\.dynamicTypeSize, .large))
        XCTAssertEqual(host.measured(proposal: proposal).height, before.height, accuracy: 0.5)
    }

    func testPurchaseLoadingAndUnavailableTextAlsoUsesFullHeight() {
        for status in ["Loading purchase options and regional prices…", "Purchase is currently unavailable"] {
            for size in sizes {
                let label = OnboardingPurchaseOptionLabel(title: "Family Lifetime", subtitle: "One-time purchase",
                                                         priceLabel: status, icon: "person.3.fill", badge: "Family Sharing",
                                                         isPrimary: false, isLoading: status.hasPrefix("Loading"),
                                                         subtitleFont: Typography.body(), padding: Spacing.s4)
                let actual = measure(label, size: size)
                let statusHeight = textHeight(status, font: Typography.bodyEmphasis(), width: 264, size: size)
                XCTAssertGreaterThan(actual.height, statusHeight + 2 * Spacing.s3)
                XCTAssertLessThanOrEqual(actual.width, 288)
            }
        }
    }

    func testReadingHeadersAndPurchaseDisclosureGrowInBothThemes() {
        for dark in [false, true] {
            for view in [
                AnyView(OnboardingHeader(eyebrow: "Apple Health", title: "Choose What Health.md Can Read",
                                         description: "Grant read access for the categories you want to export. You can adjust this later in the Health app.",
                                         icon: "heart.fill", showsIcon: false)),
                AnyView(OnboardingPaywallHeader(title: "Keep Your Health Archive Growing", subtitle: "Unlimited private exports, including scheduled runs.",
                                               titleIdentifier: "test.title", subtitleIdentifier: "test.subtitle")),
                AnyView(OnboardingPurchaseDisclosure())
            ] {
                var previousHeight: CGFloat = 0
                for size in sizes {
                    let actual = measure(view.preferredColorScheme(dark ? .dark : .light), size: size)
                    XCTAssertGreaterThan(actual.height, previousHeight)
                    XCTAssertLessThanOrEqual(actual.width, 288)
                    previousHeight = actual.height
                }
            }
        }
    }
}
#endif
