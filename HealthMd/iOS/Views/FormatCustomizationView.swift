//
//  FormatCustomizationView.swift
//  Health.md
//
//  Customization options for export format, date/time, units, and templates
//

import SwiftUI

struct FormatCustomizationView: View {
    @ObservedObject var customization: FormatCustomization

    private var previewDate: Date { Date() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                pageHeader
                formatBasicsCard
                frontmatterAndTemplateCard
                previewCard
                resetButton
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgPrimary.ignoresSafeArea())
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
                subtitle: "Preview: \(customization.dateFormat.format(date: previewDate))",
                selection: $customization.dateFormat,
                options: DateFormatPreference.allCases,
                optionTitle: { $0.displayName }
            )
            FormatDivider()
            FormatSelectionRow(
                title: "Time Format",
                subtitle: "Preview: \(customization.timeFormat.format(date: previewDate))",
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
                    subtitle: "\(enabledFrontmatterCount) fields configured",
                    status: "Schema-Safe"
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
            customization.reset()
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.counterclockwise")
                    .accessibilityHidden(true)
                Text("Reset to Defaults")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(Color.error)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .frame(maxWidth: .infinity)
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
        let summary = template.includeSummary ? "Summary On" : "Summary Off"
        let emoji = template.useEmoji ? "Emoji On" : "Emoji Off"
        return "\(header) · \(summary) · \(emoji)"
    }

    private var previewText: String {
        let date = Date()
        let converter = customization.unitConverter

        var preview = ""
        preview += "Date: \(customization.dateFormat.format(date: date))\n"
        preview += "Time: \(customization.timeFormat.format(date: date))\n"
        preview += "Distance: \(converter.formatDistance(5000))\n"
        preview += "Weight: \(converter.formatWeight(70))\n"
        preview += "Temperature: \(converter.formatTemperature(37.0))"

        return preview
    }
}

// MARK: - Frontmatter Customization View

struct FrontmatterCustomizationView: View {
    @ObservedObject var config: FrontmatterConfiguration
    @State private var showAddCustomField = false
    @State private var showAddPlaceholderField = false
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State private var newPlaceholderKey = ""
    @State private var searchText = ""

    var body: some View {
        ScrollView {
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
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Frontmatter Fields")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Enable All Fields") {
                        for index in config.fields.indices {
                            config.fields[index].isEnabled = true
                        }
                    }
                    Button("Disable All Fields") {
                        for index in config.fields.indices {
                            config.fields[index].isEnabled = false
                        }
                    }
                    Divider()
                    Menu("Key Style") {
                        ForEach(FrontmatterKeyStyle.allCases, id: \.self) { style in
                            Button {
                                config.applyKeyStyle(style)
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
                        config.applyKeyStyle(.snakeCase)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Frontmatter field actions")
                .accessibilityHint("Opens actions for frontmatter fields and key styles")
            }
        }
        .alert("Add Custom Field", isPresented: $showAddCustomField) {
            TextField("Field name (e.g., tags)", text: $newFieldKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Value (e.g., health, daily)", text: $newFieldValue)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                newFieldKey = ""
                newFieldValue = ""
            }
            Button("Add Field") {
                if !newFieldKey.isEmpty {
                    config.customFields[newFieldKey] = newFieldValue
                }
                newFieldKey = ""
                newFieldValue = ""
            }
        } message: {
            Text("Add a custom field that will be included in every export.")
        }
        .alert("Add Placeholder Field", isPresented: $showAddPlaceholderField) {
            TextField("Field name (e.g., omron_systolic)", text: $newPlaceholderKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                newPlaceholderKey = ""
            }
            Button("Add Placeholder") {
                if !newPlaceholderKey.isEmpty && !config.placeholderFields.contains(newPlaceholderKey) {
                    config.placeholderFields.append(newPlaceholderKey)
                }
                newPlaceholderKey = ""
            }
        } message: {
            Text("Add a field that will export with an empty value for manual entry.")
        }
    }

    private var frontmatterSummary: some View {
        HStack(spacing: Spacing.md) {
            FormatStatPill(title: "Enabled", value: "\(enabledFieldCount)/\(config.fields.count)")
            FormatStatPill(title: "Custom", value: "\(config.customFields.count)")
            FormatStatPill(title: "Placeholders", value: "\(config.placeholderFields.count)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(enabledFieldCount) of \(config.fields.count) health metric fields enabled, \(config.customFields.count) custom fields, \(config.placeholderFields.count) placeholder fields")
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
                        FrontmatterFieldRow(field: binding(for: field))
                        if index < filteredFields.count - 1 {
                            FormatDivider()
                                .padding(.leading, 54)
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

            TextField("Search Fields", text: $searchText)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search frontmatter fields")
                .accessibilityHint("Type to filter health metric field keys")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textMuted)
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
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(key)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(value.isEmpty ? "Empty Value" : value)
                    .font(.footnote)
                    .foregroundStyle(value.isEmpty ? Color.textMuted : Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(role: .destructive) {
                config.customFields.removeValue(forKey: key)
            } label: {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.error)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.error.opacity(0.08)))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(key)")
        }
        .padding(.vertical, Spacing.sm)
    }

