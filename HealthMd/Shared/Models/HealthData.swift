import Foundation

// MARK: - Time-Series Sample Types

/// A single timestamped numeric reading (e.g., one heart rate measurement).
struct TimeSample: Codable, Sendable {
    let timestamp: Date
    let value: Double
}

/// A sleep stage interval with start/end times.
struct SleepStageSample: Codable, Sendable {
    /// One of: "deep", "rem", "core", "awake", "inBed", "unspecified"
    let stage: String
    let startDate: Date
    let endDate: Date
}

// MARK: - Sleep Data

struct SleepData: Codable {
    var totalDuration: TimeInterval = 0
    var deepSleep: TimeInterval = 0
    var remSleep: TimeInterval = 0
    var coreSleep: TimeInterval = 0
    var awakeTime: TimeInterval = 0
    var inBedTime: TimeInterval = 0

    /// Start of the overall sleep session (bedtime).
    /// Derived from the earliest InBed sample start, or the earliest sleep-stage sample start
    /// when no InBed samples are recorded.
    var sessionStart: Date? = nil

    /// End of the overall sleep session (wake time).
    /// Derived from the latest InBed sample end, or the latest sleep-stage sample end
    /// when no InBed samples are recorded.
    var sessionEnd: Date? = nil

    /// Individual sleep stage intervals for granular export.
    var stages: [SleepStageSample] = []

    var hasData: Bool {
        totalDuration > 0 || deepSleep > 0 || remSleep > 0 || coreSleep > 0 || awakeTime > 0 || inBedTime > 0
    }

    enum CodingKeys: String, CodingKey {
        case totalDuration, deepSleep, remSleep, coreSleep, awakeTime, inBedTime
        case sessionStart, sessionEnd, stages
    }

    init(
        totalDuration: TimeInterval = 0, deepSleep: TimeInterval = 0,
        remSleep: TimeInterval = 0, coreSleep: TimeInterval = 0,
        awakeTime: TimeInterval = 0, inBedTime: TimeInterval = 0,
        sessionStart: Date? = nil, sessionEnd: Date? = nil,
        stages: [SleepStageSample] = []
    ) {
        self.totalDuration = totalDuration
        self.deepSleep = deepSleep
        self.remSleep = remSleep
        self.coreSleep = coreSleep
        self.awakeTime = awakeTime
        self.inBedTime = inBedTime
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
        self.stages = stages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration) ?? 0
        deepSleep = try container.decodeIfPresent(TimeInterval.self, forKey: .deepSleep) ?? 0
        remSleep = try container.decodeIfPresent(TimeInterval.self, forKey: .remSleep) ?? 0
        coreSleep = try container.decodeIfPresent(TimeInterval.self, forKey: .coreSleep) ?? 0
        awakeTime = try container.decodeIfPresent(TimeInterval.self, forKey: .awakeTime) ?? 0
        inBedTime = try container.decodeIfPresent(TimeInterval.self, forKey: .inBedTime) ?? 0
        sessionStart = try container.decodeIfPresent(Date.self, forKey: .sessionStart)
        sessionEnd = try container.decodeIfPresent(Date.self, forKey: .sessionEnd)
        stages = try container.decodeIfPresent([SleepStageSample].self, forKey: .stages) ?? []
    }
}

// MARK: - Activity Data

struct ActivityData: Codable {
    var steps: Int?
    var activeCalories: Double?
    var exerciseMinutes: Double?
    var flightsClimbed: Int?
    var walkingRunningDistance: Double? // in meters
    var standHours: Int?
    var basalEnergyBurned: Double?
    var cyclingDistance: Double? // in meters
    var swimmingDistance: Double? // in meters
    var swimmingStrokes: Int?
    var pushCount: Int? // wheelchair users
    var vo2Max: Double? // mL/kg/min (Cardio Fitness)
    var wheelchairDistance: Double? // in meters
    var downhillSnowSportsDistance: Double? // in meters
    var moveTime: Double? // in minutes
    var physicalEffort: Double? // kcal/hr/kg

    var hasData: Bool {
        steps != nil || activeCalories != nil || exerciseMinutes != nil ||
        flightsClimbed != nil || walkingRunningDistance != nil ||
        standHours != nil || basalEnergyBurned != nil ||
        cyclingDistance != nil || swimmingDistance != nil ||
        swimmingStrokes != nil || pushCount != nil || vo2Max != nil ||
        wheelchairDistance != nil || downhillSnowSportsDistance != nil ||
        moveTime != nil || physicalEffort != nil
    }
}

// MARK: - Heart Data

struct HeartData: Codable {
    var restingHeartRate: Double?
    var walkingHeartRateAverage: Double?
    var averageHeartRate: Double?
    var hrv: Double? // in milliseconds
    var heartRateMin: Double?
    var heartRateMax: Double?

    /// Individual heart rate readings throughout the day for granular export.
    var heartRateSamples: [TimeSample] = []
    /// Individual HRV readings for granular export.
    var hrvSamples: [TimeSample] = []

    var heartRateRecovery: Double? // bpm
    var atrialFibrillationBurden: Double? // percentage

    var hasData: Bool {
        restingHeartRate != nil || walkingHeartRateAverage != nil ||
        averageHeartRate != nil || hrv != nil ||
        heartRateMin != nil || heartRateMax != nil ||
        heartRateRecovery != nil || atrialFibrillationBurden != nil
    }

    enum CodingKeys: String, CodingKey {
        case restingHeartRate, walkingHeartRateAverage, averageHeartRate
        case hrv, heartRateMin, heartRateMax
        case heartRateSamples, hrvSamples
    }

