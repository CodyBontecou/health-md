#if os(macOS)
import SwiftUI

// MARK: - Settings Window (⌘,) — Branded

struct MacSettingsWindow: View {
    @State private var selection: MacSettingsDestination = .general

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)

            selectedView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MacSettingsBackdrop())
        .frame(
            minWidth: 880,
            idealWidth: 1_100,
            maxWidth: .infinity,
            minHeight: 640,
            idealHeight: 760,
            maxHeight: .infinity
        )
        .foregroundStyle(Color.textPrimary)
        .tint(Color.accent)
    }

    private var settingsHeader: some View {
        HStack(spacing: Spacing.s6) {
            HStack(spacing: Spacing.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .fill(Color.accentSubtle)
                        .frame(width: 36, height: 36)
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(Typography.headline())
                    Text("Configure this Mac and the local CLI")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.s4)

            HStack(spacing: Spacing.s1) {
                ForEach(MacSettingsDestination.allCases) { destination in
                    Button {
                        withAnimation(AnimationTimings.fast) {
                            selection = destination
                        }
                    } label: {
                        Label(destination.title, systemImage: destination.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(MacSettingsTabButtonStyle(isSelected: selection == destination))
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .padding(Spacing.s1)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.vertical, Spacing.s4)
        .background(Color.bgPrimary.opacity(0.96))
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selection {
        case .general:
            MacGeneralSettingsView()
        case .cli:
            MacCLIView()
        }
    }
}

private enum MacSettingsDestination: String, CaseIterable, Identifiable {
    case general
    case cli

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .cli: return "CLI"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .cli: return "terminal"
        }
    }
}

private struct MacSettingsTabButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption().weight(.semibold))
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
            .padding(.horizontal, Spacing.s3)
            .frame(height: 34)
            .background(
                isSelected
                    ? Color.bgPrimary
                    : (configuration.isPressed ? Color.bgTertiary : Color.clear),
                in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Color.borderSubtle : Color.clear, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 2, y: 1)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Sidebar Settings View

struct MacDetailSettingsView: View {
    var body: some View {
        MacSettingsWindow()
            .navigationTitle("Settings")
    }
}

// MARK: - General Settings

