#if os(macOS)
import SwiftUI

// MARK: - Menu Bar View — Destination Agent Popup

struct MacMenuBarView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService
    @ObservedObject private var historyManager = ExportHistoryManager.shared

    var body: some View {
        glassBody.glassTheme()
    }

    /// MacMenuBarG: status header, last export and folder, then Open, History and Quit.
    private var glassBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("HealthCrystalHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text("Mac destination")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(readinessText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(readinessIsPositive
                        ? Color.glassAdaptive(\.ok)
                        : Color.glassAdaptive(\.coral))
            }

            fact(String(localized: "Last export"), value: lastExportSummary)
            fact(String(localized: "Folder"), value: folderDetail, monospaced: vaultManager.hasVaultSelection)

            Rectangle()
                .fill(Color.glassAdaptive(\.line))
                .frame(height: 1)
                .accessibilityHidden(true)

            menuAction(String(localized: "Open Health.md"), shortcut: "⌘O") {
                showMainWindow()
            }
            .keyboardShortcut("o", modifiers: .command)
            menuAction(String(localized: "History")) {
                showMainWindow(destination: .history)
            }
            menuAction(String(localized: "Quit Health.md"), shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(Color.glassAdaptive(\.text))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Health.md Mac destination menu")
    }

    private func fact(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.glassAdaptive(\.muted))
            Text(value)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }

    private func menuAction(
        _ label: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.glassAdaptive(\.muted))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(
            shortcut.map { String(localized: "Keyboard shortcut: \($0)") } ?? ""
        )
    }

    // MARK: - State

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    /// The destination path with the home folder shortened to "~", as on the board.
    private var folderDetail: String {
        guard vaultManager.hasVaultSelection else { return String(localized: "Choose folder") }
        guard folderAccessHealthy else {
            return "\(vaultManager.vaultName): \(vaultManager.vaultAvailabilityText)"
        }
        guard let path = vaultManager.pathForDisplay else { return vaultManager.vaultName }
        return MacDisplayPath.abbreviatingHome(path)
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

    /// The newest history entry as "Today 11:02 PM · Oct 30 · 1 file", falling back to this
    /// session's result when there is no history yet.
    private var lastExportSummary: String {
        if let entry = historyManager.history.first {
            return entry.lastExportMenuLine
        }
        return sessionExportSummary ?? String(localized: "None yet")
    }

    private var sessionExportSummary: String? {
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

    private func showMainWindow(destination: MacSidebarNavigation.Destination? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        WindowManager.shared.openMainWindow?()
        if let destination {
            MacSidebarNavigation.request(destination)
        }
    }
}

#endif
