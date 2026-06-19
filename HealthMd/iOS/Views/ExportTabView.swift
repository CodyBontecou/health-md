import SwiftUI
import UIKit
import os.log

// MARK: - Export Tab View
// Single scrollable home for all iOS export configuration plus the export action.

struct ExportTabView: View {
    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "ExportPreview")

    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var syncService: SyncService
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @Binding var exportTargetSelection: ExportTargetSelection
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var dateRangePreset: ExportDateRangePreset
    @Binding var isExporting: Bool
    @Binding var exportProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var showFolderPicker: Bool
    let canExport: Bool
    var onCancelExport: (() -> Void)?
    let onExportTapped: () -> Void

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showHealthPermissionsGuide = false
    @State private var showPreviewRequirementsPrompt = false
    @State private var showFilenameEditor = false
    @State private var showFolderStructureEditor = false
    @State private var showSubfolderEditor = false
    @State private var showPreview = false
    @State private var showRollupHelp = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    heroHeader
                    statusBadges
                    exportTargetSection
                    dateRangeSection
                    healthDataSection
                    formatsSection
                    automationSection
                    formatOptionsSection
                    outputSection
                    pathPreviewSection
                    resetButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                floatingExportBar
                    .zIndex(1)
            }
            .toolbar(.hidden, for: .navigationBar)
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
            .alert("Finish Preview Setup", isPresented: $showPreviewRequirementsPrompt) {
                if previewNeedsHealthPermission {
                    Button("Connect Apple Health") {
                        Task { try? await healthKitManager.requestAuthorization() }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(previewRequirementsMessage)
            }
            .alert("Roll-Up Summaries", isPresented: $showRollupHelp) {
                Button("Done", role: .cancel) { }
            } message: {
                Text("\(ExportRolloutCopy.rollupSummariesHelp)\n\n\(ExportRolloutCopy.pluginCompatibilityHelp)")
            }
            .onChange(of: exportStatusMessage) { oldValue, newValue in
                if !newValue.isEmpty && newValue != oldValue {
                    UIAccessibility.post(notification: .announcement, argument: newValue)
                }
            }
        }
        .sheet(isPresented: $showFilenameEditor) {
            FilenameFormatEditor(filenameFormat: $advancedSettings.filenameFormat)
        }
        .sheet(isPresented: $showFolderStructureEditor) {
            FolderStructureEditor(
                folderStructure: $advancedSettings.folderStructure,
                organizeFormatsIntoFolders: $advancedSettings.organizeFormatsIntoFolders
            )
        }
        .sheet(isPresented: $showSubfolderEditor) {
            SubfolderEditor(
                subfolder: $vaultManager.healthSubfolder,
                onSave: { vaultManager.saveSubfolderSetting() }
            )
        }
        .sheet(isPresented: $showPreview) {
            ExportPreviewView(
                startDate: previewDateRange.startDate,
                endDate: previewDateRange.endDate,
                vaultManager: vaultManager,
                settings: advancedSettings,
                destinationLabel: previewDestinationLabel,
                destinationRootName: previewDestinationRootName,
                dateRangePreset: dateRangePreset,
                targetType: exportTargetSelection == .connectedMac ? .connectedMac : .localFile,
                fetchHealthData: { date in
                    #if DEBUG
                    if TestMode.useHealthKitExportPreviewFixtures {
                        return UITestHealthKitFixtures.exportPreviewHealthData(
                            for: date,
                            includeGranularData: advancedSettings.includeGranularData
                        )
                    }
                    #endif

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
    }

    // MARK: - Header

    private var heroHeader: some View {
        VStack(spacing: Spacing.s4) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(spacing: Spacing.s1) {
                Text("Export")
                    .font(Typography.heading24())
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)

                Text("Choose what Health.md writes from Apple Health")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.s1)
    }

    // MARK: - Status Badges

    private var statusBadges: some View {
        let badges = Group {
            CompactStatusBadge(
                icon: "heart.fill",
                title: "Health",
                statusText: healthKitManager.isAuthorized ? "Connected" : "Connect",
                isConnected: healthKitManager.isAuthorized,
                action: {
                    Task {
                        try? await healthKitManager.requestAuthorization()
                        if healthKitManager.isAuthorized {
                            showHealthPermissionsGuide = true
                        }
                    }
                }
            )
            .accessibilityIdentifier(AccessibilityID.Export.healthBadge)

            CompactStatusBadge(
                icon: "folder.fill",
                title: vaultManager.isVaultConfigured ? vaultManager.vaultName : "Folder",
                statusText: vaultBadgeStatusText,
                isConnected: vaultManager.vaultURL != nil,
                action: { showFolderPicker = true }
            )
            .accessibilityIdentifier(AccessibilityID.Export.vaultBadge)
        }

        return Group {
            if usesAccessibilityLayout {
                VStack(spacing: Spacing.md) {
                    badges
                }
            } else {
                HStack(spacing: Spacing.md) {
                    badges
                }
            }
        }
    }

    private var vaultBadgeStatusText: String {
        if vaultManager.vaultURL != nil { return "Selected" }
        if vaultManager.hasSavedVaultFolder { return "Reconnect" }
        return "Choose Folder"
    }

    // MARK: - Export Target

    private var exportTargetSection: some View {
        sectionCard(title: "Export Target") {
            VStack(spacing: Spacing.sm) {
                exportTargetOption(
                    target: .localIPhoneFolder,
                    icon: "iphone",
                    title: ExportTargetSelection.localIPhoneFolder.title,
                    subtitle: localTargetSubtitle,
                    isSelected: exportTargetSelection == .localIPhoneFolder,
                    isEnabled: true,
                    accessibilityIdentifier: AccessibilityID.Export.localTargetOption
                ) {
                    exportTargetSelection = .localIPhoneFolder
                    if vaultManager.vaultURL == nil {
                        showFolderPicker = true
                    }
                }

                Divider().background(Color.borderSubtle)

                exportTargetOption(
                    target: .connectedMac,
                    icon: "desktopcomputer",
                    title: ExportTargetSelection.connectedMac.title,
                    subtitle: macTargetSubtitle,
                    isSelected: exportTargetSelection == .connectedMac,
                    isEnabled: syncService.canExportToConnectedMac,
                    accessibilityIdentifier: AccessibilityID.Export.macTargetOption
                ) {
                    exportTargetSelection = .connectedMac
                }
            }
        }
    }

    private var localTargetSubtitle: String {
        if vaultManager.vaultURL != nil {
            return "Exports to \(vaultManager.vaultName) on this iPhone."
        }
        if vaultManager.hasSavedVaultFolder {
            return "Saved folder unavailable. Reconnect it in Files or tap to re-select."
        }
        return "Local iPhone folder. Tap to choose a folder."
    }

    private var macTargetSubtitle: String {
        if syncService.canExportToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return "Ready on Mac: \(path)"
            }
            if let name = syncService.macDestinationStatus?.destinationDisplayName {
                return "Ready on Mac: \(name)"
            }
            return syncService.macExportReadinessMessage
        }
        return macTargetUnavailableMessage
    }

    private var macTargetUnavailableMessage: String {
        guard syncService.connectionState == .connected else {
            return "No Mac connected. Open Health.md on your Mac to connect."
        }
        guard let capabilities = syncService.remoteCapabilities else {
            return syncService.macExportReadinessMessage
        }
        guard capabilities.platform == .macOS,
              capabilities.isCompatibleWithMacExportJobs else {
            return "Incompatible Mac. Update Health.md on Mac."
        }
        guard let status = syncService.macDestinationStatus else {
            return syncService.macExportReadinessMessage
        }
        if status.activeJobID != nil {
            return "Mac busy. Wait for the current export to finish."
        }
        if !status.destinationFolderSelected {
            return "No folder selected. Choose a folder on Mac."
        }
        if !status.folderAccessHealthy {
            return "Mac folder access denied. Re-select the folder on Mac."
        }
        return syncService.macExportReadinessMessage
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        sectionCard(title: "Date Range") {
            VStack(spacing: Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: Spacing.sm
                ) {
                    ForEach(ExportDateRangePreset.allCases) { preset in
                        dateRangePresetButton(preset)
                    }
                }

                if dateRangePreset == .custom {
                    Divider().background(Color.borderSubtle)

                    VStack(spacing: Spacing.md) {
                        DatePicker(
                            "Start Date",
                            selection: $startDate,
                            in: ...endDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .tint(Color.accent)
                        .accessibilityIdentifier(AccessibilityID.Export.customStartDatePicker)
                        .accessibilityHint("Select the start date for your export range")

                        Divider().background(Color.borderSubtle)

                        DatePicker(
                            "End Date",
                            selection: $endDate,
                            in: startDate...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .tint(Color.accent)
                        .accessibilityIdentifier(AccessibilityID.Export.customEndDatePicker)
                        .accessibilityHint("Select the end date for your export range")
                    }
                }
            }
        }
    }

    private var previewDateRange: (startDate: Date, endDate: Date) {
        (startDate, endDate)
    }

    private func dateRangePresetButton(_ preset: ExportDateRangePreset) -> some View {
        let isSelected = dateRangePreset == preset
        return Button {
            selectDateRangePreset(preset)
        } label: {
            HStack(spacing: Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.headline())
                }
                Text(preset.title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accent.opacity(0.18) : Color.bgSecondary)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accent.opacity(0.45) : Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - Health Data

    private var healthDataSection: some View {
        sectionCard(title: "Health Data") {
            VStack(spacing: 0) {
                inlineNavigationRow(
                    icon: "list.bullet.rectangle",
                    title: "Health Metrics",
                    subtitle: "\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) metrics enabled",
                    destination: {
                        MetricSelectionView(
                            selectionState: advancedSettings.metricSelection,
                            healthKitManager: healthKitManager
                        )
                    }
                )

                rowDivider()

                timeSeriesInlineRow
            }
        }
    }

    private var timeSeriesInlineRow: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            inlineIcon("waveform.path.ecg", isActive: advancedSettings.includeGranularData)

            VStack(alignment: .leading, spacing: Spacing.s2) {
                Toggle("Include Time-Series Data", isOn: $advancedSettings.includeGranularData)
                    .tint(Color.accent)
                    .font(.body.weight(.semibold))
                    .accessibilityHint("Includes individual timestamped samples in exports")

                Text("Adds timestamped samples for intraday charts and richer workout details.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, Spacing.s3)
    }

    // MARK: - Export Formats

    private var formatsSection: some View {
        sectionCard(title: "Export Formats") {
            VStack(spacing: 0) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Toggle(format.rawValue, isOn: Binding(
                        get: { advancedSettings.exportFormats.contains(format) },
                        set: { isOn in
                            if isOn { advancedSettings.exportFormats.insert(format) }
                            else { advancedSettings.exportFormats.remove(format) }
                        }
                    ))
                    .tint(Color.accent)
                    .font(.body.weight(.semibold))
                    .padding(.vertical, Spacing.s2)
                    .accessibilityLabel(format.rawValue)
                    .accessibilityValue(advancedSettings.exportFormats.contains(format) ? "Enabled" : "Disabled")

                    if format != ExportFormat.allCases.last {
                        rowDivider(leading: 0)
                    }
                }

                if advancedSettings.exportFormats.contains(.markdown) {
                    rowDivider(leading: 0)

                    Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                        .padding(.vertical, Spacing.s2)
                        .accessibilityHint("Adds YAML metadata at the top of markdown files")

                    rowDivider(leading: 0)

                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                        .padding(.vertical, Spacing.s2)
                        .accessibilityHint("Organizes health data under category headings")
                }

                if advancedSettings.exportFormats.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Select at least one export format.")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(Color.error)
                    .padding(.top, Spacing.s2)
                }
            }
        }
    }

    // MARK: - Automation

    private var automationSection: some View {
        sectionCard(title: "Automation") {
            VStack(spacing: 0) {
                rollupInlineControls

                rowDivider()

                NavigationLink {
                    DailyNoteInjectionView(
                        settings: advancedSettings.dailyNoteInjection,
                        metricSelection: advancedSettings.metricSelection,
                        healthSubfolder: vaultManager.healthSubfolder
                    )
                } label: {
                    inlineNavigationRowLabel(
                        icon: "note.text",
                        title: "Daily Note Injection",
                        subtitle: dailyNoteInjectionSummary,
                        isActive: advancedSettings.dailyNoteInjection.enabled,
                        badgeCount: nil
                    )
                }
                .buttonStyle(.plain)

                rowDivider()

                NavigationLink {
                    IndividualTrackingView(
                        settings: advancedSettings.individualTracking,
                        metricSelection: advancedSettings.metricSelection
                    )
                } label: {
                    inlineNavigationRowLabel(
                        icon: "doc.on.doc",
                        title: "Individual Entry Tracking",
                        subtitle: individualTrackingSummary,
                        isActive: advancedSettings.individualTracking.globalEnabled,
                        badgeCount: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rollupInlineControls: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                inlineIcon("calendar.badge.clock", isActive: advancedSettings.rollupSummariesEnabled)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Roll-Up Summaries")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(rollupDescription)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button { showRollupHelp = true } label: {
                    Image(systemName: "info.circle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How roll-up summaries work")
            }

            VStack(spacing: 0) {
                Toggle("Weekly", isOn: $advancedSettings.generateWeeklyRollups)
                    .tint(Color.accent)
                    .padding(.vertical, Spacing.s1)
                    .accessibilityHint("Generates weekly roll-up files for every selected export format")

                Toggle("Monthly", isOn: $advancedSettings.generateMonthlyRollups)
                    .tint(Color.accent)
                    .padding(.vertical, Spacing.s1)
                    .accessibilityHint("Generates monthly roll-up files for every selected export format")

                Toggle("Yearly", isOn: $advancedSettings.generateYearlyRollups)
                    .tint(Color.accent)
                    .padding(.vertical, Spacing.s1)
                    .accessibilityHint("Generates yearly roll-up files for every selected export format")
            }
            .padding(.leading, 40)
        }
        .padding(.vertical, Spacing.s3)
    }

    // MARK: - Format Options

    private var formatOptionsSection: some View {
        sectionCard(title: "Format Options") {
            VStack(spacing: 0) {
                inlineNavigationRow(
                    icon: "slider.horizontal.3",
                    title: "Format Customization",
                    subtitle: formatCustomizationSummary,
                    destination: { FormatCustomizationView(customization: advancedSettings.formatCustomization) }
                )

                rowDivider()

                writeModeInlineRow
            }
        }
    }

    private var writeModeInlineRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                inlineIcon("arrow.triangle.2.circlepath")

                VStack(alignment: .leading, spacing: 3) {
                    Text("When File Exists")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(advancedSettings.writeMode.description)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker("Write Mode", selection: $advancedSettings.writeMode) {
                ForEach(WriteMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(Color.accent)
            .padding(.leading, 40)
            .accessibilityLabel("File handling mode")
            .accessibilityValue(advancedSettings.writeMode.rawValue)
        }
        .padding(.vertical, Spacing.s3)
    }

    // MARK: - Output Settings

    private var outputSection: some View {
        sectionCard(title: "Output") {
            VStack(spacing: 0) {
                Button { showSubfolderEditor = true } label: {
                    inlineEditorRowLabel(
                        icon: "folder",
                        title: "Subfolder",
                        value: vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Subfolder: \(vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder)")
                .accessibilityHint("Double tap to change subfolder name")

                rowDivider()

                Button { showFolderStructureEditor = true } label: {
                    inlineEditorRowLabel(
                        icon: "folder.badge.gearshape",
                        title: "Folder Organization",
                        value: folderStructureDisplayText
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Folder organization: \(folderStructureDisplayText)")
                .accessibilityHint("Double tap to change folder structure")

                Text("Format folders are off by default for compatibility with existing plugins and shortcuts.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, 40)
                    .padding(.bottom, Spacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                rowDivider()

                Button { showFilenameEditor = true } label: {
                    inlineEditorRowLabel(
                        icon: "doc.text",
                        title: "Filename Format",
                        value: advancedSettings.filenameFormat
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filename format: \(advancedSettings.filenameFormat)")
                .accessibilityHint("Double tap to customize filename format")
            }
        }
    }

    // MARK: - Path Preview

    private var pathPreviewSection: some View {
        sectionCard(title: "Export Path Preview") {
            HStack(spacing: Spacing.s3) {
                inlineIcon("arrow.right")
                    .accessibilityHidden(true)

                Text(exportPath)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.Export.pathPreview)
            .accessibilityLabel("Export destination")
            .accessibilityValue(exportPath)
            .accessibilityHint("Updates based on the selected export target and file naming settings")
        }
    }

    // MARK: - Floating Export Bar

    private var floatingExportBar: some View {
        VStack(spacing: Spacing.s2) {
            if isExporting {
                VStack(spacing: Spacing.s2) {
                    if exportProgress > 0 {
                        ProgressView(value: exportProgress)
                            .progressViewStyle(.linear)
                            .tint(Color.accent)
                            .frame(maxWidth: 220)
                    }

                    if !exportStatusMessage.isEmpty {
                        Text(exportStatusMessage)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel(exportStatusMessage)
                    }
                }
                .transition(.opacity)
            }

            if !purchaseManager.isUnlocked && canExport && !isExporting {
                let remaining = purchaseManager.freeExportsRemaining
                Text(remaining == 1
                     ? "1 free export remaining"
                     : "\(remaining) free exports remaining")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityIdentifier(AccessibilityID.Export.freeExportsLabel)
                    .accessibilityLabel("\(remaining) free export\(remaining == 1 ? "" : "s") remaining before purchase required")
            }

            Group {
                if usesAccessibilityLayout {
                    VStack(spacing: Spacing.s2) {
                        floatingBarButtons
                    }
                } else {
                    HStack(spacing: Spacing.s2) {
                        floatingBarButtons
                    }
                }
            }
            .padding(Spacing.s2)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .fill(Color.bgPrimary.opacity(0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            .animation(reduceMotion ? nil : AnimationTimings.standard, value: isExporting)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.s3)
        .padding(.bottom, Spacing.s2)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.bgPrimary.opacity(0), Color.bgPrimary.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var floatingBarButtons: some View {
        if !isExporting {
            previewPillButton
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }

        pearlExportButton

        if isExporting {
            pearlStopButton
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    private var pearlExportButton: some View {
        Button(action: onExportTapped) {
            HStack(spacing: Spacing.s2) {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.bgPrimary))
                        .scaleEffect(0.7)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.footnote.weight(.semibold))
                }
                Text(LocalizedStringKey(isExporting ? "Exporting…" : "Export Data"))
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(Color.bgPrimary)
            .frame(minWidth: 132)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .fill(Color.textPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.textPrimary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .opacity(canExport ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canExport || isExporting)
        .accessibilityIdentifier(AccessibilityID.Export.exportButton)
        .accessibilityLabel(isExporting ? "Exporting" : "Export Health Data")
    }

    private var previewPillButton: some View {
        Button { handlePreviewTapped() } label: {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "eye")
                    .font(.footnote.weight(.semibold))
                Text("Preview")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .fill(Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .opacity(canPreview ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!canPreview)
        .accessibilityIdentifier(AccessibilityID.Export.previewButton)
        .accessibilityLabel("Preview Export")
        .accessibilityHint(healthKitManager.isAuthorized ? "Shows the files and contents that will be exported" : "Prompts to connect Apple Health before showing preview")
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

    private var previewDestinationLabel: String {
        switch exportTargetSelection {
        case .localIPhoneFolder:
            return vaultManager.vaultURL == nil ? "iPhone folder" : "iPhone: \(vaultManager.vaultName)"
        case .connectedMac:
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return "Mac: \(path)"
            }
            if let name = syncService.macDestinationStatus?.destinationDisplayName {
                return "Mac: \(name)"
            }
            return "Connected Mac"
        }
    }

    private var previewDestinationRootName: String? {
        switch exportTargetSelection {
        case .localIPhoneFolder:
            return nil
        case .connectedMac:
            return previewDestinationLabel
        }
    }

    private var pearlStopButton: some View {
        Button {
            onCancelExport?()
        } label: {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "stop.fill")
                    .font(.footnote.weight(.semibold))
                Text("Stop")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .fill(Color.error)
            )
            .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .shadow(color: Color.error.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Export.cancelExportButton)
        .accessibilityLabel("Stop export")
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            advancedSettings.reset()
        } label: {
            Text("Reset to Defaults")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.error)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm + 2)
                .background(
                    Capsule()
                        .fill(Color.bgPrimary)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.error.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.md)
        .accessibilityLabel("Reset to defaults")
        .accessibilityHint("Double tap to reset all export settings to default values")
    }

    // MARK: - Reusable section helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            sectionLabel(title)
            VStack(spacing: 0) {
                content()
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .fill(Color.bgPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 2, x: 0, y: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.labelUppercase())
            .foregroundStyle(Color.textMuted)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowDivider(leading: CGFloat = 40) -> some View {
        Divider()
            .background(Color.borderSubtle)
            .padding(.leading, leading)
    }

    private func inlineIcon(_ systemName: String, isActive: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(isActive ? Color.accent : Color.textSecondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .fill(isActive ? Color.selectedBackground : Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isActive ? Color.accent.opacity(0.35) : Color.borderSubtle, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func inlineNavigationRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool = false,
        badgeCount: Int? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            inlineNavigationRowLabel(
                icon: icon,
                title: title,
                subtitle: subtitle,
                isActive: isActive,
                badgeCount: badgeCount
            )
        }
        .buttonStyle(.plain)
    }

    private func inlineNavigationRowLabel(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool,
        badgeCount: Int?
    ) -> some View {
        HStack(spacing: Spacing.s3) {
            inlineIcon(icon, isActive: isActive)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.s2) {
                    Text(LocalizedStringKey(title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    if let badgeCount {
                        Text("\(badgeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.bgPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accent))
                    }
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if isActive {
                Text("On")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.selectedBackground))
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
        }
        .padding(.vertical, Spacing.s3)
        .contentShape(Rectangle())
    }

    private func inlineEditorRowLabel(icon: String, title: String, value: String) -> some View {
        HStack(spacing: Spacing.s3) {
            inlineIcon(icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(value)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "pencil")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
        }
        .padding(.vertical, Spacing.s3)
        .contentShape(Rectangle())
    }

    private func exportTargetOption(
        target: ExportTargetSelection,
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        isEnabled: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s3) {
                inlineIcon(icon, isActive: isSelected)
                    .foregroundStyle(isEnabled ? (isSelected ? Color.accent : Color.textSecondary) : Color.textMuted)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(isEnabled ? Color.textSecondary : Color.textMuted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Spacing.s2)

                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.bgPrimary.opacity(0.75)))
                        .overlay(Capsule().strokeBorder(Color.accent.opacity(0.24), lineWidth: 1))
                        .accessibilityLabel("Selected")
                } else if !isEnabled {
                    Text("Unavailable")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.bgSecondary))
                        .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
                } else {
                    Image(systemName: "circle")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.selectedBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Color.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .opacity(isEnabled || isSelected ? 1 : 0.62)
            .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(target.title): \(subtitle)")
        .accessibilityValue(isSelected ? "Selected" : (isEnabled ? "Available" : "Unavailable"))
        .accessibilityHint(isEnabled ? "Double tap to select this export target" : subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Computed summaries

    private var rollupDescription: String {
        guard advancedSettings.rollupSummariesEnabled else {
            return "Off · Enable a period to write summary files."
        }
        let periods = advancedSettings.enabledRollupPeriods.map { $0.displayName }.joined(separator: " · ")
        let formatCount = advancedSettings.exportFormats.count
        if formatCount == 0 {
            return "\(periods) · Select an export format first."
        }
        let formatLabel = formatCount == 1 ? "1 format" : "\(formatCount) formats"
        return "\(periods) · \(formatLabel)"
    }

    private var formatCustomizationSummary: String {
        let fc = advancedSettings.formatCustomization
        var parts: [String] = []
        parts.append(fc.dateFormat.format(date: Date()))
        parts.append(fc.unitPreference.rawValue)
        parts.append(fc.timeFormat == .hour12 || fc.timeFormat == .hour12WithSeconds ? "12h" : "24h")
        return parts.joined(separator: " · ")
    }

    private var dailyNoteInjectionSummary: String {
        let dni = advancedSettings.dailyNoteInjection
        guard dni.enabled else { return "Disabled" }
        let path = dni.previewPath(for: Date())
        let count = advancedSettings.metricSelection.totalEnabledCount
        if count == 0 { return "Enabled · No metrics selected" }
        return "Enabled · \(count) metrics · \(path)"
    }

    private var individualTrackingSummary: String {
        let it = advancedSettings.individualTracking
        if !it.globalEnabled { return "Disabled" }
        let count = it.totalEnabledCount
        if count == 0 {
            return String(localized: "Enabled · No metrics selected", comment: "Individual tracking with no metrics")
        }
        return String(localized: "Enabled · \(count) metrics", comment: "Individual tracking metric count")
    }

    private var folderStructureDisplayText: String {
        let dateFolders = advancedSettings.folderStructure.isEmpty ? "Flat (no date subfolders)" : advancedSettings.folderStructure
        if advancedSettings.organizeFormatsIntoFolders {
            return "File type folders / \(dateFolders)"
        }
        return advancedSettings.folderStructure.isEmpty ? "Flat (no subfolders)" : advancedSettings.folderStructure
    }

    private var formatExtensionsList: String {
        advancedSettings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { $0.fileExtension }
            .joined(separator: ",")
    }

    private var exportPath: String {
        switch exportTargetSelection {
        case .localIPhoneFolder:
            return formattedExportPath(rootName: vaultManager.vaultName)
        case .connectedMac:
            return formattedExportPath(rootName: macDestinationRootName)
        }
    }

    private var macDestinationRootName: String {
        if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
            return "Mac: \(path)"
        }
        if let name = syncService.macDestinationStatus?.destinationDisplayName {
            return "Mac: \(name)"
        }
        if let peerName = syncService.connectedPeerName {
            return "Mac: \(peerName)"
        }
        return "Mac: No folder selected"
    }

    private func formattedExportPath(rootName: String) -> String {
        let dateRange = previewDateRange
        let startDate = dateRange.startDate
        let endDate = dateRange.endDate
        let subfolder = vaultManager.healthSubfolder
        let subfolderPath = subfolder.isEmpty ? "" : subfolder + "/"
        let fileExtension = advancedSettings.primaryFormat.fileExtension
        let formatCount = advancedSettings.exportFormats.count

        let dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let totalFiles = (dayCount + 1) * max(formatCount, 1)

        if dayCount == 0 {
            let primaryFormat = advancedSettings.primaryFormat
            let folderPath = advancedSettings.formatFolderPath(for: startDate, format: primaryFormat).map { $0 + "/" } ?? ""
            let filename = advancedSettings.formatFilename(for: startDate)
            let primaryFilename = advancedSettings.filename(for: startDate, format: primaryFormat)
            if formatCount > 1 {
                if advancedSettings.organizeFormatsIntoFolders {
                    let groupedFolderPreview = advancedSettings.folderStructure.isEmpty ? "{format}/" : "{format}/…/"
                    return "\(rootName)/\(subfolderPath)\(groupedFolderPreview)\(filename).{\(formatExtensionsList)} (\(formatCount) files)"
                }
                return "\(rootName)/\(subfolderPath)\(folderPath)\(filename).{\(formatExtensionsList)} (\(formatCount) files)"
            }
            return "\(rootName)/\(subfolderPath)\(folderPath)\(primaryFilename)"
        } else {
            let startFilename = advancedSettings.formatFilename(for: startDate)
            let endFilename = advancedSettings.formatFilename(for: endDate)
            if advancedSettings.organizeFormatsIntoFolders || !advancedSettings.folderStructure.isEmpty {
                let folderDescription = advancedSettings.organizeFormatsIntoFolders ? "format/date folders" : "date folders"
                return "\(rootName)/\(subfolderPath).../{files} (\(totalFiles) files in \(folderDescription))"
            } else {
                return "\(rootName)/\(subfolderPath)\(startFilename).\(fileExtension) to \(endFilename).\(fileExtension) (\(totalFiles) files)"
            }
        }
    }
}
