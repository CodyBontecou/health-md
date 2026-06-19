import SwiftUI
import UIKit
import os.log

// MARK: - iPad Export View (matching macOS MacExportView glass card layout)

struct iPadExportView: View {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "ExportPreview")

    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var dateRangePreset: ExportDateRangePreset
    @Binding var isExporting: Bool
    @Binding var exportProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var showFolderPicker: Bool
    let canExport: Bool
    var onCancelExport: (() -> Void)?
    /// Called when the user taps "Export Now". The parent decides whether to export
    /// immediately or show the paywall.
    var onExportTapped: (() -> Void)?

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showHealthPermissionsGuide = false
    @State private var showPreviewRequirementsPrompt = false
    @State private var showMetricSelection = false
    @State private var showPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: - Health Data Status
                VStack(alignment: .leading, spacing: 14) {
                    iPadBrandLabel("Health Data")

                    HStack(spacing: 12) {
                        Circle()
                            .fill(healthKitManager.isAuthorized ? Color.success : Color.textMuted)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthKitManager.isAuthorized
                                 ? "Apple Health Connected"
                                 : "Not Connected")
                                .font(Typography.monoEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(healthKitManager.isAuthorized
                                 ? "Ready to export health data"
                                 : "Grant access to export health data")
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        if !healthKitManager.isAuthorized {
                            Button("Connect") {
                                Task { try? await healthKitManager.requestAuthorization() }
                            }
                            .font(Typography.monoEmphasis())
                            .buttonStyle(.bordered)
                            .tint(Color.accent)
                            .controlSize(.small)
                        } else {
                            Button("Permissions") {
                                showHealthPermissionsGuide = true
                            }
                            .font(Typography.monoEmphasis())
                            .buttonStyle(.bordered)
                            .tint(Color.accent)
                            .controlSize(.small)
                        }
                    }

                    if !healthKitManager.isAuthorized {
                        Text("Connect Apple Health to start exporting your wellness data.")
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .iPadLiquidGlass()

                // MARK: - Export Folder
                VStack(alignment: .leading, spacing: 14) {
                    iPadBrandLabel("Export Folder")

                    HStack(spacing: 10) {
                        if let url = vaultManager.vaultURL {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accent)
                                .font(Typography.body())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vaultManager.vaultName)
                                    .font(Typography.monoEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                Text(url.path(percentEncoded: false))
                                    .font(Typography.monoCaption())
                                    .foregroundStyle(Color.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } else {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.textMuted)
                                .font(Typography.body())
                            Text("No folder selected")
                                .font(Typography.mono())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Button(vaultManager.vaultURL != nil ? "Change…" : "Choose…") {
                            showFolderPicker = true
                        }
                        .font(Typography.monoEmphasis())
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }

                    if vaultManager.vaultURL != nil {
                        HStack {
                            Text("Subfolder")
                                .font(Typography.mono())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder)
                                .font(Typography.monoEmphasis())
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .iPadLiquidGlass()

                // MARK: - Date Range
                VStack(alignment: .leading, spacing: 14) {
                    iPadBrandLabel("Date Range")

                    HStack(spacing: 10) {
                        ForEach(ExportDateRangePreset.allCases) { preset in
                            presetDateButton(preset)
                        }
                    }

                    if dateRangePreset == .custom {
                        Divider().background(Color.white.opacity(0.08))

                        HStack {
                            Text("From")
                                .font(Typography.mono())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            DatePicker("Start Date", selection: $startDate, in: ...endDate, displayedComponents: .date)
                                .labelsHidden()
                                .tint(Color.accent)
                                .accessibilityIdentifier(AccessibilityID.Export.customStartDatePicker)
                                .accessibilityLabel("Start Date")
                        }

                        HStack {
                            Text("To")
                                .font(Typography.mono())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            DatePicker("End Date", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .tint(Color.accent)
                                .accessibilityIdentifier(AccessibilityID.Export.customEndDatePicker)
                                .accessibilityLabel("End Date")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .iPadLiquidGlass()

                // MARK: - Export Options
                VStack(alignment: .leading, spacing: 14) {
                    iPadBrandLabel("Export Options")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Formats")
                            .font(Typography.mono())
                            .foregroundStyle(Color.textSecondary)
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Toggle(format.rawValue, isOn: Binding(
                                get: { advancedSettings.exportFormats.contains(format) },
                                set: { isOn in
                                    if isOn { advancedSettings.exportFormats.insert(format) }
                                    else { advancedSettings.exportFormats.remove(format) }
                                }
                            ))
                            .tint(Color.accent)
                        }
                        if advancedSettings.exportFormats.isEmpty {
                            Text("Select at least one export format.")
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.red)
                        }
                    }

                    HStack {
                        Text("Write Mode")
                            .font(Typography.mono())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Picker("", selection: $advancedSettings.writeMode) {
                            ForEach(WriteMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accent)
                        .frame(width: 180)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health Metrics")
                                .font(Typography.mono())
                                .foregroundStyle(Color.textSecondary)
                            Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Button("Configure…") {
                            showMetricSelection = true
                        }
                        .font(Typography.monoEmphasis())
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .iPadLiquidGlass()

                // MARK: - Export Progress
                if isExporting {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            iPadBrandLabel("Progress")
                            Spacer()
                            Button {
                                onCancelExport?()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                        .font(Typography.headline())
                                    Text("Stop")
                                        .font(Typography.monoEmphasis())
                                }
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
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
                            .accessibilityLabel("Stop export")
                        }

                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(exportStatusMessage)
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.textSecondary)
                        }
                        ProgressView(value: exportProgress)
                            .tint(Color.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .iPadLiquidGlass()
                }

                // MARK: - Ready / Not Ready
                if !isExporting && !canExport {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.textMuted)
                        Text(readinessMessage)
                            .font(Typography.mono())
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .iPadLiquidGlass()
                }
            }
            .padding(24)
        }
        .navigationTitle("Export")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    handlePreviewTapped()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("Preview")
                            .font(Typography.monoEmphasis())
                    }
                }
                .disabled(!canPreview || isExporting)
                .tint(Color.accent)
                .accessibilityLabel("Preview export")
                .accessibilityHint(healthKitManager.isAuthorized ? "Shows the files and contents that will be exported" : "Prompts to connect Apple Health before showing preview")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onExportTapped?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: purchaseManager.canExport ? "arrow.up.doc.fill" : "lock.fill")
                        Text(purchaseManager.canExport ? "Export Now" : "Unlock to Export")
                            .font(Typography.monoEmphasis())
                    }
                }
                .disabled(!canExport || isExporting)
                .tint(Color.accent)
                .accessibilityLabel(purchaseManager.canExport ? "Review export" : "Unlock to export")
                .accessibilityHint(purchaseManager.canExport ? "Exports health data to the selected folder" : "Opens the unlock screen")
            }
        }
        .sheet(isPresented: $showMetricSelection) {
            iPadMetricSelectionView(
                selectionState: advancedSettings.metricSelection,
                healthKitManager: healthKitManager
            )
        }
        .sheet(isPresented: $showPreview) {
            ExportPreviewView(
                startDate: previewDateRange.startDate,
                endDate: previewDateRange.endDate,
                vaultManager: vaultManager,
                settings: advancedSettings,
                destinationLabel: vaultManager.vaultURL == nil ? "iPad folder" : "iPad: \(vaultManager.vaultName)",
                destinationRootName: nil,
                dateRangePreset: dateRangePreset,
                targetType: .localFile,
                fetchHealthData: { date in
                    do {
                        return try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: advancedSettings.includeGranularData,
                            metricSelection: advancedSettings.metricSelection
                        )
                    } catch {
                        Self.logger.warning("Export preview HealthKit fetch failed for date=\(date, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            )
        }
        .alert("Adjust Health Permissions", isPresented: $showHealthPermissionsGuide) {
            Button("Open Health App") {
                if let healthURL = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(healthURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To change which health data Health.md can access:\n\n1. Tap \"Open Health App\"\n2. Tap your profile icon (top right)\n3. Tap \"Apps\"\n4. Select \"Health.md\"\n5. Toggle permissions on or off")
        }
        .alert("Finish Preview Setup", isPresented: $showPreviewRequirementsPrompt) {
            if previewNeedsHealthPermission {
                Button("Connect Apple Health") {
                    Task { try? await healthKitManager.requestAuthorization() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(previewRequirementsMessage)
        }
    }

    // MARK: - Helpers

    private var readinessMessage: String {
        if !healthKitManager.isAuthorized && vaultManager.vaultURL == nil {
            return "Connect Apple Health and choose an export folder to get started."
        } else if !healthKitManager.isAuthorized {
            return "Connect Apple Health to export."
        } else {
            return "Choose an export folder to get started."
        }
    }

    private var canPreview: Bool {
        !advancedSettings.exportFormats.isEmpty
    }

    private var previewNeedsHealthPermission: Bool {
        !healthKitManager.isAuthorized
    }

    private var previewRequirementsMessage: String {
        "To preview your export, connect Apple Health so Health.md can read your data."
    }

    private func handlePreviewTapped() {
        if previewNeedsHealthPermission {
            showPreviewRequirementsPrompt = true
        } else {
            showPreview = true
        }
    }

    private var previewDateRange: (startDate: Date, endDate: Date) {
        (startDate, endDate)
    }

    @ViewBuilder
    private func presetDateButton(_ preset: ExportDateRangePreset) -> some View {
        let isSelected = dateRangePreset == preset
        Button {
            selectDateRangePreset(preset)
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.headline())
                }
                Text(preset.title)
                    .font(Typography.monoCaption())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
        .background(
            Capsule()
                .fill(isSelected ? Color.accent.opacity(0.16) : Color.white.opacity(0.05))
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.accent.opacity(0.4) : Color.white.opacity(0.15), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier(for: preset))
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(preset.accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectDateRangePreset(_ preset: ExportDateRangePreset) {
        dateRangePreset = preset

        switch preset {
        case .custom:
            return
        case .allTime:
            Task {
                let earliestDate = await healthKitManager.findEarliestHealthDataDate()
                await MainActor.run {
                    guard dateRangePreset == .allTime else { return }
                    applyResolvedDateRange(
                        for: .allTime,
                        allTimeStartDate: earliestDate,
                        allTimeEndDate: Date()
                    )
                }
            }
        case .today, .yesterday:
            applyResolvedDateRange(for: preset)
        }
    }

    private func applyResolvedDateRange(
        for preset: ExportDateRangePreset,
        allTimeStartDate: Date? = nil,
        allTimeEndDate: Date? = nil
    ) {
        let range = preset.resolvedRange(
            currentStartDate: startDate,
            currentEndDate: endDate,
            allTimeStartDate: allTimeStartDate,
            allTimeEndDate: allTimeEndDate
        ) ?? ExportDateRangePreset.today.resolvedRange(
            currentStartDate: startDate,
            currentEndDate: endDate
        )

        guard let range else { return }
        startDate = range.startDate
        endDate = range.endDate
    }

    private func accessibilityIdentifier(for preset: ExportDateRangePreset) -> String {
        switch preset {
        case .today:
            return AccessibilityID.Export.datePresetTodayButton
        case .yesterday:
            return AccessibilityID.Export.datePresetYesterdayButton
        case .allTime:
            return AccessibilityID.Export.datePresetAllTimeButton
        case .custom:
            return AccessibilityID.Export.datePresetCustomButton
        }
    }
}

// MARK: - iPad Metric Selection View (matching macOS MacMetricSelectionView)

struct iPadMetricSelectionView: View {
    @ObservedObject var selectionState: MetricSelectionState
    @ObservedObject var healthKitManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedCategories: Set<HealthMetricCategory> = []
    @State private var showPendingApprovalAlert = false
    @State private var showMedicationAuthorizationAlert = false
    @State private var showMedicationAuthorizationErrorAlert = false
    @State private var medicationAuthorizationError = ""
    @State private var isRequestingMedicationAuthorization = false
    @State private var pendingMedicationAction: MedicationSelectionAction?

    private enum MedicationSelectionAction {
        case category
        case metric(String)
    }

    private var enabledCategoryCount: Int {
        HealthMetricCategory.allCases.filter { selectionState.isCategoryFullyEnabled($0) }.count
    }

    private var availableCategoryCount: Int {
        HealthMetricCategory.allCases.filter { !$0.isPendingAppleApproval }.count
    }

    private var filteredCategories: [HealthMetricCategory] {
        if searchText.isEmpty { return HealthMetricCategory.allCases }
        return HealthMetricCategory.allCases.filter { category in
            let metrics = HealthMetrics.byCategory[category] ?? []
            return metrics.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
                || category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func filteredMetrics(for category: HealthMetricCategory) -> [HealthMetricDefinition] {
        let metrics = HealthMetrics.byCategory[category] ?? []
        if searchText.isEmpty { return metrics }
        return metrics.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        iPadBrandLabel("Health Metrics")
                        Text("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled · \(enabledCategoryCount) of \(availableCategoryCount) categories")
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    ProgressView(value: Double(selectionState.totalEnabledCount), total: Double(selectionState.totalMetricCount))
                        .frame(width: 100)
                        .tint(Color.accent)
                }
                .padding()

                Divider()
                    .opacity(0.3)

                // Category list
                List {
                    ForEach(filteredCategories, id: \.self) { category in
                        categorySection(for: category)
                    }
                }
                .searchable(text: $searchText, prompt: "Search metrics…")

                Divider()
                    .opacity(0.3)

                // Footer with actions
                HStack {
                    Menu("Actions") {
                        Button("Select All Standard Metrics") { selectionState.selectAll() }
                        Button("Deselect All") { selectionState.deselectAll() }
                        if healthKitManager.isMedicationAuthorizationSupported {
                            Divider()
                            Button(healthKitManager.isMedicationAuthorizationRequested ? "Change Medication Access" : "Choose Medications…") {
                                Task { await requestMedicationAuthorizationAndApply(nil) }
                            }
                        }
                    }

                    Spacer()

                    Button("Done") { dismiss() }
                        .tint(Color.accent)
                        .fontWeight(.semibold)
                }
                .padding()
            }
            .navigationTitle("Health Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Permission pending", isPresented: $showPendingApprovalAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This metric requires additional Apple permission before Health.md can export it.")
            }
            .alert("Choose medications to export", isPresented: $showMedicationAuthorizationAlert) {
                Button("Choose Medications") {
                    let action = pendingMedicationAction
                    Task { await requestMedicationAuthorizationAndApply(action) }
                }
                Button("Cancel", role: .cancel) {
                    pendingMedicationAction = nil
                }
            } message: {
                Text("Apple treats medications differently from other Health data. You'll choose the individual medications Health.md may read, and exports will include only the medications you select.")
            }
            .alert("Medication access unavailable", isPresented: $showMedicationAuthorizationErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(medicationAuthorizationError)
            }
        }
    }

    @ViewBuilder
    private func categorySection(for category: HealthMetricCategory) -> some View {
        if category.isPendingAppleApproval {
            pendingCategoryRow(for: category)
        } else {
            standardCategorySection(for: category)
        }
    }

    @ViewBuilder
    private func pendingCategoryRow(for category: HealthMetricCategory) -> some View {
        Button {
            showPendingApprovalAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(Typography.monoEmphasis())
                        .foregroundStyle(Color.textPrimary)
                    Text("Pending Apple permission")
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                }

                Spacer()

                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func standardCategorySection(for category: HealthMetricCategory) -> some View {
        let metrics = filteredMetrics(for: category)
        let isExpanded = expandedCategories.contains(category) || !searchText.isEmpty

        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { newVal in
                if newVal { expandedCategories.insert(category) }
                else { expandedCategories.remove(category) }
            }
        )) {
            if category == .medications {
                medicationAuthorizationSummary
            }

            ForEach(metrics, id: \.id) { metric in
                Toggle(isOn: Binding(
                    get: { selectionState.isMetricEnabled(metric.id) },
                    set: { _ in toggleMetric(metric) }
                )) {
                    HStack {
                        Text(metric.name)
                            .font(Typography.mono())
                        if !metric.unit.isEmpty {
                            Text("(\(metric.unit))")
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
                .tint(Color.accent)
                .disabled(metric.category == .medications && !healthKitManager.isMedicationAuthorizationSupported)
                .padding(.leading, 8)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)

                Text(category.rawValue)
                    .font(Typography.monoEmphasis())

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(selectionState.enabledMetricCount(for: category))/\(selectionState.totalMetricCount(for: category))")
                        .font(Typography.monoEmphasis())
                        .foregroundStyle(Color.textMuted)
                    if category == .medications {
                        Text(medicationStatusText)
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                    }
                }

                Button {
                    toggleCategory(category)
                } label: {
                    categoryToggleIcon(for: category)
                }
                .buttonStyle(.plain)
                .disabled(category == .medications && !healthKitManager.isMedicationAuthorizationSupported)
            }
        }
    }

    private var medicationStatusText: String {
        if !healthKitManager.isMedicationAuthorizationSupported { return "iOS 26+" }
        return healthKitManager.isMedicationAuthorizationRequested ? "access selected" : "permission needed"
    }

    private var medicationAuthorizationSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(healthKitManager.isMedicationAuthorizationRequested ? "Medication access selected" : "Choose medications before exporting")
                .font(Typography.monoEmphasis())
            Text(medicationAuthorizationMessage)
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textMuted)
            if healthKitManager.isMedicationAuthorizationSupported {
                Button(healthKitManager.isMedicationAuthorizationRequested ? "Change Medication Access" : "Choose Medications") {
                    Task { await requestMedicationAuthorizationAndApply(nil) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRequestingMedicationAuthorization)
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 4)
    }

    private var medicationAuthorizationMessage: String {
        if !healthKitManager.isMedicationAuthorizationSupported {
            return "Medication export requires iOS 26 or later. Other Health metrics can still be exported."
        }
        if healthKitManager.isMedicationAuthorizationRequested {
            return "Health.md exports only the medications selected in Apple's permission sheet."
        }
        return "Medications use Apple's per-medication selector instead of the standard Health access prompt."
    }

    @ViewBuilder
    private func categoryToggleIcon(for category: HealthMetricCategory) -> some View {
        if category == .medications && !healthKitManager.isMedicationAuthorizationSupported {
            Image(systemName: "lock.circle")
                .foregroundStyle(Color.textMuted)
        } else if selectionState.isCategoryFullyEnabled(category) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
        } else if selectionState.isCategoryPartiallyEnabled(category) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(Color.warning)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.textMuted)
        }
    }

    private func toggleCategory(_ category: HealthMetricCategory) {
        guard category == .medications else {
            selectionState.toggleCategory(category)
            return
        }

        if selectionState.isCategoryFullyEnabled(category) {
            selectionState.toggleCategory(category)
            return
        }

        guard healthKitManager.isMedicationAuthorizationSupported else {
            showMedicationUnsupportedError()
            return
        }

        guard healthKitManager.isMedicationAuthorizationRequested else {
            pendingMedicationAction = .category
            showMedicationAuthorizationAlert = true
            return
        }

        selectionState.toggleCategory(category)
    }

    private func toggleMetric(_ metric: HealthMetricDefinition) {
        guard metric.category == .medications else {
            selectionState.toggleMetric(metric.id)
            return
        }

        if selectionState.isMetricEnabled(metric.id) {
            selectionState.toggleMetric(metric.id)
            return
        }

        guard healthKitManager.isMedicationAuthorizationSupported else {
            showMedicationUnsupportedError()
            return
        }

        guard healthKitManager.isMedicationAuthorizationRequested else {
            pendingMedicationAction = .metric(metric.id)
            showMedicationAuthorizationAlert = true
            return
        }

        selectionState.toggleMetric(metric.id)
    }

    @MainActor
    private func requestMedicationAuthorizationAndApply(_ action: MedicationSelectionAction?) async {
        guard healthKitManager.isMedicationAuthorizationSupported else {
            showMedicationUnsupportedError()
            return
        }

        isRequestingMedicationAuthorization = true
        defer {
            isRequestingMedicationAuthorization = false
            pendingMedicationAction = nil
        }

        do {
            try await healthKitManager.requestMedicationAuthorization(force: true)
            if let action {
                applyMedicationSelection(action)
            }
        } catch {
            medicationAuthorizationError = error.localizedDescription
            showMedicationAuthorizationErrorAlert = true
        }
    }

    private func applyMedicationSelection(_ action: MedicationSelectionAction) {
        switch action {
        case .category:
            if !selectionState.isCategoryFullyEnabled(.medications) {
                selectionState.toggleCategory(.medications)
            }
        case .metric(let metricId):
            if !selectionState.isMetricEnabled(metricId) {
                selectionState.toggleMetric(metricId)
            }
        }
    }

    private func showMedicationUnsupportedError() {
        medicationAuthorizationError = "Medication export requires iOS 26 or later. You can still export all other Health metrics."
        showMedicationAuthorizationErrorAlert = true
    }
}
