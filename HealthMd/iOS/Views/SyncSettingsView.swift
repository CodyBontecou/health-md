import SwiftUI

// MARK: - Sync Settings View (iOS)

struct SyncSettingsView: View {
    @EnvironmentObject var syncService: SyncService
    @AppStorage("syncEnabled") private var syncEnabled = false

    private let macAppURL = URL(string: "https://apps.apple.com/us/app/health-md/id6757763969")!

    var body: some View {
        List {
            syncToggleSection
            downloadMacSection
            connectionSection
            macExportFlowSection
            errorSection
        }
        .navigationTitle("Mac Destination")
        .onAppear {
            if syncEnabled && !TestMode.isUITesting {
                syncService.startAdvertising()
            }
        }
        .onChange(of: syncService.connectionState) { oldValue, newValue in
            guard oldValue != newValue else { return }
            let announcement: String
            switch newValue {
            case .connected: announcement = "Connected to Mac"
            case .connecting: announcement = "Connecting to Mac"
            case .disconnected: announcement = "Disconnected from Mac"
            }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    // MARK: - Sections

    private var syncToggleSection: some View {
        Section {
            Toggle("Enable Mac Destination", isOn: $syncEnabled)
                .onChange(of: syncEnabled) { _, newValue in
                    if newValue {
                        if !TestMode.isUITesting {
                            syncService.startAdvertising()
                        }
                        UIAccessibility.post(notification: .announcement, argument: "Mac destination enabled")
                    } else {
                        if !TestMode.isUITesting {
                            syncService.stopAdvertising()
                            syncService.disconnect()
                        }
                        UIAccessibility.post(notification: .announcement, argument: "Mac destination disabled")
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Sync.syncToggle)
                .accessibilityLabel("Mac export destination")
                .accessibilityValue(syncEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Double tap to \(syncEnabled ? "disable" : "enable") this Mac as an export destination")
        } footer: {
            Text("When enabled, Health.md on Mac can connect locally and appear as a Connected Mac target in the Export tab. Configure formats, metrics, dates, filenames, and write mode on iPhone, then tap Export to send the job to Mac.")
        }
    }

    @ViewBuilder
    private var downloadMacSection: some View {
        if !syncEnabled {
            Section {
                Link(destination: macAppURL) {
                    downloadMacLinkContent
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Download Health.md for macOS")
                .accessibilityHint("Double tap to open download page in browser")
                .accessibilityAddTraits(.isLink)
            }
        }
    }

    private var downloadMacLinkContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(Typography.headline())
                .foregroundStyle(Color.accent)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("DOWNLOAD FOR")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)
                Text("macOS")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(Typography.headline())
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accent.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var connectionSection: some View {
        if syncEnabled {
            Section {
                connectionStatusRow
                if syncService.connectionState == .connected {
                    destinationStatusRow
                }
            } header: {
                Text("Connection")
            }
        }
    }

    private var connectionStatusRow: some View {
        HStack {
            connectionStatusIcon
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                Text(connectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Sync.connectionStatus)
        .accessibilityLabel("Connection status")
        .accessibilityValue("\(connectionTitle). \(connectionSubtitle)")
    }

    private var destinationStatusRow: some View {
        HStack {
            Image(systemName: destinationStatusIcon)
                .foregroundStyle(destinationStatusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(destinationStatusTitle)
                Text(destinationStatusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac destination readiness")
        .accessibilityValue("\(destinationStatusTitle). \(destinationStatusSubtitle)")
    }

    @ViewBuilder
    private var macExportFlowSection: some View {
        if syncEnabled {
            Section {
                Label("Open Health.md on Mac and choose a destination folder", systemImage: "1.circle")
                Label("Return to the iPhone Export tab", systemImage: "2.circle")
                Label("Choose Connected Mac and tap Export", systemImage: "3.circle")
            } header: {
                Text("Export to Mac")
            } footer: {
                Text("The Mac app no longer has a separate export setup flow. It receives the iPhone-configured export job and writes files to the folder selected on Mac.")
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = syncService.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Error")
                    .accessibilityValue(error)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var connectionStatusIcon: some View {
        switch syncService.connectionState {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .disconnected:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        }
    }

    private var connectionTitle: String {
        switch syncService.connectionState {
        case .connected:
            return "Connected to \(syncService.connectedPeerName ?? "Mac")"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Waiting for Mac"
        }
    }

    private var connectionSubtitle: String {
        switch syncService.connectionState {
        case .connected: return "Connected locally; check destination readiness below"
        case .connecting: return "Establishing connection…"
        case .disconnected: return "Open Health.md on your Mac to connect"
        }
    }

    private var destinationStatusIcon: String {
        syncService.canExportToConnectedMac ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var destinationStatusColor: Color {
        syncService.canExportToConnectedMac ? .green : .orange
    }

    private var destinationStatusTitle: String {
        syncService.canExportToConnectedMac ? "Ready for Mac exports" : "Mac needs attention"
    }

    private var destinationStatusSubtitle: String {
        if syncService.canExportToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return "Exports will be written to \(path)"
            }
            return "Select Connected Mac in the Export tab."
        }

        guard let capabilities = syncService.remoteCapabilities else {
            return "Waiting for destination status from Mac."
        }
        guard capabilities.platform == .macOS,
              capabilities.isCompatibleWithMacExportJobs else {
            return "Update Health.md on Mac to receive iPhone-configured export jobs."
        }
        guard let status = syncService.macDestinationStatus else {
            return "Waiting for destination status from Mac."
        }
        if status.activeJobID != nil { return "Mac is currently writing another export." }
        if !status.destinationFolderSelected { return "Choose a destination folder in Health.md on Mac." }
        if !status.folderAccessHealthy { return "Re-select the Mac destination folder to restore write access." }
        return status.lastError ?? syncService.macExportReadinessMessage
    }
}
