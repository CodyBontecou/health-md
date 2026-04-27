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
    case euShort = "dd/MM/yyyy"           // 13/01/2026
    case euLong = "d MMMM yyyy"           // 13 January 2026
    case compact = "yyyyMMdd"             // 20260113
    case friendly = "EEE, MMM d, yyyy"    // Mon, Jan 13, 2026
    
    var displayName: String {
        switch self {
        case .iso8601: return String(localized: "ISO 8601 (2026-01-13)", comment: "Date format option")
        case .usShort: return String(localized: "US Short (01/13/2026)", comment: "Date format option")
        case .usLong: return String(localized: "US Long (January 13, 2026)", comment: "Date format option")
        case .euShort: return String(localized: "EU Short (13/01/2026)", comment: "Date format option")
        case .euLong: return String(localized: "EU Long (13 January 2026)", comment: "Date format option")
        case .compact: return String(localized: "Compact (20260113)", comment: "Date format option")
        case .friendly: return String(localized: "Friendly (Mon, Jan 13, 2026)", comment: "Date format option")
        }
    }
    
    func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self.rawValue
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
    
    func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self.rawValue
        return formatter.string(from: date)
    }
}

// MARK: - Unit Preferences

enum UnitPreference: String, CaseIterable, Codable {
    case metric = "Metric"
    case imperial = "Imperial"
    
    var displayName: String { rawValue }
    
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
    
    enum CodingKeys: String, CodingKey {
        case fields, customFields, placeholderFields, includeDate, includeType
        case customDateKey, customTypeKey, customTypeValue, keyStyle
    }
    
