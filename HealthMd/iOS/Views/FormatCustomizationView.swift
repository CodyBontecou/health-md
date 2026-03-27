//
//  FormatCustomizationView.swift
//  Health.md
//
//  Customization options for export format, date/time, units, and templates
//

import SwiftUI

struct FormatCustomizationView: View {
    @ObservedObject var customization: FormatCustomization
    
    var body: some View {
        Form {
            // Date & Time Section
            Section {
                Picker("Date Format", selection: $customization.dateFormat) {
                    ForEach(DateFormatPreference.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Date format")
                .accessibilityValue(customization.dateFormat.displayName)
                
                Picker("Time Format", selection: $customization.timeFormat) {
                    ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Time format")
                .accessibilityValue(customization.timeFormat.displayName)
            } header: {
                Text("Date & Time")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text("Controls how dates and times appear in your exported files")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Units Section
            Section {
                Picker("Unit System", selection: $customization.unitPreference) {
                    ForEach(UnitPreference.allCases, id: \.self) { unit in
                        VStack(alignment: .leading) {
                            Text(unit.displayName).tag(unit)
                        }
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Unit system")
                .accessibilityValue(customization.unitPreference.displayName)
            } header: {
                Text("Units")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text(customization.unitPreference.description)
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Frontmatter Section
            Section {
                NavigationLink {
                    FrontmatterCustomizationView(config: customization.frontmatterConfig)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Frontmatter Fields")
                                .font(Typography.body())
                            Text("\(enabledFrontmatterCount) fields configured")
                                .font(Typography.caption())
                                .foregroundColor(Color.textSecondary)
                        }
                        Spacer()
                    }
                }

                Toggle("Frontmatter Only", isOn: $customization.markdownTemplate.frontmatterOnly)
                    .tint(Color.accent)
                    .accessibilityLabel("Frontmatter only mode")
                    .accessibilityValue(customization.markdownTemplate.frontmatterOnly ? "Enabled" : "Disabled")
            } header: {
                Text("Frontmatter")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text(customization.markdownTemplate.frontmatterOnly
                    ? "Only YAML frontmatter will be generated — no markdown body. Use with Update write mode to merge health metrics into existing daily notes."
                    : "Health metrics are included in both frontmatter fields and the markdown body")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Markdown Template Section
            Section {
                NavigationLink {
                    MarkdownTemplateView(config: $customization.markdownTemplate)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Markdown Template")
                                .font(Typography.body())
                            Text(customization.markdownTemplate.style.displayName)
                                .font(Typography.caption())
                                .foregroundColor(Color.textSecondary)
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Template")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text("Choose a template style or create your own custom format")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Preview Section
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Format Preview")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(Color.textSecondary)
                    
                    Text(previewText)
                        .font(.caption.monospaced())
                        .foregroundColor(Color.textPrimary)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Format preview")
                .accessibilityValue(previewText)
            } header: {
                Text("Preview")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            }
            
            // Reset Section
            Section {
                Button(action: {
                    customization.reset()
                }) {
                    HStack {
                        Spacer()
                        Text("Reset to Defaults")
                            .font(Typography.body())
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .accessibilityLabel("Reset to defaults")
                .accessibilityHint("Double tap to reset all format customizations to default values")
            }
        }
        .navigationTitle("Format Customization")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var enabledFrontmatterCount: Int {
        customization.frontmatterConfig.fields.filter { $0.isEnabled }.count +
        customization.frontmatterConfig.customFields.count +
        customization.frontmatterConfig.placeholderFields.count
    }
    
    private var previewText: String {
        let date = Date()
        let converter = customization.unitConverter
        
        var preview = ""
        preview += "Date: \(customization.dateFormat.format(date: date))\n"
        preview += "Time: \(customization.timeFormat.format(date: date))\n"
        preview += "Distance: \(converter.formatDistance(5000))\n"
        preview += "Weight: \(converter.formatWeight(70))\n"
        preview += "Temp: \(converter.formatTemperature(37.0))"
        
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
        Form {
            // Key Style Section
            Section {
                Picker("Key Style", selection: Binding(
                    get: { config.keyStyle },
                    set: { newStyle in
                        config.applyKeyStyle(newStyle)
                    }
                )) {
                    ForEach(FrontmatterKeyStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .tint(Color.accent)
            } header: {
                Text("Key Format")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text(config.keyStyle.description)
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Core Fields Section
            Section {
                Toggle("Include Date Field", isOn: $config.includeDate)
                    .tint(Color.accent)
                    .accessibilityLabel("Include date field in frontmatter")
                    .accessibilityValue(config.includeDate ? "Enabled" : "Disabled")
                
                if config.includeDate {
                    HStack {
                        Text("Field Name")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("date", text: $config.customDateKey)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                            .accessibilityLabel("Date field name")
                            .accessibilityValue(config.customDateKey.isEmpty ? "date" : config.customDateKey)
                    }
                }
                
                Toggle("Include Type Field", isOn: $config.includeType)
                    .tint(Color.accent)
                    .accessibilityLabel("Include type field in frontmatter")
                    .accessibilityValue(config.includeType ? "Enabled" : "Disabled")
                
                if config.includeType {
                    HStack {
                        Text("Field Name")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("type", text: $config.customTypeKey)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                            .accessibilityLabel("Type field name")
                            .accessibilityValue(config.customTypeKey.isEmpty ? "type" : config.customTypeKey)
                    }
                    
                    HStack {
                        Text("Value")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("health-data", text: $config.customTypeValue)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                            .accessibilityLabel("Type field value")
                            .accessibilityValue(config.customTypeValue.isEmpty ? "health-data" : config.customTypeValue)
                    }
                }
            } header: {
                Text("Core Fields")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            }
            
            // Custom Static Fields Section
            Section {
                ForEach(Array(config.customFields.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(Typography.body())
                        Spacer()
                        Text(config.customFields[key] ?? "")
                            .foregroundColor(Color.textSecondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            config.customFields.removeValue(forKey: key)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                
                Button(action: { showAddCustomField = true }) {
                    Label("Add Custom Field", systemImage: "plus.circle")
                        .foregroundColor(Color.accent)
                }
            } header: {
                Text("Custom Static Fields")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text("Add fields with fixed values to every export (e.g., tags, author)")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Placeholder Fields Section (for manual entry)
            Section {
                ForEach(config.placeholderFields.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(Typography.body())
                        Spacer()
                        Text("(empty)")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)
                            .italic()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            config.placeholderFields.removeAll { $0 == key }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                
                Button(action: { showAddPlaceholderField = true }) {
                    Label("Add Placeholder Field", systemImage: "plus.circle")
                        .foregroundColor(Color.accent)
                }
            } header: {
                Text("Placeholder Fields")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text("Add fields with empty values for manual entry after export (e.g., omron_systolic, omron_diastolic, notes)")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Health Metric Fields Section
            Section {
                if !searchText.isEmpty {
                    ForEach(filteredFields.indices, id: \.self) { index in
                        FrontmatterFieldRow(field: binding(for: filteredFields[index]))
                    }
                } else {
                    ForEach(fieldCategories, id: \.name) { category in
                        DisclosureGroup(category.name) {
                            ForEach(category.fields.indices, id: \.self) { index in
                                if let fieldIndex = config.fields.firstIndex(where: { $0.originalKey == category.fields[index].originalKey }) {
                                    FrontmatterFieldRow(field: $config.fields[fieldIndex])
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Health Metric Fields")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                    Spacer()
                    Text("\(config.fields.filter { $0.isEnabled }.count)/\(config.fields.count)")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }
            }
            .searchable(text: $searchText, prompt: "Search fields")
        }
        .navigationTitle("Frontmatter Fields")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Enable All") {
                        for i in config.fields.indices {
                            config.fields[i].isEnabled = true
                        }
                    }
                    Button("Disable All") {
                        for i in config.fields.indices {
                            config.fields[i].isEnabled = false
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
                }
            }
        }
        .alert("Add Custom Field", isPresented: $showAddCustomField) {
            TextField("Field name (e.g., tags)", text: $newFieldKey)
            TextField("Value (e.g., health, daily)", text: $newFieldValue)
            Button("Cancel", role: .cancel) {
                newFieldKey = ""
                newFieldValue = ""
            }
            Button("Add") {
                if !newFieldKey.isEmpty {
                    config.customFields[newFieldKey] = newFieldValue
                }
                newFieldKey = ""
                newFieldValue = ""
            }
        } message: {
            Text("Add a custom field that will be included in every export")
        }
        .alert("Add Placeholder Field", isPresented: $showAddPlaceholderField) {
            TextField("Field name (e.g., omron_systolic)", text: $newPlaceholderKey)
            Button("Cancel", role: .cancel) {
                newPlaceholderKey = ""
            }
            Button("Add") {
                if !newPlaceholderKey.isEmpty && !config.placeholderFields.contains(newPlaceholderKey) {
                    config.placeholderFields.append(newPlaceholderKey)
                }
                newPlaceholderKey = ""
            }
        } message: {
            Text("Add a field that will export with an empty value for you to fill in manually")
        }
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
        HStack {
            Toggle("", isOn: $field.isEnabled)
                .labelsHidden()
                .tint(Color.accent)
                .accessibilityLabel(fieldDisplayName)
                .accessibilityValue(field.isEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Double tap to \(field.isEnabled ? "disable" : "enable") this field")
            
            VStack(alignment: .leading, spacing: 2) {
                Text(field.originalKey)
                    .font(Typography.body())
                    .foregroundColor(field.isEnabled ? Color.textPrimary : Color.textMuted)
                
                if field.customKey != field.originalKey && !field.customKey.isEmpty {
                    Text("→ \(field.customKey)")
                        .font(Typography.caption())
                        .foregroundColor(Color.accent)
                }
            }
            .accessibilityHidden(true)
            
            Spacer()
            
            Button(action: {
                tempCustomKey = field.customKey
                isEditing = true
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(field.originalKey)")
            .accessibilityHint("Double tap to enter a custom name for this field")
        }
        .alert("Rename Field", isPresented: $isEditing) {
            TextField(field.originalKey, text: $tempCustomKey)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                field.customKey = tempCustomKey.isEmpty ? field.originalKey : tempCustomKey
            }
            Button("Reset") {
                field.customKey = field.originalKey
            }
        } message: {
            Text("Enter a custom name for '\(field.originalKey)'")
        }
    }
}

// MARK: - Markdown Template View

struct MarkdownTemplateView: View {
    @Binding var config: MarkdownTemplateConfig
    
    var body: some View {
        Form {
            // Template Style Section
            Section {
                Picker("Style", selection: $config.style) {
                    ForEach(MarkdownTemplateStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .tint(Color.accent)
            } header: {
                Text("Template Style")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text(config.style.description)
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            // Options Section
            Section {
                Picker("Section Headers", selection: $config.sectionHeaderLevel) {
                    Text("# H1").tag(1)
                    Text("## H2").tag(2)
                    Text("### H3").tag(3)
                }
                .tint(Color.accent)
                .accessibilityLabel("Section header level")
                .accessibilityValue("H\(config.sectionHeaderLevel)")
                
                Picker("Bullet Style", selection: $config.bulletStyle) {
                    ForEach(MarkdownTemplateConfig.BulletStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .tint(Color.accent)
                .accessibilityLabel("Bullet style")
                .accessibilityValue(config.bulletStyle.displayName)
                
                Toggle("Use Emoji in Headers", isOn: $config.useEmoji)
                    .tint(Color.accent)
                    .accessibilityLabel("Use emoji in section headers")
                    .accessibilityValue(config.useEmoji ? "Enabled" : "Disabled")
                
                Toggle("Include Summary", isOn: $config.includeSummary)
                    .tint(Color.accent)
                    .accessibilityLabel("Include summary at top of document")
                    .accessibilityValue(config.includeSummary ? "Enabled" : "Disabled")
            } header: {
                Text("Options")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            }
            
            // Custom Template Section
            if config.style == .custom {
                Section {
                    TextEditor(text: $config.customTemplate)
                        .font(.caption.monospaced())
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                } header: {
                    Text("Custom Template")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available placeholders:")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)
                        Text("{{date}}, {{#section}}...{{/section}}, {{metrics}}")
                            .font(.caption2.monospaced())
                            .foregroundColor(Color.textMuted)
                    }
                }
            }
            
            // Preview Section
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(previewText)
                        .font(.caption.monospaced())
                        .foregroundColor(Color.textPrimary)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            } header: {
                Text("Preview")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            }
        }
        .navigationTitle("Markdown Template")
        .navigationBarTitleDisplayMode(.inline)
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
