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

    private enum Route: Hashable { case sync, appSupport }

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var apiExportSettings: APIExportSettings
    @EnvironmentObject private var gatewaySettings: AgentDataGatewaySettings
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var path: [Route] = []
    @State private var showPaywall = false
    @State private var showIntegrations = false
    @State private var showAPI = false
    @State private var showGateway = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text("Settings").glassFont(.largeTitle).foregroundStyle(palette.text)

                    GlassPanel {
                        row(
                            "Health.md",
                            subtitle: purchaseManager.isUnlocked
                                ? String(localized: "Restore or manage")
                                : String(localized: "Unlock Health.md")
                        ) { showPaywall = true }
                    }

                    sectionTitle(String(localized: "Destinations"))
                    GlassPanel {
                        row(
                            String(localized: "Folder"),
                            subtitle: vaultManager.hasVaultSelection ? vaultManager.vaultName : nil
                        ) {
                            configurationProtection.performConfigurationChange { showFolderPicker = true }
                        }
                        row(String(localized: "Mac and CLI"), subtitle: connectionText) { path.append(.sync) }
                        row(
                            String(localized: "API Endpoint"),
                            subtitle: apiExportSettings.isConfigured ? apiExportSettings.displayName : nil
                        ) { showAPI = true }
                        row(
                            String(localized: "Agent Data gateway"),
                            subtitle: gatewaySettings.isConfigured ? gatewaySettings.displayName : nil
                        ) { showGateway = true }
                    }

                    sectionTitle(String(localized: "Data"))
                    GlassPanel {
                        row(String(localized: "Clinician report")) { showClinicianReport = true }
                        if ConnectedAppsFeature.isEnabled {
                            row(String(localized: "Connected apps")) { showIntegrations = true }
                        }
                    }

                    sectionTitle(String(localized: "App"))
                    GlassPanel {
                        row(String(localized: "App & support")) { path.append(.appSupport) }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, GlassMetrics.scrollBottomInset)
            }
            .background(palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sync:
                    SyncSettingsView()
                case .appSupport:
                    SettingsTabView(
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        externalIntegrationManager: externalIntegrationManager,
                        profileCoordinator: profileCoordinator,
                        showFolderPicker: $showFolderPicker,
                        showExportProfiles: $showExportProfiles,
                        showClinicianReport: $showClinicianReport
                    )
                }
            }
        }
        .accessibilityIdentifier("glass.settings")
        .sheet(isPresented: $showPaywall) { PaywallView(context: .settings) }
        .sheet(isPresented: $showAPI) {
            GlassAPIDestinationSheet(settings: apiExportSettings).glassTheme()
        }
        .sheet(isPresented: $showGateway) {
            GlassGatewayDestinationSheet(settings: gatewaySettings).glassTheme()
        }
        .sheet(isPresented: $showIntegrations) {
            ExternalIntegrationsView(manager: externalIntegrationManager)
        }
        .onAppear(perform: followSyncRequest)
        .onChange(of: selectedTab) { _, _ in followSyncRequest() }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil { path = [.appSupport] }
        }
    }

    /// Pairing links ask for the Sync tab, which now lives here.
    private func followSyncRequest() {
        if selectedTab == .sync { path = [.sync] }
    }

    private var connectionText: String {
        switch syncService.connectionState {
        case .connected: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting…")
        case .disconnected: return String(localized: "Disconnected")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).glassFont(.caption).foregroundStyle(palette.muted)
    }

    private func row(_ title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassRow(title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
