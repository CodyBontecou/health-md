//
//  IndividualTrackingView.swift
//  Health.md
//
//  Settings UI for configuring individual timestamped entry exports.
//

import SwiftUI

struct IndividualTrackingView: View {
    @ObservedObject var settings: IndividualTrackingSettings
    @ObservedObject var metricSelection: MetricSelectionState
    @Environment(\.dismiss) private var dismiss
    
    @State private var expandedCategories: Set<HealthMetricCategory> = []
    @State private var showingQuickActions = false
    
    var body: some View {
        Form {
            // Global Toggle Section
            Section {
                HStack {
                    Toggle("Enable Individual Entry Tracking", isOn: $settings.globalEnabled)
                        .tint(Color.accent)
                    
                    if settings.globalEnabled && settings.totalEnabledCount > 0 {
                        Text("\(settings.totalEnabledCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.accent)
                            )
                    }
                }
            } header: {
                Text("Master Switch")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text("When enabled, selected metrics will create individual timestamped files in addition to daily summaries.")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }
            
            if settings.globalEnabled {
                // Quick Actions Section
                Section {
                    Button(action: { settings.enableSuggested() }) {
                        Label("Enable Suggested Metrics", systemImage: "sparkles")
                            .font(Typography.body())
                    }
                    .tint(Color.accent)
                    
                    Button(action: { settings.enableAll() }) {
                        Label("Enable All Metrics", systemImage: "checkmark.circle.fill")
                            .font(Typography.body())
                    }
                    .tint(Color.accent)
                    
                    Button(action: { settings.disableAll() }) {
                        Label("Disable All Metrics", systemImage: "xmark.circle")
                            .font(Typography.body())
                    }
                    .tint(Color.red)
                } header: {
                    Text("Quick Actions")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Suggested metrics include mood, symptoms, workouts, blood pressure, and blood glucose.")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }
                
                // Per-Category Metric Selection
                Section {
                    ForEach(categoriesWithEnabledMetrics, id: \.self) { category in
                        CategoryTrackingRow(
                            category: category,
                            settings: settings,
                            metricSelection: metricSelection,
                            isExpanded: expandedCategories.contains(category),
                            onToggleExpand: { toggleCategory(category) }
                        )
                    }
                } header: {
                    HStack {
                        Text("Per-Metric Settings")
                            .font(Typography.caption())
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        Text("\(settings.totalEnabledCount) tracked")
                            .font(Typography.caption())
                            .foregroundColor(Color.accent)
                    }
                } footer: {
                    Text("Only categories with enabled metrics in your export settings are shown. Enable more metrics in Health Metrics settings.")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }
                
                // Folder Configuration Section
                Section {
                    HStack {
                        Text("Entries Folder")
                            .font(Typography.body())
                        Spacer()
                        TextField("entries", text: $settings.entriesFolder)
                            .font(Typography.body())
                            .foregroundColor(Color.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    Toggle("Organize by Category", isOn: $settings.useCategoryFolders)
                        .tint(Color.accent)
                } header: {
                    Text("Folder Structure")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text(folderStructurePreview)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.textMuted)
                }
                
                // Filename Template Section
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TextField("{date}_{time}_{metric}", text: $settings.filenameTemplate)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Text("Placeholders: {date}, {time}, {metric}, {category}")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)
                    }
                } header: {
                    Text("Filename Template")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Example: \(filenamePreview)")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.textMuted)
                }
                
                // Preview Section
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Individual Entry Preview")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                        
                        Text(entryPreview)
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
        }
        .navigationTitle("Individual Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Computed Properties
    
    /// Categories that have at least one enabled metric in export settings
    private var categoriesWithEnabledMetrics: [HealthMetricCategory] {
        HealthMetricCategory.allCases.filter { category in
            metricSelection.enabledMetricCount(for: category) > 0
        }
    }
    
    private func toggleCategory(_ category: HealthMetricCategory) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }
    
    private var folderStructurePreview: String {
        if settings.useCategoryFolders {
            // Get categories that have enabled metrics for individual tracking
            let enabledCategories = HealthMetricCategory.allCases.filter { category in
                settings.enabledCount(for: category) > 0
            }
            
            if enabledCategories.isEmpty {
                return "📁 \(settings.entriesFolder)/\n   (no metrics selected)"
            }
            
            var preview = "📁 \(settings.entriesFolder)/"
            for category in enabledCategories {
                let folderName = category.rawValue
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                preview += "\n   📁 \(folderName)/"
            }
            return preview
        } else {
            return "📁 \(settings.entriesFolder)/"
        }
    }
    
    private var filenamePreview: String {
        // Find an enabled metric to use for preview, or fall back to default
        let sampleMetric: HealthMetricDefinition
        
        if let enabledMetricId = settings.metricConfigs.first(where: { $0.value.trackIndividually })?.key,
           let metric = HealthMetrics.all.first(where: { $0.id == enabledMetricId }) {
            sampleMetric = metric
        } else {
            // Default fallback
            sampleMetric = HealthMetricDefinition(
                id: "daily_mood",
                name: "Daily Mood",
                category: .mindfulness,
                unit: "",
                healthKitIdentifier: nil,
                metricType: .category,
                aggregation: .mostRecent
            )
        }
        return settings.filename(for: sampleMetric, date: Date(), time: Date())
    }
    
    private var entryPreview: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        
        dateFormatter.dateFormat = "HH:mm"
        let timeStr = dateFormatter.string(from: Date())
        
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let datetimeStr = dateFormatter.string(from: Date())
        
        return """
        ---
        date: \(dateStr)
        time: "\(timeStr)"
        datetime: \(datetimeStr)
        type: mindfulness
        metric: daily_mood
        valence: 0.7
        feeling: pleasant
        labels:
          - happy
          - calm
        ---
        """
    }
}

