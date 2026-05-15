import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Connection Status Pill
// Liquid Glass status indicator with soft glow

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
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 8

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: status.color.opacity(0.6), radius: 4, x: 0, y: 0)

            Text(status.label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, Spacing.sm + 2)
        .padding(.vertical, Spacing.xs + 2)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
        .accessibilityValue(status == .connected ? "Active" : "Inactive")
    }
}

// MARK: - Health Icon
// Liquid Glass icon with soft glow when connected

struct PulsingHeartIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isConnected: Bool
    @ScaledMetric(relativeTo: .title2) private var iconContainerSize: CGFloat = 48

    var body: some View {
        ZStack {
            // Glow layer when connected
            if isConnected && !reduceMotion {
                Image(systemName: "heart.fill")
                    .accessibilityHidden(true)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 8)
                    .opacity(0.6)
            }

            // Main icon
            Image(systemName: "heart.fill")
                .accessibilityHidden(true)
                .font(.title2.weight(.medium))
                .foregroundStyle(isConnected ? Color.accent : Color.textMuted)
        }
        .frame(width: iconContainerSize, height: iconContainerSize)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health connection")
        .accessibilityValue(isConnected ? "Connected" : "Not connected")
    }
}

// MARK: - Vault Icon
// Liquid Glass icon with soft glow when selected

struct VaultIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool
    @ScaledMetric(relativeTo: .title2) private var iconContainerSize: CGFloat = 48

    var body: some View {
        ZStack {
            // Glow layer when selected
            if isSelected && !reduceMotion {
                Image(systemName: "folder.fill")
                    .accessibilityHidden(true)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 8)
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }

            // Main icon
            Image(systemName: "folder.fill")
                .accessibilityHidden(true)
                .font(.title2.weight(.medium))
                .foregroundStyle(isSelected ? Color.accent : Color.textMuted)
        }
        .frame(width: iconContainerSize, height: iconContainerSize)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vault folder")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - Export Status Badge
// Liquid Glass toast notification that slides up from bottom

struct ExportStatusBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum StatusType {
        case success(String)
        case error(String)
    }

    let status: StatusType
    let onDismiss: () -> Void
    /// When provided on a success badge, tapping opens Files.app at this folder.
    var folderURL: URL? = nil
    @State private var isVisible = false
    @State private var offset: CGFloat = 100

    private var canOpenFolder: Bool {
        if case .success = status { return folderURL != nil }
        return false
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon with glow
            ZStack {
                if !reduceMotion {
                    Group {
                        switch status {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.success)
                                .blur(radius: 6)
                                .opacity(0.6)
                        case .error:
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(Color.error)
                                .blur(radius: 6)
                                .opacity(0.6)
                        }
                    }
                }

                Group {
                    switch status {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.success)
                    case .error:
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.error)
                    }
                }
            }
            .font(.title3.weight(.medium))

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if canOpenFolder {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.caption2.weight(.medium))
                        Text("Open in Files")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Color.success.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, Spacing.md + 4)
        .padding(.vertical, Spacing.sm + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
        .shadow(color: borderColor.opacity(0.3), radius: 8, x: 0, y: 2)
        .opacity(isVisible ? 1 : 0)
        .offset(y: reduceMotion ? 0 : offset)
        .onAppear {
            withOptionalMotionAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
                offset = 0
            }
            // Announce to VoiceOver users
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
    
    private var statusAccessibilityValue: String {
        switch status {
        case .success: return "Success"
        case .error: return "Error"
        }
    }

    private func dismiss() {
        withOptionalMotionAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVisible = false
            offset = 100
        }

        // Call onDismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.3)) {
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

    /// Open Files.app navigated to `url`. Falls back to the Files root if the
    /// system can't open the file URL directly.
    private func openInFiles(_ url: URL) {
        // `UIApplication.open` with a file:// URL opens Files.app and navigates
        // to that location on iOS when the file/folder is accessible.
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                // Fallback: open Files.app at its root
                if let filesRoot = URL(string: "shareddocuments://") {
                    UIApplication.shared.open(filesRoot)
                }
            }
        }
    }

    private var message: String {
        switch status {
        case .success(let msg), .error(let msg):
            return msg
        }
    }

    private var messageColor: Color {
        switch status {
        case .success: return .success
        case .error: return .error
        }
    }

    private var borderColor: Color {
        switch status {
        case .success: return .success
        case .error: return .error
        }
    }
}

// MARK: - Deprecated Effects
// Shimmer removed - too decorative for minimal aesthetic

extension View {
    func shimmer() -> some View {
        self // Return self without shimmer
    }
}