    init(
        restingHeartRate: Double? = nil, walkingHeartRateAverage: Double? = nil,
        averageHeartRate: Double? = nil, hrv: Double? = nil,
        heartRateMin: Double? = nil, heartRateMax: Double? = nil,
        heartRateSamples: [TimeSample] = [], hrvSamples: [TimeSample] = []
    ) {
        self.restingHeartRate = restingHeartRate
        self.walkingHeartRateAverage = walkingHeartRateAverage
        self.averageHeartRate = averageHeartRate
        self.hrv = hrv
        self.heartRateMin = heartRateMin
        self.heartRateMax = heartRateMax
        self.heartRateSamples = heartRateSamples
        self.hrvSamples = hrvSamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restingHeartRate = try container.decodeIfPresent(Double.self, forKey: .restingHeartRate)
        walkingHeartRateAverage = try container.decodeIfPresent(Double.self, forKey: .walkingHeartRateAverage)
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        hrv = try container.decodeIfPresent(Double.self, forKey: .hrv)
        heartRateMin = try container.decodeIfPresent(Double.self, forKey: .heartRateMin)
        heartRateMax = try container.decodeIfPresent(Double.self, forKey: .heartRateMax)
        heartRateSamples = try container.decodeIfPresent([TimeSample].self, forKey: .heartRateSamples) ?? []
        hrvSamples = try container.decodeIfPresent([TimeSample].self, forKey: .hrvSamples) ?? []
    }
}

// MARK: - Vitals Data

struct VitalsData: Codable {
    // Respiratory Rate (daily aggregates)
    var respiratoryRateAvg: Double?
    var respiratoryRateMin: Double?
    var respiratoryRateMax: Double?

    // Blood Oxygen / SpO2 (daily aggregates)
    var bloodOxygenAvg: Double? // as percentage (0-1)
    var bloodOxygenMin: Double?
    var bloodOxygenMax: Double?

    // Body Temperature (daily aggregates)
    var bodyTemperatureAvg: Double? // in Celsius
    var bodyTemperatureMin: Double?
    var bodyTemperatureMax: Double?

    // Blood Pressure (daily aggregates)
    var bloodPressureSystolicAvg: Double?
    var bloodPressureSystolicMin: Double?
    var bloodPressureSystolicMax: Double?
    var bloodPressureDiastolicAvg: Double?
    var bloodPressureDiastolicMin: Double?
    var bloodPressureDiastolicMax: Double?

    // Blood Glucose (daily aggregates)
    var bloodGlucoseAvg: Double? // mg/dL
    var bloodGlucoseMin: Double?
    var bloodGlucoseMax: Double?

    // Granular time-series samples
    var bloodOxygenSamples: [TimeSample] = []
    var bloodGlucoseSamples: [TimeSample] = []
    var respiratoryRateSamples: [TimeSample] = []

    // Additional vitals
    var basalBodyTemperature: Double? // Celsius
    var wristTemperature: Double? // Celsius
    var electrodermalActivity: Double? // µS

    // Respiratory function tests
    var forcedVitalCapacity: Double? // liters
    var forcedExpiratoryVolume1: Double? // liters
    var peakExpiratoryFlowRate: Double? // L/min
    var inhalerUsage: Double? // count

    var hasData: Bool {
        respiratoryRateAvg != nil || bloodOxygenAvg != nil ||
        bodyTemperatureAvg != nil || bloodPressureSystolicAvg != nil ||
        bloodPressureDiastolicAvg != nil || bloodGlucoseAvg != nil ||
        basalBodyTemperature != nil || wristTemperature != nil ||
        electrodermalActivity != nil || forcedVitalCapacity != nil ||
        forcedExpiratoryVolume1 != nil || peakExpiratoryFlowRate != nil ||
        inhalerUsage != nil
    }

    // Convenience properties for backward compatibility / simple access
    var respiratoryRate: Double? { respiratoryRateAvg }
    var bloodOxygen: Double? { bloodOxygenAvg }
    var bodyTemperature: Double? { bodyTemperatureAvg }
    var bloodPressureSystolic: Double? { bloodPressureSystolicAvg }
    var bloodPressureDiastolic: Double? { bloodPressureDiastolicAvg }
    var bloodGlucose: Double? { bloodGlucoseAvg }

    enum CodingKeys: String, CodingKey {
        case respiratoryRateAvg, respiratoryRateMin, respiratoryRateMax
        case bloodOxygenAvg, bloodOxygenMin, bloodOxygenMax
        case bodyTemperatureAvg, bodyTemperatureMin, bodyTemperatureMax
        case bloodPressureSystolicAvg, bloodPressureSystolicMin, bloodPressureSystolicMax
        case bloodPressureDiastolicAvg, bloodPressureDiastolicMin, bloodPressureDiastolicMax
        case bloodGlucoseAvg, bloodGlucoseMin, bloodGlucoseMax
        case bloodOxygenSamples, bloodGlucoseSamples, respiratoryRateSamples
    }

