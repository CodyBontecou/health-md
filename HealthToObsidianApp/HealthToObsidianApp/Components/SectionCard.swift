import SwiftUI

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
                        .foregroundStyle(.textPrimary)

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
                            .foregroundStyle(.textPrimary)

                        if isSelected {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.obsidianPurple)

                                Text(vaultName)
                                    .font(Typography.caption())
                                    .foregroundStyle(.textSecondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("No vault selected")
                                .font(Typography.caption())
                                .foregroundStyle(.textMuted)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    SecondaryButton(
                        isSelected ? "Change Vault" : "Select Vault",
                        icon: "folder.badge.plus",
                        color: .obsidianPurple,
                        action: onSelectVault
                    )

                    if isSelected {
                        DestructiveButton(title: "Remove", action: onClear)
                    }
                }
            }
        }
    }
}

// MARK: - Export Settings Card

struct ExportSettingsCard: View {
    @Binding var subfolder: String
    @Binding var selectedDate: Date
    let exportPath: String
    let onSubfolderChange: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Section header
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.textSecondary)

                    Text("Export Settings")
                        .font(Typography.headline())
                        .foregroundStyle(.textPrimary)
                }

                // Subfolder input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SUBFOLDER")
                        .font(Typography.label())
                        .foregroundStyle(.textMuted)
                        .tracking(1)

                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "folder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.textMuted)

                        TextField("Health", text: $subfolder)
                            .font(Typography.bodyMono())
                            .foregroundStyle(.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: subfolder) { _, _ in
                                onSubfolderChange()
                            }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm + 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.glassBorder, lineWidth: 1)
                    )
                }

                // Date picker
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("DATE")
                        .font(Typography.label())
                        .foregroundStyle(.textMuted)
                        .tracking(1)

                    DatePicker(
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    ) {
                        EmptyView()
                    }
                    .datePickerStyle(.graphical)
                    .tint(.obsidianPurple)
                    .colorScheme(.dark)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.bgSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.glassBorder, lineWidth: 1)
                    )
                }

                // Export path preview
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.obsidianViolet)

                    Text(exportPath)
                        .font(Typography.caption())
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.obsidianPurple.opacity(0.1))
                )
            }
        }
    }
}
