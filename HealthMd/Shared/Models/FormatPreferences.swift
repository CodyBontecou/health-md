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
        case .iso8601: return "ISO 8601 (2026-01-13)"
        case .usShort: return "US Short (01/13/2026)"
        case .usLong: return "US Long (January 13, 2026)"
        case .euShort: return "EU Short (13/01/2026)"
        case .euLong: return "EU Long (13 January 2026)"
        case .compact: return "Compact (20260113)"
        case .friendly: return "Friendly (Mon, Jan 13, 2026)"
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
        case .hour24: return "24-hour (14:30)"
        case .hour24WithSeconds: return "24-hour with seconds (14:30:45)"
        case .hour12: return "12-hour (2:30 PM)"
        case .hour12WithSeconds: return "12-hour with seconds (2:30:45 PM)"
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
        case .metric: return "Kilometers, kilograms, Celsius"
        case .imperial: return "Miles, pounds, Fahrenheit"
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
    @Published var customFields: [String: String]  // Additional user-defined fields
    @Published var includeDate: Bool
    @Published var includeType: Bool
    @Published var customDateKey: String
    @Published var customTypeKey: String
    @Published var customTypeValue: String
    
    enum CodingKeys: String, CodingKey {
        case fields, customFields, includeDate, includeType
        case customDateKey, customTypeKey, customTypeValue
    }
    
    static let defaultFields: [CustomFrontmatterField] = [
        // Sleep
        CustomFrontmatterField(originalKey: "sleep_total_hours"),
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
        // Heart
        CustomFrontmatterField(originalKey: "resting_heart_rate"),
        CustomFrontmatterField(originalKey: "walking_heart_rate"),
        CustomFrontmatterField(originalKey: "average_heart_rate"),
        CustomFrontmatterField(originalKey: "heart_rate_min"),
        CustomFrontmatterField(originalKey: "heart_rate_max"),
        CustomFrontmatterField(originalKey: "hrv_ms"),
        // Vitals
        CustomFrontmatterField(originalKey: "respiratory_rate"),
        CustomFrontmatterField(originalKey: "blood_oxygen"),
        CustomFrontmatterField(originalKey: "body_temperature"),
        CustomFrontmatterField(originalKey: "blood_pressure_systolic"),
        CustomFrontmatterField(originalKey: "blood_pressure_diastolic"),
        CustomFrontmatterField(originalKey: "blood_glucose"),
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
    ]
    
    init() {
        self.fields = Self.defaultFields
        self.customFields = [:]
        self.includeDate = true
        self.includeType = true
        self.customDateKey = "date"
        self.customTypeKey = "type"
        self.customTypeValue = "health-data"
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fields = try container.decodeIfPresent([CustomFrontmatterField].self, forKey: .fields) ?? Self.defaultFields
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        includeDate = try container.decodeIfPresent(Bool.self, forKey: .includeDate) ?? true
        includeType = try container.decodeIfPresent(Bool.self, forKey: .includeType) ?? true
        customDateKey = try container.decodeIfPresent(String.self, forKey: .customDateKey) ?? "date"
        customTypeKey = try container.decodeIfPresent(String.self, forKey: .customTypeKey) ?? "type"
        customTypeValue = try container.decodeIfPresent(String.self, forKey: .customTypeValue) ?? "health-data"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fields, forKey: .fields)
        try container.encode(customFields, forKey: .customFields)
        try container.encode(includeDate, forKey: .includeDate)
        try container.encode(includeType, forKey: .includeType)
        try container.encode(customDateKey, forKey: .customDateKey)
        try container.encode(customTypeKey, forKey: .customTypeKey)
        try container.encode(customTypeValue, forKey: .customTypeValue)
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
    
    /// Reset all fields to defaults
    func reset() {
        fields = Self.defaultFields
        customFields = [:]
        includeDate = true
        includeType = true
        customDateKey = "date"
        customTypeKey = "type"
        customTypeValue = "health-data"
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
        case .standard: return "Balanced format with sections and bullet points"
        case .compact: return "Condensed single-line metrics, minimal whitespace"
        case .detailed: return "Expanded format with descriptions and context"
        case .custom: return "Your own template with placeholders"
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
            case .dash: return "Dash (-)"
            case .asterisk: return "Asterisk (*)"
            case .plus: return "Plus (+)"
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
