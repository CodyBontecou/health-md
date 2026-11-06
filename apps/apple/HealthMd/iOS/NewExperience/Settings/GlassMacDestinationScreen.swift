#if os(iOS)
import HealthMdConnectionCore
import SwiftUI

/// MacDestG. Same service calls, lock wrapping and validation as `SyncSettingsView`.
struct GlassMacDestinationScreen: View {
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.glassPalette) private var palette
    @AppStorage("syncEnabled") private var syncEnabled = false
    @AppStorage("manualIPLastHost") private var manualMacHost = ""
    @AppStorage("manualIPLastPort") private var manualMacPort = String(SyncService.manualIPPort)
    @State private var manualPairingCode = ""
    @ObservedObject private var requestRange = MacExportRequestRange.shared

    private let macAppURL = URL(string: "https://apps.apple.com/us/app/health-md/id6757763969")!

    private var shouldStartRuntimeServices: Bool {
        #if DEBUG
        !TestMode.isUITesting && !MarketingCapture.isActive
        #else
        !TestMode.isUITesting
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                GlassPanel {
                    GlassToggleRow(
                        title: String(localized: "Mac destination"),
                        subtitle: String(localized: "Advertise this iPhone on your local network"),
                        isOn: $syncEnabled
                    )
                    .accessibilityIdentifier(AccessibilityID.Sync.syncToggle)
                }
                .configurationChangesProtected()

                if syncEnabled {
                    statusPanel
                    manualIPPanel
                }

                GlassPanel {
                    Link(destination: macAppURL) {
                        GlassRow(title: String(localized: "Get Health.md for Mac")) {
                            GlassIconTile(systemImage: "desktopcomputer", color: .settingsTileBlue)
                        } trailing: {
                            HStack(spacing: 8) {
                                Text("App Store").glassFont(.body).foregroundStyle(palette.muted)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.muted)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("glass.macDestination.getMacApp")
                }

                if let error = syncService.lastError {
                    GlassBanner(
                        title: String(localized: "Connection Error"),
                        message: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }

                Text("The Mac writes files using the setup you choose on iPhone.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Health.md for Mac"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.macDestination")
        .onAppear {
            if syncEnabled && shouldStartRuntimeServices { syncService.startAdvertising() }
        }
        .onChange(of: syncEnabled) { _, isOn in
            if !TestMode.isUITesting {
                if isOn {
                    syncService.startAdvertising()
                    syncService.restoreSavedManualIPConnectionIfNeeded(afterUserEnabledSync: true)
                } else {
                    syncService.stopAdvertising()
                    syncService.disconnect()
                }
            }
            UIAccessibility.post(
                notification: .announcement,
                argument: isOn ? String(localized: "Mac destination enabled") : String(localized: "Mac destination disabled")
            )
        }
        .onChange(of: syncService.connectionState) { oldValue, newValue in
            guard oldValue != newValue else { return }
            let announcement: String
            switch newValue {
            case .connected:
                announcement = String(localized: "Connected to Mac")
                if syncService.activeTransport == .manualIP { manualPairingCode = "" }
            case .connecting: announcement = String(localized: "Connecting to Mac")
            case .disconnected: announcement = String(localized: "Disconnected from Mac")
            }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    private var statusPanel: some View {
        GlassPanel {
            GlassRow(title: connectionTitle, subtitle: connectionSubtitle) {
                if syncService.connectionState == .connecting { ProgressView() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.Sync.connectionStatus)
            if syncService.connectionState == .connected {
                if let activeJobID = syncService.macDestinationStatus?.activeJobID {
                    progressRow(activeJobID)
                    Button(role: .destructive) {
                        syncService.send(.macExportCancel(jobID: activeJobID))
                    } label: {
                        GlassRow(title: String(localized: "Cancel Mac export")) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(palette.coral)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    GlassRow(title: destinationTitle, subtitle: destinationSubtitle) { EmptyView() }
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Live progress of the Mac's active job, from the same progress messages the export
    /// screen uses. The Mac reports days written; the dates come from the job this iPhone
    /// started, and are left out for a job it did not start.
    private func progressRow(_ jobID: UUID) -> some View {
        let progress: MacExportProgress? = {
            if case .macExportProgress(let progress) = syncService.latestMacExportMessage,
               progress.jobID == jobID, progress.totalDays > 0 {
                return progress
            }
            return nil
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(progressText(progress, range: requestRange.rangeText(for: jobID)))
            .glassFont(.body)
            .foregroundStyle(palette.text)
            if let progress {
                ProgressView(value: min(max(progress.fractionComplete, 0), 1))
                    .tint(palette.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(palette.accent)
            }
        }
        .padding(GlassMetrics.panelPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("glass.macDestination.progress")
    }

    private func progressText(_ progress: MacExportProgress?, range: String?) -> String {
        switch (progress, range) {
        case let (progress?, range?):
            return String(localized: "Exporting \(range) to the Mac… \(progress.processedDays) of \(progress.totalDays)")
        case let (progress?, nil):
            return String(localized: "Exporting to the Mac… \(progress.processedDays) of \(progress.totalDays)")
        case let (nil, range?):
            return String(localized: "Exporting \(range) to the Mac…")
        case (nil, nil):
            return String(localized: "Exporting to the Mac…")
        }
    }

    private var manualIPPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Connect by IP"))
            GlassPanel {
                VStack(alignment: .leading, spacing: 0) {
                    labelledField(String(localized: "Mac IP or Tailscale address")) {
                        TextField(String("100.64.0.12"), text: $manualMacHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .accessibilityLabel(String(localized: "Mac IP or Tailscale address"))
                    }
                    labelledField(String(localized: "Port"), showsDivider: true) {
                        TextField(String(SyncService.manualIPPort), text: $manualMacPort)
                            .keyboardType(.numberPad)
                            .accessibilityLabel(String(localized: "Port"))
                    }
                    labelledField(String(localized: "Pairing code"), showsDivider: true) {
                        SecureField(
                            syncService.hasSavedManualIPConnection
                                ? String(localized: "Pairing code (not required)")
                                : String(localized: "From Mac → Manual IP"),
                            text: $manualPairingCode
                        )
                        .keyboardType(.numberPad)
                        .accessibilityLabel(String(localized: "Pairing code"))
                    }
                }
                .configurationChangesProtected()

                if syncService.hasSavedManualIPConnection {
                    Text("Paired with \(syncService.savedManualIPMacName ?? "Mac"). The connection is saved; no pairing code is required.")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                }

                VStack(spacing: 8) {
                    Button(manualIPButtonTitle) {
                        configurationProtection.performConfigurationChange { connectByManualIP() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(!canAttemptManualIPConnection)
                    if syncService.activeTransport == .manualIP {
                        Button("Disconnect") { syncService.disconnect() }
                            .glassFont(.caption)
                            .foregroundStyle(palette.accent)
                            .frame(minHeight: GlassMetrics.touchTarget)
                    }
                }
                .padding(GlassMetrics.panelPadding)
            }
            Text("On the Mac, open Mac Destination, enable Manual IP Connections and generate a pairing code.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
        }
    }

    /// MacDestG's field: caption above, input below.
    private func labelledField<Field: View>(
        _ label: String,
        showsDivider: Bool = false,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).glassFont(.caption).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            field()
                .textFieldStyle(.plain)
                .glassFont(.body)
                .foregroundStyle(palette.text)
                .frame(minHeight: 28)
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle().fill(palette.line).frame(height: 1)
                    .padding(.horizontal, GlassMetrics.panelPadding)
            }
        }
    }

    private var connectionTitle: String {
        switch syncService.connectionState {
        case .connected: return syncService.connectedPeerName ?? String(localized: "Connected to Mac")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected: return String(localized: "Waiting for Mac")
        }
    }

    private var connectionSubtitle: String {
        switch syncService.connectionState {
        case .connected:
            return syncService.activeTransport == .manualIP
                ? String(localized: "Connected · manual IP")
                : String(localized: "Connected · same network")
        case .connecting:
            return syncService.activeTransport == .manualIP
                ? String(localized: "Connecting to the entered Mac address…")
                : String(localized: "Establishing connection…")
        case .disconnected: return String(localized: "Open Health.md on your Mac to connect")
        }
    }

    private var canAttemptManualIPConnection: Bool {
        !manualMacHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (syncService.hasSavedManualIPConnection
                || !ManualIPSyncSecurity.normalizedPairingCode(manualPairingCode).isEmpty)
            && syncService.connectionState != .connecting
    }

    private var manualIPButtonTitle: String {
        syncService.connectionState == .connected && syncService.activeTransport == .manualIP
            ? String(localized: "Reconnect")
            : String(localized: "Connect")
    }

    private func connectByManualIP() {
        let port = UInt16(manualMacPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? SyncService.manualIPPort
        let pairingCode = ManualIPSyncSecurity.normalizedPairingCode(manualPairingCode)
        manualMacPort = String(port)
        if pairingCode.isEmpty && syncService.hasSavedManualIPConnection {
            syncService.connectToSavedManualMac(host: manualMacHost, port: port)
        } else {
            syncService.connectToManualMac(host: manualMacHost, port: port, pairingCode: pairingCode)
        }
    }

    private var destinationTitle: String {
        syncService.canExportToConnectedMac
            ? String(localized: "Ready for Mac Exports")
            : String(localized: "Mac Needs Attention")
    }

    private var destinationSubtitle: String {
        if syncService.canExportToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return String(localized: "Exports will be written to \(path)")
            }
            return String(localized: "Choose Connected Mac as the destination on an automation’s Output page.")
        }
        guard let capabilities = syncService.remoteCapabilities else {
            return String(localized: "Waiting for destination status from Mac.")
        }
        guard capabilities.platform == .macOS, capabilities.isCompatibleWithMacExportJobs else {
            return String(localized: "Update Health.md on Mac to receive iPhone-configured export jobs.")
        }
        guard let status = syncService.macDestinationStatus else {
            return String(localized: "Waiting for destination status from Mac.")
        }
        if status.activeJobID != nil { return String(localized: "Mac is currently writing another export.") }
        if !status.destinationFolderSelected { return String(localized: "Choose a destination folder in Health.md on Mac.") }
        if !status.folderAccessHealthy {
            let destination = status.destinationPathForDisplay
                ?? status.destinationDisplayName
                ?? String(localized: "the saved Mac folder")
            return String(localized: "Saved Mac destination \(destination) needs access. Re-select it in Health.md on Mac.")
        }
        return status.lastError ?? syncService.macExportReadinessMessage
    }
}
#endif
