//
//  FormatCustomizationView.swift
//  Health.md
//
//  Customization options for export format, date/time, units, and templates
//

import SwiftUI

struct FormatCustomizationView: View {
    @ObservedObject var customization: FormatCustomization
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // Date & Time Section
                Section {
                    Picker("Date Format", selection: $customization.dateFormat) {
                        ForEach(DateFormatPreference.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .tint(Color.accent)
                    
                    Picker("Time Format", selection: $customization.timeFormat) {
                        ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .tint(Color.accent)
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
                } header: {
                    Text("Frontmatter")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Customize field names and add custom properties for Obsidian Bases format")
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                        
                        Text(previewText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
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
                }
            }
            .navigationTitle("Format Customization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Typography.body())
                    .foregroundColor(Color.accent)
                }
            }
        }
    }
    
    private var enabledFrontmatterCount: Int {
        customization.frontmatterConfig.fields.filter { $0.isEnabled }.count +
        customization.frontmatterConfig.customFields.count
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
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State private var searchText = ""
    
    var body: some View {
        Form {
            // Core Fields Section
            Section {
                Toggle("Include Date Field", isOn: $config.includeDate)
                    .tint(Color.accent)
                
                if config.includeDate {
                    HStack {
                        Text("Field Name")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("date", text: $config.customDateKey)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                    }
                }
                
                Toggle("Include Type Field", isOn: $config.includeType)
                    .tint(Color.accent)
                
                if config.includeType {
                    HStack {
                        Text("Field Name")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("type", text: $config.customTypeKey)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                    }
                    
                    HStack {
                        Text("Value")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("health-data", text: $config.customTypeValue)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
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
                    Button("Reset Names") {
                        for i in config.fields.indices {
                            config.fields[i].customKey = config.fields[i].originalKey
                        }
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
    
    var body: some View {
        HStack {
            Toggle("", isOn: $field.isEnabled)
                .labelsHidden()
                .tint(Color.accent)
            
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
            
            Spacer()
            
            Button(action: {
                tempCustomKey = field.customKey
                isEditing = true
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(Color.textMuted)
            }
            .buttonStyle(.plain)
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
                
                Picker("Bullet Style", selection: $config.bulletStyle) {
                    ForEach(MarkdownTemplateConfig.BulletStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .tint(Color.accent)
                
                Toggle("Use Emoji in Headers", isOn: $config.useEmoji)
                    .tint(Color.accent)
                
                Toggle("Include Summary", isOn: $config.includeSummary)
                    .tint(Color.accent)
            } header: {
                Text("Options")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            }
            
            // Custom Template Section
            if config.style == .custom {
                Section {
                    TextEditor(text: $config.customTemplate)
                        .font(.system(size: 12, design: .monospaced))
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
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.textMuted)
                    }
                }
            }
            
            // Preview Section
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(previewText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
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
        preview += "\(bullet) **Deep:** 1h 45m\n\n"
        
        preview += "\(headerPrefix) \(activityEmoji)Activity\n\n"
        preview += "\(bullet) **Steps:** 8,432\n"
        preview += "\(bullet) **Calories:** 420 kcal"
        
        return preview
    }
}