    init(
        respiratoryRateAvg: Double? = nil, respiratoryRateMin: Double? = nil, respiratoryRateMax: Double? = nil,
        bloodOxygenAvg: Double? = nil, bloodOxygenMin: Double? = nil, bloodOxygenMax: Double? = nil,
        bodyTemperatureAvg: Double? = nil, bodyTemperatureMin: Double? = nil, bodyTemperatureMax: Double? = nil,
        bloodPressureSystolicAvg: Double? = nil, bloodPressureSystolicMin: Double? = nil, bloodPressureSystolicMax: Double? = nil,
        bloodPressureDiastolicAvg: Double? = nil, bloodPressureDiastolicMin: Double? = nil, bloodPressureDiastolicMax: Double? = nil,
        bloodGlucoseAvg: Double? = nil, bloodGlucoseMin: Double? = nil, bloodGlucoseMax: Double? = nil,
        bloodOxygenSamples: [TimeSample] = [], bloodGlucoseSamples: [TimeSample] = [], respiratoryRateSamples: [TimeSample] = []
    ) {
        self.respiratoryRateAvg = respiratoryRateAvg; self.respiratoryRateMin = respiratoryRateMin; self.respiratoryRateMax = respiratoryRateMax
        self.bloodOxygenAvg = bloodOxygenAvg; self.bloodOxygenMin = bloodOxygenMin; self.bloodOxygenMax = bloodOxygenMax
        self.bodyTemperatureAvg = bodyTemperatureAvg; self.bodyTemperatureMin = bodyTemperatureMin; self.bodyTemperatureMax = bodyTemperatureMax
        self.bloodPressureSystolicAvg = bloodPressureSystolicAvg; self.bloodPressureSystolicMin = bloodPressureSystolicMin; self.bloodPressureSystolicMax = bloodPressureSystolicMax
        self.bloodPressureDiastolicAvg = bloodPressureDiastolicAvg; self.bloodPressureDiastolicMin = bloodPressureDiastolicMin; self.bloodPressureDiastolicMax = bloodPressureDiastolicMax
        self.bloodGlucoseAvg = bloodGlucoseAvg; self.bloodGlucoseMin = bloodGlucoseMin; self.bloodGlucoseMax = bloodGlucoseMax
        self.bloodOxygenSamples = bloodOxygenSamples; self.bloodGlucoseSamples = bloodGlucoseSamples; self.respiratoryRateSamples = respiratoryRateSamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        respiratoryRateAvg = try container.decodeIfPresent(Double.self, forKey: .respiratoryRateAvg)
        respiratoryRateMin = try container.decodeIfPresent(Double.self, forKey: .respiratoryRateMin)
        respiratoryRateMax = try container.decodeIfPresent(Double.self, forKey: .respiratoryRateMax)
        bloodOxygenAvg = try container.decodeIfPresent(Double.self, forKey: .bloodOxygenAvg)
        bloodOxygenMin = try container.decodeIfPresent(Double.self, forKey: .bloodOxygenMin)
        bloodOxygenMax = try container.decodeIfPresent(Double.self, forKey: .bloodOxygenMax)
        bodyTemperatureAvg = try container.decodeIfPresent(Double.self, forKey: .bodyTemperatureAvg)
        bodyTemperatureMin = try container.decodeIfPresent(Double.self, forKey: .bodyTemperatureMin)
        bodyTemperatureMax = try container.decodeIfPresent(Double.self, forKey: .bodyTemperatureMax)
        bloodPressureSystolicAvg = try container.decodeIfPresent(Double.self, forKey: .bloodPressureSystolicAvg)
        bloodPressureSystolicMin = try container.decodeIfPresent(Double.self, forKey: .bloodPressureSystolicMin)
        bloodPressureSystolicMax = try container.decodeIfPresent(Double.self, forKey: .bloodPressureSystolicMax)
        bloodPressureDiastolicAvg = try container.decodeIfPresent(Double.self, forKey: .bloodPressureDiastolicAvg)
        bloodPressureDiastolicMin = try container.decodeIfPresent(Double.self, forKey: .bloodPressureDiastolicMin)
        bloodPressureDiastolicMax = try container.decodeIfPresent(Double.self, forKey: .bloodPressureDiastolicMax)
        bloodGlucoseAvg = try container.decodeIfPresent(Double.self, forKey: .bloodGlucoseAvg)
        bloodGlucoseMin = try container.decodeIfPresent(Double.self, forKey: .bloodGlucoseMin)
        bloodGlucoseMax = try container.decodeIfPresent(Double.self, forKey: .bloodGlucoseMax)
        bloodOxygenSamples = try container.decodeIfPresent([TimeSample].self, forKey: .bloodOxygenSamples) ?? []
        bloodGlucoseSamples = try container.decodeIfPresent([TimeSample].self, forKey: .bloodGlucoseSamples) ?? []
        respiratoryRateSamples = try container.decodeIfPresent([TimeSample].self, forKey: .respiratoryRateSamples) ?? []
    }
}

// MARK: - Body Data

struct BodyData: Codable {
    var weight: Double? // in kg
    var bodyFatPercentage: Double?
    var height: Double? // in meters
    var bmi: Double?
    var leanBodyMass: Double? // in kg
    var waistCircumference: Double? // in meters

    var hasData: Bool {
        weight != nil || bodyFatPercentage != nil || height != nil ||
        bmi != nil || leanBodyMass != nil || waistCircumference != nil
    }
}

// MARK: - Nutrition Data

struct NutritionData: Codable {
    var dietaryEnergy: Double? // kcal
    var protein: Double? // grams
    var carbohydrates: Double? // grams
    var fat: Double? // grams
    var fiber: Double? // grams
    var sugar: Double? // grams
    var sodium: Double? // mg
    var water: Double? // liters
    var caffeine: Double? // mg
    var cholesterol: Double? // mg
    var saturatedFat: Double? // grams
    var monounsaturatedFat: Double? // grams
    var polyunsaturatedFat: Double? // grams

    var hasData: Bool {
        dietaryEnergy != nil || protein != nil || carbohydrates != nil ||
        fat != nil || fiber != nil || sugar != nil || sodium != nil ||
        water != nil || caffeine != nil || cholesterol != nil || saturatedFat != nil ||
        monounsaturatedFat != nil || polyunsaturatedFat != nil
    }
}

// MARK: - Mindfulness Data

struct MindfulnessData: Codable {
    var mindfulMinutes: Double?
    var mindfulSessions: Int?
    var stateOfMind: [StateOfMindEntry] = []

