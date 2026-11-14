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
    @AppStorage(IPhoneDirectCLIService.portKey) private var savedDirectCLIPort = String(HealthMdDirectProtocol.defaultManualIPPort)
    @State private var directCLIPort = String(HealthMdDirectProtocol.defaultManualIPPort)
    @AppStorage(IPhoneDirectCLIService.transportKey) private var directCLITransport = DirectTransportKind.manualIP.rawValue
    @State private var pairingCode = ""
    @State private var showScanner = false
    @State private var showsCodeEntry = false
    @ObservedObject private var history = ExportHistoryManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var enterCodeAfterScanner = false
    @FocusState private var pairingCodeFocused: Bool
    private let pairingMethods = DirectCLIPairingMethodStore()

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
                        title: String(localized: "Direct CLI access"),
                        subtitle: String(localized: "healthmd connects while Health.md is open"),
                        isOn: enabled
                    )
                    .accessibilityIdentifier(AccessibilityID.Sync.directCLIToggle)
                }
                note(String(localized: "New commands need the app open. An active export can finish briefly in the background."))

                if directCLIService.needsPairingCode, directCLIService.pendingPairingLink == nil {
                    Button {
                        configurationProtection.performConfigurationChange { showScanner = true }
                    } label: {
                        Label(String(localized: "Scan pairing QR"), systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(directCLIService.isConnecting)
                    .accessibilityIdentifier(AccessibilityID.Sync.directCLIScanButton)
                    .accessibilityHint("Opens the in-app camera scanner and pairs as soon as a valid QR is recognized")
                    if directCLIEnabled, horizontalSizeClass == .regular, !showsCodeEntry {
                        Button(String(localized: "Enter 20-digit code")) { showsCodeEntry = true }
                            .glassFont(.body)
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                            .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
                            .accessibilityIdentifier("glass.cli.enterCode")
                    }
                }

                if let link = directCLIService.pendingPairingLink { handoffPanel(link) }

                if directCLIEnabled {
                    if directCLIService.isConnected || directCLIService.isConnecting {
                        GlassPanel {
                            GlassRow(title: statusTitle, subtitle: statusSubtitle) {
                                if directCLIService.isConnecting { ProgressView() }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if directCLIService.pendingPairingLink == nil,
                       directCLIService.needsPairingCode,
                       horizontalSizeClass != .regular || showsCodeEntry {
                        manualPairing
                    }
                }

                if directCLIService.hasPairedCLI { pairedSection }

                GlassPanel {
                    VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                        Text("Agent export permissions").glassFont(.body)
                        AgentExportPermissionsSetupControls()
                    }
                }

                note(String(localized: "Nearby discovers pairing on the same network and never falls back to Manual IP. Health.md never auto-pairs from links opened by other apps."))

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
        .navigationTitle(String(localized: "healthmd CLI"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.cliDestination")
        .onAppear {
            directCLIPort = savedDirectCLIPort
            if directCLIEnabled && shouldStartRuntimeServices { directCLIService.setEnabled(true) }
            if directCLIService.pendingPairingLink != nil { pairingMethods.noteAttempt(.qr) }
        }
        .onChange(of: directCLIService.pendingPairingLink) { _, link in
            // Scanned in Health.md or opened from the camera, a pairing link is a QR pairing.
            if link != nil { pairingMethods.noteAttempt(.qr) }
        }
        .onChange(of: directCLIService.isConnected) { _, connected in
            if connected { pairingCode = "" }
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            if enterCodeAfterScanner {
                enterCodeAfterScanner = false
                // The code form only exists while Direct CLI access is on; the scanner is
                // reachable with it off, so choosing to enter a code turns access on.
                if !directCLIEnabled { enabled.wrappedValue = true }
                showsCodeEntry = true
                pairingCodeFocused = true
            }
        }) {
            DirectCLIPairingScannerView(onPairingLink: { link in
                configurationProtection.performConfigurationChange {
                    directCLIService.handleScannedPairingLink(link)
                }
            }, onEnterCode: { enterCodeAfterScanner = true })
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
            GlassSectionLabel(title: String(localized: "Or enter code"))
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    if directCLITransport == DirectTransportKind.manualIP.rawValue {
                        TextField("Mac IP or Tailscale address", text: $directCLIHost)
                            .accessibilityLabel(Text("Mac IP or Tailscale address"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Port", text: $directCLIPort)
                            .keyboardType(.numberPad)
                            .accessibilityLabel(Text("Port"))
                        if ManualConnectionPort.parse(directCLIPort) == nil {
                            Text("Enter a port from 1 to 65535.")
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.coral)
                        }
                    }
                    SecureField("20-digit pairing code", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .focused($pairingCodeFocused)
                    Text("Six-digit codes still work with older CLI versions.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.muted)
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
        }
    }

    private var pairedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Paired"))
            GlassPanel {
                GlassRow(
                    title: directCLIService.pairedCLIName ?? String(localized: "healthmd CLI"),
                    subtitle: pairedSubtitle
                ) {
                    GlassSettingsBadge(title: String(localized: "Paired"), tone: directCLIEnabled ? .ok : .off)
                }
                .accessibilityElement(children: .combine)
                GlassToggleRow(
                    title: String(localized: "Wake requests"),
                    subtitle: horizontalSizeClass == .regular
                        ? String(localized: "Notify me when the CLI is waiting")
                        : String(localized: "Notify me when the CLI is waiting for this phone"),
                    isOn: wake
                )
                .disabled(directWakeManager.state == .enrolling)
                .overlay(alignment: .top) { divider }
                if case .unavailable(let reason) = directWakeManager.state {
                    Text(reason)
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .padding(.bottom, 8)
                }
                Button(role: .destructive) {
                    configurationProtection.performConfigurationChange {
                        directCLIService.forgetPairedCLI()
                        pairingMethods.forget()
                        pairingCode = ""
                    }
                } label: {
                    Text("Forget pairing")
                        .glassFont(.body)
                        .foregroundStyle(palette.coral)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { divider }
            }
        }
    }

    /// "Paired via QR · last used today". The phone records when it paired, how (from the
    /// attempt that made the pairing) and the direct exports it served, not status-only commands.
    private var pairedSubtitle: String? {
        let pairedAt = directCLIService.pairedCLIPairedAt
        let method: String? = switch pairingMethods.method(forPairingAt: pairedAt) {
        case .qr: String(localized: "Paired via QR")
        case .code: String(localized: "Paired via code")
        case nil: nil
        }
        // Pairing is itself a use, so the later of the two is the honest "last used".
        let lastUsed = [
            SettingsDestinationActivity.lastDirectCLIRequest(in: history.history),
            pairedAt,
        ].compactMap { $0 }.max()
        let lastUsedText = lastUsed.map {
            String(localized: "last used \(SettingsDestinationActivity.relativeDayText($0))")
        }
        let parts = [method, lastUsedText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var divider: some View {
        Rectangle().fill(palette.line).frame(height: 1)
            .padding(.horizontal, GlassMetrics.panelPadding)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .glassFont(.rowSubtitle)
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 4)
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

    private var canConnect: Bool {
        let hasHost = !directCLIHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let digits = ManualIPSyncSecurity.normalizedPairingCode(pairingCode).utf8.count
        let hasCode = digits == DirectPairingSecurity.sharedPairingCodeDigits
            || digits == DirectPairingSecurity.legacyPairingCodeDigits
        let transportReady = directCLITransport == DirectTransportKind.nearby.rawValue
            || (hasHost && ManualConnectionPort.parse(directCLIPort) != nil)
        return transportReady && !directCLIService.isConnecting && (!directCLIService.needsPairingCode || hasCode)
    }

    private func connect() {
        if directCLIService.needsPairingCode { pairingMethods.noteAttempt(.code) }
        // Nearby ignores the manual endpoint; an invalid manual draft must not
        // overwrite its saved port when pairing through Nearby.
        let port: UInt16
        if directCLITransport == DirectTransportKind.nearby.rawValue {
            port = ManualConnectionPort.parse(savedDirectCLIPort) ?? HealthMdDirectProtocol.defaultManualIPPort
        } else {
            guard let manualPort = ManualConnectionPort.parse(directCLIPort) else { return }
            port = manualPort
            directCLIPort = String(port)
            savedDirectCLIPort = String(port)
        }
        directCLIService.connect(
            host: directCLIHost,
            port: port,
            pairingCode: ManualIPSyncSecurity.normalizedPairingCode(pairingCode)
        )
    }
}
#endif
