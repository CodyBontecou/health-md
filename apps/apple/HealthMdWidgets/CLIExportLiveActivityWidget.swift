import ActivityKit
import SwiftUI
import WidgetKit

struct CLIExportLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CLIExportActivityAttributes.self) { context in
            CLIExportLockScreenView(context: context)
                .activityBackgroundTint(WidgetGlass.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.sourceLabel, systemImage: context.state.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.phaseColor)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    CLIExportProgressSummary(state: context.state)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "scope")
                            Text(context.attributes.targetLabel)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .privacySensitive()

                        Text(context.state.message)
                            .font(.caption)
                            .lineLimit(1)
                            .privacySensitive()

                        CLIExportProgressBar(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.iconName)
                    .foregroundStyle(context.state.phaseColor)
            } compactTrailing: {
                CLIExportCompactProgress(state: context.state)
            } minimal: {
                Image(systemName: context.state.iconName)
                    .foregroundStyle(context.state.phaseColor)
            }
            .keylineTint(context.state.phaseColor)
        }
    }
}

/// LiveActivityG: title and percentage, the progress bar, then "<dates> · to <target>"
/// beside the Reading → Sending steps. The status message stays in the Dynamic Island.
private struct CLIExportLockScreenView: View {
    let context: ActivityViewContext<CLIExportActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("WidgetAppIcon")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)

                Text(context.state.title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                CLIExportProgressSummary(state: context.state)
            }

            CLIExportProgressBar(state: context.state)

            HStack(spacing: 8) {
                Text(context.footerTarget)
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 8)
                CLIExportStepIndicator(state: context.state)
            }
            .font(.system(size: 12))
            .foregroundStyle(WidgetGlass.secondaryText)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// "Reading → Sending": the step in progress is bright, the other is dimmed. Phases outside
/// the two steps show their status instead.
private struct CLIExportStepIndicator: View {
    let state: CLIExportActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .capturing, .transferring:
            HStack(spacing: 4) {
                Text("Reading")
                    .foregroundStyle(state.phase == .capturing ? Color.white : WidgetGlass.secondaryText)
                    .fontWeight(state.phase == .capturing ? .semibold : .regular)
                Text(verbatim: "→")
                    .accessibilityHidden(true)
                Text("Sending")
                    .foregroundStyle(state.phase == .transferring ? Color.white : WidgetGlass.secondaryText)
                    .fontWeight(state.phase == .transferring ? .semibold : .regular)
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.phase == .capturing ? Text("Step 1 of 2, reading") : Text("Step 2 of 2, sending"))
        default:
            Text(state.shortStatus)
                .foregroundStyle(state.phaseColor)
                .lineLimit(1)
        }
    }
}

private extension ActivityViewContext<CLIExportActivityAttributes> {
    /// "Oct 24 – 30 · to <computer-name>" as in LiveActivityG. Without a known date range the
    /// day count stands in, and is left out until the total is known.
    var footerTarget: String {
        var parts: [String] = []
        if let range = CLIExportLiveActivityFormat.dateRange(
            start: attributes.dateRangeStart,
            end: attributes.dateRangeEnd
        ) {
            parts.append(range)
        } else if state.totalDays > 0 {
            parts.append(String(localized: "\(min(state.processedDays, state.totalDays)) of \(state.totalDays) days"))
        }
        parts.append(String(localized: "to \(attributes.targetLabel)"))
        return parts.joined(separator: " · ")
    }
}

enum CLIExportLiveActivityFormat {
    /// "Oct 24 – 30", or "Oct 24" for one day, in the current locale.
    static func dateRange(start: Date?, end: Date?, calendar: Calendar = .current) -> String? {
        guard let start, let end else { return nil }
        let lower = min(start, end)
        let upper = max(start, end)
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.dateTemplate = "MMMd"
        if calendar.isDate(lower, inSameDayAs: upper) {
            let single = DateFormatter()
            single.calendar = calendar
            single.setLocalizedDateFormatFromTemplate("MMMd")
            return single.string(from: lower)
        }
        return formatter.string(from: lower, to: upper)
    }
}

private struct CLIExportProgressBar: View {
    let state: CLIExportActivityAttributes.ContentState

    var body: some View {
        if let fraction = state.fractionComplete {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(state.phaseColor)
                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("CLI export progress")
                .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        } else if !state.isTerminal && state.phase != .paused {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(state.phaseColor)
                .accessibilityLabel("CLI export in progress")
        }
    }
}

private struct CLIExportProgressSummary: View {
    let state: CLIExportActivityAttributes.ContentState

    var body: some View {
        if let fraction = state.fractionComplete {
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(state.phaseColor)
        } else {
            Image(systemName: state.phase == .paused ? "pause.fill" : "ellipsis")
                .foregroundStyle(state.phaseColor)
        }
    }
}

