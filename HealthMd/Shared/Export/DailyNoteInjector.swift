//
//  DailyNoteInjector.swift
//  Health.md
//
//  Injects health metrics into the YAML frontmatter of an existing daily note
//  without touching the rest of the file's content.
//  Which metrics are injected is driven entirely by MetricSelectionState —
//  no separate field selection needed.
//

import Foundation

// MARK: - Metric ID → Frontmatter Key Mapping

/// Maps each HealthMetrics metric ID to the frontmatter original-key(s) it produces.
/// Keys here match the values in HealthMetricsDictionary (allMetricsDictionary).
private let metricIdToFrontmatterKeys: [String: [String]] = [
    // Sleep
    "sleep_total":    ["sleep_total_hours"],
    "sleep_bedtime":  ["sleep_bedtime"],
    "sleep_wake":     ["sleep_wake"],
    "sleep_deep":     ["sleep_deep_hours"],
    "sleep_rem":      ["sleep_rem_hours"],
    "sleep_core":     ["sleep_core_hours"],
    "sleep_awake":    ["sleep_awake_hours"],
    "sleep_in_bed":   ["sleep_in_bed_hours"],

    // Activity
    "steps":                      ["steps"],
    "active_energy":              ["active_calories"],
    "basal_energy":               ["basal_calories"],
    "exercise_time":              ["exercise_minutes"],
    "stand_time":                 ["stand_hours"],
    "flights_climbed":            ["flights_climbed"],
    "distance_walking_running":   ["walking_running_km"],
    "distance_swimming":          ["swimming_m"],
    "swimming_strokes":           ["swimming_strokes"],
    "push_count":                 ["wheelchair_pushes"],
    "vo2_max":                    ["vo2_max"],

    // Cycling (separate category)
    "cycling_distance":           ["cycling_km"],

    // Heart
    "resting_heart_rate":  ["resting_heart_rate"],
    "walking_heart_rate":  ["walking_heart_rate"],
    "heart_rate_avg":      ["average_heart_rate"],
    "heart_rate_min":      ["heart_rate_min"],
    "heart_rate_max":      ["heart_rate_max"],
    "hrv":                 ["hrv_ms"],

    // Vitals
    "blood_pressure_systolic":  ["blood_pressure_systolic"],
    "blood_pressure_diastolic": ["blood_pressure_diastolic"],
    "blood_glucose":            ["blood_glucose"],
    "body_temperature":         ["body_temperature"],
    "basal_body_temperature":   ["body_temperature"],

    // Respiratory
    "respiratory_rate": ["respiratory_rate"],
    "blood_oxygen":     ["blood_oxygen"],

    // Body Measurements
    "weight":             ["weight_kg"],
    "height":             ["height_m"],
    "bmi":                ["bmi"],
    "body_fat":           ["body_fat_percent"],
    "lean_body_mass":     ["lean_body_mass_kg"],
    "waist_circumference": ["waist_circumference_cm"],

    // Nutrition
    "dietary_energy":      ["dietary_calories"],
    "dietary_protein":     ["protein_g"],
    "dietary_carbs":       ["carbohydrates_g"],
    "dietary_fat":         ["fat_g"],
    "dietary_fat_saturated": ["saturated_fat_g"],
    "dietary_fiber":       ["fiber_g"],
    "dietary_sugar":       ["sugar_g"],
    "dietary_sodium":      ["sodium_mg"],
    "dietary_cholesterol": ["cholesterol_mg"],
    "dietary_water":       ["water_l"],
    "dietary_caffeine":    ["caffeine_mg"],

    // Mindfulness
    "mindful_minutes":  ["mindful_minutes"],
    "mindful_sessions": ["mindful_sessions"],
    "daily_mood":       ["average_mood_valence", "average_mood_percent"],
    "average_valence":  ["average_mood_valence", "average_mood_percent"],

    // Mobility
    "walking_speed":         ["walking_speed"],
    "walking_step_length":   ["step_length_cm"],
    "walking_double_support": ["double_support_percent"],
    "walking_asymmetry":     ["walking_asymmetry_percent"],
    "stair_ascent_speed":    ["stair_ascent_speed"],
    "stair_descent_speed":   ["stair_descent_speed"],
    "six_minute_walk":       ["six_min_walk_m"],

    // Hearing
    "headphone_audio":    ["headphone_audio_db"],
    "environmental_sound": ["environmental_sound_db"],

    // Workouts
    "workouts": ["workout_count", "workout_minutes", "workout_calories",
                 "workout_distance_km", "workouts"],
]

// MARK: - Daily Note Injector

struct DailyNoteInjector {

    // MARK: - Injection Result

    enum InjectionResult {
        case updated(path: String)
        case skipped(reason: String)
        case failed(Error)
    }

