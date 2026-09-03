import HealthMdConnectionCore
import SwiftUI

// MARK: - Sync Settings View (iOS)

struct SyncSettingsView: View {
    private enum ConfigurationTarget: String {
        case macDestination
        case cli
    }

    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var directCLIService: IPhoneDirectCLIService
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject var directWakeManager: IPhoneDirectWakeManager
    @AppStorage("syncEnabled") private var syncEnabled = false
    @AppStorage(IPhoneDirectCLIService.enabledKey) private var directCLIEnabled = false
    @AppStorage(IPhoneDirectCLIService.hostKey) private var directCLIHost = ""
    @AppStorage(IPhoneDirectCLIService.portKey) private var directCLIPort = String(HealthMdDirectProtocol.defaultManualIPPort)
    @AppStorage(IPhoneDirectCLIService.transportKey) private var directCLITransport = DirectTransportKind.manualIP.rawValue
    @AppStorage("manualIPLastHost") private var manualMacHost = ""
    @AppStorage("manualIPLastPort") private var manualMacPort = String(SyncService.manualIPPort)
    @State private var manualPairingCode = ""
    @State private var directCLIPairingCode = ""
    @State private var showDirectCLIPairingScanner = false
    @State private var configurationTarget: ConfigurationTarget = .macDestination
    @FocusState private var focusedManualIPField: ManualIPField?

    private enum ManualIPField: Hashable {
        case host
        case port
        case pairingCode
    }

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
            VStack(alignment: .leading, spacing: Spacing.s4) {
                syncHeader
                configurationTargetPicker

                switch configurationTarget {
                case .macDestination:
                    syncToggleSection
                        .configurationChangesProtected()
                    downloadMacSection
                    connectionSection
                    manualIPSection
                    macExportFlowSection
                    errorSection
                case .cli:
                    directCLISection
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s4)
            .padding(.bottom, 120)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if directCLIService.pendingPairingLink != nil {
                configurationTarget = .cli
            }
            if syncEnabled && shouldStartRuntimeServices {
                syncService.startAdvertising()
            }
            if directCLIEnabled && shouldStartRuntimeServices {
                directCLIService.setEnabled(true)
            }
        }
        .onChange(of: directCLIService.pendingPairingLink) { _, pairingLink in
            if pairingLink != nil {
                configurationTarget = .cli
            }
        }
        .onChange(of: directCLIService.isConnected) { _, connected in
            if connected { directCLIPairingCode = "" }
        }
        .onChange(of: syncService.connectionState) { oldValue, newValue in
            guard oldValue != newValue else { return }
            let announcement: String
            switch newValue {
            case .connected:
                announcement = "Connected to Mac"
                if syncService.activeTransport == .manualIP {
                    manualPairingCode = ""
                }
            case .connecting: announcement = "Connecting to Mac"
            case .disconnected: announcement = "Disconnected from Mac"
            }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        .fullScreenCover(isPresented: $showDirectCLIPairingScanner) {
            DirectCLIPairingScannerView { pairingLink in
                configurationProtection.performConfigurationChange {
                    directCLIService.handleScannedPairingLink(pairingLink)
                }
            }
        }
    }

    // MARK: - Header

