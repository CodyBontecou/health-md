import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
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
    @State private var showSubfolderPrompt = false
    @State private var pendingFolderURL: URL?
    @State private var tempSubfolderName = ""

    var body: some View {
        ZStack {
            // Clean minimal background
            Color.bgPrimary.ignoresSafeArea()

            // Main content based on selected tab
            VStack(spacing: 0) {
                switch selectedTab {
                case .export:
                    ExportTabView(
                        healthKitManager: healthKitManager,
                        vaultManager: vaultManager,
                        isExporting: $isExporting,
                        exportProgress: $exportProgress,
                        exportStatusMessage: $exportStatusMessage,
                        showExportModal: $showExportModal,
                        showFolderPicker: $showFolderPicker,
                        canExport: canExport
                    )
                case .schedule:
                    ScheduleTabView()
                        .environmentObject(schedulingManager)
                        .environmentObject(healthKitManager)
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
                    ExportStatusBadge(
                        status: status.starts(with: "Exported")
                            ? .success(status)
                            : .error(status),
                        onDismiss: dismissStatus
                    )
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
            if healthKitManager.isHealthDataAvailable && !healthKitManager.isAuthorized {
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

    // MARK: - Export

    private func exportData() {
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""
        statusDismissTimer?.invalidate()

        Task {
            defer {
                isExporting = false
                exportProgress = 0.0
            }

            var dates: [Date] = []
            var currentDate = startDate
            let calendar = Calendar.current

            currentDate = calendar.startOfDay(for: currentDate)
            let normalizedEndDate = calendar.startOfDay(for: endDate)
            let normalizedStartDate = currentDate

            while currentDate <= normalizedEndDate {
                dates.append(currentDate)
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                    break
                }
                currentDate = nextDate
            }

            let totalDays = dates.count
            var successCount = 0
            var failedDateDetails: [FailedDateDetail] = []
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for (index, date) in dates.enumerated() {
                exportStatusMessage = "Exporting \(dateFormatter.string(from: date))... (\(index + 1)/\(totalDays))"

                do {
                    let healthData = try await healthKitManager.fetchHealthData(for: date)
                    try await vaultManager.exportHealthData(healthData, settings: advancedSettings)
                    successCount += 1
                } catch let error as ExportError {
                    let reason: ExportFailureReason
                    switch error {
                    case .noVaultSelected:
                        reason = .noVaultSelected
                    case .noHealthData:
                        reason = .noHealthData
                    case .accessDenied:
                        reason = .accessDenied
                    }
                    failedDateDetails.append(FailedDateDetail(date: date, reason: reason))
                } catch {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .unknown, errorDetails: error.localizedDescription))
                }

                exportProgress = Double(index + 1) / Double(totalDays)
            }

            if failedDateDetails.isEmpty {
                exportStatusMessage = "Successfully exported \(successCount) file\(successCount == 1 ? "" : "s")"
                vaultManager.lastExportStatus = "Exported \(successCount) file\(successCount == 1 ? "" : "s")"

                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: normalizedStartDate,
                    dateRangeEnd: normalizedEndDate,
                    successCount: successCount,
                    totalCount: totalDays
                )

                startStatusDismissTimer()
            } else if successCount > 0 {
                let failedDatesStr = failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                exportStatusMessage = "Exported \(successCount)/\(totalDays) files. Failed: \(failedDatesStr)"
                vaultManager.lastExportStatus = "Partial export: \(successCount)/\(totalDays) succeeded"

                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: normalizedStartDate,
                    dateRangeEnd: normalizedEndDate,
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails
                )

                startStatusDismissTimer()
            } else {
                let primaryReason = failedDateDetails.first?.reason ?? .unknown
                exportStatusMessage = "Export failed: \(primaryReason.shortDescription)"
                vaultManager.lastExportStatus = primaryReason.shortDescription

                exportHistory.recordFailure(
                    source: .manual,
                    dateRangeStart: normalizedStartDate,
                    dateRangeEnd: normalizedEndDate,
                    reason: primaryReason,
                    successCount: 0,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails
                )

                if let firstFailedDetail = failedDateDetails.first {
                    errorMessage = firstFailedDetail.detailedMessage
                } else {
                    errorMessage = primaryReason.detailedDescription
                }
                showError = true
            }
        }
    }
}

// MARK: - Export Tab View

struct ExportTabView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var vaultManager: VaultManager
    @Binding var isExporting: Bool
    @Binding var exportProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var showExportModal: Bool
    @Binding var showFolderPicker: Bool
    let canExport: Bool
    
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
                            if healthKitManager.isAuthorized {
                                // Already authorized - show guide to adjust permissions
                                showHealthPermissionsGuide = true
                            } else {
                                // Not yet authorized - show permission sheet
                                Task {
                                    try? await healthKitManager.requestAuthorization()
                                }
                            }
                        }
                    )

                    CompactStatusBadge(
                        icon: "folder.fill",
                        title: vaultManager.vaultURL != nil ? vaultManager.vaultName : "Vault",
                        isConnected: vaultManager.vaultURL != nil,
                        action: {
                            showFolderPicker = true
                        }
                    )
                }

                // Main Export Button
                PrimaryButton(
                    "Export Health Data",
                    icon: "arrow.up.doc.fill",
                    isLoading: isExporting,
                    isDisabled: !canExport,
                    action: { showExportModal = true }
                )

                // Export progress with glass background
                if isExporting && !exportStatusMessage.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Text(exportStatusMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textSecondary)

                        ProgressView(value: exportProgress)
                            .tint(.accent)
                            .frame(maxWidth: .infinity)
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

    var body: some View {
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

            Spacer()

            // Main content
            VStack(spacing: Spacing.xl) {
                // Settings icon with Liquid Glass container
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.textMuted)
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

                VStack(spacing: Spacing.sm) {
                    Text("CONFIGURE")
                        .font(Typography.hero())
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                        .tracking(3)

                    Text("YOUR APP")
                        .font(Typography.hero())
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                        .tracking(3)
                }

                Text("Customize export format and data types")
                    .font(Typography.bodyLarge())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.sm)
            }

            Spacer()

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
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .sheet(isPresented: $showAdvancedSettings) {
            AdvancedSettingsView(settings: advancedSettings)
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
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
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(SchedulingManager.shared)
}
