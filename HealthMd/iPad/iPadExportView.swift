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
    @State private var showFormatHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HealthMdPageHeader(
                    title: "Export",
                    subtitle: "Choose what Health.md writes from Apple Health"
                )

                // MARK: - Setup Status
                HStack(alignment: .top, spacing: Spacing.s3) {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        HStack(spacing: Spacing.s2) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(healthKitManager.isAuthorized ? Color.success : Color.textMuted)
                                .accessibilityHidden(true)
                            Text("Health")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(healthKitManager.isAuthorized ? "Connected" : "Connect")
                                .font(Typography.label())
                                .foregroundStyle(healthKitManager.isAuthorized ? Color.success : Color.accent)
                                .geistPill(tint: healthKitManager.isAuthorized ? Color.success : Color.accent)
                        }

                        Text(healthKitManager.isAuthorized ? "Ready to export Apple Health data" : "Grant access to export health data")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)

                        Button(healthKitManager.isAuthorized ? "Permissions" : "Connect") {
                            Task {
                                let outcome = try? await healthKitManager.requestAuthorization()
                                if outcome == .unnecessary {
                                    showHealthPermissionsGuide = true
                                }
                            }
                        }
                        .font(Typography.bodyEmphasis())
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        HStack(spacing: Spacing.s2) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(vaultManager.vaultURL == nil ? Color.textMuted : Color.accent)
                                .accessibilityHidden(true)
                            Text(vaultManager.vaultURL == nil ? "Folder" : vaultManager.vaultName)
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(vaultManager.vaultURL == nil ? "Choose" : "Selected")
                                .font(Typography.label())
                                .foregroundStyle(vaultManager.vaultURL == nil ? Color.accent : Color.success)
                                .geistPill(tint: vaultManager.vaultURL == nil ? Color.accent : Color.success)
                        }

                        Text(vaultManager.vaultURL?.path(percentEncoded: false) ?? "Choose where Health.md writes exports")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button(vaultManager.vaultURL != nil ? "Change…" : "Choose Folder") {
                            showFolderPicker = true
                        }
                        .font(Typography.bodyEmphasis())
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }

                // MARK: - Export Target
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Export Target")

                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "ipad")
                            .foregroundStyle(Color.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Local iPad Folder")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text("Exports to the folder selected above, with optional subfolders and file organization.")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        Text("Selected")
                            .font(Typography.label())
                            .foregroundStyle(Color.accent)
                            .geistPill(tint: Color.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Date Range
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Date Range")

                    HStack(spacing: Spacing.s2) {
                        ForEach(ExportDateRangePreset.allCases) { preset in
                            presetDateButton(preset)
                        }
                    }

                    if dateRangePreset == .custom {
                        Divider().background(Color.borderSubtle)

                        HStack {
                            Text("From")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            DatePicker("Start Date", selection: $startDate, in: ...endDate, displayedComponents: .date)
                                .labelsHidden()
                                .tint(Color.accent)
                                .accessibilityIdentifier(AccessibilityID.Export.customStartDatePicker)
                                .accessibilityLabel("Start Date")
                        }

                        HStack {
                            Text("To")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
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
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Health Data
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Health Data")

                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(Color.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Health Metrics")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) metrics enabled")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        Button("Configure…") {
                            showMetricSelection = true
                        }
                        .font(Typography.bodyEmphasis())
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }

                    Divider().background(Color.borderSubtle)

                    Toggle(isOn: $advancedSettings.includeGranularData) {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Lossless Health Records")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text("Retains every selected HealthKit source record alongside daily summaries, including source UUIDs, exact timestamps, provenance, metadata, and detailed series. Files may be much larger. Turn this off for summary-only exports.")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    .tint(Color.accent)
                    .accessibilityLabel("Lossless Health Records")
                    .accessibilityHint("Retains every selected HealthKit source record alongside daily summaries, including source UUIDs, exact timestamps, provenance, metadata, and detailed series. Files may be much larger. Turn this off for summary-only exports.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Export Formats
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    HStack(spacing: Spacing.s2) {
                        iPadBrandLabel("Export Formats")
                        Spacer()
                        Button { showFormatHelp = true } label: {
                            Image(systemName: "info.circle")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textMuted)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("How export formats work")
                    }

                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Toggle(format.rawValue, isOn: Binding(
                            get: { advancedSettings.exportFormats.contains(format) },
                            set: { isOn in
                                if isOn { advancedSettings.exportFormats.insert(format) }
                                else { advancedSettings.exportFormats.remove(format) }
                            }
                        ))
                        .tint(Color.accent)
                        .font(Typography.bodyEmphasis())
                    }

                    if !advancedSettings.exportFormats.isEmpty {
                        Divider().background(Color.borderSubtle)
                        Toggle("Zip Export Files", isOn: $advancedSettings.archiveExportFiles)
                            .tint(Color.accent)
                    }

                    if advancedSettings.exportFormats.contains(.markdown) {
                        Divider().background(Color.borderSubtle)
                        Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                            .tint(Color.accent)
                        Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                            .tint(Color.accent)
                    }

                    if advancedSettings.exportFormats.isEmpty {
                        Text("Select at least one export format.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Automation
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Automation")

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Roll-Up Summaries")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                        Text("Generate weekly, monthly, or yearly summary files for every selected export format.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)

                        Toggle("Weekly", isOn: $advancedSettings.generateWeeklyRollups)
                            .tint(Color.accent)
                        Toggle("Monthly", isOn: $advancedSettings.generateMonthlyRollups)
                            .tint(Color.accent)
                        Toggle("Yearly", isOn: $advancedSettings.generateYearlyRollups)
                            .tint(Color.accent)
                        Toggle("Summary files only", isOn: $advancedSettings.summaryOnlyExport)
                            .tint(Color.accent)
                            .disabled(!advancedSettings.rollupSummariesEnabled)
                        Text("Skips daily files when at least one roll-up period is enabled.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                    }

                    Divider().background(Color.borderSubtle)

                    Toggle(isOn: $advancedSettings.dailyNoteInjection.enabled) {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Daily Note Injection")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(advancedSettings.dailyNoteInjection.enabled ? "Enabled" : "Disabled")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    .tint(Color.accent)

                    Divider().background(Color.borderSubtle)

                    Toggle(isOn: $advancedSettings.individualTracking.globalEnabled) {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Individual Entry Tracking")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(advancedSettings.individualTracking.globalEnabled ? "\(advancedSettings.individualTracking.totalEnabledCount) metrics selected" : "Disabled")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    .tint(Color.accent)

                    if advancedSettings.individualTracking.globalEnabled {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .font(Typography.body())
                            .textFieldStyle(.roundedBorder)
                        Toggle("Organize individual entries by category", isOn: $advancedSettings.individualTracking.useCategoryFolders)
                            .tint(Color.accent)
                        if advancedSettings.individualTracking.totalEnabledCount == 0 {
                            Text("No metrics selected — individual entries won’t be created until you select metrics to track.")
                                .font(Typography.caption())
                                .foregroundStyle(Color.warning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Format Options
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Format Options")

                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Format Customization")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text("Dates, times, units, and Markdown output style.")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                    }

                    Picker("Date Format", selection: $advancedSettings.formatCustomization.dateFormat) {
                        ForEach(DateFormatPreference.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .tint(Color.accent)

                    Picker("Time Format", selection: $advancedSettings.formatCustomization.timeFormat) {
                        ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .tint(Color.accent)

                    Picker("Unit System", selection: $advancedSettings.formatCustomization.unitPreference) {
                        ForEach(UnitPreference.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .tint(Color.accent)

                    if advancedSettings.exportFormats.contains(.markdown) {
                        Divider().background(Color.borderSubtle)

                        Picker("Markdown Style", selection: $advancedSettings.formatCustomization.markdownTemplate.style) {
                            ForEach(MarkdownTemplateStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .tint(Color.accent)

                        Picker("Header Level", selection: $advancedSettings.formatCustomization.markdownTemplate.sectionHeaderLevel) {
                            Text("# H1").tag(1)
                            Text("## H2").tag(2)
                            Text("### H3").tag(3)
                        }
                        .tint(Color.accent)

                        Toggle("Use Emoji in Headers", isOn: $advancedSettings.formatCustomization.markdownTemplate.useEmoji)
                            .tint(Color.accent)
                        Toggle("Include Summary", isOn: $advancedSettings.formatCustomization.markdownTemplate.includeSummary)
                            .tint(Color.accent)
                    }

                    Divider().background(Color.borderSubtle)
                    iPadBrandLabel("Placeholder Fields")
                    iPadPlaceholderFieldsView(config: advancedSettings.formatCustomization.frontmatterConfig)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Output
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Output")

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Subfolder")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                        TextField("Health", text: $vaultManager.healthSubfolder)
                            .font(Typography.body())
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: vaultManager.healthSubfolder) {
                                vaultManager.saveSubfolderSetting()
                            }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Folder Organization")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                        TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                            .font(Typography.body())
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Organize by File Type", isOn: $advancedSettings.organizeFormatsIntoFolders)
                        .tint(Color.accent)

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Filename Format")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                        TextField("{date}", text: $advancedSettings.filenameFormat)
                            .font(Typography.body())
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Export Path Preview
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Export Path Preview")
                    let date = Date()
                    let format = advancedSettings.primaryFormat
                    let filename = advancedSettings.filename(for: date, format: format)
                    let path = advancedSettings.formatFolderPath(for: date, format: format).map { "\($0)/\(filename)" } ?? filename
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(Color.accent)
                            .accessibilityHidden(true)
                        Text(path)
                            .font(Typography.monoEmphasis())
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Reset Export Configuration
                Button(role: .destructive) {
                    advancedSettings.reset()
                } label: {
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: "arrow.counterclockwise")
                            .accessibilityHidden(true)
                        Text("Reset Export Configuration")
                            .font(Typography.bodyEmphasis())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.error)

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
                                        .font(Typography.bodyEmphasis())
                                }
                                .foregroundStyle(Color.error)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.error.opacity(0.15))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.error.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop export")
                        }

                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(exportStatusMessage)
                                .font(Typography.caption())
                                .foregroundStyle(Color.textSecondary)
                        }
                        ProgressView(value: exportProgress)
                            .tint(Color.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }

                // MARK: - Ready / Not Ready
                if !isExporting && !canExport {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.textMuted)
                        Text(readinessMessage)
                            .font(Typography.body())
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s8)
            .iPadContentColumn()
        }
        .scrollIndicators(.hidden)
        .iPadPageBackground()
        .navigationTitle("Export")
        .iPadHiddenSystemNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    handlePreviewTapped()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("Preview")
                            .font(Typography.bodyEmphasis())
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
                            .font(Typography.bodyEmphasis())
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
        .sheet(isPresented: $showFormatHelp) {
            ExportFormatHelpSheet(showJSONTip: !advancedSettings.exportFormats.contains(.json))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                },
                requestHealthAuthorization: {
                    try await healthKitManager.requestAuthorization()
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
                    .font(Typography.caption())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentSubtle : Color.bgSecondary)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.accent.opacity(0.35) : Color.borderSubtle, lineWidth: 1)
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
    @State private var showVisionAuthorizationErrorAlert = false
    @State private var visionAuthorizationError = ""

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
                HealthMdPageHeader(
                    title: "Health Metrics",
                    subtitle: "\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled · \(enabledCategoryCount) of \(availableCategoryCount) categories"
                ) {
                    ProgressView(value: Double(selectionState.totalEnabledCount), total: Double(selectionState.totalMetricCount))
                        .frame(maxWidth: 220)
                        .tint(Color.accent)
                }
                .padding(Spacing.s6)

                Divider()
                    .background(Color.borderSubtle)

                // Category list
                List {
                    ForEach(filteredCategories, id: \.self) { category in
                        categorySection(for: category)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bgPrimary)
                .searchable(text: $searchText, prompt: "Search metrics…")

                Divider()
                    .background(Color.borderSubtle)

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
                        if healthKitManager.isVisionAuthorizationSupported {
                            Divider()
                            Button(healthKitManager.isVisionAuthorizationRequested ? "Change Vision Prescription Access" : "Choose Vision Prescriptions…") {
                                Task { await requestVisionAuthorizationAndApply(nil) }
                            }
                        }
                    }

                    Spacer()

                    Button("Done") { dismiss() }
                        .tint(Color.accent)
                        .fontWeight(.semibold)
                }
                .padding(Spacing.s4)
                .background(Color.bgPrimary)
            }
            .iPadPageBackground()
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
            .alert("Vision prescription access unavailable", isPresented: $showVisionAuthorizationErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(visionAuthorizationError)
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
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                    Text("Pending Apple permission")
                        .font(Typography.caption())
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
                            .font(Typography.body())
                        if !metric.selectionDetail.isEmpty {
                            Text("(\(metric.selectionDetail))")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
                .tint(Color.accent)
                .disabled(
                    !metric.availability.isAvailableOnCurrentPlatform ||
                        (metric.category == .medications && !healthKitManager.isMedicationAuthorizationSupported) ||
                        (metric.category == .vision && !healthKitManager.isVisionAuthorizationSupported)
                )
                .padding(.leading, 8)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)

                Text(category.rawValue)
                    .font(Typography.bodyEmphasis())

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(selectionState.enabledMetricCount(for: category))/\(selectionState.totalMetricCount(for: category))")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textMuted)
                    if category == .medications {
                        Text(medicationStatusText)
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                }

                Button {
                    toggleCategory(category)
                } label: {
                    categoryToggleIcon(for: category)
                }
                .buttonStyle(.plain)
                .disabled(
                    (category == .medications && !healthKitManager.isMedicationAuthorizationSupported) ||
                    (category == .vision && !healthKitManager.isVisionAuthorizationSupported)
                )
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
                .font(Typography.bodyEmphasis())
            Text(medicationAuthorizationMessage)
                .font(Typography.caption())
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
        if category == .vision {
            if selectionState.isCategoryFullyEnabled(category) {
                selectionState.toggleCategory(category)
            } else {
                Task { await requestVisionAuthorizationAndApply(.category) }
            }
            return
        }
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
        if metric.category == .vision {
            if selectionState.isMetricEnabled(metric.id) {
                selectionState.toggleMetric(metric.id)
            } else {
                Task { await requestVisionAuthorizationAndApply(.metric(metric.id)) }
            }
            return
        }
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
    private func requestVisionAuthorizationAndApply(_ action: MedicationSelectionAction?) async {
        guard healthKitManager.isVisionAuthorizationSupported else {
            visionAuthorizationError = "Vision prescription access requires a supported iOS runtime."
            showVisionAuthorizationErrorAlert = true
            return
        }
        do {
            try await healthKitManager.requestVisionPrescriptionAuthorization(force: true)
            if let action {
                switch action {
                case .category:
                    if !selectionState.isCategoryFullyEnabled(.vision) {
                        selectionState.toggleCategory(.vision)
                    }
                case .metric(let metricID):
                    if !selectionState.isMetricEnabled(metricID) {
                        selectionState.toggleMetric(metricID)
                    }
                }
            }
        } catch {
            let nsError = error as NSError
            visionAuthorizationError = "Apple's vision prescription selector did not complete (\(nsError.domain), code \(nsError.code))."
            showVisionAuthorizationErrorAlert = true
        }
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
