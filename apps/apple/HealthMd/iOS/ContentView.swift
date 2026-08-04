import SwiftUI
import UIKit
import StoreKit
import Combine
import QuickLook
import os.log

enum ConnectedMacInteractiveResultValidator {
    static func failure(for payload: MacExportResultPayload) -> MacExportFailure? {
        guard !payload.hasConsistentFileAccounting else { return nil }
        return MacExportFailure(
            jobID: payload.jobID,
            reason: .payloadDecodeFailure,
            message: "Mac export returned inconsistent file accounting.",
            underlyingError: "The connected Mac result was rejected before export history was recorded."
        )
    }
}

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "Export")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var directCLIService: IPhoneDirectCLIService
    @EnvironmentObject var corpusRecoveryManager: IPhoneCorpusExportRecoveryManager
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @EnvironmentObject var schedulingManager: SchedulingManager

    @State private var selectedTab: NavTab = .export
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var dateRangePreset: ExportDateRangePreset = .today
    @State private var showFolderPicker = false
    @State private var showDestinationChangedAlert = false
    @State private var presentFirstExportPreview = false
    @State private var isExporting = false
    @State private var isRequestingHealthAuthorization = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatusMessage = ""
    @State private var partialExportNotice: PartialExportNotice?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var errorReason: ExportFailureReason?
    @State private var statusDismissTimer: Timer?
    @State private var exportTask: Task<Void, Never>?
    @State private var quickLookURL: URL?
    @State private var quickLookTarget: ExportPresentationTarget?
    @State private var markdownPreview: ExportedMarkdownPresentation?
    @State private var markdownPreviewTarget: ExportPresentationTarget?
    @State private var exportFolderBrowserTarget: ExportPresentationTarget?
    @State private var browsedFileURL: URL?
    @State private var showExportFolderBrowser = false
    @State private var showPaywall = false
    @State private var showMarketingMetricSelection = false
    @State private var showMarketingFormatCustomization = false
    @State private var showMarketingIndividualTracking = false
    @State private var showMarketingDailyNoteInjection = false
    @State private var showMarketingPaywall = false
    @State private var showMarketingOnboarding = false
    @AppStorage(ExportTargetSelection.storageKey) private var exportTargetSelection: ExportTargetSelection = .localIPhoneFolder
    @StateObject private var apiExportSettings = APIExportSettings()
    @EnvironmentObject var externalIntegrationManager: ExternalIntegrationManager
    @State private var activeMacExportJobID: UUID?
    @State private var macExportPayloadSent = false
    @State private var macExportUsesResumableCorpus = false
    @State private var macExportWaitingForReconnect = false
    @State private var macExportQuotaRecorded = false
    @State private var activeMacExportStartDate: Date?
    @State private var activeMacExportEndDate: Date?
    @AppStorage("discordPromoDismissed") private var discordPromoDismissed = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    init() {
        let savedDateRange = Self.initialDateRangeSelection()
        _startDate = State(initialValue: savedDateRange.startDate)
        _endDate = State(initialValue: savedDateRange.endDate)
        _dateRangePreset = State(initialValue: savedDateRange.preset)
    }

    private static func initialDateRangeSelection() -> ExportDateRangeSelection {
        #if DEBUG
        if TestMode.isUITesting || MarketingCapture.isActive {
            return ExportDateRangeSelection.defaultSelection()
        }
        #endif
        return ExportDateRangeSelectionStore.shared.load()
    }

    private var shouldPersistDateRangeSelection: Bool {
        #if DEBUG
        return !TestMode.isUITesting && !MarketingCapture.isActive
        #else
        return true
        #endif
    }

    var body: some View {
        if !hasCompletedOnboarding && (!TestMode.isUITesting || TestMode.showsOnboarding) {
            OnboardingView(
                showFolderPicker: $showFolderPicker,
                vaultManager: vaultManager,
                onComplete: {
                    HealthMdReleaseNotes.markCurrentVersionAsSeenAfterOnboarding()
                    withOptionalMotionAnimation(AnimationTimings.smooth) {
                        selectedTab = .export
                        presentFirstExportPreview = true
                        hasCompletedOnboarding = true
                    }
                }
            )
            .environmentObject(healthKitManager)
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    vaultManager.setVaultFolder(url)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        } else {
        ZStack {
            // Clean minimal background
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                if !discordPromoDismissed {
                    DiscordPromoBanner {
                        withOptionalMotionAnimation(AnimationTimings.standard) {
                            discordPromoDismissed = true
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                TabView(selection: $selectedTab) {
                    ExportTabView(
                        healthKitManager: healthKitManager,
                        vaultManager: vaultManager,
                        syncService: syncService,
                        advancedSettings: advancedSettings,
                        apiExportSettings: apiExportSettings,
                        externalIntegrations: ConnectedAppsFeature.isEnabled
                            ? externalIntegrationManager
                            : nil,
                        exportTargetSelection: $exportTargetSelection,
                        startDate: $startDate,
                        endDate: $endDate,
                        dateRangePreset: $dateRangePreset,
                        isExporting: $isExporting,
                        exportProgress: $exportProgress,
                        exportStatusMessage: $exportStatusMessage,
                        showFolderPicker: $showFolderPicker,
                        presentFirstExportPreview: $presentFirstExportPreview,
                        canExport: canExport,
                        onCancelExport: cancelExport,
                        onExportTapped: exportData
                    )
                    .tabItem {
                        Label("Export", systemImage: "arrow.up.doc.fill")
                            .accessibilityIdentifier(AccessibilityID.Tab.export)
                    }
                    .tag(NavTab.export)
                    .accessibilityIdentifier(AccessibilityID.Tab.export)

                    ScheduleTabView(
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        apiExportSettings: apiExportSettings,
                        showFolderPicker: $showFolderPicker
                    )
                    .environmentObject(schedulingManager)
                    .environmentObject(healthKitManager)
                        .tabItem {
                            Label("Schedule", systemImage: "clock.fill")
                                .accessibilityIdentifier(AccessibilityID.Tab.schedule)
                        }
                        .tag(NavTab.schedule)
                        .accessibilityIdentifier(AccessibilityID.Tab.schedule)

                    NavigationStack {
                        SyncSettingsView()
                    }
                    .tabItem {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            .accessibilityIdentifier(AccessibilityID.Tab.sync)
                    }
                    .tag(NavTab.sync)
                    .accessibilityIdentifier(AccessibilityID.Tab.sync)

                    SettingsTabView(
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        externalIntegrationManager: externalIntegrationManager,
                        showFolderPicker: $showFolderPicker
                    )
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                            .accessibilityIdentifier(AccessibilityID.Tab.settings)
                    }
                    .tag(NavTab.settings)
                    .accessibilityIdentifier(AccessibilityID.Tab.settings)
                }
                .tint(Color.accent)
                .onAppear {
                    if directCLIService.pendingPairingLink != nil { selectedTab = .sync }
                }
                .onChange(of: directCLIService.pendingPairingLink) { _, pairingLink in
                    if pairingLink != nil { selectedTab = .sync }
                }
            }

            // Toast notifications
            VStack {
                Spacer()

                PartialExportNoticeToast(
                    notice: $partialExportNotice,
                    bottomPadding: 120,
                    onDismiss: dismissStatus,
                    requestHealthAuthorization: {
                        try await healthKitManager.requestAuthorization()
                    }
                )

                // Per-file writers publish intermediate status while a batch is still running.
                // Keep the completion toast hidden until the whole export operation finishes.
                if !isExporting,
                   partialExportNotice == nil,
                   let status = vaultManager.lastExportStatus {
                    let isSuccess = status.starts(with: "Exported") || status.starts(with: "Updated")
                    let presentationTarget = isSuccess
                        ? vaultManager.lastExportPresentationTarget
                        : nil
                    ExportStatusBadge(
                        status: isSuccess ? .success(status) : .error(status),
                        onDismiss: dismissStatus,
                        exportFileName: presentationTarget?.fileURL.lastPathComponent,
                        onPreview: presentationTarget.map { target in
                            { presentExportPreview(target) }
                        },
                        onBrowseFolder: presentationTarget.map { target in
                            { browseExportFolder(target) }
                        }
                    )
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                vaultManager.setVaultFolder(url)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExportFolderBrowser, onDismiss: finishBrowsingExportFolder) {
            if let target = exportFolderBrowserTarget {
                ExportFolderBrowser(
                    initialDirectoryURL: target.folderURL,
                    onFileSelected: { url in
                        browsedFileURL = url
                        showExportFolderBrowser = false
                    },
                    onCancel: {
                        showExportFolderBrowser = false
                    }
                )
                .ignoresSafeArea()
            }
        }
        .sheet(item: $markdownPreview, onDismiss: releaseMarkdownPreviewAccess) { presentation in
            ExportedMarkdownViewer(target: presentation.target)
        }
        .quickLookPreview($quickLookURL)
        .onChange(of: quickLookURL) { _, newURL in
            if newURL == nil {
                releaseQuickLookAccess()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: currentPaywallContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $showMarketingMetricSelection) {
            MarketingSheetWrapper {
                MetricSelectionView(
                    selectionState: advancedSettings.metricSelection,
                    healthKitManager: healthKitManager
                )
            }
        }
        .sheet(isPresented: $showMarketingFormatCustomization) {
            MarketingSheetWrapper {
                FormatCustomizationView(customization: advancedSettings.formatCustomization)
            }
        }
        .sheet(isPresented: $showMarketingIndividualTracking) {
            MarketingSheetWrapper {
                IndividualTrackingView(
                    settings: advancedSettings.individualTracking,
                    metricSelection: advancedSettings.metricSelection
                )
            }
        }
        .sheet(isPresented: $showMarketingDailyNoteInjection) {
            MarketingSheetWrapper {
                DailyNoteInjectionView(
                    settings: advancedSettings.dailyNoteInjection,
                    metricSelection: advancedSettings.metricSelection,
                    healthSubfolder: vaultManager.healthSubfolder
                )
            }
        }
        .sheet(isPresented: $showMarketingPaywall) {
            PaywallView(context: .export)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onReceive(NotificationCenter.default.publisher(for: MarketingCapture.dismissSheetNotification)) { _ in
                    showMarketingPaywall = false
                }
        }
        .sheet(isPresented: $showMarketingOnboarding) {
            OnboardingView(
                showFolderPicker: .constant(false),
                vaultManager: vaultManager,
                onComplete: {}
            )
            .environmentObject(healthKitManager)
            .onReceive(NotificationCenter.default.publisher(for: MarketingCapture.dismissSheetNotification)) { _ in
                showMarketingOnboarding = false
            }
        }
        #endif
        .alert("Export Folder Changed", isPresented: $showDestinationChangedAlert) {
            Button("Choose Folder") { showFolderPicker = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved folder now points to a different location. Health.md paused local exports so it won’t write somewhere you did not select. Review any duplicate or conflict in Files, then re-select the intended folder.")
        }
        .alert(errorReason?.alertTitle ?? ExportFailureReason.unknown.alertTitle, isPresented: $showError) {
            if errorReason == .noHealthData {
                Button("Open Health App") {
                    if let healthURL = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(healthURL)
                    }
                }
            }
            Button(errorReason == .noHealthData ? "Done" : "OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert(
            schedulingManager.notificationExportResult?.title ?? "Export",
            isPresented: Binding(
                get: {
                    guard let result = schedulingManager.notificationExportResult else { return false }
                    return !NotificationExportActivityTracker.shared.handles(result)
                },
                set: { if !$0 { schedulingManager.notificationExportResult = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                schedulingManager.notificationExportResult = nil
            }
        } message: {
            if let result = schedulingManager.notificationExportResult {
                Text(result.message)
            }
        }
        .keepsScreenAwake(while: isExporting)
        .onReceive(syncService.$latestMacExportMessage.compactMap { $0 }) { message in
            handleMacExportMessage(message)
        }
        .onReceive(corpusRecoveryManager.$activeSnapshot) { snapshot in
            handleCorpusRecoverySnapshot(snapshot)
        }
        .onAppear {
            restoreInteractiveCorpusExportIfNeeded()
        }
        .onChange(of: syncService.connectionState) { _, newState in
            handleSyncConnectionStateChange(newState)
        }
        .task {
            #if DEBUG
            if MarketingCapture.isIAPReviewActive {
                vaultManager.setTestVault()
                selectedTab = .settings
                try? await Task.sleep(for: .milliseconds(900))
                showMarketingPaywall = true
                return
            }

            if MarketingCapture.isActive {
                vaultManager.setTestVault()
                try? await Task.sleep(for: .milliseconds(800))
                await runMarketingCapture()
                return
            }
            #endif
            if TestMode.isUITesting {
                // In test mode, set vault from environment if requested
                if TestMode.vaultSelected {
                    vaultManager.setTestVault()
                } else {
                    vaultManager.clearVaultFolder()
                }
                if TestMode.useHealthKitExportPreviewFixtures {
                    advancedSettings.exportFormats = [.markdown]
                    advancedSettings.includeGranularData = true
                    advancedSettings.metricSelection.selectAll()
                    advancedSettings.generateWeeklyRollups = true
                    advancedSettings.generateMonthlyRollups = true
                    advancedSettings.generateYearlyRollups = true
                }
                if TestMode.noExportFormats {
                    advancedSettings.exportFormats = []
                }
                advancedSettings.archiveExportFiles = TestMode.archiveExports
            }

            restoreInteractiveCorpusExportIfNeeded()
            await refreshDateRangeSelectionForOpening()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            restoreInteractiveCorpusExportIfNeeded()
            Task { await refreshDateRangeSelectionForOpening() }
        }
        .onChange(of: dateRangePreset) { _, _ in
            saveDateRangeSelection()
        }
        .onChange(of: startDate) { _, _ in
            saveDateRangeSelection()
        }
        .onChange(of: endDate) { _, _ in
            saveDateRangeSelection()
        }
        .healthMdReleaseNotesSheet()
        .onDisappear {
            statusDismissTimer?.invalidate()
            releaseQuickLookAccess()
            releaseMarkdownPreviewAccess()
            releaseExportFolderBrowserAccess()
        }
        } // else (main app)
    }

    // MARK: - Marketing Capture

    #if DEBUG
    @MainActor
    private func runMarketingCapture() async {
        // Enable features so sub-screens look populated
        advancedSettings.individualTracking.globalEnabled = true
        advancedSettings.dailyNoteInjection.enabled = true
        advancedSettings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        advancedSettings.includeGranularData = true
        advancedSettings.metricSelection.selectAll()
        advancedSettings.generateWeeklyRollups = true
        advancedSettings.generateMonthlyRollups = true
        advancedSettings.generateYearlyRollups = true
        exportTargetSelection = .localIPhoneFolder
        vaultManager.setTestVault()

        let steps: [CaptureStep] = [
            // Tab screens — capture clean state first
            CaptureStep(name: "01-export") {
                selectedTab = .export
            },
            CaptureStep(name: "05-export-formats", settle: .milliseconds(2000)) {
                selectedTab = .export
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(
                        name: MarketingCapture.scrollExportNotification,
                        object: MarketingCapture.exportHealthDataAnchor
                    )
                }
            },
            CaptureStep(name: "02-schedule") {
                selectedTab = .schedule
            },
            CaptureStep(name: "03-sync") {
                let capabilities = SyncPeerCapabilities.current(platform: .macOS)
                syncService.connectionState = .connected
                syncService.connectedPeerName = "Test Mac"
                syncService.remoteCapabilities = capabilities
                syncService.macDestinationStatus = MacDestinationStatus(
                    isConnected: true,
                    isReadyForExports: true,
                    destinationFolderSelected: true,
                    folderAccessHealthy: true,
                    destinationDisplayName: "Test Mac",
                    destinationPathForDisplay: "/Users/cody/Health",
                    lastError: nil,
                    activeJobID: nil,
                    capabilities: capabilities
                )
                selectedTab = .sync
            },
            CaptureStep(name: "04-settings") {
                selectedTab = .settings
            },

            // Metric Selection (standalone sheet)
            CaptureStep(name: "06-metric-selection", settle: .milliseconds(2000)) {
                showMarketingMetricSelection = true
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                showMarketingMetricSelection = false
            },

            // Format Customization (standalone sheet)
            CaptureStep(name: "07-format-customization", settle: .milliseconds(2000)) {
                showMarketingFormatCustomization = true
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                showMarketingFormatCustomization = false
            },

            // Individual Tracking (standalone sheet)
            CaptureStep(name: "08-individual-tracking", settle: .milliseconds(2000)) {
                showMarketingIndividualTracking = true
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                showMarketingIndividualTracking = false
            },

            // Export Preview (sheet backed by deterministic in-app fixtures)
            CaptureStep(name: "10-export-preview", settle: .milliseconds(5000)) {
                MarketingCapture.pendingAdvancedSubscreen = .exportPreview
                selectedTab = .export
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                MarketingCapture.pendingAdvancedSubscreen = nil
            },

            // Daily Note Injection (standalone sheet)
            CaptureStep(name: "09-daily-note-injection", settle: .milliseconds(2000)) {
                showMarketingDailyNoteInjection = true
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                showMarketingDailyNoteInjection = false
            },

            // Paywall (standalone marketing sheet)
            CaptureStep(name: "11-paywall", settle: .milliseconds(2000)) {
                showMarketingPaywall = true
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                showMarketingPaywall = false
            },

            // Onboarding (welcome step)
            CaptureStep(name: "12-onboarding", settle: .milliseconds(2200)) {
                showMarketingOnboarding = true
            } cleanup: {
                NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
                showMarketingOnboarding = false
            },
        ]

        await MarketingCaptureCoordinator.shared.run(steps: steps)
    }
    #endif

    // MARK: - Computed Properties

    private var canExport: Bool {
        ExportTargetReadiness.canExport(
            isHealthKitAuthorized: healthKitManager.isAuthorized,
            hasSelectedFormat: !advancedSettings.exportFormats.isEmpty,
            dailyNotesOnlyModeEnabled: advancedSettings.dailyNotesOnlyModeEnabled,
            target: exportTargetSelection,
            hasLocalFolder: vaultManager.vaultURL != nil || vaultManager.requiresVaultReselection,
            canExportToConnectedMac: canExportToConnectedMacWithCurrentSettings,
            apiEndpointConfigured: apiExportSettings.isConfigured
        )
    }

    private var canExportToConnectedMacWithCurrentSettings: Bool {
        syncService.canExportToConnectedMac(requiring: advancedSettings)
    }

    // MARK: - Date Range Persistence

    @MainActor
    private func refreshDateRangeSelectionForOpening() async {
        guard shouldPersistDateRangeSelection else { return }

        let selection = ExportDateRangeSelectionStore.shared.load()
        dateRangePreset = selection.preset
        startDate = selection.startDate
        endDate = selection.endDate

        guard selection.preset == .allTime,
              healthKitManager.isAuthorized,
              let earliestDate = await healthKitManager.findEarliestHealthDataDate() else {
            return
        }

        guard dateRangePreset == .allTime,
              let range = ExportDateRangePreset.allTime.resolvedRange(
                currentStartDate: startDate,
                currentEndDate: endDate,
                allTimeStartDate: earliestDate,
                allTimeEndDate: Date()
              ) else {
            return
        }

        startDate = range.startDate
        endDate = range.endDate
    }

    private func saveDateRangeSelection() {
        guard shouldPersistDateRangeSelection else { return }
        ExportDateRangeSelectionStore.shared.save(
            preset: dateRangePreset,
            startDate: startDate,
            endDate: endDate
        )
    }

    // MARK: - Status Helpers

    private func startStatusDismissTimer() {
        statusDismissTimer?.invalidate()
        let status = vaultManager.lastExportStatus ?? ""
        let hasExportActions = vaultManager.lastExportPresentationTarget != nil
            && (status.starts(with: "Exported") || status.starts(with: "Updated"))
        guard !hasExportActions else { return }

        statusDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            dismissStatus()
        }
    }

    private func withOptionalMotionAnimation(_ animation: Animation, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    private func dismissStatus() {
        partialExportNotice = nil
        vaultManager.lastExportStatus = nil
        vaultManager.clearLastExportPresentationTarget()
        statusDismissTimer?.invalidate()
    }

    private func presentExportPreview(_ target: ExportPresentationTarget) {
        statusDismissTimer?.invalidate()
        releaseQuickLookAccess()
        releaseMarkdownPreviewAccess()

        guard vaultManager.startAccessingExportPresentationTarget(target) else {
            presentExportPresentationError(
                "Health.md can’t access the exported file. Re-select the export folder and try again."
            )
            return
        }
        guard FileManager.default.fileExists(atPath: target.fileURL.path) else {
            vaultManager.stopAccessingExportPresentationTarget(target)
            presentExportPresentationError(
                "The exported file is no longer available at its original location."
            )
            return
        }

        switch ExportFilePreviewRoute.route(for: target.fileURL) {
        case .inAppMarkdown:
            markdownPreviewTarget = target
            markdownPreview = ExportedMarkdownPresentation(target: target)
        case .quickLook:
            quickLookTarget = target
            quickLookURL = target.fileURL
        }
    }

    private func browseExportFolder(_ target: ExportPresentationTarget) {
        statusDismissTimer?.invalidate()
        releaseExportFolderBrowserAccess()

        guard vaultManager.startAccessingExportPresentationTarget(target) else {
            presentExportPresentationError(
                "Health.md can’t access the export folder. Re-select it and try again."
            )
            return
        }
        guard FileManager.default.fileExists(atPath: target.folderURL.path) else {
            vaultManager.stopAccessingExportPresentationTarget(target)
            presentExportPresentationError(
                "The export folder is no longer available at its original location."
            )
            return
        }

        browsedFileURL = nil
        exportFolderBrowserTarget = target
        showExportFolderBrowser = true
    }

    private func finishBrowsingExportFolder() {
        releaseExportFolderBrowserAccess()
        guard let browsedFileURL else { return }
        self.browsedFileURL = nil

        let selectedTarget = ExportPresentationTarget(
            fileURL: browsedFileURL,
            securityScopedRootURL: browsedFileURL
        )
        DispatchQueue.main.async {
            presentExportPreview(selectedTarget)
        }
    }

    private func releaseQuickLookAccess() {
        guard let target = quickLookTarget else { return }
        vaultManager.stopAccessingExportPresentationTarget(target)
        quickLookTarget = nil
    }

    private func releaseMarkdownPreviewAccess() {
        guard let target = markdownPreviewTarget else { return }
        vaultManager.stopAccessingExportPresentationTarget(target)
        markdownPreviewTarget = nil
        markdownPreview = nil
    }

    private func releaseExportFolderBrowserAccess() {
        guard let target = exportFolderBrowserTarget else { return }
        vaultManager.stopAccessingExportPresentationTarget(target)
        exportFolderBrowserTarget = nil
    }

    private func presentExportPresentationError(_ message: String) {
        errorReason = nil
        errorMessage = message
        showError = true
    }

    private var currentPaywallContext: PricingAnalyticsPaywallContext {
        exportTargetSelection == .connectedMac ? .macTarget : .export
    }

    private var currentExportTargetType: PricingAnalyticsExportTargetType {
        switch exportTargetSelection {
        case .localIPhoneFolder:
            return .localFile
        case .connectedMac:
            return .connectedMac
        case .apiEndpoint:
            return .apiEndpoint
        }
    }

    private func presentExportPaywall() {
        PricingAnalyticsClient.shared.trackExportBlockedByQuota(
            context: currentPaywallContext,
            targetType: currentExportTargetType,
            quotaState: purchaseManager.analyticsQuotaState
        )
        showPaywall = true
    }

    private func trackSuccessfulExport(
        targetType: PricingAnalyticsExportTargetType,
        startDate: Date,
        endDate: Date
    ) {
        let metadata = PricingAnalyticsExportMetadata(
            targetType: targetType,
            formatCount: advancedSettings.exportFormats.count,
            metricCount: advancedSettings.metricSelection.totalEnabledCount,
            dateRangePreset: dateRangePreset,
            startDate: startDate,
            endDate: endDate
        )
        PricingAnalyticsClient.shared.trackExportSucceeded(
            metadata: metadata,
            quotaState: purchaseManager.analyticsQuotaState
        )
    }

    // MARK: - Auto-Sync

    private func autoSyncDates(_ dates: [Date]) async {
        var records: [HealthData] = []
        await HealthKitQueryExecutionController.withController {
            for date in dates {
                do {
                    let data = try await healthKitManager.fetchHealthData(for: date)
                    if data.hasAnyData {
                        records.append(data)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    let descriptor = HealthKitSafeLogging.failureDescriptor(
                        operation: "autoSyncFetch",
                        error: error as NSError
                    )
                    Self.logger.warning("Auto-sync HealthKit fetch failed: \(descriptor, privacy: .public)")
                }
            }
        }
        guard !records.isEmpty else { return }

        let payload = SyncPayload(
            deviceName: UIDevice.current.name,
            syncTimestamp: Date(),
            healthRecords: records
        )
        syncService.sendLargePayload(.healthData(payload))
    }

    // MARK: - Export

    private func cancelExport() {
        if let jobID = activeMacExportJobID,
           corpusRecoveryManager.journal(jobID: jobID) != nil {
            exportStatusMessage = "Cancelling durable Mac export…"
            Task {
                _ = await corpusRecoveryManager.cancel(jobID: jobID)
                guard activeMacExportJobID == jobID else { return }
                isExporting = false
                exportProgress = 0
                reconcileDurableExportExecutionAssertion()
                resetMacExportState()
            }
            return
        }
        if let jobID = activeMacExportJobID, macExportPayloadSent {
            syncService.send(.macExportCancel(jobID: jobID))
            exportTask?.cancel()
            exportStatusMessage = "Cancelling Mac export…"
            return
        }

        exportTask?.cancel()
    }

    private func exportData() {
        // Durable work outlives this view and even the app process. Repeated
        // taps should focus that immutable export, not create a competing job.
        if restoreInteractiveCorpusExportIfNeeded() { return }

        partialExportNotice = nil
        statusDismissTimer?.invalidate()
        vaultManager.clearLastExportPresentationTarget()

        // The primary export action stays available so an incomplete setup can
        // lead the user directly to its missing step instead of appearing broken.
        guard healthKitManager.isAuthorized else {
            requestHealthAuthorizationForExport()
            return
        }

        if advancedSettings.dailyNotesOnlyModeEnabled && exportTargetSelection == .apiEndpoint {
            presentExportConfigurationError("Daily Notes Only requires a Local Folder or Connected Mac destination. Turn it off to export to an API endpoint.")
            return
        }

        guard advancedSettings.hasFileDestinationOutput else {
            presentExportConfigurationError("Select at least one export format, or enable Daily Notes Only.")
            return
        }

        if exportTargetSelection == .localIPhoneFolder {
            vaultManager.refreshVaultAccess()
            if vaultManager.requiresVaultReselection {
                showDestinationChangedAlert = true
                return
            }
        }

        // Keep the established quota behavior once Health and output setup are
        // complete; target validation happens after access is available.
        guard purchaseManager.canExport else {
            presentExportPaywall()
            return
        }

        switch exportTargetSelection {
        case .localIPhoneFolder:
            guard vaultManager.vaultURL != nil else {
                exportStatusMessage = vaultManager.hasSavedVaultFolder
                    ? "Reconnect or re-select the export folder."
                    : "Choose a folder before exporting."
                showFolderPicker = true
                return
            }
        case .connectedMac:
            guard canExportToConnectedMacWithCurrentSettings else {
                presentExportConfigurationError(syncService.macExportReadinessMessage(requiring: advancedSettings))
                return
            }
        case .apiEndpoint:
            guard apiExportSettings.isConfigured else {
                presentExportConfigurationError("Configure a valid API endpoint before exporting.")
                return
            }
        }

        // In UI test mode, simulate export only after the same configuration
        // preflight checks that a release build performs.
        if TestMode.isUITesting {
            simulateTestExport()
            return
        }

        switch exportTargetSelection {
        case .localIPhoneFolder:
            exportLocalData()
        case .connectedMac:
            exportDataToConnectedMac()
        case .apiEndpoint:
            exportDataToAPIEndpoint()
        }
    }

    private func requestHealthAuthorizationForExport() {
        guard !isRequestingHealthAuthorization else { return }

        isRequestingHealthAuthorization = true
        exportStatusMessage = "Connect Apple Health to continue."

        Task {
            do {
                let outcome = try await healthKitManager.requestAuthorization()
                isRequestingHealthAuthorization = false

                guard outcome != .unavailable, healthKitManager.isAuthorized else {
                    presentExportConfigurationError("Apple Health data is not available on this device.")
                    return
                }

                // Continue the original action after the HealthKit sheet closes.
                exportData()
            } catch {
                isRequestingHealthAuthorization = false
                presentExportConfigurationError(
                    "Apple Health access could not be requested. Please try again or review Health permissions in the Health app."
                )
            }
        }
    }

    private func presentExportConfigurationError(_ message: String) {
        exportStatusMessage = message
        errorReason = nil
        errorMessage = message
        showError = true
    }

    private func presentExportFailure(
        _ reason: ExportFailureReason,
        detail: FailedDateDetail? = nil
    ) {
        errorReason = reason
        errorMessage = detail?.detailedMessage ?? reason.detailedDescription
        showError = true
    }

    private func exportLocalData() {
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""
        statusDismissTimer?.invalidate()

        exportTask = Task {
            defer {
                isExporting = false
                exportProgress = 0.0
                exportTask = nil
            }

            let dateRange = effectiveExportDateRange()
            startDate = dateRange.startDate
            endDate = dateRange.endDate
            let dates = ExportOrchestrator.dateRange(from: dateRange.startDate, to: dateRange.endDate)
            let externalIntegrations: ExternalIntegrationDailyRecordProviding? = ConnectedAppsFeature.isEnabled ? externalIntegrationManager : nil

            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: advancedSettings,
                externalIntegrations: externalIntegrations,
                onProgress: { current, total, dateStr in
                    exportStatusMessage = "Exporting \(dateStr)... (\(current)/\(total))"
                    exportProgress = Double(current) / Double(total)
                }
            )

            let normalizedStartDate = dates.first ?? dateRange.startDate
            let normalizedEndDate = dates.last ?? dateRange.endDate

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: normalizedStartDate,
                dateRangeEnd: normalizedEndDate
            )

            // Count this as one export action against the free quota.
            if result.successCount > 0 {
                purchaseManager.recordExportUse()
                trackSuccessfulExport(
                    targetType: .localFile,
                    startDate: normalizedStartDate,
                    endDate: normalizedEndDate
                )
            }

            if result.wasCancelled {
                if advancedSettings.dailyNotesOnlyModeEnabled {
                    exportStatusMessage = result.dailyNoteUpdateCount > 0
                        ? "Daily note update stopped — \(result.dailyNoteUpdateCount) of \(result.totalCount) notes updated"
                        : "Daily note update cancelled"
                    vaultManager.lastExportStatus = exportStatusMessage
                } else if result.successCount > 0 {
                    exportStatusMessage = String(localized: "Export stopped after exporting \(result.generatedFileCountDescription)", comment: "Export cancelled after writing a known lower bound or exact generated-file count")
                    vaultManager.lastExportStatus = exportStatusMessage
                } else {
                    exportStatusMessage = String(localized: "Export cancelled", comment: "Export was cancelled")
                    vaultManager.lastExportStatus = String(localized: "Export cancelled", comment: "Export was cancelled")
                }
                startStatusDismissTimer()
            } else if result.isFullSuccess {
                if advancedSettings.dailyNotesOnlyModeEnabled {
                    exportStatusMessage = "Updated \(result.dailyNoteUpdateCount) daily note\(result.dailyNoteUpdateCount == 1 ? "" : "s")"
                    vaultManager.lastExportStatus = exportStatusMessage
                } else if result.formatsPerDate > 1 || result.rollupFileCount > 0 || result.archiveCount > 0 {
                    exportStatusMessage = String(localized: "Successfully exported \(result.generatedFileCountDescription) (\(result.fileBreakdownDescription))", comment: "Multi-format export success message with an exact, lower-bound, or unknown generated-file count")
                    vaultManager.lastExportStatus = String(localized: "Exported \(result.generatedFileCountDescription)", comment: "Generated-file export status message")
                } else {
                    exportStatusMessage = String(localized: "Successfully exported \(result.generatedFileCountDescription)", comment: "Export success message with an exact, lower-bound, or unknown generated-file count")
                    vaultManager.lastExportStatus = String(localized: "Exported \(result.generatedFileCountDescription)", comment: "Generated-file export status message")
                }
                startStatusDismissTimer()

                if ReviewManager.shared.recordSuccessfulExport() {
                    ReviewManager.shared.didRequestReview()
                    requestReview()
                }
            } else if result.isPartialSuccess {
                let isCompletedDailyNoteSkip = advancedSettings.dailyNotesOnlyModeEnabled
                    && result.dailyNoteSkipCount > 0
                    && result.didCompleteAllRequestedDates
                if !isCompletedDailyNoteSkip {
                    partialExportNotice = PartialExportNotice(result: result)
                }
                let warning = result.hasPartialFailures ? result.partialFailureSummary : nil
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                let suffix = warning ?? "Failed: \(failedDatesStr)"
                if isCompletedDailyNoteSkip {
                    exportStatusMessage = "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) missing daily notes. No export files were created."
                    vaultManager.lastExportStatus = "Daily notes: \(result.dailyNoteUpdateCount) updated, \(result.dailyNoteSkipCount) skipped"
                    startStatusDismissTimer()
                } else if advancedSettings.dailyNotesOnlyModeEnabled {
                    exportStatusMessage = "Updated \(result.dailyNoteUpdateCount)/\(result.totalCount) daily notes. \(suffix)"
                    vaultManager.lastExportStatus = "Partial daily note update: \(result.dailyNoteUpdateCount)/\(result.totalCount)"
                } else if result.formatsPerDate > 1 || result.rollupFileCount > 0 || result.archiveCount > 0 {
                    exportStatusMessage = "Exported \(result.generatedFileCountDescription) (\(result.fileBreakdownDescription)). \(suffix)"
                    vaultManager.lastExportStatus = "Partial export: \(result.successCount)/\(result.totalCount) days succeeded (\(result.generatedFileCountDescription))"
                } else {
                    exportStatusMessage = "Exported \(result.generatedFileCountDescription). \(suffix)"
                    vaultManager.lastExportStatus = "Partial export: \(result.successCount)/\(result.totalCount) days succeeded (\(result.generatedFileCountDescription))"
                }
            } else {
                let primaryReason = result.primaryFailureReason ?? .unknown
                exportStatusMessage = advancedSettings.dailyNotesOnlyModeEnabled
                    ? "No daily notes were updated"
                    : "Export failed: \(primaryReason.shortDescription)"
                vaultManager.lastExportStatus = primaryReason.shortDescription
                presentExportFailure(
                    primaryReason,
                    detail: result.failedDateDetails.first
                )
            }
        }
    }

    private func exportDataToAPIEndpoint() {
        guard purchaseManager.canExport else {
            presentExportPaywall()
            return
        }
        guard let apiDestination = apiExportSettings.destinationSnapshot else {
            presentExportConfigurationError("Configure a valid API endpoint before exporting.")
            return
        }

        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = "Preparing API export…"
        statusDismissTimer?.invalidate()

        exportTask = Task {
            defer {
                isExporting = false
                exportProgress = 0.0
                exportTask = nil
            }

            let dateRange = effectiveExportDateRange()
            startDate = dateRange.startDate
            endDate = dateRange.endDate
            let dates = ExportOrchestrator.dateRange(from: dateRange.startDate, to: dateRange.endDate)
            let normalizedStartDate = dates.first ?? dateRange.startDate
            let normalizedEndDate = dates.last ?? dateRange.endDate
            let totalDays = dates.count
            let externalIntegrations: ExternalIntegrationDailyRecordProviding? = ConnectedAppsFeature.isEnabled ? externalIntegrationManager : nil

            // Large ranges are uploaded in bounded sequential batches by
            // APIEndpointExportRunner (see defaultMaxBatchDaySpan) so a long
            // history export can't build one oversized request. Progress is
            // still reported per date across the whole run, regardless of
            // how many batches that ends up being.
            let result = await APIEndpointExportRunner.export(
                dates: dates,
                healthKitManager: healthKitManager,
                settings: advancedSettings,
                destination: apiDestination,
                externalIntegrations: externalIntegrations,
                onProgress: { completed, total in
                    let clampedTotal = max(total, 1)
                    if completed < clampedTotal {
                        exportStatusMessage = "Preparing \(completed + 1)/\(clampedTotal) for API…"
                    } else {
                        exportStatusMessage = "Uploading to API…"
                    }
                    exportProgress = Double(completed) / Double(clampedTotal) * 0.85
                }
            )

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: normalizedStartDate,
                dateRangeEnd: normalizedEndDate,
                targetLabel: apiDestination.displayName,
                exportTarget: .apiEndpoint,
                fileCount: 0
            )

            if result.successCount > 0 {
                purchaseManager.recordExportUse()
                trackSuccessfulExport(
                    targetType: .apiEndpoint,
                    startDate: normalizedStartDate,
                    endDate: normalizedEndDate
                )
            }

            let providerRecordSentence: String?
            if result.externalRecordPayloadCount == 0 {
                providerRecordSentence = nil
            } else if result.externalRecordPayloadCount == 1 {
                providerRecordSentence = String(localized: "Included 1 provider record.", comment: "API export status with one provider payload record")
            } else {
                providerRecordSentence = String(localized: "Included \(result.externalRecordPayloadCount) provider records.", comment: "API export status with multiple provider payload records")
            }

            if result.wasCancelled {
                exportStatusMessage = result.successCount == 0
                    ? "API export cancelled"
                    : "API export stopped — uploaded \(result.successCount)/\(totalDays) days"
                vaultManager.lastExportStatus = exportStatusMessage
                startStatusDismissTimer()
            } else if result.isFullSuccess {
                let uploadedDaySentence = result.successCount == 1
                    ? String(localized: "Uploaded 1 data day to API.", comment: "Successful API export status for one data day")
                    : String(localized: "Uploaded \(result.successCount) data days to API.", comment: "Successful API export status for multiple data days")
                exportStatusMessage = [uploadedDaySentence, providerRecordSentence]
                    .compactMap { $0 }
                    .joined(separator: " ")
                vaultManager.lastExportStatus = "API export complete"
                startStatusDismissTimer()

                if ReviewManager.shared.recordSuccessfulExport() {
                    ReviewManager.shared.didRequestReview()
                    requestReview()
                }
            } else if result.isPartialSuccess {
                partialExportNotice = PartialExportNotice(result: result)
                let warning = result.hasPartialFailures ? result.partialFailureSummary : nil
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                let suffix = warning ?? "Failed: \(failedDatesStr)"
                let uploadedDaySentence = totalDays == 1
                    ? String(localized: "Uploaded \(result.successCount) of 1 data day to API.", comment: "Partial API export status when one data day was requested")
                    : String(localized: "Uploaded \(result.successCount) of \(totalDays) data days to API.", comment: "Partial API export status when multiple data days were requested")
                exportStatusMessage = [uploadedDaySentence, providerRecordSentence, suffix]
                    .compactMap { $0 }
                    .joined(separator: " ")
                vaultManager.lastExportStatus = "API partial export: \(result.successCount)/\(totalDays) days uploaded"
            } else {
                let primaryReason = result.primaryFailureReason ?? .unknown
                exportStatusMessage = "API export failed: \(primaryReason.shortDescription)"
                vaultManager.lastExportStatus = "API export failed"
                presentExportFailure(
                    primaryReason,
                    detail: result.failedDateDetails.first
                )
            }
        }
    }

    private func apiExportFailureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized, .dataNotAvailable, .medicationAuthorizationUnsupported,
             .visionAuthorizationUnsupported:
            return .healthKitError
        }
    }

    private func exportDataToConnectedMac() {
        guard purchaseManager.canExport else {
            presentExportPaywall()
            return
        }
        guard canExportToConnectedMacWithCurrentSettings else {
            presentExportConfigurationError(syncService.macExportReadinessMessage(requiring: advancedSettings))
            return
        }

        let jobID = UUID()
        activeMacExportJobID = jobID
        activeMacExportStartDate = nil
        activeMacExportEndDate = nil
        macExportPayloadSent = false
        macExportUsesResumableCorpus = false
        macExportWaitingForReconnect = false
        macExportQuotaRecorded = false
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = "Preparing Mac export…"
        syncService.isSyncing = true
        statusDismissTimer?.invalidate()

        exportTask = Task {
            externalIntegrationManager.beginExportAction()
            defer { externalIntegrationManager.endExportAction() }
            do {
                let destinationName = syncService.macDestinationStatus?.destinationDisplayName
                    ?? syncService.connectedPeerName
                    ?? "Mac"
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
                if ConnectedAppsFeature.isEnabled, externalIntegrationManager.connectedProviderCount > 0 {
                    externalRecordFetcher = { date in
                        await externalIntegrationManager.fetchDailyRecords(for: date)
                    }
                } else {
                    externalRecordFetcher = nil
                }

                if let remote = syncService.remoteCapabilities,
                   let negotiation = SyncPeerCapabilities.current(platform: .iOS)
                        .negotiateConnectedCorpusTransfer(with: remote) {
                    activeMacExportStartDate = startDate
                    activeMacExportEndDate = endDate
                    macExportUsesResumableCorpus = true
                    macExportPayloadSent = true
                    _ = try await IPhoneConnectedCorpusProducer.sendFileExport(
                        jobID: jobID,
                        startDate: startDate,
                        endDate: endDate,
                        settings: advancedSettings,
                        healthSubfolder: vaultManager.healthSubfolder,
                        destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                        negotiation: negotiation,
                        healthKitManager: healthKitManager,
                        externalRecordFetcher: externalRecordFetcher,
                        syncService: syncService,
                        progress: { update in
                            exportStatusMessage = update.message
                            exportProgress = update.presentationFraction(
                                previousFraction: exportProgress
                            )
                        }
                    )
                    guard activeMacExportJobID == jobID else { return }
                    exportStatusMessage = "Waiting for \(destinationName) to finish…"
                    exportProgress = max(exportProgress, 0.9)
                    exportTask = nil
                    return
                }

                if syncService.remoteCapabilities?.supportsSizeBoundedConnectedTransfers != true,
                   syncService.remoteCapabilities?.supportsChunkedMacExportJobs == true {
                    try await HealthKitQueryExecutionController.withController {
                        try await streamConnectedMacExport(
                            jobID: jobID,
                            destinationName: destinationName,
                            dateFormatter: dateFormatter,
                            externalRecordFetcher: externalRecordFetcher
                        )
                    }
                    return
                }

                let job = try await HealthKitQueryExecutionController.withController {
                    try await MacExportJobBuilder.build(
                    jobID: jobID,
                    sourceDeviceName: UIDevice.current.name,
                    startDate: startDate,
                    endDate: endDate,
                    settings: advancedSettings,
                    healthSubfolder: vaultManager.healthSubfolder,
                    destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                    fetchHealthData: { date, includeGranularData in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: advancedSettings.metricSelection
                        )
                    },
                    fetchExternalDailyRecords: externalRecordFetcher,
                    onProgress: { current, total, date in
                        exportStatusMessage = "Preparing \(dateFormatter.string(from: date)) for Mac… (\(current)/\(total))"
                        exportProgress = Double(current) / Double(max(total, 1)) * 0.35
                    }
                    )
                }

                guard activeMacExportJobID == jobID else { return }

                guard purchaseManager.canExport else {
                    presentExportPaywall()
                    finishMacExportPreparationStopped(
                        jobID: jobID,
                        message: "Export limit reached. Upgrade to export more."
                    )
                    return
                }

                guard canExportToConnectedMacWithCurrentSettings else {
                    finishMacExportPreparationFailed(
                        jobID: jobID,
                        message: syncService.macExportReadinessMessage(requiring: advancedSettings)
                    )
                    return
                }

                activeMacExportStartDate = job.dateRangeStart
                activeMacExportEndDate = job.dateRangeEnd
                exportStatusMessage = "Sending export to \(destinationName)…"
                exportProgress = max(exportProgress, 0.4)

                if syncService.remoteCapabilities?.supportsSizeBoundedConnectedTransfers == true {
                    let preparedFile = try ConnectedTransferFile.encode(job)
                    defer { preparedFile.remove() }
                    macExportPayloadSent = true
                    let result = await syncService.sendConnectedTransfer(
                        preparedFile,
                        manifest: ConnectedTransferManifest(
                            kind: .macExportJobV1,
                            jobID: jobID,
                            payloadSchemaVersion: 1
                        ),
                        onValidatedProgress: { accepted, total in
                            exportStatusMessage = "Streaming export to \(destinationName)… (\(accepted)/\(total))"
                            exportProgress = max(
                                exportProgress,
                                0.4 + Double(accepted) / Double(max(total, 1)) * 0.4
                            )
                        }
                    )
                    guard activeMacExportJobID == jobID else { return }
                    switch result {
                    case .success:
                        exportStatusMessage = "Waiting for \(destinationName) to finish…"
                        exportProgress = max(exportProgress, 0.85)
                        exportTask = nil
                    case .failure(let abort):
                        failStreamedMacExport(jobID: jobID, message: abort.message)
                    }
                    return
                }

                guard syncService.sendLargePayload(.macExportRequest(job)) else {
                    finishMacExportPreparationFailed(
                        jobID: jobID,
                        message: syncService.lastError ?? "Failed to send export payload to \(destinationName)."
                    )
                    return
                }
                macExportPayloadSent = true
                exportStatusMessage = "Waiting for \(destinationName) to start…"
                exportTask = nil
            } catch let error as IPhoneCorpusExportRecoveryManager.StartError {
                guard activeMacExportJobID == jobID else { return }
                if restoreInteractiveCorpusExportIfNeeded() { return }
                finishConflictingMacExportAttempt(
                    jobID: jobID,
                    message: error.localizedDescription
                )
            } catch let error as ConnectedCorpusDurableSender.DurableSenderError {
                if case .paused = error {
                    guard activeMacExportJobID == jobID else { return }
                    macExportWaitingForReconnect = true
                    exportStatusMessage = error.localizedDescription
                    exportTask = nil
                    reconcileDurableExportExecutionAssertion()
                    return
                }
                completeMacExport(with: MacExportFailure(
                    jobID: jobID,
                    reason: .payloadDecodeFailure,
                    message: error.localizedDescription
                ))
            } catch is CancellationError {
                if macExportPayloadSent {
                    _ = syncService.sendLargePayload(.macExportStreamAbort(MacExportStreamAbort(
                        jobID: jobID,
                        reason: .cancelled,
                        message: "Export cancelled"
                    )))
                    completeMacExport(with: MacExportFailure(
                        jobID: jobID,
                        reason: .cancelled,
                        message: "Export cancelled"
                    ))
                } else {
                    finishMacExportPreparationStopped(jobID: jobID, message: "Export cancelled")
                }
            } catch {
                guard activeMacExportJobID == jobID else { return }
                if macExportUsesResumableCorpus && macExportPayloadSent {
                    completeMacExport(with: MacExportFailure(
                        jobID: jobID,
                        reason: .payloadDecodeFailure,
                        message: "Mac export could not complete: \(error.localizedDescription)"
                    ))
                } else {
                    finishMacExportPreparationFailed(
                        jobID: jobID,
                        message: "Failed to prepare Mac export: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func streamConnectedMacExport(
        jobID: UUID,
        destinationName: String,
        dateFormatter: DateFormatter,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
    ) async throws {
        let metadata = await MacExportStreamingJobBuilder.metadataForNewOperation(
            startDate: startDate,
            endDate: endDate,
            settings: advancedSettings,
            healthSubfolder: vaultManager.healthSubfolder,
            destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
            enforceConnectedOperationGate: true,
            hasNativeOnlyCompanionAction: advancedSettings.writesExternalProviderSidecars
                && externalRecordFetcher != nil
        )
        let chunks = MacExportStreamingJobBuilder.chunks(for: metadata.transferDates)

        guard activeMacExportJobID == jobID else { return }

        guard purchaseManager.canExport else {
            presentExportPaywall()
            finishMacExportPreparationStopped(
                jobID: jobID,
                message: "Export limit reached. Upgrade to export more."
            )
            return
        }

        guard canExportToConnectedMacWithCurrentSettings else {
            finishMacExportPreparationFailed(
                jobID: jobID,
                message: syncService.macExportReadinessMessage(requiring: advancedSettings)
            )
            return
        }

        let streamStart = MacExportStreamStart(
            jobID: jobID,
            createdAt: Date(),
            sourceDeviceName: UIDevice.current.name,
            dateRangeStart: metadata.dateRangeStart,
            dateRangeEnd: metadata.dateRangeEnd,
            requestedDates: metadata.requestedDates,
            totalRequestedDays: metadata.totalRequestedDays,
            totalTransferDays: metadata.totalTransferDays,
            settingsSnapshot: metadata.settingsSnapshot,
            appleExportEnginePin: metadata.settingsSnapshot.appleExportEnginePin,
            requestedTarget: metadata.requestedTarget,
            chunkStrategyVersion: MacExportStreamingJobBuilder.chunkStrategyVersion
        )

        activeMacExportStartDate = metadata.dateRangeStart
        activeMacExportEndDate = metadata.dateRangeEnd
        exportStatusMessage = "Starting streamed export to \(destinationName)…"
        exportProgress = max(exportProgress, 0.35)

        let startAck = await syncService.sendMacExportStreamPayloadAndWaitForAck(
            .macExportStreamStart(streamStart),
            jobID: jobID,
            sequence: -1
        )
        guard activeMacExportJobID == jobID else { return }
        guard startAck?.accepted == true else {
            finishMacExportPreparationFailed(
                jobID: jobID,
                message: startAck?.message
                    ?? syncService.lastError
                    ?? "Timed out waiting for \(destinationName) to start the streamed export."
            )
            return
        }
        macExportPayloadSent = true

        var failedDateDetails: [FailedDateDetail] = []
        var processedTransferDays = 0

        for chunk in chunks {
            try Task.checkCancellation()
            guard activeMacExportJobID == jobID else { return }

            var records: [HealthData] = []
            var externalDailyRecords: [ExternalDailyRecord] = []

            for date in chunk.dates {
                try Task.checkCancellation()
                let day = Calendar.current.startOfDay(for: date)
                let shouldIncludeGranularData = MacExportStreamingJobBuilder.shouldIncludeGranularData(
                    for: date,
                    metadata: metadata,
                    settings: advancedSettings
                )
                let nextProcessed = processedTransferDays + 1
                exportStatusMessage = "Preparing \(dateFormatter.string(from: date)) for \(destinationName)… (\(processedTransferDays)/\(metadata.totalTransferDays))"
                exportProgress = 0.35 + (Double(processedTransferDays) / Double(max(metadata.totalTransferDays, 1)) * 0.45)

                do {
                    let fetchedRecord = try await healthKitManager.fetchHealthData(
                        for: date,
                        includeGranularData: shouldIncludeGranularData,
                        metricSelection: advancedSettings.metricSelection
                    )
                    let record = ConnectedExportGranularMode.sanitized(
                        fetchedRecord,
                        includesGranularData: shouldIncludeGranularData
                    )
                    records.append(record)

                    if record.hasAnyData,
                       metadata.requestedDays.contains(day),
                       advancedSettings.writesExternalProviderSidecars,
                       let externalRecordFetcher {
                        let providerRecords = await externalRecordFetcher(date)
                        externalDailyRecords.append(contentsOf: providerRecords.filter(\.shouldExport))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as HealthKitManager.HealthKitError {
                    failedDateDetails.append(FailedDateDetail(
                        date: date,
                        reason: apiExportFailureReason(for: error),
                        errorDetails: error.localizedDescription
                    ))
                } catch {
                    failedDateDetails.append(FailedDateDetail(
                        date: date,
                        reason: .healthKitError,
                        errorDetails: error.localizedDescription
                    ))
                }

                processedTransferDays = nextProcessed
                exportStatusMessage = "Prepared \(processedTransferDays) of \(metadata.totalTransferDays) days for \(destinationName)."
                exportProgress = 0.35 + (Double(processedTransferDays) / Double(max(metadata.totalTransferDays, 1)) * 0.45)
            }

            exportStatusMessage = "Sending prepared days to \(destinationName)…"
            let payload = MacExportStreamChunk(
                jobID: jobID,
                sequence: chunk.sequence,
                records: records,
                externalDailyRecords: externalDailyRecords,
                processedTransferDays: processedTransferDays,
                totalTransferDays: metadata.totalTransferDays
            )
            let chunkAck = await syncService.sendMacExportStreamPayloadAndWaitForAck(
                .macExportStreamChunk(payload),
                jobID: jobID,
                sequence: chunk.sequence
            )
            guard activeMacExportJobID == jobID else { return }
            guard chunkAck?.accepted == true else {
                failStreamedMacExport(
                    jobID: jobID,
                    message: chunkAck?.message
                        ?? syncService.lastError
                        ?? "Timed out waiting for \(destinationName) to accept stream chunk \(chunk.sequence)."
                )
                return
            }
        }

        guard activeMacExportJobID == jobID else { return }
        guard syncService.sendLargePayload(.macExportStreamComplete(MacExportStreamComplete(
            jobID: jobID,
            totalChunks: chunks.count,
            iphoneFailedDateDetails: failedDateDetails
        ))) else {
            failStreamedMacExport(
                jobID: jobID,
                message: syncService.lastError ?? "Failed to finish streamed export to \(destinationName)."
            )
            return
        }

        exportStatusMessage = "Waiting for \(destinationName) to finish…"
        exportProgress = max(exportProgress, 0.85)
        exportTask = nil
    }

    private func failStreamedMacExport(jobID: UUID, message: String) {
        guard activeMacExportJobID == jobID else { return }
        syncService.cancelMacExportStreamAckWaiters(jobID: jobID)
        _ = syncService.sendLargePayload(.macExportStreamAbort(MacExportStreamAbort(
            jobID: jobID,
            reason: .cancelled,
            message: message
        )))
        completeMacExport(with: MacExportFailure(
            jobID: jobID,
            reason: .payloadDecodeFailure,
            message: message
        ))
    }

    private func finishConflictingMacExportAttempt(jobID: UUID, message: String) {
        // StartError is raised before the attempted job can create a durable
        // checkpoint, even though the UI optimistically marked payloadSent.
        guard activeMacExportJobID == jobID else { return }
        exportStatusMessage = message
        vaultManager.lastExportStatus = message
        isExporting = false
        exportProgress = 0.0
        exportTask = nil
        // The incumbent durable job owns the process execution assertion.
        // Rejecting this new attempt must not release it.
        resetMacExportState()
        startStatusDismissTimer()
    }

    private func finishMacExportPreparationStopped(jobID: UUID, message: String) {
        guard activeMacExportJobID == jobID, !macExportPayloadSent else { return }
        exportStatusMessage = message
        vaultManager.lastExportStatus = message
        isExporting = false
        exportProgress = 0.0
        exportTask = nil
        syncService.isSyncing = false
        resetMacExportState()
        startStatusDismissTimer()
    }

    private func finishMacExportPreparationFailed(jobID: UUID, message: String) {
        guard activeMacExportJobID == jobID, !macExportPayloadSent else { return }
        exportStatusMessage = "Export failed: \(message)"
        vaultManager.lastExportStatus = message
        errorReason = nil
        errorMessage = message
        showError = true
        isExporting = false
        exportProgress = 0.0
        exportTask = nil
        syncService.isSyncing = false
        resetMacExportState()
    }

    private func handleSyncConnectionStateChange(_ newState: SyncConnectionState) {
        guard let jobID = activeMacExportJobID else { return }

        if macExportWaitingForReconnect {
            switch newState {
            case .connecting:
                syncService.isSyncing = true
                exportStatusMessage = "Reconnecting to Mac…"
                return
            case .connected:
                syncService.isSyncing = true
                macExportWaitingForReconnect = false
                exportStatusMessage = "Reconnected. Resuming Mac export…"
                return
            case .disconnected:
                break
            }
        }

        guard newState == .disconnected else { return }
        switch ConnectedMacExportLifecyclePolicy.disconnectDisposition(
            payloadSent: macExportPayloadSent,
            usesResumableCorpus: macExportUsesResumableCorpus,
            userInitiated: syncService.lastDisconnectWasUserInitiated
        ) {
        case .awaitReconnect:
            macExportWaitingForReconnect = true
            exportStatusMessage = "Connection interrupted. Waiting to reconnect and resume…"
            // SyncService releases its execution assertion as part of disconnect
            // cleanup. Restore it on the next actor turn so the foreground app
            // stays awake while the corpus producer waits for the same session.
            Task { @MainActor in
                guard activeMacExportJobID == jobID, macExportWaitingForReconnect else { return }
                syncService.isSyncing = true
            }
        case .cancel:
            exportTask?.cancel()
            if macExportPayloadSent {
                completeMacExport(with: MacExportFailure(
                    jobID: jobID,
                    reason: .cancelled,
                    message: "Mac export cancelled because the destination was disconnected."
                ))
            } else {
                finishMacExportPreparationStopped(
                    jobID: jobID,
                    message: "Mac export cancelled because the destination was disconnected."
                )
            }
        case .failAfterPayload:
            completeMacExport(with: MacExportFailure(
                jobID: jobID,
                reason: .payloadDecodeFailure,
                message: "Mac disconnected before export finished."
            ))
        case .failBeforePayload:
            exportTask?.cancel()
            finishMacExportPreparationFailed(
                jobID: jobID,
                message: "Mac disconnected before export could be sent."
            )
        }
    }

    private func reconcileDurableExportExecutionAssertion() {
        corpusRecoveryManager.reconcileExecutionAssertion(on: syncService)
    }

    @discardableResult
    private func restoreInteractiveCorpusExportIfNeeded() -> Bool {
        guard let snapshot = corpusRecoveryManager.activeSnapshot else { return false }
        switch snapshot.state {
        case .completed, .partialSuccess, .failed, .cancelled, .expired:
            return false
        case .preparing, .transferring, .paused, .finalizing:
            break
        }
        exportTask = nil
        handleCorpusRecoverySnapshot(snapshot)
        return true
    }

    private func handleCorpusRecoverySnapshot(_ snapshot: ConnectedCorpusProgressSnapshot?) {
        guard let snapshot else {
            guard macExportUsesResumableCorpus,
                  isExporting,
                  let jobID = activeMacExportJobID,
                  let journal = corpusRecoveryManager.journal(jobID: jobID),
                  journal.state.isTerminal else { return }
            finishCorpusRecoveryUI(
                succeeded: journal.state == .completed,
                message: journal.statusMessage ?? "Connected Mac export finished."
            )
            return
        }

        let terminalStates: [ConnectedCorpusJobState] = [
            .completed, .partialSuccess, .failed, .cancelled, .expired
        ]
        if terminalStates.contains(snapshot.state) {
            guard snapshot.jobID == activeMacExportJobID else { return }
            finishCorpusRecoveryUI(
                succeeded: snapshot.state == .completed || snapshot.state == .partialSuccess,
                message: snapshot.message ?? "Connected Mac export finished."
            )
            return
        }

        let previousFraction = activeMacExportJobID == snapshot.jobID ? exportProgress : 0
        activeMacExportJobID = snapshot.jobID
        let journal = corpusRecoveryManager.journal(jobID: snapshot.jobID)
        if let journal {
            activeMacExportStartDate = journal.exportManifest.dateRangeStart
            activeMacExportEndDate = journal.exportManifest.dateRangeEnd
        }
        // A persisted journal is the durable payload boundary, even before its
        // first partition commits. Disconnects must resume rather than fail it.
        macExportPayloadSent = true
        macExportUsesResumableCorpus = true
        macExportWaitingForReconnect = snapshot.state == .paused
            || syncService.connectionState != .connected
        isExporting = true
        exportProgress = IPhoneConnectedCorpusProgressUpdate.presentationFraction(
            preparedDays: journal?.nextItemIndex ?? 0,
            transferredDays: journal?.completedItemCount ?? 0,
            totalDays: journal?.totalItemCount ?? snapshot.totalDays,
            isFinalizing: snapshot.state == .finalizing,
            previousFraction: previousFraction
        )
        if syncService.connectionState != .connected {
            exportStatusMessage = "Export paused. Reconnect the same Mac to resume."
        } else {
            exportStatusMessage = snapshot.message
                ?? (snapshot.state == .paused
                    ? "Export paused. Reopen Health.md and reconnect the same Mac to resume."
                    : "Resuming durable Mac export…")
        }
        if syncService.connectionState == .connected,
           let journal,
           let remoteInstallationID = syncService.remoteCapabilities?.installationID,
           journal.isBound(
               sourceInstallationID: syncService.installationID,
               destinationInstallationID: remoteInstallationID
           ) {
            syncService.isSyncing = true
            syncService.reassertExecutionAssertionIfSyncing()
        }
    }

    private func finishCorpusRecoveryUI(succeeded: Bool, message: String) {
        isExporting = false
        exportTask = nil
        reconcileDurableExportExecutionAssertion()
        exportProgress = succeeded ? 1.0 : 0.0
        exportStatusMessage = message
        resetMacExportState()
        startStatusDismissTimer()
    }

    private func handleMacExportMessage(_ message: SyncMessage) {
        switch message {
        case .macExportAccepted(let acknowledgement):
            guard acknowledgement.jobID == activeMacExportJobID else { return }
            exportStatusMessage = acknowledgement.message ?? "Mac accepted export."
            exportProgress = max(exportProgress, 0.45)
        case .macExportProgress(let progress):
            guard progress.jobID == activeMacExportJobID else { return }
            exportStatusMessage = progress.message
            let phaseFraction = min(max(progress.fractionComplete, 0), 1)
            if macExportUsesResumableCorpus {
                // Durable capture/transfer owns 0...0.9. Mac-side writing uses
                // only the final band and must never regress that frontier.
                exportProgress = max(exportProgress, 0.9 + phaseFraction * 0.09)
            } else {
                exportProgress = max(exportProgress, max(0.45, phaseFraction))
            }
        case .macExportResult(let result):
            guard result.jobID == activeMacExportJobID else { return }
            completeMacExport(with: result)
        case .macExportFailed(let failure):
            guard failure.jobID == nil || failure.jobID == activeMacExportJobID else { return }
            completeMacExport(with: failure)
        default:
            break
        }
    }

    private func completeMacExport(with result: MacExportResultPayload) {
        if let validationFailure = ConnectedMacInteractiveResultValidator.failure(for: result) {
            completeMacExport(with: validationFailure)
            return
        }
        let durableJournal = corpusRecoveryManager.journal(jobID: result.jobID)
        let completionSettings = durableJournal?.exportManifest.settingsSnapshot
            .makeAdvancedExportSettings() ?? advancedSettings
        let normalizedStartDate = activeMacExportStartDate
            ?? durableJournal?.exportManifest.dateRangeStart
            ?? Calendar.current.startOfDay(for: startDate)
        let normalizedEndDate = activeMacExportEndDate
            ?? durableJournal?.exportManifest.dateRangeEnd
            ?? Calendar.current.startOfDay(for: endDate)
        let exportResult = ExportOrchestrator.ExportResult(macExportPayload: result)
        let destinationName = result.destinationDisplayName
            ?? syncService.macDestinationStatus?.destinationDisplayName
            ?? "Mac"

        let shouldRecordCompletion = durableJournal?.completionRecorded != true
        if shouldRecordCompletion {
            ExportOrchestrator.recordResult(
                exportResult,
                source: .macAgent,
                dateRangeStart: normalizedStartDate,
                dateRangeEnd: normalizedEndDate,
                targetLabel: destinationName
            )

            if result.successCount > 0, !macExportQuotaRecorded {
                purchaseManager.recordExportUse()
                macExportQuotaRecorded = true
                trackSuccessfulExport(
                    targetType: .connectedMac,
                    startDate: normalizedStartDate,
                    endDate: normalizedEndDate
                )
            }
        }

        vaultManager.clearLastExportPresentationTarget()
        exportProgress = 1.0
        isExporting = false
        exportTask = nil
        if durableJournal != nil {
            reconcileDurableExportExecutionAssertion()
        } else {
            syncService.isSyncing = false
        }

        switch result.status {
        case .success:
            if completionSettings.dailyNotesOnlyModeEnabled {
                exportStatusMessage = "Updated \(result.dailyNoteUpdateCount) daily note\(result.dailyNoteUpdateCount == 1 ? "" : "s") on \(destinationName)"
                vaultManager.lastExportStatus = exportStatusMessage
            } else if result.formatsPerDate > 1 || result.totalFilesWritten > 0 {
                exportStatusMessage = "Successfully exported \(exportResult.generatedFileCountDescription) to \(destinationName) (\(exportResult.fileBreakdownDescription))"
                vaultManager.lastExportStatus = "Exported \(exportResult.generatedFileCountDescription) to Mac"
            } else {
                exportStatusMessage = "Successfully exported \(exportResult.generatedFileCountDescription) to \(destinationName)"
                vaultManager.lastExportStatus = "Exported \(exportResult.generatedFileCountDescription) to Mac"
            }
            startStatusDismissTimer()

            if ReviewManager.shared.recordSuccessfulExport() {
                ReviewManager.shared.didRequestReview()
                requestReview()
            }
        case .partialSuccess:
            let isCompletedDailyNoteSkip = completionSettings.dailyNotesOnlyModeEnabled
                && result.dailyNoteSkipCount > 0
                && result.completedDates?.count == result.totalCount
            if !isCompletedDailyNoteSkip {
                partialExportNotice = PartialExportNotice(result: exportResult)
            }
            let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
            if isCompletedDailyNoteSkip {
                exportStatusMessage = "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) missing daily notes on \(destinationName). No export files were created."
                vaultManager.lastExportStatus = "Daily notes: \(result.dailyNoteUpdateCount) updated, \(result.dailyNoteSkipCount) skipped"
                startStatusDismissTimer()
            } else if completionSettings.dailyNotesOnlyModeEnabled {
                exportStatusMessage = "Updated \(result.dailyNoteUpdateCount)/\(result.totalCount) daily notes on \(destinationName). Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial daily note update: \(result.dailyNoteUpdateCount)/\(result.totalCount)"
            } else if result.formatsPerDate > 1 || result.totalFilesWritten > 0 {
                exportStatusMessage = "Exported \(exportResult.generatedFileCountDescription) to \(destinationName) (\(exportResult.fileBreakdownDescription)). Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial Mac export: \(result.successCount)/\(result.totalCount) days succeeded (\(exportResult.generatedFileCountDescription))"
            } else {
                exportStatusMessage = "Exported \(exportResult.generatedFileCountDescription) to \(destinationName). Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial Mac export: \(result.successCount)/\(result.totalCount) days succeeded (\(exportResult.generatedFileCountDescription))"
            }
        case .cancelled:
            if result.successCount > 0 {
                exportStatusMessage = "Mac export stopped after exporting \(exportResult.generatedFileCountDescription)"
                vaultManager.lastExportStatus = exportStatusMessage
            } else {
                exportStatusMessage = "Mac export cancelled"
                vaultManager.lastExportStatus = "Mac export cancelled"
            }
            startStatusDismissTimer()
        case .failure:
            let primaryReason = exportResult.primaryFailureReason ?? .unknown
            exportStatusMessage = completionSettings.dailyNotesOnlyModeEnabled
                ? "No daily notes were updated on \(destinationName)"
                : "Mac export failed: \(primaryReason.shortDescription)"
            vaultManager.lastExportStatus = primaryReason.shortDescription
            presentExportFailure(
                primaryReason,
                detail: result.failedDateDetails.first
            )
        }

        corpusRecoveryManager.markCompletionRecorded(jobID: result.jobID)
        resetMacExportState()
    }

    private func completeMacExport(with failure: MacExportFailure) {
        let hasDurableJournal = activeMacExportJobID
            .flatMap { corpusRecoveryManager.journal(jobID: $0) } != nil
        let normalizedStartDate = activeMacExportStartDate ?? Calendar.current.startOfDay(for: startDate)
        let normalizedEndDate = activeMacExportEndDate ?? Calendar.current.startOfDay(for: endDate)
        let totalCount = max(ExportOrchestrator.dateRange(from: normalizedStartDate, to: normalizedEndDate).count, 1)
        let reason = exportFailureReason(for: failure.reason)
        let failedDetail = FailedDateDetail(
            date: normalizedStartDate,
            reason: reason,
            errorDetails: failure.underlyingError ?? failure.message
        )
        let exportResult = ExportOrchestrator.ExportResult(
            macExportFailure: failure,
            totalCount: totalCount,
            formatsPerDate: advancedSettings.looseFormatsPerDate,
            failedDateDetails: [failedDetail]
        )

        ExportOrchestrator.recordResult(
            exportResult,
            source: .macAgent,
            dateRangeStart: normalizedStartDate,
            dateRangeEnd: normalizedEndDate,
            targetLabel: syncService.macDestinationStatus?.destinationDisplayName ?? syncService.connectedPeerName ?? "Mac"
        )

        isExporting = false
        exportProgress = 0.0
        exportTask = nil
        if hasDurableJournal {
            reconcileDurableExportExecutionAssertion()
        } else {
            syncService.isSyncing = false
        }
        vaultManager.clearLastExportPresentationTarget()

        if failure.reason == .cancelled {
            exportStatusMessage = "Mac export cancelled"
            vaultManager.lastExportStatus = "Mac export cancelled"
            startStatusDismissTimer()
        } else {
            exportStatusMessage = "Mac export failed: \(failure.message)"
            vaultManager.lastExportStatus = failure.message
            errorReason = reason
            errorMessage = failure.underlyingError.map { "\(failure.message)\n\nDetails: \($0)" } ?? failure.message
            showError = true
        }

        resetMacExportState()
    }

    private func exportFailureReason(for reason: MacExportFailureReason) -> ExportFailureReason {
        switch reason {
        case .noMacFolderSelected:
            return .noVaultSelected
        case .macFolderAccessDenied:
            return .accessDenied
        case .noHealthRecordsReceived:
            return .noHealthData
        case .exportWriteFailure:
            return .fileWriteError
        case .cancelled:
            return .unknown
        case .incompatibleProtocol, .noFormatsSelected, .payloadDecodeFailure, .macBusy:
            return .unknown
        }
    }

    private func resetMacExportState() {
        activeMacExportJobID = nil
        activeMacExportStartDate = nil
        activeMacExportEndDate = nil
        macExportPayloadSent = false
        macExportUsesResumableCorpus = false
        macExportWaitingForReconnect = false
        macExportQuotaRecorded = false
    }

    /// Simulate an export for UI tests without real HealthKit/vault.
    private func simulateTestExport() {
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""

        exportTask = Task {
            defer {
                isExporting = false
                exportProgress = 0.0
                exportTask = nil
            }

            // Brief delay to simulate progress
            exportStatusMessage = "Exporting 2026-03-28... (1/1)"
            exportProgress = 0.5
            try? await Task.sleep(for: .milliseconds(300))

            let result = TestMode.exportResult ?? "success"
            if result == "intermediate-success" {
                // Reproduce a per-file completion update during a multi-file export.
                vaultManager.lastExportStatus = "Exported 1 file"
                if let fileURL = createTestExportFile() {
                    vaultManager.recordExportPresentationTarget(
                        fileURL: fileURL,
                        securityScopedRootURL: nil
                    )
                }
                exportStatusMessage = "Exporting 2026-03-29... (2/2)"
                exportProgress = 0.5
                try? await Task.sleep(for: .seconds(3))
            }

            switch result {
            case "partial":
                let warning = ExportPartialFailure(
                    date: Date(timeIntervalSince1970: 1_774_656_000),
                    dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBiologicalSex",
                    dateRangeDescription: "2026-03-28",
                    errorDescription: "Authorization is not determined"
                )
                let exportResult = ExportOrchestrator.ExportResult(
                    successCount: 1,
                    totalCount: 1,
                    failedDateDetails: [],
                    partialFailures: [warning]
                )
                partialExportNotice = PartialExportNotice(result: exportResult)
                exportStatusMessage = "Exported 1 file with 1 warning"
                vaultManager.lastExportStatus = "Partial export: 1 warning"
                purchaseManager.recordExportUse()
            case "fail", "no-data":
                exportStatusMessage = "No matching health data"
                vaultManager.lastExportStatus = "No health data"
                presentExportFailure(.noHealthData)
            default:
                if advancedSettings.archiveModeEnabled {
                    exportStatusMessage = "Successfully exported 1 files (no loose daily files + 1 ZIP archive)"
                    vaultManager.lastExportStatus = "Exported ZIP archive"
                } else {
                    exportStatusMessage = "Successfully exported 1 files"
                    vaultManager.lastExportStatus = "Exported 1 files"
                }
                if let fileURL = createTestExportFile() {
                    vaultManager.recordExportPresentationTarget(
                        fileURL: fileURL,
                        securityScopedRootURL: nil
                    )
                }
                purchaseManager.recordExportUse()
                exportProgress = 1.0
                startStatusDismissTimer()
            }
        }
    }

    private func createTestExportFile() -> URL? {
        let folderURL = (vaultManager.vaultURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Health", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
            if advancedSettings.archiveModeEnabled {
                let fileURL = folderURL.appendingPathComponent("Health.md Export 2026-03-28.zip")
                try? FileManager.default.removeItem(at: fileURL)
                let writer = try ZipArchiveWriter.begin(to: fileURL)
                try writer.append(ZipArchiveWriter.Entry(
                    path: "README.txt",
                    data: Data("Health.md UI test export".utf8)
                ))
                try writer.finish()
                return fileURL
            }

            let fileURL = folderURL.appendingPathComponent("2026-03-28.md")
            let markdown = """
            ---
            schema_version: 7
            date: 2026-03-28
            ---

            # Health.md UI test export

            ## Activity

            - **Steps:** 12,500 steps
            - **Walking distance:** 8.4 km
            """
            try markdown.write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
            return fileURL
        } catch {
            return nil
        }
    }

    private func effectiveExportDateRange() -> (startDate: Date, endDate: Date) {
        (startDate, endDate)
    }
}

// MARK: - Discord Promo Banner

struct DiscordPromoBanner: View {
    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    bannerMessage
                    HStack(spacing: Spacing.sm) {
                        bannerJoinLink
                        bannerDismissButton
                    }
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    bannerMessage
                    Spacer(minLength: Spacing.sm)
                    bannerJoinLink
                    bannerDismissButton
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Join the Health.md Discord community.")
    }

    private var bannerMessage: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.accentSubtle)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Join the community")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Chat with us on Discord")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bannerJoinLink: some View {
        Link(destination: discordURL) {
            Text("Join")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentSubtle)
                )
        }
    }

    private var bannerDismissButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textMuted)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.bgSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Discord banner")
    }
}

