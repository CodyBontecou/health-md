#if os(macOS)
import SwiftUI

// MARK: - Settings Window (⌘,)

struct MacSettingsWindow: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
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
            Section("Export Format") {
                Picker("Format", selection: $advancedSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if advancedSettings.exportFormat == .markdown {
                    Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                }
            }

            // MARK: File Naming
            Section("File Naming") {
                LabeledContent("Filename Pattern") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Folder Structure") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Preview") {
                    let filename = advancedSettings.formatFilename(for: Date())
                    let ext = advancedSettings.exportFormat.fileExtension
                    if let folder = advancedSettings.formatFolderPath(for: Date()) {
                        Text("\(folder)/\(filename).\(ext)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(filename).\(ext)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Format Customization
            Section("Format Customization") {
                Picker("Date Format", selection: $advancedSettings.formatCustomization.dateFormat) {
                    ForEach(DateFormatPreference.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Time Format", selection: $advancedSettings.formatCustomization.timeFormat) {
                    ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Unit System", selection: $advancedSettings.formatCustomization.unitPreference) {
                    ForEach(UnitPreference.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }

            // MARK: Markdown Template
            if advancedSettings.exportFormat == .markdown {
                Section("Markdown Template") {
                    Picker("Style", selection: $advancedSettings.formatCustomization.markdownTemplate.style) {
                        ForEach(MarkdownTemplateStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Picker("Header Level", selection: $advancedSettings.formatCustomization.markdownTemplate.sectionHeaderLevel) {
                        Text("# H1").tag(1)
                        Text("## H2").tag(2)
                        Text("### H3").tag(3)
                    }

                    Picker("Bullet Style", selection: $advancedSettings.formatCustomization.markdownTemplate.bulletStyle) {
                        ForEach(MarkdownTemplateConfig.BulletStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Toggle("Use Emoji in Headers", isOn: $advancedSettings.formatCustomization.markdownTemplate.useEmoji)
                    Toggle("Include Summary", isOn: $advancedSettings.formatCustomization.markdownTemplate.includeSummary)
                }
            }

            // MARK: Individual Tracking
            Section {
                Toggle("Enable individual entries", isOn: $advancedSettings.individualTracking.globalEnabled)

                if advancedSettings.individualTracking.globalEnabled {
                    LabeledContent("Entries Folder") {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)

                    LabeledContent("Tracked Metrics") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Individual Entry Tracking")
            } footer: {
                Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
            }

            // MARK: Reset
            Section {
                Button("Reset All Settings to Defaults", role: .destructive) {
                    advancedSettings.reset()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

// MARK: - Settings Tabs (for ⌘, window)

struct MacGeneralSettingsTab: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var healthKitManager: HealthKitManager

    var body: some View {
        Form {
            Section("Health Connection") {
                HStack {
                    Circle()
                        .fill(healthKitManager.isAuthorized ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    Text(healthKitManager.isAuthorized ? "Connected to Apple Health" : "Not Connected")
                    Spacer()
                    if !healthKitManager.isAuthorized {
                        Button("Authorize…") {
                            Task { try? await healthKitManager.requestAuthorization() }
                        }
                    }
                }
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
            Section("Export Format") {
                Picker("Format", selection: $advancedSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if advancedSettings.exportFormat == .markdown {
                    Toggle("Include Frontmatter", isOn: $advancedSettings.includeMetadata)
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                }
            }

            Section("File Naming") {
                LabeledContent("Filename") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Subfolder Pattern") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display Formats") {
                Picker("Date Format", selection: $advancedSettings.formatCustomization.dateFormat) {
                    ForEach(DateFormatPreference.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }

                Picker("Time Format", selection: $advancedSettings.formatCustomization.timeFormat) {
                    ForEach(TimeFormatPreference.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }

                Picker("Units", selection: $advancedSettings.formatCustomization.unitPreference) {
                    ForEach(UnitPreference.allCases, id: \.self) { u in
                        Text(u.displayName).tag(u)
                    }
                }
            }

            if advancedSettings.exportFormat == .markdown {
                Section("Markdown Template") {
                    Picker("Style", selection: $advancedSettings.formatCustomization.markdownTemplate.style) {
                        ForEach(MarkdownTemplateStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }

                    Picker("Header Level", selection: $advancedSettings.formatCustomization.markdownTemplate.sectionHeaderLevel) {
                        Text("# H1").tag(1)
                        Text("## H2").tag(2)
                        Text("### H3").tag(3)
                    }

                    Picker("Bullet Style", selection: $advancedSettings.formatCustomization.markdownTemplate.bulletStyle) {
                        ForEach(MarkdownTemplateConfig.BulletStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }

                    Toggle("Emoji in Headers", isOn: $advancedSettings.formatCustomization.markdownTemplate.useEmoji)
                    Toggle("Include Summary", isOn: $advancedSettings.formatCustomization.markdownTemplate.includeSummary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct MacDataSettingsTab: View {
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
    @State private var showMetricSelection = false

    var body: some View {
        Form {
            Section("Health Metrics") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Metrics")
                        Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView(
                        value: Double(advancedSettings.metricSelection.totalEnabledCount),
                        total: Double(advancedSettings.metricSelection.totalMetricCount)
                    )
                    .frame(width: 100)
                    Button("Configure…") {
                        showMetricSelection = true
                    }
                }

                // Quick category toggles
                ForEach(HealthMetricCategory.allCases, id: \.self) { category in
                    let enabled = advancedSettings.metricSelection.enabledMetricCount(for: category)
                    let total = advancedSettings.metricSelection.totalMetricCount(for: category)

                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                        Text(category.rawValue)
                        Spacer()
                        Text("\(enabled)/\(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section {
                Toggle("Enable individual entries", isOn: $advancedSettings.individualTracking.globalEnabled)

                if advancedSettings.individualTracking.globalEnabled {
                    LabeledContent("Entries Folder") {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .frame(width: 200)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)

                    LabeledContent("Tracked") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount) metrics")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Enable Suggested") {
                            advancedSettings.individualTracking.enableSuggested()
                        }
                        .buttonStyle(.bordered)

                        Button("Disable All") {
                            advancedSettings.individualTracking.disableAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Individual Entry Tracking")
            } footer: {
                Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showMetricSelection) {
            MacMetricSelectionView(selectionState: advancedSettings.metricSelection)
                .frame(minWidth: 500, minHeight: 500)
        }
    }
}

#endif
