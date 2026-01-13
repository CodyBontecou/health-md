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
// Minimal layout with clear hierarchy

struct HealthConnectionCard: View {
    let isAuthorized: Bool
    let statusText: String
    let onConnect: () async throws -> Void

    @State private var isConnecting = false

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Label
                Text("APPLE HEALTH")
                    .font(Typography.labelUppercase())
                    .foregroundStyle(.textMuted)
                    .tracking(1.5)

                // Status and action
                HStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        PulsingHeartIcon(isConnected: isAuthorized)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isAuthorized ? "Connected" : "Not Connected")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(.textPrimary)

                            Text(isAuthorized ? "Health data access enabled" : "Tap connect to enable")
                                .font(Typography.caption())
                                .foregroundStyle(.textSecondary)
                        }
                    }

                    Spacer()

                    if !isAuthorized {
                        SecondaryButton("Connect") {
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
}

// MARK: - Vault Selection Card
// Clean vault selection interface

struct VaultSelectionCard: View {
    let vaultName: String
    let isSelected: Bool
    let onSelectVault: () -> Void
    let onClear: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Label
                Text("OBSIDIAN VAULT")
                    .font(Typography.labelUppercase())
                    .foregroundStyle(.textMuted)
                    .tracking(1.5)

                // Status
                HStack(spacing: Spacing.sm) {
                    VaultIcon(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isSelected ? vaultName : "No vault selected")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)

                        Text(isSelected ? "Export destination" : "Select vault folder")
                            .font(Typography.caption())
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer()
                }

                // Actions
                HStack(spacing: Spacing.sm) {
                    SecondaryButton(
                        isSelected ? "Change" : "Select Vault",
                        icon: "folder",
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
// Minimal settings interface

struct ExportSettingsCard: View {
    @Binding var subfolder: String
    @Binding var selectedDate: Date
    let exportPath: String
    let onSubfolderChange: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Section header
                Text("EXPORT SETTINGS")
                    .font(Typography.labelUppercase())
                    .foregroundStyle(.textMuted)
                    .tracking(1.5)

                // Subfolder input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Subfolder")
                        .font(Typography.caption())
                        .foregroundStyle(.textSecondary)

                    TextField("Health", text: $subfolder)
                        .font(Typography.mono())
                        .foregroundStyle(.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.borderDefault, lineWidth: 1)
                        )
                        .onChange(of: subfolder) { _, _ in
                            onSubfolderChange()
                        }
                }

                // Date picker
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Date")
                        .font(Typography.caption())
                        .foregroundStyle(.textSecondary)

                    DatePicker(
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    ) {
                        EmptyView()
                    }
                    .datePickerStyle(.graphical)
                    .tint(.accent)
                    .colorScheme(.dark)
                    .padding(Spacing.sm)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.borderDefault, lineWidth: 1)
                    )
                }

                // Export path preview
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Export path")
                        .font(Typography.caption())
                        .foregroundStyle(.textSecondary)

                    Text(exportPath)
                        .font(Typography.mono())
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.borderSubtle, lineWidth: 1)
                        )
                }
            }
        }
    }
}
