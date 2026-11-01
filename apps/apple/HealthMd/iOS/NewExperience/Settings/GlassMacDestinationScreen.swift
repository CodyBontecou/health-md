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
                        title: String(localized: "Enable Mac Destination"),
                        subtitle: String(localized: "Advertise this iPhone on your local network so Health.md on Mac can connect."),
                        isOn: $syncEnabled
                    )
                    .accessibilityIdentifier(AccessibilityID.Sync.syncToggle)
                }
                .configurationChangesProtected()

                if syncEnabled {
                    statusPanel
                    manualIPPanel
                } else {
                    Link(destination: macAppURL) {
                        GlassPanel {
                            GlassRow(
                                title: String(localized: "Health.md for macOS"),
                                subtitle: String(localized: "Download from the App Store")
                            ) {
                                Image(systemName: "arrow.up.right").foregroundStyle(palette.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
        .navigationTitle(String(localized: "Mac Destination"))
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
                GlassRow(title: destinationTitle, subtitle: destinationSubtitle) { EmptyView() }
                    .accessibilityElement(children: .combine)
                if syncService.macDestinationStatus?.activeJobID != nil {
                    Button(role: .destructive) {
                        guard let jobID = syncService.macDestinationStatus?.activeJobID else { return }
                        syncService.send(.macExportCancel(jobID: jobID))
                    } label: {
                        GlassRow(title: String(localized: "Cancel Active Mac Export")) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(palette.coral)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var manualIPPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Connect by IP Address"))
            GlassPanel {
                VStack(spacing: 12) {
                    TextField("Mac Tailscale IP or hostname", text: $manualMacHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $manualMacPort)
                        .keyboardType(.numberPad)
                    SecureField(
                        syncService.hasSavedManualIPConnection ? "Pairing code (not required)" : "Pairing code",
                        text: $manualPairingCode
                    )
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Pairing code")
                }
                .textFieldStyle(.plain)
                .glassFont(.body)
                .foregroundStyle(palette.text)
                .padding(GlassMetrics.panelPadding)
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
            Text("On your Mac, open Mac Destination, enable Manual IP Connections, and generate a pairing code.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
        }
    }

    private var connectionTitle: String {
        switch syncService.connectionState {
        case .connected: return String(localized: "Connected to \(syncService.connectedPeerName ?? "Mac")")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected: return String(localized: "Waiting for Mac")
        }
    }

    private var connectionSubtitle: String {
        switch syncService.connectionState {
        case .connected:
            return syncService.activeTransport == .manualIP
                ? String(localized: "Connected by manual IP / Tailscale; check destination readiness below")
                : String(localized: "Connected locally; check destination readiness below")
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
            return String(localized: "Select Connected Mac in the Export tab.")
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