    /// Export-only override used by metric-level filtering.
    ///
    /// Kept out of Codable so persisted/synced data remains unchanged.
    var isAverageValenceExportEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case mindfulMinutes
        case mindfulSessions
        case stateOfMind
    }

    init(
        mindfulMinutes: Double? = nil,
        mindfulSessions: Int? = nil,
        stateOfMind: [StateOfMindEntry] = [],
        isAverageValenceExportEnabled: Bool = true
    ) {
        self.mindfulMinutes = mindfulMinutes
        self.mindfulSessions = mindfulSessions
        self.stateOfMind = stateOfMind
        self.isAverageValenceExportEnabled = isAverageValenceExportEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mindfulMinutes = try container.decodeIfPresent(Double.self, forKey: .mindfulMinutes)
        mindfulSessions = try container.decodeIfPresent(Int.self, forKey: .mindfulSessions)
        stateOfMind = try container.decodeIfPresent([StateOfMindEntry].self, forKey: .stateOfMind) ?? []
        isAverageValenceExportEnabled = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mindfulMinutes, forKey: .mindfulMinutes)
        try container.encodeIfPresent(mindfulSessions, forKey: .mindfulSessions)
        try container.encode(stateOfMind, forKey: .stateOfMind)
    }

    var hasData: Bool {
        mindfulMinutes != nil || mindfulSessions != nil || !stateOfMind.isEmpty
    }
    
    // Computed properties for State of Mind analysis
    var dailyMoods: [StateOfMindEntry] {
        stateOfMind.filter { $0.kind == .dailyMood }
    }
    
    var momentaryEmotions: [StateOfMindEntry] {
        stateOfMind.filter { $0.kind == .momentaryEmotion }
    }
    
    var averageValence: Double? {
        guard isAverageValenceExportEnabled, !stateOfMind.isEmpty else { return nil }
        let total = stateOfMind.reduce(0.0) { $0 + $1.valence }
        return total / Double(stateOfMind.count)
    }
    
    var averageDailyMoodValence: Double? {
        guard !dailyMoods.isEmpty else { return nil }
        let total = dailyMoods.reduce(0.0) { $0 + $1.valence }
        return total / Double(dailyMoods.count)
    }
    
    var allLabels: [String] {
        Array(Set(stateOfMind.flatMap { $0.labels })).sorted()
    }
    
    var allAssociations: [String] {
        Array(Set(stateOfMind.flatMap { $0.associations })).sorted()
    }

    mutating func removeDailyMoodEntries() {
        stateOfMind.removeAll { $0.kind == .dailyMood }
    }

    mutating func removeMomentaryEmotionEntries() {
        stateOfMind.removeAll { $0.kind == .momentaryEmotion }
    }
}

// MARK: - State of Mind Entry

struct StateOfMindEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let kind: StateOfMindKind
    let valence: Double  // -1.0 (very unpleasant) to 1.0 (very pleasant)
    let labels: [String]  // Emotion/mood labels like "Happy", "Anxious", etc.
    let associations: [String]  // Context like "Work", "Exercise", "Family", etc.

    init(id: UUID = UUID(), timestamp: Date, kind: StateOfMindKind, valence: Double, labels: [String], associations: [String]) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.valence = valence
        self.labels = labels
        self.associations = associations
    }

    enum StateOfMindKind: String, Codable {
        case momentaryEmotion = "Momentary Emotion"
        case dailyMood = "Daily Mood"
    }
    
    /// Converts valence (-1 to 1) to a human-readable description
    var valenceDescription: String {
        switch valence {
        case -1.0 ..< -0.6:
            return "Very Unpleasant"
        case -0.6 ..< -0.2:
            return "Unpleasant"
        case -0.2 ..< 0.2:
            return "Neutral"
        case 0.2 ..< 0.6:
            return "Pleasant"
        case 0.6 ... 1.0:
            return "Very Pleasant"
        default:
            return "Unknown"
        }
    }
    
    /// Converts valence to a percentage (0-100)
    var valencePercent: Int {
        Int(((valence + 1.0) / 2.0) * 100)
    }
    
    /// Returns an emoji representation of the valence
    var valenceEmoji: String {
        switch valence {
        case -1.0 ..< -0.6:
            return "😢"
        case -0.6 ..< -0.2:
            return "😔"
        case -0.2 ..< 0.2:
            return "😐"
        case 0.2 ..< 0.6:
            return "🙂"
        case 0.6 ... 1.0:
            return "😊"
        default:
            return "❓"
        }
    }
}

// MARK: - Mobility Data

struct MobilityData: Codable {
    var walkingSpeed: Double? // m/s
    var walkingStepLength: Double? // meters
    var walkingDoubleSupportPercentage: Double?
    var walkingAsymmetryPercentage: Double?
    var stairAscentSpeed: Double? // m/s
    var stairDescentSpeed: Double? // m/s
    var sixMinuteWalkDistance: Double? // meters
    var walkingSteadiness: Double? // percentage (0-1)
    var runningSpeed: Double? // m/s
    var runningStrideLength: Double? // meters
    var runningGroundContactTime: Double? // milliseconds
    var runningVerticalOscillation: Double? // centimeters
    var runningPower: Double? // watts

    var hasData: Bool {
        walkingSpeed != nil || walkingStepLength != nil ||
        walkingDoubleSupportPercentage != nil || walkingAsymmetryPercentage != nil ||
        stairAscentSpeed != nil || stairDescentSpeed != nil || sixMinuteWalkDistance != nil ||
        walkingSteadiness != nil || runningSpeed != nil || runningStrideLength != nil ||
        runningGroundContactTime != nil || runningVerticalOscillation != nil || runningPower != nil
    }
}

