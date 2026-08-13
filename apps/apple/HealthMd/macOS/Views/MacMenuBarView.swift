#if os(macOS)
import SwiftUI

// MARK: - Menu Bar View — Destination Agent Popup

struct MacMenuBarView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService
    @Environment(\.openSettings) private var openSettings

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
                    label: String(localized: "iPhone"),
                    connected: syncService.connectionState == .connected,
                    detail: syncService.connectionState == .connected
                        ? syncService.connectedPeerName ?? String(localized: "Connected")
                        : String(localized: "Not connected")
                )

                statusRow(
                    label: String(localized: "Destination"),
                    connected: folderAccessHealthy,
                    detail: destinationDetail
                )

                statusRow(
                    label: String(localized: "Readiness"),
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
                    label: vaultManager.vaultURL == nil
                        ? String(localized: "Choose Destination…")
                        : String(localized: "Change Destination…")
                ) {
                    chooseDestinationFolder()
                }

                menuAction(
                    icon: "macwindow",
                    label: String(localized: "Open Mac Destination"),
                    shortcut: "⌘0"
                ) {
                    WindowManager.shared.openMainWindow?()
                }

                menuAction(
                    icon: "gearshape",
                    label: String(localized: "Destination Settings…"),
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
        .accessibilityValue(
            String(localized: "\(connected ? String(localized: "Ready") : String(localized: "Not ready")): \(detail)")
        )
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
        .accessibilityHint(
            shortcut.map { String(localized: "Keyboard shortcut: \($0)") } ?? ""
        )
    }

    // MARK: - State

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var destinationDetail: String {
        guard vaultManager.vaultURL != nil else { return String(localized: "Choose folder") }
        return folderAccessHealthy ? vaultManager.vaultName : String(localized: "Access denied")
    }

    private var readinessIsPositive: Bool {
        syncService.connectionState == .connected
            && iPhoneSupportsMacExports
            && folderAccessHealthy
            && !syncService.isSyncing
    }

    private var readinessText: String {
        if syncService.isSyncing { return String(localized: "Receiving export") }
        if syncService.connectionState != .connected { return String(localized: "Connect iPhone") }
        if !iPhoneSupportsMacExports { return String(localized: "Update iPhone app") }
        if vaultManager.vaultURL == nil { return String(localized: "Choose folder") }
        if !folderAccessHealthy { return String(localized: "Re-select folder") }
        return String(localized: "Ready")
    }

    private var iPhoneSupportsMacExports: Bool {
        guard syncService.connectionState == .connected else { return false }
        guard let capabilities = syncService.remoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }

    private var lastExportSummary: String? {
        if let failure = syncService.lastMacExportFailure {
            return localizedFailureSummary(failure.reason)
        }
        if let result = syncService.lastMacExportResult {
            switch result.status {
            case .success:
                if result.dailyNoteUpdateCount > 0,
                   result.isTotalFilesWrittenAuthoritative,
                   result.totalFilesWritten == 0 {
                    return String(localized: "\(result.dailyNoteUpdateCount) daily notes updated")
                }
                return result.generatedFileCountDescription
                    ?? String(localized: "Export Complete")
            case .partialSuccess:
                if result.dailyNoteSkipCount > 0,
                   result.isTotalFilesWrittenAuthoritative,
                   result.totalFilesWritten == 0 {
                    return String(localized: "\(result.dailyNoteUpdateCount) updated, \(result.dailyNoteSkipCount) daily notes skipped")
                }
                if result.dailyNoteUpdateCount > 0,
                   result.isTotalFilesWrittenAuthoritative,
                   result.totalFilesWritten == 0 {
                    return String(localized: "Partial: \(result.dailyNoteUpdateCount) daily notes updated")
                }
                return result.generatedFileCountDescription.map { "Partial: \($0)" }
                    ?? String(localized: "Export Partial")
            case .failure:
                return String(localized: "Failed")
            case .cancelled:
                return String(localized: "Cancelled")
            }
        }
        return vaultManager.localizedLastExportStatus
    }

    private func localizedFailureSummary(_ reason: MacExportFailureReason) -> String {
        switch reason {
        case .incompatibleProtocol:
            return String(localized: "Update Health.md on both devices")
        case .noMacFolderSelected:
            return String(localized: "Choose a destination folder")
        case .macFolderAccessDenied:
            return String(localized: "Destination folder access denied")
        case .noFormatsSelected:
            return String(localized: "No export formats selected")
        case .noHealthRecordsReceived:
            return String(localized: "No health records received")
        case .payloadDecodeFailure:
            return String(localized: "Export data could not be read")
        case .exportWriteFailure:
            return String(localized: "Export files could not be written")
        case .macBusy:
            return String(localized: "Mac is busy with another export")
        case .cancelled:
            return String(localized: "Cancelled")
        }
    }

    // MARK: - Actions

    private func chooseDestinationFolder() {
        MacFolderPicker.show { url in
            vaultManager.setVaultFolder(url)
        }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

#endif
