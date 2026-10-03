//
//  FormatCustomizationView.swift
//  Health.md
//
//  Customization options for export format, date/time, units, and templates
//

import SwiftUI

struct FormatCustomizationView: View {
    @ObservedObject var customization: FormatCustomization
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    private var previewDate: Date { Date() }

    var body: some View {
        FormatPageScroll { _ in
            VStack(alignment: .leading, spacing: Spacing.lg) {
                pageHeader
                formatBasicsCard
                frontmatterAndTemplateCard
                previewCard
                resetButton
            }
        }
        .navigationTitle("Format Customization")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pageHeader: some View {
        FormatPageHeader(
            icon: "slider.horizontal.3",
            title: "Format Customization",
            subtitle: "Tune presentation settings without changing Health.md’s export schema."
        )
    }

    private var formatBasicsCard: some View {
        FormatSectionCard(
            title: "Date, Time, and Units",
            subtitle: "These choices affect display values in exported files."
        ) {
            FormatSelectionRow(
                title: "Date Format",
                subtitle: String(localized: "Preview: \(customization.dateFormat.format(date: previewDate))"),
                selection: $customization.dateFormat,
                options: DateFormatPreference.allCases,
                optionTitle: { $0.displayName }
            )
            FormatDivider()
            FormatSelectionRow(
                title: "Time Format",
                subtitle: String(localized: "Preview: \(customization.timeFormat.format(date: previewDate))"),
                selection: $customization.timeFormat,
                options: TimeFormatPreference.allCases,
                optionTitle: { $0.displayName }
            )
            FormatDivider()
            FormatSelectionRow(
                title: "Unit System",
                subtitle: customization.unitPreference.description,
                selection: $customization.unitPreference,
                options: UnitPreference.allCases,
                optionTitle: { $0.displayName }
            )
        }
    }

    private var frontmatterAndTemplateCard: some View {
        FormatSectionCard(
            title: "Output Details",
            subtitle: "Customize metadata fields and human-readable Markdown layout."
        ) {
            NavigationLink {
                FrontmatterCustomizationView(config: customization.frontmatterConfig)
            } label: {
                FormatNavigationRow(
                    icon: "number.square",
                    title: "Frontmatter Fields",
                    subtitle: String(localized: "\(enabledFrontmatterCount) fields configured"),
                    status: String(localized: "Schema-Safe")
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Frontmatter fields")
            .accessibilityValue("\(enabledFrontmatterCount) fields configured")
            .accessibilityHint("Double tap to customize frontmatter field names and enabled fields")

            FormatDivider()

            NavigationLink {
                MarkdownTemplateView(config: $customization.markdownTemplate)
            } label: {
                FormatNavigationRow(
                    icon: "doc.plaintext",
                    title: "Markdown Template",
                    subtitle: markdownTemplateSummary,
                    status: customization.markdownTemplate.style.displayName
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Markdown template")
            .accessibilityValue(markdownTemplateSummary)
            .accessibilityHint("Double tap to customize Markdown template settings")
        }
    }

    private var previewCard: some View {
        FormatSectionCard(title: "Format Preview") {
            FormatCodeBlock(text: previewText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Format preview")
                .accessibilityValue(previewText)
        }
    }

    private var resetButton: some View {
        Button(action: {
            configurationProtection.performConfigurationChange {
                customization.reset()
            }
        }) {
            FormatActionLabel(title: "Reset to Defaults", systemImage: "arrow.counterclockwise")
                .foregroundStyle(Color.errorText)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.error.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.error.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset to defaults")
        .accessibilityHint("Double tap to reset all format customizations to default values")
    }

    private var enabledFrontmatterCount: Int {
        customization.frontmatterConfig.fields.filter { $0.isEnabled }.count +
        customization.frontmatterConfig.customFields.count +
        customization.frontmatterConfig.placeholderFields.count
    }

    private var markdownTemplateSummary: String {
        let template = customization.markdownTemplate
        let header = "H\(template.sectionHeaderLevel)"
        let summary = template.includeSummary ? String(localized: "Summary On") : String(localized: "Summary Off")
        let emoji = template.useEmoji ? String(localized: "Emoji On") : String(localized: "Emoji Off")
        return "\(header) · \(summary) · \(emoji)"
    }

    private var previewText: String {
        let date = Date()
        let converter = customization.unitConverter

        var preview = ""
        preview += String(localized: "Date: \(customization.dateFormat.format(date: date))") + "\n"
        preview += String(localized: "Time: \(customization.timeFormat.format(date: date))") + "\n"
        preview += String(localized: "Distance: \(converter.formatDistance(5000))") + "\n"
        preview += String(localized: "Weight: \(converter.formatWeight(70))") + "\n"
        preview += String(localized: "Temperature: \(converter.formatTemperature(37.0))")

        return preview
    }
}

// MARK: - Frontmatter Customization View

struct FrontmatterCustomizationView: View {
    @ObservedObject var config: FrontmatterConfiguration
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var showAddCustomField = false
    @State private var showAddPlaceholderField = false
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State private var newPlaceholderKey = ""
    @State private var searchText = ""
    @State private var renameTargetKey: String?
    @State private var renameTempKey = ""

    private func startRenaming(originalKey: String, customKey: String) {
        renameTempKey = customKey
        renameTargetKey = originalKey
    }

    private func applyRename(_ newKey: String?) {
        guard let targetKey = renameTargetKey,
              let index = config.fields.firstIndex(where: { $0.originalKey == targetKey }) else { return }
        configurationProtection.performConfigurationChange {
            if let newKey, !newKey.isEmpty {
                config.fields[index].customKey = newKey
            } else {
                config.fields[index].customKey = config.fields[index].originalKey
            }
        }
    }

    var body: some View {
        FormatPageScroll { _ in
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FormatPageHeader(
                    icon: "number.square",
                    title: "Frontmatter Fields",
                    subtitle: "Choose the YAML fields written to Markdown and Obsidian Bases files."
                )

                frontmatterSummary
                coreFieldsCard
                customFieldsCard
                placeholderFieldsCard
                healthMetricFieldsCard
            }
        }
        .navigationTitle("Frontmatter Fields")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Enable All Fields") {
                        configurationProtection.performConfigurationChange {
                            for index in config.fields.indices {
                                config.fields[index].isEnabled = true
                            }
                        }
                    }
                    Button("Disable All Fields") {
                        configurationProtection.performConfigurationChange {
                            for index in config.fields.indices {
                                config.fields[index].isEnabled = false
                            }
                        }
                    }
                    Divider()
                    Menu("Key Style") {
                        ForEach(FrontmatterKeyStyle.allCases, id: \.self) { style in
                            Button {
                                configurationProtection.performConfigurationChange {
                                    config.applyKeyStyle(style)
                                }
                            } label: {
                                HStack {
                                    Text(style.displayName)
                                    if config.keyStyle == style {
                                        Image(systemName: "checkmark")
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                    Button("Reset Names") {
                        configurationProtection.performConfigurationChange {
                            config.applyKeyStyle(.snakeCase)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Frontmatter field actions")
                .accessibilityHint("Opens actions for frontmatter fields and key styles")
            }
        }
        .geistDialog(
            isPresented: $showAddCustomField,
            title: Text("Add Custom Field"),
            message: Text("Add a custom field that will be included in every export."),
            actions: [
                .cancel {
                    newFieldKey = ""
                    newFieldValue = ""
                },
                .action("Add Field") {
                    configurationProtection.performConfigurationChange {
                        if !newFieldKey.isEmpty {
                            config.customFields[newFieldKey] = newFieldValue
                        }
                        newFieldKey = ""
                        newFieldValue = ""
                    }
                }
            ],
            fields: [
                GeistDialogField(placeholder: "Field name (e.g., tags)", text: $newFieldKey),
                GeistDialogField(placeholder: "Value (e.g., health, daily)", text: $newFieldValue)
            ]
        )
        .geistDialog(
            isPresented: $showAddPlaceholderField,
            title: Text("Add Placeholder Field"),
            message: Text("Add a field that will export with an empty value for manual entry."),
            actions: [
                .cancel {
                    newPlaceholderKey = ""
                },
                .action("Add Placeholder") {
                    configurationProtection.performConfigurationChange {
                        if !newPlaceholderKey.isEmpty && !config.placeholderFields.contains(newPlaceholderKey) {
                            config.placeholderFields.append(newPlaceholderKey)
                        }
                        newPlaceholderKey = ""
                    }
                }
            ],
            fields: [
                GeistDialogField(placeholder: "Field name (e.g., omron_systolic)", text: $newPlaceholderKey)
            ]
        )
        .geistDialog(
            isPresented: Binding(
                get: { renameTargetKey != nil },
                set: { if !$0 { renameTargetKey = nil } }
            ),
            title: Text("Rename Field"),
            message: renameTargetKey.map { Text("Enter a custom name for \($0).") },
            actions: [
                .cancel(),
                .action("Save Name") { applyRename(renameTempKey) },
                .action("Reset Name") { applyRename(nil) }
            ],
            fields: [
                GeistDialogField(
                    placeholder: LocalizedStringKey(renameTargetKey ?? ""),
                    text: $renameTempKey
                )
            ]
        )
    }

    private var frontmatterSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                frontmatterStats
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                frontmatterStats
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(enabledFieldCount) of \(config.fields.count) health metric fields enabled, \(config.customFields.count) custom fields, \(config.placeholderFields.count) placeholder fields")
    }

    @ViewBuilder
    private var frontmatterStats: some View {
        FormatStatPill(title: "Enabled", value: "\(enabledFieldCount)/\(config.fields.count)")
        FormatStatPill(title: "Custom", value: "\(config.customFields.count)")
        FormatStatPill(title: "Placeholders", value: "\(config.placeholderFields.count)")
    }

    private var coreFieldsCard: some View {
        FormatSectionCard(
            title: "Core Metadata",
            subtitle: "Renaming keys changes field names in output, so keep downstream automations in mind."
        ) {
            FormatSelectionRow(
                title: "Key Style",
                subtitle: config.keyStyle.description,
                selection: Binding(
                    get: { config.keyStyle },
                    set: { config.applyKeyStyle($0) }
                ),
                options: FrontmatterKeyStyle.allCases,
                optionTitle: { $0.displayName }
            )

            FormatDivider()

            FormatToggleRow(
                title: "Include Date Field",
                subtitle: "Adds the export date to frontmatter.",
                isOn: $config.includeDate,
                accessibilityLabel: "Include date field in frontmatter"
            )

            if config.includeDate {
                FormatDivider()
                FormatTextFieldRow(
                    title: "Date Field Name",
                    placeholder: "date",
                    text: $config.customDateKey,
                    defaultValue: "date",
                    accessibilityLabel: "Date field name"
                )
            }

            FormatDivider()

            FormatToggleRow(
                title: "Include Type Field",
                subtitle: "Adds a fixed type value for Obsidian queries.",
                isOn: $config.includeType,
                accessibilityLabel: "Include type field in frontmatter"
            )

            if config.includeType {
                FormatDivider()
                FormatTextFieldRow(
                    title: "Type Field Name",
                    placeholder: "type",
                    text: $config.customTypeKey,
                    defaultValue: "type",
                    accessibilityLabel: "Type field name"
                )
                FormatDivider()
                FormatTextFieldRow(
                    title: "Type Field Value",
                    placeholder: "health-data",
                    text: $config.customTypeValue,
                    defaultValue: "health-data",
                    accessibilityLabel: "Type field value"
                )
            }
        }
    }

    private var customFieldsCard: some View {
        FormatSectionCard(
            title: "Custom Static Fields",
            subtitle: "Fixed values added to every export, like tags or author."
        ) {
            if config.customFields.isEmpty {
                FormatEmptyState(
                    title: "No Custom Fields",
                    message: "Add a fixed key and value when every export should carry the same metadata."
                )
            } else {
                ForEach(Array(config.customFields.keys.sorted().enumerated()), id: \.element) { index, key in
                    customFieldRow(key: key, value: config.customFields[key] ?? "")
                    if index < config.customFields.count - 1 {
                        FormatDivider()
                    }
                }
            }

            FormatDivider()

            FormatInlineButton(title: "Add Custom Field", systemImage: "plus.circle") {
                showAddCustomField = true
            }
        }
    }

    private var placeholderFieldsCard: some View {
        FormatSectionCard(
            title: "Placeholder Fields",
            subtitle: "Empty fields for values you fill in manually after export."
        ) {
            if config.placeholderFields.isEmpty {
                FormatEmptyState(
                    title: "No Placeholder Fields",
                    message: "Add optional blank keys for manual notes, device readings, or review fields."
                )
            } else {
                ForEach(Array(config.placeholderFields.sorted().enumerated()), id: \.element) { index, key in
                    placeholderFieldRow(key: key)
                    if index < config.placeholderFields.count - 1 {
                        FormatDivider()
                    }
                }
            }

            FormatDivider()

            FormatInlineButton(title: "Add Placeholder Field", systemImage: "plus.circle") {
                showAddPlaceholderField = true
            }
        }
    }

    private var healthMetricFieldsCard: some View {
        FormatSectionCard(
            title: "Health Metric Fields",
            subtitle: "Enabled: \(enabledFieldCount) of \(config.fields.count)"
        ) {
            fieldSearchBar

            FormatDivider()

            if !searchText.isEmpty {
                if filteredFields.isEmpty {
                    FormatEmptyState(
                        title: "No Fields Found",
                        message: "Try another health metric field name."
                    )
                } else {
                    ForEach(Array(filteredFields.enumerated()), id: \.element.originalKey) { index, field in
                        FrontmatterFieldRow(field: binding(for: field)) { originalKey, customKey in
                            startRenaming(originalKey: originalKey, customKey: customKey)
                        }
                        if index < filteredFields.count - 1 {
                            FormatDivider()
                        }
                    }
                }
            } else {
                ForEach(Array(fieldCategories.enumerated()), id: \.element.name) { index, category in
                    fieldCategoryDisclosure(category)
                    if index < fieldCategories.count - 1 {
                        FormatDivider()
                    }
                }
            }
        }
    }

    private var fieldSearchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)

            TextField("Search Fields", text: $searchText,
                      prompt: Text("Search Fields").foregroundStyle(Color.textSecondary))
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityLabel("Search frontmatter fields")
                .accessibilityHint("Type to filter health metric field keys")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private func customFieldRow(key: String, value: String) -> some View {
        FormatFrontmatterEntry(
            key: key,
            value: value.isEmpty ? String(localized: "Empty Value") : value,
            deleteLabel: String(localized: "Delete custom field \(key)")
        ) {
            configurationProtection.performConfigurationChange {
                config.customFields.removeValue(forKey: key)
            }
        }
    }

    private func placeholderFieldRow(key: String) -> some View {
        FormatFrontmatterEntry(
            key: key,
            value: String(localized: "Empty on export"),
            deleteLabel: String(localized: "Delete placeholder field \(key)")
        ) {
            configurationProtection.performConfigurationChange {
                config.placeholderFields.removeAll { $0 == key }
            }
        }
    }

    private func fieldCategoryDisclosure(_ category: (name: String, fields: [CustomFrontmatterField])) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(category.fields.enumerated()), id: \.element.originalKey) { index, field in
                    if let fieldIndex = config.fields.firstIndex(where: { $0.originalKey == field.originalKey }) {
                        FrontmatterFieldRow(field: $config.fields[fieldIndex]) { originalKey, customKey in
                            startRenaming(originalKey: originalKey, customKey: customKey)
                        }
                        if index < category.fields.count - 1 {
                            FormatDivider()
                        }
                    }
                }
            }
            .padding(.top, Spacing.xs)
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(categoryEnabledCount(for: category.fields)) of \(category.fields.count) enabled")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FormatValuePill(text: "\(category.fields.count)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(Color.textSecondary)
    }

    private var enabledFieldCount: Int {
        config.fields.filter { $0.isEnabled }.count
    }

    private var filteredFields: [CustomFrontmatterField] {
        guard !searchText.isEmpty else { return config.fields }
        return config.fields.filter {
            $0.originalKey.localizedCaseInsensitiveContains(searchText) ||
            $0.customKey.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func binding(for field: CustomFrontmatterField) -> Binding<CustomFrontmatterField> {
        guard let index = config.fields.firstIndex(where: { $0.originalKey == field.originalKey }) else {
            return .constant(field)
        }
        return $config.fields[index]
    }

    private func categoryEnabledCount(for fields: [CustomFrontmatterField]) -> Int {
        fields.filter { field in
            config.fields.first(where: { $0.originalKey == field.originalKey })?.isEnabled == true
        }.count
    }

    private var fieldCategories: [(name: String, fields: [CustomFrontmatterField])] {
        let categoryPrefixes: [(name: String, prefixes: [String])] = [
            ("Sleep", ["sleep_"]),
            ("Activity", ["steps", "active_", "basal_", "exercise_", "stand_", "flights_", "walking_running", "cycling", "swimming", "wheelchair"]),
            ("Heart", ["resting_heart", "walking_heart", "average_heart", "heart_rate", "hrv"]),
            ("Vitals", ["respiratory", "blood_oxygen", "body_temperature", "blood_pressure", "blood_glucose"]),
            ("Body", ["weight", "height", "bmi", "body_fat", "lean_body", "waist"]),
            ("Nutrition", ["dietary", "protein", "carbohydrates", "fat", "saturated", "fiber", "sugar", "sodium", "cholesterol", "water", "caffeine"]),
            ("Mindfulness", ["mindful"]),
            ("Mobility", ["walking_speed", "step_length", "double_support", "walking_asymmetry", "stair_", "six_min"]),
            ("Hearing", ["headphone", "environmental"]),
            ("Workouts", ["workout"])
        ]

        return categoryPrefixes.map { category in
            let fields = config.fields.filter { field in
                category.prefixes.contains { prefix in
                    field.originalKey.hasPrefix(prefix)
                }
            }
            return (name: category.name, fields: fields)
        }.filter { !$0.fields.isEmpty }
    }
}

// MARK: - Frontmatter Field Row

struct FrontmatterFieldRow: View {
    @Binding var field: CustomFrontmatterField
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    let onRename: (String, String) -> Void

    var body: some View {
        FormatFrontmatterFieldContent(
            originalKey: field.originalKey,
            customKey: field.customKey,
            isEnabled: configurationProtection.protecting($field.isEnabled)
        ) {
            FormatInlineButton(title: "Rename Field", systemImage: "pencil") {
                onRename(field.originalKey, field.customKey)
            }
            .accessibilityLabel("Rename \(field.originalKey)")
            .accessibilityHint("Double tap to enter a custom name for this field")
        }
    }
}

// MARK: - Markdown Template View

struct MarkdownTemplateView: View {
    @Binding var config: MarkdownTemplateConfig
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        FormatPageScroll { availableHeight in
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FormatPageHeader(
                    icon: "doc.plaintext",
                    title: "Markdown Template",
                    subtitle: "Adjust the readable Markdown body while keeping structured data intact."
                )

                templateStyleCard
                optionsCard

                if config.style == .custom {
                    FormatTemplateEditor(
                        text: configurationProtection.protecting($config.customTemplate),
                        availableHeight: availableHeight
                    )
                }

                previewCard
            }
        }
        .navigationTitle("Markdown Template")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var templateStyleCard: some View {
        FormatSectionCard(
            title: "Template Style",
            subtitle: config.style.description
        ) {
            FormatSelectionRow(
                title: "Style",
                subtitle: "Choose the overall Markdown layout.",
                selection: $config.style,
                options: MarkdownTemplateStyle.allCases,
                optionTitle: { $0.displayName }
            )
        }
    }

    private var optionsCard: some View {
        FormatSectionCard(
            title: "Markdown Options",
            subtitle: "Small formatting choices for headings, bullets, and summary text."
        ) {
            FormatSelectionRow(
                title: "Section Headers",
                subtitle: "Controls the heading level for each category.",
                selection: $config.sectionHeaderLevel,
                options: [1, 2, 3],
                optionTitle: { level in
                    String(repeating: "#", count: level) + " H\(level)"
                }
            )
            .accessibilityLabel("Section header level")
            .accessibilityValue("H\(config.sectionHeaderLevel)")

            FormatDivider()

            FormatSelectionRow(
                title: "Bullet Style",
                subtitle: "Used for metric lines inside each section.",
                selection: $config.bulletStyle,
                options: MarkdownTemplateConfig.BulletStyle.allCases,
                optionTitle: { $0.displayName }
            )
            .accessibilityLabel("Bullet style")
            .accessibilityValue(config.bulletStyle.displayName)

            FormatDivider()

            FormatToggleRow(
                title: "Use Emoji in Headers",
                subtitle: "Adds category emoji to Markdown headings.",
                isOn: $config.useEmoji,
                accessibilityLabel: "Use emoji in section headers"
            )

            FormatDivider()

            FormatToggleRow(
                title: "Include Summary",
                subtitle: "Adds a short overview below the title.",
                isOn: $config.includeSummary,
                accessibilityLabel: "Include summary at top of document"
            )
        }
    }

    private var previewCard: some View {
        FormatSectionCard(title: "Markdown Preview") {
            FormatCodeBlock(text: previewText)
        }
    }

    private var previewText: String {
        let headerPrefix = String(repeating: "#", count: config.sectionHeaderLevel)
        let bullet = config.bulletStyle.rawValue
        let sleepEmoji = config.useEmoji ? "😴 " : ""
        let activityEmoji = config.useEmoji ? "🏃 " : ""

        var preview = "# Health Data — 2026-01-13\n\n"

        if config.includeSummary {
            preview += "7h 30m sleep · 8,432 steps · 2 workouts\n\n"
        }

        preview += "\(headerPrefix) \(sleepEmoji)Sleep\n\n"
        preview += "\(bullet) **Total:** 7h 30m\n"
        preview += "\(bullet) **Bedtime:** 23:15\n"
        preview += "\(bullet) **Wake:** 06:45\n"
        preview += "\(bullet) **Deep:** 1h 45m\n\n"

        preview += "\(headerPrefix) \(activityEmoji)Activity\n\n"
        preview += "\(bullet) **Steps:** 8,432\n"
        preview += "\(bullet) **Calories:** 420 kcal"

        return preview
    }
}

// MARK: - Geist Format Customization Components

private struct FormatPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HealthMdPageHeader(title: title, subtitle: subtitle)
    }
}

private struct FormatSelectionRow<Value: Hashable>: View {
    let title: String
    let subtitle: String
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        FormatSelectionControl(
            title: title, subtitle: subtitle, selection: selection,
            options: options, optionTitle: optionTitle
        ) { option in
            configurationProtection.performConfigurationChange {
                selection = option
            }
        }
    }
}

private struct FormatToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accessibilityLabel: String
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        FormatToggleControl(
            title: title, subtitle: subtitle,
            isOn: configurationProtection.protecting($isOn),
            accessibilityLabel: accessibilityLabel
        )
    }
}

private struct FormatTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let defaultValue: String
    let accessibilityLabel: String
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        FormatTextFieldControl(
            title: title, placeholder: placeholder,
            text: configurationProtection.protecting($text),
            defaultValue: defaultValue, accessibilityLabel: accessibilityLabel
        )
    }
}
