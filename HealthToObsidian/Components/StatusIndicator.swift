import SwiftUI

// MARK: - Connection Status Pill

struct StatusPill: View {
    enum Status {
        case connected
        case disconnected
        case pending

        var color: Color {
            switch self {
            case .connected: return .successGlow
            case .disconnected: return .textMuted
            case .pending: return .healthAmber
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
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing && status == .connected ? 1.3 : 1)
                .opacity(isPulsing && status == .connected ? 0.7 : 1)

            Text(status.label)
                .font(Typography.label())
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, Spacing.sm + 4)
        .padding(.vertical, Spacing.xs + 2)
        .background(
            Capsule()
                .fill(status.color.opacity(0.15))
        )
        .onAppear {
            if status == .connected {
                withAnimation(AnimationTimings.pulse) {
                    isPulsing = true
                }
            }
        }
    }
}

// MARK: - Pulsing Heart Icon

struct PulsingHeartIcon: View {
    let isConnected: Bool
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Glow layer
            if isConnected {
                Image(systemName: "heart.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.healthCoral)
                    .blur(radius: 10)
                    .opacity(isPulsing ? 0.8 : 0.4)
            }

            // Main icon
            Image(systemName: "heart.fill")
                .font(.system(size: 28))
                .foregroundStyle(
                    isConnected
                        ? AppGradients.healthGradient
                        : LinearGradient(colors: [.textMuted], startPoint: .top, endPoint: .bottom)
                )
                .scaleEffect(isPulsing && isConnected ? 1.1 : 1)
        }
        .frame(width: 50, height: 50)
        .onAppear {
            if isConnected {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: isConnected) { _, newValue in
            if newValue {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

// MARK: - Vault Icon

struct VaultIcon: View {
    let isSelected: Bool
    @State private var isGlowing = false

    var body: some View {
        ZStack {
            // Glow layer
            if isSelected {
                Image(systemName: "cube.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.obsidianPurple)
                    .blur(radius: 10)
                    .opacity(isGlowing ? 0.6 : 0.3)
            }

            // Crystal/vault icon
            Image(systemName: "cube.fill")
                .font(.system(size: 26))
                .foregroundStyle(
                    isSelected
                        ? AppGradients.obsidianGradient
                        : LinearGradient(colors: [.textMuted], startPoint: .top, endPoint: .bottom)
                )
                .rotationEffect(.degrees(isGlowing && isSelected ? 5 : -5))
        }
        .frame(width: 50, height: 50)
        .onAppear {
            if isSelected {
                withAnimation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    isGlowing = true
                }
            }
        }
    }
}

// MARK: - Export Status Badge

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
                        .foregroundStyle(.successGlow)
                        .symbolEffect(.bounce, value: isVisible)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.errorGlow)
                        .symbolEffect(.bounce, value: isVisible)
                }
            }
            .font(.system(size: 16, weight: .medium))

            Text(message)
                .font(Typography.caption())
                .foregroundStyle(messageColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            withAnimation(AnimationTimings.springBouncy) {
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
        case .success: return .successGlow
        case .error: return .errorGlow
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .success: return .successGlow.opacity(0.1)
        case .error: return .errorGlow.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch status {
        case .success: return .successGlow.opacity(0.3)
        case .error: return .errorGlow.opacity(0.3)
        }
    }
}

// MARK: - Loading Shimmer

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.1),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}
