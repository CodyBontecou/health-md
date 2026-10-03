import SwiftUI
import XCTest
#if A11Y_ISOLATED_MAC
@testable import HealthMdMac
#else
@testable import HealthMd
#endif
#if os(iOS)
import UIKit
import CoreText
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class A11yFoundationTests: XCTestCase {
    // Kept explicit: aliases remain part of the existing 19-call-site contract.
    private var tokens: [(String, Font, CGFloat, Font.Weight, Bool)] { [
        ("hero", Typography.hero(), 32, .semibold, false),
        ("displayLarge", Typography.displayLarge(), 32, .semibold, false),
        ("displayMedium", Typography.displayMedium(), 24, .semibold, false),
        ("heading24", Typography.heading24(), 24, .semibold, false),
        ("heading20", Typography.heading20(), 20, .semibold, false),
        ("headline", Typography.headline(), 16, .semibold, false),
        ("headlineEmphasis", Typography.headlineEmphasis(), 16, .semibold, false),
        ("bodyLarge", Typography.bodyLarge(), 18, .regular, false),
        ("body", Typography.body(), 14, .regular, false),
        ("bodyEmphasis", Typography.bodyEmphasis(), 14, .medium, false),
        ("caption", Typography.caption(), 13, .regular, false),
        ("label", Typography.label(), 12, .medium, false),
        ("labelUppercase", Typography.labelUppercase(), 12, .medium, false),
        ("mono", Typography.mono(), 14, .regular, true),
        ("monoEmphasis", Typography.monoEmphasis(), 14, .medium, true),
        ("monoCaption", Typography.monoCaption(), 12, .regular, true),
        ("monoCaptionEmphasis", Typography.monoCaptionEmphasis(), 12, .medium, true),
        ("monoLabel", Typography.monoLabel(), 12, .medium, true),
        ("bodyMono", Typography.bodyMono(), 14, .regular, true)
    ] }

    #if os(iOS)
    private let categories: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility5]

    private func measure(_ text: String = "Health archive", font: Font, size: DynamicTypeSize) -> CGSize {
        let host = A11yHosting(Text(text).font(font).fixedSize().environment(\.dynamicTypeSize, size))
        defer { host.close() }
        return host.measured()
    }

    func testAllNineteenFontsGrowInViewScopedEnvironment() {
        XCTAssertEqual(tokens.count, 19)
        // Native positive controls guard against a broken measurement environment.
        for (name, font) in tokens.map({ ($0.0, $0.1) }) + [
            ("native.body", .body), ("native.headline", .headline),
            ("native.caption", .caption), ("native.footnote", .footnote), ("native.callout", .callout)
        ] {
            var previous = CGSize.zero
            for category in categories {
                let size = measure(font: font, size: category)
                XCTAssertGreaterThan(size.height, previous.height, "\(name) \(category) must grow")
                XCTAssertGreaterThan(size.width, previous.width, "\(name) \(category) must grow")
                print("A11Y_FONT \(name) \(category) \(size.width)x\(size.height)")
                previous = size
            }
        }
    }

    func testBundledFacesExistAndDefaultSizesAndWeightsArePreserved() throws {
        for name in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium"] {
            let font = try XCTUnwrap(UIFont(name: name, size: 14), "Missing registered face; fallback is NOT success")
            XCTAssertEqual(font.fontName, name)
        }
        for (name, font, baseSize, weight, mono) in tokens {
            let face = mono ? (weight == .medium ? "GeistMono-Medium" : "GeistMono-Regular")
                : (weight == .semibold ? "Geist-SemiBold" : (weight == .medium ? "Geist-Medium" : "Geist-Regular"))
            // A separate fixed-face control verifies retained default metrics, not just growth.
            let reference = Font.custom(face, fixedSize: baseSize).weight(weight)
            let actual = measure(font: font, size: .large)
            let expected = measure(font: reference, size: .large)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, name)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, name)
        }
        let regular = try XCTUnwrap(UIFont(name: "Geist-Regular", size: 14))
        let medium = try XCTUnwrap(UIFont(name: "Geist-Medium", size: 14))
        let semibold = try XCTUnwrap(UIFont(name: "Geist-SemiBold", size: 14))
        func fontWeight(_ font: UIFont) -> CGFloat {
            (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? -1
        }
        XCTAssertLessThan(fontWeight(regular), fontWeight(medium))
        XCTAssertLessThan(fontWeight(medium), fontWeight(semibold))
    }

    func testMonoCharactersAndDigitsRemainEqualWidthAtEverySize() {
        for (name, font, _, _, mono) in tokens where mono {
            for category in categories {
                let narrow = measure("iiii1111", font: font, size: category)
                let wide = measure("WWWW8888", font: font, size: category)
                XCTAssertEqual(narrow.width, wide.width, accuracy: 0.5, "\(name) \(category)")
            }
        }
        XCTAssertLessThan(measure("iiii", font: Typography.body(), size: .large).width,
                          measure("WWWW", font: Typography.body(), size: .large).width)
    }

    func testAlreadyCreatedFontsRespondToLiveEnvironmentChanges() {
        let font = Typography.body()
        let host = A11yHosting(Text("Live text").font(font).fixedSize().environment(\.dynamicTypeSize, .large))
        defer { host.close() }
        let before = host.measured()
        host.update(Text("Live text").font(font).fixedSize().environment(\.dynamicTypeSize, .accessibility5))
        let enlarged = host.measured()
        XCTAssertGreaterThan(enlarged.height, before.height * 2)
        host.update(Text("Live text").font(font).fixedSize().environment(\.dynamicTypeSize, .large))
        XCTAssertEqual(host.measured().height, before.height, accuracy: 0.5)
    }

    func testProductionButtonsGrowAndHaveMinimumTargets() {
        for category in categories {
            let samples: [(String, AnyView)] = [
                ("secondary", AnyView(SecondaryButton("Choose a different destination folder") {})),
                ("destructive", AnyView(DestructiveButton(title: "Remove the selected destination", action: {}))),
                ("primary", AnyView(PrimaryButton("Create My First Export", icon: "arrow.right") {})),
                ("icon", AnyView(IconButton(icon: "xmark", accessibilityLabel: "Close") {}))
            ]
            for (name, view) in samples {
                let host = A11yHosting(view.environment(\.dynamicTypeSize, category))
                let size = host.measured(proposal: CGSize(width: 280, height: 2000))
                host.close()
                XCTAssertGreaterThanOrEqual(size.height, 44, "\(name) \(category)")
                XCTAssertGreaterThanOrEqual(size.width, 44, "\(name) \(category)")
                XCTAssertLessThanOrEqual(size.width, 280, "\(name) \(category)")
                if category == .accessibility5 && name != "icon" { XCTAssertGreaterThan(size.height, 60, name) }
            }
        }
    }

    func testProductionStatusLabelsAndSymbolContainersGrow() {
        let samples: [(String, AnyView)] = [
            ("connected", AnyView(StatusPill(status: .connected))),
            ("disconnected", AnyView(StatusPill(status: .disconnected))),
            ("pending", AnyView(StatusPill(status: .pending))),
            ("healthSymbol", AnyView(PulsingHeartIcon(isConnected: true))),
            ("vaultSymbol", AnyView(VaultIcon(isSelected: true)))
        ]
        for (name, sample) in samples {
            var previous = CGSize.zero
            for category in categories {
                let host = A11yHosting(sample.environment(\.dynamicTypeSize, category))
                let measured = host.measured()
                host.close()
                XCTAssertGreaterThan(measured.height, previous.height, "\(name) \(category)")
                XCTAssertGreaterThan(measured.width, previous.width, "\(name) \(category)")
                previous = measured
            }
        }
    }

    func testReadableTextContrastOnActualBothThemeSurfacesAndStatusTints() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            func rgba(_ color: Color) -> [CGFloat] {
                let resolved = UIColor(color).resolvedColor(with: traits)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
                return [r, g, b, a]
            }
            func contrast(_ fg: [CGFloat], _ bg: [CGFloat]) -> Double {
                func luminance(_ rgba: [CGFloat]) -> Double {
                    let rgb = rgba.prefix(3).map { Double($0) }.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
                }
                let a = luminance(fg), b = luminance(bg)
                return (max(a, b) + 0.05) / (min(a, b) + 0.05)
            }
            for surface in [Color.bgPrimary, .bgSecondary, .bgTertiary, .controlBackground, .controlPressed, .selectedBackground] {
                let bg = rgba(surface)
                for text in [Color.textPrimary, .textSecondary, .successText, .errorText] {
                    XCTAssertGreaterThanOrEqual(contrast(rgba(text), bg), 4.5, "\(style) \(text) / \(surface)")
                }
                for status in [StatusPill.Status.connected, .disconnected, .pending] {
                    let tint = rgba(status.color)
                    let tinted = (0..<3).map { tint[$0] * 0.10 + bg[$0] * 0.90 } + [1]
                    let ratio = contrast(rgba(status.textColor), tinted)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(style) \(status) tint on \(surface): \(ratio)")
                }
            }
        }
    }
    #elseif os(macOS)
    func testSharedDesktopTypographyRetainsNativeSizesAndDesigns() {
        XCTAssertEqual(tokens.count, 19)
        for (name, font, size, weight, mono) in tokens {
            XCTAssertEqual(font, .system(size: size, weight: weight, design: mono ? .monospaced : .default), name)
            let host = NSHostingView(rootView: Text("Health archive").font(font).fixedSize())
            XCTAssertGreaterThan(host.fittingSize.height, 0, name)
        }
    }

    func testDesktopHeaderWrapsWithoutTouchOnlyDefaults() {
        let host = NSHostingView(rootView: HealthMdPageHeader(title: "Synthetic desktop heading", subtitle: "An isolated component, without any destination or runtime services.").frame(width: 320))
        XCTAssertEqual(host.fittingSize.width, 320, accuracy: 1)
        XCTAssertGreaterThan(host.fittingSize.height, 80)
    }
    #endif
}