struct MacGeneralSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore
    @EnvironmentObject var encryptedHealthContextManager: MacEncryptedHealthContextManager
    @State private var showClearConfirmation = false
    @State private var showEncryptedContextDeleteConfirmation = false
    @State private var showRetentionConfirmation = false
    @State private var retentionBoundary = Date()

    var body: some View {
        Form {
            Section {
                Text("Health.md for Mac works as a local export destination. Configure formats, metrics, date ranges, filenames, write modes, and Lossless Health Records on iPhone, then send the export to this Mac.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Lossless Health Records retains every selected HealthKit source record alongside daily summaries, including source UUIDs, exact timestamps, provenance, metadata, and detailed series. Files may be much larger. Turn it off on iPhone for summary-only exports.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                BrandLabel("iPhone-Controlled Exports")
            }

            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(syncService.connectionState == .connected ? Color.success : Color.textMuted)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(syncService.connectionState == .connected
                         ? "Connected to \(syncService.connectedPeerName ?? "iPhone")"
                         : "Not connected")
                        .font(BrandTypography.bodyMedium())
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connection status")
                .accessibilityValue(syncService.connectionState == .connected
                    ? "Connected to \(syncService.connectedPeerName ?? "iPhone")"
                    : "Not connected")

                HStack {
                    Text("Readiness")
                    Spacer()
                    Text(readinessText)
                        .font(BrandTypography.value())
                        .foregroundStyle(readinessColor)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Mac export readiness")
                .accessibilityValue(readinessText)
            } header: {
                BrandLabel("Status")
            }

            MacVaultFolderSection(showSubfolder: false, showClearButton: true)

            Section {
                HStack {
                    Text("Encrypted context days")
                    Spacer()
                    Text("\(encryptedHealthContextManager.ownerDateCount)")
                        .font(BrandTypography.value())
                        .foregroundStyle(Color.accent)
                }

                if let earliest = encryptedHealthContextManager.earliestOwnerDate,
                   let latest = encryptedHealthContextManager.latestOwnerDate {
                    LabeledContent("Owner-date range") {
                        Text(earliest == latest ? earliest : "\(earliest) – \(latest)")
                            .font(Typography.mono())
                    }
                }

                DatePicker(
                    "Delete days before",
                    selection: $retentionBoundary,
                    displayedComponents: .date
                )
                Button("Delete Older Context…") {
                    showRetentionConfirmation = true
                }
                .disabled(encryptedHealthContextManager.isWorking
                    || encryptedHealthContextManager.ownerDateCount == 0)

                Button("Delete All Encrypted Context…", role: .destructive) {
                    showEncryptedContextDeleteConfirmation = true
                }
                .disabled(encryptedHealthContextManager.isWorking
                    || encryptedHealthContextManager.ownerDateCount == 0)

                if let error = encryptedHealthContextManager.lastError {
                    Text(error)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.error)
                }
            } header: {
                BrandLabel("Local Query Context")
            } footer: {
                Text("This Keychain-encrypted store is independent from exported files. Retention is never automatic; deleting it does not change Apple Health on iPhone.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }

            if healthDataStore.recordCount > 0 {
                Section {
                    HStack {
                        Text("Cached legacy records")
                        Spacer()
                        Text("\(healthDataStore.recordCount)")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    Button("Delete Legacy Cache", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .tint(Color.error)
                    .accessibilityHint("Removes cached Health data from the old Mac sync flow")
                } header: {
                    BrandLabel("Legacy Cache")
                } footer: {
                    Text("New Mac-targeted exports are built on iPhone and sent directly to the selected folder. This cache is only for the old manual sync flow.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            }

            Section {
                Button {
                    FeedbackHelper.openMailClient()
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }

                Button {
                    FeedbackHelper.openGitHubIssue()
                } label: {
                    Label("Report a Bug on GitHub", systemImage: "ladybug")
                }
            } header: {
                BrandLabel("Feedback")
            }
        }
        .formStyle(.grouped)
        .alert("Delete Legacy Synced Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                healthDataStore.deleteAll()
            }
        } message: {
            Text("This removes the old iPhone→Mac cache from this Mac. It does not affect Health data on iPhone or exported files.")
        }
        .alert("Delete All Encrypted Query Context?", isPresented: $showEncryptedContextDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task { await encryptedHealthContextManager.deleteAll() }
            }
        } message: {
            Text("This removes every compact context day and its dedicated Keychain key. Exported files and Apple Health remain unchanged.")
        }
        .alert("Delete Context Before \(retentionOwnerDate)?", isPresented: $showRetentionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Older Days", role: .destructive) {
                let boundary = retentionOwnerDate
                Task { await encryptedHealthContextManager.delete(before: boundary) }
            }
        } message: {
            Text("Every encrypted owner day earlier than this date will be permanently removed. The boundary date and newer days remain.")
        }
    }

    private var retentionOwnerDate: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: retentionBoundary)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var readinessText: String {
        if syncService.isSyncing { return "Receiving export" }
        if syncService.connectionState != .connected { return "Connect iPhone" }
        if !iPhoneSupportsMacExports { return "Update iPhone app" }
        if vaultManager.vaultURL == nil { return "Choose folder" }
        if !folderAccessHealthy { return "Re-select folder" }
        return "Ready"
    }

    private var readinessColor: Color {
        readinessText == "Ready" ? Color.success : Color.warning
    }

    private var iPhoneSupportsMacExports: Bool {
        guard syncService.connectionState == .connected else { return false }
        guard let capabilities = syncService.remoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }
}

// MARK: - Shared Settings Components

struct MacSettingsBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color.bgTertiary.opacity(0.72), Color.bgSecondary],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct MacSettingsCard<Content: View>: View {
    var padding: CGFloat = Spacing.s6
    private let content: Content

    init(padding: CGFloat = Spacing.s6, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.bgPrimary, in: RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 2)
    }
}

struct MacSettingsSectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    private let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.2)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.s3)
            accessory
        }
    }
}

extension MacSettingsSectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct MacSettingsPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    private let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .fill(Color.accentSubtle)
                    .frame(width: 52, height: 52)
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.displayMedium())
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 700, alignment: .leading)
            }

            Spacer(minLength: Spacing.s4)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MacSettingsPageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String, systemImage: String) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}

