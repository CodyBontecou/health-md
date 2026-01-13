import SwiftUI

// MARK: - Connection Status Pill
// Minimal status indicator - no animations

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
                .frame(width: 6, height: 6)

            Text(status.label)
                .font(Typography.label())
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.bgTertiary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Health Icon
// Minimal icon - no pulse, no glow

struct PulsingHeartIcon: View {
    let isConnected: Bool

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(isConnected ? .accent : .textMuted)
            .frame(width: 44, height: 44)
    }
}

// MARK: - Vault Icon
// Minimal icon - no rotation, no glow

struct VaultIcon: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(isSelected ? .accent : .textMuted)
            .frame(width: 44, height: 44)
    }
}

// MARK: - Export Status Badge
// Minimal status message - simple fade in

struct ExportStatusBadge: View {
    enum StatusType {
        case success(String)
        case error(String)
    }

    let status: StatusType
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                switch status {
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.success)
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.error)
                }
            }
            .font(.system(size: 14, weight: .medium))

            Text(message)
                .font(Typography.body())
                .foregroundStyle(messageColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(AnimationTimings.smooth) {
                isVisible = true
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
