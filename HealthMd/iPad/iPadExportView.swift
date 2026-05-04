import SwiftUI
import UIKit

// MARK: - iPad Export View (matching macOS MacExportView glass card layout)

struct iPadExportView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var isExporting: Bool
    @Binding var exportProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var showFolderPicker: Bool
    let canExport: Bool
    var onCancelExport: (() -> Void)?
    var onExport: (() -> Void)?
    /// Called when the user taps "Export Now". The parent decides whether to show
    /// the export modal or the paywall.
    var onExportTapped: (() -> Void)?

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showHealthPermissionsGuide = false
    @State private var showMetricSelection = false

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
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                            Text(healthKitManager.isAuthorized
                                 ? "Ready to export health data"
                                 : "Grant access to export health data")
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        if !healthKitManager.isAuthorized {
                            Button("Connect") {
                                Task { try? await healthKitManager.requestAuthorization() }
                            }
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .buttonStyle(.bordered)
                            .tint(Color.accent)
                            .controlSize(.small)
                        } else {
                            Button("Permissions") {
                                showHealthPermissionsGuide = true
                            }
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .buttonStyle(.bordered)
                            .tint(Color.accent)
                            .controlSize(.small)
                        }
                    }

                    if !healthKitManager.isAuthorized {
                        Text("Connect Apple Health to start exporting your wellness data.")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
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
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vaultManager.vaultName)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.textPrimary)
                                Text(url.path(percentEncoded: false))
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } else {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.textMuted)
                                .font(.system(size: 16))
                            Text("No folder selected")
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Button(vaultManager.vaultURL != nil ? "Change…" : "Choose…") {
                            showFolderPicker = true
                        }
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }

                    if vaultManager.vaultURL != nil {
                        HStack {
                            Text("Subfolder")
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
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

                    HStack {
                        Text("From")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.accent)
                    }

                    HStack {
                        Text("To")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.accent)
                    }

                    HStack(spacing: 10) {
                        quickDateButton("Yesterday") {
                            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = yesterday
                            endDate = yesterday
                        }
                        quickDateButton("7 Days") {
                            endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                        }
                        quickDateButton("30 Days") {
                            endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
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
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
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
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.red)
                        }
                    }

                    HStack {
                        Text("Write Mode")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
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
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                            Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Button("Configure…") {
                            showMetricSelection = true
                        }
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Stop")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
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
                        }

                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(exportStatusMessage)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
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
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
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
                    onExportTapped?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: purchaseManager.canExport ? "arrow.up.doc.fill" : "lock.fill")
                        Text(purchaseManager.canExport ? "Export Now" : "Unlock to Export")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                .disabled(!canExport || isExporting)
                .tint(Color.accent)
            }
        }
        .sheet(isPresented: $showMetricSelection) {
            iPadMetricSelectionView(selectionState: advancedSettings.metricSelection)
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

    @ViewBuilder
    private func quickDateButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textSecondary)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - iPad Metric Selection View (matching macOS MacMetricSelectionView)

struct iPadMetricSelectionView: View {
    @ObservedObject var selectionState: MetricSelectionState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedCategories: Set<HealthMetricCategory> = []

    private var enabledCategoryCount: Int {
        HealthMetricCategory.allCases.filter { selectionState.isCategoryFullyEnabled($0) }.count
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
                        Text("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled · \(enabledCategoryCount) of \(HealthMetricCategory.allCases.count) categories")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
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
                        Button("Select All") { selectionState.selectAll() }
                        Button("Deselect All") { selectionState.deselectAll() }
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
        }
    }

    @ViewBuilder
    private func categorySection(for category: HealthMetricCategory) -> some View {
        let metrics = filteredMetrics(for: category)
        let isExpanded = expandedCategories.contains(category) || !searchText.isEmpty

        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { newVal in
                if newVal { expandedCategories.insert(category) }
                else { expandedCategories.remove(category) }
            }
        )) {
            ForEach(metrics, id: \.id) { metric in
                Toggle(isOn: Binding(
                    get: { selectionState.isMetricEnabled(metric.id) },
                    set: { _ in selectionState.toggleMetric(metric.id) }
                )) {
                    HStack {
                        Text(metric.name)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                        if !metric.unit.isEmpty {
                            Text("(\(metric.unit))")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
                .tint(Color.accent)
                .padding(.leading, 8)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)

                Text(category.rawValue)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))

                Spacer()

                Text("\(selectionState.enabledMetricCount(for: category))/\(selectionState.totalMetricCount(for: category))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textMuted)

                Button {
                    selectionState.toggleCategory(category)
                } label: {
                    if selectionState.isCategoryFullyEnabled(category) {
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
                .buttonStyle(.plain)
            }
        }
    }
}
