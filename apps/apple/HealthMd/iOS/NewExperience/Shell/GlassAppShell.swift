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
    let onPreviewExport: (ExportPresentationTarget) -> Void
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var ledgerStore = CoverageLedgerStore.shared
    @ObservedObject private var exportHistory = ExportHistoryManager.shared

    @State private var exportRequest: ExportNowRequest?
    @State private var showPreview = false
    @State private var showAttention = false
    @State private var showClassicExport = false
    @State private var showPreviewRequirements = false
    @State private var dismissedHistoryNotice: HealthHistoryAssessment?
    @State private var resultEntry: ExportHistoryEntry?
    @State private var scheduleRevision = 0
    @State private var tabRootID = UUID()

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
                // Tapping the current tab returns to its root, as on a system tab bar.
                if newValue == tab.wrappedValue { tabRootID = UUID() }
                switch newValue {
                case .archive: selectedTab = .export
                case .automations: selectedTab = .schedule
                case .settings: selectedTab = .settings
                }
            }
        )
    }

    /// Unfolded iPhone Duo: navigation moves to a right-side rail.
    private var usesRail: Bool { horizontalSizeClass == .regular && !isPad }

    /// iPad uses a leading sidebar at regular width. Split View stays compact.
    private var usesSidebar: Bool { horizontalSizeClass == .regular && isPad }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var exportNowButton: some View {
        ExportNowAccessoryButton(title: String(localized: "Export now")) {
            exportRequest = ExportNowRequest()
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if usesSidebar {
                GlassSidebar(title: "Health.md", items: Self.navigationItems, selection: tab) {
                    exportNowButton
                }
            }
            ZStack(alignment: .bottom) {
                content.id(tabRootID)
                VStack(spacing: 10) {
                    historyCard
                    if isExporting {
                        ExportMomentView(
                            progress: exportProgress,
                            message: exportStatusMessage,
                            onCancel: onCancelExport
                        )
                    }
                    if !usesRail && !usesSidebar {
                        FloatingTabBar(
                            items: Self.navigationItems,
                            selection: tab,
                            accessoryTitle: String(localized: "Export now")
                        ) {
                            exportRequest = ExportNowRequest()
                        }
                    }
                }
            }
            if usesRail {
                NavigationRail(items: Self.navigationItems, selection: tab) { exportNowButton }
                    .padding(8)
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
        .geistDialog(
            isPresented: $showPreviewRequirements,
            title: Text("Finish Preview Setup"),
            message: Text("To preview your export, connect Apple Health so Health.md can read your data."),
            actions: [
                .cancel(),
                .action("Connect Apple Health") {
                    Task {
                        _ = try? await healthKitManager.requestAuthorization()
                        if healthKitManager.isAuthorized {
                            await Task.yield()
                            showPreview = true
                        }
                    }
                }
            ]
        )
        .sheet(isPresented: $showClassicExport) {
            NavigationStack { classicExportTab }
                .overlay(alignment: .topTrailing) {
                    Button(String(localized: "Done")) { showClassicExport = false }
                        .buttonStyle(.plain)
                        .glassFont(.caption)
                        .padding(.horizontal, 14)
                        .frame(minHeight: GlassMetrics.touchTarget)
                        .glassSurface(in: Capsule(), isInteractive: true)
                        .padding(GlassMetrics.screenMargin)
                        .accessibilityIdentifier("glass.classicExport.done")
                }
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
            #if DEBUG
            // Lets the classic export journeys reach the still-shipping Export settings directly.
            if UserDefaults.standard.bool(forKey: "UITestOpenClassicExport") { showClassicExport = true }
            #endif
            consumeFirstPreview(presentFirstExportPreview)
        }
    }

    private var resultBinding: Binding<ExportHistoryEntry?> {
        Binding(get: { resultEntry }, set: { resultEntry = $0 })
    }

    private func consumeFirstPreview(_ requested: Bool) {
        guard requested else { return }
        presentFirstExportPreview = false
        // As on the Export tab: without Health access the preview has nothing to show.
        if healthKitManager.isAuthorized {
            showPreview = true
        } else if configurationProtection.isEnabled {
            configurationProtection.presentBlockedChangeToast()
        } else {
            showPreviewRequirements = true
        }
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
            .task(id: ledgerStore.ledger) { publishWidgetSnapshot() }
        case .automations:
            if let profileCoordinator {
                AutomationsScreen(
                    coordinator: profileCoordinator,
                    historyContent: AnyView(scheduleDetails),
                    onRun: { exportRequest = ExportNowRequest(profileID: $0) },
                    onPreview: { profileID in
                        // The preview renders the live settings, so load this profile first.
                        _ = profileCoordinator.activate(profileID: profileID)
                        showPreview = true
                    },
                    onSchedulesChanged: { scheduleRevision += 1 },
                    onOpenExportSettings: { showClassicExport = true }
                )
            }
        case .settings:
            SettingsScreen(
                vaultManager: vaultManager,
                advancedSettings: advancedSettings,
                externalIntegrationManager: externalIntegrationManager,
                profileCoordinator: profileCoordinator,
                selectedTab: $selectedTab,
                showFolderPicker: $showFolderPicker,
                showExportProfiles: $showExportProfiles,
                showClinicianReport: $showClinicianReport
            )
        }
    }

    /// Interim home for the Schedule tab's history and retry.
    private var scheduleDetails: some View {
        ScheduleSettingsView(
            vaultManager: vaultManager,
            advancedSettings: advancedSettings,
            apiExportSettings: apiExportSettings,
            agentDataGatewaySettings: agentDataGatewaySettings,
            showFolderPicker: $showFolderPicker,
            profileCoordinator: profileCoordinator
        )
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
        } else if let assessment = executionHistoryAssessment,
                  assessment.needsWarning,
                  dismissedHistoryNotice != assessment {
            // After an export runs, say how far its history was checked, as the Export tab did.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(assessment.warningTitle)
                        .glassFont(.navTitle)
                    Spacer()
                    Button {
                        dismissedHistoryNotice = assessment
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Dismiss"))
                }
                HealthHistoryDisclosureContent(assessment: assessment, isExecution: true) {
                    if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                }
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
        let entries = profileCoordinator?.scheduledEntryStore.allEntries() ?? []
        return profiles.enumerated().map { index, profile in
            ArchiveProfile(
                id: profile.id,
                name: profile.name,
                destination: profileCoordinator.map { AutomationFacts(coordinator: $0).destination(profile) }
                    ?? destinationLabel(for: profile.target, profile: profile),
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
        if let latest = exportHistory.history.first(where: { $0.exportTarget == .apiEndpoint }),
           latest.presentationStatus == .failed {
            items.append(.init(
                id: "endpoint",
                title: String(localized: "Endpoint failing"),
                message: latest.failureReasonForDisplay?.shortDescription ?? latest.summaryDescription,
                actionTitle: String(localized: "All export settings"),
                action: { showClassicExport = true }
            ))
        }
        if profiles.contains(where: { $0.target == .connectedMac }), syncService.connectionState != .connected {
            items.append(.init(
                id: "mac",
                title: String(localized: "Mac offline"),
                message: String(localized: "Mac exports wait until your Mac is back on the same network."),
                actionTitle: nil,
                action: nil
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
            if let vaultURL = vaultManager.vaultURL,
               let file = Self.exportedFile(for: date, in: vaultURL) {
                onPreviewExport(ExportPresentationTarget(fileURL: file, securityScopedRootURL: vaultURL))
            } else if let target = vaultManager.lastExportPresentationTarget {
                onBrowseExportFolder(target)
            } else if let vaultURL = vaultManager.vaultURL {
                onBrowseExportFolder(ExportPresentationTarget(
                    fileURL: vaultURL.appendingPathComponent(profile.name),
                    securityScopedRootURL: vaultURL
                ))
            }
        }
    }

    /// Finds the date's file by its ISO date. Custom filenames without one open the folder.
    private static func exportedFile(for date: Date, in folder: URL) -> URL? {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
        let key = CoverageDateKey.key(for: date, calendar: .current)
        guard let files = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var visited = 0
        for case let url as URL in files {
            visited += 1
            if visited > 20_000 { return nil }
            if url.pathExtension == "md", url.lastPathComponent.contains(key) { return url }
        }
        return nil
    }

    private func publishWidgetSnapshot() {
        let model = archiveModel
        let stats = model.stats(month: model.now, filter: nil)
        let nextRun = archiveProfiles.compactMap(\.entry).filter(\.isEnabled).compactMap {
            ScheduleDateMath.calculateNextRunDate(schedule: $0.dateMathProjection, now: model.now)
        }.min()
        ArchiveWidgetPublisher.publish(
            streak: stats.streak,
            archivedCount: stats.archivedCount,
            gapCount: stats.gapCount,
            nextRun: nextRun
        )
        WeeklyGapNotification.refresh(gapCount: model.weeklyGapCount)
    }

    private func resume(_ profile: ArchiveProfile) {
        configurationProtection.performConfigurationChange {
            profileCoordinator?.scheduledEntryStore.update(profileID: profile.id) { $0.isEnabled = true }
            schedulingManager.refreshScheduledAutomation()
            scheduleRevision += 1
        }
    }

    private func resolveAllTimeRange() async -> (start: Date, end: Date)? {
        guard let earliest = await healthKitManager.findEarliestHealthDataDate() else { return nil }
        return (earliest, Date())
    }
}

/// Writes the facts the Archive widget reads from the app group. Health-free.
enum ArchiveWidgetPublisher {
    private struct Snapshot: Codable {
        let streak: Int
        let archivedCount: Int
        let gapCount: Int
        let nextRun: Date?
    }

    static func publish(streak: Int, archivedCount: Int, gapCount: Int, nextRun: Date?) {
        guard let data = try? JSONEncoder().encode(Snapshot(
            streak: streak,
            archivedCount: archivedCount,
            gapCount: gapCount,
            nextRun: nextRun
        )) else { return }
        UserDefaults(suiteName: CoverageLedgerStore.appGroupIdentifier)?
            .set(data, forKey: "healthMdArchiveWidgetSnapshot.v1")
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
            fetchHealthData: { date, snapshot in
                let settings = snapshot.makeAdvancedExportSettings()
                #if DEBUG
                if TestMode.useHealthKitExportPreviewFixtures || MarketingCapture.isActive {
                    return UITestHealthKitFixtures.exportPreviewHealthData(
                        for: date,
                        includeGranularData: settings.effectiveDetailPolicy.includesSelectedTimeSeries,
                        includeLargeSourceArchive: TestMode.healthKitExportPreviewLargeArchive
                            && settings.effectiveDetailPolicy.includesCanonicalArchive,
                        includePartialFailures: TestMode.healthKitExportPreviewPartialCapture
                    )
                }
                #endif
                return try? await healthKitManager.fetchHealthData(
                    for: date,
                    detailPolicy: settings.effectiveDetailPolicy,
                    metricSelection: settings.metricSelection,
                    timeZone: settings.exportTimeZoneOverride ?? .current
                )
            },
            requestHealthAuthorization: { try await healthKitManager.requestAuthorization() },
            onExport: onExport
        )
    }

    private var targetType: ExportPreviewTargetType {
        switch exportTargetSelection {
        case .localIPhoneFolder: return .localFile
        case .connectedMac: return .connectedMac
        case .apiEndpoint: return .apiEndpoint
        case .agentDataGateway: return .agentDataGateway
        }
    }
}
#endif
