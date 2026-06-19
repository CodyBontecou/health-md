import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Geist Status Pill

struct StatusPill: View {
    enum Status {
        case connected
        case disconnected
        case pending

        var color: Color {
            switch self {
            case .connected: return .success
            case .disconnected: return .textMuted
            case .pending: return .warning
            }
        }

        var label: String {
            switch self {
            case .connected: return "Connected"
            case .disconnected: return "Not Connected"
            case .pending: return "Pending"
            }
        }
    }

    let status: Status
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Circle()
                .fill(status.color)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)

            Text(status.label)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(status.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(status.color.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
        .accessibilityValue(status == .connected ? "Active" : "Inactive")
    }
}

// MARK: - Symbol Containers

struct PulsingHeartIcon: View {
    let isConnected: Bool
    @ScaledMetric(relativeTo: .title2) private var iconContainerSize: CGFloat = 48

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 20, weight: .medium, design: .default))
            .foregroundStyle(isConnected ? Color.accent : Color.textMuted)
            .frame(width: iconContainerSize, height: iconContainerSize)
            .background(isConnected ? Color.accentSubtle : Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isConnected ? Color.accent.opacity(0.25) : Color.borderSubtle, lineWidth: 1)
                    .accessibilityHidden(true)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Health connection")
            .accessibilityValue(isConnected ? "Connected" : "Not connected")
    }
}

struct VaultIcon: View {
    let isSelected: Bool
    @ScaledMetric(relativeTo: .title2) private var iconContainerSize: CGFloat = 48

    var body: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 20, weight: .medium, design: .default))
            .foregroundStyle(isSelected ? Color.accent : Color.textMuted)
            .frame(width: iconContainerSize, height: iconContainerSize)
            .background(isSelected ? Color.accentSubtle : Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Color.accent.opacity(0.25) : Color.borderSubtle, lineWidth: 1)
                    .accessibilityHidden(true)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vault folder")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - Export Toast

struct ExportStatusBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum StatusType {
        case success(String)
        case error(String)
    }

    let status: StatusType
    let onDismiss: () -> Void
    var folderURL: URL? = nil

    @State private var isVisible = false
    @State private var offset: CGFloat = 80

    private var canOpenFolder: Bool {
        if case .success = status { return folderURL != nil }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: statusIcon)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(statusColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(message)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if canOpenFolder {
                    HStack(spacing: Spacing.s1) {
                        Image(systemName: "folder.fill")
                            .font(.caption2.weight(.medium))
                            .accessibilityHidden(true)
                        Text("Open in Files")
                            .font(Typography.label())
                    }
                    .foregroundStyle(Color.success)
                }
            }

            Spacer(minLength: Spacing.s2)
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(statusColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        .opacity(isVisible ? 1 : 0)
        .offset(y: reduceMotion ? 0 : offset)
        .onAppear {
            withOptionalMotionAnimation(AnimationTimings.standard) {
                isVisible = true
                offset = 0
            }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .onTapGesture {
            if canOpenFolder, let url = folderURL {
                openInFiles(url)
            }
            dismiss()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(canOpenFolder ? "\(message). Open in Files" : message)
        .accessibilityValue(statusAccessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(canOpenFolder ? "Double tap to open exported files in Files app" : "Double tap to dismiss")
    }

    private var message: String {
        switch status {
        case .success(let msg), .error(let msg): return msg
        }
    }

    private var statusIcon: String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .success: return .success
        case .error: return .error
        }
    }

    private var statusAccessibilityValue: String {
        switch status {
        case .success: return "Success"
        case .error: return "Error"
        }
    }

    private func dismiss() {
        withOptionalMotionAnimation(AnimationTimings.standard) {
            isVisible = false
            offset = 80
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.2)) {
            onDismiss()
        }
    }

    private func withOptionalMotionAnimation(_ animation: Animation, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    private func openInFiles(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { success in
            if !success, let filesRoot = URL(string: "shareddocuments://") {
                UIApplication.shared.open(filesRoot)
            }
        }
    }
}

extension View {
    func shimmer() -> some View { self }
}
