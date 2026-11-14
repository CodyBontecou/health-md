#if os(iOS)
import SwiftUI

/// LargeConfirmG and HistoryWarnG: a dimmed scrim with a stacked-button decision card.
struct GlassDecisionDialog: View {
    struct Action: Identifiable {
        enum Role { case primary, secondary, cancel }
        let title: String
        var role: Role = .secondary
        var accessibilityIdentifier: String?
        let handler: () -> Void
        var id: String { title }
    }

    let title: String
    let message: String
    var messageAccessibilityIdentifier: String? = nil
    let actions: [Action]

    @Environment(\.glassPalette) private var palette

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .accessibilityIdentifier(messageAccessibilityIdentifier ?? "")
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        button(action)
                    }
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 420)
            .glassSurface(cornerRadius: GlassMetrics.dialogRadius, style: .strong)
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func button(_ action: Action) -> some View {
        Button(action: action.handler) {
            Text(action.title)
                .font(.system(size: 16, weight: action.role == .primary ? .semibold : .medium))
                .foregroundStyle(foreground(action.role))
                .frame(maxWidth: .infinity, minHeight: GlassMetrics.primaryButtonHeight)
                .background(Capsule().fill(action.role == .primary ? palette.accent : palette.surface2))
                .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
    }

    private func foreground(_ role: Action.Role) -> Color {
        switch role {
        case .primary: return palette.accentInk
        case .secondary: return palette.text
        case .cancel: return palette.muted
        }
    }
}
#endif
