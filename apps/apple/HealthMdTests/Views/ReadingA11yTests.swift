#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import HealthMd

/// Isolated tests host the actual production components;
/// reference Text measurements are typography baselines, not copied row layouts.
@MainActor
final class ReadingA11yTests: XCTestCase {
    private struct Display {
        let size: DynamicTypeSize
        let width: CGFloat
        let height: CGFloat
        var locale = "en_US"
        var dark = false
    }

    private var displays: [Display] { [
        Display(size: .large, width: 320, height: 640),
        Display(size: .xxxLarge, width: 320, height: 640),
        Display(size: .accessibility1, width: 320, height: 640),
        Display(size: .accessibility5, width: 320, height: 640),
        Display(size: .accessibility5, width: 320, height: 640, dark: true),
        Display(size: .large, width: 280, height: 480),
        Display(size: .accessibility5, width: 280, height: 280),
        Display(size: .accessibility5, width: 320, height: 480, locale: "de_DE", dark: true),
        Display(size: .accessibility5, width: 320, height: 480, locale: "ar", dark: true),
        Display(size: .accessibility5, width: 320, height: 640, locale: "ja_JP")
    ] }

    private let descriptionText = "Analytics never includes health values, metric names, health dates, exported files, paths, peer names, or credentials. It is not used for advertising or cross-app tracking."
    private let longHost = "synthetic-mac-with-a-long-name.example.invalid"

    private func measured<V: View>(_ view: V, display: Display, width: CGFloat? = nil) -> CGSize {
        let width = width ?? display.width
        let host = A11yHosting(
            view.environment(\.dynamicTypeSize, display.size)
                .environment(\.locale, Locale(identifier: display.locale))
                .environment(\.layoutDirection, display.locale == "ar" ? .rightToLeft : .leftToRight)
                .environment(\.colorScheme, display.dark ? .dark : .light),
            size: CGSize(width: width, height: display.height)
        )
        defer { host.close() }
        return host.measured(proposal: CGSize(width: width, height: 10000))
    }

    private func textHeight(_ text: String, font: Font, display: Display, width: CGFloat) -> CGFloat {
        measured(Text(text).font(font).fixedSize(horizontal: false, vertical: true), display: display, width: width).height
    }

    func testMetricNamesAndDetailsKeepTheirCompleteNaturalHeight() {
        let names = ["Heart Rate Variability During Walking", "Herzfrequenzvariabilität beim Gehen", "تباين معدل ضربات القلب أثناء المشي", "歩行中の心拍変動と心肺機能の測定"]
        for display in displays {
            for name in names {
                let detail = "SDNN · ms"
                let label = measured(ReadingMetricLabel(name: name, detail: detail), display: display, width: 200)
                let required = textHeight(name, font: Typography.bodyEmphasis(), display: display, width: 200)
                    + textHeight(detail, font: Typography.monoCaption(), display: display, width: 200) + Spacing.s1
                XCTAssertEqual(label.height, required, accuracy: 1, "The production label must not cap either text block")
                let toggle = measured(ReadingMetricToggle(name: name, detail: detail, isOn: .constant(false), accessibilityHint: "Synthetic metric"), display: display)
                XCTAssertLessThanOrEqual(toggle.width, display.width + 1)
                XCTAssertGreaterThanOrEqual(toggle.height, 44)
            }
        }
    }

    func testCategoryTitleAndSubtitleGrowWithoutStatusRailTakingReadingWidth() {
        for display in displays {
            let title = "Heart Health and Walking Stability"
            let subtitle = "Separate Apple permission required"
            let category = ReadingMetricCategoryHeader(title: title, subtitle: subtitle, icon: "heart", isExpanded: true, accessibilityLabel: title, onExpand: {}) {
                ReadingMetricCategoryStatus(label: "Enabled", icon: "checkmark", tint: .success, textColor: .successText)
            }
            let bounds = measured(category, display: display)
            let required = textHeight(title, font: Typography.headline(), display: display, width: display.width - 32)
                + textHeight(subtitle, font: Typography.caption(), display: display, width: display.width - 32) + 32
            XCTAssertGreaterThanOrEqual(bounds.height, required - 1)
            XCTAssertLessThanOrEqual(bounds.width, display.width + 1)
            XCTAssertGreaterThanOrEqual(bounds.height, 44)
        }
    }

    func testSettingsDescriptionKeepsFullCopyAndNaturalHeight() {
        for display in displays {
            let label = ReadingSettingsRowLabel(icon: "hand.raised.fill", title: "Privacy Policy", subtitle: descriptionText, status: "Configured", statusTone: .success)
            let bounds = measured(label, display: display)
            let required = textHeight("Privacy Policy", font: Typography.headline(), display: display, width: display.width - 32)
                + textHeight(descriptionText, font: Typography.caption(), display: display, width: display.width - 32) + 28
            XCTAssertGreaterThanOrEqual(bounds.height, required - 1, "All privacy copy must contribute to measured height")
            XCTAssertLessThanOrEqual(bounds.width, display.width + 1)
        }
    }

