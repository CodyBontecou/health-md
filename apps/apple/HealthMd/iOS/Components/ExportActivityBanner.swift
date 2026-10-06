#if os(iOS)
import SwiftUI

struct ExportActivityBannerDetail: Equatable, Identifiable {
    let text: String
    let systemImage: String

    var id: String { "\(systemImage):\(text)" }
}

struct ExportActivityBannerAction: Identifiable {
    enum Style: Equatable {
        case standard
        case success
        case destructive
    }

    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let style: Style
    let perform: () -> Void

    var id: String { accessibilityIdentifier }

    init(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        style: Style = .destructive,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.style = style
        self.perform = perform
    }
}

/// Shared visual shell for persistent activity and transient status feedback.
/// Callers retain lifecycle ownership and update the same card from progress to
/// its terminal state instead of swapping between unrelated banner/toast views.
struct ExportActivityBanner: View {
    let title: String
    let systemImage: String
    let tint: Color
    let sourceLabel: String?
    let targetLabel: String?
    let message: String
    let progress: Double?
    let showsIndeterminateProgress: Bool
    let progressAccessibilityLabel: String
    let details: [ExportActivityBannerDetail]
    let trailingText: String?
    let accessibilityIdentifier: String
    let actions: [ExportActivityBannerAction]
    let onDismiss: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        systemImage: String,
        tint: Color,
        sourceLabel: String? = nil,
        targetLabel: String? = nil,
        message: String,
        progress: Double?,
        showsIndeterminateProgress: Bool,
        progressAccessibilityLabel: String,
        details: [ExportActivityBannerDetail],
        trailingText: String?,
        accessibilityIdentifier: String,
        action: ExportActivityBannerAction? = nil,
        actions: [ExportActivityBannerAction] = [],
        onDismiss: (() -> Void)? = nil
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
        self.actions = actions.isEmpty ? (action.map { [$0] } ?? []) : actions
        self.onDismiss = onDismiss
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
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.s2)

                if sourceLabel != nil || targetLabel != nil {
                    VStack(alignment: .trailing, spacing: 1) {
                        if let sourceLabel {
                            Text(sourceLabel)
                                .font(.caption2.weight(.semibold))
                        }
                        if let targetLabel {
                            Text(targetLabel)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.bgSecondary))
                    .privacySensitive()
                }

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            if !details.isEmpty || trailingText != nil || !actions.isEmpty {
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
        .accessibilityLabel(message.isEmpty ? title : "\(title). \(message)")
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
            ForEach(actions) { action in
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
            if !actions.isEmpty {
                VStack(alignment: .trailing, spacing: Spacing.s2) {
                    ForEach(actions) { action in
                        actionButton(action)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ action: ExportActivityBannerAction) -> some View {
        Button(role: action.style == .destructive ? .destructive : nil, action: action.perform) {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(actionForeground(for: action.style))
                .padding(.horizontal, Spacing.s2)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .fill(actionBackground(for: action.style))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(actionBorder(for: action.style), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }

    private func actionForeground(for style: ExportActivityBannerAction.Style) -> Color {
        switch style {
        case .standard: return .accent
        case .success: return .successText
        case .destructive: return .error
        }
    }

    private func actionBackground(for style: ExportActivityBannerAction.Style) -> Color {
        switch style {
        case .standard: return Color.accent.opacity(0.08)
        case .success: return Color.success.opacity(0.10)
        case .destructive: return Color.error.opacity(0.08)
        }
    }

    private func actionBorder(for style: ExportActivityBannerAction.Style) -> Color {
        switch style {
        case .standard: return Color.accent.opacity(0.22)
        case .success: return Color.success.opacity(0.28)
        case .destructive: return Color.error.opacity(0.22)
        }
    }
}
#endif