    static let defaultFields: [CustomFrontmatterField] = [
        // Sleep
        CustomFrontmatterField(originalKey: "sleep_total_hours"),
        CustomFrontmatterField(originalKey: "sleep_bedtime"),
        CustomFrontmatterField(originalKey: "sleep_wake"),
        CustomFrontmatterField(originalKey: "sleep_deep_hours"),
        CustomFrontmatterField(originalKey: "sleep_rem_hours"),
        CustomFrontmatterField(originalKey: "sleep_core_hours"),
        CustomFrontmatterField(originalKey: "sleep_awake_hours"),
        CustomFrontmatterField(originalKey: "sleep_in_bed_hours"),
        // Activity
        CustomFrontmatterField(originalKey: "steps"),
        CustomFrontmatterField(originalKey: "active_calories"),
        CustomFrontmatterField(originalKey: "basal_calories"),
        CustomFrontmatterField(originalKey: "exercise_minutes"),
        CustomFrontmatterField(originalKey: "stand_hours"),
        CustomFrontmatterField(originalKey: "flights_climbed"),
        CustomFrontmatterField(originalKey: "walking_running_km"),
        CustomFrontmatterField(originalKey: "cycling_km"),
        CustomFrontmatterField(originalKey: "swimming_m"),
        CustomFrontmatterField(originalKey: "swimming_strokes"),
        CustomFrontmatterField(originalKey: "wheelchair_pushes"),
        CustomFrontmatterField(originalKey: "vo2_max"),
        // Heart
        CustomFrontmatterField(originalKey: "resting_heart_rate"),
        CustomFrontmatterField(originalKey: "walking_heart_rate"),
        CustomFrontmatterField(originalKey: "average_heart_rate"),
        CustomFrontmatterField(originalKey: "heart_rate_min"),
        CustomFrontmatterField(originalKey: "heart_rate_max"),
        CustomFrontmatterField(originalKey: "hrv_ms"),
        // Vitals
        CustomFrontmatterField(originalKey: "respiratory_rate"),
        CustomFrontmatterField(originalKey: "respiratory_rate_avg"),
        CustomFrontmatterField(originalKey: "respiratory_rate_min"),
        CustomFrontmatterField(originalKey: "respiratory_rate_max"),
        CustomFrontmatterField(originalKey: "blood_oxygen"),
        CustomFrontmatterField(originalKey: "blood_oxygen_avg"),
        CustomFrontmatterField(originalKey: "blood_oxygen_min"),
        CustomFrontmatterField(originalKey: "blood_oxygen_max"),
        CustomFrontmatterField(originalKey: "body_temperature"),
        CustomFrontmatterField(originalKey: "body_temperature_avg"),
        CustomFrontmatterField(originalKey: "body_temperature_min"),
        CustomFrontmatterField(originalKey: "body_temperature_max"),
        CustomFrontmatterField(originalKey: "blood_pressure_systolic"),
        CustomFrontmatterField(originalKey: "blood_pressure_systolic_avg"),
        CustomFrontmatterField(originalKey: "blood_pressure_systolic_min"),
        CustomFrontmatterField(originalKey: "blood_pressure_systolic_max"),
        CustomFrontmatterField(originalKey: "blood_pressure_diastolic"),
        CustomFrontmatterField(originalKey: "blood_pressure_diastolic_avg"),
        CustomFrontmatterField(originalKey: "blood_pressure_diastolic_min"),
        CustomFrontmatterField(originalKey: "blood_pressure_diastolic_max"),
        CustomFrontmatterField(originalKey: "blood_glucose"),
        CustomFrontmatterField(originalKey: "blood_glucose_avg"),
        CustomFrontmatterField(originalKey: "blood_glucose_min"),
        CustomFrontmatterField(originalKey: "blood_glucose_max"),
        // Body
        CustomFrontmatterField(originalKey: "weight_kg"),
        CustomFrontmatterField(originalKey: "height_m"),
        CustomFrontmatterField(originalKey: "bmi"),
        CustomFrontmatterField(originalKey: "body_fat_percent"),
        CustomFrontmatterField(originalKey: "lean_body_mass_kg"),
        CustomFrontmatterField(originalKey: "waist_circumference_cm"),
        // Nutrition
        CustomFrontmatterField(originalKey: "dietary_calories"),
        CustomFrontmatterField(originalKey: "protein_g"),
        CustomFrontmatterField(originalKey: "carbohydrates_g"),
        CustomFrontmatterField(originalKey: "fat_g"),
        CustomFrontmatterField(originalKey: "saturated_fat_g"),
        CustomFrontmatterField(originalKey: "fiber_g"),
        CustomFrontmatterField(originalKey: "sugar_g"),
        CustomFrontmatterField(originalKey: "sodium_mg"),
        CustomFrontmatterField(originalKey: "cholesterol_mg"),
        CustomFrontmatterField(originalKey: "water_l"),
        CustomFrontmatterField(originalKey: "caffeine_mg"),
        // Mindfulness
        CustomFrontmatterField(originalKey: "mindful_minutes"),
        CustomFrontmatterField(originalKey: "mindful_sessions"),
        CustomFrontmatterField(originalKey: "mood_entries"),
        CustomFrontmatterField(originalKey: "average_mood_valence"),
        CustomFrontmatterField(originalKey: "average_mood_percent"),
        CustomFrontmatterField(originalKey: "daily_mood_count"),
        CustomFrontmatterField(originalKey: "daily_mood_percent"),
        CustomFrontmatterField(originalKey: "momentary_emotion_count"),
        CustomFrontmatterField(originalKey: "mood_labels"),
        CustomFrontmatterField(originalKey: "mood_associations"),
        // Mobility
        CustomFrontmatterField(originalKey: "walking_speed"),
        CustomFrontmatterField(originalKey: "step_length_cm"),
        CustomFrontmatterField(originalKey: "double_support_percent"),
        CustomFrontmatterField(originalKey: "walking_asymmetry_percent"),
        CustomFrontmatterField(originalKey: "stair_ascent_speed"),
        CustomFrontmatterField(originalKey: "stair_descent_speed"),
        CustomFrontmatterField(originalKey: "six_min_walk_m"),
        // Hearing
        CustomFrontmatterField(originalKey: "headphone_audio_db"),
        CustomFrontmatterField(originalKey: "environmental_sound_db"),
        // Workouts
        CustomFrontmatterField(originalKey: "workout_count"),
        CustomFrontmatterField(originalKey: "workout_minutes"),
        CustomFrontmatterField(originalKey: "workout_calories"),
        CustomFrontmatterField(originalKey: "workout_distance_km"),
        CustomFrontmatterField(originalKey: "workouts"),
        CustomFrontmatterField(originalKey: "workout_avg_heart_rate"),
        CustomFrontmatterField(originalKey: "workout_max_heart_rate"),
        CustomFrontmatterField(originalKey: "workout_min_heart_rate"),
        CustomFrontmatterField(originalKey: "workout_running_cadence"),
        CustomFrontmatterField(originalKey: "workout_running_stride_length"),
        CustomFrontmatterField(originalKey: "workout_running_ground_contact"),
        CustomFrontmatterField(originalKey: "workout_running_vertical_oscillation"),
        CustomFrontmatterField(originalKey: "workout_cycling_cadence"),
        CustomFrontmatterField(originalKey: "workout_avg_power"),
        CustomFrontmatterField(originalKey: "workout_max_power"),
    ]
    
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
        var decoded = try container.decodeIfPresent([CustomFrontmatterField].self, forKey: .fields) ?? Self.defaultFields
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        placeholderFields = try container.decodeIfPresent([String].self, forKey: .placeholderFields) ?? []
        includeDate = try container.decodeIfPresent(Bool.self, forKey: .includeDate) ?? true
        includeType = try container.decodeIfPresent(Bool.self, forKey: .includeType) ?? true
        customDateKey = try container.decodeIfPresent(String.self, forKey: .customDateKey) ?? "date"
        customTypeKey = try container.decodeIfPresent(String.self, forKey: .customTypeKey) ?? "type"
        customTypeValue = try container.decodeIfPresent(String.self, forKey: .customTypeValue) ?? "health-data"
        keyStyle = try container.decodeIfPresent(FrontmatterKeyStyle.self, forKey: .keyStyle) ?? .snakeCase

        // Migration: inject any default fields that are missing from a saved config.
        // This ensures users upgrading from older versions see new fields rather than
        // having them silently absent.
        let existingKeys = Set(decoded.map { $0.originalKey })
        for defaultField in Self.defaultFields {
            guard !existingKeys.contains(defaultField.originalKey) else { continue }
            // Insert adjacent to the field that precedes it in defaultFields, if possible.
            let defaultKeys = Self.defaultFields.map { $0.originalKey }
            if let defaultIndex = defaultKeys.firstIndex(of: defaultField.originalKey),
               defaultIndex > 0 {
                let precedingKey = defaultKeys[defaultIndex - 1]
                if let insertAfter = decoded.firstIndex(where: { $0.originalKey == precedingKey }) {
                    decoded.insert(defaultField, at: insertAfter + 1)
                } else {
                    decoded.append(defaultField)
                }
            } else {
                decoded.insert(defaultField, at: 0)
            }
        }
        fields = decoded
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
}

// MARK: - Markdown Template

enum MarkdownTemplateStyle: String, CaseIterable, Codable {
    case standard = "Standard"
    case compact = "Compact"
    case detailed = "Detailed"
    case custom = "Custom"
    
    var displayName: String { rawValue }
    
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
    """
    
    init() {
        self.style = .standard
        self.customTemplate = Self.defaultTemplate
        self.sectionHeaderLevel = 2
        self.useEmoji = false
        self.includeSummary = true
        self.bulletStyle = .dash
    }
}

// MARK: - Unit Conversion Helpers

struct UnitConverter {
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