// MARK: - Schedule Tab View

struct ScheduleTabView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject var apiExportSettings: APIExportSettings
    @Binding var showFolderPicker: Bool

    var body: some View {
        NavigationStack {
            ScheduleSettingsView(
                vaultManager: vaultManager,
                advancedSettings: advancedSettings,
                apiExportSettings: apiExportSettings,
                showFolderPicker: $showFolderPicker
            )
        }
    }
}

// MARK: - Settings Tab View

struct SettingsTabView: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject var externalIntegrationManager: ExternalIntegrationManager
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Binding var showFolderPicker: Bool
    @State private var showMailCompose = false
    @State private var showPaywall = false
    @State private var showExternalIntegrations = false
    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    private let privacyPolicyURL = URL(string: "https://healthmd.app/privacy-policy.html")!
    @State private var debugResult: String = ""
    @State private var showDebugAlert = false
    @State private var isRunningDebug = false

    private var unlockSubtitle: String {
        "Individual and Family Lifetime options"
    }

    private var purchaseSettingsIcon: String {
        if purchaseManager.isFamilyUnlocked {
            return "person.3.fill"
        }
        return purchaseManager.isUnlocked ? "checkmark.seal.fill" : "lock.fill"
    }

    private var purchaseSettingsTitle: String {
        purchaseManager.isUnlocked ? "Purchases & Family" : "Unlock Full Access"
    }

    private var purchaseSettingsSubtitle: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Lifetime active"
        }
        if purchaseManager.canBuyFamilyUpgrade {
            return "Full access active — family upgrade available"
        }
        if purchaseManager.isUnlocked {
            return "Full access active"
        }
        return unlockSubtitle
    }

    private var purchaseStatusLabel: String {
        purchaseManager.isUnlocked ? "Active" : "Limited"
    }

    private var purchaseStatusTone: SettingsStatusTone {
        purchaseManager.isUnlocked ? .success : .warning
    }

    private var vaultStatusLabel: String {
        vaultManager.vaultURL == nil ? "Not Set" : "Configured"
    }

    private var showDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                settingsHeader
                accountAndStorageSection
                privacyAndAnalyticsSection
                if ConnectedAppsFeature.isEnabled {
                    connectedAppsSection
                }
                supportSection
                debugToolsSection
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s4)
            .padding(.bottom, 120)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExternalIntegrations) {
            ExternalIntegrationsView(manager: externalIntegrationManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Receipt Verification", isPresented: $showDebugAlert) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(debugResult)
        }
    }

    private var settingsHeader: some View {
        HealthMdPageHeader(
            title: "Settings",
            subtitle: "Manage access, storage, and support for Health.md."
        ) {
            HStack(spacing: Spacing.sm) {
                SettingsStatusPill(text: purchaseManager.isUnlocked ? "Full Access" : "Free Plan", tone: purchaseStatusTone)
                SettingsStatusPill(text: vaultManager.vaultURL == nil ? "Vault Needed" : "Vault Set", tone: vaultManager.vaultURL == nil ? .warning : .success)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Purchase status: \(purchaseManager.isUnlocked ? "full access" : "free plan"). Vault status: \(vaultStatusLabel.lowercased()).")
        }
    }

    private var accountAndStorageSection: some View {
        SettingsSectionCard(
            title: "Account & Storage",
            subtitle: "Choose where exports go and manage your access."
        ) {
            SettingsRow(
                icon: purchaseSettingsIcon,
                title: purchaseSettingsTitle,
                subtitle: purchaseSettingsSubtitle,
                status: purchaseStatusLabel,
                statusTone: purchaseStatusTone,
                isActive: purchaseManager.isUnlocked,
                accessibilityHint: "Double tap to manage purchases and Family Sharing",
                action: { showPaywall = true }
            )

            SettingsRowDivider()

            SettingsRow(
                icon: "folder.fill",
                title: "Obsidian Vault",
                subtitle: vaultManager.isVaultConfigured ? vaultManager.vaultName : "Choose a folder for exports",
                status: vaultStatusLabel,
                statusTone: vaultManager.vaultURL == nil ? .warning : .success,
                isActive: vaultManager.vaultURL != nil,
                accessibilityHint: "Double tap to choose an Obsidian vault folder",
                action: { showFolderPicker = true }
            )
        }
    }

    private var privacyAndAnalyticsSection: some View {
        SettingsSectionCard(
            title: "Privacy & Analytics",
            subtitle: "Health.md collects limited product events using a random app-install identifier for setup, export-shape, and purchase-flow analytics."
        ) {
            SettingsRow(
                icon: "hand.raised.fill",
                title: "Privacy Policy",
                subtitle: "Analytics never includes health values, metric names, health dates, exported files, paths, peer names, or credentials. It is not used for advertising or cross-app tracking.",
                status: "View",
                statusTone: .accent,
                isActive: true,
                accessibilityHint: "Double tap to open the Health.md privacy policy",
                action: { UIApplication.shared.open(privacyPolicyURL) }
            )
        }
    }

    private var connectedAppsSection: some View {
        SettingsSectionCard(
            title: "Connected Apps",
            subtitle: "Add provider-native sidecar exports without replacing Apple Health."
        ) {
            SettingsRow(
                icon: "link.circle.fill",
                title: "Third-Party Integrations",
                subtitle: "Fitbit, Oura, WHOOP, Withings, and Strava",
                status: externalIntegrationManager.connectedProviderCount == 0 ? "None" : "\(externalIntegrationManager.connectedProviderCount)",
                statusTone: externalIntegrationManager.connectedProviderCount == 0 ? .muted : .success,
                isActive: externalIntegrationManager.connectedProviderCount > 0,
                accessibilityHint: "Double tap to connect or disconnect third-party health providers",
                action: { showExternalIntegrations = true }
            )
        }
    }

    private var supportSection: some View {
        SettingsSectionCard(
            title: "Community & Support",
            subtitle: "Get help, share ideas, or report a problem."
        ) {
            SettingsRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Join Our Discord",
                subtitle: "Chat with the community",
                status: "Open",
                statusTone: .accent,
                isActive: true,
                accessibilityHint: "Double tap to open Discord",
                action: { UIApplication.shared.open(discordURL) }
            )

            SettingsRowDivider()

            SettingsRow(
                icon: "envelope.fill",
                title: "Send Feedback",
                subtitle: "Questions, ideas, or issues",
                status: "Email",
                statusTone: .muted,
                isActive: true,
                accessibilityHint: "Double tap to send feedback by email",
                action: {
                    if FeedbackHelper.canSendMail {
                        showMailCompose = true
                    } else if let url = FeedbackHelper.mailtoURL() {
                        UIApplication.shared.open(url)
                    }
                }
            )

            SettingsRowDivider()

            SettingsRow(
                icon: "ladybug.fill",
                title: "Report a Bug",
                subtitle: "Open an issue on GitHub",
                status: "GitHub",
                statusTone: .muted,
                isActive: true,
                accessibilityHint: "Double tap to open GitHub Issues",
                action: { FeedbackHelper.openGitHubIssue() }
            )
        }
    }

    @ViewBuilder
    private var debugToolsSection: some View {
        if showDebugTools {
            SettingsSectionCard(
                title: "Developer Tools",
                subtitle: "Debug actions available in development builds."
            ) {
                SettingsRow(
                    icon: "checkmark.shield.fill",
                    title: isRunningDebug ? "Running…" : "Verify Receipt",
                    subtitle: "Test worker ↔ Apple end-to-end",
                    status: isRunningDebug ? "Running…" : "Run",
                    statusTone: .accent,
                    isActive: true,
                    accessibilityHint: "Double tap to verify the purchase receipt",
                    action: runReceiptVerification
                )

                SettingsRowDivider()

                SettingsRow(
                    icon: "arrow.counterclockwise",
                    title: "Replay Onboarding",
                    subtitle: "Show onboarding flow again",
                    status: "Replay",
                    statusTone: .muted,
                    isActive: true,
                    accessibilityHint: "Double tap to replay onboarding",
                    action: replayOnboarding
                )
            }
        }
    }

    private func runReceiptVerification() {
        guard !isRunningDebug else { return }
        isRunningDebug = true
        Task {
            let result = await PurchaseManager.shared.debugVerifyReceipt()
            await MainActor.run {
                debugResult = result
                isRunningDebug = false
                showDebugAlert = true
            }
        }
    }

    private func replayOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        debugResult = "Onboarding will replay now."
        showDebugAlert = true
    }
}

