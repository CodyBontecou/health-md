import SwiftUI
import UIKit

// MARK: - iPad Settings View (matching macOS MacDetailSettingsView Form layout)

struct iPadSettingsView: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @Binding var showFolderPicker: Bool
    @State private var showMetricSelection = false
    @State private var showMailCompose = false
    private let macAppURL = URL(string: "https://isolated.tech/apps/healthmd")!

    var body: some View {
        Form {
            // MARK: Export Folder
            Section {
                HStack {
                    if let url = vaultManager.vaultURL {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vaultManager.vaultName)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                            Text(url.path(percentEncoded: false))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.textMuted)
                        Text("No folder selected")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    Button(vaultManager.vaultURL != nil ? "Change…" : "Choose…") {
                        showFolderPicker = true
                    }
                    .tint(Color.accent)
                }

                if vaultManager.vaultURL != nil {
                    LabeledContent("Subfolder") {
                        TextField("Health", text: $vaultManager.healthSubfolder)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 200)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: vaultManager.healthSubfolder) {
                                vaultManager.saveSubfolderSetting()
                            }
                    }

                    Button("Clear Folder Selection", role: .destructive) {
                        vaultManager.clearVaultFolder()
                    }
                    .tint(Color.error)
                }
            } header: {
                iPadBrandLabel("Export Folder")
            }

            // MARK: Export Format
            Section {
                Picker("Format", selection: $advancedSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .tint(Color.accent)

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .tint(Color.accent)

                if advancedSettings.exportFormat == .markdown {
                    Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                }
            } header: {
                iPadBrandLabel("Export Format")
            }

            // MARK: File Naming
            Section {
                LabeledContent("Filename Pattern") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Folder Structure") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }

                Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textMuted)

                LabeledContent("Preview") {
                    let filename = advancedSettings.formatFilename(for: Date())
                    let ext = advancedSettings.exportFormat.fileExtension
                    if let folder = advancedSettings.formatFolderPath(for: Date()) {
                        Text("\(folder)/\(filename).\(ext)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.accent)
                    } else {
                        Text("\(filename).\(ext)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.accent)
                    }
                }
            } header: {
                iPadBrandLabel("File Naming")
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
                iPadBrandLabel("Format Customization")
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
                    iPadBrandLabel("Markdown Template")
                }
            }
            
            // MARK: Placeholder Fields
            Section {
                iPadPlaceholderFieldsView(config: advancedSettings.formatCustomization.frontmatterConfig)
            } header: {
                iPadBrandLabel("Placeholder Fields")
            } footer: {
                Text("Add fields that export with empty values for manual entry (e.g., omron_systolic, omron_diastolic)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
            }

            // MARK: Health Metrics
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Metrics")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
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
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textMuted)
                    }
                }
            } header: {
                iPadBrandLabel("Health Metrics")
            }

            // MARK: Individual Entry Tracking
            Section {
                Toggle("Enable individual entries", isOn: $advancedSettings.individualTracking.globalEnabled)
                    .tint(Color.accent)

                if advancedSettings.individualTracking.globalEnabled {
                    LabeledContent("Entries Folder") {
                        TextField("entries", text: $advancedSettings.individualTracking.entriesFolder)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 200)
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)
                        .tint(Color.accent)

                    LabeledContent("Tracked Metrics") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.accent)
                    }
                }
            } header: {
                iPadBrandLabel("Individual Entry Tracking")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.textMuted)
                    if advancedSettings.individualTracking.globalEnabled && advancedSettings.individualTracking.totalEnabledCount == 0 {
                        Text("⚠️ No metrics selected — individual entries won't be created until you select metrics to track.")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.orange)
                    }
                }
            }

            // MARK: Apps
            Section {
                Button {
                    UIApplication.shared.open(macAppURL)
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        Text("Health.md for macOS")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                iPadBrandLabel("Apps")
            } footer: {
                Text("Download the desktop app to sync and review your health data on Mac.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
            }

            // MARK: Feedback
            Section {
                Button {
                    if FeedbackHelper.canSendMail {
                        showMailCompose = true
                    } else if let url = FeedbackHelper.mailtoURL() {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        Text("Send Feedback")
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
                    HStack {
                        Image(systemName: "ladybug")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        Text("Report a Bug on GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                iPadBrandLabel("Feedback")
            }

            // MARK: Reset
            Section {
                Button("Reset All Settings to Defaults", role: .destructive) {
                    advancedSettings.reset()
                }
                .tint(Color.error)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showMetricSelection) {
            iPadMetricSelectionView(selectionState: advancedSettings.metricSelection)
        }
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
    }
}

// MARK: - Placeholder Fields View for iPad

struct iPadPlaceholderFieldsView: View {
    @ObservedObject var config: FrontmatterConfiguration
    @State private var newPlaceholderKey = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // List existing placeholder fields
            ForEach(config.placeholderFields.sorted(), id: \.self) { key in
                HStack {
                    Text(key)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                    Spacer()
                    Text("(empty)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
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
                    .font(.system(size: 13, design: .monospaced))
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
