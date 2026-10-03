#if os(iOS)
import SwiftUI

struct ExportActivityBannerDetail: Equatable, Identifiable {
    let text: String
    let systemImage: String

    var id: String { "\(systemImage):\(text)" }
}

struct ExportActivityBannerAction {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let perform: () -> Void
}

/// Shared visual shell for export activity presented at the top of the iOS app.
/// Lifecycle ownership stays with each caller so manual exports do not affect
/// CLI tracking or Live Activities.
struct ExportActivityBanner: View {
    let title: String
    let systemImage: String
    let tint: Color
    let sourceLabel: String
    let targetLabel: String
    let message: String
    let progress: Double?
    let showsIndeterminateProgress: Bool
    let progressAccessibilityLabel: String
    let details: [ExportActivityBannerDetail]
    let trailingText: String?
    let accessibilityIdentifier: String
    let action: ExportActivityBannerAction?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        systemImage: String,
        tint: Color,
        sourceLabel: String,
        targetLabel: String,
        message: String,
        progress: Double?,
        showsIndeterminateProgress: Bool,
        progressAccessibilityLabel: String,
        details: [ExportActivityBannerDetail],
        trailingText: String?,
        accessibilityIdentifier: String,
        action: ExportActivityBannerAction? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.sourceLabel = sourceLabel
        self.targetLabel = targetLabel
        self.message = message
        self.progress = progress
        self.showsIndeterminateProgress = showsIndeterminateProgress
        self.progressAccessibilityLabel = progressAccessibilityLabel
        self.details = details
        self.trailingText = trailingText
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: Spacing.s2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(sourceLabel)
                        .font(.caption2.weight(.semibold))
                    Text(targetLabel)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.bgSecondary))
                .privacySensitive()
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                let clampedProgress = min(max(progress, 0), 1)
                let percent = Int((clampedProgress * 100).rounded())
                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .accessibilityLabel(progressAccessibilityLabel)
                    .accessibilityValue(String(localized: "\(percent) percent complete"))
            } else if showsIndeterminateProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .accessibilityLabel(progressAccessibilityLabel)
            }

            if !details.isEmpty || trailingText != nil || action != nil {
                activityFooter
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .fill(Color.bgPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var activityFooter: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalFooter
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalFooter
                verticalFooter
            }
        }
    }

    private var horizontalFooter: some View {
        HStack(spacing: Spacing.s3) {
            ForEach(details) { detail in
                Label(detail.text, systemImage: detail.systemImage)
            }
            Spacer(minLength: 0)
            if let trailingText {
                Text(trailingText)
            }
            if let action {
                actionButton(action)
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.textMuted)
    }

    private var verticalFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(details) { detail in
                Label(detail.text, systemImage: detail.systemImage)
            }
            if let trailingText {
                Text(trailingText)
            }
            if let action {
                HStack {
                    Spacer(minLength: 0)
                    actionButton(action)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ action: ExportActivityBannerAction) -> some View {
        Button(role: .destructive, action: action.perform) {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.error)
                .padding(.horizontal, Spacing.s2)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .fill(Color.error.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(Color.error.opacity(0.22), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }
}

struct ManualExportActivityBanner: View {
    let target: ExportTargetSelection
    let progress: Double
    let message: String
    let onCancel: () -> Void

    var body: some View {
        ExportActivityBanner(
            title: String(localized: "Export in Progress"),
            systemImage: systemImage,
            tint: Color.accent,
            sourceLabel: String(localized: "iPhone"),
            targetLabel: targetLabel,
            message: message.isEmpty ? String(localized: "Exporting") : message,
            progress: progress,
            showsIndeterminateProgress: false,
            progressAccessibilityLabel: String(localized: "Export progress"),
            details: [],
            trailingText: nil,
            accessibilityIdentifier: AccessibilityID.Export.activityBanner,
            action: ExportActivityBannerAction(
                title: String(localized: "Stop Export"),
                systemImage: "stop.fill",
                accessibilityIdentifier: AccessibilityID.Export.cancelExportButton,
                perform: onCancel
            )
        )
    }

    private var targetLabel: String {
        switch target {
        case .localIPhoneFolder:
            return String(localized: "Local iPhone Folder")
        case .connectedMac:
            return String(localized: "Connected Mac")
        case .apiEndpoint:
            return String(localized: "API Endpoint")
        }
    }

    private var systemImage: String {
        switch target {
        case .localIPhoneFolder: return "folder.fill"
        case .connectedMac: return "desktopcomputer"
        case .apiEndpoint: return "network"
        }
    }
}
#endif
