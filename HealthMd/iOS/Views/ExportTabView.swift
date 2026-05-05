import SwiftUI
import UIKit

// MARK: - Export Tab View
// Single scrollable home for all iOS export configuration plus the export action.

struct ExportTabView: View {
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
    let onExportTapped: () -> Void

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showHealthPermissionsGuide = false
    @State private var showFilenameEditor = false
    @State private var showFolderStructureEditor = false
    @State private var showSubfolderEditor = false
    @State private var showPreview = false
    @State private var pearlPulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    heroHeader
                    statusBadges
                    dateRangeSection
                    metricsRow
                    formatsSection
                    timeSeriesSection
                    formatCustomizationRow
                    dailyNoteInjectionRow
                    individualTrackingRow
                    if advancedSettings.individualTracking.globalEnabled {
                        IndividualTrackingExportPreview(settings: advancedSettings.individualTracking)
                    }
                    outputSection
                    writeModeSection
                    pathPreviewSection
                    resetButton
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
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
            FolderStructureEditor(folderStructure: $advancedSettings.folderStructure)
        }
        .sheet(isPresented: $showSubfolderEditor) {
            SubfolderEditor(
                subfolder: $vaultManager.healthSubfolder,
                onSave: { vaultManager.saveSubfolderSetting() }
            )
        }
        .sheet(isPresented: $showPreview) {
            ExportPreviewView(
                startDate: startDate,
                endDate: endDate,
                vaultManager: vaultManager,
                settings: advancedSettings,
                fetchHealthData: { date in
                    try? await healthKitManager.fetchHealthData(
                        for: date,
                        includeGranularData: advancedSettings.includeGranularData
                    )
                }
            )
        }
    }

    // MARK: - Header

    private var heroHeader: some View {
        VStack(spacing: Spacing.sm) {
            Text("EXPORT")
                .font(Typography.labelUppercase())
                .foregroundStyle(Color.textMuted)
                .tracking(3)

            ZStack {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .blur(radius: 18)
                    .opacity(0.5)
                    .accessibilityHidden(true)

                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.accent.opacity(0.4), radius: 16, x: 0, y: 8)
            }
            .padding(.top, Spacing.xs)

            Text("Configure your export")
                .font(Typography.bodyLarge())
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Badges

    private var statusBadges: some View {
        HStack(spacing: Spacing.md) {
            CompactStatusBadge(
                icon: "heart.fill",
                title: "Health",
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
                title: vaultManager.vaultURL != nil ? vaultManager.vaultName : "Vault",
                isConnected: vaultManager.vaultURL != nil,
                action: { showFolderPicker = true }
            )
            .accessibilityIdentifier(AccessibilityID.Export.vaultBadge)
        }
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        sectionCard(title: "DATE RANGE") {
            VStack(spacing: Spacing.md) {
                DatePicker(
                    "Start Date",
                    selection: $startDate,
                    in: ...endDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(Color.accent)
                .colorScheme(.dark)
                .accessibilityHint("Select the start date for your export range")

                Divider().background(Color.white.opacity(0.08))

                DatePicker(
                    "End Date",
                    selection: $endDate,
                    in: startDate...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(Color.accent)
                .colorScheme(.dark)
                .accessibilityHint("Select the end date for your export range")
            }
        }
    }

    // MARK: - Health Metrics

    private var metricsRow: some View {
        navigationRow(
            icon: "list.bullet.rectangle",
            title: "Health Metrics",
            subtitle: "\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) metrics enabled",
            destination: { MetricSelectionView(selectionState: advancedSettings.metricSelection) }
        )
    }

    // MARK: - Export Formats

    private var formatsSection: some View {
        sectionCard(title: "EXPORT FORMATS") {
            VStack(spacing: Spacing.sm) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Toggle(format.rawValue, isOn: Binding(
                        get: { advancedSettings.exportFormats.contains(format) },
                        set: { isOn in
                            if isOn { advancedSettings.exportFormats.insert(format) }
                            else { advancedSettings.exportFormats.remove(format) }
                        }
                    ))
                    .tint(Color.accent)
                    .accessibilityLabel(format.rawValue)
                    .accessibilityValue(advancedSettings.exportFormats.contains(format) ? "Enabled" : "Disabled")
                }

                if advancedSettings.exportFormats.contains(.markdown) {
                    Divider().background(Color.white.opacity(0.08))

                    Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                        .accessibilityHint("Adds YAML metadata at the top of markdown files")

                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                        .accessibilityHint("Organizes health data under category headings")
                }

                if advancedSettings.exportFormats.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text("Select at least one export format.")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(Color.red)
                    .padding(.top, Spacing.xs)
                } else {
                    Text(formatDescription)
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Time-Series

    private var timeSeriesSection: some View {
        sectionCard(title: "TIME-SERIES DATA") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle("Include Time-Series Data", isOn: $advancedSettings.includeGranularData)
                    .tint(Color.accent)
                    .accessibilityHint("Includes individual timestamped samples in exports")

                Text("Include individual timestamped samples (sleep stages, heart rate, blood oxygen) so intraday graphs can be reconstructed.")
                    .font(.footnote)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: - Format Customization

    private var formatCustomizationRow: some View {
        navigationRow(
            icon: "slider.horizontal.3",
            title: "Format Customization",
            subtitle: formatCustomizationSummary,
            destination: { FormatCustomizationView(customization: advancedSettings.formatCustomization) }
        )
    }

    // MARK: - Daily Note Injection

    private var dailyNoteInjectionRow: some View {
        NavigationLink {
            DailyNoteInjectionView(
                settings: advancedSettings.dailyNoteInjection,
                metricSelection: advancedSettings.metricSelection,
                healthSubfolder: vaultManager.healthSubfolder
            )
        } label: {
            navigationRowLabel(
                icon: "note.text",
                title: "Daily Note Injection",
                subtitle: dailyNoteInjectionSummary,
                isActive: advancedSettings.dailyNoteInjection.enabled,
                badgeCount: advancedSettings.dailyNoteInjection.enabled ? advancedSettings.metricSelection.totalEnabledCount : nil
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Individual Entry Tracking

    private var individualTrackingRow: some View {
        NavigationLink {
            IndividualTrackingView(
                settings: advancedSettings.individualTracking,
                metricSelection: advancedSettings.metricSelection
            )
        } label: {
            navigationRowLabel(
                icon: "doc.on.doc",
                title: "Individual Entry Tracking",
                subtitle: individualTrackingSummary,
                isActive: advancedSettings.individualTracking.globalEnabled,
                badgeCount: (advancedSettings.individualTracking.globalEnabled && advancedSettings.individualTracking.totalEnabledCount > 0)
                    ? advancedSettings.individualTracking.totalEnabledCount
                    : nil
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Output Settings

    private var outputSection: some View {
        VStack(spacing: Spacing.md) {
            sectionLabel("OUTPUT")

            Button { showSubfolderEditor = true } label: {
                editorRowLabel(
                    icon: "folder",
                    title: "Subfolder",
                    value: vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Subfolder: \(vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder)")
            .accessibilityHint("Double tap to change subfolder name")

            Button { showFolderStructureEditor = true } label: {
                editorRowLabel(
                    icon: "folder.badge.gearshape",
                    title: "Folder Organization",
                    value: folderStructureDisplayText
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Folder organization: \(folderStructureDisplayText)")
            .accessibilityHint("Double tap to change folder structure")

            Button { showFilenameEditor = true } label: {
                editorRowLabel(
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

    // MARK: - Write Mode

    private var writeModeSection: some View {
        sectionCard(title: "WHEN FILE EXISTS") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color.accent)
                .accessibilityLabel("File handling mode")
                .accessibilityValue(advancedSettings.writeMode.rawValue)

                Text(advancedSettings.writeMode.description)
                    .font(.footnote)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: - Path Preview

    private var pathPreviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel("EXPORT PATH PREVIEW")

            HStack(spacing: Spacing.sm) {
                ZStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accent)
                        .blur(radius: 4)
                        .opacity(0.5)
                        .accessibilityHidden(true)

                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accent)
                }
                .font(.system(size: 16, weight: .medium))

                Text(exportPath)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Export destination: \(exportPath)")
        }
    }

    // MARK: - Floating Export Bar

    private var floatingExportBar: some View {
        VStack(spacing: 8) {
            if isExporting && exportProgress > 0 {
                ProgressView(value: exportProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.accent)
                    .frame(maxWidth: 200)
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

            HStack(spacing: 10) {
                if !isExporting {
                    previewPillButton
                        .transition(.scale.combined(with: .opacity))
                }

                pearlExportButton

                if isExporting {
                    pearlStopButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(AnimationTimings.standard, value: isExporting)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pearlPulse = true
            }
        }
    }

    private var pearlExportButton: some View {
        Button(action: onExportTapped) {
            HStack(spacing: 6) {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.textPrimary))
                        .scaleEffect(0.7)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(LocalizedStringKey(isExporting ? "Exporting…" : "Export"))
                    .font(.callout.weight(.semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .modifier(LiquidGlassCapsuleModifier(tint: nil, isInteractive: false))
            .contentShape(Capsule())
            .opacity(canExport ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!canExport || isExporting)
        .accessibilityIdentifier(AccessibilityID.Export.exportButton)
        .accessibilityLabel(isExporting ? "Exporting" : "Export Health Data")
    }

    private var previewPillButton: some View {
        Button { showPreview = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 13, weight: .semibold))
                Text("Preview")
                    .font(.callout.weight(.semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .modifier(LiquidGlassCapsuleModifier(tint: nil, isInteractive: false))
            .contentShape(Capsule())
            .opacity(canPreview ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!canPreview)
        .accessibilityIdentifier(AccessibilityID.Export.previewButton)
        .accessibilityLabel("Preview Export")
        .accessibilityHint("Shows the files and contents that will be exported")
    }

    private var canPreview: Bool {
        !advancedSettings.exportFormats.isEmpty && healthKitManager.isAuthorized
    }

    private var pearlStopButton: some View {
        Button {
            onCancelExport?()
        } label: {
            pearl(
                icon: "stop.fill",
                iconColor: .white,
                fill: Color.red,
                isLoading: false,
                shouldPulse: false
            )
            .padding(5)
            .modifier(LiquidGlassCapsuleModifier(tint: nil, isInteractive: false))
            .contentShape(Capsule())
            .shadow(color: Color.red.opacity(0.2), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Export.cancelExportButton)
        .accessibilityLabel("Stop export")
    }

    @ViewBuilder
    private func pearl(
        icon: String,
        iconColor: Color,
        fill: Color,
        isLoading: Bool,
        shouldPulse: Bool
    ) -> some View {
        ZStack {
            // Soft accent halo — breathes when ready
            Circle()
                .fill(fill)
                .frame(width: 38, height: 38)
                .blur(radius: 16)
                .opacity(shouldPulse ? (pearlPulse ? 0.45 : 0.22) : 0.18)
                .scaleEffect(shouldPulse && pearlPulse ? 1.14 : 1.0)

            // The pearl itself — a tinted dome with specular highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [fill.opacity(0.88), fill.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .overlay(
                    // Top-left specular highlight
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.32), .clear],
                                center: UnitPoint(x: 0.3, y: 0.25),
                                startRadius: 0,
                                endRadius: 14
                            )
                        )
                        .frame(width: 30, height: 30)
                )

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: iconColor))
                    .scaleEffect(0.6)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: 38, height: 38)
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            advancedSettings.reset()
        } label: {
            Text("Reset to Defaults")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.red)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm + 2)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel(title)
            VStack(spacing: 0) {
                content()
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.textMuted)
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func navigationRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            navigationRowLabel(
                icon: icon,
                title: title,
                subtitle: subtitle,
                isActive: false,
                badgeCount: nil
            )
        }
        .buttonStyle(.plain)
    }

    private func navigationRowLabel(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool,
        badgeCount: Int?
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    if let badgeCount {
                        Text("\(badgeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
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
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accent)
                    .font(.system(size: 16))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func editorRowLabel(icon: String, title: String, value: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(value)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Computed summaries

    private var formatDescription: LocalizedStringKey {
        if advancedSettings.exportFormats.count > 1 {
            return "One file per selected format will be written for each exported date."
        }
        switch advancedSettings.primaryFormat {
        case .markdown:
            return "Human-readable format perfect for Obsidian. Includes headers, lists, and frontmatter metadata."
        case .obsidianBases:
            return "Optimized for Obsidian Bases. All metrics are stored as frontmatter properties for querying, filtering, and sorting."
        case .json:
            return "Structured data format ideal for programmatic access and data analysis."
        case .csv:
            return "Spreadsheet-compatible format. Each data point becomes a row with date, category, metric, and value columns."
        }
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
        let path = dni.previewPath(for: Date(), healthSubfolder: vaultManager.healthSubfolder)
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
        advancedSettings.folderStructure.isEmpty ? "Flat (no subfolders)" : advancedSettings.folderStructure
    }

    private var formatExtensionsList: String {
        advancedSettings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { $0.fileExtension }
            .joined(separator: ",")
    }

    private var exportPath: String {
        let subfolder = vaultManager.healthSubfolder
        let subfolderPath = subfolder.isEmpty ? "" : subfolder + "/"
        let fileExtension = advancedSettings.primaryFormat.fileExtension
        let formatCount = advancedSettings.exportFormats.count

        let dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let totalFiles = (dayCount + 1) * max(formatCount, 1)
        let vaultName = vaultManager.vaultName

        if dayCount == 0 {
            let folderPath = advancedSettings.formatFolderPath(for: startDate).map { $0 + "/" } ?? ""
            let filename = advancedSettings.formatFilename(for: startDate)
            if formatCount > 1 {
                return "\(vaultName)/\(subfolderPath)\(folderPath)\(filename).{\(formatExtensionsList)} (\(formatCount) files)"
            }
            return "\(vaultName)/\(subfolderPath)\(folderPath)\(filename).\(fileExtension)"
        } else {
            let startFilename = advancedSettings.formatFilename(for: startDate)
            let endFilename = advancedSettings.formatFilename(for: endDate)
            if !advancedSettings.folderStructure.isEmpty {
                return "\(vaultName)/\(subfolderPath).../{files} (\(totalFiles) files in date folders)"
            } else {
                return "\(vaultName)/\(subfolderPath)\(startFilename).\(fileExtension) to \(endFilename).\(fileExtension) (\(totalFiles) files)"
            }
        }
    }
}

