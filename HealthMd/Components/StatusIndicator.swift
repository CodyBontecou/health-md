import SwiftUI

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

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .shadow(color: status.color.opacity(0.6), radius: 4, x: 0, y: 0)

            Text(status.label)
                .font(.system(size: 13, weight: .medium))
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
    }
}

// MARK: - Health Icon
// Liquid Glass icon with soft glow when connected

struct PulsingHeartIcon: View {
    let isConnected: Bool

    var body: some View {
        ZStack {
            // Glow layer when connected
            if isConnected {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 8)
                    .opacity(0.6)
            }

            // Main icon
            Image(systemName: "heart.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isConnected ? Color.accent : Color.textMuted)
        }
        .frame(width: 48, height: 48)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Vault Icon
// Liquid Glass icon with soft glow when selected

struct VaultIcon: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Glow layer when selected
            if isSelected {
                Image(systemName: "folder.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 8)
                    .opacity(0.6)
            }

            // Main icon
            Image(systemName: "folder.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isSelected ? Color.accent : Color.textMuted)
        }
        .frame(width: 48, height: 48)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Export Status Badge
// Liquid Glass toast notification that slides up from bottom

struct ExportStatusBadge: View {
    enum StatusType {
        case success(String)
        case error(String)
    }

    let status: StatusType
    let onDismiss: () -> Void
    @State private var isVisible = false
    @State private var offset: CGFloat = 100

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon with glow
            ZStack {
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
            .font(.system(size: 18, weight: .medium))

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
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
        .offset(y: offset)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
                offset = 0
            }
        }
        .onTapGesture {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVisible = false
            offset = 100
        }

        // Call onDismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
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
