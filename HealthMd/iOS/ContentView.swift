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
    @State private var showExportModal = false
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
    @AppStorage("macAppPromoDismissed") private var macAppPromoDismissed = false
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    var body: some View {
        ZStack {
            // Clean minimal background
            Color.bgPrimary.ignoresSafeArea()

            // Main content based on selected tab
            VStack(spacing: 0) {
                if !macAppPromoDismissed {
                    MacAppPromoBanner {
                        withAnimation(AnimationTimings.standard) {
                            macAppPromoDismissed = true
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                switch selectedTab {
                case .export:
                    ExportTabView(
                        healthKitManager: healthKitManager,
                        vaultManager: vaultManager,
                        isExporting: $isExporting,
                        exportProgress: $exportProgress,
                        exportStatusMessage: $exportStatusMessage,
                        showFolderPicker: $showFolderPicker,
                        canExport: canExport,
                        onCancelExport: cancelExport,
                        onExportTapped: {
                            if purchaseManager.canExport {
                                if TestMode.isUITesting {
                                    // Skip export modal in test mode — run simulated export directly
                                    exportData()
                                } else {
                                    showExportModal = true
                                }
                            } else {
                                showPaywall = true
                            }
                        }
                    )
                case .schedule:
                    ScheduleTabView()
                        .environmentObject(schedulingManager)
                        .environmentObject(healthKitManager)
                case .sync:
                    NavigationStack {
                        SyncSettingsView()
                    }
                case .settings:
                    SettingsTabView(
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        showFolderPicker: $showFolderPicker
                    )
                }

                Spacer(minLength: 0)

                // Liquid Glass Nav Bar
                LiquidGlassNavBar(selectedTab: $selectedTab)
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
        .sheet(isPresented: $showExportModal) {
            ExportModal(
                startDate: $startDate,
                endDate: $endDate,
                subfolder: $vaultManager.healthSubfolder,
                vaultName: vaultManager.vaultName,
                onExport: exportData,
                onSubfolderChange: { vaultManager.saveSubfolderSetting() },
                exportSettings: advancedSettings
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
    }

    // MARK: - Computed Properties

    private var canExport: Bool {
        healthKitManager.isAuthorized && vaultManager.vaultURL != nil
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
            showExportModal = false
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
                exportStatusMessage = String(localized: "Successfully exported \(result.successCount) files", comment: "Export success message")
                vaultManager.lastExportStatus = String(localized: "Exported \(result.successCount) files", comment: "Export status message")
                startStatusDismissTimer()

                if ReviewManager.shared.recordSuccessfulExport() {
                    ReviewManager.shared.didRequestReview()
                    requestReview()
                }
            } else if result.isPartialSuccess {
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                exportStatusMessage = "Exported \(result.successCount)/\(result.totalCount) files. Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial export: \(result.successCount)/\(result.totalCount) succeeded"
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

// MARK: - macOS Promo Banner

struct MacAppPromoBanner: View {
    private let macAppURL = URL(string: "https://isolated.tech/apps/healthmd")!
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.accentSubtle)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Now on macOS")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text("Get the desktop app")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.sm)

            Link(destination: macAppURL) {
                Text("View")
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
            .accessibilityLabel("Dismiss macOS banner")
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
        .accessibilityLabel("Health.md for macOS promotion. Now on macOS, get the desktop app.")
    }
}

// MARK: - Export Tab View

struct ExportTabView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var vaultManager: VaultManager
    @Binding var isExporting: Bool
    @Binding var exportProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var showFolderPicker: Bool
    let canExport: Bool
    var onCancelExport: (() -> Void)?
    /// Called when the user taps the export button. The parent decides
    /// whether to show the export modal or the paywall.
    let onExportTapped: () -> Void

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showHealthPermissionsGuide = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Icon and Title
            VStack(spacing: Spacing.lg) {
                // App Icon with Liquid Glass effect
                ZStack {
                    // Glow behind icon
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                        .blur(radius: 30)
                        .opacity(0.5)
                        .accessibilityHidden(true)

                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.accent.opacity(0.4), radius: 24, x: 0, y: 12)
                }

                // Title
                Text("Health.md")
                    .font(Typography.hero())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)
                    .tracking(2)

                // Subtitle
                Text("Export your wellness data to markdown")
                    .font(Typography.bodyLarge())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.xs)
            }

            Spacer()

            // Status and Export Section with glass background
            VStack(spacing: Spacing.lg) {
                // Status badges
                HStack(spacing: Spacing.md) {
                    CompactStatusBadge(
                        icon: "heart.fill",
                        title: "Health",
                        isConnected: healthKitManager.isAuthorized,
                        action: {
                            Task {
                                // Always attempt to show the HealthKit authorization sheet.
                                // If new types exist that haven't been requested before,
                                // iOS will re-present the full permission sheet.
                                try? await healthKitManager.requestAuthorization()
                                // If already fully authorized, guide user to Health app
                                if healthKitManager.isAuthorized {
                                    showHealthPermissionsGuide = true
                                }
                            }
                        }
                    )
                    .accessibilityIdentifier(AccessibilityID.Export.healthBadge)

                    CompactStatusBadge(
                        icon: "folder.fill",
                        title: vaultManager.vaultURL != nil ? vaultManager.vaultName : "Vault",
                        isConnected: vaultManager.vaultURL != nil,
                        action: {
                            showFolderPicker = true
                        }
                    )
                    .accessibilityIdentifier(AccessibilityID.Export.vaultBadge)
                }

                // Main Export Button
                PrimaryButton(
                    "Export Health Data",
                    icon: "arrow.up.doc.fill",
                    isLoading: isExporting,
                    isDisabled: !canExport,
                    action: onExportTapped
                )
                .accessibilityIdentifier(AccessibilityID.Export.exportButton)

                // Free exports remaining hint
                if !purchaseManager.isUnlocked && canExport && !isExporting {
                    let remaining = purchaseManager.freeExportsRemaining
                    Text(remaining == 1
                         ? "1 free export remaining"
                         : "\(remaining) free exports remaining")
                        .font(.caption)
                        .foregroundStyle(Color.textMuted)
                        .accessibilityIdentifier(AccessibilityID.Export.freeExportsLabel)
                        .accessibilityLabel("\(remaining) free export\(remaining == 1 ? "" : "s") remaining before purchase required")
                }

                // Export progress with glass background
                if isExporting && !exportStatusMessage.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Text(exportStatusMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textSecondary)

                        ProgressView(value: exportProgress)
                            .tint(.accent)
                            .frame(maxWidth: .infinity)

                        Button {
                            onCancelExport?()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Stop Export")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.15))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityID.Export.cancelExportButton)
                        .padding(.top, Spacing.xs)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .alert("Adjust Health Permissions", isPresented: $showHealthPermissionsGuide) {
            Button("Open Health App") {
                if let healthURL = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(healthURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To change which health data Health.md can access:\n\n1. Tap \"Open Health App\"\n2. Tap your profile icon (top right)\n3. Tap \"Apps\"\n4. Select \"Health.md\"\n5. Toggle permissions on or off")
        }
        .onChange(of: exportStatusMessage) { oldValue, newValue in
            // Announce export progress to VoiceOver users
            if !newValue.isEmpty && newValue != oldValue {
                UIAccessibility.post(notification: .announcement, argument: newValue)
            }
        }
    }
}

// MARK: - Schedule Tab View

struct ScheduleTabView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @State private var showScheduleSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: Spacing.sm) {
                Text("SCHEDULE")
                    .font(Typography.labelUppercase())
                    .foregroundStyle(Color.textMuted)
                    .tracking(3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Spacing.xl)
            }

            Spacer()

            // Main content
            VStack(spacing: Spacing.xl) {
                // Schedule status icon with Liquid Glass container
                ZStack {
                    // Glow when active
                    if schedulingManager.schedule.isEnabled {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .blur(radius: 20)
                            .opacity(0.5)
                            .accessibilityHidden(true)
                    }

                    Image(systemName: schedulingManager.schedule.isEnabled ? "clock.fill" : "clock")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(schedulingManager.schedule.isEnabled ? Color.accent : Color.textMuted)
                }
                .frame(width: 100, height: 100)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: schedulingManager.schedule.isEnabled ? Color.accent.opacity(0.3) : Color.clear, radius: 20, x: 0, y: 10)

                // Status text
                VStack(spacing: Spacing.sm) {
                    Text(schedulingManager.schedule.isEnabled ? "SCHEDULE" : "NO SCHEDULE")
                        .font(Typography.hero())
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                        .tracking(3)

                    Text(schedulingManager.schedule.isEnabled ? "ACTIVE" : "SET")
                        .font(Typography.hero())
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                        .tracking(3)
                }
                .accessibilityIdentifier(AccessibilityID.Schedule.statusText)

                if schedulingManager.schedule.isEnabled,
                   let nextExport = schedulingManager.getNextExportDescription() {
                    Text(nextExport)
                        .font(Typography.bodyLarge())
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.top, Spacing.sm)
                } else {
                    Text("Automate your health data exports")
                        .font(Typography.bodyLarge())
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Spacing.sm)
                }
            }

            Spacer()

            // Configure button
            VStack(spacing: Spacing.lg) {
                PrimaryButton(
                    schedulingManager.schedule.isEnabled ? "Manage Schedule" : "Set Up Schedule",
                    icon: schedulingManager.schedule.isEnabled ? "pencil" : "plus",
                    action: { showScheduleSettings = true }
                )
                .accessibilityIdentifier(AccessibilityID.Schedule.setupButton)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .sheet(isPresented: $showScheduleSettings) {
            ScheduleSettingsView()
                .environmentObject(schedulingManager)
                .environmentObject(healthKitManager)
        }
    }
}

