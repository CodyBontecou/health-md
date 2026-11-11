#if os(macOS)
import SwiftUI

// MARK: - Mac glass page building blocks
//
// The Mac boards (MacHomeG, MacSettingsG, MacCLIG) share one layout: a 26 pt title with a
// muted paragraph, then titled glass sections of 40 pt rows separated by hairlines.

/// Scrolling page with the boards' 24 × 28 pt insets and 18 pt section gap.
struct MacGlassPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.glassAdaptive(\.bg).ignoresSafeArea())
        .foregroundStyle(Color.glassAdaptive(\.text))
        .tint(Color.glassAdaptive(\.accent))
    }
}

/// The page title, its paragraph and an optional trailing status.
struct MacGlassPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 660, alignment: .leading)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension MacGlassPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// "Ready" style status capsule from MacHomeG.
struct MacGlassStatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.glassAdaptive(\.surface2), in: Capsule())
    }
}

/// A titled glass group. Separate rows with `MacGlassDivider()`.
struct MacGlassSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.glassAdaptive(\.muted))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 16)
        }
    }
}

/// The hairline between rows.
struct MacGlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.glassAdaptive(\.line))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A 40 pt row: title on the left, any trailing view on the right.
struct MacGlassRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.glassAdaptive(\.text))
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}

extension MacGlassRow where Trailing == MacGlassValue {
    /// A row whose value is plain text in `tone`.
    init(_ title: String, value: String, tone: MacGlassValue.Tone = .muted, monospaced: Bool = false) {
        self.title = title
        self.trailing = MacGlassValue(value, tone: tone, monospaced: monospaced)
    }
}

/// Right-hand row text in the boards' tones.
struct MacGlassValue: View {
    enum Tone { case muted, accent, text, ok, warning, coral }

    let text: String
    var tone: Tone = .muted
    var monospaced = false

    init(_ text: String, tone: Tone = .muted, monospaced: Bool = false) {
        self.text = text
        self.tone = tone
        self.monospaced = monospaced
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: monospaced ? .monospaced : .default))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var color: Color {
        switch tone {
        case .muted: return Color.glassAdaptive(\.muted)
        case .accent: return Color.glassAdaptive(\.accent)
        case .text: return Color.glassAdaptive(\.text)
        case .ok: return Color.glassAdaptive(\.ok)
        case .warning: return Color.warning
        case .coral: return Color.glassAdaptive(\.coral)
        }
    }
}

/// Small text-style action used inside rows ("Change", "Copy", "Delete…").
struct MacGlassRowButtonStyle: ButtonStyle {
    var tone: MacGlassValue.Tone = .accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
    }

    private var color: Color {
        switch tone {
        case .coral: return Color.glassAdaptive(\.coral)
        case .muted: return Color.glassAdaptive(\.muted)
        case .text: return Color.glassAdaptive(\.text)
        default: return Color.glassAdaptive(\.accent)
        }
    }
}

/// The boards' accent "On" / "Off" row value; clicking it flips the setting.
struct MacGlassOnOffButton: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(isOn ? String(localized: "On") : String(localized: "Off"))
        }
        .buttonStyle(MacGlassRowButtonStyle(tone: isOn ? .accent : .muted))
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// MacCLIG's 32 pt capsule buttons: accent fill for the primary action, glass fill otherwise.
struct MacGlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.glassAdaptive(\.accentInk) : Color.glassAdaptive(\.text))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                prominent ? Color.glassAdaptive(\.accent) : Color.glassAdaptive(\.surface2),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.glassAdaptive(\.edge), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// Muted footnote under a section.
struct MacGlassFootnote: View {
    let text: String

    var body: some View {
        // Inline code spans in footnote copy render as code, not literal backticks.
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .font(.system(size: 12))
            .foregroundStyle(Color.glassAdaptive(\.muted))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

/// Paths as the boards show them: the home folder shortened to "~".
enum MacDisplayPath {
    static func abbreviatingHome(_ path: String, home: String = MacDisplayPath.userHome) -> String {
        guard !home.isEmpty else { return path }
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == trimmedHome { return "~" }
        if path.hasPrefix(trimmedHome + "/") {
            return "~" + path.dropFirst(trimmedHome.count)
        }
        return path
    }

    /// The real home folder; inside the sandbox `NSHomeDirectory()` is the container.
    static var userHome: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }
}

#endif
