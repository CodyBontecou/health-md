#if os(macOS)
import SwiftUI

// MARK: - Settings Window (⌘,) — Branded

struct MacSettingsWindow: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings

    var body: some View {
        TabView {
            MacGeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            MacFormatSettingsTab()
                .tabItem { Label("Format", systemImage: "doc.text") }

            MacDataSettingsTab()
                .tabItem { Label("Data", systemImage: "heart.text.square") }

            MacScheduleView()
                .tabItem { Label("Schedule", systemImage: "clock") }

            MacFeedbackTab()
                .tabItem { Label("Feedback", systemImage: "envelope") }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Sidebar Settings View

struct MacDetailSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings

    var body: some View {
        Form {
            // MARK: Export Folder
            MacVaultFolderSection(showClearButton: true)

            // MARK: Export Format
            Section {
                Picker("Format", selection: $advancedSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Export format")
                .accessibilityValue(advancedSettings.exportFormat.rawValue)

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Write mode")
                .accessibilityValue(advancedSettings.writeMode.rawValue)

                if advancedSettings.exportFormat == .markdown {
                    Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                        .accessibilityLabel("Include frontmatter metadata")
                        .accessibilityValue(advancedSettings.includeMetadata ? "Enabled" : "Disabled")
                    Toggle("Frontmatter Only", isOn: $advancedSettings.formatCustomization.markdownTemplate.frontmatterOnly)
                        .tint(Color.accent)
                        .accessibilityLabel("Frontmatter only mode")
                        .accessibilityValue(advancedSettings.formatCustomization.markdownTemplate.frontmatterOnly ? "Enabled" : "Disabled")
                        .help("Output only YAML frontmatter with no markdown body. Use with Update write mode to merge health metrics into existing daily notes.")
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                        .accessibilityLabel("Group by category")
                        .accessibilityValue(advancedSettings.groupByCategory ? "Enabled" : "Disabled")
                }
            } header: {
                BrandLabel("Export Format")
            }

            // MARK: File Naming
            Section {
                LabeledContent("Filename Pattern") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Folder Structure") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)

                LabeledContent("Preview") {
                    let filename = advancedSettings.formatFilename(for: Date())
                    let ext = advancedSettings.exportFormat.fileExtension
                    if let folder = advancedSettings.formatFolderPath(for: Date()) {
                        Text("\(folder)/\(filename).\(ext)")
                            .font(BrandTypography.detail())
                            .foregroundStyle(Color.accent)
                    } else {
                        Text("\(filename).\(ext)")
                            .font(BrandTypography.detail())
                            .foregroundStyle(Color.accent)
                    }
                }
            } header: {
                BrandLabel("File Naming")
            }

            // MARK: Format Customization
            Section {
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
            } header: {
                BrandLabel("Format Customization")
            }

            // MARK: Markdown Template
            if advancedSettings.exportFormat == .markdown {
                Section {
                    Picker("Style", selection: $advancedSettings.formatCustomization.markdownTemplate.style) {
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

                    Picker("Bullet Style", selection: $advancedSettings.formatCustomization.markdownTemplate.bulletStyle) {
                        ForEach(MarkdownTemplateConfig.BulletStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .tint(Color.accent)

                    Toggle("Use Emoji in Headers", isOn: $advancedSettings.formatCustomization.markdownTemplate.useEmoji)
                        .tint(Color.accent)
                    Toggle("Include Summary", isOn: $advancedSettings.formatCustomization.markdownTemplate.includeSummary)
                        .tint(Color.accent)
                } header: {
                    BrandLabel("Markdown Template")
                }
            }

            // MARK: Individual Tracking
            Section {
                Toggle("Enable individual entries", isOn: $advancedSettings.individualTracking.globalEnabled)
                    .tint(Color.accent)
                    .accessibilityLabel("Enable individual entries")
                    .accessibilityValue(advancedSettings.individualTracking.globalEnabled ? "Enabled" : "Disabled")
                    .accessibilityHint("Creates individual timestamped files for selected metrics")

                if advancedSettings.individualTracking.globalEnabled {
                    LabeledContent("Entries Folder") {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Entries folder name")
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)
                        .tint(Color.accent)
                        .accessibilityLabel("Organize by category")
                        .accessibilityValue(advancedSettings.individualTracking.useCategoryFolders ? "Enabled" : "Disabled")

                    LabeledContent("Tracked Metrics") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount)")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Tracked metrics")
                    .accessibilityValue("\(advancedSettings.individualTracking.totalEnabledCount)")
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

            // MARK: Feedback
            Section {
                Button {
                    FeedbackHelper.openMailClient()
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text("Send Feedback")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send feedback")
                .accessibilityHint("Opens your email client to send feedback")

                Button {
                    FeedbackHelper.openGitHubIssue()
                } label: {
                    HStack {
                        Image(systemName: "ladybug")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text("Report a Bug on GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Report a bug on GitHub")
                .accessibilityHint("Opens GitHub to create a new issue")
            } header: {
                BrandLabel("Feedback")
            }

            // MARK: Reset
            Section {
                Button("Reset All Settings to Defaults", role: .destructive) {
                    advancedSettings.reset()
                }
                .tint(Color.error)
                .accessibilityLabel("Reset all settings to defaults")
                .accessibilityHint("Resets all export and format settings to their default values")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
                Picker("Format", selection: $advancedSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Export format")
                .accessibilityValue(advancedSettings.exportFormat.rawValue)

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Write mode")
                .accessibilityValue(advancedSettings.writeMode.rawValue)

                if advancedSettings.exportFormat == .markdown {
                    Toggle("Include Frontmatter", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                        .accessibilityLabel("Include frontmatter")
                        .accessibilityValue(advancedSettings.includeMetadata ? "Enabled" : "Disabled")
                    Toggle("Frontmatter Only", isOn: $advancedSettings.formatCustomization.markdownTemplate.frontmatterOnly)
                        .tint(Color.accent)
                        .accessibilityLabel("Frontmatter only mode")
                        .accessibilityValue(advancedSettings.formatCustomization.markdownTemplate.frontmatterOnly ? "Enabled" : "Disabled")
                        .help("Output only YAML frontmatter with no markdown body. Use with Update write mode to merge health metrics into existing daily notes.")
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                        .accessibilityLabel("Group by category")
                        .accessibilityValue(advancedSettings.groupByCategory ? "Enabled" : "Disabled")
                }
            } header: {
                BrandLabel("Export Format")
            }

            Section {
                LabeledContent("Filename") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Filename pattern")
                        .accessibilityHint("Use placeholders like {date}, {year}, {month}")
                }

                LabeledContent("Subfolder Pattern") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .font(.system(size: 13, design: .monospaced))
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

            if advancedSettings.exportFormat == .markdown {
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
                    let enabled = advancedSettings.metricSelection.enabledMetricCount(for: category)
                    let total = advancedSettings.metricSelection.totalMetricCount(for: category)

                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        Text(category.rawValue)
                        Spacer()
                        Text("\(enabled)/\(total)")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.textMuted)
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
                            .font(.system(size: 13, design: .monospaced))
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
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
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
