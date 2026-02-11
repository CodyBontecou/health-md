//
//  AdvancedSettingsView.swift
//  Health.md
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
                    NavigationLink {
                        MetricSelectionView(selectionState: settings.metricSelection)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Health Metrics")
                                    .font(Typography.body())
                                Text("\(settings.metricSelection.totalEnabledCount) of \(settings.metricSelection.totalMetricCount) metrics enabled")
                                    .font(Typography.caption())
                                    .foregroundColor(Color.textSecondary)
                            }
                            Spacer()
                        }
                    }
                } header: {
                    Text("Data Types to Export")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Choose from \(HealthMetricCategory.allCases.count) categories including sleep, activity, heart, nutrition, symptoms, and more. Over 100+ metrics available.")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
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
                
                // Format Customization Section
                Section {
                    NavigationLink {
                        FormatCustomizationView(customization: settings.formatCustomization)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Format Customization")
                                    .font(Typography.body())
                                Text(formatCustomizationSummary)
                                    .font(Typography.caption())
                                    .foregroundColor(Color.textSecondary)
                            }
                            Spacer()
                        }
                    }
                } header: {
                    Text("Customization")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Customize date/time formats, units, frontmatter fields, and markdown templates")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }
                
                // Individual Entry Tracking Section
                Section {
                    NavigationLink {
                        IndividualTrackingView(
                            settings: settings.individualTracking,
                            metricSelection: settings.metricSelection
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Individual Entry Tracking")
                                        .font(Typography.body())
                                    
                                    if settings.individualTracking.globalEnabled && settings.individualTracking.totalEnabledCount > 0 {
                                        Text("\(settings.individualTracking.totalEnabledCount)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(Color.accent)
                                            )
                                    }
                                }
                                Text(individualTrackingSummary)
                                    .font(Typography.caption())
                                    .foregroundColor(Color.textSecondary)
                            }
                            Spacer()
                            if settings.individualTracking.globalEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.accent)
                            }
                        }
                    }
                } header: {
                    Text("Granular Tracking")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Create individual timestamped files for selected metrics in addition to daily summaries.")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }

                // Write Mode Section
                Section {
                    Picker("When File Exists", selection: $settings.writeMode) {
                        ForEach(WriteMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .tint(Color.accent)
                } header: {
                    Text("File Handling")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text(settings.writeMode.description)
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }

                // Preview Section with Liquid Glass styling
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Export Preview")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.textSecondary)

                        Text(previewText)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
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
        case .obsidianBases:
            return "Optimized for Obsidian Bases. All metrics are stored as frontmatter properties for querying, filtering, and sorting."
        case .json:
            return "Structured data format ideal for programmatic access and data analysis."
        case .csv:
            return "Spreadsheet-compatible format. Each data point becomes a row with date, category, metric, and value columns."
        }
    }
    
    private var formatCustomizationSummary: String {
        let fc = settings.formatCustomization
        var parts: [String] = []
        
        // Date format
        let dateExample = fc.dateFormat.format(date: Date())
        parts.append(dateExample)
        
        // Unit preference
        parts.append(fc.unitPreference.rawValue)
        
        // Time format indicator
        parts.append(fc.timeFormat == .hour12 || fc.timeFormat == .hour12WithSeconds ? "12h" : "24h")
        
        return parts.joined(separator: " · ")
    }
    
    private var individualTrackingSummary: String {
        let it = settings.individualTracking
        if !it.globalEnabled {
            return "Disabled"
        }
        let count = it.totalEnabledCount
        if count == 0 {
            return "Enabled · No metrics selected"
        }
        return "Enabled · \(count) metric\(count == 1 ? "" : "s")"
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

        case .obsidianBases:
            var preview = fileName + "\n"
            preview += "---\n"
            preview += "date: 2026-01-13\n"
            preview += "type: health-data\n"
            if settings.isCategoryEnabled(.sleep) {
                preview += "sleep_total_hours: 7.5\n"
            }
            if settings.isCategoryEnabled(.activity) {
                preview += "steps: 8432\n"
            }
            if settings.isCategoryEnabled(.heart) {
                preview += "resting_heart_rate: 62\n"
                preview += "hrv_ms: 45.2\n"
            }
            if settings.isCategoryEnabled(.nutrition) {
                preview += "dietary_calories: 2100\n"
            }
            preview += "---\n"
            preview += "# Health — 2026-01-13"
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
        HealthMetricCategory.allCases
            .filter { settings.isCategoryEnabled($0) }
            .map { $0.rawValue }
    }
}
