import SwiftUI

struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.glassPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassFont(.navTitle)
            .foregroundStyle(palette.accentInk)
            .frame(maxWidth: .infinity, minHeight: GlassMetrics.primaryButtonHeight)
            .background(Capsule().fill(palette.accent))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// A neutral full-width button (AutomationDetailG's Run now / Duplicate / Pause):
/// 46pt capsule on `surface2` with an edge and a top highlight.
struct GlassSecondaryButtonStyle: ButtonStyle {
    @Environment(\.glassPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassFont(.body)
            .fontWeight(.medium)
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(palette.surface2))
            .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
            .overlay(alignment: .top) {
                Capsule().strokeBorder(palette.hi, lineWidth: 1)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

struct GlassToggleStyle: ToggleStyle {
    /// Draws only the switch. A custom style cannot read `.labelsHidden()`, so a switch
    /// whose label is shown beside it asks for this; the label still names it to VoiceOver.
    var labelsHidden = false

    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                if !labelsHidden {
                    configuration.label
                    Spacer(minLength: 8)
                }
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? palette.accent : palette.track)
                    Capsule()
                        .fill(Color.white)
                        .frame(
                            width: GlassMetrics.switchKnobSize.width,
                            height: GlassMetrics.switchKnobSize.height
                        )
                        .padding(2)
                }
                .frame(width: GlassMetrics.switchSize.width, height: GlassMetrics.switchSize.height)
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: configuration.isOn)
            }
            .frame(minHeight: GlassMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

struct GlassSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value
    /// When set, segment `n` gets the identifier `<prefix>.<n>`, so UI tests need no labels.
    var accessibilityIdentifierPrefix: String?

    @Environment(\.glassPalette) private var palette

    var body: some View {
        // ExportNowG, CLIDestG, DiagnosticsG: the selected segment is a raised neutral
        // pill with bold text; the accent stays for chips and primary actions.
        HStack(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let isSelected = segment.value == selection
                Button {
                    selection = segment.value
                } label: {
                    Text(segment.title)
                        .glassFont(.caption)
                        .fontWeight(isSelected ? .bold : .medium)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.segmentedHeight)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(palette.glassStrong)
                                    .overlay(alignment: .top) {
                                        Capsule().strokeBorder(palette.hi, lineWidth: 1)
                                            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                                    }
                                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(accessibilityIdentifierPrefix.map { "\($0).\(index)" } ?? "")
            }
        }
        .padding(3)
        .background(Capsule().fill(palette.surface))
        .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
    }
}

struct GlassChip: View {
    let title: String
    var dotColor: Color?
    var isSelected = false
    let action: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Text(title).lineLimit(1)
            }
            // The boards' chips: 34pt tall, 14pt semibold.
            .glassFont(.chip)
            .foregroundStyle(isSelected ? palette.accentInk : palette.text)
            .padding(.horizontal, 14)
            .frame(minHeight: GlassMetrics.chipHeight)
            .background(Capsule().fill(isSelected ? palette.accent : palette.surface2))
            .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: GlassMetrics.touchTarget)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct StatusBadge: View {
    let title: String
    let status: CoverageStatus

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(palette.surface2))
    }

    private var color: Color {
        switch status {
        case .complete: return palette.ok
        case .partial, .inProgress: return palette.accent
        case .missing: return palette.coral
        case .notDue, .paused: return palette.muted
        }
    }
}

/// Original logo from https://developers.google.com/workspace/drive/api/guides/branding.
struct GoogleDriveConnectionButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image("GoogleDriveLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight)
        }
        .buttonStyle(GoogleDriveConnectionButtonStyle())
    }
}

private struct GoogleDriveConnectionButtonStyle: ButtonStyle {
    @Environment(\.glassPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassFont(.body)
            .fontWeight(.medium)
            .foregroundStyle(palette.text)
            .background(Capsule().fill(palette.surface2))
            .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
