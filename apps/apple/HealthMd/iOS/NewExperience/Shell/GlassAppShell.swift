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
    /// Commits a folder chosen inside the classic export sheet.
    let onSelectFolder: (URL) -> Void
    let executionHistoryAssessment: HealthHistoryAssessment?
    let isAssessingHistory: Bool
    let historyCheckAwaitsDecision: Bool
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
    /// Export tapped in the classic sheet; it runs once the sheet has gone, because a
    /// sheet presented during the dismissal (the folder picker) would be dropped.
    @State private var exportAfterClassicDismiss = false
    /// Counts exports requested from the classic sheet; each runs once it has closed.
    @State private var classicExportRequest = 0
    /// The classic sheet presents its own folder picker: one attached beneath a
    /// presented sheet cannot appear over it.
    @State private var showClassicFolderPicker = false
    @State private var showPreviewRequirements = false
    @State private var dismissedHistoryNotice: HealthHistoryAssessment?
    @State private var resultEntry: ExportHistoryEntry?
    /// The finished run the moment shows until the user leaves it.
    @State private var momentDone: ExportHistoryEntry?
    @State private var scheduleRevision = 0
    @State private var tabRootID = UUID()
    @State private var archiveFilter: UUID?
    @State private var windowSize: CGSize = .zero
    @State private var editingAutomation: AutomationEditRequest?
    /// FileViewerG: a day's written file pushes from the Archive with Back.
    @State private var archiveFile: ArchiveFileRoute?
    /// GatewayDestG's "Clinic destination · Managed" link, Practice-gated.
    @State private var showGatewayClinicAccess = false
    @State private var endpointSheet: EndpointSheetRequest?
    /// What a closing sheet asked to present next. It runs from that sheet's onDismiss,
    /// because a sheet presented while another is still dismissing can be dropped.
    @State private var afterSheetDismiss: (() -> Void)?
    /// LargeConfirmG: asked over the Archive once the Export now sheet has closed.
    @State private var pendingLargeExport: ExportScaleGuard.Scale?
    @ObservedObject private var gapBackfillRouter = WeeklyGapBackfillRouter.shared
    /// Set once this phone has shown its unfolded (inner display) layout. Only then
    /// does the folded layout invite the user to unfold.
    @AppStorage("glass.hasSeenUnfoldedLayout") private var hasSeenUnfoldedLayout = false

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

    private var windowClass: GlassWindowClass {
        GlassWindowClass.resolve(
            isPad: isPad,
            isRegularWidth: horizontalSizeClass == .regular,
            windowSize: windowSize,
            screenSize: Self.screenSize,
            hasSeenUnfolded: hasSeenUnfoldedLayout
        )
    }

    private static var screenSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.size ?? .zero
    }

    private func noteUnfoldedLayoutIfSeen() {
        guard !hasSeenUnfoldedLayout,
              GlassWindowClass.looksUnfolded(
                isPad: isPad,
                isRegularWidth: horizontalSizeClass == .regular,
                windowSize: windowSize
              ) else { return }
        hasSeenUnfoldedLayout = true
    }

    /// On iPad the Archive header carries Export now, and iPadAutomationsG and iPadSettingsG
    /// have none (Automations runs each profile itself). Only the empty Archive, which has
    /// no header, keeps it in the sidebar.
    private var sidebarShowsExportNow: Bool { tab.wrappedValue == .archive && needsSetup }

    private var exportNowButton: some View {
        ExportNowAccessoryButton(title: String(localized: "Export now")) {
            exportRequest = ExportNowRequest()
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if usesSidebar {
                GlassSidebar(title: "Health.md", items: Self.navigationItems, selection: tab) {
                    if tab.wrappedValue == .archive && !needsSetup { sidebarProfiles }
                } accessory: {
                    if sidebarShowsExportNow { exportNowButton }
                }
                .padding([.leading, .vertical], 16)
            }
            ZStack(alignment: .bottom) {
                content.id(tabRootID)
                VStack(spacing: 10) {
                    historyCard
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
        .overlay { exportMoment }
        .overlay { largeExportDecision }
        .overlay { historyDecision }
        .ignoresSafeArea(.keyboard)
        .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
        } action: { size in
            windowSize = size
            noteUnfoldedLayoutIfSeen()
        }
        .onChange(of: horizontalSizeClass) { _, _ in noteUnfoldedLayoutIfSeen() }
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
                preview: { exportFromPreview in
                    AnyView(GlassExportPreviewSheet(
                        vaultManager: vaultManager,
                        startDate: startDate,
                        endDate: endDate,
                        dateRangePreset: dateRangePreset,
                        exportTargetSelection: exportTargetSelection,
                        destinationLabel: destinationLabel(for: exportTargetSelection, profile: nil),
                        onExport: exportFromPreview,
                        presentation: .glassPushed
                    ))
                },
                onExport: onExport,
                onConfirmLargeExport: { pendingLargeExport = $0 }
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
            .glassTheme()
        }
        .sheet(isPresented: $showAttention, onDismiss: runAfterSheetDismiss) {
            // Each fix opens its own screen once Needs attention has gone.
            AttentionScreen(items: attentionItems.map { item in
                guard let action = item.action else { return item }
                return .init(
                    id: item.id,
                    title: item.title,
                    message: item.message,
                    actionTitle: item.actionTitle,
                    action: { afterSheetDismiss = action }
                )
            })
            .glassTheme()
        }
        .sheet(item: $endpointSheet) { request in
            Group {
                if request.target == .agentDataGateway {
                    GlassGatewayDestinationSheet(
                        settings: agentDataGatewaySettings,
                        onOpenClinicAccess: PracticeFeaturePolicy.current.isEnabled ? { showGatewayClinicAccess = true } : nil
                    )
                    .sheet(isPresented: $showGatewayClinicAccess) {
                        NavigationStack { GlassClinicAccessScreen(coordinator: profileCoordinator) }
                            .glassTheme()
                    }
                } else {
                    GlassAPIDestinationSheet(settings: apiExportSettings)
                }
            }
            .glassTheme()
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
        .sheet(isPresented: $showClassicExport, onDismiss: {
            guard exportAfterClassicDismiss else { return }
            exportAfterClassicDismiss = false
            // The dismissal handler can belong to the body that presented the sheet,
            // whose `onExport` still sees the destination chosen before the sheet's
            // edits. Run the export from the current body instead.
            classicExportRequest += 1
        }) {
            NavigationStack { classicExportTab }
                .sheet(isPresented: $showClassicFolderPicker) {
                    FolderPicker { url in
                        configurationProtection.performConfigurationChange { onSelectFolder(url) }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                .overlay(alignment: .topTrailing) {
                    Button(String(localized: "Close")) { showClassicExport = false }
                        .buttonStyle(.plain)
                        .glassFont(.caption)
                        .padding(.horizontal, 14)
                        .frame(minHeight: GlassMetrics.touchTarget)
                        .glassSurface(in: Capsule(), isInteractive: true)
                        .padding(GlassMetrics.screenMargin)
                        .accessibilityIdentifier("glass.classicExport.done")
                }
        }
        .sheet(item: resultBinding, onDismiss: runAfterSheetDismiss) { entry in
            ExportResultScreen(
                entry: entry,
                onRetry: { start, end in
                    // Export now opens once the result sheet has closed.
                    afterSheetDismiss = { exportRequest = ExportNowRequest(startDate: start, endDate: end) }
                },
                onShowInFiles: showInFilesAction(for: entry),
                // ExportResultG's day links: a local run's file for that date.
                dayFile: showInFilesAction(for: entry) == nil ? nil : { date in
                    guard let root = vaultManager.vaultURL,
                          let file = Self.exportedFile(for: date, in: root) else { return nil }
                    return ExportPresentationTarget(fileURL: file, securityScopedRootURL: root)
                }
            )
            .glassTheme()
        }
        .onChange(of: isExporting) { wasExporting, nowExporting in
            if nowExporting { momentDone = nil }
            // A full failure already raises ContentView's dialog.
            guard wasExporting, !nowExporting, let latest = exportHistory.history.first,
                  latest.timestamp.timeIntervalSinceNow > -60 else { return }
            switch latest.presentationStatus {
            case .success: momentDone = latest
            case .partialSuccess: resultEntry = latest
            case .failed: break
            }
        }
        .onChange(of: presentFirstExportPreview) { _, requested in consumeFirstPreview(requested) }
        .onChange(of: classicExportRequest) { _, _ in onExport() }
        .onChange(of: gapBackfillRouter.pendingRequest, initial: true) { _, _ in consumeGapBackfillRequest() }
        #if DEBUG
        // App Store screenshots: a month of coverage with two gaps, in memory only.
        .task(id: archiveProfiles.map(\.id)) {
            if TestMode.isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_COVERAGE"] == "true" {
                ledgerStore.seedScreenshotCoverage(profileIDs: archiveProfiles.map(\.id))
            }
        }
        #endif
        .onAppear {
            #if DEBUG
            // Lets the classic export journeys reach the still-shipping Export settings directly.
            if UserDefaults.standard.bool(forKey: "UITestOpenClassicExport") { showClassicExport = true }
            #endif
            consumeFirstPreview(presentFirstExportPreview)
        }
    }

    // MARK: - Export moment

    /// MomentGlass covers the app while an export runs, then reports what it wrote.
    @ViewBuilder private var exportMoment: some View {
        if isExporting {
            ExportMomentView(
                phase: .running(ExportMomentProgress.make(
                    message: exportStatusMessage,
                    progress: exportProgress,
                    start: startDate,
                    end: endDate,
                    calendar: .current
                )),
                onCancel: onCancelExport,
                onSeeArchive: {}
            )
            .transition(.opacity)
        } else if let done = momentDone {
            ExportMomentView(
                phase: .done(title: ExportMomentSummary.title(done), subtitle: ExportMomentSummary.subtitle(done)),
                onCancel: {},
                onSeeArchive: {
                    momentDone = nil
                    tab.wrappedValue = .archive
                }
            )
            .transition(.opacity)
        }
    }

    /// Opens the export folder for a local run; other destinations have no folder to show.
    private func showInFilesAction(for entry: ExportHistoryEntry) -> (() -> Void)? {
        guard entry.exportTarget == nil || entry.exportTarget == .localIPhoneFolder,
              vaultManager.vaultURL != nil || vaultManager.lastExportPresentationTarget != nil else { return nil }
        return {
            if let target = vaultManager.lastExportPresentationTarget {
                onBrowseExportFolder(target)
            } else if let vaultURL = vaultManager.vaultURL {
                onBrowseExportFolder(ExportPresentationTarget(fileURL: vaultURL, securityScopedRootURL: vaultURL))
            }
        }
    }

    private func runAfterSheetDismiss() {
        guard let next = afterSheetDismiss else { return }
        afterSheetDismiss = nil
        next()
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
            // ArchiveGlass*: the sentence card's Edit pushes ComposeGlass, with the
            // system back button returning to the Archive.
            NavigationStack {
                ArchiveScreen(
                    model: archiveModel,
                    layout: ArchiveLayout(windowClass),
                    filter: $archiveFilter,
                    needsSetup: needsSetup,
                    setup: ArchiveSetupState(isHealthConnected: healthKitManager.isAuthorized),
                    attentionCount: attentionItems.count,
                    onAction: handleDayAction,
                    onResume: resume,
                    onManageAutomations: { tab.wrappedValue = .automations },
                    onEditAutomation: { editingAutomation = AutomationEditRequest(id: $0.id) },
                    onShowAttention: { showAttention = true },
                    onConnectHealth: connectHealth,
                    onSetUp: { showFolderPicker = true },
                    onBackfill: { exportRequest = ExportNowRequest() },
                    onExportNow: { exportRequest = ExportNowRequest() }
                )
                .task(id: ledgerStore.ledger) { publishWidgetSnapshot() }
                .navigationTitle(String(localized: "Archive"))
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $editingAutomation) { request in
                    archiveComposer(request)
                }
                .navigationDestination(item: $archiveFile) { route in
                    ExportedMarkdownViewer(
                        target: ExportPresentationTarget(fileURL: route.fileURL, securityScopedRootURL: route.rootURL),
                        presentedModally: false
                    )
                }
            }
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

    /// ComposeGlass, pushed from the Archive sentence card's Edit.
    @ViewBuilder private func archiveComposer(_ request: AutomationEditRequest) -> some View {
        if let profileCoordinator {
            ComposerScreen(
                coordinator: profileCoordinator,
                profileID: request.id,
                onPreview: { profileID in
                    editingAutomation = nil
                    _ = profileCoordinator.activate(profileID: profileID)
                    showPreview = true
                },
                onSchedulesChanged: { scheduleRevision += 1 },
                onRun: { profileID in
                    editingAutomation = nil
                    exportRequest = ExportNowRequest(profileID: profileID)
                }
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
            showFolderPicker: $showClassicFolderPicker,
            presentFirstExportPreview: .constant(false),
            canExport: canExport,
            onExportTapped: {
                exportAfterClassicDismiss = true
                showClassicExport = false
            },
            historyProfileStore: profileCoordinator?.profileStore,
            executionHistoryAssessment: executionHistoryAssessment,
            isAssessingHistory: isAssessingHistory,
            onContinueWithoutHistoryVerification: onContinueWithoutHistoryVerification,
            onCancelHistoryVerification: onCancelHistoryVerification
        )
    }

    // MARK: - Large export

    /// LargeConfirmG: the Export now sheet has closed; the decision sits over the Archive.
    @ViewBuilder private var largeExportDecision: some View {
        if let scale = pendingLargeExport {
            GlassDecisionDialog(
                title: String(localized: "Export \(scale.dayCount) days?"),
                message: String(localized: "This writes about \(scale.estimatedFileCount) files and can take several minutes. Keep Health.md open until it finishes. Completed days are kept if you stop."),
                actions: [
                    .init(
                        title: String(localized: "Export \(scale.dayCount) days"),
                        role: .primary,
                        accessibilityIdentifier: "glass.exportNow.largeConfirm"
                    ) {
                        pendingLargeExport = nil
                        onExport()
                    },
                    .init(title: String(localized: "Cancel")) { pendingLargeExport = nil }
                ]
            )
        }
    }

    // MARK: - Weekly gap backfill

    /// NotificationsG's "Tap to backfill": Export now over this week's gaps, or the plain
    /// sheet when the week has none left.
    private func backfillThisWeek() {
        let model = archiveModel
        if let range = WeeklyGapNotification.backfillRange(
            today: model.now,
            calendar: model.calendar,
            isGap: { model.status(on: $0, filter: nil) == .missing }
        ) {
            exportRequest = ExportNowRequest(startDate: range.start, endDate: range.end)
        } else {
            exportRequest = ExportNowRequest()
        }
    }

    /// A tapped weekly gap notification lands on the Archive with backfill open.
    private func consumeGapBackfillRequest() {
        guard gapBackfillRouter.consume() else { return }
        editingAutomation = nil
        showAttention = false
        resultEntry = nil
        momentDone = nil
        tab.wrappedValue = .archive
        guard !needsSetup, !isExporting else { return }
        backfillThisWeek()
    }

    // MARK: - History check

    /// The export flow pauses on this decision, so it stays visible over every tab.
    /// True while a timed-out history check waits for Continue or Cancel.
    private var awaitsHistoryDecision: Bool {
        isAssessingHistory && historyCheckAwaitsDecision
    }

    /// HistoryWarnG: the check could not confirm older history, so the export waits here.
    @ViewBuilder private var historyDecision: some View {
        if awaitsHistoryDecision {
            GlassDecisionDialog(
                title: String(localized: "Can’t confirm older history"),
                message: String(localized: "Apple Health may only share recent data with Health.md, so older dates could come out empty. You can export anyway or check access first."),
                actions: [
                    .init(title: String(localized: "Check Health access"), role: .primary, accessibilityIdentifier: "export.historyWarning.reviewAccess") {
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    },
                    .init(title: String(localized: "Export anyway"), accessibilityIdentifier: "export.historyWarning.continueUnverified") {
                        onContinueWithoutHistoryVerification()
                    },
                    .init(title: String(localized: "Cancel"), role: .cancel, accessibilityIdentifier: "export.historyWarning.cancelCheck") {
                        onCancelHistoryVerification()
                    }
                ]
            )
            .accessibilityIdentifier("export.historyWarning")
        }
    }

    @ViewBuilder private var historyCard: some View {
        if awaitsHistoryDecision {
            EmptyView()
        } else if isAssessingHistory {
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
        let facts = profileCoordinator.map { AutomationFacts(coordinator: $0) }
        let ledger = ledgerStore.ledger
        return profiles.enumerated().map { index, profile in
            let destination = facts?.destination(profile) ?? destinationLabel(for: profile.target, profile: profile)
            let entry = entries.first { $0.profileID == profile.id }
            return ArchiveProfile(
                id: profile.id,
                name: profile.name,
                destination: destination,
                colorIndex: index,
                entry: entry,
                outputPath: outputPath(for: profile, destination: destination),
                pausedSince: ArchivePause.since(
                    events: ledger.scheduleEvents[profile.id] ?? [],
                    isPaused: entry?.isEnabled == false,
                    ledgerStartedAt: ledger.startedAt,
                    didSeedFromHistory: ledger.didSeedFromHistory
                ),
                sentence: facts?.sentence(profile).plainText,
                writesFilesOnDevice: profile.target == .localIPhoneFolder
            )
        }
    }

    /// The profile's own output settings decide each date's file; endpoints show where they POST.
    private func outputPath(for profile: ExportProfile, destination: String) -> ArchiveOutputPath {
        let store = profileCoordinator?.destinationStore
        switch profile.target {
        case .localIPhoneFolder:
            return .files(
                root: destination,
                healthSubfolder: profile.settings.healthSubfolder ?? vaultManager.healthSubfolder,
                settings: profile.settings
            )
        case .connectedMac:
            let root = syncService.macDestinationStatus?.destinationPathForDisplay
                ?? syncService.macDestinationStatus?.destinationDisplayName
                ?? destination
            // Without its own subfolder the Mac applies its local setting, which the iPhone can't see.
            guard let subfolder = profile.settings.healthSubfolder else { return .label(root) }
            return .files(root: root, healthSubfolder: subfolder, settings: profile.settings)
        case .apiEndpoint:
            let url = store?.apiEndpoint(id: profile.apiEndpointID)?.endpointURLString
            return ArchiveOutputPath.endpointLine(url.flatMap(URL.init(string:)))
                .map { .endpoint(line: $0) } ?? .label(destination)
        case .agentDataGateway:
            let gateway = store?.agentDataGateway(id: store?.agentDataGatewayBinding(profileID: profile.id))
            let ingest = gateway.flatMap { AgentDataGatewayDestinationSnapshot(endpointURLString: $0.endpointURLString) }
            return ArchiveOutputPath.endpointLine(ingest?.ingestURL)
                .map { .endpoint(line: $0) } ?? .label(destination)
        }
    }

    private var sidebarProfiles: some View {
        ArchiveSidebarProfiles(profiles: archiveProfiles, filter: $archiveFilter)
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
                action: connectHealth
            ))
        } else if let item = medicationPermissionItem {
            items.append(item)
        }
        if vaultManager.requiresVaultReselection {
            let waiting = profiles.filter { $0.target == .localIPhoneFolder && $0.folderVaultID == nil }.map(\.name)
            let folder = vaultManager.vaultName
            items.append(.init(
                id: "folder",
                title: String(localized: "Folder unavailable"),
                message: waiting.isEmpty
                    ? String(localized: "The \(folder) folder moved or can’t be verified. Choose it again to resume exports.")
                    : String(localized: "The \(folder) folder moved or can’t be verified. Choose it again to resume \(waiting.formatted(.list(type: .and)))."),
                actionTitle: String(localized: "Choose folder"),
                action: { showFolderPicker = true }
            ))
        }
        items.append(contentsOf: [ExportTargetSelection.apiEndpoint, .agentDataGateway].compactMap(endpointItem))
        let macProfiles = profiles.filter { $0.target == .connectedMac }
        if !macProfiles.isEmpty, syncService.connectionState != .connected {
            let mac = syncService.connectedPeerName
                ?? syncService.savedManualIPMacName
                ?? String(localized: "Connected Mac")
            let names = macProfiles.map(\.name).formatted(.list(type: .and))
            items.append(.init(
                id: "mac",
                title: String(localized: "Mac offline"),
                message: String(localized: "\(mac) is offline. \(names) exports wait until it’s back on the same network."),
                actionTitle: nil,
                action: nil
            ))
        }
        return items
    }

    /// Medications use their own per-object permission, so a profile can select them
    /// while Health.md has never been allowed to read them.
    private var medicationPermissionItem: AttentionScreen.Item? {
        guard healthKitManager.isMedicationAuthorizationSupported,
              !healthKitManager.isMedicationAuthorizationRequested else { return nil }
        let medicationIDs = Set(HealthMetrics.availableInCurrentBuild.filter { $0.category == .medications }.map(\.id))
        let selecting = profiles.filter { !$0.settings.metricSelection.enabledMetricIDs.isDisjoint(with: medicationIDs) }
        guard !selecting.isEmpty else { return nil }
        return .init(
            id: "health.medications",
            title: String(localized: "Apple Health permission"),
            message: String(localized: "Health.md can’t read Medications. Exports skip them until you allow access."),
            actionTitle: String(localized: "Allow Medications"),
            action: { Task { try? await healthKitManager.requestMedicationAuthorization(force: true) } }
        )
    }

    /// "api.example.com returned 503 three times. Agent feed will retry at the next refresh."
    private func endpointItem(_ target: ExportTargetSelection) -> AttentionScreen.Item? {
        let runs = exportHistory.history.filter { $0.exportTarget == target }
        let failures = ArchiveAttention.consecutiveFailures(runs.map(\.presentationStatus))
        guard failures > 0, let latest = runs.first else { return nil }
        let candidates = profiles.filter { $0.target == target }
        let profile = candidates.first { $0.name == latest.profileName } ?? (candidates.count == 1 ? candidates.first : nil)
        let host = endpointHost(for: profile, target: target)
        let statuses = runs.prefix(failures).map { run in
            run.failedDateDetails.compactMap(\.errorDetails).first { ArchiveAttention.httpStatus(in: $0) != nil }
        }
        var message: String
        let times = AttentionCountText.spelled(failures)
        if let status = ArchiveAttention.repeatedStatus(statuses) {
            // A status code is an identifier, not a quantity: never grouped or localized.
            let code = String(describing: status)
            message = failures == 1
                ? String(localized: "\(host) returned \(code).")
                : String(localized: "\(host) returned \(code) \(times) times.")
        } else {
            let reason = latest.failureReasonForDisplay?.shortDescription ?? latest.summaryDescription
            message = failures == 1
                ? String(localized: "\(host): \(reason).")
                : String(localized: "\(host) failed \(times) times: \(reason).")
        }
        if let profile, let entry = profileCoordinator?.scheduledEntryStore.entry(profileID: profile.id), entry.isEnabled {
            message += " " + (entry.todayRefreshEnabled
                ? String(localized: "\(profile.name) will retry at the next refresh.")
                : String(localized: "\(profile.name) will retry at the next scheduled run."))
        }
        return .init(
            id: "endpoint.\(target.rawValue)",
            title: target == .agentDataGateway
                ? String(localized: "Agent Data gateway failing")
                : String(localized: "Endpoint failing"),
            message: message,
            actionTitle: String(localized: "View endpoint"),
            action: { endpointSheet = EndpointSheetRequest(target: target) }
        )
    }

    private func endpointHost(for profile: ExportProfile?, target: ExportTargetSelection) -> String {
        let store = profileCoordinator?.destinationStore
        let urlString: String?
        switch target {
        case .agentDataGateway:
            urlString = profile.flatMap { store?.agentDataGateway(id: store?.agentDataGatewayBinding(profileID: $0.id)) }?
                .endpointURLString ?? agentDataGatewaySettings.endpointURLString
        default:
            urlString = profile.flatMap { store?.apiEndpoint(id: $0.apiEndpointID) }?.endpointURLString
                ?? apiExportSettings.endpointURLString
        }
        if let host = urlString.flatMap(URL.init(string:))?.host(), !host.isEmpty { return host }
        return target == .agentDataGateway ? agentDataGatewaySettings.displayName : apiExportSettings.displayName
    }

    private func connectHealth() {
        Task { _ = try? await healthKitManager.requestAuthorization() }
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
            openArchiveFile(profile, on: date)
        }
    }

    /// FileViewerG: the automation's own file for the date, from its own folder and
    /// format. A missing file opens its folder; the disk is read off the main actor.
    private func openArchiveFile(_ profile: ArchiveProfile, on date: Date) {
        guard archiveModel.canOpen(profile, on: date),
              let relativePath = profile.outputPath?.relativeFilePath(on: date) else { return }
        let folderVaultID = profiles.first { $0.id == profile.id }?.folderVaultID
        let bookmark = profileCoordinator?.destinationStore.vault(id: folderVaultID)?.bookmarkData
        // A profile without its own folder writes to the app's saved folder.
        let fallbackRoot = folderVaultID == nil ? vaultManager.vaultURL : nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ArchiveFileLocation.locate(relativePath: relativePath, bookmarkData: bookmark, fallbackRootURL: fallbackRoot)
            }.value
            switch result.location {
            case .file(let file):
                if ExportFilePreviewRoute.route(for: file) == .inAppMarkdown {
                    archiveFile = ArchiveFileRoute(fileURL: file, rootURL: result.rootURL)
                } else {
                    onPreviewExport(ExportPresentationTarget(fileURL: file, securityScopedRootURL: result.rootURL))
                }
            case .folder(let folder):
                // The browser opens the target file's folder.
                let expected = (relativePath as NSString).lastPathComponent
                onBrowseExportFolder(ExportPresentationTarget(
                    fileURL: folder.appendingPathComponent(expected, isDirectory: false),
                    securityScopedRootURL: result.rootURL
                ))
            case .unavailable:
                showFolderPicker = true
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.now)
        let recentDays = (1...14).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.map { model.status(on: $0, filter: nil).rawValue }
        ArchiveWidgetPublisher.publish(
            streak: stats.streak,
            archivedCount: stats.archivedCount,
            gapCount: stats.gapCount,
            nextRun: nextRun,
            recentDays: recentDays
        )
        WeeklyGapNotification.refresh(gapCount: model.weeklyGapCount)
    }

    private func resume(_ profile: ArchiveProfile) {
        configurationProtection.performConfigurationChange {
            guard let entryStore = profileCoordinator?.scheduledEntryStore else { return }
            entryStore.update(profileID: profile.id) { $0.isEnabled = true }
            // As every other schedule switch: asks for notifications and refreshes the schedule.
            AutomationScheduleSwitch.didSwitch(
                isEnabled: true,
                entries: entryStore.entries,
                schedulingManager: schedulingManager
            )
            scheduleRevision += 1
        }
    }

    private func resolveAllTimeRange() async -> (start: Date, end: Date)? {
        guard let earliest = await healthKitManager.findEarliestHealthDataDate() else { return nil }
        return (earliest, Date())
    }
}

