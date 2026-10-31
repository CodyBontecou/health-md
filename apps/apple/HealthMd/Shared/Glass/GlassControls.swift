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

struct GlassToggleStyle: ToggleStyle {
    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
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

    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection
                Button {
                    selection = segment.value
                } label: {
                    Text(segment.title)
                        .glassFont(.caption)
                        .foregroundStyle(isSelected ? palette.accentInk : palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.segmentedHeight)
                        .background(Capsule().fill(isSelected ? palette.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
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
            .glassFont(.body)
            .foregroundStyle(isSelected ? palette.accentInk : palette.text)
            .padding(.horizontal, 16)
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