// MARK: - Hearing Data

struct HearingData: Codable {
    var headphoneAudioLevel: Double? // dB
    var environmentalSoundLevel: Double? // dB

    var hasData: Bool {
        headphoneAudioLevel != nil || environmentalSoundLevel != nil
    }
}

// MARK: - Cycling Performance Data

struct CyclingPerformanceData: Codable {
    var cyclingSpeed: Double? // m/s
    var cyclingPower: Double? // watts
    var cyclingCadence: Double? // rpm
    var cyclingFTP: Double? // watts

    var hasData: Bool {
        cyclingSpeed != nil || cyclingPower != nil ||
        cyclingCadence != nil || cyclingFTP != nil
    }
}

// MARK: - Vitamins Data

struct VitaminsData: Codable {
    var vitaminA: Double? // µg
    var vitaminB6: Double? // mg
    var vitaminB12: Double? // µg
    var vitaminC: Double? // mg
    var vitaminD: Double? // µg
    var vitaminE: Double? // mg
    var vitaminK: Double? // µg
    var thiamin: Double? // mg
    var riboflavin: Double? // mg
    var niacin: Double? // mg
    var folate: Double? // µg
    var biotin: Double? // µg
    var pantothenicAcid: Double? // mg

    var hasData: Bool {
        vitaminA != nil || vitaminB6 != nil || vitaminB12 != nil ||
        vitaminC != nil || vitaminD != nil || vitaminE != nil ||
        vitaminK != nil || thiamin != nil || riboflavin != nil ||
        niacin != nil || folate != nil || biotin != nil || pantothenicAcid != nil
    }
}

// MARK: - Minerals Data

struct MineralsData: Codable {
    var calcium: Double? // mg
    var iron: Double? // mg
    var potassium: Double? // mg
    var magnesium: Double? // mg
    var phosphorus: Double? // mg
    var zinc: Double? // mg
    var selenium: Double? // µg
    var copper: Double? // mg
    var manganese: Double? // mg
    var chromium: Double? // µg
    var molybdenum: Double? // µg
    var chloride: Double? // mg
    var iodine: Double? // µg

    var hasData: Bool {
        calcium != nil || iron != nil || potassium != nil || magnesium != nil ||
        phosphorus != nil || zinc != nil || selenium != nil || copper != nil ||
        manganese != nil || chromium != nil || molybdenum != nil ||
        chloride != nil || iodine != nil
    }
}

// MARK: - Symptoms Data

struct SymptomsData: Codable {
    /// Symptom metric ID → count of occurrences for the day.
    /// Keys match HealthMetrics IDs (e.g., "symptom_headache", "symptom_fatigue").
    var counts: [String: Int] = [:]

    var hasData: Bool { !counts.isEmpty }
}

// MARK: - Other Health Data

struct OtherHealthData: Codable {
    var uvExposure: Double?
    var timeInDaylight: Double? // minutes
    var numberOfFalls: Double?
    var bloodAlcoholContent: Double? // percentage
    var alcoholicBeverages: Double? // count
    var insulinDelivery: Double? // IU
    var toothbrushingCount: Int?
    var handwashingCount: Int?
    var waterTemperature: Double? // Celsius
    var underwaterDepth: Double? // meters

    var hasData: Bool {
        uvExposure != nil || timeInDaylight != nil || numberOfFalls != nil ||
        bloodAlcoholContent != nil || alcoholicBeverages != nil ||
        insulinDelivery != nil || toothbrushingCount != nil ||
        handwashingCount != nil || waterTemperature != nil || underwaterDepth != nil
    }
}

// MARK: - Reproductive Health Data

struct ReproductiveHealthData: Codable {
    var menstrualFlow: String? // "none", "light", "medium", "heavy", "unspecified"
    var sexualActivityCount: Int?
    var ovulationTestResult: String? // "negative", "positive", "indeterminate", "estrogen_surge"
    var cervicalMucusQuality: String? // "dry", "sticky", "creamy", "watery", "egg_white"
    var intermenstrualBleedingCount: Int?

    var hasData: Bool {
        menstrualFlow != nil || sexualActivityCount != nil ||
        ovulationTestResult != nil || cervicalMucusQuality != nil ||
        intermenstrualBleedingCount != nil
    }
}

// MARK: - Workout Type (Platform-Agnostic)

enum WorkoutType: String, Codable, CaseIterable {
    case running
    case walking
    case cycling
    case swimming
    case hiking
    case yoga
    case functionalStrengthTraining
    case traditionalStrengthTraining
    case coreTraining
    case highIntensityIntervalTraining
    case elliptical
    case rowing
    case stairClimbing
    case pilates
    case dance
    case cooldown
    case mixedCardio
    case socialDance
    case pickleball
    case tennis
    case badminton
    case tableTennis
    case golf
    case soccer
    case basketball
    case baseball
    case softball
    case volleyball
    case americanFootball
    case rugby
    case hockey
    case lacrosse
    case skatingSports
    case snowSports
    case waterSports
    case martialArts
    case boxing
    case kickboxing
    case wrestling
    case climbing
    case jumpRope
    case mindAndBody
    case flexibility
    case other

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .coreTraining: return "Core Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .mixedCardio: return "Mixed Cardio"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .tennis: return "Tennis"
        case .badminton: return "Badminton"
        case .tableTennis: return "Table Tennis"
        case .golf: return "Golf"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .baseball: return "Baseball"
        case .softball: return "Softball"
        case .volleyball: return "Volleyball"
        case .americanFootball: return "American Football"
        case .rugby: return "Rugby"
        case .hockey: return "Hockey"
        case .lacrosse: return "Lacrosse"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .waterSports: return "Water Sports"
        case .martialArts: return "Martial Arts"
        case .boxing: return "Boxing"
        case .kickboxing: return "Kickboxing"
        case .wrestling: return "Wrestling"
        case .climbing: return "Climbing"
        case .jumpRope: return "Jump Rope"
        case .mindAndBody: return "Mind & Body"
        case .flexibility: return "Flexibility"
        case .other: return "Other"
        }
    }
}