/// Opens one automation's detail from the Archive's "Edit".
struct AutomationEditRequest: Identifiable, Hashable {
    let id: UUID
}

/// Opens the API endpoint or Agent Data gateway settings from Needs attention.
struct EndpointSheetRequest: Identifiable, Equatable {
    let target: ExportTargetSelection
    var id: String { target.rawValue }
}

/// Writes the facts the Archive widget reads from the app group. Health-free.
enum ArchiveWidgetPublisher {
    private struct Snapshot: Codable {
        let streak: Int
        let archivedCount: Int
        let gapCount: Int
        let nextRun: Date?
        /// "All" coverage status raw values for the 14 days before today, oldest first.
        let recentDays: [String]
    }

    static func publish(streak: Int, archivedCount: Int, gapCount: Int, nextRun: Date?, recentDays: [String]) {
        guard let data = try? JSONEncoder().encode(Snapshot(
            streak: streak,
            archivedCount: archivedCount,
            gapCount: gapCount,
            nextRun: nextRun,
            recentDays: recentDays
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
    var presentation: ExportPreviewPresentation = .glass

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
            onExport: onExport,
            presentation: presentation
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

/// A written file opened from an Archive day.
struct ArchiveFileRoute: Hashable {
    let fileURL: URL
    let rootURL: URL?
}
#endif
