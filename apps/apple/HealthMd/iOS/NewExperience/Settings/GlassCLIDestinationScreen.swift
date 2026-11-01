#if os(iOS)
import HealthMdConnectionCore
import SwiftUI

/// CLIDestG. Pairing, wake and transport rules are unchanged from `SyncSettingsView`:
/// Nearby never falls back to Manual IP, and links opened by other apps never auto-pair.
struct GlassCLIDestinationScreen: View {
    @EnvironmentObject private var directCLIService: IPhoneDirectCLIService
    @EnvironmentObject private var directWakeManager: IPhoneDirectWakeManager
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.glassPalette) private var palette
    @AppStorage(IPhoneDirectCLIService.enabledKey) private var directCLIEnabled = false
    @AppStorage(IPhoneDirectCLIService.hostKey) private var directCLIHost = ""
    @AppStorage(IPhoneDirectCLIService.portKey) private var directCLIPort = String(HealthMdDirectProtocol.defaultManualIPPort)
    @AppStorage(IPhoneDirectCLIService.transportKey) private var directCLITransport = DirectTransportKind.manualIP.rawValue
    @State private var pairingCode = ""
    @State private var showScanner = false

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
                        title: String(localized: "Enable Direct CLI Access"),
                        subtitle: String(localized: "New commands require Health.md to be open. An active export can continue briefly in the background."),
                        isOn: enabled
                    )
                    .accessibilityIdentifier(AccessibilityID.Sync.directCLIToggle)
                }

                if directCLIService.needsPairingCode, directCLIService.pendingPairingLink == nil {
                    Button {
                        configurationProtection.performConfigurationChange { showScanner = true }
                    } label: {
                        Label("Scan Pairing QR", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(directCLIService.isConnecting)
                    .accessibilityIdentifier(AccessibilityID.Sync.directCLIScanButton)
                    .accessibilityHint("Opens the in-app camera scanner and pairs as soon as a valid QR is recognized")
                    Text("Start pairing from healthmd or your MCP client, then scan its QR here. Health.md does not auto-pair from links opened by other apps.")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                }

                if let link = directCLIService.pendingPairingLink { handoffPanel(link) }

                if directCLIEnabled {
                    GlassPanel {
                        GlassRow(title: statusTitle, subtitle: statusSubtitle) {
                            if directCLIService.isConnecting { ProgressView() }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if directCLIService.pendingPairingLink == nil {
                        if directCLIService.needsPairingCode {
                            manualPairing
                        } else {
                            pairedPanel
                        }
                    }
                }

                if directCLIService.hasPairedCLI { wakePanel }

                if let error = directCLIService.lastError {
                    GlassBanner(title: error, systemImage: "exclamationmark.triangle", tone: .warning)
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "CLI"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.cliDestination")
        .onAppear {
            if directCLIEnabled && shouldStartRuntimeServices { directCLIService.setEnabled(true) }
        }
        .onChange(of: directCLIService.isConnected) { _, connected in
            if connected { pairingCode = "" }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DirectCLIPairingScannerView { link in
                configurationProtection.performConfigurationChange {
                    directCLIService.handleScannedPairingLink(link)
                }
            }
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { directCLIEnabled },
            set: { isOn in
                configurationProtection.performConfigurationChange {
                    directCLIEnabled = isOn
                    directCLIService.setEnabled(isOn)
                }
            }
        )
    }

    private var transport: Binding<String> {
        Binding(
            get: { directCLITransport },
            set: { value in
                configurationProtection.performConfigurationChange {
                    directCLITransport = value
                    directCLIService.updateTransport(DirectTransportKind(rawValue: value) ?? .manualIP)
                }
            }
        )
    }

    private var wake: Binding<Bool> {
        Binding(
            get: {
                if case .enrolled = directWakeManager.state { return true }
                return false
            },
            set: { isOn in
                configurationProtection.performConfigurationChange {
                    Task { @MainActor in
                        if isOn {
                            await directWakeManager.enable()
                        } else {
                            await directWakeManager.disable()
                        }
                    }
                }
            }
        )
    }

    private func handoffPanel(_ link: IPhoneDirectCLIPairingLink) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("Pairing from QR", systemImage: "qrcode.viewfinder")
                    .glassFont(.navTitle)
                    .foregroundStyle(palette.text)
                Text(handoffMessage(link)).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                if !directCLIService.isConnecting, directCLIService.lastError != nil {
                    Button("Retry QR pairing") { directCLIService.retryPendingPairingLink() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                }
                Button("Cancel", role: .cancel) { directCLIService.cancelPendingPairingLink() }
                    .frame(minHeight: GlassMetrics.touchTarget)
            }
            .padding(GlassMetrics.panelPadding)
        }
    }

    private var manualPairing: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSegmentedControl(
                segments: [
                    .init(value: DirectTransportKind.nearby.rawValue, title: String(localized: "Nearby")),
                    .init(value: DirectTransportKind.manualIP.rawValue, title: String(localized: "Manual IP"))
                ],
                selection: transport
            )
            GlassPanel {
                VStack(spacing: 12) {
                    if directCLITransport == DirectTransportKind.manualIP.rawValue {
                        TextField("Mac IP or Tailscale address", text: $directCLIHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Port", text: $directCLIPort)
                            .keyboardType(.numberPad)
                    }
                    SecureField("20-digit pairing code", text: $pairingCode)
                        .keyboardType(.numberPad)
                }
                .textFieldStyle(.plain)
                .glassFont(.body)
                .foregroundStyle(palette.text)
                .padding(GlassMetrics.panelPadding)
                .configurationChangesProtected()
                Button("Pair with healthmd") {
                    configurationProtection.performConfigurationChange { connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(!canConnect)
                .padding(GlassMetrics.panelPadding)
            }
            if directCLITransport == DirectTransportKind.nearby.rawValue {
                Text("Nearby discovers the pairing command on the same local network. It never falls back to Manual IP.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
            Text("Current healthmd versions use one 20-digit code on iOS and Android. Six-digit entry remains available only for a legacy CLI.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
        }
    }

    private var pairedPanel: some View {
        GlassPanel {
            Text("Paired with \(directCLIService.pairedCLIName ?? "healthmd CLI") via \(transportLabel). Commands connect on demand while access is enabled.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(GlassMetrics.panelPadding)
            Button(role: .destructive) {
                configurationProtection.performConfigurationChange {
                    directCLIService.forgetPairedCLI()
                    pairingCode = ""
                }
            } label: {
                GlassRow(title: String(localized: "Forget Pairing")) {
                    Image(systemName: "trash").foregroundStyle(palette.coral)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var wakePanel: some View {
        GlassPanel {
            GlassToggleRow(
                title: String(localized: "Allow paired computers to send wake requests"),
                subtitle: String(localized: "Get a notification when the CLI is waiting for this phone, so unlocking and opening Health.md finishes the same command. Requires the wake service; the CLI keeps waiting without it."),
                isOn: wake
            )
            .disabled(directWakeManager.state == .enrolling)
            if case .unavailable(let reason) = directWakeManager.state {
                Text(reason)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .padding(GlassMetrics.panelPadding)
            }
        }
    }

    private func handoffMessage(_ link: IPhoneDirectCLIPairingLink) -> String {
        // A port is an address component, not a locale-formatted quantity.
        let port = String(link.port)
        if directCLIService.isConnecting {
            return String(localized: "Connecting automatically to healthmd at \(link.host):\(port). Keep Health.md open until pairing completes.")
        }
        if directCLIService.isPairingHandoffWaitingForActiveOperation {
            return String(localized: "Waiting for the active direct operation to finish, then Health.md will connect automatically to \(link.host):\(port).")
        }
        return String(localized: "Scanning this QR inside Health.md authorizes a one-time connection to healthmd at \(link.host):\(port).")
    }

    private var statusTitle: String {
        if directCLIService.isConnected {
            return String(localized: "Connected to \(directCLIService.connectedCLIName ?? "healthmd")")
        }
        if directCLIService.isConnecting { return String(localized: "Pairing with healthmd…") }
        return directCLIService.hasPairedCLI ? String(localized: "Ready for healthmd") : String(localized: "Pair a healthmd CLI")
    }

    private var statusSubtitle: String {
        if directCLIService.isConnected {
            return String(localized: "The authenticated CLI can request status, raw data, or generated export files.")
        }
        if directCLIService.isConnecting {
            return String(localized: "Keep this screen open while the first authenticated connection completes.")
        }
        if directCLIService.hasPairedCLI {
            return String(localized: "Access is on. The paired CLI can connect when you run a direct command; no new code is required.")
        }
        return String(localized: "Scan a fresh QR from healthmd above, or choose the same transport and enter its one-time code manually.")
    }

    private var transportLabel: String {
        directCLITransport == DirectTransportKind.nearby.rawValue ? String(localized: "Nearby") : String(localized: "Manual IP")
    }

    private var canConnect: Bool {
        let hasHost = !directCLIHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let digits = ManualIPSyncSecurity.normalizedPairingCode(pairingCode).utf8.count
        let hasCode = digits == DirectPairingSecurity.sharedPairingCodeDigits
            || digits == DirectPairingSecurity.legacyPairingCodeDigits
        let transportReady = directCLITransport == DirectTransportKind.nearby.rawValue || hasHost
        return transportReady && !directCLIService.isConnecting && (!directCLIService.needsPairingCode || hasCode)
    }

    private func connect() {
        let port = UInt16(directCLIPort.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? HealthMdDirectProtocol.defaultManualIPPort
        directCLIPort = String(port)
        directCLIService.connect(
            host: directCLIHost,
            port: port,
            pairingCode: ManualIPSyncSecurity.normalizedPairingCode(pairingCode)
        )
    }
}
#endif
