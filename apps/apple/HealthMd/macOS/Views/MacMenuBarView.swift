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
        glassBody.glassTheme()
    }

    /// MacMenuBarG, plus the destination and settings actions the app already offers.
    private var glassBody: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.panelPadding / 2) {
            HStack {
                Text("Mac Destination").font(.headline)
                Spacer()
                Text(readinessText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readinessIsPositive
                        ? Color.glassAdaptive(\.ok)
                        : Color.glassAdaptive(\.coral))
            }
            VStack(alignment: .leading, spacing: 8) {
                glassFact(String(localized: "iPhone"), value: syncService.connectionState == .connected
                    ? syncService.connectedPeerName ?? String(localized: "Connected")
                    : String(localized: "Not connected"))
                if let lastExportSummary {
                    glassFact(String(localized: "Last export"), value: lastExportSummary)
                }
                glassFact(String(localized: "Destination"), value: destinationDetail)
            }
            .padding(GlassMetrics.panelPadding * 0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: GlassMetrics.iconTileRadius * 1.4)

            menuAction(
                icon: vaultManager.hasVaultSelection ? "folder" : "folder.badge.plus",
                label: vaultManager.hasVaultSelection
                    ? String(localized: "Change Destination…")
                    : String(localized: "Choose Destination…"),
                action: chooseDestinationFolder
            )
            menuAction(icon: "macwindow", label: String(localized: "Open Mac Destination"), shortcut: "⌘0") {
                WindowManager.shared.openMainWindow?()
            }
            menuAction(
                icon: "gearshape",
                label: String(localized: "Destination Settings…"),
                shortcut: "⌘,",
                action: openSettingsWindow
            )
            menuAction(icon: "power", label: String(localized: "Quit Health.md"), shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Health.md Mac destination menu")
    }

    private func glassFact(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(secondaryTextColor)
            Text(value).font(.callout).lineLimit(1).truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
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
        guard vaultManager.hasVaultSelection else { return String(localized: "Choose folder") }
        return folderAccessHealthy
            ? vaultManager.vaultName
            : "\(vaultManager.vaultName): \(vaultManager.vaultAvailabilityText)"
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
        if !vaultManager.hasVaultSelection { return String(localized: "Choose folder") }
        if !folderAccessHealthy { return vaultManager.vaultAvailabilityText }
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
                   result.hasAuthoritativeFileCount,
                   result.totalFilesWritten == 0 {
                    return String(localized: "\(result.dailyNoteUpdateCount) daily notes updated")
                }
                return result.generatedFileCountDescription
                    ?? String(localized: "Export Complete")
            case .partialSuccess:
                if result.dailyNoteSkipCount > 0,
                   result.hasAuthoritativeFileCount,
                   result.totalFilesWritten == 0 {
                    return String(localized: "\(result.dailyNoteUpdateCount) updated, \(result.dailyNoteSkipCount) daily notes skipped")
                }
                if result.dailyNoteUpdateCount > 0,
                   result.hasAuthoritativeFileCount,
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
