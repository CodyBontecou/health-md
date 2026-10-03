import SwiftUI
import Combine
import UIKit
import os.log

// MARK: - iPad Root View (matching macOS NavigationSplitView layout)

struct iPadContentView: View {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "Export")

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
        @EnvironmentObject var configurationProtection: ConfigurationProtectionManager
    @StateObject private var vaultManager = VaultManager()

    @State private var selectedTab: iPadNavItem? = .export
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var dateRangePreset: ExportDateRangePreset = .today
    @State private var hasResolvedAllTimeRangeThisLaunch = false
    @State private var showFolderPicker = false
    @State private var showDestinationChangedAlert = false
    @State private var presentFirstExportPreview = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatusMessage = ""
    @State private var partialExportNotice: PartialExportNotice?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var errorReason: ExportFailureReason?
    @State private var exportTask: Task<Void, Never>?
    let historyProfileStore: ExportProfileStore?
    @State private var historyProfileID: UUID?
    @State private var executionHistoryAssessment: HealthHistoryAssessment?
    @State private var lastHistorySelection: HealthHistoryExecutionSelection?
    @State private var isAssessingHistory = false
    @State private var historyExecutionCoordinator = HealthHistoryAssessmentCoordinator()
    @State private var historyExecutionTask: Task<Void, Never>?
    @State private var pendingHistorySelection: HealthHistoryExecutionSelection?
    @State private var pendingHistoryRequestID: UUID?
    // Two tablet-root slots (preview/execution), each retaining at most one
    // physical SDK owner. This is NOT a global UI/query HealthKit budget.
    @State private var historyPreviewWorker = HealthHistoryAssessmentWorker()
    @State private var historyExecutionWorker = HealthHistoryAssessmentWorker()
    @State private var showPaywall = false
    @State private var showUpgradePromptPaywall = false
    @State private var presentPaywallAfterUpgradePrompt = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    init(historyProfileStore: ExportProfileStore? = nil) {
        self.historyProfileStore = historyProfileStore
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

    // MARK: - Interactive Export Lifecycle Marker

    /// The marker is launch state, so it follows the same UI-testing and
    /// marketing-capture guards as date-range persistence itself.
    private func markInteractiveExportBegan() {
        guard shouldPersistDateRangeSelection else { return }
        ExportDateRangeSelectionStore.shared.markInteractiveExportBegan()
    }

    private func markInteractiveExportEnded() {
        guard shouldPersistDateRangeSelection else { return }
        ExportDateRangeSelectionStore.shared.markInteractiveExportEnded()
    }

    var body: some View {
        if !hasCompletedOnboarding && (!TestMode.isUITesting || TestMode.showsOnboarding) {
            OnboardingView(
                showFolderPicker: $showFolderPicker,
                vaultManager: vaultManager,
                onComplete: {
                    HealthMdReleaseNotes.markCurrentVersionAsSeenAfterOnboarding()
                    withAnimation(AnimationTimings.smooth) {
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
            NavigationSplitView(columnVisibility: $columnVisibility) {
                iPadSidebar(selectedTab: $selectedTab)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                    .iPadPageBackground()
            } detail: {
                Group {
                    switch selectedTab {
                    case .sync:
                        iPadSyncView()
                    case .export:
                        iPadExportView(
                            healthKitManager: healthKitManager,
                            vaultManager: vaultManager,
                            advancedSettings: advancedSettings,
                            startDate: $startDate,
                            endDate: $endDate,
                            dateRangePreset: $dateRangePreset,
                            isExporting: $isExporting,
                            exportProgress: $exportProgress,
                            exportStatusMessage: $exportStatusMessage,
                            showFolderPicker: $showFolderPicker,
                            presentFirstExportPreview: $presentFirstExportPreview,
                            canExport: canExport && !isAssessingHistory,
                            onCancelExport: cancelExport,
                            onExportTapped: exportData,
                            historyProfileID: historyProfileID,
                            executionHistoryAssessment: executionHistoryAssessment,
                            isAssessingHistory: isAssessingHistory,
                            historyPreviewWorker: historyPreviewWorker,
                            onContinueWithoutHistoryVerification: continueWithoutHistoryVerification,
                            onCancelHistoryVerification: invalidateExecutionHistory
                        )
                    case .schedule:
                        iPadScheduleView(
                            vaultManager: vaultManager,
                            advancedSettings: advancedSettings,
                            showFolderPicker: $showFolderPicker
                        )
                        .environmentObject(schedulingManager)
                        .environmentObject(healthKitManager)
                    case .history:
                        iPadHistoryView()
                    case .settings:
                        iPadSettingsView(
                            vaultManager: vaultManager,
                            advancedSettings: advancedSettings,
                            healthKitManager: healthKitManager,
                            showFolderPicker: $showFolderPicker
                        )
                    case .none:
                        brandPlaceholder
                    }
                }
                .iPadPageBackground()
                .environment(\.healthMdSidebarToggle, HealthMdSidebarToggle(
                    isSidebarVisible: columnVisibility != .detailOnly,
                    toggle: toggleSidebar
                ))
            }
            .tint(.accent)
            .overlay(alignment: .bottom) {
                PartialExportNoticeToast(
                    notice: $partialExportNotice,
                    bottomPadding: Spacing.lg,
                    onDismiss: {},
                    requestHealthAuthorization: {
                        try await healthKitManager.requestAuthorization()
                    }
                )
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    configurationProtection.performConfigurationChange {
                        vaultManager.setVaultFolder(url)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(context: .export)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(
                isPresented: Binding(
                    get: { purchaseManager.pendingUpgradePrompt != nil },
                    set: { presented in
                        if !presented { handleUpgradePromptSwipeDismissIfNeeded() }
                    }
                ),
                onDismiss: {
                    if presentPaywallAfterUpgradePrompt {
                        presentPaywallAfterUpgradePrompt = false
                        showUpgradePromptPaywall = true
                    }
                }
            ) {
                ExportUpgradePrompt(
                    milestone: purchaseManager.pendingUpgradePrompt ?? 0,
                    onUpgrade: {
                        let quotaState = purchaseManager.analyticsQuotaState
                        purchaseManager.consumeUpgradePrompt()
                        PricingAnalyticsClient.shared.trackUpgradePromptTapped(quotaState: quotaState)
                        presentPaywallAfterUpgradePrompt = true
                    },
                    onDismiss: {
                        let quotaState = purchaseManager.analyticsQuotaState
                        purchaseManager.consumeUpgradePrompt()
                        PricingAnalyticsClient.shared.trackUpgradePromptDismissed(quotaState: quotaState)
                    }
                )
            }
            .sheet(isPresented: $showUpgradePromptPaywall) {
                PaywallView(context: .upgradePrompt)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .geistDialog(
                isPresented: $showDestinationChangedAlert,
                title: Text("Export Folder Changed"),
                message: Text("The saved folder now points to a different location. Health.md paused local exports so it won’t write somewhere you did not select. Review any duplicate or conflict in Files, then re-select the intended folder."),
                actions: [
                    .cancel(),
                    .action("Choose Folder") { showFolderPicker = true }
                ]
            )
            .geistDialog(
                isPresented: $showError,
                title: Text(errorReason?.alertTitle ?? ExportFailureReason.unknown.alertTitle),
                message: Text(errorMessage),
                actions: errorReason == .noHealthData
                    ? [
                        .action("Done", role: .secondary),
                        .action("Open Health App") {
                            if let healthURL = URL(string: "x-apple-health://") {
                                UIApplication.shared.open(healthURL)
                            }
                        }
                    ]
                    : [.action("OK", role: .secondary)]
            )
            .geistDialog(
                isPresented: Binding(
                    get: {
                        guard let result = schedulingManager.notificationExportResult else { return false }
                        return !NotificationExportActivityTracker.shared.handles(result)
                    },
                    set: { if !$0 { schedulingManager.notificationExportResult = nil } }
                ),
                title: Text(schedulingManager.notificationExportResult?.title ?? "Export"),
                message: schedulingManager.notificationExportResult.map { Text($0.message) },
                actions: [
                    .action("OK", role: .secondary) {
                        schedulingManager.notificationExportResult = nil
                    }
                ]
            )
            .healthMdReleaseNotesSheet()
            .keepsScreenAwake(while: isExporting)
            .task {
                refreshHistoryProfileIdentity()
                if TestMode.isUITesting {
                    if TestMode.vaultSelected {
                        vaultManager.setTestVault()
                    } else {
                        vaultManager.clearVaultFolder()
                    }
                    if TestMode.useHealthKitExportPreviewFixtures {
                        advancedSettings.exportFormats = [.markdown]
                        advancedSettings.detailPolicy = .lossless
                        advancedSettings.metricSelection.selectAll()
                        advancedSettings.generateWeeklyRollups = true
                        advancedSettings.generateMonthlyRollups = true
                        advancedSettings.generateYearlyRollups = true
                    }
                }
                await refreshDateRangeSelectionForOpening(isInitialLaunch: true)
            }
            .onChange(of: vaultManager.vaultURL) { _, _ in invalidateExecutionHistory() }
            .onChange(of: selectedTab) { _, _ in invalidateExecutionHistory() }
            .onChange(of: interactiveHistorySelection) { _, current in invalidateIfHistorySelectionChanged(current) }
            .onChange(of: healthKitManager.isAuthorized) { _, _ in invalidateExecutionHistory() }
            .onReceive(historyProfileStore?.$activeProfileID.eraseToAnyPublisher() ?? Just<UUID?>(nil).eraseToAnyPublisher()) { _ in
                refreshHistoryProfileIdentity()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                // Other canonical-store instances do not publish through our
                // store. Filter by fresh valid identity, not unrelated writes.
                refreshHistoryProfileIdentity()
            }
            .onDisappear { invalidateExecutionHistory(); historyPreviewWorker.cancelLogicalWaiter() }
            .onChange(of: scenePhase) { _, newPhase in
                invalidateExecutionHistory()
                historyPreviewWorker.cancelLogicalWaiter()
                guard newPhase == .active else { return }
                vaultManager.refreshVaultAccess()
                refreshHistoryProfileIdentity()
                Task { await refreshDateRangeSelectionForOpening() }
            }
            .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
                if requestID != nil { selectedTab = .settings }
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
        }
    }

    private func toggleSidebar() {
        withAnimation(AnimationTimings.smooth) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    // MARK: - Placeholder

    private var brandPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(Typography.heading24())
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            Text("health.md")
                .font(Typography.heading20())
                .foregroundStyle(Color.textPrimary)
                .tracking(-0.4)
            Text("Select a section from the sidebar")
                .font(Typography.body())
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Computed Properties

    private var canExport: Bool {
        healthKitManager.isAuthorized
            && vaultManager.hasVaultSelection
            && advancedSettings.hasFileDestinationOutput
    }

    // MARK: - Date Range Persistence

    @MainActor
    private func refreshDateRangeSelectionForOpening(isInitialLaunch: Bool = false) async {
        guard shouldPersistDateRangeSelection else { return }

        let store = ExportDateRangeSelectionStore.shared
        // A leftover in-flight marker means the previous run ended without a
        // terminal export path (crash, kill, force quit). Consume it once per
        // launch; a fresh process cannot have an export in flight yet.
        let hadInterruptedInteractiveExport = isInitialLaunch
            && store.consumeInterruptedInteractiveExportMarker()
        let persisted = store.load()
        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: hadInterruptedInteractiveExport,
            resolvesAllTimeRange: isInitialLaunch
        )

        dateRangePreset = selection.preset
        startDate = selection.startDate
        endDate = selection.endDate

        // All Time always extends through the present; a warm foreground
        // activation across midnight must not restore a stale end date that
        // would silently truncate the export range.
        if let refreshed = ExportDateRangeLaunchPolicy.selectionWithAllTimeEndDateRefreshed(
            selection
        ) {
            endDate = refreshed.endDate
        }

        guard isInitialLaunch,
              !hasResolvedAllTimeRangeThisLaunch,
              selection.preset == .allTime,
              healthKitManager.isAuthorized else {
            return
        }

        hasResolvedAllTimeRangeThisLaunch = true

        guard let earliestDate = await healthKitManager.findEarliestHealthDataDate() else {
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

    private func presentExportPaywall() {
        PricingAnalyticsClient.shared.trackExportBlockedByQuota(
            context: .export,
            targetType: .localFile,
            quotaState: purchaseManager.analyticsQuotaState
        )
        showPaywall = true
    }

    /// Swipe-to-dismiss on the value-moment prompt bypasses the button
    /// actions, so the binding's `set(false)` finishes the funnel. Button
    /// paths have already consumed the milestone by then, making this a no-op.
    private func handleUpgradePromptSwipeDismissIfNeeded() {
        guard purchaseManager.pendingUpgradePrompt != nil else { return }
        let quotaState = purchaseManager.analyticsQuotaState
        purchaseManager.consumeUpgradePrompt()
        PricingAnalyticsClient.shared.trackUpgradePromptDismissed(quotaState: quotaState)
    }

    private func trackSuccessfulExport(startDate: Date, endDate: Date) {
        let metadata = PricingAnalyticsExportMetadata(
            targetType: .localFile,
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
        invalidateExecutionHistory()
        exportTask?.cancel()
    }

    private var interactiveHistorySelection: HealthHistoryExecutionSelection {
        // Body/onChange evaluation uses cached presentation state only.
        makeHistorySelection(profileID: historyProfileID)
    }

    private func freshInteractiveHistorySelection() -> HealthHistoryExecutionSelection {
        makeHistorySelection(profileID: HealthHistoryCanonicalProfileIdentity.read())
    }

    private func refreshHistoryProfileIdentity() {
        let current = HealthHistoryCanonicalProfileIdentity.read()
        guard current != historyProfileID else { return }
        historyProfileID = current
        invalidateIfHistorySelectionChanged(makeHistorySelection(profileID: current))
    }

    private func invalidateIfHistorySelectionChanged(_ current: HealthHistoryExecutionSelection) {
        if let pending = pendingHistorySelection, pending != current { invalidateExecutionHistory() }
        else if let captured = lastHistorySelection, captured != current { invalidateExecutionHistory() }
    }

    private func makeHistorySelection(profileID: UUID?) -> HealthHistoryExecutionSelection {
        let scope = HealthHistoryScope(metricIDs: advancedSettings.metricSelection.enabledMetrics,
            startDate: startDate, endDate: endDate,
            timeZoneIdentifier: (advancedSettings.exportTimeZoneOverride ?? .current).identifier,
            allAvailable: dateRangePreset == .allTime,
            profileID: profileID, rangeSemantics: .ownerDates)
        return HealthHistoryExecutionSelection(scope: scope,
            settings: ExportSettingsSnapshot.from(advancedSettings, appleExportEngineAuthorityIsFrozen: false),
            target: .localIPhoneFolder, preset: dateRangePreset, localDestinationURL: vaultManager.vaultURL)
    }

    private func clearPendingHistoryCheck() {
        pendingHistorySelection = nil
        pendingHistoryRequestID = nil
        isAssessingHistory = false
        historyExecutionTask = nil
    }

    private func invalidateExecutionHistory() {
        historyExecutionCoordinator.invalidate()
        historyExecutionWorker.cancelLogicalWaiter()
        historyExecutionTask?.cancel()
        executionHistoryAssessment = nil
        lastHistorySelection = nil
        if isAssessingHistory { exportStatusMessage = "History check cancelled. Review the selection and export again." }
        clearPendingHistoryCheck()
    }

    private func continueWithoutHistoryVerification() {
        guard let selection = pendingHistorySelection, selection == freshInteractiveHistorySelection() else {
            invalidateExecutionHistory(); return
        }
        historyExecutionCoordinator.invalidate()
        historyExecutionWorker.cancelLogicalWaiter()
        historyExecutionTask?.cancel()
        clearPendingHistoryCheck()
        executionHistoryAssessment = healthKitManager.historyAssessmentNotCompleted(scope: selection.scope)
        beginInteractiveCapture(selection)
    }

    private func beginInteractiveCapture(_ selection: HealthHistoryExecutionSelection) {
        guard selection == freshInteractiveHistorySelection(), canExport,
              scenePhase == .active, selectedTab == .export else { return }
        guard purchaseManager.canExport else { presentExportPaywall(); return }
        vaultManager.refreshVaultAccess()
        guard vaultManager.vaultURL == selection.localDestinationURL,
              vaultManager.vaultURL != nil, !vaultManager.requiresVaultReselection else {
            configurationProtection.performConfigurationChange { showDestinationChangedAlert = true }
            return
        }
        lastHistorySelection = selection
        captureExportData(selection)
    }

    private func presentExportFailure(
        _ reason: ExportFailureReason,
        detail: FailedDateDetail? = nil
    ) {
        errorReason = reason
        errorMessage = detail?.detailedMessage ?? reason.detailedDescription
        showError = true
    }

    private func exportData() {
        guard !isAssessingHistory, !isExporting else { return }
        vaultManager.refreshVaultAccess()
        if vaultManager.requiresVaultReselection {
            configurationProtection.performConfigurationChange {
                showDestinationChangedAlert = true
            }
            return
        }
        guard vaultManager.vaultURL != nil else {
            configurationProtection.performConfigurationChange {
                showFolderPicker = true
            }
            return
        }

        guard purchaseManager.canExport else {
            presentExportPaywall()
            return
        }

        if TestMode.isUITesting,
           let result = TestMode.exportResult,
           ["fail", "no-data"].contains(result) {
            exportStatusMessage = "No matching health data"
            vaultManager.lastExportStatus = "No health data"
            presentExportFailure(.noHealthData)
            return
        }

        refreshHistoryProfileIdentity()
        let selection = freshInteractiveHistorySelection()
        let requestID = historyExecutionCoordinator.beginRequest()
        pendingHistorySelection = selection
        pendingHistoryRequestID = requestID
        isAssessingHistory = true
        exportStatusMessage = "Checking history access…"
        historyExecutionTask = Task {
            defer { if pendingHistoryRequestID == requestID { clearPendingHistoryCheck() } }
            let result = await historyExecutionCoordinator.assess(requestID: requestID, scope: selection.scope, isCurrent: {
                selection == freshInteractiveHistorySelection() && scenePhase == .active
            }, operation: {
                await historyExecutionWorker.assess(notCompleted: healthKitManager.historyAssessmentNotCompleted(scope: selection.scope)) {
                    await healthKitManager.assessHistoryAccess(scope: selection.scope)
                }
            })
            guard pendingHistoryRequestID == requestID, let assessment = result else { return }
            clearPendingHistoryCheck()
            executionHistoryAssessment = assessment
            beginInteractiveCapture(selection)
        }
    }

    private func captureExportData(_ selection: HealthHistoryExecutionSelection) {
        let advancedSettings = selection.makeCaptureSettings()
        // Set synchronously before any export work starts so a crash, kill, or
        // force quit mid-export arms the interrupted marker for the next
        // launch's downgrade. Cleared in the defer below on every terminal
        // path (success, failure, cancellation).
        markInteractiveExportBegan()
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""
        partialExportNotice = nil

        exportTask = Task {
            defer {
                markInteractiveExportEnded()
                isExporting = false
                exportProgress = 0.0
                exportTask = nil
            }

            let dateRange = (startDate: selection.scope.startDate, endDate: selection.scope.endDate)
            let frozenTimeZone = TimeZone(identifier: selection.scope.timeZoneIdentifier) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = frozenTimeZone
            let dates = ExportOrchestrator.dateRange(
                from: dateRange.startDate,
                to: dateRange.endDate,
                calendar: calendar
            )

            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: advancedSettings,
                captureCalendar: calendar,
                onProgress: { current, total, dateStr in
                    exportStatusMessage = "Exporting \(dateStr)… (\(current)/\(total))"
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
                    startDate: normalizedStartDate,
                    endDate: normalizedEndDate
                )
            }

            if result.successCount > 0,
               syncService.connectionState == .connected,
               UserDefaults.standard.bool(forKey: "syncEnabled"),
               UserDefaults.standard.bool(forKey: "autoSyncAfterExport") {
                await autoSyncDates(dates)
            }

            if result.wasCancelled {
                if advancedSettings.dailyNotesOnlyModeEnabled {
                    exportStatusMessage = result.dailyNoteUpdateCount > 0
                        ? "Daily note update stopped — \(result.dailyNoteUpdateCount) of \(result.totalCount) notes updated"
                        : "Daily note update cancelled"
                } else if result.isPartialSuccess {
                    exportStatusMessage = "\(String(localized: "Export cancelled")) · \(result.localizedGeneratedFileAndDataDayDescription)"
                } else {
                    exportStatusMessage = String(localized: "Export cancelled", comment: "Export was cancelled")
                }
            } else if result.isFullSuccess {
                let noteSuffix = result.localizedInformationalNoteSummary.map { " \($0)" } ?? ""
                exportStatusMessage = advancedSettings.dailyNotesOnlyModeEnabled
                    ? "Updated \(result.dailyNoteUpdateCount) daily note\(result.dailyNoteUpdateCount == 1 ? "" : "s")"
                    : result.localizedGeneratedFileAndDataDayDescription + noteSuffix
            } else if result.isPartialSuccess {
                let isCompletedDailyNoteSkip = advancedSettings.dailyNotesOnlyModeEnabled
                    && result.dailyNoteSkipCount > 0
                    && result.didCompleteAllRequestedDates
                if !isCompletedDailyNoteSkip {
                    partialExportNotice = PartialExportNotice(result: result)
                }
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                let suffix = result.hasDegradingPartialFailures ? result.partialFailureSummary : "Failed: \(failedDatesStr)"
                if isCompletedDailyNoteSkip {
                    exportStatusMessage = "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) missing daily notes. No export files were created."
                } else {
                    exportStatusMessage = advancedSettings.dailyNotesOnlyModeEnabled
                        ? "Updated \(result.dailyNoteUpdateCount)/\(result.totalCount) daily notes. \(suffix)"
                        : "\(result.localizedGeneratedFileAndDataDayDescription). \(suffix)"
                }
            } else {
                let primaryReason = result.primaryFailureReason ?? .unknown
                exportStatusMessage = advancedSettings.dailyNotesOnlyModeEnabled
                    ? "No daily notes were updated"
                    : String(localized: "Export failed: \(primaryReason.shortDescription)", comment: "Export failure message")

                presentExportFailure(
                    primaryReason,
                    detail: result.failedDateDetails.first
                )
            }
        }
    }

    private func effectiveExportDateRange() -> (startDate: Date, endDate: Date) {
        (startDate, endDate)
    }
}