    // MARK: - Public API

    /// Inject health metrics for the enabled metrics into a daily note.
    ///
    /// Which metrics are injected is determined by `metricSelection` — the same
    /// selection the user configures in Health Metrics settings.
    @discardableResult
    static func inject(
        healthData: HealthData,
        into vaultURL: URL,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization,
        metricSelection: MetricSelectionState
    ) -> InjectionResult {
        guard settings.enabled else { return .skipped(reason: "Injection disabled") }

        // 1. Resolve target file URL
        var targetURL = vaultURL
        let folder = settings.folderPath.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty {
            targetURL = targetURL.appendingPathComponent(folder, isDirectory: true)
        }
        let filename = settings.formatFilename(for: healthData.date) + ".md"
        targetURL = targetURL.appendingPathComponent(filename)

        let fm = FileManager.default

        // 2. Handle missing file
        if !fm.fileExists(atPath: targetURL.path) {
            if settings.createIfMissing {
                do {
                    // Always call createDirectory with withIntermediateDirectories:true —
                    // it is idempotent and creates the full path (e.g. vault/Daily/) in one call.
                    let parent = targetURL.deletingLastPathComponent()
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
                    try "".write(to: targetURL, atomically: true, encoding: .utf8)
                } catch {
                    return .failed(error)
                }
            } else {
                return .skipped(reason: "Daily note not found: \(filename)")
            }
        }

        // 3. Read existing content
        let existingContent: String
        do {
            existingContent = try String(contentsOf: targetURL, encoding: .utf8)
        } catch {
            return .failed(error)
        }

        // 4. Build the set of frontmatter keys to inject based on enabled metrics
        let allMetrics = healthData.allMetricsDictionary(using: customization.unitConverter, timeFormat: customization.timeFormat)
        let fmConfig = customization.frontmatterConfig
        let allowedKeys = frontmatterKeys(enabledIn: metricSelection)

        var injectionLines: [String] = ["---"]
        // Preserve order: iterate over allowedKeys in a stable sequence
        for originalKey in allowedKeys {
            guard let value = allMetrics[originalKey] else { continue }
            let outputKey = resolvedOutputKey(originalKey: originalKey, fmConfig: fmConfig)
            injectionLines.append("\(outputKey): \(value)")
        }

        guard injectionLines.count > 1 else {
            return .skipped(reason: "No data available for enabled metrics on this date")
        }
        injectionLines.append("---")
        let injectionFrontmatter = injectionLines.joined(separator: "\n") + "\n"

        // 5. Merge into existing content (body preserved)
        let updatedContent = mergeIntoContent(
            existing: existingContent,
            injectionFrontmatter: injectionFrontmatter
        )

        // 6. Write back
        do {
            try updatedContent.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            return .failed(error)
        }

        return .updated(path: settings.previewPath(for: healthData.date))
    }

    // MARK: - Private helpers

    /// Returns the ordered set of frontmatter originalKeys that correspond to
    /// metrics enabled in the given MetricSelectionState.
    static func frontmatterKeys(enabledIn metricSelection: MetricSelectionState) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()

        for metric in HealthMetrics.all {
            guard metricSelection.isMetricEnabled(metric.id) else { continue }
            guard let fmKeys = metricIdToFrontmatterKeys[metric.id] else { continue }
            for k in fmKeys where !seen.contains(k) {
                keys.append(k)
                seen.insert(k)
            }
        }
        return keys
    }

    private static func resolvedOutputKey(
        originalKey: String,
        fmConfig: FrontmatterConfiguration
    ) -> String {
        if let field = fmConfig.fields.first(where: { $0.originalKey == originalKey }) {
            let key = field.customKey.trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? originalKey : key
        }
        return originalKey
    }

    private static func mergeIntoContent(existing: String, injectionFrontmatter: String) -> String {
        let lines = existing.components(separatedBy: "\n")
        var existingFrontmatter = ""
        var bodyStartIndex = 0

        if let first = lines.first,
           first.trimmingCharacters(in: .whitespaces) == "---" {
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    existingFrontmatter = lines[0...i].joined(separator: "\n") + "\n"
                    bodyStartIndex = i + 1
                    break
                }
            }
        }

        if existingFrontmatter.isEmpty {
            if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return injectionFrontmatter
            }
            return injectionFrontmatter + "\n" + existing
        }

        let mergedFrontmatter = MarkdownMerger.mergeFrontmatter(
            existing: existingFrontmatter,
            new: injectionFrontmatter
        )

        let body = lines[bodyStartIndex...].joined(separator: "\n")
        if body.hasPrefix("\n") || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mergedFrontmatter + body
        }
        return mergedFrontmatter + "\n" + body
    }
}