struct MacSettingsStatusBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(Typography.label())
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.s3)
            .frame(height: 30)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }
}

struct MacSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }
}

// MARK: - Settings Tabs (for ⌘, window)

struct MacGeneralSettingsTab: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(syncService.connectionState == .connected ? Color.success : Color.textMuted)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(syncService.connectionState == .connected
                         ? "Connected to \(syncService.connectedPeerName ?? "iPhone")"
                         : "Not Connected")
                        .font(BrandTypography.bodyMedium())
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connection status")
                .accessibilityValue(syncService.connectionState == .connected
                    ? "Connected to \(syncService.connectedPeerName ?? "iPhone")"
                    : "Not connected")

                HStack {
                    Text("Synced Records")
                    Spacer()
                    Text("\(healthDataStore.recordCount)")
                        .font(BrandTypography.value())
                        .foregroundStyle(Color.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Synced records")
                .accessibilityValue("\(healthDataStore.recordCount)")

                if let lastSync = healthDataStore.lastSyncDate {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Last sync")
                }
            } header: {
                BrandLabel("iPhone Sync")
            }

            MacVaultFolderSection()
        }
        .formStyle(.grouped)
    }
}

struct MacFormatSettingsTab: View {
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
    @State private var showFormatHelp = false

    var body: some View {
        Form {
            Section {
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
                if advancedSettings.dailyNotesOnlyModeEnabled {
                    Text("Daily Notes Only is active. Format choices are saved but aggregate files are skipped.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.accent)
                } else if advancedSettings.exportFormats.isEmpty {
                    Text("Select at least one export format, or enable Daily Notes Only.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.error)
                }

                Text(ExportRolloutCopy.versionedExportsHelp)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)

                Text(ExportRolloutCopy.dataDictionaryHelp)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Write mode")
                .accessibilityValue(advancedSettings.writeMode.rawValue)

                if advancedSettings.exportFormats.contains(.markdown) {
                    Toggle("Include Frontmatter", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                        .accessibilityLabel("Include frontmatter")
                        .accessibilityValue(advancedSettings.includeMetadata ? "Enabled" : "Disabled")
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                        .accessibilityLabel("Group by category")
                        .accessibilityValue(advancedSettings.groupByCategory ? "Enabled" : "Disabled")
                }
            } header: {
                HStack(spacing: 6) {
                    BrandLabel("Export Formats")
                    Spacer()
                    Button { showFormatHelp = true } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How export formats work")
                }
            }

            Section {
                Toggle("Weekly summaries", isOn: $advancedSettings.generateWeeklyRollups)
                    .tint(Color.accent)
                    .disabled(advancedSettings.dailyNotesOnlyModeEnabled)
                    .accessibilityLabel("Weekly roll-up summaries")
                    .accessibilityValue(advancedSettings.generateWeeklyRollups ? "Enabled" : "Disabled")
                Toggle("Monthly summaries", isOn: $advancedSettings.generateMonthlyRollups)
                    .tint(Color.accent)
                    .disabled(advancedSettings.dailyNotesOnlyModeEnabled)
                    .accessibilityLabel("Monthly roll-up summaries")
                    .accessibilityValue(advancedSettings.generateMonthlyRollups ? "Enabled" : "Disabled")
                Toggle("Yearly summaries", isOn: $advancedSettings.generateYearlyRollups)
                    .tint(Color.accent)
                    .disabled(advancedSettings.dailyNotesOnlyModeEnabled)
                    .accessibilityLabel("Yearly roll-up summaries")
                    .accessibilityValue(advancedSettings.generateYearlyRollups ? "Enabled" : "Disabled")

                Toggle("Summary files only", isOn: $advancedSettings.summaryOnlyExport)
                    .tint(Color.accent)
                    .disabled(!advancedSettings.rollupSummariesEnabled || advancedSettings.dailyNotesOnlyModeEnabled)
                    .accessibilityLabel("Export roll-up summaries only")
                    .accessibilityValue(advancedSettings.summaryOnlyModeEnabled ? "Enabled" : "Disabled")

                Text("Skips daily files and side effects. Health.md still fetches the full touched periods to build the enabled summaries.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)

                Text(ExportRolloutCopy.rollupSummariesHelp)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)

                Text(ExportRolloutCopy.pluginCompatibilityHelp)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            } header: {
                BrandLabel("Roll-up Summaries")
            }

            Section {
                LabeledContent("Filename") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .font(Typography.mono())
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Filename pattern")
                        .accessibilityHint("Use placeholders like {date}, {year}, {month}")
                }

                LabeledContent("Subfolder Pattern") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .font(Typography.mono())
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Subfolder pattern")
                        .accessibilityHint("Use placeholders to organize files into subfolders")
                }

                Toggle("Organize by File Type", isOn: $advancedSettings.organizeFormatsIntoFolders)
                    .tint(Color.accent)
                    .accessibilityLabel("Organize exports by file type")
                    .accessibilityValue(advancedSettings.organizeFormatsIntoFolders ? "Enabled" : "Disabled")

                Text("Placeholders: {date}, {year}, {YR}, {month}, {day}, {weekday}, {monthName}, {quarter}.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)

                Text(ExportRolloutCopy.formatFoldersHelp)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            } header: {
                BrandLabel("File Naming")
            }

            Section {
                Picker("Date Format", selection: $advancedSettings.formatCustomization.dateFormat) {
                    ForEach(DateFormatPreference.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Date format")
                .accessibilityValue(advancedSettings.formatCustomization.dateFormat.displayName)

                Picker("Time Format", selection: $advancedSettings.formatCustomization.timeFormat) {
                    ForEach(TimeFormatPreference.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Time format")
                .accessibilityValue(advancedSettings.formatCustomization.timeFormat.displayName)

                Picker("Units", selection: $advancedSettings.formatCustomization.unitPreference) {
                    ForEach(UnitPreference.allCases, id: \.self) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Unit system")
                .accessibilityValue(advancedSettings.formatCustomization.unitPreference.displayName)

                Text(ExportRolloutCopy.canonicalUnitsHelp)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            } header: {
                BrandLabel("Display Formats")
            }

            if advancedSettings.exportFormats.contains(.markdown) {
                Section {
                    Picker("Style", selection: $advancedSettings.formatCustomization.markdownTemplate.style) {
                        ForEach(MarkdownTemplateStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .tint(Color.accent)

                    Picker("Header Level", selection: $advancedSettings.formatCustomization.markdownTemplate.sectionHeaderLevel) {
                        Text("# H1").tag(1)
                        Text("## H2").tag(2)
                        Text("### H3").tag(3)
                    }
                    .tint(Color.accent)

                    Picker("Bullet Style", selection: $advancedSettings.formatCustomization.markdownTemplate.bulletStyle) {
                        ForEach(MarkdownTemplateConfig.BulletStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .tint(Color.accent)

                    Toggle("Emoji in Headers", isOn: $advancedSettings.formatCustomization.markdownTemplate.useEmoji)
                        .tint(Color.accent)
                    Toggle("Include Summary", isOn: $advancedSettings.formatCustomization.markdownTemplate.includeSummary)
                        .tint(Color.accent)
                } header: {
                    BrandLabel("Markdown Template")
                }
            }
            
            // Placeholder Fields Section
            Section {
                MacPlaceholderFieldsView(config: advancedSettings.formatCustomization.frontmatterConfig)
            } header: {
                BrandLabel("Placeholder Fields")
            } footer: {
                Text("Add fields that export with empty values for manual entry (e.g., omron_systolic)")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showFormatHelp) {
            ExportFormatHelpSheet(showJSONTip: !advancedSettings.exportFormats.contains(.json))
                .frame(minWidth: 440, minHeight: 500)
        }
    }
}

// MARK: - Placeholder Fields View for macOS

struct MacPlaceholderFieldsView: View {
    @ObservedObject var config: FrontmatterConfiguration
    @State private var newPlaceholderKey = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // List existing placeholder fields
            ForEach(config.placeholderFields.sorted(), id: \.self) { key in
                HStack {
                    Text(key)
                        .font(BrandTypography.body())
                    Spacer()
                    Text("(empty)")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                    Button {
                        config.placeholderFields.removeAll { $0 == key }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Add new placeholder field
            HStack {
                TextField("Field name (e.g., omron_systolic)", text: $newPlaceholderKey)
                    .textFieldStyle(.roundedBorder)
                
                Button("Add") {
                    if !newPlaceholderKey.isEmpty && !config.placeholderFields.contains(newPlaceholderKey) {
                        config.placeholderFields.append(newPlaceholderKey)
                        newPlaceholderKey = ""
                    }
                }
                .disabled(newPlaceholderKey.isEmpty)
                .tint(Color.accent)
            }
        }
    }
}

struct MacDataSettingsTab: View {
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
    @EnvironmentObject var vaultManager: VaultManager
    @State private var showMetricSelection = false

    private var individualTrackableMetrics: [HealthMetricDefinition] {
        HealthMetrics.all.filter { advancedSettings.metricSelection.isMetricEnabled($0.id) }
    }

    private var enabledTrackableIndividualMetricCount: Int {
        individualTrackableMetrics.filter { advancedSettings.individualTracking.shouldTrackIndividually($0.id) }.count
    }

    private var tracksAllEnabledIndividualMetrics: Bool {
        guard !individualTrackableMetrics.isEmpty else { return false }
        return enabledTrackableIndividualMetricCount == individualTrackableMetrics.count
    }

    private func setTracksAllEnabledIndividualMetrics(_ shouldTrack: Bool) {
        advancedSettings.individualTracking.disableAll()

        guard shouldTrack else { return }
        for metric in individualTrackableMetrics {
            advancedSettings.individualTracking.setTrackIndividually(metric.id, enabled: true)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Metrics")
                            .font(BrandTypography.bodyMedium())
                        Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    ProgressView(
                        value: Double(advancedSettings.metricSelection.totalEnabledCount),
                        total: Double(advancedSettings.metricSelection.totalMetricCount)
                    )
                    .frame(width: 100)
                    .tint(Color.accent)
                    Button("Configure…") {
                        showMetricSelection = true
                    }
                    .tint(Color.accent)
                }

                ForEach(HealthMetricCategory.allCases, id: \.self) { category in
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        Text(category.rawValue)
                        Spacer()
                        if category.isPendingAppleApproval {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(Color.textMuted)
                            Text("Pending")
                                .font(BrandTypography.value())
                                .foregroundStyle(Color.textMuted)
                        } else {
                            let enabled = advancedSettings.metricSelection.enabledMetricCount(for: category)
                            let total = advancedSettings.metricSelection.totalMetricCount(for: category)
                            Text("\(enabled)/\(total)")
                                .font(BrandTypography.value())
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            } header: {
                BrandLabel("Health Metrics")
            }

            Section {
                Toggle("Enable individual entries", isOn: $advancedSettings.individualTracking.globalEnabled)
                    .tint(Color.accent)
                    .disabled(advancedSettings.dailyNotesOnlyModeEnabled)

                if advancedSettings.individualTracking.globalEnabled {
                    LabeledContent("Entries Folder") {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .font(Typography.mono())
                            .disabled(advancedSettings.dailyNotesOnlyModeEnabled)
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)
                        .tint(Color.accent)
                        .disabled(advancedSettings.dailyNotesOnlyModeEnabled)

                    LabeledContent("Tracked") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount) metrics")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    HStack {
                        Toggle(isOn: Binding(
                            get: { tracksAllEnabledIndividualMetrics },
                            set: { setTracksAllEnabledIndividualMetrics($0) }
                        )) {
                            Text(tracksAllEnabledIndividualMetrics ? "All Enabled Metrics Tracked" : "Track All Enabled Metrics")
                                .font(BrandTypography.body())
                        }
                        .toggleStyle(.switch)
                        .tint(Color.accent)
                        .disabled(individualTrackableMetrics.isEmpty)

                        Button("Disable All") {
                            advancedSettings.individualTracking.disableAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(advancedSettings.individualTracking.totalEnabledCount == 0)
                    }
                    .disabled(advancedSettings.dailyNotesOnlyModeEnabled)
                }
            } header: {
                BrandLabel("Individual Entry Tracking")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if advancedSettings.dailyNotesOnlyModeEnabled {
                        Text("Inactive while Daily Notes Only is on. Your individual-entry settings are preserved.")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                    Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                    if advancedSettings.individualTracking.globalEnabled && advancedSettings.individualTracking.totalEnabledCount == 0 {
                        Text("⚠️ No metrics selected — individual entries won't be created until you select metrics to track.")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.warning)
                    }
                }
            }

            // MARK: Daily Note Injection
            Section {
                Toggle("Inject into daily notes", isOn: $advancedSettings.dailyNoteInjection.enabled)
                    .tint(Color.accent)
                    .accessibilityLabel("Inject health metrics into daily notes")
                    .accessibilityValue(advancedSettings.dailyNoteInjection.enabled ? "Enabled" : "Disabled")

                if advancedSettings.dailyNoteInjection.enabled {
                    LabeledContent("Notes Folder") {
                        TextField("Daily", text: $advancedSettings.dailyNoteInjection.folderPath)
                            .font(Typography.mono())
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Daily notes folder path")
                    }

                    LabeledContent("Filename Pattern") {
                        TextField("{date}", text: $advancedSettings.dailyNoteInjection.filenamePattern)
                            .font(Typography.mono())
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Daily note filename pattern")
                    }

                    LabeledContent("Preview") {
                        Text(advancedSettings.dailyNoteInjection.previewPath(for: Date()))
                            .font(BrandTypography.detail())
                            .foregroundStyle(Color.accent)
                    }

                    Toggle("Create note if missing", isOn: $advancedSettings.dailyNoteInjection.createIfMissing)
                        .tint(Color.accent)

                    Toggle("Daily Notes Only", isOn: $advancedSettings.dailyNoteInjection.dailyNotesOnly)
                        .tint(Color.accent)
                        .accessibilityHint("Skips aggregate exports, ZIPs, roll-ups, individual entries, provider sidecars, and the data dictionary while preserving their settings")

                    Toggle("Inject metric sections", isOn: $advancedSettings.dailyNoteInjection.injectMarkdownSections)
                        .tint(Color.accent)
                        .accessibilityLabel("Inject markdown sections into the note body")

                    LabeledContent("Metrics Injected") {
                        Text("\(advancedSettings.metricSelection.totalEnabledCount) enabled")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    Text("Injects the same metrics enabled in Health Metrics. Manual exports, scheduled exports, and Mac destination exports run Daily Note Injection when it is enabled.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            } header: {
                BrandLabel("Daily Note Injection")
            } footer: {
                Text("Injects selected metrics into your existing daily notes' YAML frontmatter. The notes folder is relative to the selected vault/root, not the Health.md export subfolder. Turn on \"Inject metric sections\" to also write Sleep, Activity, etc. into the note body. Leave folder empty to search the vault root. Placeholders: {date}, {year}, {YR}, {month}, {day}, {weekday}, {monthName}, {quarter}.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showMetricSelection) {
            MacMetricSelectionView(selectionState: advancedSettings.metricSelection)
                .frame(minWidth: 500, minHeight: 500)
        }
    }
}



// MARK: - Feedback Tab (for ⌘, window)

struct MacFeedbackTab: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Have a question, idea, or ran into a problem?")
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)

                    Text("Send an email or open a GitHub issue — both include your app version and system info automatically.")
                        .font(BrandTypography.body())
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    FeedbackHelper.openMailClient()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Feedback")
                                .font(BrandTypography.bodyMedium())
                                .foregroundStyle(Color.textPrimary)
                            Text("Opens your default email client")
                                .font(BrandTypography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    FeedbackHelper.openGitHubIssue()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "ladybug.fill")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Report a Bug on GitHub")
                                .font(BrandTypography.bodyMedium())
                                .foregroundStyle(Color.textPrimary)
                            Text("Opens a pre-filled issue template")
                                .font(BrandTypography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                BrandLabel("Get in Touch")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diagnostics included automatically:")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)

                    Text(FeedbackHelper.diagnosticsBlock)
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.borderSubtle, lineWidth: 1)
                        )
                }
                .padding(.vertical, 4)
            } header: {
                BrandLabel("What Gets Shared")
            } footer: {
                Text("No health data or personal information is included — only app version and system info.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }
        }
        .formStyle(.grouped)
    }
}

#endif
