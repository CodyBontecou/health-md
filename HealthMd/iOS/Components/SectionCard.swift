import SwiftUI

// MARK: - Compact Status Badge
// Liquid Glass pill-style status indicator with glow effects

struct CompactStatusBadge: View {
    let icon: String
    let title: String
    let isConnected: Bool
    let action: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))

                Text(LocalizedStringKey(title))
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)

                // Status dot with glow
                ZStack {
                    Circle()
                        .fill(isConnected ? Color.success : Color.textMuted)
                        .frame(width: 8, height: 8)
                        .blur(radius: isConnected ? 4 : 0)
                        .opacity(isConnected ? 0.6 : 0)

                    Circle()
                        .fill(isConnected ? Color.success : Color.textMuted)
                        .frame(width: 8, height: 8)
                }
            }
            .foregroundStyle(isConnected ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, Spacing.md + 2)
            .padding(.vertical, Spacing.sm + 2)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isConnected ? Color.success.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: isConnected ? Color.success.opacity(0.2) : Color.clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isConnected ? "Connected" : "Not connected")
        .accessibilityAddTraits(action != nil ? .isButton : [])
        .accessibilityHint(action != nil ? "Double tap to configure" : "")
    }
}

// MARK: - Section Card Container

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .glassCard()
    }
}

// MARK: - Health Connection Card

struct HealthConnectionCard: View {
    let isAuthorized: Bool
    let statusText: String
    let onConnect: () async throws -> Void

    @State private var isConnecting = false

    var body: some View {
        SectionCard {
            HStack(spacing: Spacing.md) {
                PulsingHeartIcon(isConnected: isAuthorized)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Apple Health")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)

                    StatusPill(status: isAuthorized ? .connected : .disconnected)
                }

                Spacer()

                if !isAuthorized {
                    SecondaryButton("Connect", icon: "arrow.right") {
                        Task {
                            isConnecting = true
                            defer { isConnecting = false }
                            try? await onConnect()
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Health, \(isAuthorized ? "Connected" : "Not connected")")
    }
}

// MARK: - Vault Selection Card

struct VaultSelectionCard: View {
    let vaultName: String
    let isSelected: Bool
    let onSelectVault: () -> Void
    let onClear: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    VaultIcon(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Obsidian Vault")
                            .font(Typography.headline())
                            .foregroundStyle(Color.textPrimary)

                        if isSelected {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accent)

                                Text(vaultName)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("No vault selected")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    SecondaryButton(
                        isSelected ? "Change Vault" : "Select Vault",
                        icon: "folder.badge.plus",
                        action: onSelectVault
                    )

                    if isSelected {
                        DestructiveButton(title: "Remove", action: onClear)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Obsidian Vault, \(isSelected ? vaultName : "Not selected")")
    }
}

// MARK: - Export Settings Card

struct ExportSettingsCard: View {
    @Binding var subfolder: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    let exportPath: String
    let onSubfolderChange: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Section header with Liquid Glass icon
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    Text("Export Settings")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                }

                // Subfolder input with Liquid Glass
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SUBFOLDER")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .tracking(2)

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accent)

                        TextField("Health", text: $subfolder)
                            .font(Typography.bodyMono())
                            .foregroundStyle(Color.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: subfolder) { _, _ in
                                onSubfolderChange()
                            }
                            .accessibilityLabel("Subfolder name")
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }

                // Date range pickers with Liquid Glass
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Start Date
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("START DATE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textMuted)
                            .tracking(2)

                        DatePicker(
                            selection: $startDate,
                            in: ...endDate,
                            displayedComponents: .date
                        ) {
                            Text("Start Date")
                        }
                        .datePickerStyle(.graphical)
                        .tint(.accent)
                        .colorScheme(.dark)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .accessibilityHint("Select the start date for your export range")
                    }

                    // End Date
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("END DATE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textMuted)
                            .tracking(2)

                        DatePicker(
                            selection: $endDate,
                            in: startDate...Date(),
                            displayedComponents: .date
                        ) {
                            Text("End Date")
                        }
                        .datePickerStyle(.graphical)
                        .tint(.accent)
                        .colorScheme(.dark)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .accessibilityHint("Select the end date for your export range")
                    }
                }

                // Export path preview with Liquid Glass
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.accent)
                            .blur(radius: 4)
                            .opacity(0.5)
                            .accessibilityHidden(true)

                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.accent)
                    }
                    .font(.system(size: 14, weight: .medium))

                    Text(exportPath)
                        .font(.footnote.weight(.medium).monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}
