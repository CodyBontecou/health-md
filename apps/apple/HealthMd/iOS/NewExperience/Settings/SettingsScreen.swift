#if os(iOS)
import SwiftUI

/// SettingsGlass: account, destinations, data, and app and support. Each row opens the
/// view that already owns that capability, so no setup logic is duplicated here.
struct SettingsScreen: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject var externalIntegrationManager: ExternalIntegrationManager
    let profileCoordinator: ExportProfileCoordinator?
    @Binding var selectedTab: NavTab
    @Binding var showFolderPicker: Bool
    @Binding var showExportProfiles: Bool
    @Binding var showClinicianReport: Bool

    private enum Route: Hashable { case folder, mac, cli, api, gateway, clinic, appSupport, connectedApps, clinicianReport, metrics }

    @Environment(\.glassPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var directCLIService: IPhoneDirectCLIService
    @EnvironmentObject private var apiExportSettings: APIExportSettings
    @EnvironmentObject private var gatewaySettings: AgentDataGatewaySettings
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var path: [Route] = []
    @State private var showPaywall = false
    @AppStorage("syncEnabled") private var syncEnabled = false
    @AppStorage(IPhoneDirectCLIService.enabledKey) private var directCLIEnabled = false

    /// iPadSettingsG, by the same rule as iPadAutomationsG: an unfolded phone keeps the
    /// phone column, its wording, and the Default metrics row.
    private var usesTwoPanes: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    /// In two panes the detail shows one route, so opening replaces instead of pushing.
    private func open(_ route: Route) {
        if usesTwoPanes { path = [route] } else { path.append(route) }
    }

    var body: some View {
        Group {
            if usesTwoPanes {
                HStack(spacing: 0) {
                    NavigationStack { hub }
                        .frame(width: GlassMetrics.listPaneWidth)
                    NavigationStack {
                        destination(path.last ?? .folder).id(path.last ?? .folder)
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    hub.navigationDestination(for: Route.self) { destination($0) }
                }
            }
        }
        .accessibilityIdentifier("glass.settings")
        .sheet(isPresented: $showPaywall) { PaywallView(context: .settings, profileCoordinator: profileCoordinator) }
        .onAppear {
            #if DEBUG
            // Profile management lives in Automations; UI journeys still reach the legacy sheet.
            if UserDefaults.standard.bool(forKey: "UITestOpenExportProfiles") { showExportProfiles = true }
            #endif
            followSyncRequest()
            // The shell mounts this screen only on its tab, so a request made from
            // another tab has already changed by the time onChange could see it.
            if configurationProtection.settingsNavigationRequestID != nil { path = [.appSupport] }
            followClinicianReportRequest(showClinicianReport)
        }
        // ClinicianReportG is pushed here; a request through the binding opens the page.
        .onChange(of: showClinicianReport) { _, requested in followClinicianReportRequest(requested) }
        .onChange(of: selectedTab) { _, _ in followSyncRequest() }
        .onChange(of: directCLIService.pendingPairingLink) { _, link in
            if link != nil { path = [.cli] }
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil { path = [.appSupport] }
        }
    }

    private var hub: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    // iPadSettingsG: the sidebar already names the app, so the pane has no title.
                    if !usesTwoPanes {
                        Text("Settings").glassFont(.largeTitle).foregroundStyle(palette.text)
                    }

                    planRow

                    sectionTitle(String(localized: "Destinations"))
                    GlassPanel {
                        GlassSettingsRow(
                            title: folderTitle,
                            subtitle: folderSubtitle,
                            systemImage: "folder.fill", tile: .settingsTileViolet,
                            badge: folderBadge
                        ) { open(.folder) }
                        .accessibilityIdentifier("glass.settings.folder")
                        GlassSettingsRow(
                            title: macTitle,
                            subtitle: String(localized: "Health.md for Mac"),
                            systemImage: "desktopcomputer", tile: .settingsTileBlue,
                            badge: macBadge,
                            showsDivider: true
                        ) { open(.mac) }
                        .accessibilityIdentifier("glass.settings.mac")
                        GlassSettingsRow(
                            title: String(localized: "healthmd CLI"),
                            subtitle: directCLIService.hasPairedCLI ? String(localized: "1 paired computer") : nil,
                            systemImage: "terminal.fill", tile: .settingsTileGraphite,
                            badge: cliBadge,
                            showsDivider: true
                        ) { open(.cli) }
                        .accessibilityIdentifier("glass.settings.cli")
                        GlassSettingsRow(
                            title: String(localized: "API endpoint"),
                            subtitle: apiSubtitle,
                            systemImage: "chevron.left.forwardslash.chevron.right", tile: .settingsTileGreen,
                            badge: .readiness(apiExportSettings.isConfigured),
                            showsDivider: true
                        ) { open(.api) }
                        .accessibilityIdentifier("glass.settings.api")
                        GlassSettingsRow(
                            title: String(localized: "Agent Data gateway"),
                            subtitle: gatewaySubtitle,
                            systemImage: "arrow.up.doc.fill", tile: .settingsTilePurple,
                            badge: .readiness(gatewaySettings.isConfigured),
                            showsDivider: true
                        ) { open(.gateway) }
                        .accessibilityIdentifier("glass.settings.gateway")
                    }

                    sectionTitle(usesTwoPanes ? String(localized: "Data & app") : String(localized: "Data"))
                    GlassPanel {
                        // iPadSettingsG has no Default metrics row: on iPad, metrics are edited
                        // per automation (MetricsG), one tap away in the Automations pane.
                        if !usesTwoPanes {
                            GlassSettingsRow(
                                title: String(localized: "Default metrics"),
                                systemImage: "heart.fill", tile: .settingsTileRed,
                                value: "\(defaultMetricCount)"
                            ) {
                                // MetricsG is a pushed page.
                                if profileCoordinator?.profileStore.activeProfile != nil {
                                    open(.metrics)
                                } else {
                                    showExportProfiles = true
                                }
                            }
                            .accessibilityIdentifier("glass.settings.metrics")
                        }
                        if ConnectedAppsFeature.isEnabled {
                            GlassSettingsRow(
                                title: String(localized: "Connected apps"),
                                systemImage: "plus", tile: .settingsTileOrange,
                                value: connectedAppsValue,
                                showsDivider: !usesTwoPanes
                            ) { open(.connectedApps) }
                        }
                        if PracticeFeaturePolicy.current.isEnabled {
                            GlassSettingsRow(
                                title: String(localized: "Clinic access"),
                                systemImage: "cross.case.fill", tile: .settingsTileGreen,
                                showsDivider: !usesTwoPanes || ConnectedAppsFeature.isEnabled
                            ) { open(.clinic) }
                            .accessibilityIdentifier("glass.settings.clinic")
                        }
                        GlassSettingsRow(
                            title: String(localized: "Clinician report"),
                            systemImage: "doc.text.fill", tile: .settingsTileGray,
                            showsDivider: !usesTwoPanes || ConnectedAppsFeature.isEnabled
                                || PracticeFeaturePolicy.current.isEnabled
                        ) { open(.clinicianReport) }
                        if usesTwoPanes {
                            GlassSettingsRow(
                                title: String(localized: "App & support"),
                                subtitle: String(localized: "Lock, setup, privacy, help"),
                                systemImage: "gearshape.fill", tile: .settingsTileGray,
                                showsDivider: true
                            ) { open(.appSupport) }
                            .accessibilityIdentifier("glass.settings.appSupport")
                        }
                    }

                    if !usesTwoPanes {
                        sectionTitle(String(localized: "App"))
                        GlassPanel {
                            GlassSettingsRow(
                                title: String(localized: "Lock configuration"),
                                systemImage: "lock.fill", tile: .settingsTileGray,
                                value: configurationProtection.isEnabled ? String(localized: "On") : String(localized: "Off")
                            ) { open(.appSupport) }
                            .accessibilityIdentifier("glass.settings.lock")
                            GlassSettingsRow(
                                title: String(localized: "Privacy"),
                                systemImage: "hand.raised.fill", tile: .settingsTileBlue,
                                value: String(localized: "No analytics"),
                                showsDivider: true
                            ) { open(.appSupport) }
                            .accessibilityIdentifier("glass.settings.privacy")
                            GlassSettingsRow(
                                title: String(localized: "Help & diagnostics"),
                                systemImage: "questionmark.circle.fill", tile: .settingsTileViolet,
                                showsDivider: true
                            ) { open(.appSupport) }
                            .accessibilityIdentifier("glass.settings.appSupport")
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, GlassMetrics.scrollBottomInset)
            }
            .background(palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .folder:
            GlassFolderDestinationScreen(
                vaultManager: vaultManager,
                coordinator: profileCoordinator,
                showFolderPicker: $showFolderPicker
            )
        case .mac:
            GlassMacDestinationScreen()
        case .cli:
            GlassCLIDestinationScreen()
        case .api:
            GlassAPIDestinationSheet(settings: apiExportSettings, presentedAsSheet: false)
        case .gateway:
            GlassGatewayDestinationSheet(
                settings: gatewaySettings,
                presentedAsSheet: false,
                onOpenClinicAccess: PracticeFeaturePolicy.current.isEnabled ? { open(.clinic) } : nil
            )
        case .clinic:
            // Fail closed: a stale route never shows the screen once the gate is off.
            if PracticeFeaturePolicy.current.isEnabled {
                GlassClinicAccessScreen(coordinator: profileCoordinator)
            }
        case .appSupport:
            GlassAppSupportScreen()
        case .connectedApps:
            // ConnectedAppsG and ClinicianReportG are pushed pages: Back, no Done/Close.
            if ConnectedAppsFeature.isEnabled {
                ExternalIntegrationsView(manager: externalIntegrationManager)
            }
        case .metrics:
            if let profileCoordinator, let profile = profileCoordinator.profileStore.activeProfile {
                GlassProfilePage(kind: .metrics, coordinator: profileCoordinator, profile: profile)
            }
        case .clinicianReport:
            ClinicianReportView(
                healthKitManager: healthKitManager,
                unitPreference: advancedSettings.formatCustomization.unitPreference
            )
        }
    }

    /// The app row: SettingsGlass draws a 58 pt icon in its own card with a chevron;
    /// iPadSettingsG a 44 pt icon in a smaller tile that leads the sidebar.
    private var planRow: some View {
        let compact = usesTwoPanes
        return Button { showPaywall = true } label: {
            HStack(spacing: compact ? 12 : 14) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: compact ? 44 : 58, height: compact ? 44 : 58)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
                    .shadow(color: .black.opacity(compact ? 0 : 0.3), radius: 1.5, y: 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: compact ? 0 : 3) {
                    Text(verbatim: "Health.md")
                        .font(.system(size: compact ? 16 : 19, weight: .bold))
                        .foregroundStyle(palette.text)
                    Text(planSubtitle)
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 8)
                if !compact {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: compact ? 18 : 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("glass.settings.plan")
    }

    private func followClinicianReportRequest(_ requested: Bool) {
        guard requested else { return }
        showClinicianReport = false
        if path.last != .clinicianReport { open(.clinicianReport) }
    }

    /// Pairing links ask for the Sync tab, which now lives here.
    private func followSyncRequest() {
        if selectedTab == .sync { path = directCLIService.pendingPairingLink == nil ? [.mac] : [.cli] }
    }

    /// SettingsGlass: "[Your plan] · restore or manage". iPadSettingsG shows the plan alone.
    private var planSubtitle: String {
        guard purchaseManager.isUnlocked else { return String(localized: "Unlock Health.md") }
        return usesTwoPanes
            ? purchaseManager.activePlanTitle
            : String(localized: "\(purchaseManager.activePlanTitle) · restore or manage")
    }

    private var folderTitle: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "Vault on this iPad")
            : String(localized: "Vault on this iPhone")
    }

    /// Folder automations can each write to their own folder, so summarise how many are in use.
    private var folderSubtitle: String? {
        let profiles = (profileCoordinator?.profileStore.profiles ?? []).filter { $0.target == .localIPhoneFolder }
        let ownFolders = Set(profiles.compactMap(\.folderVaultID))
        let usesDefault = profiles.isEmpty || profiles.contains { $0.folderVaultID == nil }
        let count = ownFolders.count + (usesDefault && vaultManager.hasVaultSelection ? 1 : 0)
        if count > 1 { return String(localized: "\(count) folders") }
        if usesDefault {
            guard vaultManager.hasVaultSelection else { return nil }
            let subfolder = vaultManager.healthSubfolder.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = subfolder.isEmpty ? vaultManager.vaultName : "\(vaultManager.vaultName)/\(subfolder)"
            return usesTwoPanes ? path : String(localized: "\(path) · default")
        }
        return profileCoordinator?.destinationStore.vault(id: ownFolders.first)?.name
    }

    private var folderBadge: GlassSettingsBadgeState {
        switch vaultManager.destinationState {
        case .available: return .init(String(localized: "Ready"), .ok)
        case .notSelected: return .init(String(localized: "Off"), .off)
        case .temporarilyUnavailable: return .init(String(localized: "Unavailable"), .attention)
        case .requiresReviewIdentityUnavailable,
             .requiresReselectionDestinationChanged,
             .requiresReselectionMissingExpectedPath:
            return .init(String(localized: "Needs review"), .attention)
        }
    }

    private var macTitle: String {
        if syncService.connectionState == .connected, let name = syncService.connectedPeerName, !name.isEmpty {
            return name
        }
        return String(localized: "Mac Destination")
    }

    private var macBadge: GlassSettingsBadgeState {
        guard syncEnabled else { return .init(String(localized: "Off"), .off) }
        switch syncService.connectionState {
        case .connected: return .init(String(localized: "Online"), .ok)
        case .connecting: return .init(String(localized: "Connecting…"), .off)
        case .disconnected: return .init(String(localized: "Offline"), .off)
        }
    }

    private var cliBadge: GlassSettingsBadgeState? {
        if directCLIService.hasPairedCLI { return .init(String(localized: "Paired"), directCLIEnabled ? .ok : .off) }
        return directCLIEnabled ? nil : .readiness(false)
    }

    private var apiSubtitle: String {
        guard apiExportSettings.isConfigured else {
            return usesTwoPanes ? String(localized: "Send JSON") : String(localized: "Send JSON to your server")
        }
        let name = DestinationNameStore().apiEndpointName
        return name.isEmpty ? apiExportSettings.displayName : name
    }

    private var gatewaySubtitle: String {
        guard gatewaySettings.isConfigured else {
            return usesTwoPanes ? "/v1/ingest" : String(localized: "Upload to /v1/ingest")
        }
        let name = DestinationNameStore().agentDataGatewayName
        return name.isEmpty ? gatewaySettings.displayName : name
    }

    /// The active automation's metric count; legacy mode without profiles counts the live selection.
    private var defaultMetricCount: Int {
        if let profile = profileCoordinator?.profileStore.activeProfile {
            return profile.settings.metricSelection.enabledMetricIDs
                .intersection(HealthMetrics.availableMetricIDsInCurrentBuild).count
        }
        return advancedSettings.metricSelection.totalEnabledCount
    }

    private var connectedAppsValue: String? {
        let names = externalIntegrationManager.accounts.keys.map(\.displayName).sorted()
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).glassFont(.caption).foregroundStyle(palette.muted)
    }

}
#endif
