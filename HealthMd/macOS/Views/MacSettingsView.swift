#if os(macOS)
import SwiftUI

// MARK: - Settings Window (⌘,) — Branded

struct MacSettingsWindow: View {
    var body: some View {
        MacAgentSettingsView()
            .frame(width: 560, height: 360)
    }
}

// MARK: - Sidebar Settings View

struct MacDetailSettingsView: View {
    var body: some View {
        MacAgentSettingsView()
            .navigationTitle("Settings")
    }
}

// MARK: - Agent Settings

struct MacAgentSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section {
                Text("Health.md for Mac now works as a local export destination. Configure formats, metrics, date ranges, filenames, and write modes on iPhone, then send the export to this Mac.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
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
                if advancedSettings.exportFormats.isEmpty {
                    Text("Select at least one export format.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.red)
                }

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
                BrandLabel("Export Formats")
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

                Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}")
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

                if advancedSettings.individualTracking.globalEnabled {
                    LabeledContent("Entries Folder") {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .font(Typography.mono())
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)
                        .tint(Color.accent)

                    LabeledContent("Tracked") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount) metrics")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    HStack {
                        Button("Enable Suggested") {
                            advancedSettings.individualTracking.enableSuggested()
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)

                        Button("Disable All") {
                            advancedSettings.individualTracking.disableAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                BrandLabel("Individual Entry Tracking")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                    if advancedSettings.individualTracking.globalEnabled && advancedSettings.individualTracking.totalEnabledCount == 0 {
                        Text("⚠️ No metrics selected — individual entries won't be created until you select metrics to track.")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.orange)
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
                        Text(advancedSettings.dailyNoteInjection.previewPath(
                            for: Date(),
                            healthSubfolder: vaultManager.healthSubfolder
                        ))
                        .font(BrandTypography.detail())
                        .foregroundStyle(Color.accent)
                    }

                    Toggle("Create note if missing", isOn: $advancedSettings.dailyNoteInjection.createIfMissing)
                        .tint(Color.accent)

                    Toggle("Inject metric sections", isOn: $advancedSettings.dailyNoteInjection.injectMarkdownSections)
                        .tint(Color.accent)
                        .accessibilityLabel("Inject markdown sections into the note body")

                    LabeledContent("Metrics Injected") {
                        Text("\(advancedSettings.metricSelection.totalEnabledCount) enabled")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    Text("Injects the same metrics enabled in Health Metrics. Change your metric selection there to control what gets injected.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            } header: {
                BrandLabel("Daily Note Injection")
            } footer: {
                Text("Injects selected metrics into your existing daily notes' YAML frontmatter. Turn on \"Inject metric sections\" to also write Sleep, Activity, etc. into the note body — app-managed sections are replaced on each export, user-added sections are preserved. Leave folder empty to search the vault root. Placeholders: {date}, {year}, {month}, {day}.")
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