// MARK: - Category Row Component

struct CategoryTrackingRow: View {
    let category: HealthMetricCategory
    @ObservedObject var settings: IndividualTrackingSettings
    @ObservedObject var metricSelection: MetricSelectionState
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Category header
            Button(action: onToggleExpand) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color.accent)
                        .frame(width: 24)
                    
                    Text(category.rawValue)
                        .font(Typography.body())
                        .foregroundColor(Color.textPrimary)
                    
                    Spacer()
                    
                    // Status indicator
                    if settings.isCategoryFullyEnabled(category) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.accent)
                    } else if settings.isCategoryPartiallyEnabled(category) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(Color.accent.opacity(0.6))
                    }
                    
                    Text("\(settings.enabledCount(for: category))/\(enabledMetricsInCategory.count)")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded metrics list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(enabledMetricsInCategory, id: \.id) { metric in
                        MetricTrackingRow(metric: metric, settings: settings)
                    }
                }
                .padding(.leading, 32)
                .padding(.top, Spacing.sm)
            }
        }
    }
    
    /// Metrics in this category that are enabled in export settings
    private var enabledMetricsInCategory: [HealthMetricDefinition] {
        let categoryMetrics = HealthMetrics.byCategory[category] ?? []
        return categoryMetrics.filter { metricSelection.isMetricEnabled($0.id) }
    }
}

// MARK: - Individual Metric Row

struct MetricTrackingRow: View {
    let metric: HealthMetricDefinition
    @ObservedObject var settings: IndividualTrackingSettings
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(metric.name)
                        .font(Typography.caption())
                        .foregroundColor(Color.textPrimary)
                    
                    if IndividualTrackingSettings.isSuggested(metric.id) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(Color.accent)
                    }
                }
                
                Text(aggregationDescription(metric.aggregation))
                    .font(.system(size: 11))
                    .foregroundColor(Color.textMuted)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { settings.shouldTrackIndividually(metric.id) },
                set: { settings.setTrackIndividually(metric.id, enabled: $0) }
            ))
            .tint(Color.accent)
            .labelsHidden()
        }
        .padding(.vertical, 6)
    }
    
    private func aggregationDescription(_ aggregation: HealthMetricDefinition.AggregationType) -> String {
        switch aggregation {
        case .cumulative: return "Daily: sum"
        case .discreteAvg: return "Daily: average"
        case .discreteMin: return "Daily: minimum"
        case .discreteMax: return "Daily: maximum"
        case .mostRecent: return "Daily: latest"
        case .duration: return "Daily: total time"
        case .count: return "Daily: count"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IndividualTrackingView(
            settings: IndividualTrackingSettings(),
            metricSelection: MetricSelectionState()
        )
    }
}
