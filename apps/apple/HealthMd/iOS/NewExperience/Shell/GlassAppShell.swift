#if os(iOS)
import SwiftUI

enum GlassTab: Hashable {
    case archive, automations, settings
}

/// The Liquid Glass root. `ContentView` still owns export execution, lifecycle and its
/// sheets, so this view is presentation only. Screens without a glass version yet
/// host the existing view, which keeps every capability reachable.
struct GlassAppShell: View {
    @Binding var selectedTab: NavTab
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var externalIntegrationManager: ExternalIntegrationManager
    let profileCoordinator: ExportProfileCoordinator?
    @Binding var exportTargetSelection: ExportTargetSelection
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var dateRangePreset: ExportDateRangePreset
    @Binding var isExporting: Bool
    let exportProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var showFolderPicker: Bool
    @Binding var showExportProfiles: Bool
    @Binding var showClinicianReport: Bool
    @Binding var presentFirstExportPreview: Bool
    let onFirstExportPreviewDismissed: () -> Void
    let canExport: Bool
    let onExport: () -> Void
    let onCancelExport: () -> Void
    let onBrowseExportFolder: (ExportPresentationTarget) -> Void
    let executionHistoryAssessment: HealthHistoryAssessment?
    let isAssessingHistory: Bool
    let onContinueWithoutHistoryVerification: () -> Void
    let onCancelHistoryVerification: () -> Void

    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @EnvironmentObject private var advancedSettings: AdvancedExportSettings
    @EnvironmentObject private var apiExportSettings: APIExportSettings
    @EnvironmentObject private var agentDataGatewaySettings: AgentDataGatewaySettings
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @ObservedObject private var ledgerStore = CoverageLedgerStore.shared
    @ObservedObject private var exportHistory = ExportHistoryManager.shared

    @State private var exportRequest: ExportNowRequest?
    @State private var showPreview = false
    @State private var showAttention = false
    @State private var showClassicExport = false
    @State private var resultEntry: ExportHistoryEntry?
    @State private var scheduleStore = ScheduledExportEntryStore()
    @State private var scheduleRevision = 0

