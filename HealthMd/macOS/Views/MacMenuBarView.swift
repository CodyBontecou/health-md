#if os(macOS)
import SwiftUI

// MARK: - Menu Bar View — Destination Agent Popup

struct MacMenuBarView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService

    // Use semantic system colors in the menu bar popup so text contrast adapts
    // correctly to macOS material/vibrancy in both light and dark appearances.
    private var primaryTextColor: Color { .primary }
    private var secondaryTextColor: Color { .secondary }
    private var mutedTextColor: Color { .secondary.opacity(0.75) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 6) {
                statusRow(
                    label: "iPhone",
                    connected: syncService.connectionState == .connected,
                    detail: syncService.connectionState == .connected
                        ? syncService.connectedPeerName ?? "Connected"
                        : "Not connected"
                )

                statusRow(
                    label: "Destination",
                    connected: folderAccessHealthy,
                    detail: destinationDetail
                )

                statusRow(
                    label: "Readiness",
                    connected: readinessIsPositive,
                    detail: readinessText
                )

                if let lastExportSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(mutedTextColor)
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        Text("Last export:")
                            .foregroundStyle(mutedTextColor)
                        Text(lastExportSummary)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(BrandTypography.caption())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Last Mac export")
                    .accessibilityValue(lastExportSummary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().opacity(0.3)

            VStack(spacing: 2) {
                menuAction(
                    icon: vaultManager.vaultURL == nil ? "folder.badge.plus" : "folder",
                    label: vaultManager.vaultURL == nil ? "Choose Destination…" : "Change Destination…"
                ) {
                    chooseDestinationFolder()
                }

                menuAction(
                    icon: "macwindow",
                    label: "Open Mac Destination",
                    shortcut: "⌘0"
                ) {
                    WindowManager.shared.openMainWindow?()
                }

                menuAction(
                    icon: "gearshape",
                    label: "Destination Settings…",
                    shortcut: "⌘,"
                ) {
                    openSettingsWindow()
                }
            }
            .padding(.vertical, 4)

            Divider().opacity(0.3)

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text("Quit Health.md")
                        .font(BrandTypography.body())
                    Spacer()
                    Text("⌘Q")
                        .font(BrandTypography.caption())
                        .foregroundStyle(mutedTextColor)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(secondaryTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
            .accessibilityLabel("Quit Health.md")
            .accessibilityHint("Keyboard shortcut: Command Q")
        }
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Health.md Mac destination menu")
    }

    // MARK: - Components

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(Color.accent)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("health.md")
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(primaryTextColor)
                Text("Mac Destination")
                    .font(BrandTypography.caption())
                    .foregroundStyle(mutedTextColor)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func statusRow(label: String, connected: Bool, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? Color.success : mutedTextColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(label + ":")
                .foregroundStyle(mutedTextColor)
            Text(detail)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(BrandTypography.caption())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) status")
        .accessibilityValue("\(connected ? "Ready" : "Not ready"): \(detail)")
    }

    @ViewBuilder
    private func menuAction(
        icon: String,
        label: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accent)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(label)
                    .font(BrandTypography.body())
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(BrandTypography.caption())
                        .foregroundStyle(mutedTextColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(secondaryTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityLabel(label)
        .accessibilityHint(shortcut != nil ? "Keyboard shortcut: \(shortcut!)" : "")
    }

    // MARK: - State

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var destinationDetail: String {
        guard vaultManager.vaultURL != nil else { return "Choose folder" }
        return folderAccessHealthy ? vaultManager.vaultName : "Access denied"
    }

    private var readinessIsPositive: Bool {
        readinessText == "Ready"
    }

    private var readinessText: String {
        if syncService.isSyncing { return "Receiving export" }
        if syncService.connectionState != .connected { return "Connect iPhone" }
        if !iPhoneSupportsMacExports { return "Update iPhone app" }
        if vaultManager.vaultURL == nil { return "Choose folder" }
        if !folderAccessHealthy { return "Re-select folder" }
        return "Ready"
    }

    private var iPhoneSupportsMacExports: Bool {
        guard syncService.connectionState == .connected else { return false }
        guard let capabilities = syncService.remoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }

    private var lastExportSummary: String? {
        if let failure = syncService.lastMacExportFailure {
            return failure.message
        }
        if let result = syncService.lastMacExportResult {
            switch result.status {
            case .success:
                return "\(result.totalFilesWritten) file(s)"
            case .partialSuccess:
                return "Partial: \(result.totalFilesWritten) file(s)"
            case .failure:
                return "Failed"
            case .cancelled:
                return "Cancelled"
            }
        }
        return vaultManager.lastExportStatus
    }

    // MARK: - Actions

    private func chooseDestinationFolder() {
        MacFolderPicker.show { url in
            vaultManager.setVaultFolder(url)
        }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

#endif