    private func placeholderFieldRow(key: String) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(key)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Empty on export")
                    .font(.footnote)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            Button(role: .destructive) {
                config.placeholderFields.removeAll { $0 == key }
            } label: {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.error)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.error.opacity(0.08)))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(key)")
        }
        .padding(.vertical, Spacing.sm)
    }

    private func fieldCategoryDisclosure(_ category: (name: String, fields: [CustomFrontmatterField])) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(category.fields.enumerated()), id: \.element.originalKey) { index, field in
                    if let fieldIndex = config.fields.firstIndex(where: { $0.originalKey == field.originalKey }) {
                        FrontmatterFieldRow(field: $config.fields[fieldIndex])
                        if index < category.fields.count - 1 {
                            FormatDivider()
                                .padding(.leading, 54)
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
                    Text("\(categoryEnabledCount(for: category.fields)) of \(category.fields.count) enabled")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                FormatValuePill(text: "\(category.fields.count)")
            }
            .padding(.vertical, Spacing.sm)
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
    @State private var isEditing = false
    @State private var tempCustomKey = ""

    private var fieldDisplayName: String {
        if field.customKey != field.originalKey && !field.customKey.isEmpty {
            return "\(field.originalKey) renamed to \(field.customKey)"
        }
        return field.originalKey
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Toggle("", isOn: $field.isEnabled)
                .labelsHidden()
                .tint(Color.accent)
                .accessibilityLabel(fieldDisplayName)
                .accessibilityValue(field.isEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Double tap to \(field.isEnabled ? "disable" : "enable") this field")

            VStack(alignment: .leading, spacing: 3) {
                Text(field.originalKey)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(field.isEnabled ? Color.textPrimary : Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if field.customKey != field.originalKey && !field.customKey.isEmpty {
                    Text("Renamed to \(field.customKey)")
                        .font(.footnote)
                        .foregroundStyle(Color.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(field.isEnabled ? "Included in frontmatter" : "Not exported")
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .accessibilityHidden(true)

            Spacer(minLength: Spacing.sm)

            Button(action: {
                tempCustomKey = field.customKey
                isEditing = true
            }) {
                Image(systemName: "pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.bgSecondary))
                    .overlay(Circle().strokeBorder(Color.borderSubtle, lineWidth: 1))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(field.originalKey)")
            .accessibilityHint("Double tap to enter a custom name for this field")
        }
        .padding(.vertical, Spacing.sm)
        .alert("Rename Field", isPresented: $isEditing) {
            TextField(field.originalKey, text: $tempCustomKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save Name") {
                field.customKey = tempCustomKey.isEmpty ? field.originalKey : tempCustomKey
            }
            Button("Reset Name") {
                field.customKey = field.originalKey
            }
        } message: {
            Text("Enter a custom name for \(field.originalKey).")
        }
    }
}

// MARK: - Markdown Template View

struct MarkdownTemplateView: View {
    @Binding var config: MarkdownTemplateConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FormatPageHeader(
                    icon: "doc.plaintext",
                    title: "Markdown Template",
                    subtitle: "Adjust the readable Markdown body while keeping structured data intact."
                )

                templateStyleCard
                optionsCard

                if config.style == .custom {
                    customTemplateCard
                }

                previewCard
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgPrimary.ignoresSafeArea())
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

    private var customTemplateCard: some View {
        FormatSectionCard(
            title: "Custom Template",
            subtitle: "Use placeholders to control the Markdown body."
        ) {
            TextEditor(text: $config.customTemplate)
                .font(.caption.monospaced())
                .foregroundStyle(Color.textPrimary)
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityLabel("Custom template")

            FormatDivider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Available Placeholders")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("{{date}}, {{#section}}...{{/section}}, {{metrics}}")
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textMuted)
                    .textSelection(.enabled)
            }
            .padding(.vertical, Spacing.sm)
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
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 40, height: 40)
            .overlay(Circle().strokeBorder(Color.accent.opacity(0.24), lineWidth: 1))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.displayMedium())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormatSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    private let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bgTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
    }
}

private struct FormatSelectionRow<Value: Hashable>: View {
    let title: String
    let subtitle: String
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        HStack {
                            Text(optionTitle(option))
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityValue(selection == option ? "Selected" : "Not selected")
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(optionTitle(selection))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs + 2)
                .frame(maxWidth: 190, alignment: .trailing)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
            }
            .accessibilityLabel(title)
            .accessibilityValue(optionTitle(selection))
        }
        .padding(.vertical, Spacing.sm)
    }
}

private struct FormatToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accessibilityLabel: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.accent)
        .padding(.vertical, Spacing.sm)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "Enabled" : "Disabled")
    }
}

private struct FormatTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let defaultValue: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Default: \(defaultValue)")
                    .font(.footnote)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer(minLength: Spacing.sm)

            TextField(placeholder, text: $text)
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs + 2)
                .frame(maxWidth: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(text.isEmpty ? defaultValue : text)
        }
        .padding(.vertical, Spacing.sm)
    }
}

private struct FormatNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accent.opacity(0.12)))
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.18), lineWidth: 1))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    FormatValuePill(text: status)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }
}

private struct FormatCodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textPrimary)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }
}

private struct FormatStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }
}

private struct FormatValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.bgSecondary))
            .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
    }
}

private struct FormatEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormatInlineButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.accent)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct FormatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }
}