// MARK: - Settings Tab View

struct SettingsTabView: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @Binding var showFolderPicker: Bool
    @State private var showAdvancedSettings = false
    @State private var showSyncSettings = false
    @State private var showMailCompose = false
    private let macAppURL = URL(string: "https://isolated.tech/apps/healthmd")!
    @State private var debugResult: String = ""
    @State private var showDebugAlert = false
    @State private var isRunningDebug = false

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
                // Vault selection
                SettingsRow(
                    icon: "folder.fill",
                    title: "Obsidian Vault",
                    subtitle: vaultManager.vaultURL != nil ? vaultManager.vaultName : "Not selected",
                    isActive: vaultManager.vaultURL != nil,
                    action: { showFolderPicker = true }
                )

                // Advanced settings
                SettingsRow(
                    icon: "slider.horizontal.3",
                    title: "Export Settings",
                    subtitle: "\(advancedSettings.exportFormat.rawValue) format",
                    isActive: true,
                    action: { showAdvancedSettings = true }
                )

                // Mac sync
                SettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Mac Sync",
                    subtitle: "Send data to your Mac",
                    isActive: UserDefaults.standard.bool(forKey: "syncEnabled"),
                    action: { showSyncSettings = true }
                )

                SettingsRow(
                    icon: "desktopcomputer",
                    title: "Health.md for macOS",
                    subtitle: "Download on the App Store",
                    isActive: true,
                    action: { UIApplication.shared.open(macAppURL) }
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
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 120) // Clear nav bar
        }
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showAdvancedSettings) {
            AdvancedSettingsView(settings: advancedSettings, healthSubfolder: vaultManager.healthSubfolder)
        }
        .sheet(isPresented: $showSyncSettings) {
            NavigationStack {
                SyncSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSyncSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
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
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(subtitle)
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
