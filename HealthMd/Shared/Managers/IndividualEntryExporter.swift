//
//  IndividualEntryExporter.swift
//  Health.md
//
//  Handles exporting individual timestamped health entries as separate files.
//

import Foundation
import HealthKit

// MARK: - Individual Health Sample

/// Represents a single health data sample with timestamp for individual export
struct IndividualHealthSample {
    let metricId: String
    let metricName: String
    let category: HealthMetricCategory
    let timestamp: Date
    let value: Any
    let unit: String
    let source: String?
    let additionalFields: [String: Any]
    
    init(
        metricId: String,
        metricName: String,
        category: HealthMetricCategory,
        timestamp: Date,
        value: Any,
        unit: String,
        source: String? = nil,
        additionalFields: [String: Any] = [:]
    ) {
        self.metricId = metricId
        self.metricName = metricName
        self.category = category
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.source = source
        self.additionalFields = additionalFields
    }
}

// MARK: - Individual Entry Exporter

@MainActor
final class IndividualEntryExporter {
    
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let datetimeFormatter: ISO8601DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        datetimeFormatter = ISO8601DateFormatter()
        datetimeFormatter.formatOptions = [.withInternetDateTime]
    }
    
    // MARK: - Export Individual Entries
    
    /// Export individual samples as separate files
    /// Returns the number of files written
    func exportIndividualEntries(
        samples: [IndividualHealthSample],
        to baseURL: URL,
        settings: IndividualTrackingSettings,
        formatSettings: FormatCustomization
    ) throws -> Int {
        var filesWritten = 0
        let fileManager = FileManager.default
        
        for sample in samples {
            // Skip if this metric isn't configured for individual tracking
            guard settings.shouldTrackIndividually(sample.metricId) else {
                continue
            }
            
            // Build the metric definition for folder/filename generation
            let metricDef = HealthMetricDefinition(
                id: sample.metricId,
                name: sample.metricName,
                category: sample.category,
                unit: sample.unit,
                healthKitIdentifier: nil,
                metricType: .quantity,
                aggregation: .mostRecent
            )
            
            // Build folder path
            let folderPath = settings.folderPath(for: metricDef)
            let folderURL = baseURL.appendingPathComponent(folderPath, isDirectory: true)
            
            // Create directory if needed
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            
            // Generate filename
            let filename = settings.filename(for: metricDef, date: sample.timestamp, time: sample.timestamp)
            let fileURL = folderURL.appendingPathComponent(filename)
            
            // Generate content
            let content = generateEntryContent(for: sample, formatSettings: formatSettings)
            
            // Write file
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            filesWritten += 1
        }
        
        return filesWritten
    }
    
    // MARK: - Content Generation
    
    /// Generate markdown content for an individual entry
    private func generateEntryContent(for sample: IndividualHealthSample, formatSettings: FormatCustomization) -> String {
        var lines: [String] = []
        
        // YAML frontmatter
        lines.append("---")
        lines.append("date: \(dateFormatter.string(from: sample.timestamp))")
        lines.append("time: \"\(timeFormatter.string(from: sample.timestamp))\"")
        lines.append("datetime: \(datetimeFormatter.string(from: sample.timestamp))")
        lines.append("type: \(sample.category.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
        lines.append("metric: \(sample.metricId)")
        
        // Primary value
        if let doubleValue = sample.value as? Double {
            lines.append("value: \(formatValue(doubleValue))")
        } else if let intValue = sample.value as? Int {
            lines.append("value: \(intValue)")
        } else if let stringValue = sample.value as? String {
            lines.append("value: \"\(stringValue)\"")
        }
        
        // Unit
        if !sample.unit.isEmpty {
            lines.append("unit: \(sample.unit)")
        }
        
        // Source
        if let source = sample.source {
            lines.append("source: \"\(source)\"")
        }
        
        // Additional fields
        for (key, value) in sample.additionalFields.sorted(by: { $0.key < $1.key }) {
            lines.append(formatYAMLField(key: key, value: value))
        }
        
        lines.append("---")
        
        return lines.joined(separator: "\n")
    }
    
    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func formatYAMLField(key: String, value: Any) -> String {
        switch value {
        case let array as [String]:
            if array.isEmpty {
                return "\(key): []"
            }
            var result = "\(key):"
            for item in array {
                result += "\n  - \(item)"
            }
            return result
            
        case let dict as [String: Any]:
            var result = "\(key):"
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                result += "\n  \(k): \(v)"
            }
            return result
            
        case let doubleVal as Double:
            return "\(key): \(formatValue(doubleVal))"
            
        case let intVal as Int:
            return "\(key): \(intVal)"
            
        case let boolVal as Bool:
            return "\(key): \(boolVal)"
            
        case let stringVal as String:
            // Quote strings that might need it
            if stringVal.contains(":") || stringVal.contains("#") || stringVal.hasPrefix(" ") {
                return "\(key): \"\(stringVal)\""
            }
            return "\(key): \(stringVal)"
            
        default:
            return "\(key): \(value)"
        }
    }
    
    // MARK: - Sample Extraction from HealthData
    
    /// Extract individual samples from HealthData that should be tracked individually
    func extractIndividualSamples(from healthData: HealthData, settings: IndividualTrackingSettings) -> [IndividualHealthSample] {
        var samples: [IndividualHealthSample] = []
        
        // State of Mind entries (already have timestamps)
        if settings.shouldTrackIndividually("daily_mood") || 
           settings.shouldTrackIndividually("momentary_emotions") ||
           settings.shouldTrackIndividually("average_valence") {
            samples.append(contentsOf: extractStateOfMindSamples(from: healthData.mindfulness))
        }
        
        // Workouts (already have timestamps)
        if settings.shouldTrackIndividually("workouts") {
            samples.append(contentsOf: extractWorkoutSamples(from: healthData.workouts))
        }
        
        // For metrics that currently only have aggregated values,
        // we create a single "daily" entry at midnight
        // In a future enhancement, we could fetch individual samples from HealthKit
        
        // Blood pressure (if we have data, create an entry)
        if settings.shouldTrackIndividually("blood_pressure_systolic") || 
           settings.shouldTrackIndividually("blood_pressure_diastolic") {
            if let sample = extractBloodPressureSample(from: healthData) {
                samples.append(sample)
            }
        }
        
        // Blood glucose
        if settings.shouldTrackIndividually("blood_glucose"),
           let glucose = healthData.vitals.bloodGlucose {
            samples.append(IndividualHealthSample(
                metricId: "blood_glucose",
                metricName: "Blood Glucose",
                category: .vitals,
                timestamp: healthData.date,
                value: glucose,
                unit: "mg/dL"
            ))
        }
        
        // Weight
        if settings.shouldTrackIndividually("weight"),
           let weight = healthData.body.weight {
            samples.append(IndividualHealthSample(
                metricId: "weight",
                metricName: "Weight",
                category: .bodyMeasurements,
                timestamp: healthData.date,
                value: weight,
                unit: "kg"
            ))
        }
        
        // Symptoms - create entries for any logged symptoms
        samples.append(contentsOf: extractSymptomSamples(from: healthData, settings: settings))
        
        return samples
    }
    
    // MARK: - Specific Extractors
    
    private func extractStateOfMindSamples(from mindfulness: MindfulnessData) -> [IndividualHealthSample] {
        return mindfulness.stateOfMind.map { entry in
            let metricId = entry.kind == .dailyMood ? "daily_mood" : "momentary_emotions"
            let metricName = entry.kind == .dailyMood ? "Daily Mood" : "Momentary Emotion"
            
            var additionalFields: [String: Any] = [
                "valence": entry.valence,
                "feeling": entry.valenceDescription
            ]
            
            if !entry.labels.isEmpty {
                additionalFields["labels"] = entry.labels
            }
            
            if !entry.associations.isEmpty {
                additionalFields["associations"] = entry.associations
            }
            
            return IndividualHealthSample(
                metricId: metricId,
                metricName: metricName,
                category: .mindfulness,
                timestamp: entry.timestamp,
                value: entry.valence,
                unit: "",
                additionalFields: additionalFields
            )
        }
    }
    
    private func extractWorkoutSamples(from workouts: [WorkoutData]) -> [IndividualHealthSample] {
        return workouts.map { workout in
            var additionalFields: [String: Any] = [
                "workout_type": workout.workoutTypeName,
                "duration_minutes": Int(workout.duration / 60)
            ]
            
            if let calories = workout.calories {
                additionalFields["calories"] = Int(calories)
            }
            
            if let distance = workout.distance {
                additionalFields["distance_meters"] = Int(distance)
            }
            
            return IndividualHealthSample(
                metricId: "workouts",
                metricName: "Workout",
                category: .workouts,
                timestamp: workout.startTime,
                value: workout.workoutTypeName,
                unit: "",
                additionalFields: additionalFields
            )
        }
    }
    
    private func extractBloodPressureSample(from healthData: HealthData) -> IndividualHealthSample? {
        guard let systolic = healthData.vitals.bloodPressureSystolic,
              let diastolic = healthData.vitals.bloodPressureDiastolic else {
            return nil
        }
        
        return IndividualHealthSample(
            metricId: "blood_pressure",
            metricName: "Blood Pressure",
            category: .vitals,
            timestamp: healthData.date,
            value: "\(Int(systolic))/\(Int(diastolic))",
            unit: "mmHg",
            additionalFields: [
                "systolic": Int(systolic),
                "diastolic": Int(diastolic)
            ]
        )
    }
    
    private func extractSymptomSamples(from healthData: HealthData, settings: IndividualTrackingSettings) -> [IndividualHealthSample] {
        // Note: The current HealthData model doesn't have detailed symptom data
        // This is a placeholder for when symptom tracking is enhanced
        return []
    }
}


