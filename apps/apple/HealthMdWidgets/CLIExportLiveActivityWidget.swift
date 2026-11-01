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

private struct CLIExportLockScreenView: View {
    let context: ActivityViewContext<CLIExportActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("WidgetAppIcon")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)

                Text(context.state.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                CLIExportProgressSummary(state: context.state)
            }

            Text(context.state.message)
                .font(.caption)
                .foregroundStyle(WidgetGlass.secondaryText)
                .lineLimit(2)
                .privacySensitive()

            CLIExportProgressBar(state: context.state)

            HStack(spacing: 8) {
                Text(context.footerTarget)
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 8)
                Text(context.attributes.sourceLabel)
                    .lineLimit(1)
                Text(context.state.shortStatus)
                    .foregroundStyle(context.state.phaseColor)
            }
            .font(.caption)
            .foregroundStyle(WidgetGlass.secondaryText)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private extension ActivityViewContext<CLIExportActivityAttributes> {
    /// "3 of 7 days · to Mac" as in LiveActivityG; days are left out until the total is known.
    var footerTarget: String {
        var parts: [String] = []
        if state.totalDays > 0 {
            parts.append("\(min(state.processedDays, state.totalDays)) of \(state.totalDays) days")
        }
        if state.committedBytes > 0 {
            parts.append(state.formattedBytes)
        } else if state.committedPartitions > 0 {
            parts.append("\(state.committedPartitions) sent")
        }
        parts.append("to \(attributes.targetLabel)")
        return parts.joined(separator: " · ")
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
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
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
}
