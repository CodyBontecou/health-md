//
//  FormatPreferences.swift
//  Health.md
//
//  Export format customization preferences
//

import Foundation
import Combine

// MARK: - Date Format

enum DateFormatPreference: String, CaseIterable, Codable {
    case iso8601 = "yyyy-MM-dd"           // 2026-01-13
    case usShort = "MM/dd/yyyy"           // 01/13/2026
    case usLong = "MMMM d, yyyy"          // January 13, 2026
    case euDot = "dd.MM.yyyy"             // 13.01.2026
    case euShort = "dd/MM/yyyy"           // 13/01/2026
    case euLong = "d MMMM yyyy"           // 13 January 2026
    case compact = "yyyyMMdd"             // 20260113
    case friendly = "EEE, MMM d, yyyy"    // Mon, Jan 13, 2026
    
    var displayName: String {
        switch self {
        case .iso8601: return String(localized: "ISO 8601 (2026-01-13)", comment: "Date format option")
        case .usShort: return String(localized: "US Short (01/13/2026)", comment: "Date format option")
        case .usLong: return String(localized: "US Long (January 13, 2026)", comment: "Date format option")
        case .euDot: return String(localized: "EU Dot (13.01.2026)", comment: "Date format option")
        case .euShort: return String(localized: "EU Short (13/01/2026)", comment: "Date format option")
        case .euLong: return String(localized: "EU Long (13 January 2026)", comment: "Date format option")
        case .compact: return String(localized: "Compact (20260113)", comment: "Date format option")
        case .friendly: return String(localized: "Friendly (Mon, Jan 13, 2026)", comment: "Date format option")
        }
    }
    