// MARK: - Settings Components

private struct SettingsSectionCard<Content: View>: View {
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
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
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

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.borderSubtle)
            .padding(.leading, 64)
    }
}

private enum SettingsStatusTone {
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

private struct SettingsStatusPill: View {
    let text: String
    let tone: SettingsStatusTone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone.background))
            .overlay(Capsule().strokeBorder(tone.border, lineWidth: 1))
    }
}

private struct SettingsRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let title: String
    let subtitle: String
    let status: String?
    let statusTone: SettingsStatusTone
    let isActive: Bool
    let accessibilityHint: String
    let action: () -> Void

    @State private var isPressed = false

    init(
        icon: String,
        title: String,
        subtitle: String,
        status: String? = nil,
        statusTone: SettingsStatusTone = .muted,
        isActive: Bool,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusTone = statusTone
        self.isActive = isActive
        self.accessibilityHint = accessibilityHint ?? "Double tap to open \(title)"
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(LocalizedStringKey(title))
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)

                    Text(LocalizedStringKey(subtitle))
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .layoutPriority(1)

                Spacer(minLength: Spacing.sm)

                if let status {
                    SettingsStatusPill(text: status, tone: statusTone)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed ? Color.bgSecondary : Color.clear)
            )
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.99 : 1.0))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(status ?? (isActive ? "Configured" : "Not configured"))
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeInOut(duration: 0.15), updates)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(SyncService())
        .environmentObject(SchedulingManager.shared)
        .environmentObject(ExternalIntegrationManager())
}
