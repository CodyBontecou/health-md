import SwiftUI
import UIKit
import os.log

// MARK: - iPad Root View (matching macOS NavigationSplitView layout)

struct iPadContentView: View {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "Export")

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var schedulingManager: SchedulingManager
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()

    @State private var selectedTab: iPadNavItem? = .export
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var dateRangePreset: ExportDateRangePreset = .today
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
    @State private var showPaywall = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
                            canExport: canExport,
                            onCancelExport: cancelExport,
                            onExportTapped: exportData
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
                    vaultManager.setVaultFolder(url)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(context: .export)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
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
            .healthMdReleaseNotesSheet()
            .keepsScreenAwake(while: isExporting)
            .task {
                if TestMode.isUITesting {
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
                }
                await refreshDateRangeSelectionForOpening()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
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
            && (vaultManager.vaultURL != nil || vaultManager.requiresVaultReselection)
            && advancedSettings.hasFileDestinationOutput
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

    private func presentExportPaywall() {
        PricingAnalyticsClient.shared.trackExportBlockedByQuota(
            context: .export,
            targetType: .localFile,
            quotaState: purchaseManager.analyticsQuotaState
        )
        showPaywall = true
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
        exportTask?.cancel()
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
        vaultManager.refreshVaultAccess()
        if vaultManager.requiresVaultReselection {
            showDestinationChangedAlert = true
            return
        }
        guard vaultManager.vaultURL != nil else {
            showFolderPicker = true
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

        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""
        partialExportNotice = nil

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

            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: advancedSettings,
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
                } else if result.successCount > 0 {
                    exportStatusMessage = GeneratedFileCountText.localizedStoppedStatus(
                        count: result.totalFilesWritten,
                        isAuthoritative: result.hasAuthoritativeFileCount,
                        successfulDataDayCount: result.successCount,
                        totalDataDayCount: result.totalCount
                    )
                } else {
                    exportStatusMessage = String(localized: "Export cancelled", comment: "Export was cancelled")
                }
            } else if result.isFullSuccess {
                exportStatusMessage = advancedSettings.dailyNotesOnlyModeEnabled
                    ? GeneratedFileCountText.localizedDailyNotesUpdated(
                        count: result.dailyNoteUpdateCount
                    )
                    : GeneratedFileCountText.localizedCompletedStatus(
                        count: result.totalFilesWritten,
                        isAuthoritative: result.hasAuthoritativeFileCount,
                        successfulDataDayCount: result.successCount,
                        totalDataDayCount: result.totalCount
                    )
            } else if result.isPartialSuccess {
                let isCompletedDailyNoteSkip = advancedSettings.dailyNotesOnlyModeEnabled
                    && result.dailyNoteSkipCount > 0
                    && result.didCompleteAllRequestedDates
                if !isCompletedDailyNoteSkip {
                    partialExportNotice = PartialExportNotice(result: result)
                }
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                let suffix: String
                if result.hasPartialFailures {
                    suffix = result.partialFailureSummary
                } else if result.hadTerminalFailure {
                    suffix = GeneratedFileCountText.localizedTerminalFailure
                } else {
                    suffix = failedDatesStr.isEmpty
                        ? GeneratedFileCountText.localizedIncompleteDataDays
                        : GeneratedFileCountText.localizedFailedDates(failedDatesStr)
                }
                if isCompletedDailyNoteSkip {
                    exportStatusMessage = "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) missing daily notes. No export files were created."
                } else {
                    exportStatusMessage = advancedSettings.dailyNotesOnlyModeEnabled
                        ? "Updated \(result.dailyNoteUpdateCount)/\(result.totalCount) daily notes. \(suffix)"
                        : GeneratedFileCountText.localizedPartialStatus(
                            count: result.totalFilesWritten,
                            isAuthoritative: result.hasAuthoritativeFileCount,
                            successfulDataDayCount: result.successCount,
                            totalDataDayCount: result.totalCount
                        ) + " " + suffix
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
