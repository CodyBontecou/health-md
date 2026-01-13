//
//  AdvancedSettingsView.swift
//  HealthToObsidian
//
//  Created by Claude on 2026-01-13.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var settings: AdvancedExportSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Data Types Section
                Section {
                    Toggle("Sleep", isOn: $settings.dataTypes.sleep)
                        .tint(Color.accent)

                    Toggle("Activity", isOn: $settings.dataTypes.activity)
                        .tint(Color.accent)

                    Toggle("Vitals", isOn: $settings.dataTypes.vitals)
                        .tint(Color.accent)

                    Toggle("Body Measurements", isOn: $settings.dataTypes.body)
                        .tint(Color.accent)

                    Toggle("Workouts", isOn: $settings.dataTypes.workouts)
                        .tint(Color.accent)
                } header: {
                    Text("Data Types to Export")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    if !settings.dataTypes.hasAnySelected {
                        Text("At least one data type must be selected")
                            .font(Typography.caption())
                            .foregroundColor(.red)
                    } else {
                        Text("Select which health data categories to include in exports")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)
                    }
                }

                // Export Format Section
                Section {
                    Picker("Format", selection: $settings.exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .tint(Color.accent)

                    if settings.exportFormat == .markdown {
                        Toggle("Include Frontmatter Metadata", isOn: $settings.includeMetadata)
                            .tint(Color.accent)

                        Toggle("Group by Category", isOn: $settings.groupByCategory)
                            .tint(Color.accent)
                    }
                } header: {
                    Text("Export Format")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text(formatDescription)
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }

                // Preview Section
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Export Preview")
                            .font(Typography.label())
                            .foregroundColor(Color.textSecondary)

                        Text(previewText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.textMuted)
                            .padding(Spacing.md)
                            .background(Color.bgSecondary)
                            .cornerRadius(8)
                    }
                } header: {
                    Text("Preview")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                }

                // Reset Section
                Section {
                    Button(action: {
                        settings.reset()
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
            .navigationTitle("Advanced Settings")
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

    private var formatDescription: String {
        switch settings.exportFormat {
        case .markdown:
            return "Human-readable format perfect for Obsidian. Includes headers, lists, and frontmatter metadata."
        case .json:
            return "Structured data format ideal for programmatic access and data analysis."
        case .csv:
            return "Spreadsheet-compatible format. Each data point becomes a row with date, category, metric, and value columns."
        }
    }

    private var previewText: String {
        let fileName = "2026-01-13.\(settings.exportFormat.fileExtension)"
        let categories = selectedCategories.joined(separator: ", ")

        switch settings.exportFormat {
        case .markdown:
            var preview = fileName + "\n"
            if settings.includeMetadata {
                preview += "---\ndate: 2026-01-13\ntype: health-data\n---\n\n"
            }
            preview += "# Health Data\n"
            if settings.groupByCategory {
                preview += "\n## \(selectedCategories.first ?? "Category")\n- Metric: Value"
            } else {
                preview += "\n- Metric: Value"
            }
            return preview

        case .json:
            return """
            \(fileName)
            {
              "date": "2026-01-13",
              "categories": [\(categories)]
            }
            """

        case .csv:
            return """
            \(fileName)
            Date,Category,Metric,Value
            2026-01-13,\(selectedCategories.first ?? "Sleep"),Duration,8h 30m
            """
        }
    }

    private var selectedCategories: [String] {
        var categories: [String] = []
        if settings.dataTypes.sleep { categories.append("Sleep") }
        if settings.dataTypes.activity { categories.append("Activity") }
        if settings.dataTypes.vitals { categories.append("Vitals") }
        if settings.dataTypes.body { categories.append("Body") }
        if settings.dataTypes.workouts { categories.append("Workouts") }
        return categories
    }
}
