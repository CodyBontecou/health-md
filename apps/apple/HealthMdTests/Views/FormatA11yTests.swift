#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import HealthMd

/// Production components, never a settings repository or protection substitute.
/// Execution is a central gate; these tests do not certify the full protected screens.
@MainActor
final class FormatA11yTests: XCTestCase {
    private let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility5]
    private let widths: [CGFloat] = [240, 288, 320, 568]
    private let longKey = "synthetic_original_output_key_with_a_long_unbroken_identifier"
    private let renamedKey = "synthetic_renamed_output_key_preserved_without_truncation"
    private let longValue = "Synthetic metadata only: this complete value remains readable without changing spaces, punctuation, or export settings."

    private func measure<V: View>(_ view: V, width: CGFloat, size: DynamicTypeSize) -> CGSize {
        let host = A11yHosting(view.environment(\.dynamicTypeSize, size), size: CGSize(width: width, height: 640))
        defer { host.close() }
        return host.measured(proposal: CGSize(width: width, height: 10000))
    }

    private func textHeight(_ text: String, font: Font, width: CGFloat, size: DynamicTypeSize) -> CGFloat {
        measure(Text(text).font(font).fixedSize(horizontal: false, vertical: true), width: width, size: size).height
    }

    func testClosedMenuLabelAllocatesFullValueHeightAtEveryTextSizeAndWidth() {
        for size in sizes {
            for width in widths {
                for value in ["ISO 8601 (2026-01-13)", "Friendly (Mon, Jan 13, 2026)", "12-hour with seconds (2:30:45 PM)"] {
                    let actual = measure(FormatSelectionValueLabel(value: value), width: width, size: size)
                    // A conservative lower bound: even text with the entire padded width
                    // must fit vertically. The real chevron consumes additional width.
                    let fullText = textHeight(value, font: .footnote.weight(.medium), width: width - 16, size: size)
                    XCTAssertLessThanOrEqual(actual.width, width + 0.5)
                    XCTAssertGreaterThanOrEqual(actual.width, 44)
                    XCTAssertGreaterThanOrEqual(actual.height, max(44, fullText + 16) - 0.5)
                }
            }
        }
    }

    func testHostedNativeMenuRowBudgetsTitleHelperAndValueSeparately() {
        let title = "Date Format"
        let subtitle = "Preview: Monday, January 13, 2026, with the complete selected format visible."
        let value = "Friendly (Mon, Jan 13, 2026)"
        for size in sizes {
            for width in widths {
                let row = FormatSelectionControl(title: title, subtitle: subtitle, selection: value,
                                                 options: [value], optionTitle: { $0 }, onSelect: { _ in })
                let actual = measure(row, width: width, size: size)
                let label = measure(FormatSelectionValueLabel(value: value), width: width, size: size)
                let titleHeight = textHeight(title, font: .body.weight(.semibold), width: width, size: size)
                let helperHeight = textHeight(subtitle, font: .footnote, width: width, size: size)
                XCTAssertLessThanOrEqual(actual.width, width + 0.5)
                XCTAssertGreaterThanOrEqual(actual.height, titleHeight + helperHeight + label.height + 31)
            }
        }
    }

    func testLongOriginalRenamedCustomAndPlaceholderValuesIncreaseLayoutHeight() {
        for size in sizes {
            for width in widths {
                func metric(_ original: String, _ renamed: String) -> some View {
                    FormatFrontmatterFieldContent(originalKey: original, customKey: renamed, isEnabled: .constant(true)) {
                        FormatInlineButton(title: "Rename Field", systemImage: "pencil", action: {})
                    }
                }
                let short = measure(metric("steps", "steps"), width: width, size: size)
                let long = measure(metric(longKey, renamedKey), width: width, size: size)
                XCTAssertLessThanOrEqual(long.width, width + 0.5)
                XCTAssertGreaterThan(long.height, short.height)
                let renamedHeight = textHeight("Renamed to \(renamedKey)", font: .footnote, width: width, size: size)
                XCTAssertGreaterThanOrEqual(long.height, renamedHeight + 44)

                let entry = FormatFrontmatterEntry(key: longKey, value: longValue,
                                                   deleteLabel: "Delete custom field \(longKey)", onDelete: {})
                let entrySize = measure(entry, width: width, size: size)
                let keyHeight = textHeight(longKey, font: Typography.monoEmphasis(), width: width, size: size)
                let valueHeight = textHeight(longValue, font: .footnote, width: width, size: size)
                XCTAssertLessThanOrEqual(entrySize.width, width + 0.5)
                XCTAssertGreaterThanOrEqual(entrySize.height, keyHeight + valueHeight + 44)

                let placeholder = FormatFrontmatterEntry(key: longKey, value: "Empty on export",
                                                         deleteLabel: "Delete placeholder field \(longKey)", onDelete: {})
                XCTAssertGreaterThanOrEqual(measure(placeholder, width: width, size: size).height, keyHeight + 44)
            }
        }
    }

    func testSingleLineInputOverflowHasAFullWrappingReadingSurface() {
        for size in sizes {
            for width in widths {
                XCTAssertLessThanOrEqual(measure(FormatOverflowValue(text: "date"), width: width, size: size).height, 0.5)
                for value in [String(repeating: longKey, count: 3), "  exact spaces\nand a second line  "] {
                    let actual = measure(FormatOverflowValue(text: value), width: width, size: size)
                    let fullText = textHeight(value, font: Typography.monoCaption(), width: width, size: size)
                    XCTAssertGreaterThanOrEqual(actual.height, fullText)
                    XCTAssertLessThanOrEqual(actual.width, width + 0.5)
                }
            }
        }
    }

    func testNativeInputKeepsExactTextAndMinimumEditingBounds() throws {
        let value = "  \(longKey)  "
        for size in sizes {
            for width in [CGFloat(240), 320] {
                let host = A11yHosting(
                    FormatTextFieldControl(title: "Type Field Value", placeholder: "health-data", text: .constant(value),
                                           defaultValue: "health-data", accessibilityLabel: "Type field value")
                        .environment(\.dynamicTypeSize, size),
                    size: CGSize(width: width, height: 640)
                )
                defer { host.close() }
                let input = try XCTUnwrap(descendants(of: host.controller.view, type: UITextField.self).first)
                XCTAssertEqual(input.text, value)
                // The native editor itself, not only its decorative background, grows.
                XCTAssertGreaterThanOrEqual(input.bounds.height, 44)
                XCTAssertLessThanOrEqual(input.bounds.width, width)
                XCTAssertGreaterThanOrEqual(host.measured(proposal: CGSize(width: width, height: 10000)).height, 44)
            }
        }
    }

    func testTemplateUsesRemainingHeightWithoutDroppingText() throws {
        let template = "# Synthetic {{date}}\n" + String(repeating: "α العربية 日本語 {{unknown}}\n", count: 80)
        for size in sizes {
            for availableHeight in [CGFloat(120), 200, 280, 640] {
                let host = A11yHosting(
                    FormatTemplateEditor(text: .constant(template), availableHeight: availableHeight)
                        .environment(\.dynamicTypeSize, size),
                    size: CGSize(width: 320, height: 640)
                )
                defer { host.close() }
                let editor = try XCTUnwrap(descendants(of: host.controller.view, type: UITextView.self).first)
                XCTAssertEqual(editor.text, template)
                XCTAssertGreaterThanOrEqual(editor.bounds.height, 44)
                XCTAssertLessThanOrEqual(editor.bounds.height, availableHeight / 2 + 1)
                XCTAssertTrue(editor.isScrollEnabled)
            }
        }
    }

    func testActionLabelsAndNavigationTargetsGrowWithoutElision() {
        for size in sizes {
            for width in widths {
                let samples = [
                    AnyView(FormatInlineButton(title: "Add Placeholder Field", systemImage: "plus.circle", action: {})),
                    AnyView(FormatInlineButton(title: "Rename Field", systemImage: "pencil", action: {})),
                    AnyView(FormatActionLabel(title: "Delete Field", systemImage: "trash")),
                    AnyView(FormatNavigationRow(icon: "number.square", title: "Frontmatter Fields", subtitle: longValue, status: "Schema-Safe"))
                ]
                for sample in samples {
                    let actual = measure(sample, width: width, size: size)
                    XCTAssertGreaterThanOrEqual(actual.height, 44)
                    XCTAssertGreaterThanOrEqual(actual.width, 44)
                    XCTAssertLessThanOrEqual(actual.width, width + 0.5)
                }
            }
        }
    }

    func testLiveTextSizeChangeReflowsRealMenuLabelAndCodeWithoutChangingValues() {
        let value = "Friendly (Mon, Jan 13, 2026)"
        let code = "# Synthetic {{date}}\n" + longValue
        func content(_ size: DynamicTypeSize) -> some View {
            VStack {
                FormatSelectionValueLabel(value: value)
                FormatCodeBlock(text: code)
            }
            .environment(\.dynamicTypeSize, size)
        }
        let host = A11yHosting(content(.large))
        defer { host.close() }
        let proposal = CGSize(width: 288, height: 10000)
        let original = host.measured(proposal: proposal)
        host.update(content(.accessibility5))
        let enlarged = host.measured(proposal: proposal)
        XCTAssertGreaterThan(enlarged.height, original.height * 2)
        XCTAssertLessThanOrEqual(enlarged.width, proposal.width + 0.5)
        host.update(content(.large))
        XCTAssertEqual(host.measured(proposal: proposal).height, original.height, accuracy: 0.5)
    }

    func testBothThemeNativeMenuAndLongValueCaptures() {
        for size in sizes {
            for theme in [ColorScheme.light, .dark] {
                let host = A11yHosting(
                    FormatSectionCard(title: "Date, Time, and Units", subtitle: "These choices affect display values in exported files.") {
                        FormatSelectionControl(title: "Date Format", subtitle: "Preview: 2026-01-13",
                                               selection: "ISO 8601 (2026-01-13)",
                                               options: ["ISO 8601 (2026-01-13)"], optionTitle: { $0 }, onSelect: { _ in })
                    }
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, theme)
                )
                defer { host.close() }
                let attachment = XCTAttachment(image: host.capture())
                attachment.name = "format-hosted-menu-\(size)-\(theme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testHelperAndDestructiveTextContrastOnFormatSurfacesAndUnchangedErrorTint() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            func rgb(_ color: Color) -> [Double] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
                return [Double(r), Double(g), Double(b)]
            }
            func luminance(_ color: [Double]) -> Double {
                let linear = color.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
            }
            func contrast(_ foreground: [Double], _ background: [Double]) -> Double {
                let a = luminance(foreground), b = luminance(background)
                return (max(a, b) + 0.05) / (min(a, b) + 0.05)
            }
            for surface in [Color.bgPrimary, .bgSecondary, .bgTertiary] {
                XCTAssertGreaterThanOrEqual(contrast(rgb(.textSecondary), rgb(surface)), 4.5)
            }
            // Actual callers: Reset on the page, Delete inside a section card.
            // Their existing 8% error fills do not composite over bgSecondary.
            for surface in [Color.bgPrimary, .bgTertiary] {
                let background = rgb(surface)
                let tint = rgb(.error)
                let composited = zip(tint, background).map { $0.0 * 0.08 + $0.1 * 0.92 }
                XCTAssertGreaterThanOrEqual(contrast(rgb(.errorText), composited), 4.5)
            }
        }
    }

    private func descendants<T: UIView>(of view: UIView, type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: $0, type: type) }
    }
}
#endif
