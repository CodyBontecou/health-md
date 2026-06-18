import SwiftUI
import StoreKit
import UIKit

// MARK: - iPad Settings View (matching macOS MacDetailSettingsView Form layout)

struct iPadSettingsView: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var showFolderPicker: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var metricProgressWidth: CGFloat = 100
    @State private var showMetricSelection = false
    @State private var showMailCompose = false
    @State private var showPaywall = false
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    private var usesVerticalControlRows: Bool { dynamicTypeSize.isAccessibilitySize }

    private var purchaseStatusTitle: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Lifetime active"
        }
        if purchaseManager.isUnlocked {
            return "Full access active"
        }
        return "Unlock Full Access"
    }

    private var purchaseStatusDetail: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Sharing enabled"
        }
        if purchaseManager.canBuyFamilyUpgrade {
            return "Family upgrade available"
        }
        if purchaseManager.isUnlocked {
            return "Full access active"
        }
        if let individualPrice = purchaseManager.product(for: .individual)?.displayPrice,
           let familyPrice = purchaseManager.product(for: .family)?.displayPrice {
            return "Individual \(individualPrice) or Family \(familyPrice)"
        }
        return "One-time unlock — individual or family"
    }

    var body: some View {
        Form {
            // MARK: Export Folder
            Section {
                if usesVerticalControlRows {
                    VStack(alignment: .leading, spacing: 12) {
                        folderStatus
                        folderPickerButton
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            folderStatus
                            Spacer()
                            folderPickerButton
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            folderStatus
                            folderPickerButton
                        }
                    }
                }

                if vaultManager.vaultURL != nil {
                    LabeledContent("Subfolder") {
                        TextField("Health", text: $vaultManager.healthSubfolder)
                            .font(Typography.mono())
                            .frame(minWidth: 160, maxWidth: 280, alignment: .trailing)
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

            // MARK: Purchases
            Section {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: purchaseManager.isFamilyUnlocked ? "person.3.fill" : (purchaseManager.isUnlocked ? "checkmark.seal.fill" : "lock.fill"))
                            .foregroundStyle(purchaseManager.isUnlocked ? Color.accent : Color.textMuted)
                            .frame(width: 20)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(purchaseStatusTitle)
                                .font(Typography.monoEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(purchaseStatusDetail)
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Purchases and Family Sharing")
                .accessibilityValue("\(purchaseStatusTitle), \(purchaseStatusDetail)")
            } header: {
                iPadBrandLabel("Purchases")
            }

            // MARK: Export Formats
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
                }
                if advancedSettings.exportFormats.isEmpty {
                    Text("Select at least one export format.")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .tint(Color.accent)

                if advancedSettings.exportFormats.contains(.markdown) {
                    Toggle("Include Frontmatter Metadata", isOn: $advancedSettings.includeMetadata)
                        .tint(Color.accent)
                    Toggle("Group by Category", isOn: $advancedSettings.groupByCategory)
                        .tint(Color.accent)
                }
            } header: {
                iPadBrandLabel("Export Formats")
            }

            // MARK: File Naming
            Section {
                LabeledContent("Filename Pattern") {
                    TextField("{date}", text: $advancedSettings.filenameFormat)
                        .font(Typography.mono())
                        .frame(minWidth: 160, maxWidth: 280, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Folder Structure") {
                    TextField("e.g. {year}/{month}", text: $advancedSettings.folderStructure)
                        .font(Typography.mono())
                        .frame(minWidth: 160, maxWidth: 280, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Organize by File Type", isOn: $advancedSettings.organizeFormatsIntoFolders)
                    .tint(Color.accent)

                Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}. File type folders use Markdown/, Bases/, JSON/, and CSV/.")
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textMuted)

                LabeledContent("Preview") {
                    let date = Date()
                    let format = advancedSettings.primaryFormat
                    let filename = advancedSettings.filename(for: date, format: format)
                    if let folder = advancedSettings.formatFolderPath(for: date, format: format) {
                        Text("\(folder)/\(filename)")
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.accent)
                    } else {
                        Text(filename)
                            .font(Typography.monoCaption())
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
            if advancedSettings.exportFormats.contains(.markdown) {
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
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textMuted)
            }

            // MARK: Health Metrics
            Section {
                if usesVerticalControlRows {
                    VStack(alignment: .leading, spacing: 12) {
                        metricsSummary
                        ProgressView(
                            value: Double(advancedSettings.metricSelection.totalEnabledCount),
                            total: Double(advancedSettings.metricSelection.totalMetricCount)
                        )
                        .tint(Color.accent)
                        metricsConfigureButton
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            metricsSummary
                            Spacer()
                            ProgressView(
                                value: Double(advancedSettings.metricSelection.totalEnabledCount),
                                total: Double(advancedSettings.metricSelection.totalMetricCount)
                            )
                            .frame(width: metricProgressWidth)
                            .tint(Color.accent)
                            metricsConfigureButton
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            metricsSummary
                            metricsConfigureButton
                        }
                    }
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
                                .font(.caption2)
                                .foregroundStyle(Color.textMuted)
                            Text("Pending")
                                .font(Typography.monoEmphasis())
                                .foregroundStyle(Color.textMuted)
                        } else {
                            let enabled = advancedSettings.metricSelection.enabledMetricCount(for: category)
                            let total = advancedSettings.metricSelection.totalMetricCount(for: category)
                            Text("\(enabled)/\(total)")
                                .font(Typography.monoEmphasis())
                                .foregroundStyle(Color.textMuted)
                        }
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
                            .font(Typography.mono())
                            .frame(minWidth: 160, maxWidth: 280, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Organize by Category", isOn: $advancedSettings.individualTracking.useCategoryFolders)
                        .tint(Color.accent)

                    LabeledContent("Tracked Metrics") {
                        Text("\(advancedSettings.individualTracking.totalEnabledCount)")
                            .font(Typography.monoEmphasis())
                            .foregroundStyle(Color.accent)
                    }
                }
            } header: {
                iPadBrandLabel("Individual Entry Tracking")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                    if advancedSettings.individualTracking.globalEnabled && advancedSettings.individualTracking.totalEnabledCount == 0 {
                        Text("⚠️ No metrics selected — individual entries won't be created until you select metrics to track.")
                            .font(Typography.monoCaptionEmphasis())
                            .foregroundStyle(Color.orange)
                    }
                }
            }

            // MARK: Community
            Section {
                Button {
                    UIApplication.shared.open(discordURL)
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                        Text("Join our Discord")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join our Discord")
            } header: {
                iPadBrandLabel("Community")
            } footer: {
                Text("Chat with other Health.md users, share feedback, and get help.")
                    .font(Typography.monoCaption())
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
                .accessibilityLabel("Send feedback")

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
                .accessibilityLabel("Report a bug on GitHub")
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
            iPadMetricSelectionView(
                selectionState: advancedSettings.metricSelection,
                healthKitManager: healthKitManager
            )
        }
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var folderStatus: some View {
        HStack(spacing: 8) {
            if let url = vaultManager.vaultURL {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vaultManager.vaultName)
                        .font(Typography.monoEmphasis())
                    Text(url.path(percentEncoded: false))
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(Color.textMuted)
                Text("No folder selected")
                    .font(Typography.mono())
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var folderPickerButton: some View {
        Button(vaultManager.vaultURL != nil ? "Change…" : "Choose…") {
            showFolderPicker = true
        }
        .tint(Color.accent)
    }

    private var metricsSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Selected Metrics")
                .font(Typography.monoEmphasis())
            Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textMuted)
        }
    }

    private var metricsConfigureButton: some View {
        Button("Configure…") {
            showMetricSelection = true
        }
        .tint(Color.accent)
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
                        .font(Typography.mono())
                    Spacer()
                    Text("(empty)")
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                    Button {
                        config.placeholderFields.removeAll { $0 == key }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove placeholder field \(key)")
                }
            }
            
            // Add new placeholder field
            HStack {
                TextField("Field name (e.g., omron_systolic)", text: $newPlaceholderKey)
                    .font(Typography.mono())
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