private struct CLIExportCompactProgress: View {
    let state: CLIExportActivityAttributes.ContentState

    var body: some View {
        if let fraction = state.fractionComplete {
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(state.phaseColor)
        } else {
            Image(systemName: state.phase == .paused ? "pause.fill" : "ellipsis")
                .foregroundStyle(state.phaseColor)
        }
    }
}

private extension CLIExportActivityAttributes.ContentState {
    var title: String {
        switch phase {
        case .preparing: return "CLI export starting"
        case .capturing: return "Reading Health data"
        case .transferring: return "Sending CLI export"
        case .paused: return "CLI export paused"
        case .completed: return "CLI export complete"
        case .completedWithWarnings: return "Export completed with warnings"
        case .failed: return "CLI export failed"
        case .cancelled: return "CLI export cancelled"
        }
    }

    var shortStatus: String {
        switch phase {
        case .preparing: return "Starting"
        case .capturing: return "Reading"
        case .transferring: return "Sending"
        case .paused: return "Paused"
        case .completed: return "Complete"
        case .completedWithWarnings: return "Warnings"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var iconName: String {
        switch phase {
        case .preparing, .capturing: return "waveform.path.ecg"
        case .transferring: return "arrow.up.doc.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .completedWithWarnings: return "exclamationmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var phaseColor: Color {
        switch phase {
        case .failed, .cancelled: return WidgetGlass.coral
        case .completed: return WidgetGlass.ok
        case .completedWithWarnings, .paused: return WidgetGlass.amber
        case .preparing, .capturing, .transferring: return WidgetGlass.accent
        }
    }

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: committedBytes, countStyle: .file)
    }
}

/// Liquid Glass colours for the extension. These are the dark tokens, because these
/// surfaces are dark.
enum WidgetGlass {
    static let background = Color(red: 0x0E / 255, green: 0x0E / 255, blue: 0x11 / 255)
    static let accent = Color(red: 0xCD / 255, green: 0xB6 / 255, blue: 0xFF / 255)
    static let ok = Color(red: 0x8B / 255, green: 0xF0 / 255, blue: 0xB4 / 255)
    static let coral = Color(red: 0xFF / 255, green: 0xA1 / 255, blue: 0x84 / 255)
    static let amber = Color(red: 0xF2 / 255, green: 0xB2 / 255, blue: 0x66 / 255)
    static let covered = Color(red: 0x3B / 255, green: 0x30 / 255, blue: 0x58 / 255)
    static let secondaryText = Color(red: 0xDA / 255, green: 0xD4 / 255, blue: 0xE8 / 255)
    static let muted = Color(red: 0xB3 / 255, green: 0xAB / 255, blue: 0xC6 / 255)
    static let hrv = Color(red: 0x5E / 255, green: 0xD3 / 255, blue: 0xB0 / 255)

    /// WidgetActivityG ring and label colours.
    static let moveRing = Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x7A / 255)
    static let moveText = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x93 / 255)
    static let exercise = Color(red: 0xA6 / 255, green: 0xF2 / 255, blue: 0x5F / 255)
    static let stand = Color(red: 0x5E / 255, green: 0xD3 / 255, blue: 0xF2 / 255)

    /// The glass panel's fill, edge and top highlight (`rgba(255,255,255,…)` in the boards).
    static let panelFill = Color.white.opacity(0.06)
    static let panelEdge = Color.white.opacity(0.12)
    static let panelHighlight = Color.white.opacity(0.22)
    static let panelLowlight = Color.white.opacity(0.06)
    static let rowFill = Color.white.opacity(0.06)
}

/// The boards' glass panel, approximated for WidgetKit. Widgets cannot sample what is behind
/// them, so the 26 pt backdrop blur becomes a translucent white fill over the dark base; the
/// 1 pt edge and the inset top highlight are drawn as strokes on the container shape.
struct WidgetGlassPanelBackground: View {
    var body: some View {
        ZStack {
            WidgetGlass.background
            ContainerRelativeShape()
                .fill(WidgetGlass.panelFill)
            ContainerRelativeShape()
                .strokeBorder(WidgetGlass.panelEdge, lineWidth: 1)
            ContainerRelativeShape()
                .inset(by: 1)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: WidgetGlass.panelHighlight, location: 0),
                            .init(color: .clear, location: 0.18),
                            .init(color: .clear, location: 0.82),
                            .init(color: WidgetGlass.panelLowlight, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }
}

/// The crystal heart used as the brand mark on the glass widgets.
struct WidgetCrystalHeart: View {
    let size: CGFloat

    var body: some View {
        Image("HealthCrystalHeart")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
