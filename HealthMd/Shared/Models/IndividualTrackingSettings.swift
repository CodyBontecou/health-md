//
//  IndividualTrackingSettings.swift
//  Health.md
//
//  Universal granular tracking - allows any metric to export
//  individual timestamped files in addition to daily aggregates.
//

import Foundation
import Combine

// MARK: - Per-Metric Tracking Configuration

struct MetricTrackingConfig: Codable, Equatable {
    /// Whether to create individual timestamped files for this metric
    var trackIndividually: Bool = false
    
    /// Custom folder override (nil = use default/category folder)
    var customFolder: String? = nil
}

// MARK: - Individual Tracking Settings

class IndividualTrackingSettings: ObservableObject, Codable {
    
    // MARK: - Published Properties
    
    /// Global toggle - master switch for individual tracking
    @Published var globalEnabled: Bool = false
    
    /// Per-metric individual tracking configurations
    @Published var metricConfigs: [String: MetricTrackingConfig] = [:]
    
    /// Root folder for individual entries (relative to export root)
    @Published var entriesFolder: String = "entries"
    
    /// Organize entries into category subfolders
    @Published var useCategoryFolders: Bool = true
    
    /// Filename template for individual entries
    /// Placeholders: {date}, {time}, {metric}, {category}
    @Published var filenameTemplate: String = "{date}_{time}_{metric}"
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case globalEnabled
        case metricConfigs
        case entriesFolder
        case useCategoryFolders
        case filenameTemplate
    }
    
    // MARK: - Initialization
    
    init() {
        // Defaults set in property declarations
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalEnabled) ?? false
        metricConfigs = try container.decodeIfPresent([String: MetricTrackingConfig].self, forKey: .metricConfigs) ?? [:]
        entriesFolder = try container.decodeIfPresent(String.self, forKey: .entriesFolder) ?? "entries"
        useCategoryFolders = try container.decodeIfPresent(Bool.self, forKey: .useCategoryFolders) ?? true
        filenameTemplate = try container.decodeIfPresent(String.self, forKey: .filenameTemplate) ?? "{date}_{time}_{metric}"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalEnabled, forKey: .globalEnabled)
        try container.encode(metricConfigs, forKey: .metricConfigs)
        try container.encode(entriesFolder, forKey: .entriesFolder)
        try container.encode(useCategoryFolders, forKey: .useCategoryFolders)
        try container.encode(filenameTemplate, forKey: .filenameTemplate)
    }
    
    // MARK: - Metric Configuration
    
    /// Check if a specific metric should create individual entries
    func shouldTrackIndividually(_ metricId: String) -> Bool {
        guard globalEnabled else { return false }
        return metricConfigs[metricId]?.trackIndividually ?? false
    }
    
    /// Get the configuration for a metric (creates default if missing)
    func config(for metricId: String) -> MetricTrackingConfig {
        return metricConfigs[metricId] ?? MetricTrackingConfig()
    }
    
    /// Set whether a metric tracks individually
    func setTrackIndividually(_ metricId: String, enabled: Bool) {
        var config = metricConfigs[metricId] ?? MetricTrackingConfig()
        config.trackIndividually = enabled
        metricConfigs[metricId] = config
    }
    
    /// Toggle individual tracking for a metric
    func toggleMetric(_ metricId: String) {
        let current = metricConfigs[metricId]?.trackIndividually ?? false
        setTrackIndividually(metricId, enabled: !current)
    }
    
    // MARK: - Category Helpers
    
    /// Enable individual tracking for all metrics in a category
    func enableCategory(_ category: HealthMetricCategory) {
        let metrics = HealthMetrics.byCategory[category] ?? []
        for metric in metrics {
            setTrackIndividually(metric.id, enabled: true)
        }
    }
    
    /// Disable individual tracking for all metrics in a category
    func disableCategory(_ category: HealthMetricCategory) {
        let metrics = HealthMetrics.byCategory[category] ?? []
        for metric in metrics {
            setTrackIndividually(metric.id, enabled: false)
        }
    }
    
    /// Check if all metrics in a category are tracked individually
    func isCategoryFullyEnabled(_ category: HealthMetricCategory) -> Bool {
        guard globalEnabled else { return false }
        let metrics = HealthMetrics.byCategory[category] ?? []
        return metrics.allSatisfy { shouldTrackIndividually($0.id) }
    }
    
    /// Check if some (but not all) metrics in a category are tracked
    func isCategoryPartiallyEnabled(_ category: HealthMetricCategory) -> Bool {
        guard globalEnabled else { return false }
        let metrics = HealthMetrics.byCategory[category] ?? []
        let enabledCount = metrics.filter { shouldTrackIndividually($0.id) }.count
        return enabledCount > 0 && enabledCount < metrics.count
    }
    
    /// Count of individually tracked metrics in a category
    func enabledCount(for category: HealthMetricCategory) -> Int {
        guard globalEnabled else { return 0 }
        let metrics = HealthMetrics.byCategory[category] ?? []
        return metrics.filter { shouldTrackIndividually($0.id) }.count
    }
    
    // MARK: - Bulk Operations
    
    /// Enable individual tracking for all metrics
    func enableAll() {
        for metric in HealthMetrics.all {
            setTrackIndividually(metric.id, enabled: true)
        }
    }
    
    /// Disable individual tracking for all metrics
    func disableAll() {
        metricConfigs.removeAll()
    }
    
    /// Enable suggested metrics (mood, symptoms, workouts)
    func enableSuggested() {
        // Mood/mindfulness
        enableCategory(.mindfulness)
        
        // Symptoms
        enableCategory(.symptoms)
        
        // Workouts
        setTrackIndividually("workouts", enabled: true)
        
        // Blood pressure and glucose (often logged multiple times)
        setTrackIndividually("blood_pressure_systolic", enabled: true)
        setTrackIndividually("blood_pressure_diastolic", enabled: true)
        setTrackIndividually("blood_glucose", enabled: true)
    }
    
    /// Total count of metrics being tracked individually
    var totalEnabledCount: Int {
        guard globalEnabled else { return 0 }
        return metricConfigs.values.filter { $0.trackIndividually }.count
    }
    
    // MARK: - File Path Helpers
    
    /// Generate the folder path for an individual entry
    func folderPath(for metric: HealthMetricDefinition) -> String {
        if useCategoryFolders {
            let categoryFolder = metric.category.rawValue
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            return "\(entriesFolder)/\(categoryFolder)"
        }
        return entriesFolder
    }
    
    /// Generate filename for an individual entry
    func filename(for metric: HealthMetricDefinition, date: Date, time: Date) -> String {
        let dateFormatter = DateFormatter()
        var result = filenameTemplate
        
        // {date} -> yyyy_MM_dd
        dateFormatter.dateFormat = "yyyy_MM_dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
        
        // {time} -> HHmm
        dateFormatter.dateFormat = "HHmm"
        result = result.replacingOccurrences(of: "{time}", with: dateFormatter.string(from: time))
        
        // {metric} -> metric id
        result = result.replacingOccurrences(of: "{metric}", with: metric.id)
        
        // {category} -> category name (lowercase, underscored)
        let categoryName = metric.category.rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        result = result.replacingOccurrences(of: "{category}", with: categoryName)
        
        return result + ".md"
    }
    
    // MARK: - Reset
    
    func reset() {
        globalEnabled = false
        metricConfigs.removeAll()
        entriesFolder = "entries"
        useCategoryFolders = true
        filenameTemplate = "{date}_{time}_{metric}"
    }
}

// MARK: - Suggested Metrics for Individual Tracking

extension IndividualTrackingSettings {
    
    /// Metrics that are commonly useful to track individually
    static let suggestedMetricIds: Set<String> = [
        // Mindfulness - mood varies throughout day
        "daily_mood",
        "average_valence",
        "momentary_emotions",
        "mindful_minutes",
        "mindful_sessions",
        
        // Symptoms - important to log when they occur
        "symptom_headache",
        "symptom_fatigue",
        "symptom_nausea",
        "symptom_dizziness",
        "symptom_mood_changes",
        
        // Vitals - often measured multiple times
        "blood_pressure_systolic",
        "blood_pressure_diastolic",
        "blood_glucose",
        
        // Workouts - each workout is unique
        "workouts",
    ]
    
    /// Check if a metric is in the suggested list
    static func isSuggested(_ metricId: String) -> Bool {
        suggestedMetricIds.contains(metricId)
    }
}