    private var tab: Binding<GlassTab> {
        Binding(
            get: {
                switch selectedTab {
                case .export: return .archive
                case .schedule: return .automations
                case .sync, .settings: return .settings
                }
            },
            set: { newValue in
                switch newValue {
                case .archive: selectedTab = .export
                case .automations: selectedTab = .schedule
                case .settings: selectedTab = .settings
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            VStack(spacing: 10) {
                historyCard
                if isExporting {
                    ExportMomentView(
                        progress: exportProgress,
                        message: exportStatusMessage,
                        onCancel: onCancelExport
                    )
                }
                FloatingTabBar(
                    items: Self.navigationItems,
                    selection: tab,
                    accessoryTitle: String(localized: "Export now")
                ) {
                    exportRequest = ExportNowRequest()
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .glassTheme()
        .sheet(item: $exportRequest) { request in
            ExportNowSheet(
                request: request,
                profiles: archiveProfiles,
                advancedSettings: advancedSettings,
                startDate: $startDate,
                endDate: $endDate,
                dateRangePreset: $dateRangePreset,
                destinationLabel: destinationLabel(for: exportTargetSelection, profile: nil),
                activeProfileID: profileCoordinator?.profileStore.activeProfileID,
                onSelectProfile: { _ = profileCoordinator?.activate(profileID: $0) },
                resolveAllTime: resolveAllTimeRange,
                onPreview: { showPreview = true },
                onExport: onExport
            )
            .glassTheme()
        }
        .sheet(isPresented: $showPreview, onDismiss: onFirstExportPreviewDismissed) {
            GlassExportPreviewSheet(
                vaultManager: vaultManager,
                startDate: startDate,
                endDate: endDate,
                dateRangePreset: dateRangePreset,
                exportTargetSelection: exportTargetSelection,
                destinationLabel: destinationLabel(for: exportTargetSelection, profile: nil),
                onExport: onExport
            )
        }
        .sheet(isPresented: $showAttention) {
            AttentionScreen(items: attentionItems).glassTheme()
        }
        .sheet(isPresented: $showClassicExport) {
            NavigationStack { classicExportTab }
        }
        .sheet(item: resultBinding) { entry in
            ExportResultScreen(entry: entry) { start, end in
                exportRequest = ExportNowRequest(startDate: start, endDate: end)
            }
            .glassTheme()
        }
        .onChange(of: isExporting) { wasExporting, nowExporting in
            // A full failure already raises ContentView's dialog.
            guard wasExporting, !nowExporting, let latest = exportHistory.history.first,
                  latest.presentationStatus == .partialSuccess,
                  latest.timestamp.timeIntervalSinceNow > -60 else { return }
            resultEntry = latest
        }
        .onChange(of: presentFirstExportPreview) { _, requested in consumeFirstPreview(requested) }
        .onAppear {
            consumeFirstPreview(presentFirstExportPreview)
        }
    }

    private var resultBinding: Binding<ExportHistoryEntry?> {
        Binding(get: { resultEntry }, set: { resultEntry = $0 })
    }

    private func consumeFirstPreview(_ requested: Bool) {
        guard requested else { return }
        presentFirstExportPreview = false
        showPreview = true
    }

    private static let navigationItems: [GlassNavigationItem<GlassTab>] = [
        .init(id: .archive, title: String(localized: "Archive"), systemImage: "calendar"),
        .init(id: .automations, title: String(localized: "Automations"), systemImage: "bolt.horizontal"),
        .init(id: .settings, title: String(localized: "Settings"), systemImage: "gearshape")
    ]

    @ViewBuilder private var content: some View {
        switch tab.wrappedValue {
        case .archive:
            ArchiveScreen(
                model: archiveModel,
                needsSetup: needsSetup,
                attentionCount: attentionItems.count,
                onAction: handleDayAction,
                onResume: resume,
                onManageAutomations: { tab.wrappedValue = .automations },
                onShowAttention: { showAttention = true },
                onSetUp: { showFolderPicker = true }
            )
        case .automations:
            ScheduleTabView(
                vaultManager: vaultManager,
                advancedSettings: advancedSettings,
                apiExportSettings: apiExportSettings,
                showFolderPicker: $showFolderPicker,
                profileCoordinator: profileCoordinator
            )
            .safeAreaInset(edge: .top) { classicExportLink }
            .safeAreaPadding(.bottom, GlassMetrics.tabBarHeight + GlassMetrics.tabBarBottomOffset)
        case .settings:
            VStack(spacing: 0) {
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
            .safeAreaPadding(.bottom, GlassMetrics.tabBarHeight + GlassMetrics.tabBarBottomOffset)
        }
    }

    private var classicExportLink: some View {
        Button(String(localized: "All export settings")) { showClassicExport = true }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .frame(minHeight: GlassMetrics.touchTarget)
    }

    private var classicExportTab: some View {
        ExportTabView(
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            syncService: syncService,
            advancedSettings: advancedSettings,
            apiExportSettings: apiExportSettings,
            agentDataGatewaySettings: agentDataGatewaySettings,
            externalIntegrations: ConnectedAppsFeature.isEnabled ? externalIntegrationManager : nil,
            exportTargetSelection: $exportTargetSelection,
            startDate: $startDate,
            endDate: $endDate,
            dateRangePreset: $dateRangePreset,
            isExporting: $isExporting,
            exportStatusMessage: $exportStatusMessage,
            showFolderPicker: $showFolderPicker,
            presentFirstExportPreview: .constant(false),
            canExport: canExport,
            onExportTapped: {
                showClassicExport = false
                onExport()
            },
            historyProfileStore: profileCoordinator?.profileStore,
            executionHistoryAssessment: executionHistoryAssessment,
            isAssessingHistory: isAssessingHistory,
            onContinueWithoutHistoryVerification: onContinueWithoutHistoryVerification,
            onCancelHistoryVerification: onCancelHistoryVerification
        )
    }

    // MARK: - History check

    /// The export flow pauses on this decision, so it stays visible over every tab.
    @ViewBuilder private var historyCard: some View {
        if isAssessingHistory {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Checking history access"))
                    .glassFont(.navTitle)
                HealthHistoryPendingContent(
                    continueUnverified: onContinueWithoutHistoryVerification,
                    cancel: onCancelHistoryVerification
                )
            }
            .padding(GlassMetrics.panelPadding)
            .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius, style: .strong)
            .padding(.horizontal, GlassMetrics.screenMargin)
        }
    }

    // MARK: - Model

    private var profiles: [ExportProfile] { profileCoordinator?.profileStore.profiles ?? [] }

    private var archiveProfiles: [ArchiveProfile] {
        _ = scheduleRevision
        let entries = scheduleStore.allEntries()
        return profiles.enumerated().map { index, profile in
            ArchiveProfile(
                id: profile.id,
                name: profile.name,
                destination: destinationLabel(for: profile.target, profile: profile),
                colorIndex: index,
                entry: entries.first { $0.profileID == profile.id }
            )
        }
    }

    private var archiveModel: ArchiveModel {
        ArchiveModel(
            profiles: archiveProfiles,
            ledger: ledgerStore.ledger,
            now: Date(),
            calendar: .current,
            activeJobProfileID: isExporting ? profileCoordinator?.profileStore.activeProfileID : nil
        )
    }

    private var needsSetup: Bool {
        ledgerStore.ledger.profiles.isEmpty
            && exportHistory.history.isEmpty
            && !vaultManager.hasVaultSelection
            && exportTargetSelection == .localIPhoneFolder
    }

    private func destinationLabel(for target: ExportTargetSelection, profile: ExportProfile?) -> String {
        switch target {
        case .localIPhoneFolder:
            return vaultManager.hasVaultSelection ? vaultManager.vaultName : String(localized: "iPhone folder")
        case .connectedMac:
            return syncService.macDestinationStatus?.destinationPathForDisplay
                ?? syncService.macDestinationStatus?.destinationDisplayName
                ?? String(localized: "Connected Mac")
        case .apiEndpoint:
            return apiExportSettings.displayName
        case .agentDataGateway:
            return agentDataGatewaySettings.displayName
        }
    }

    private var attentionItems: [AttentionScreen.Item] {
        var items: [AttentionScreen.Item] = []
        if !healthKitManager.isAuthorized {
            items.append(.init(
                id: "health",
                title: String(localized: "Apple Health permission"),
                message: String(localized: "Health.md can’t read your health data until you allow it."),
                actionTitle: String(localized: "Connect Apple Health"),
                action: { Task { try? await healthKitManager.requestAuthorization() } }
            ))
        }
        if vaultManager.requiresVaultReselection {
            items.append(.init(
                id: "folder",
                title: String(localized: "Folder unavailable"),
                message: String(localized: "Choose the export folder again to resume exports."),
                actionTitle: String(localized: "Choose folder"),
                action: { showFolderPicker = true }
            ))
        }
        return items
    }

    // MARK: - Actions

    private func handleDayAction(
        _ profile: ArchiveProfile,
        _ action: ArchiveAggregation.DayAction,
        _ date: Date
    ) {
        switch action {
        case .backfill, .reExport, .retry, .refresh:
            exportRequest = ExportNowRequest(profileID: profile.id, startDate: date, endDate: date)
        case .open:
            if let target = vaultManager.lastExportPresentationTarget {
                onBrowseExportFolder(target)
            } else if let vaultURL = vaultManager.vaultURL {
                onBrowseExportFolder(ExportPresentationTarget(
                    fileURL: vaultURL.appendingPathComponent(profile.name),
                    securityScopedRootURL: vaultURL
                ))
            }
        }
    }

    private func resume(_ profile: ArchiveProfile) {
        configurationProtection.performConfigurationChange {
            scheduleStore.update(profileID: profile.id) { $0.isEnabled = true }
            scheduleRevision += 1
        }
    }

    private func resolveAllTimeRange() async -> (start: Date, end: Date)? {
        guard let earliest = await healthKitManager.findEarliestHealthDataDate() else { return nil }
        return (earliest, Date())
    }
}

/// The existing preview with the same fetch path as the Export tab.
struct GlassExportPreviewSheet: View {
    @ObservedObject var vaultManager: VaultManager
    let startDate: Date
    let endDate: Date
    let dateRangePreset: ExportDateRangePreset
    let exportTargetSelection: ExportTargetSelection
    let destinationLabel: String
    let onExport: () -> Void

    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var advancedSettings: AdvancedExportSettings
    @EnvironmentObject private var apiExportSettings: APIExportSettings

    var body: some View {
        ExportPreviewView(
            startDate: startDate,
            endDate: endDate,
            vaultManager: vaultManager,
            settings: advancedSettings,
            destinationLabel: destinationLabel,
            destinationRootName: exportTargetSelection == .localIPhoneFolder ? nil : destinationLabel,
            dateRangePreset: dateRangePreset,
            targetType: targetType,
            apiDestination: exportTargetSelection == .apiEndpoint ? apiExportSettings.destinationSnapshot : nil,
            connectedAppsEnabled: ConnectedAppsFeature.isEnabled,
            fetchHealthData: { date in
                try? await healthKitManager.fetchHealthData(
                    for: date,
                    detailPolicy: advancedSettings.effectiveDetailPolicy,
                    metricSelection: advancedSettings.metricSelection,
                    timeZone: advancedSettings.exportTimeZoneOverride ?? .current
                )
            },
            requestHealthAuthorization: { try await healthKitManager.requestAuthorization() },
            onExport: onExport
        )
    }

    private var targetType: PricingAnalyticsExportTargetType {
        switch exportTargetSelection {
        case .localIPhoneFolder: return .localFile
        case .connectedMac: return .connectedMac
        case .apiEndpoint: return .apiEndpoint
        case .agentDataGateway: return .agentDataGateway
        }
    }
}
#endif
