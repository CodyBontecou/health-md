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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: context.state.iconName)
                    .foregroundStyle(context.state.phaseColor)
                    .font(.headline)

                Text(context.state.title)
                    .font(.headline)

                Spacer(minLength: 8)

                Text(context.attributes.sourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Image(systemName: "scope")
                Text(context.attributes.targetLabel)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .privacySensitive()

            Text(context.state.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .privacySensitive()

            CLIExportProgressBar(state: context.state)

            HStack(spacing: 14) {
                if context.state.totalDays > 0 {
                    Label(
                        "\(min(context.state.processedDays, context.state.totalDays)) of \(context.state.totalDays) days",
                        systemImage: "calendar"
                    )
                }
                if context.state.committedBytes > 0 {
                    Label(context.state.formattedBytes, systemImage: "arrow.up.doc")
                } else if context.state.committedPartitions > 0 {
                    Label(
                        "\(context.state.committedPartitions) sent",
                        systemImage: "arrow.up.doc"
                    )
                }
                Spacer(minLength: 0)
                Text(context.state.shortStatus)
                    .foregroundStyle(context.state.phaseColor)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct CLIExportProgressBar: View {
    let state: CLIExportActivityAttributes.ContentState

    var body: some View {
        if let fraction = state.fractionComplete {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(state.phaseColor)
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
                .font(.headline.monospacedDigit())
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
}