// MARK: - Workout Data

struct WorkoutData: Identifiable, Codable {
    let id: UUID
    let workoutType: WorkoutType
    let startTime: Date
    let duration: TimeInterval
    let calories: Double?
    let distance: Double? // in meters
    let avgHeartRate: Double? // bpm
    let maxHeartRate: Double? // bpm
    let minHeartRate: Double? // bpm
    let avgRunningCadence: Double?      // steps per minute
    let avgStrideLength: Double?         // meters
    let avgGroundContactTime: Double?    // milliseconds
    let avgVerticalOscillation: Double?  // centimeters
    let avgCyclingCadence: Double?       // revolutions per minute
    let avgPower: Double?                // watts
    let maxPower: Double?                // watts

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType,
        startTime: Date,
        duration: TimeInterval,
        calories: Double?,
        distance: Double?,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        minHeartRate: Double? = nil,
        avgRunningCadence: Double? = nil,
        avgStrideLength: Double? = nil,
        avgGroundContactTime: Double? = nil,
        avgVerticalOscillation: Double? = nil,
        avgCyclingCadence: Double? = nil,
        avgPower: Double? = nil,
        maxPower: Double? = nil
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startTime = startTime
        self.duration = duration
        self.calories = calories
        self.distance = distance
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.avgRunningCadence = avgRunningCadence
        self.avgStrideLength = avgStrideLength
        self.avgGroundContactTime = avgGroundContactTime
        self.avgVerticalOscillation = avgVerticalOscillation
        self.avgCyclingCadence = avgCyclingCadence
        self.avgPower = avgPower
        self.maxPower = maxPower
    }

    var workoutTypeName: String {
        workoutType.displayName
    }

    /// Picks the right rate format for this workout type:
    /// speed (km/h) for cycling/skating/snow/water, swim pace (/100m) for
    /// swimming, otherwise pace (/km). Returns the user-facing label and the
    /// formatted value, or nil if distance/duration aren't suitable.
    func paceOrSpeed(using converter: UnitConverter) -> (label: String, value: String)? {
        guard let distance = distance, distance > 0, duration > 0 else { return nil }
        switch workoutType {
        case .swimming:
            guard let v = converter.formatSwimPace(meters: distance, duration: duration) else { return nil }
            return ("Avg Pace", v)
        case .cycling, .skatingSports, .snowSports, .waterSports:
            guard let v = converter.formatSpeed(meters: distance, duration: duration) else { return nil }
            return ("Avg Speed", v)
        default:
            guard let v = converter.formatPace(meters: distance, duration: duration) else { return nil }
            return ("Avg Pace", v)
        }
    }
}

// MARK: - Complete Health Data

struct HealthData: Codable {
    let date: Date
    var sleep: SleepData = SleepData()
    var activity: ActivityData = ActivityData()
    var heart: HeartData = HeartData()
    var vitals: VitalsData = VitalsData()
    var body: BodyData = BodyData()
    var nutrition: NutritionData = NutritionData()
    var mindfulness: MindfulnessData = MindfulnessData()
    var mobility: MobilityData = MobilityData()
    var hearing: HearingData = HearingData()
    var reproductiveHealth: ReproductiveHealthData = ReproductiveHealthData()
    var cyclingPerformance: CyclingPerformanceData = CyclingPerformanceData()
    var vitamins: VitaminsData = VitaminsData()
    var minerals: MineralsData = MineralsData()
    var symptoms: SymptomsData = SymptomsData()
    var other: OtherHealthData = OtherHealthData()
    var workouts: [WorkoutData] = []

    var hasAnyData: Bool {
        sleep.hasData || activity.hasData || heart.hasData || vitals.hasData ||
        body.hasData || nutrition.hasData || mindfulness.hasData ||
        mobility.hasData || hearing.hasData || reproductiveHealth.hasData ||
        cyclingPerformance.hasData || vitamins.hasData || minerals.hasData ||
        symptoms.hasData || other.hasData || !workouts.isEmpty
    }
}

// MARK: - Export Formats

extension HealthData {
    func export(format: ExportFormat, settings: AdvancedExportSettings) -> String {
        let filteredData = self.filtered(by: settings.metricSelection)
        let formatCustomization = settings.formatCustomization

        switch format {
        case .markdown:
            return filteredData.toMarkdown(
                includeMetadata: settings.includeMetadata,
                groupByCategory: settings.groupByCategory,
                customization: formatCustomization
            )
        case .obsidianBases:
            return filteredData.toObsidianBases(customization: formatCustomization)
        case .json:
            return filteredData.toJSON(customization: formatCustomization)
        case .csv:
            return filteredData.toCSV(customization: formatCustomization)
        }
    }

    func filtered(by metricSelection: MetricSelectionState) -> HealthData {
        var filtered = self

        let enabledKeys = HealthMetricExportMapping.enabledFrontmatterKeySet(in: metricSelection)
        let disabledKeys = HealthMetricExportMapping.allKnownFrontmatterKeys
            .subtracting(enabledKeys)
            .sorted()

        for key in disabledKeys {
            filtered.removeExportField(for: key)
        }

        return filtered
    }

