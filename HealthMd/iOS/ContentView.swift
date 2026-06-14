import SwiftUI
import UIKit
import StoreKit
import Combine
import os.log

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "Export")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @EnvironmentObject var schedulingManager: SchedulingManager

    @State private var selectedTab: NavTab = .export
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var dateRangePreset: ExportDateRangePreset = .today
    @State private var showFolderPicker = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var statusDismissTimer: Timer?
    @State private var exportTask: Task<Void, Never>?
    @State private var showSubfolderPrompt = false
    @State private var pendingFolderURL: URL?
    @State private var tempSubfolderName = ""
    @State private var showPaywall = false
    @State private var showMarketingMetricSelection = false
    @State private var showMarketingFormatCustomization = false
    @State private var showMarketingIndividualTracking = false
    @State private var showMarketingDailyNoteInjection = false
    @State private var showMarketingPaywall = false
    @State private var showMarketingOnboarding = false
    @State private var showMarketingFolderNamePrompt = false
    @AppStorage(ExportTargetSelection.storageKey) private var exportTargetSelection: ExportTargetSelection = .localIPhoneFolder
    @State private var activeMacExportJobID: UUID?
    @State private var macExportPayloadSent = false
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
        if !hasCompletedOnboarding && !TestMode.isUITesting {
            OnboardingView(
                showFolderPicker: $showFolderPicker,
                vaultManager: vaultManager,
                onComplete: {
                    withOptionalMotionAnimation(AnimationTimings.smooth) {
                        hasCompletedOnboarding = true
                    }
                }
            )
            .environmentObject(healthKitManager)
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    pendingFolderURL = url
                    tempSubfolderName = vaultManager.healthSubfolder
                    showSubfolderPrompt = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Name Your Export Folder", isPresented: $showSubfolderPrompt) {
                TextField("Health", text: $tempSubfolderName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {
                    pendingFolderURL = nil
                    tempSubfolderName = ""
                }
                Button("Save") {
                    if let url = pendingFolderURL {
                        vaultManager.setVaultFolder(url)
                        vaultManager.healthSubfolder = tempSubfolderName.isEmpty ? "Health" : tempSubfolderName
                        vaultManager.saveSubfolderSetting()
                    }
                    pendingFolderURL = nil
                    tempSubfolderName = ""
                }
            } message: {
                Text("Enter a name for the subfolder where your health data will be exported.")
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
                        exportTargetSelection: $exportTargetSelection,
                        startDate: $startDate,
                        endDate: $endDate,
                        dateRangePreset: $dateRangePreset,
                        isExporting: $isExporting,
                        exportProgress: $exportProgress,
                        exportStatusMessage: $exportStatusMessage,
                        showFolderPicker: $showFolderPicker,
                        canExport: canExport,
                        onCancelExport: cancelExport,
                        onExportTapped: {
                            if purchaseManager.canExport {
                                exportData()
                            } else {
                                presentExportPaywall()
                            }
                        }
                    )
                    .tabItem {
                        Label("Export", systemImage: "arrow.up.doc.fill")
                            .accessibilityIdentifier(AccessibilityID.Tab.export)
                    }
                    .tag(NavTab.export)
                    .accessibilityIdentifier(AccessibilityID.Tab.export)

                    ScheduleTabView()
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
            }

            // Toast notification
            VStack {
                Spacer()

                if let status = vaultManager.lastExportStatus {
                    let isSuccess = status.starts(with: "Exported")
                    ExportStatusBadge(
                        status: isSuccess ? .success(status) : .error(status),
                        onDismiss: dismissStatus,
                        folderURL: isSuccess ? vaultManager.lastExportFolderURL : nil
                    )
                    .accessibilityIdentifier(AccessibilityID.Status.exportStatusBadge)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                pendingFolderURL = url
                tempSubfolderName = vaultManager.healthSubfolder
                showSubfolderPrompt = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Name Your Export Folder", isPresented: $showSubfolderPrompt) {
            TextField("Health", text: $tempSubfolderName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                pendingFolderURL = nil
                tempSubfolderName = ""
            }
            Button("Save") {
                if let url = pendingFolderURL {
                    vaultManager.setVaultFolder(url)
                    vaultManager.healthSubfolder = tempSubfolderName.isEmpty ? "Health" : tempSubfolderName
                    vaultManager.saveSubfolderSetting()
                }
                pendingFolderURL = nil
                tempSubfolderName = ""
            }
        } message: {
            Text("Enter a name for the subfolder where your health data will be exported.")
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
        .alert("Name Your Export Folder", isPresented: $showMarketingFolderNamePrompt) {
            TextField("Health", text: $tempSubfolderName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { tempSubfolderName = "" }
            Button("Save") { tempSubfolderName = "" }
        } message: {
            Text("Enter a name for the subfolder where your health data will be exported.")
        }
        #endif
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert(
            schedulingManager.notificationExportResult?.title ?? "Export",
            isPresented: Binding(
                get: { schedulingManager.notificationExportResult != nil },
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
        .onReceive(syncService.$latestMacExportMessage.compactMap { $0 }) { message in
            handleMacExportMessage(message)
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
                    advancedSettings.includeGranularData = true
                }
            } else if healthKitManager.isHealthDataAvailable && !healthKitManager.isAuthorized {
                do {
                    try await healthKitManager.requestAuthorization()
                    PricingAnalyticsClient.shared.trackHealthAuthorizationCompleted(
                        status: healthKitManager.isAuthorized ? .authorized : .notAuthorized
                    )
                } catch {
                    PricingAnalyticsClient.shared.trackHealthAuthorizationCompleted(status: .unknown)
                    // Silent fail on launch
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
        .healthMdReleaseNotesSheet()
        .onDisappear {
            statusDismissTimer?.invalidate()
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

        let steps: [CaptureStep] = [
            // Tab screens — capture clean state first
            CaptureStep(name: "01-export") {
                selectedTab = .export
            },
            CaptureStep(name: "02-schedule") {
                selectedTab = .schedule
            },
            CaptureStep(name: "03-sync") {
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

            // Folder name prompt (alert overlay)
            CaptureStep(name: "14-folder-name-prompt", settle: .milliseconds(1500)) {
                selectedTab = .settings
                tempSubfolderName = "Health"
                showMarketingFolderNamePrompt = true
            } cleanup: {
                showMarketingFolderNamePrompt = false
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
            target: exportTargetSelection,
            hasLocalFolder: vaultManager.vaultURL != nil,
            canExportToConnectedMac: syncService.canExportToConnectedMac
        )
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
        vaultManager.lastExportStatus = nil
        statusDismissTimer?.invalidate()
    }

    private var currentPaywallContext: PricingAnalyticsPaywallContext {
        exportTargetSelection == .connectedMac ? .macTarget : .export
    }

    private var currentExportTargetType: PricingAnalyticsExportTargetType {
        exportTargetSelection == .connectedMac ? .connectedMac : .localFile
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
        for date in dates {
            do {
                let data = try await healthKitManager.fetchHealthData(for: date)
                if data.hasAnyData {
                    records.append(data)
                }
            } catch {
                Self.logger.warning("Auto-sync HealthKit fetch failed for date=\(date, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        if let jobID = activeMacExportJobID, macExportPayloadSent {
            syncService.send(.macExportCancel(jobID: jobID))
            exportStatusMessage = "Cancelling Mac export…"
            return
        }

        exportTask?.cancel()
    }

    private func exportData() {
        // Double-check the paywall gate here too (e.g. if called programmatically).
        guard purchaseManager.canExport else {
            presentExportPaywall()
            return
        }

        // In UI test mode, simulate export without real HealthKit/vault interactions.
        if TestMode.isUITesting {
            simulateTestExport()
            return
        }

        guard healthKitManager.isAuthorized else {
            presentExportConfigurationError("Authorize Health access before exporting.")
            return
        }

        guard !advancedSettings.exportFormats.isEmpty else {
            presentExportConfigurationError("Select at least one export format before exporting.")
            return
        }

        switch exportTargetSelection {
        case .localIPhoneFolder:
            vaultManager.refreshVaultAccess()
            guard vaultManager.vaultURL != nil else {
                if vaultManager.hasSavedVaultFolder {
                    presentExportConfigurationError("Reconnect the selected folder in Files, then try again, or re-select the folder in Health.md.")
                } else {
                    presentExportConfigurationError("Choose a local iPhone folder before exporting.")
                }
                return
            }
            exportLocalData()
        case .connectedMac:
            guard syncService.canExportToConnectedMac else {
                presentExportConfigurationError(syncService.macExportReadinessMessage)
                return
            }
            exportDataToConnectedMac()
        }
    }

    private func presentExportConfigurationError(_ message: String) {
        exportStatusMessage = message
        errorMessage = message
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

            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: advancedSettings,
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
                if result.successCount > 0 {
                    exportStatusMessage = String(localized: "Export stopped — \(result.successCount) of \(result.totalCount) files exported", comment: "Export cancelled with partial success")
                    vaultManager.lastExportStatus = String(localized: "Export stopped: \(result.successCount)/\(result.totalCount) exported", comment: "Export status after cancellation")
                } else {
                    exportStatusMessage = String(localized: "Export cancelled", comment: "Export was cancelled")
                    vaultManager.lastExportStatus = String(localized: "Export cancelled", comment: "Export was cancelled")
                }
                startStatusDismissTimer()
            } else if result.isFullSuccess {
                if result.formatsPerDate > 1 {
                    exportStatusMessage = String(localized: "Successfully exported \(result.totalFilesWritten) files (\(result.successCount) days × \(result.formatsPerDate) formats)", comment: "Multi-format export success message")
                    vaultManager.lastExportStatus = String(localized: "Exported \(result.totalFilesWritten) files", comment: "Multi-format export status message")
                } else {
                    exportStatusMessage = String(localized: "Successfully exported \(result.successCount) files", comment: "Export success message")
                    vaultManager.lastExportStatus = String(localized: "Exported \(result.successCount) files", comment: "Export status message")
                }
                startStatusDismissTimer()

                if ReviewManager.shared.recordSuccessfulExport() {
                    ReviewManager.shared.didRequestReview()
                    requestReview()
                }
            } else if result.isPartialSuccess {
                let warning = result.hasPartialFailures ? result.partialFailureSummary : nil
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                let suffix = warning ?? "Failed: \(failedDatesStr)"
                if result.formatsPerDate > 1 {
                    exportStatusMessage = "Exported \(result.totalFilesWritten) files (\(result.successCount)/\(result.totalCount) days × \(result.formatsPerDate) formats). \(suffix)"
                    vaultManager.lastExportStatus = "Partial export: \(result.successCount)/\(result.totalCount) days succeeded (\(result.totalFilesWritten) files)"
                } else {
                    exportStatusMessage = "Exported \(result.successCount)/\(result.totalCount) files. \(suffix)"
                    vaultManager.lastExportStatus = "Partial export: \(result.successCount)/\(result.totalCount) succeeded"
                }
                startStatusDismissTimer()
            } else {
                let primaryReason = result.primaryFailureReason ?? .unknown
                exportStatusMessage = "Export failed: \(primaryReason.shortDescription)"
                vaultManager.lastExportStatus = primaryReason.shortDescription

                if let firstFailedDetail = result.failedDateDetails.first {
                    errorMessage = firstFailedDetail.detailedMessage
                } else {
                    errorMessage = primaryReason.detailedDescription
                }
                showError = true
            }
        }
    }

    private func exportDataToConnectedMac() {
        guard purchaseManager.canExport else {
            presentExportPaywall()
            return
        }
        guard syncService.canExportToConnectedMac else {
            presentExportConfigurationError(syncService.macExportReadinessMessage)
            return
        }

        let jobID = UUID()
        activeMacExportJobID = jobID
        activeMacExportStartDate = nil
        activeMacExportEndDate = nil
        macExportPayloadSent = false
        macExportQuotaRecorded = false
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = "Preparing Mac export…"
        syncService.isSyncing = true
        statusDismissTimer?.invalidate()

        exportTask = Task {
            do {
                let destinationName = syncService.macDestinationStatus?.destinationDisplayName
                    ?? syncService.connectedPeerName
                    ?? "Mac"
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                let job = try await MacExportJobBuilder.build(
                    jobID: jobID,
                    sourceDeviceName: UIDevice.current.name,
                    startDate: startDate,
                    endDate: endDate,
                    settings: advancedSettings,
                    destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                    fetchHealthData: { date, includeGranularData in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: advancedSettings.metricSelection
                        )
                    },
                    onProgress: { current, total, date in
                        exportStatusMessage = "Preparing \(dateFormatter.string(from: date)) for Mac… (\(current)/\(total))"
                        exportProgress = Double(current) / Double(max(total, 1)) * 0.35
                    }
                )

                guard activeMacExportJobID == jobID else { return }

                guard purchaseManager.canExport else {
                    presentExportPaywall()
                    finishMacExportPreparationStopped(
                        jobID: jobID,
                        message: "Export limit reached. Upgrade to export more."
                    )
                    return
                }

                guard syncService.canExportToConnectedMac else {
                    finishMacExportPreparationFailed(
                        jobID: jobID,
                        message: syncService.macExportReadinessMessage
                    )
                    return
                }

                activeMacExportStartDate = job.dateRangeStart
                activeMacExportEndDate = job.dateRangeEnd
                macExportPayloadSent = true
                exportStatusMessage = "Sending export to \(destinationName)…"
                exportProgress = max(exportProgress, 0.4)
                syncService.sendLargePayload(.macExportRequest(job))
                exportStatusMessage = "Waiting for \(destinationName) to start…"
                exportTask = nil
            } catch is CancellationError {
                finishMacExportPreparationStopped(jobID: jobID, message: "Export cancelled")
            } catch {
                finishMacExportPreparationFailed(
                    jobID: jobID,
                    message: "Failed to prepare Mac export: \(error.localizedDescription)"
                )
            }
        }
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
        errorMessage = message
        showError = true
        isExporting = false
        exportProgress = 0.0
        exportTask = nil
        syncService.isSyncing = false
        resetMacExportState()
    }

    private func handleSyncConnectionStateChange(_ newState: SyncConnectionState) {
        guard newState == .disconnected,
              let jobID = activeMacExportJobID else { return }

        if macExportPayloadSent {
            completeMacExport(with: MacExportFailure(
                jobID: jobID,
                reason: .payloadDecodeFailure,
                message: "Mac disconnected before export finished."
            ))
        } else {
            exportTask?.cancel()
            finishMacExportPreparationFailed(
                jobID: jobID,
                message: "Mac disconnected before export could be sent."
            )
        }
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
            exportProgress = max(0.45, progress.fractionComplete)
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
        let normalizedStartDate = activeMacExportStartDate ?? Calendar.current.startOfDay(for: startDate)
        let normalizedEndDate = activeMacExportEndDate ?? Calendar.current.startOfDay(for: endDate)
        let exportResult = ExportOrchestrator.ExportResult(
            successCount: result.successCount,
            totalCount: result.totalCount,
            failedDateDetails: result.failedDateDetails,
            formatsPerDate: result.formatsPerDate,
            wasCancelled: result.status == .cancelled
        )
        let destinationName = result.destinationDisplayName
            ?? syncService.macDestinationStatus?.destinationDisplayName
            ?? "Mac"

        ExportOrchestrator.recordResult(
            exportResult,
            source: .macAgent,
            dateRangeStart: normalizedStartDate,
            dateRangeEnd: normalizedEndDate,
            targetLabel: destinationName,
            fileCount: result.totalFilesWritten
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

        vaultManager.lastExportFolderURL = nil
        exportProgress = 1.0
        isExporting = false
        exportTask = nil
        syncService.isSyncing = false

        switch result.status {
        case .success:
            if result.formatsPerDate > 1 {
                exportStatusMessage = "Successfully exported \(result.totalFilesWritten) files to \(destinationName) (\(result.successCount) days × \(result.formatsPerDate) formats)"
                vaultManager.lastExportStatus = "Exported \(result.totalFilesWritten) files to Mac"
            } else {
                exportStatusMessage = "Successfully exported \(result.successCount) files to \(destinationName)"
                vaultManager.lastExportStatus = "Exported \(result.successCount) files to Mac"
            }
            startStatusDismissTimer()

            if ReviewManager.shared.recordSuccessfulExport() {
                ReviewManager.shared.didRequestReview()
                requestReview()
            }
        case .partialSuccess:
            let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
            if result.formatsPerDate > 1 {
                exportStatusMessage = "Exported \(result.totalFilesWritten) files to \(destinationName) (\(result.successCount)/\(result.totalCount) days × \(result.formatsPerDate) formats). Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial Mac export: \(result.successCount)/\(result.totalCount) days succeeded (\(result.totalFilesWritten) files)"
            } else {
                exportStatusMessage = "Exported \(result.successCount)/\(result.totalCount) files to \(destinationName). Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial Mac export: \(result.successCount)/\(result.totalCount) succeeded"
            }
            startStatusDismissTimer()
        case .cancelled:
            if result.successCount > 0 {
                exportStatusMessage = "Mac export stopped — \(result.successCount) of \(result.totalCount) days exported"
                vaultManager.lastExportStatus = "Mac export stopped: \(result.successCount)/\(result.totalCount) exported"
            } else {
                exportStatusMessage = "Mac export cancelled"
                vaultManager.lastExportStatus = "Mac export cancelled"
            }
            startStatusDismissTimer()
        case .failure:
            let primaryReason = exportResult.primaryFailureReason ?? .unknown
            exportStatusMessage = "Mac export failed: \(primaryReason.shortDescription)"
            vaultManager.lastExportStatus = primaryReason.shortDescription
            if let firstFailedDetail = result.failedDateDetails.first {
                errorMessage = firstFailedDetail.detailedMessage
            } else {
                errorMessage = primaryReason.detailedDescription
            }
            showError = true
        }

        resetMacExportState()
    }

    private func completeMacExport(with failure: MacExportFailure) {
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
            successCount: 0,
            totalCount: totalCount,
            failedDateDetails: [failedDetail],
            formatsPerDate: max(advancedSettings.exportFormats.count, 1),
            wasCancelled: failure.reason == .cancelled
        )

        ExportOrchestrator.recordResult(
            exportResult,
            source: .macAgent,
            dateRangeStart: normalizedStartDate,
            dateRangeEnd: normalizedEndDate,
            targetLabel: syncService.macDestinationStatus?.destinationDisplayName ?? syncService.connectedPeerName ?? "Mac",
            fileCount: 0
        )

        isExporting = false
        exportProgress = 0.0
        exportTask = nil
        syncService.isSyncing = false
        vaultManager.lastExportFolderURL = nil

        if failure.reason == .cancelled {
            exportStatusMessage = "Mac export cancelled"
            vaultManager.lastExportStatus = "Mac export cancelled"
            startStatusDismissTimer()
        } else {
            exportStatusMessage = "Mac export failed: \(failure.message)"
            vaultManager.lastExportStatus = failure.message
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
            switch result {
            case "fail":
                exportStatusMessage = "Export failed: No health data"
                vaultManager.lastExportStatus = "No health data"
                errorMessage = "No health data available for the selected dates."
                showError = true
            default:
                exportStatusMessage = "Successfully exported 1 files"
                vaultManager.lastExportStatus = "Exported 1 files"
                purchaseManager.recordExportUse()
                exportProgress = 1.0
                startStatusDismissTimer()
            }
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
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
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
                        .fill(Color.white.opacity(0.06))
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

    var body: some View {
        NavigationStack {
            ScheduleSettingsView()
                .navigationTitle("Schedule")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Settings Tab View

struct SettingsTabView: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Binding var showFolderPicker: Bool
    @State private var showMailCompose = false
    @State private var showPaywall = false
    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    @State private var debugResult: String = ""
    @State private var showDebugAlert = false
    @State private var isRunningDebug = false

    private var unlockSubtitle: String {
        if purchaseManager.isUnlocked {
            return "Unlocked"
        }
        if let individualPrice = purchaseManager.product(for: .individual)?.displayPrice,
           let familyPrice = purchaseManager.product(for: .family)?.displayPrice {
            return "Individual \(individualPrice) or Family \(familyPrice)"
        }
        if let price = purchaseManager.product(for: .individual)?.displayPrice {
            return "From \(price) — remove the 3-export limit"
        }
        return "One-time unlock — individual or family"
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
            VStack(spacing: 0) {
                // Header
                VStack(spacing: Spacing.sm) {
                    Text("SETTINGS")
                        .font(Typography.labelUppercase())
                        .foregroundStyle(Color.textMuted)
                        .tracking(3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Spacing.xl)
                }

                // Main content
                VStack(spacing: Spacing.lg) {
                    // Settings icon with Liquid Glass container
                    Image(systemName: "gearshape.fill")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 84, height: 84)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    VStack(spacing: Spacing.xs) {
                        Text("CONFIGURE")
                            .font(Typography.displayLarge())
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)
                            .tracking(3)

                        Text("YOUR APP")
                            .font(Typography.displayLarge())
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)
                            .tracking(3)
                    }

                    Text("Customize export format and data types")
                        .font(Typography.bodyLarge())
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl)

                // Settings options with Liquid Glass cards
                VStack(spacing: Spacing.md) {
                // Full Access — show unlock CTA only when not unlocked
                if !purchaseManager.isUnlocked {
                    SettingsRow(
                        icon: "lock.fill",
                        title: "Unlock Full Access",
                        subtitle: unlockSubtitle,
                        isActive: false,
                        action: { showPaywall = true }
                    )
                }

                // Vault selection
                SettingsRow(
                    icon: "folder.fill",
                    title: "Obsidian Vault",
                    subtitle: vaultManager.isVaultConfigured ? vaultManager.vaultName : "Not selected",
                    isActive: vaultManager.vaultURL != nil,
                    action: { showFolderPicker = true }
                )

                SettingsRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Join our Discord",
                    subtitle: "Chat with the community",
                    isActive: true,
                    action: { UIApplication.shared.open(discordURL) }
                )

                // Send Feedback
                SettingsRow(
                    icon: "envelope.fill",
                    title: "Send Feedback",
                    subtitle: "Questions, ideas, or issues",
                    isActive: true,
                    action: {
                        if FeedbackHelper.canSendMail {
                            showMailCompose = true
                        } else if let url = FeedbackHelper.mailtoURL() {
                            UIApplication.shared.open(url)
                        }
                    }
                )

                // Report Issue on GitHub
                SettingsRow(
                    icon: "ladybug.fill",
                    title: "Report a Bug",
                    subtitle: "Open an issue on GitHub",
                    isActive: true,
                    action: { FeedbackHelper.openGitHubIssue() }
                )

                if showDebugTools {
                    SettingsRow(
                        icon: "checkmark.shield.fill",
                        title: isRunningDebug ? "Running…" : "Debug: Verify Receipt",
                        subtitle: "Test worker ↔ Apple end-to-end",
                        isActive: true,
                        action: {
                            guard !isRunningDebug else { return }
                            isRunningDebug = true
                            Task {
                                debugResult = await PurchaseManager.shared.debugVerifyReceipt()
                                isRunningDebug = false
                                showDebugAlert = true
                            }
                        }
                    )
                    
                    SettingsRow(
                        icon: "arrow.counterclockwise",
                        title: "Debug: Reset Onboarding",
                        subtitle: "Show onboarding flow again",
                        isActive: true,
                        action: {
                            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                            debugResult = "Onboarding reset! Restart the app to see it."
                            showDebugAlert = true
                        }
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 120) // Clear nav bar
        }
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Receipt Verification", isPresented: $showDebugAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(debugResult)
        }
    }
}

// MARK: - Settings Row Component

struct SettingsRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // Icon with background
                ZStack {
                    if isActive && !reduceMotion {
                        Image(systemName: icon)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.accent)
                            .blur(radius: 6)
                            .opacity(0.5)
                            .accessibilityHidden(true)
                    }

                    Image(systemName: icon)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isActive ? Color.accent : Color.textMuted)
                }
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(LocalizedStringKey(subtitle))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.md + 4)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.98 : 1.0))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to open \(title)")
        .accessibilityValue(isActive ? "Configured" : "Not configured")
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7), updates)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(SchedulingManager.shared)
}