    func format(date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self.rawValue
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

// MARK: - Time Format

enum TimeFormatPreference: String, CaseIterable, Codable {
    case hour24 = "HH:mm"                 // 14:30
    case hour24WithSeconds = "HH:mm:ss"   // 14:30:45
    case hour12 = "h:mm a"                // 2:30 PM
    case hour12WithSeconds = "h:mm:ss a"  // 2:30:45 PM
    
    var displayName: String {
        switch self {
        case .hour24: return String(localized: "24-hour (14:30)", comment: "Time format option")
        case .hour24WithSeconds: return String(localized: "24-hour with seconds (14:30:45)", comment: "Time format option")
        case .hour12: return String(localized: "12-hour (2:30 PM)", comment: "Time format option")
        case .hour12WithSeconds: return String(localized: "12-hour with seconds (2:30:45 PM)", comment: "Time format option")
        }
    }
    
    func format(date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self.rawValue
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

// MARK: - Unit Preferences

enum UnitPreference: String, CaseIterable, Codable {
    case metric = "Metric"
    case imperial = "Imperial"
    
    var displayName: String {
        switch self {
        case .metric: return String(localized: "Metric", comment: "Unit system option")
        case .imperial: return String(localized: "Imperial", comment: "Unit system option")
        }
    }
    
    var description: String {
        switch self {
        case .metric: return String(localized: "Kilometers, kilograms, Celsius", comment: "Metric units description")
        case .imperial: return String(localized: "Miles, pounds, Fahrenheit", comment: "Imperial units description")
        }
    }
}

// MARK: - Frontmatter Key Style

enum FrontmatterKeyStyle: String, CaseIterable, Codable {
    case snakeCase = "snake_case"
    case camelCase = "camelCase"
    
    var displayName: String {
        switch self {
        case .snakeCase: return "snake_case"
        case .camelCase: return "camelCase"
        }
    }
    
    var description: String {
        switch self {
        case .snakeCase: return String(localized: "sleep_total_hours, active_calories", comment: "Snake case example")
        case .camelCase: return String(localized: "sleepTotalHours, activeCalories", comment: "Camel case example")
        }
    }
    
    /// Convert a snake_case string to camelCase
    static func toCamelCase(_ snakeCase: String) -> String {
        let parts = snakeCase.split(separator: "_")
        guard let first = parts.first else { return snakeCase }
        let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return String(first) + rest.joined()
    }
    
    /// Convert a camelCase string to snake_case
    static func toSnakeCase(_ camelCase: String) -> String {
        var result = ""
        for (i, char) in camelCase.enumerated() {
            if char.isUppercase {
                if i > 0 { result += "_" }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }
    
    /// Apply this style to a snake_case original key
    func apply(to originalKey: String) -> String {
        switch self {
        case .snakeCase: return originalKey
        case .camelCase: return Self.toCamelCase(originalKey)
        }
    }
}

// MARK: - Custom Frontmatter Field

struct CustomFrontmatterField: Codable, Identifiable, Equatable {
    var id: String { originalKey }
    let originalKey: String
    var customKey: String
    var isEnabled: Bool
    
    init(originalKey: String, customKey: String? = nil, isEnabled: Bool = true) {
        self.originalKey = originalKey
        self.customKey = customKey ?? originalKey
        self.isEnabled = isEnabled
    }
    
    /// Returns the key to use in output (custom if different, otherwise original)
    var outputKey: String {
        customKey.isEmpty ? originalKey : customKey
    }
}

// MARK: - Frontmatter Configuration

extension CodingUserInfoKey {
    static let includeSharedSetupExactFrontmatter = CodingUserInfoKey(rawValue: "healthmd.includeSharedSetupExactFrontmatter")!
}

class FrontmatterConfiguration: ObservableObject, Codable {
    @Published var fields: [CustomFrontmatterField]
    @Published var customFields: [String: String]  // Additional user-defined fields with fixed values
    @Published var placeholderFields: [String]  // Fields that export with empty values for manual entry
    @Published var includeDate: Bool
    @Published var includeType: Bool
    @Published var customDateKey: String
    @Published var customTypeKey: String
    @Published var customTypeValue: String
    @Published var keyStyle: FrontmatterKeyStyle
    /// Shared-setup imports treat the explicit field ledger as authority. Native settings keep
    /// the historical migration behavior that appends newly introduced default fields.
    var preservesExactFieldSet: Bool
    
    enum CodingKeys: String, CodingKey {
        case fields, customFields, placeholderFields, includeDate, includeType
        case customDateKey, customTypeKey, customTypeValue, keyStyle, preservesExactFieldSet
    }
    
    private static let preferredFieldOrder: [String] = [
        // Sleep
        "sleep_total_hours",
        "sleep_bedtime",
        "sleep_wake",
        "sleep_deep_hours",
        "sleep_rem_hours",
        "sleep_core_hours",
        "sleep_awake_hours",
        "sleep_in_bed_hours",
        // Activity
        "steps",
        "active_calories",
        "basal_calories",
        "exercise_minutes",
        "stand_time_minutes",
        "stand_hours",
        "flights_climbed",
        "walking_running_km",
        "walking_running_mi",
        "cycling_km",
        "cycling_mi",
        "swimming_m",
        "swimming_strokes",
        "wheelchair_pushes",
        "vo2_max",
        // Heart
        "resting_heart_rate",
        "walking_heart_rate",
        "average_heart_rate",
        "heart_rate_min",
        "heart_rate_max",
        "hrv_ms",
        // Vitals
        "respiratory_rate",
        "respiratory_rate_avg",
        "respiratory_rate_min",
        "respiratory_rate_max",
        "blood_oxygen",
        "blood_oxygen_avg",
        "blood_oxygen_min",
        "blood_oxygen_max",
        "body_temperature",
        "body_temperature_avg",
        "body_temperature_min",
        "body_temperature_max",
        "blood_pressure_systolic",
        "blood_pressure_systolic_avg",
        "blood_pressure_systolic_min",
        "blood_pressure_systolic_max",
        "blood_pressure_diastolic",
        "blood_pressure_diastolic_avg",
        "blood_pressure_diastolic_min",
        "blood_pressure_diastolic_max",
        "blood_glucose",
        "blood_glucose_avg",
        "blood_glucose_min",
        "blood_glucose_max",
        // Body
        "weight_kg",
        "height_m",
        "bmi",
        "body_fat_percent",
        "lean_body_mass_kg",
        "waist_circumference_cm",
        // Nutrition
        "dietary_calories",
        "protein_g",
        "carbohydrates_g",
        "fat_g",
        "saturated_fat_g",
        "fiber_g",
        "sugar_g",
        "sodium_mg",
        "cholesterol_mg",
        "water_l",
        "caffeine_mg",
        // Mindfulness
        "mindful_minutes",
        "mindful_sessions",
        "mood_entries",
        "average_mood_valence",
        "average_mood_percent",
        "daily_mood_count",
        "daily_mood_percent",
        "momentary_emotion_count",
        "mood_labels",
        "mood_associations",
        // Mobility
        "walking_speed",
        "step_length_cm",
        "double_support_percent",
        "walking_asymmetry_percent",
        "stair_ascent_speed",
        "stair_descent_speed",
        "six_min_walk_m",
        // Hearing
        "headphone_audio_db",
        "environmental_sound_db",
        // Workouts
        "workout_count",
        "workout_minutes",
        "workout_calories",
        "workout_distance_km",
        "workout_distance_mi",
        "workouts",
        "workout_avg_heart_rate",
        "workout_max_heart_rate",
        "workout_min_heart_rate",
        "workout_running_cadence",
        "workout_running_stride_length",
        "workout_running_ground_contact",
        "workout_running_vertical_oscillation",
        "workout_cycling_cadence",
        "workout_avg_power",
        "workout_max_power",
        "workout_details",
        // Medications
        "medication_count",
        "active_medication_count",
        "archived_medication_count",
        "medication_details",
        "medication_dose_count",
        "medication_dose_events",
        "medication_taken_count",
        "medication_skipped_count",
        "medications",
    ]

    /// The export mapping owns membership; this list preserves the historical editor order.
    /// `workout_details` is a native structured block rather than a flat metric mapping.
    static let defaultFields: [CustomFrontmatterField] = {
        let known = HealthMetricExportMapping.allKnownFrontmatterKeys.union(["workout_details"])
        let preferred = preferredFieldOrder.filter { known.contains($0) }
        let remaining = known.subtracting(preferred).sorted()
        return (preferred + remaining).map { CustomFrontmatterField(originalKey: $0) }
    }()

    init() {
        self.fields = Self.defaultFields
        self.customFields = [:]
        self.placeholderFields = []
        self.includeDate = true
        self.includeType = true
        self.customDateKey = "date"
        self.customTypeKey = "type"
        self.customTypeValue = "health-data"
        self.keyStyle = .snakeCase
        self.preservesExactFieldSet = false
        #if DEBUG
        LifecycleTracker.trackCreation(of: "FrontmatterConfiguration")
        #endif
    }

    deinit {
        #if DEBUG
        LifecycleTracker.trackDeinit(of: "FrontmatterConfiguration")
        #endif
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([CustomFrontmatterField].self, forKey: .fields) ?? Self.defaultFields
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        placeholderFields = try container.decodeIfPresent([String].self, forKey: .placeholderFields) ?? []
        includeDate = try container.decodeIfPresent(Bool.self, forKey: .includeDate) ?? true
        includeType = try container.decodeIfPresent(Bool.self, forKey: .includeType) ?? true
        customDateKey = try container.decodeIfPresent(String.self, forKey: .customDateKey) ?? "date"
        customTypeKey = try container.decodeIfPresent(String.self, forKey: .customTypeKey) ?? "type"
        customTypeValue = try container.decodeIfPresent(String.self, forKey: .customTypeValue) ?? "health-data"
        keyStyle = try container.decodeIfPresent(FrontmatterKeyStyle.self, forKey: .keyStyle) ?? .snakeCase
        if decoder.userInfo[.includeSharedSetupExactFrontmatter] as? Bool == true {
            preservesExactFieldSet = try container.decodeIfPresent(Bool.self, forKey: .preservesExactFieldSet) ?? false
        } else {
            preservesExactFieldSet = false
        }

        fields = decoded
        migrateMissingDefaultFields()
    }

    /// Native upgrades and editor copies expose newly mapped fields while preserving saved choices.
    /// Exact shared-setup imports retain their explicit field ledger.
    func migrateMissingDefaultFields() {
        guard !preservesExactFieldSet else { return }
        let existingKeys = Set(fields.map { $0.originalKey })
        let unitAlternateSourceKeys = [
            "walking_running_mi": "walking_running_km",
            "cycling_mi": "cycling_km",
            "workout_distance_mi": "workout_distance_km",
        ]
        for defaultField in Self.defaultFields {
            guard !existingKeys.contains(defaultField.originalKey) else { continue }
            var fieldToInsert = CustomFrontmatterField(originalKey: defaultField.originalKey,
                customKey: keyStyle.apply(to: defaultField.originalKey))
            if let sourceKey = unitAlternateSourceKeys[defaultField.originalKey],
               let sourceField = fields.first(where: { $0.originalKey == sourceKey }) {
                fieldToInsert = CustomFrontmatterField(
                    originalKey: defaultField.originalKey,
                    customKey: Self.customKeyForUnitAlternate(
                        sourceCustomKey: sourceField.customKey,
                        sourceOriginalKey: sourceField.originalKey,
                        defaultOriginalKey: defaultField.originalKey
                    ),
                    isEnabled: sourceField.isEnabled
                )
            }
            // Insert adjacent to the field that precedes it in defaultFields, if possible.
            let defaultKeys = Self.defaultFields.map { $0.originalKey }
            if let defaultIndex = defaultKeys.firstIndex(of: defaultField.originalKey),
               defaultIndex > 0 {
                let precedingKey = defaultKeys[defaultIndex - 1]
                if let insertAfter = fields.firstIndex(where: { $0.originalKey == precedingKey }) {
                    fields.insert(fieldToInsert, at: insertAfter + 1)
                } else {
                    fields.append(fieldToInsert)
                }
            } else {
                fields.insert(fieldToInsert, at: 0)
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fields, forKey: .fields)
        try container.encode(customFields, forKey: .customFields)
        try container.encode(placeholderFields, forKey: .placeholderFields)
        try container.encode(includeDate, forKey: .includeDate)
        try container.encode(includeType, forKey: .includeType)
        try container.encode(customDateKey, forKey: .customDateKey)
        try container.encode(customTypeKey, forKey: .customTypeKey)
        try container.encode(customTypeValue, forKey: .customTypeValue)
        try container.encode(keyStyle, forKey: .keyStyle)
        if encoder.userInfo[.includeSharedSetupExactFrontmatter] as? Bool == true {
            try container.encode(preservesExactFieldSet, forKey: .preservesExactFieldSet)
        }
    }
    
    /// Configuration validation only; user-defined keys are never included in error telemetry.
    var conflictingOutputKeys: Set<String> { Set(keyConflicts.map(\.outputKey)) }

    var keyConflicts: [FrontmatterKeyConflict] {
        let entries = Dictionary(grouping: configuredOutputSources(), by: \.key)
        return entries.keys.sorted().compactMap { key in
            let sources = entries[key, default: []].map(\.source)
            let reserved = Self.reservedNoteKeys.contains(key)
            guard sources.count > 1 || reserved else { return nil }
            return FrontmatterKeyConflict(outputKey: key, sources: sources, isReserved: reserved)
        }
    }

    func hasConflictingName(_ name: String, for originalKey: String) -> Bool {
        guard fields.first(where: { $0.originalKey == originalKey })?.isEnabled == true else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.isEmpty ? originalKey : trimmed
        return Self.reservedNoteKeys.contains(key) || configuredOutputKeys(excluding: originalKey).contains(key)
    }

    private static let reservedNoteKeys: Set<String> = [
        "healthmd_injection_kind", "healthmd_daily_injection_v1", "healthmd_daily_injection_v2"
    ]

    private func configuredOutputKeys(excluding originalKey: String? = nil) -> [String] {
        configuredOutputSources(excluding: originalKey).map(\.key)
    }

    private func configuredOutputSources(excluding originalKey: String? = nil)
        -> [(key: String, source: FrontmatterConflictSource)] {
        let configured = Set(fields.map(\.originalKey))
        // Missing legacy fields are enabled defaults, just as in the injector.
        let effectiveFields = fields + Self.defaultFields.filter { !configured.contains($0.originalKey) }
        var entries = effectiveFields.filter { $0.isEnabled && $0.originalKey != originalKey }.map { field in
            let key = field.customKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return (key: key.isEmpty ? field.originalKey : key,
                source: FrontmatterConflictSource(originalKey: field.originalKey,
                    destination: .metrics(FrontmatterFieldGroup.group(for: field.originalKey))))
        }
        if includeDate { entries.append((customDateKey, .init(originalKey: "date", destination: .core))) }
        if includeType { entries.append((customTypeKey, .init(originalKey: "type", destination: .core))) }
        entries += customFields.keys.sorted().map { ($0, .init(originalKey: $0, destination: .custom)) }
        entries += placeholderFields.map { ($0, .init(originalKey: $0, destination: .placeholders)) }
        return entries
    }

    static var keyConflictMessage: String {
        String(localized: "Frontmatter key conflict. Give each enabled field a unique, non-reserved name in Frontmatter Fields. Your daily note was not changed.")
    }

    /// Get the output key for a given original key
    func outputKey(for originalKey: String) -> String? {
        guard let field = fields.first(where: { $0.originalKey == originalKey }),
              field.isEnabled else {
            return nil
        }
        return field.outputKey
    }
    
    /// Check if a field is enabled
    func isFieldEnabled(_ originalKey: String) -> Bool {
        fields.first(where: { $0.originalKey == originalKey })?.isEnabled ?? true
    }
    
    /// Apply the given key style to all fields, converting their customKey values
    func applyKeyStyle(_ style: FrontmatterKeyStyle) {
        keyStyle = style
        for i in fields.indices {
            fields[i].customKey = style.apply(to: fields[i].originalKey)
        }
    }
    
    /// Reset all fields to defaults
    func reset() {
        fields = Self.defaultFields
        customFields = [:]
        placeholderFields = []
        includeDate = true
        includeType = true
        customDateKey = "date"
        customTypeKey = "type"
        customTypeValue = "health-data"
        keyStyle = .snakeCase
    }

    private static func customKeyForUnitAlternate(
        sourceCustomKey: String,
        sourceOriginalKey: String,
        defaultOriginalKey: String
    ) -> String {
        guard sourceCustomKey != sourceOriginalKey else { return defaultOriginalKey }
        if sourceCustomKey.hasSuffix("_km") {
            return String(sourceCustomKey.dropLast(3)) + "_mi"
        }
        if sourceCustomKey.hasSuffix("Km") {
            return String(sourceCustomKey.dropLast(2)) + "Mi"
        }
        return sourceCustomKey
    }
}

// MARK: - Markdown Template

enum MarkdownTemplateStyle: String, CaseIterable, Codable {
    case standard = "Standard"
    case compact = "Compact"
    case detailed = "Detailed"
    case custom = "Custom"
    
    var displayName: String {
        switch self {
        case .standard: return String(localized: "Standard", comment: "Markdown template style")
        case .compact: return String(localized: "Compact", comment: "Markdown template style")
        case .detailed: return String(localized: "Detailed", comment: "Markdown template style")
        case .custom: return String(localized: "Custom", comment: "Markdown template style")
        }
    }
    
    var description: String {
        switch self {
        case .standard: return String(localized: "Balanced format with sections and bullet points", comment: "Standard template description")
        case .compact: return String(localized: "Condensed single-line metrics, minimal whitespace", comment: "Compact template description")
        case .detailed: return String(localized: "Expanded format with descriptions and context", comment: "Detailed template description")
        case .custom: return String(localized: "Your own template with placeholders", comment: "Custom template description")
        }
    }
}

struct MarkdownTemplateConfig: Codable, Equatable {
    var style: MarkdownTemplateStyle
    var customTemplate: String
    var sectionHeaderLevel: Int  // 1 = #, 2 = ##, 3 = ###
    var useEmoji: Bool
    var includeSummary: Bool
    var bulletStyle: BulletStyle
    /// Presentation only: never changes workout selection, frontmatter, or source capture.
    var includeWorkoutDetailsAndMetadata: Bool

    enum CodingKeys: String, CodingKey {
        case style, customTemplate, sectionHeaderLevel, useEmoji, includeSummary, bulletStyle
        case includeWorkoutDetailsAndMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decode(MarkdownTemplateStyle.self, forKey: .style)
        customTemplate = try container.decode(String.self, forKey: .customTemplate)
        sectionHeaderLevel = try container.decode(Int.self, forKey: .sectionHeaderLevel)
        useEmoji = try container.decode(Bool.self, forKey: .useEmoji)
        includeSummary = try container.decode(Bool.self, forKey: .includeSummary)
        bulletStyle = try container.decode(BulletStyle.self, forKey: .bulletStyle)
        includeWorkoutDetailsAndMetadata = try container.decodeIfPresent(
            Bool.self, forKey: .includeWorkoutDetailsAndMetadata
        ) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(customTemplate, forKey: .customTemplate)
        try container.encode(sectionHeaderLevel, forKey: .sectionHeaderLevel)
        try container.encode(useEmoji, forKey: .useEmoji)
        try container.encode(includeSummary, forKey: .includeSummary)
        try container.encode(bulletStyle, forKey: .bulletStyle)
        // Preserve the canonical bytes/fingerprints of default-on durable snapshots.
        if !includeWorkoutDetailsAndMetadata {
            try container.encode(false, forKey: .includeWorkoutDetailsAndMetadata)
        }
    }

    enum BulletStyle: String, CaseIterable, Codable {
        case dash = "-"
        case asterisk = "*"
        case plus = "+"
        
        var displayName: String {
            switch self {
            case .dash: return String(localized: "Dash (-)", comment: "Bullet style option")
            case .asterisk: return String(localized: "Asterisk (*)", comment: "Bullet style option")
            case .plus: return String(localized: "Plus (+)", comment: "Bullet style option")
            }
        }
    }
    
    static let defaultTemplate = """
    # Health Data — {{date}}
    
    {{#sleep}}
    ## 😴 Sleep
    {{sleep_metrics}}
    {{/sleep}}
    
    {{#activity}}
    ## 🏃 Activity
    {{activity_metrics}}
    {{/activity}}
    
    {{#heart}}
    ## ❤️ Heart
    {{heart_metrics}}
    {{/heart}}
    
    {{#vitals}}
    ## 🩺 Vitals
    {{vitals_metrics}}
    {{/vitals}}
    
    {{#body}}
    ## 📏 Body
    {{body_metrics}}
    {{/body}}
    
    {{#nutrition}}
    ## 🍎 Nutrition
    {{nutrition_metrics}}
    {{/nutrition}}
    
    {{#mindfulness}}
    ## 🧘 Mindfulness
    {{mindfulness_metrics}}
    {{/mindfulness}}
    
    {{#mobility}}
    ## 🚶 Mobility
    {{mobility_metrics}}
    {{/mobility}}
    
    {{#hearing}}
    ## 👂 Hearing
    {{hearing_metrics}}
    {{/hearing}}
    
    {{#workouts}}
    ## 💪 Workouts
    {{workout_list}}
    {{/workouts}}

    {{#medications}}
    ## 💊 Medications
    {{medications_metrics}}
    {{/medications}}
    """
    
    init() {
        self.style = .standard
        self.customTemplate = Self.defaultTemplate
        self.sectionHeaderLevel = 2
        self.useEmoji = false
        self.includeSummary = true
        self.bulletStyle = .dash
        self.includeWorkoutDetailsAndMetadata = true
    }
}

// MARK: - Unit Conversion Helpers

nonisolated struct UnitConverter {
    let preference: UnitPreference
    
    // Distance
    func formatDistance(_ meters: Double) -> String {
        switch preference {
        case .metric:
            if meters >= 1000 {
                return String(format: "%.2f km", meters / 1000)
            }
            return "\(Int(meters)) m"
        case .imperial:
            let miles = meters / 1609.344
            if miles >= 0.1 {
                return String(format: "%.2f mi", miles)
            }
            let feet = meters * 3.28084
            return "\(Int(feet)) ft"
        }
    }
    
    func distanceUnit(large: Bool = true) -> String {
        switch preference {
        case .metric: return large ? "km" : "m"
        case .imperial: return large ? "mi" : "ft"
        }
    }
    
    func convertDistance(_ meters: Double, toLarge: Bool = true) -> Double {
        switch preference {
        case .metric:
            return toLarge ? meters / 1000 : meters
        case .imperial:
            return toLarge ? meters / 1609.344 : meters * 3.28084
        }
    }

    /// Pace as "M:SS /km" (metric) or "M:SS /mi" (imperial).
    /// Returns nil for non-positive distance or unrealistic paces (>60 min per unit).
    func formatPace(meters: Double, duration: TimeInterval) -> String? {
        guard meters > 0, duration > 0 else { return nil }
        let unitMeters = preference == .metric ? 1000.0 : 1609.344
        let secondsPerUnit = duration / (meters / unitMeters)
        guard secondsPerUnit < 3600 else { return nil }
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit.rounded()) % 60
        let suffix = preference == .metric ? "/km" : "/mi"
        return String(format: "%d:%02d %@", minutes, seconds, suffix)
    }

    /// Speed as "X.X km/h" (metric) or "X.X mph" (imperial). Used for cycling
    /// and other speed-oriented activities where pace doesn't fit the convention.
    func formatSpeed(meters: Double, duration: TimeInterval) -> String? {
        guard meters > 0, duration > 0 else { return nil }
        let hours = duration / 3600.0
        switch preference {
        case .metric:
            return String(format: "%.1f km/h", (meters / 1000.0) / hours)
        case .imperial:
            return String(format: "%.1f mph", (meters / 1609.344) / hours)
        }
    }

    /// Swim pace as "M:SS /100m" (metric) or "M:SS /100yd" (imperial).
    /// Returns nil for non-positive inputs or paces over 60 min per 100 units.
    func formatSwimPace(meters: Double, duration: TimeInterval) -> String? {
        guard meters > 0, duration > 0 else { return nil }
        let unitMeters = preference == .metric ? 100.0 : 91.44  // 100 yd ≈ 91.44 m
        let secondsPerUnit = duration / (meters / unitMeters)
        guard secondsPerUnit < 3600 else { return nil }
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit.rounded()) % 60
        let suffix = preference == .metric ? "/100m" : "/100yd"
        return String(format: "%d:%02d %@", minutes, seconds, suffix)
    }

    // Weight
    func formatWeight(_ kg: Double) -> String {
        switch preference {
        case .metric:
            return String(format: "%.1f kg", kg)
        case .imperial:
            let lbs = kg * 2.20462
            return String(format: "%.1f lbs", lbs)
        }
    }
    
    func weightUnit() -> String {
        switch preference {
        case .metric: return "kg"
        case .imperial: return "lbs"
        }
    }
    
    func convertWeight(_ kg: Double) -> Double {
        switch preference {
        case .metric: return kg
        case .imperial: return kg * 2.20462
        }
    }
    
    // Height
    func formatHeight(_ meters: Double) -> String {
        switch preference {
        case .metric:
            let cm = meters * 100
            return String(format: "%.1f cm", cm)
        case .imperial:
            let totalInches = meters * 39.3701
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)'\(inches)\""
        }
    }
    
    func heightUnit() -> String {
        switch preference {
        case .metric: return "cm"
        case .imperial: return "ft/in"
        }
    }
    
    func convertHeight(_ meters: Double) -> Double {
        switch preference {
        case .metric: return meters * 100  // to cm
        case .imperial: return meters * 39.3701  // to inches
        }
    }
    
    // Temperature
    func formatTemperature(_ celsius: Double) -> String {
        switch preference {
        case .metric:
            return String(format: "%.1f°C", celsius)
        case .imperial:
            let fahrenheit = (celsius * 9/5) + 32
            return String(format: "%.1f°F", fahrenheit)
        }
    }
    
    func temperatureUnit() -> String {
        switch preference {
        case .metric: return "°C"
        case .imperial: return "°F"
        }
    }
    
    func convertTemperature(_ celsius: Double) -> Double {
        switch preference {
        case .metric: return celsius
        case .imperial: return (celsius * 9/5) + 32
        }
    }
    
    // Speed
    func formatSpeed(_ metersPerSecond: Double) -> String {
        switch preference {
        case .metric:
            let kmh = metersPerSecond * 3.6
            return String(format: "%.1f km/h", kmh)
        case .imperial:
            let mph = metersPerSecond * 2.23694
            return String(format: "%.1f mph", mph)
        }
    }
    
    func speedUnit() -> String {
        switch preference {
        case .metric: return "km/h"
        case .imperial: return "mph"
        }
    }
    
    // Waist/length in cm
    func formatLength(_ meters: Double) -> String {
        switch preference {
        case .metric:
            return String(format: "%.1f cm", meters * 100)
        case .imperial:
            let inches = meters * 39.3701
            return String(format: "%.1f in", inches)
        }
    }
    
    func lengthUnit() -> String {
        switch preference {
        case .metric: return "cm"
        case .imperial: return "in"
        }
    }
    
    // Water/volume
    func formatVolume(_ liters: Double) -> String {
        switch preference {
        case .metric:
            return String(format: "%.2f L", liters)
        case .imperial:
            let oz = liters * 33.814
            return String(format: "%.1f oz", oz)
        }
    }
    
    func volumeUnit() -> String {
        switch preference {
        case .metric: return "L"
        case .imperial: return "oz"
        }
    }
    
    func convertVolume(_ liters: Double) -> Double {
        switch preference {
        case .metric: return liters
        case .imperial: return liters * 33.814
        }
    }
}