    /// Legacy category-level filtering retained only for backwards compatibility.
    /// Runtime export filtering now uses metricSelection exclusively.
    func filtered(by dataTypes: DataTypeSelection) -> HealthData {
        var filtered = self

        if !dataTypes.sleep {
            filtered.sleep = SleepData()
        }
        if !dataTypes.activity {
            filtered.activity = ActivityData()
        }
        if !dataTypes.heart {
            filtered.heart = HeartData()
        }
        if !dataTypes.vitals {
            filtered.vitals = VitalsData()
        }
        if !dataTypes.body {
            filtered.body = BodyData()
        }
        if !dataTypes.nutrition {
            filtered.nutrition = NutritionData()
        }
        if !dataTypes.mindfulness {
            filtered.mindfulness = MindfulnessData()
        }
        if !dataTypes.mobility {
            filtered.mobility = MobilityData()
        }
        if !dataTypes.hearing {
            filtered.hearing = HearingData()
        }
        if !dataTypes.reproductiveHealth {
            filtered.reproductiveHealth = ReproductiveHealthData()
        }
        // New categories always pass through in legacy filtering —
        // granular control is via metricSelection
        if !dataTypes.workouts {
            filtered.workouts = []
        }

        return filtered
    }

    private mutating func removeExportField(for frontmatterKey: String) {
        switch frontmatterKey {
        // Sleep
        case "sleep_total_hours": sleep.totalDuration = 0
        case "sleep_bedtime": sleep.sessionStart = nil
        case "sleep_wake": sleep.sessionEnd = nil
        case "sleep_deep_hours": sleep.deepSleep = 0
        case "sleep_rem_hours": sleep.remSleep = 0
        case "sleep_core_hours": sleep.coreSleep = 0
        case "sleep_awake_hours": sleep.awakeTime = 0
        case "sleep_in_bed_hours": sleep.inBedTime = 0

        // Activity
        case "steps": activity.steps = nil
        case "active_calories": activity.activeCalories = nil
        case "basal_calories": activity.basalEnergyBurned = nil
        case "exercise_minutes": activity.exerciseMinutes = nil
        case "stand_hours": activity.standHours = nil
        case "flights_climbed": activity.flightsClimbed = nil
        case "walking_running_km": activity.walkingRunningDistance = nil
        case "cycling_km": activity.cyclingDistance = nil
        case "swimming_m": activity.swimmingDistance = nil
        case "swimming_strokes": activity.swimmingStrokes = nil
        case "wheelchair_pushes": activity.pushCount = nil
        case "vo2_max": activity.vo2Max = nil
        case "wheelchair_km": activity.wheelchairDistance = nil
        case "downhill_snow_km": activity.downhillSnowSportsDistance = nil
        case "move_minutes": activity.moveTime = nil
        case "physical_effort": activity.physicalEffort = nil

        // Heart
        case "resting_heart_rate": heart.restingHeartRate = nil
        case "walking_heart_rate": heart.walkingHeartRateAverage = nil
        case "average_heart_rate": heart.averageHeartRate = nil
        case "heart_rate_min": heart.heartRateMin = nil
        case "heart_rate_max": heart.heartRateMax = nil
        case "hrv_ms": heart.hrv = nil
        case "heart_rate_recovery": heart.heartRateRecovery = nil
        case "afib_burden_percent": heart.atrialFibrillationBurden = nil

        // Respiratory + Vitals
        case "respiratory_rate", "respiratory_rate_avg", "respiratory_rate_min", "respiratory_rate_max":
            vitals.respiratoryRateAvg = nil
            vitals.respiratoryRateMin = nil
            vitals.respiratoryRateMax = nil

        case "blood_oxygen", "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max":
            vitals.bloodOxygenAvg = nil
            vitals.bloodOxygenMin = nil
            vitals.bloodOxygenMax = nil

        case "body_temperature", "body_temperature_avg", "body_temperature_min", "body_temperature_max":
            vitals.bodyTemperatureAvg = nil
            vitals.bodyTemperatureMin = nil
            vitals.bodyTemperatureMax = nil

        case "blood_pressure_systolic", "blood_pressure_systolic_avg", "blood_pressure_systolic_min", "blood_pressure_systolic_max":
            vitals.bloodPressureSystolicAvg = nil
            vitals.bloodPressureSystolicMin = nil
            vitals.bloodPressureSystolicMax = nil

        case "blood_pressure_diastolic", "blood_pressure_diastolic_avg", "blood_pressure_diastolic_min", "blood_pressure_diastolic_max":
            vitals.bloodPressureDiastolicAvg = nil
            vitals.bloodPressureDiastolicMin = nil
            vitals.bloodPressureDiastolicMax = nil

        case "blood_glucose", "blood_glucose_avg", "blood_glucose_min", "blood_glucose_max":
            vitals.bloodGlucoseAvg = nil
            vitals.bloodGlucoseMin = nil
            vitals.bloodGlucoseMax = nil
        case "basal_body_temperature": vitals.basalBodyTemperature = nil
        case "wrist_temperature": vitals.wristTemperature = nil
        case "electrodermal_activity": vitals.electrodermalActivity = nil
        case "forced_vital_capacity_l": vitals.forcedVitalCapacity = nil
        case "fev1_l": vitals.forcedExpiratoryVolume1 = nil
        case "peak_expiratory_flow": vitals.peakExpiratoryFlowRate = nil
        case "inhaler_usage": vitals.inhalerUsage = nil

        // Body
        case "weight_kg": body.weight = nil
        case "height_m": body.height = nil
        case "bmi": body.bmi = nil
        case "body_fat_percent": body.bodyFatPercentage = nil
        case "lean_body_mass_kg": body.leanBodyMass = nil
        case "waist_circumference_cm": body.waistCircumference = nil

        // Nutrition
        case "dietary_calories": nutrition.dietaryEnergy = nil
        case "protein_g": nutrition.protein = nil
        case "carbohydrates_g": nutrition.carbohydrates = nil
        case "fat_g": nutrition.fat = nil
        case "saturated_fat_g": nutrition.saturatedFat = nil
        case "fiber_g": nutrition.fiber = nil
        case "sugar_g": nutrition.sugar = nil
        case "sodium_mg": nutrition.sodium = nil
        case "cholesterol_mg": nutrition.cholesterol = nil
        case "water_l": nutrition.water = nil
        case "caffeine_mg": nutrition.caffeine = nil
        case "monounsaturated_fat_g": nutrition.monounsaturatedFat = nil
        case "polyunsaturated_fat_g": nutrition.polyunsaturatedFat = nil

        // Mindfulness
        case "mindful_minutes": mindfulness.mindfulMinutes = nil
        case "mindful_sessions": mindfulness.mindfulSessions = nil
        case "daily_mood_count", "daily_mood_percent": mindfulness.removeDailyMoodEntries()
        case "momentary_emotion_count": mindfulness.removeMomentaryEmotionEntries()
        case "average_mood_valence", "average_mood_percent": mindfulness.isAverageValenceExportEnabled = false

        // Mobility
        case "walking_speed": mobility.walkingSpeed = nil
        case "step_length_cm": mobility.walkingStepLength = nil
        case "double_support_percent": mobility.walkingDoubleSupportPercentage = nil
        case "walking_asymmetry_percent": mobility.walkingAsymmetryPercentage = nil
        case "stair_ascent_speed": mobility.stairAscentSpeed = nil
        case "stair_descent_speed": mobility.stairDescentSpeed = nil
        case "six_min_walk_m": mobility.sixMinuteWalkDistance = nil
        case "walking_steadiness_percent": mobility.walkingSteadiness = nil
        case "running_speed": mobility.runningSpeed = nil
        case "running_stride_length_m": mobility.runningStrideLength = nil
        case "running_ground_contact_ms": mobility.runningGroundContactTime = nil
        case "running_vertical_oscillation_cm": mobility.runningVerticalOscillation = nil
        case "running_power_w": mobility.runningPower = nil

        // Hearing
        case "headphone_audio_db": hearing.headphoneAudioLevel = nil
        case "environmental_sound_db": hearing.environmentalSoundLevel = nil

        // Reproductive Health
        case "menstrual_flow": reproductiveHealth.menstrualFlow = nil
        case "sexual_activity": reproductiveHealth.sexualActivityCount = nil
        case "ovulation_test": reproductiveHealth.ovulationTestResult = nil
        case "cervical_mucus": reproductiveHealth.cervicalMucusQuality = nil
        case "intermenstrual_bleeding": reproductiveHealth.intermenstrualBleedingCount = nil

        // Cycling Performance
        case "cycling_speed": cyclingPerformance.cyclingSpeed = nil
        case "cycling_power_w": cyclingPerformance.cyclingPower = nil
        case "cycling_cadence_rpm": cyclingPerformance.cyclingCadence = nil
        case "cycling_ftp_w": cyclingPerformance.cyclingFTP = nil

        // Vitamins
        case "vitamin_a_ug": vitamins.vitaminA = nil
        case "vitamin_b6_mg": vitamins.vitaminB6 = nil
        case "vitamin_b12_ug": vitamins.vitaminB12 = nil
        case "vitamin_c_mg": vitamins.vitaminC = nil
        case "vitamin_d_ug": vitamins.vitaminD = nil
        case "vitamin_e_mg": vitamins.vitaminE = nil
        case "vitamin_k_ug": vitamins.vitaminK = nil
        case "thiamin_mg": vitamins.thiamin = nil
        case "riboflavin_mg": vitamins.riboflavin = nil
        case "niacin_mg": vitamins.niacin = nil
        case "folate_ug": vitamins.folate = nil
        case "biotin_ug": vitamins.biotin = nil
        case "pantothenic_acid_mg": vitamins.pantothenicAcid = nil

        // Minerals
        case "calcium_mg": minerals.calcium = nil
        case "iron_mg": minerals.iron = nil
        case "potassium_mg": minerals.potassium = nil
        case "magnesium_mg": minerals.magnesium = nil
        case "phosphorus_mg": minerals.phosphorus = nil
        case "zinc_mg": minerals.zinc = nil
        case "selenium_ug": minerals.selenium = nil
        case "copper_mg": minerals.copper = nil
        case "manganese_mg": minerals.manganese = nil
        case "chromium_ug": minerals.chromium = nil
        case "molybdenum_ug": minerals.molybdenum = nil
        case "chloride_mg": minerals.chloride = nil
        case "iodine_ug": minerals.iodine = nil

        // Symptoms
        case let key where key.hasPrefix("symptom_"):
            symptoms.counts.removeValue(forKey: key)

        // Other
        case "uv_exposure": other.uvExposure = nil
        case "time_in_daylight_min": other.timeInDaylight = nil
        case "number_of_falls": other.numberOfFalls = nil
        case "blood_alcohol_percent": other.bloodAlcoholContent = nil
        case "alcoholic_beverages": other.alcoholicBeverages = nil
        case "insulin_delivery_iu": other.insulinDelivery = nil
        case "toothbrushing": other.toothbrushingCount = nil
        case "handwashing": other.handwashingCount = nil
        case "water_temperature": other.waterTemperature = nil
        case "underwater_depth_m": other.underwaterDepth = nil

        // Workouts
        case "workout_count", "workout_minutes", "workout_calories", "workout_distance_km", "workouts":
            workouts = []

        default:
            break
        }
    }
}
