import SwiftUI
import UIKit
import StoreKit

struct ContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @EnvironmentObject var schedulingManager: SchedulingManager

    @State private var selectedTab: NavTab = .export
    @State private var startDate = Date()
    @State private var endDate = Date()
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
    @AppStorage("discordPromoDismissed") private var discordPromoDismissed = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    var body: some View {
        if !hasCompletedOnboarding && !TestMode.isUITesting {
            OnboardingView(
                showFolderPicker: $showFolderPicker,
                vaultManager: vaultManager,
                onComplete: {
                    withAnimation(AnimationTimings.smooth) {
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
                        withAnimation(AnimationTimings.standard) {
                            discordPromoDismissed = true
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                TabView(selection: $selectedTab) {
                    ExportTabView(
                        healthKitManager: healthKitManager,
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        startDate: $startDate,
                        endDate: $endDate,
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
                                showPaywall = true
                            }
                        }
                    )
                    .tabItem { Label("Export", systemImage: "arrow.up.doc.fill") }
                    .tag(NavTab.export)
                    .accessibilityIdentifier(AccessibilityID.Tab.export)

                    ScheduleTabView()
                        .environmentObject(schedulingManager)
                        .environmentObject(healthKitManager)
                        .tabItem { Label("Schedule", systemImage: "clock.fill") }
                        .tag(NavTab.schedule)
                        .accessibilityIdentifier(AccessibilityID.Tab.schedule)

                    NavigationStack {
                        SyncSettingsView()
                    }
                    .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(NavTab.sync)
                    .accessibilityIdentifier(AccessibilityID.Tab.sync)

                    SettingsTabView(
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        showFolderPicker: $showFolderPicker
                    )
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
        .preferredColorScheme(.dark)
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
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $showMarketingMetricSelection) {
            MarketingSheetWrapper {
                MetricSelectionView(selectionState: advancedSettings.metricSelection)
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
            PaywallView()
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
        .task {
            #if DEBUG
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
                }
            } else if healthKitManager.isHealthDataAvailable && !healthKitManager.isAuthorized {
                do {
                    try await healthKitManager.requestAuthorization()
                } catch {
                    // Silent fail on launch
                }
            }
        }
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
        healthKitManager.isAuthorized
            && vaultManager.vaultURL != nil
            && !advancedSettings.exportFormats.isEmpty
    }

    // MARK: - Status Helpers

    private func startStatusDismissTimer() {
        statusDismissTimer?.invalidate()
        statusDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            dismissStatus()
        }
    }

    private func dismissStatus() {
        vaultManager.lastExportStatus = nil
        statusDismissTimer?.invalidate()
    }

    // MARK: - Auto-Sync

    private func autoSyncDates(_ dates: [Date]) async {
        var records: [HealthData] = []
        for date in dates {
            if let data = try? await healthKitManager.fetchHealthData(for: date), data.hasAnyData {
                records.append(data)
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

    private func exportData() {
        // Double-check the paywall gate here too (e.g. if called programmatically).
        guard purchaseManager.canExport else {
            showPaywall = true
            return
        }

        // In UI test mode, simulate export without real HealthKit/vault interactions
        if TestMode.isUITesting {
            simulateTestExport()
            return
        }

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

            let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)

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

            let normalizedStartDate = dates.first ?? startDate
            let normalizedEndDate = dates.last ?? endDate

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: normalizedStartDate,
                dateRangeEnd: normalizedEndDate
            )

            // Count this as one export action against the free quota.
            if result.successCount > 0 {
                purchaseManager.recordExportUse()
            }

            // Auto-sync to Mac after successful export
            if result.successCount > 0,
               syncService.connectionState == .connected,
               UserDefaults.standard.bool(forKey: "syncEnabled"),
               UserDefaults.standard.bool(forKey: "autoSyncAfterExport") {
                await autoSyncDates(dates)
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
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                if result.formatsPerDate > 1 {
                    exportStatusMessage = "Exported \(result.totalFilesWritten) files (\(result.successCount)/\(result.totalCount) days × \(result.formatsPerDate) formats). Failed: \(failedDatesStr)"
                    vaultManager.lastExportStatus = "Partial export: \(result.successCount)/\(result.totalCount) days succeeded (\(result.totalFilesWritten) files)"
                } else {
                    exportStatusMessage = "Exported \(result.successCount)/\(result.totalCount) files. Failed: \(failedDatesStr)"
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
}

// MARK: - Discord Promo Banner

struct DiscordPromoBanner: View {
    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 13, weight: .semibold))
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

                Text("Chat with us on Discord")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.sm)

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

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
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
        let price = purchaseManager.product?.displayPrice ?? "$9.99"
        return "\(price) — remove the 3-export limit"
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
                        .font(.system(size: 48, weight: .medium))
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
                    subtitle: vaultManager.vaultURL != nil ? vaultManager.vaultName : "Not selected",
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
            PaywallView()
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
                    if isActive {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .blur(radius: 6)
                            .opacity(0.5)
                            .accessibilityHidden(true)
                    }

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
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
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to open \(title)")
        .accessibilityValue(isActive ? "Configured" : "Not configured")
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(SchedulingManager.shared)
}
