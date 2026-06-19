import SwiftUI

// MARK: - Compact Status Badge

struct CompactStatusBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let title: String
    let statusText: String
    let isConnected: Bool
    let action: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(isConnected ? Color.accent : Color.textMuted)
                    .accessibilityHidden(true)

                Text(LocalizedStringKey(title))
                    .font(Typography.label())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(LocalizedStringKey(statusText))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isConnected ? Color.success : Color.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isConnected ? Color.success.opacity(0.12) : Color.bgSecondary)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isConnected ? Color.success.opacity(0.24) : Color.borderSubtle, lineWidth: 1)
                    )
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(isPressed ? Color.controlPressed : Color.controlBackground)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isConnected ? Color.accent.opacity(0.24) : Color.borderSubtle, lineWidth: 1))
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.98 : 1.0))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation { isPressed = pressing }
        }, perform: {})
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(statusText)")
        .accessibilityValue(isConnected ? "Connected" : "Not connected")
        .accessibilityAddTraits(action != nil ? .isButton : [])
        .accessibilityHint(action != nil ? "Double tap to configure" : "")
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(AnimationTimings.fast, updates)
        }
    }
}

// MARK: - Section Card Container

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .geistCard()
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
            HStack(spacing: Spacing.s4) {
                PulsingHeartIcon(isConnected: isAuthorized)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Apple Health")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)

                    StatusPill(status: isAuthorized ? .connected : .disconnected)
                }

                Spacer()

                if !isAuthorized {
                    SecondaryButton(isConnecting ? "Connecting…" : "Connect", icon: "arrow.right") {
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
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HStack(spacing: Spacing.s4) {
                    VaultIcon(isSelected: isSelected)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Obsidian Vault")
                            .font(Typography.headline())
                            .foregroundStyle(Color.textPrimary)

                        Text(isSelected ? vaultName : "No vault selected")
                            .font(Typography.caption())
                            .foregroundStyle(isSelected ? Color.textSecondary : Color.textMuted)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                HStack(spacing: Spacing.s2) {
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
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(spacing: Spacing.s3) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(Color.accent)
                        .frame(width: 32, height: 32)
                        .background(Color.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                        .accessibilityHidden(true)

                    Text("Export Settings")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)
                }

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Subfolder")
                        .font(Typography.label())
                        .foregroundStyle(Color.textSecondary)

                    HStack(spacing: Spacing.s2) {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.accent)
                            .accessibilityHidden(true)

                        TextField("Health", text: $subfolder)
                            .font(Typography.mono())
                            .foregroundStyle(Color.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: subfolder) { _, _ in onSubfolderChange() }
                            .accessibilityLabel("Subfolder name")
                    }
                    .geistInsetCard(cornerRadius: GeistRadius.sm, padding: Spacing.s3)
                }

                VStack(alignment: .leading, spacing: Spacing.s4) {
                    DatePicker("Start Date", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.accent)
                        .geistInsetCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
                        .accessibilityHint("Select the start date for your export range")

                    DatePicker("End Date", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.accent)
                        .geistInsetCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
                        .accessibilityHint("Select the end date for your export range")
                }

                HStack(spacing: Spacing.s2) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)

                    Text(exportPath)
                        .font(Typography.monoCaptionEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                }
                .geistInsetCard(cornerRadius: GeistRadius.sm, padding: Spacing.s3)
            }
        }
    }
}