    func testProtectionDescriptionAndSwitchGrowInBothStates() {
        for display in displays {
            for enabled in [false, true] {
                let row = ReadingProtectionRow(isEnabled: .constant(enabled), accessibilityIdentifier: "reading.test.protection")
                let bounds = measured(row, display: display)
                let text = enabled ? "Configuration changes are blocked on this device." : "Configuration can be edited normally."
                let required = textHeight(text, font: .footnote, display: display, width: display.width - 32) + 44 + 28 + Spacing.s2
                XCTAssertGreaterThanOrEqual(bounds.height, required - 1)
                XCTAssertLessThanOrEqual(bounds.width, display.width + 1)
            }
        }
    }

    func testRealProtectionBindingRejectsMetricMutationUntilProductionLockRowUnlocks() {
        let suite = "ReadingA11yTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let manager = ConfigurationProtectionManager(userDefaults: defaults)
        defer {
            manager.dismissBlockedChangeToast()
            defaults.removePersistentDomain(forName: suite)
        }
        var selected = false
        var calls = 0
        let lock = ReadingProtectionRow(isEnabled: Binding(get: { manager.isEnabled }, set: { manager.setEnabled($0) }), accessibilityIdentifier: "reading.test.protection")
        let metric = ReadingMetricToggle(name: "Synthetic metric", detail: "ms", isOn: manager.protecting(Binding(get: { selected }, set: { selected = $0; calls += 1 })), accessibilityHint: "Synthetic selection")

        lock.isEnabled = true
        metric.isOn = true
        XCTAssertTrue(manager.isEnabled)
        XCTAssertFalse(selected)
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(manager.blockedChangeToastID)
        lock.isEnabled = false
        metric.isOn = true
        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(selected)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(manager.blockedChangeToastID)
        // Binding/manager evidence only. Native taps are in ReadingA11yUITests;
        // shipping MetricSelectionView/HealthKit guards remain an integration gate.
    }

    func testConnectionEntriesAndActionsKeepLongValuesAndMinimumBounds() {
        for display in displays {
            for (title, value) in [("Mac IP address or hostname", longHost), ("Manual IP port", "65535")] {
                let entry = ReadingConnectionEntry(title: title, value: value, identifier: "reading.test.entry", focusEditor: {}) {
                    TextField("", text: .constant(value))
                }
                let bounds = measured(entry, display: display)
                let required = textHeight(title, font: Typography.bodyEmphasis(), display: display, width: display.width)
                    + textHeight(value, font: Typography.scaled(size: 17, monospaced: true), display: display, width: display.width) + 44 + Spacing.s2 * 2
                XCTAssertGreaterThanOrEqual(bounds.height, required - 1)
                XCTAssertLessThanOrEqual(bounds.width, display.width + 1)
            }
            let actions = ReadingConnectionActions(primaryTitle: "Connect to the selected Mac", primaryIcon: "network", isEnabled: true, onPrimary: {}, secondaryTitle: "Disconnect from the selected Mac")
            let bounds = measured(actions, display: display)
            XCTAssertLessThanOrEqual(bounds.width, display.width + 1)
            XCTAssertGreaterThanOrEqual(bounds.height, 88 + Spacing.sm)
        }
    }

    func testAlreadyHostedReadingRowsReactToLiveTextSizeChanges() {
        let row = SettingsRow(icon: "hand.raised", title: "Privacy Policy", subtitle: descriptionText, isActive: true, action: {})
        let host = A11yHosting(row.environment(\.dynamicTypeSize, .large))
        defer { host.close() }
        let proposal = CGSize(width: 320, height: 10000)
        let small = host.measured(proposal: proposal)
        host.update(row.environment(\.dynamicTypeSize, .accessibility5))
        let large = host.measured(proposal: proposal)
        XCTAssertGreaterThan(large.height, small.height * 2)
        host.update(row.environment(\.dynamicTypeSize, .large))
        XCTAssertEqual(host.measured(proposal: proposal).height, small.height, accuracy: 1)
    }

    func testSettingsStatusForegroundPassesBothThemeTintedSurfaces() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            func rgb(_ color: Color) -> [Double] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
                return [Double(r), Double(g), Double(b), Double(a)]
            }
            func luminance(_ color: [Double]) -> Double {
                let linear = color.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
            }
            for tone in [SettingsStatusTone.accent, .success, .warning, .muted] {
                for surface in [Color.bgPrimary, .bgSecondary, .bgTertiary] {
                    let fill = rgb(tone.background), base = rgb(surface)
                    let composite = (0..<3).map { fill[$0] * fill[3] + base[$0] * (1 - fill[3]) }
                    let foreground = luminance(rgb(tone.foreground)), background = luminance(composite)
                    XCTAssertGreaterThanOrEqual((max(foreground, background) + 0.05) / (min(foreground, background) + 0.05), 4.5, "\(style) \(tone) on \(surface)")
                }
            }
        }
    }
}
#endif