    private var syncHeader: some View {
        HealthMdPageHeader(
            title: configurationTarget == .macDestination ? "Mac Destination" : "CLI",
            subtitle: configurationTarget == .macDestination
                ? "Let Health.md on Mac receive iPhone-configured exports over your local network."
                : "Let the healthmd command connect while this iPhone app is open, without running the Mac app."
        ) {
            HStack(spacing: Spacing.sm) {
                if configurationTarget == .macDestination {
                    SyncStatusPill(
                        text: syncEnabled ? String(localized: "Enabled") : String(localized: "Disabled"),
                        tone: syncEnabled ? .success : .muted
                    )
                    if syncEnabled {
                        SyncStatusPill(text: connectionStatusLabel, tone: connectionTone)
                    }
                } else {
                    SyncStatusPill(
                        text: directCLIEnabled ? String(localized: "Enabled") : String(localized: "Disabled"),
                        tone: directCLIEnabled ? .success : .muted
                    )
                    if let directCLIHeaderStatusLabel {
                        SyncStatusPill(text: directCLIHeaderStatusLabel, tone: directCLIHeaderStatusTone)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel)
        }
    }

    private var configurationTargetPicker: some View {
        Picker("Sync", selection: $configurationTarget) {
            Text("Mac Destination").tag(ConfigurationTarget.macDestination)
            Text("CLI").tag(ConfigurationTarget.cli)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.Sync.configurationTargetPicker)
    }

    // MARK: - Sections

    private var syncToggleSection: some View {
        SyncCard(
            title: "Connection",
            subtitle: "Turn this on to make the Mac app available as an export target."
        ) {
            Toggle(isOn: $syncEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Mac Destination")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Advertise this iPhone on your local network so Health.md on Mac can connect.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.accent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .onChange(of: syncEnabled) { _, newValue in
                if newValue {
                    if !TestMode.isUITesting {
                        syncService.startAdvertising()
                        syncService.restoreSavedManualIPConnectionIfNeeded(afterUserEnabledSync: true)
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
        }
    }

    @ViewBuilder
    private var downloadMacSection: some View {
        if !syncEnabled {
            SyncCard(
                title: "Get the Mac App",
                subtitle: "Install the companion app before using Mac destinations."
            ) {
                Link(destination: macAppURL) {
                    downloadMacLinkContent
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Download Health.md for macOS")
                .accessibilityHint("Double tap to open download page in browser")
                .accessibilityAddTraits(.isLink)
            }
        }
    }

    private var downloadMacLinkContent: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "arrow.down.app.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Health.md for macOS")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Download from the App Store")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var connectionSection: some View {
        if syncEnabled {
            SyncCard(
                title: "Connection Status",
                subtitle: "Keep both devices nearby on the same network."
            ) {
                connectionStatusRow

                if syncService.connectionState == .connected {
                    SyncRowDivider()
                    destinationStatusRow

                    if syncService.macDestinationStatus?.activeJobID != nil {
                        SyncRowDivider()
                        cancelActiveMacExportButton
                    }
                }
            }
        }
    }

    private var connectionStatusRow: some View {
        SyncInfoRow(
            icon: connectionStatusIconName,
            title: connectionTitle,
            subtitle: connectionSubtitle,
            tone: connectionTone,
            isLoading: syncService.connectionState == .connecting
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Sync.connectionStatus)
        .accessibilityLabel("Connection status")
        .accessibilityValue("\(connectionTitle). \(connectionSubtitle)")
    }

    private var destinationStatusRow: some View {
        SyncInfoRow(
            icon: destinationStatusIcon,
            title: destinationStatusTitle,
            subtitle: destinationStatusSubtitle,
            tone: syncService.canExportToConnectedMac ? .success : .warning,
            isLoading: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac destination readiness")
        .accessibilityValue("\(destinationStatusTitle). \(destinationStatusSubtitle)")
    }

    private var cancelActiveMacExportButton: some View {
        Button(role: .destructive) {
            cancelActiveMacExport()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "xmark.circle.fill")
                    .accessibilityHidden(true)
                Text("Cancel Active Mac Export")
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.warning)
        .accessibilityLabel("Cancel active Mac export")
        .accessibilityHint("Stops the Mac export that is currently blocking this destination")
    }

    @ViewBuilder
    private var manualIPSection: some View {
        if syncEnabled {
            SyncCard(
                title: "Connect by IP Address",
                subtitle: "Use this for Tailscale or networks where automatic discovery cannot find your Mac."
            ) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("On your Mac, open Mac Destination, enable Manual IP Connections, and generate a pairing code.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                TextField("Mac Tailscale IP or hostname", text: $manualMacHost)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedManualIPField, equals: .host)
                                    .accessibilityLabel("Mac IP address or hostname")

                                TextField("Port", text: $manualMacPort)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 82)
                                    .focused($focusedManualIPField, equals: .port)
                                    .accessibilityLabel("Manual IP port")
                            }

                            SecureField(
                                syncService.hasSavedManualIPConnection ? "Pairing code (not required)" : "Pairing code",
                                text: $manualPairingCode
                            )
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedManualIPField, equals: .pairingCode)
                                .accessibilityLabel("Pairing code")
                        }
                        .configurationChangesProtected()

                        if syncService.hasSavedManualIPConnection {
                            Label(
                                "Paired with \(syncService.savedManualIPMacName ?? "Mac"). The connection is saved; no pairing code is required.",
                                systemImage: "lock.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: Spacing.sm) {
                            Button {
                                configurationProtection.performConfigurationChange {
                                    connectByManualIP()
                                }
                            } label: {
                                Label(manualIPButtonTitle, systemImage: manualIPButtonIcon)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canAttemptManualIPConnection)

                            if syncService.activeTransport == .manualIP {
                                Button("Disconnect") {
                                    syncService.disconnect()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var directCLISection: some View {
        SyncCard(
            title: "Direct CLI Access",
            subtitle: "Let the healthmd command connect while this iPhone app is open, without running the Mac app."
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle(isOn: Binding(
                    get: { directCLIEnabled },
                    set: { enabled in
                        configurationProtection.performConfigurationChange {
                            directCLIEnabled = enabled
                            directCLIService.setEnabled(enabled)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable Direct CLI Access")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("New commands require Health.md to be open. An active export can continue briefly in the background.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .tint(Color.accent)
                .accessibilityIdentifier(AccessibilityID.Sync.directCLIToggle)

                if directCLIService.hasPairedCLI {
                    SyncRowDivider()
                    Toggle(isOn: Binding(
                        get: {
                            if case .enrolled = directWakeManager.state { return true }
                            return false
                        },
                        set: { enabled in
                            configurationProtection.performConfigurationChange {
                                Task { @MainActor in
                                    if enabled {
                                        await directWakeManager.enable()
                                    } else {
                                        await directWakeManager.disable()
                                    }
                                }
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Allow paired computers to send wake requests")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("Get a notification when the CLI is waiting for this phone, so unlocking and opening Health.md finishes the same command. Requires the wake service; the CLI keeps waiting without it.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .tint(Color.accent)
                    .disabled(directWakeManager.state == .enrolling)
                    if case .unavailable(let reason) = directWakeManager.state {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if directCLIService.needsPairingCode,
                   directCLIService.pendingPairingLink == nil {
                    SyncRowDivider()

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Button {
                            configurationProtection.performConfigurationChange {
                                showDirectCLIPairingScanner = true
                            }
                        } label: {
                            Label("Scan Pairing QR", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(directCLIService.isConnecting)
                        .accessibilityIdentifier(AccessibilityID.Sync.directCLIScanButton)
                        .accessibilityHint("Opens the in-app camera scanner and pairs as soon as a valid QR is recognized")

                        Text("Start pairing from healthmd or your MCP client, then scan its QR here. Health.md does not auto-pair from links opened by other apps.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let pairingLink = directCLIService.pendingPairingLink {
                    SyncRowDivider()

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Label("Pairing from QR", systemImage: "qrcode.viewfinder")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(pairingHandoffMessage(for: pairingLink))
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !directCLIService.isConnecting,
                           directCLIService.lastError != nil {
                            Button {
                                directCLIService.retryPendingPairingLink()
                            } label: {
                                Label("Retry QR pairing", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button("Cancel", role: .cancel) {
                            directCLIService.cancelPendingPairingLink()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if directCLIEnabled {
                    SyncRowDivider()

                    SyncInfoRow(
                        icon: directCLIStatusIcon,
                        title: directCLIStatusTitle,
                        subtitle: directCLIStatusSubtitle,
                        tone: directCLIService.hasPairedCLI ? .success : .muted,
                        isLoading: directCLIService.isConnecting
                    )

                    if directCLIService.pendingPairingLink == nil {
                        if directCLIService.needsPairingCode {
                            Picker("Transport", selection: Binding(
                                get: { directCLITransport },
                                set: { value in
                                    configurationProtection.performConfigurationChange {
                                        directCLITransport = value
                                        directCLIService.updateTransport(
                                            DirectTransportKind(rawValue: value) ?? .manualIP
                                        )
                                    }
                                }
                            )) {
                                Text("Manual IP").tag(DirectTransportKind.manualIP.rawValue)
                                Text("Nearby").tag(DirectTransportKind.nearby.rawValue)
                            }
                            .pickerStyle(.segmented)

                            if directCLITransport == DirectTransportKind.manualIP.rawValue {
                                HStack(spacing: Spacing.sm) {
                                    TextField("Mac IP or Tailscale address", text: $directCLIHost)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.URL)
                                        .textFieldStyle(.roundedBorder)

                                    TextField("Port", text: $directCLIPort)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 82)
                                }
                                .configurationChangesProtected()
                            } else {
                                Text("Nearby discovers the pairing command on the same local network. It never falls back to Manual IP.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            SecureField("20-digit pairing code", text: $directCLIPairingCode)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .configurationChangesProtected()
                            Text("Current healthmd versions use one 20-digit code on iOS and Android. Six-digit entry remains available only for a legacy CLI.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)

                            Button {
                                configurationProtection.performConfigurationChange {
                                    connectDirectCLI()
                                }
                            } label: {
                                Label("Pair with healthmd", systemImage: "link")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canConnectDirectCLI)
                        } else {
                            Label(
                                "Paired with \(directCLIService.pairedCLIName ?? "healthmd CLI") via \(directCLITransportLabel). Commands connect on demand while access is enabled.",
                                systemImage: "lock.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                            DestructiveButton(title: "Forget Pairing") {
                                configurationProtection.performConfigurationChange {
                                    directCLIService.forgetPairedCLI()
                                    directCLIPairingCode = ""
                                }
                            }
                        }
                    }

                }

                if let directError = directCLIService.lastError {
                    Text(directError)
                        .font(.footnote)
                        .foregroundStyle(Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var macExportFlowSection: some View {
        if syncEnabled {
            SyncCard(
                title: "Export to Mac",
                subtitle: "The Mac writes files using the setup you choose on iPhone."
            ) {
                SyncStepRow(number: 1, text: "Open Health.md on Mac and choose a destination folder")
                SyncRowDivider()
                SyncStepRow(number: 2, text: "Return to the iPhone Export tab")
                SyncRowDivider()
                SyncStepRow(number: 3, text: "Choose Connected Mac and tap Export")
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = syncService.lastError {
            SyncCard(title: "Needs Attention") {
                SyncInfoRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Connection Error",
                    subtitle: error,
                    tone: .warning,
                    isLoading: false
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error")
                .accessibilityValue(error)
            }
        }
    }

    // MARK: - Helpers

    private var headerAccessibilityLabel: String {
        switch configurationTarget {
        case .macDestination:
            if syncEnabled {
                return "Mac destination enabled. Connection status: \(connectionStatusLabel)."
            }
            return "Mac destination disabled."
        case .cli:
            guard directCLIEnabled else { return "Direct CLI access disabled." }
            if directCLIService.isConnected { return "Direct CLI access enabled and connected." }
            if directCLIService.isConnecting { return "Direct CLI access enabled and connecting." }
            if directCLIService.hasPairedCLI { return "Direct CLI access enabled and ready." }
            return "Direct CLI access enabled and waiting to pair."
        }
    }

    private var directCLIHeaderStatusLabel: String? {
        guard directCLIEnabled else { return nil }
        if directCLIService.isConnected { return String(localized: "Connected") }
        if directCLIService.isConnecting { return String(localized: "Connecting…") }
        if directCLIService.hasPairedCLI { return String(localized: "Ready") }
        return nil
    }

    private var directCLIHeaderStatusTone: SyncStatusTone {
        directCLIService.isConnecting ? .accent : .success
    }

    private var connectionStatusLabel: String {
        switch syncService.connectionState {
        case .connected: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected: return String(localized: "Waiting")
        }
    }

    private var connectionTone: SyncStatusTone {
        switch syncService.connectionState {
        case .connected: return .success
        case .connecting: return .accent
        case .disconnected: return .muted
        }
    }

    private var connectionStatusIconName: String {
        switch syncService.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "circle.dotted"
        }
    }

    private var connectionTitle: String {
        switch syncService.connectionState {
        case .connected:
            return String(localized: "Connected to \(syncService.connectedPeerName ?? "Mac")")
        case .connecting:
            return String(localized: "Connecting…")
        case .disconnected:
            return String(localized: "Waiting for Mac")
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

    private var manualIPButtonIcon: String {
        syncService.connectionState == .connecting && syncService.activeTransport == .manualIP
            ? "arrow.triangle.2.circlepath"
            : "network"
    }

    private func connectByManualIP() {
        focusedManualIPField = nil
        let port = UInt16(manualMacPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? SyncService.manualIPPort
        let pairingCode = ManualIPSyncSecurity.normalizedPairingCode(manualPairingCode)
        manualMacPort = String(port)
        if pairingCode.isEmpty && syncService.hasSavedManualIPConnection {
            syncService.connectToSavedManualMac(host: manualMacHost, port: port)
        } else {
            syncService.connectToManualMac(
                host: manualMacHost,
                port: port,
                pairingCode: pairingCode
            )
        }
    }

    private func pairingHandoffMessage(
        for pairingLink: IPhoneDirectCLIPairingLink
    ) -> String {
        if directCLIService.isConnecting {
            return "Connecting automatically to healthmd at \(pairingLink.host):\(pairingLink.port). Keep Health.md open until pairing completes."
        }
        if directCLIService.isPairingHandoffWaitingForActiveOperation {
            return "Waiting for the active direct operation to finish, then Health.md will connect automatically to \(pairingLink.host):\(pairingLink.port)."
        }
        return "Scanning this QR inside Health.md authorizes a one-time connection to healthmd at \(pairingLink.host):\(pairingLink.port)."
    }

    private var directCLIStatusIcon: String {
        if directCLIService.isConnected { return "terminal.fill" }
        if directCLIService.isConnecting { return "arrow.triangle.2.circlepath" }
        return directCLIService.hasPairedCLI ? "checkmark.circle.fill" : "terminal"
    }

    private var directCLIStatusTitle: String {
        if directCLIService.isConnected {
            return "Connected to \(directCLIService.connectedCLIName ?? "healthmd")"
        }
        if directCLIService.isConnecting { return "Pairing with healthmd…" }
        return directCLIService.hasPairedCLI ? "Ready for healthmd" : "Pair a healthmd CLI"
    }

    private var directCLIStatusSubtitle: String {
        if directCLIService.isConnected {
            return "The authenticated CLI can request status, raw data, or generated export files."
        }
        if directCLIService.isConnecting {
            return "Keep this screen open while the first authenticated connection completes."
        }
        if directCLIService.hasPairedCLI {
            return "Access is on. The paired CLI can connect when you run a direct command; no new code is required."
        }
        return "Scan a fresh QR from healthmd above, or choose the same transport and enter its one-time code manually."
    }

    private var directCLITransportLabel: String {
        directCLITransport == DirectTransportKind.nearby.rawValue ? "Nearby" : "Manual IP"
    }

    private var canConnectDirectCLI: Bool {
        let hasHost = !directCLIHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let codeDigits = ManualIPSyncSecurity.normalizedPairingCode(directCLIPairingCode).utf8.count
        let hasCode = codeDigits == DirectPairingSecurity.sharedPairingCodeDigits
            || codeDigits == DirectPairingSecurity.legacyPairingCodeDigits
        let transportReady = directCLITransport == DirectTransportKind.nearby.rawValue || hasHost
        return transportReady
            && !directCLIService.isConnecting
            && (!directCLIService.needsPairingCode || hasCode)
    }

    private func connectDirectCLI() {
        let port = UInt16(directCLIPort.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? HealthMdDirectProtocol.defaultManualIPPort
        directCLIPort = String(port)
        directCLIService.connect(
            host: directCLIHost,
            port: port,
            pairingCode: ManualIPSyncSecurity.normalizedPairingCode(directCLIPairingCode)
        )
    }

    private func cancelActiveMacExport() {
        guard let jobID = syncService.macDestinationStatus?.activeJobID else { return }
        syncService.send(.macExportCancel(jobID: jobID))
    }

    private var destinationStatusIcon: String {
        syncService.canExportToConnectedMac ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var destinationStatusTitle: String {
        syncService.canExportToConnectedMac
            ? String(localized: "Ready for Mac Exports")
            : String(localized: "Mac Needs Attention")
    }

    private var destinationStatusSubtitle: String {
        if syncService.canExportToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return String(localized: "Exports will be written to \(path)")
            }
            return String(localized: "Select Connected Mac in the Export tab.")
        }

        guard let capabilities = syncService.remoteCapabilities else {
            return String(localized: "Waiting for destination status from Mac.")
        }
        guard capabilities.platform == .macOS,
              capabilities.isCompatibleWithMacExportJobs else {
            return "Update Health.md on Mac to receive iPhone-configured export jobs."
        }
        guard let status = syncService.macDestinationStatus else {
            return String(localized: "Waiting for destination status from Mac.")
        }
        if status.activeJobID != nil { return "Mac is currently writing another export." }
        if !status.destinationFolderSelected { return "Choose a destination folder in Health.md on Mac." }
        if !status.folderAccessHealthy {
            let destination = status.destinationPathForDisplay
                ?? status.destinationDisplayName
                ?? "the saved Mac folder"
            return "Saved Mac destination \(destination) needs access. Re-select it in Health.md on Mac."
        }
        return status.lastError ?? syncService.macExportReadinessMessage
    }
}

// MARK: - Sync Components

private struct SyncCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bgTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
    }
}

private struct SyncRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.borderSubtle)
            .padding(.leading, 64)
    }
}

private enum SyncStatusTone {
    case accent
    case success
    case warning
    case muted

    var foreground: Color {
        switch self {
        case .accent: return Color.accent
        case .success: return Color.success
        case .warning: return Color.warning
        case .muted: return Color.textMuted
        }
    }

    var background: Color {
        switch self {
        case .accent: return Color.accent.opacity(0.12)
        case .success: return Color.success.opacity(0.12)
        case .warning: return Color.warning.opacity(0.14)
        case .muted: return Color.bgSecondary
        }
    }

    var border: Color {
        switch self {
        case .accent: return Color.accent.opacity(0.24)
        case .success: return Color.success.opacity(0.22)
        case .warning: return Color.warning.opacity(0.25)
        case .muted: return Color.borderSubtle
        }
    }
}

private struct SyncStatusPill: View {
    let text: String
    let tone: SyncStatusTone

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone.background))
            .overlay(Capsule().strokeBorder(tone.border, lineWidth: 1))
    }
}

private struct SyncInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tone: SyncStatusTone
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.primary)
                } else {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(LocalizedStringKey(subtitle))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SyncStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.18), lineWidth: 1)
                )
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
