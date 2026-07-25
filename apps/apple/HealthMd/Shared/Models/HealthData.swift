import Foundation

// MARK: - Time-Series Sample Types

/// A single timestamped numeric reading (e.g., one heart rate measurement).
nonisolated struct TimeSample: Codable, Sendable {
    let timestamp: Date
    let value: Double
    let metadata: [String: String]

    init(timestamp: Date, value: Double, metadata: [String: String] = [:]) {
        self.timestamp = timestamp
        self.value = value
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        value = try container.decode(Double.self, forKey: .value)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

/// One complete blood pressure measurement. HealthKit stores systolic and
/// diastolic quantities together in a blood pressure correlation, and Health.md
/// preserves that pairing for time-series export.
nonisolated struct BloodPressureSample: Codable, Sendable, Equatable {
    let correlationUUID: UUID?
    let systolic: Double
    let diastolic: Double
    let startDate: Date
    let endDate: Date
    let sourceRevision: HealthKitSourceRevision?
    let device: HealthKitDeviceProvenance?
    let metadata: [String: String]

    init(
        correlationUUID: UUID? = nil,
        systolic: Double,
        diastolic: Double,
        startDate: Date,
        endDate: Date,
        sourceRevision: HealthKitSourceRevision? = nil,
        device: HealthKitDeviceProvenance? = nil,
        metadata: [String: String] = [:]
    ) {
        self.correlationUUID = correlationUUID
        self.systolic = systolic
        self.diastolic = diastolic
        self.startDate = startDate
        self.endDate = endDate
        self.sourceRevision = sourceRevision
        self.device = device
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correlationUUID = try container.decodeIfPresent(UUID.self, forKey: .correlationUUID)
        systolic = try container.decode(Double.self, forKey: .systolic)
        diastolic = try container.decode(Double.self, forKey: .diastolic)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        sourceRevision = try container.decodeIfPresent(HealthKitSourceRevision.self, forKey: .sourceRevision)
        device = try container.decodeIfPresent(HealthKitDeviceProvenance.self, forKey: .device)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

/// A sleep stage interval with start/end times.
nonisolated struct SleepStageSample: Codable, Sendable {
    /// One of: "deep", "rem", "core", "awake", "inBed", "unspecified"
    let stage: String
    let startDate: Date
    let endDate: Date
    let metadata: [String: String]

    init(stage: String, startDate: Date, endDate: Date, metadata: [String: String] = [:]) {
        self.stage = stage
        self.startDate = startDate
        self.endDate = endDate
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stage = try container.decode(String.self, forKey: .stage)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

// MARK: - Sleep Data

nonisolated struct SleepData: Codable, Sendable {
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

nonisolated struct ActivityData: Codable, Sendable {
    var steps: Int?
    var activeCalories: Double?
    var exerciseMinutes: Double?
    var flightsClimbed: Int?
    var walkingRunningDistance: Double? // in meters
    var standTimeMinutes: Double?
    var standHours: Int?
    var basalEnergyBurned: Double?
    var cyclingDistance: Double? // in meters
    var swimmingDistance: Double? // in meters
    var swimmingStrokes: Int?
    var pushCount: Int? // wheelchair users
    var vo2Max: Double? // mL/kg/min (Cardio Fitness)
    /// Provenance for the source VO2 Max sample. Historical carry-forward is
    /// useful, but must never look like a measurement made on the export day.
    var vo2MaxSourceUUID: UUID?
    var vo2MaxSourceStartDate: Date?
    var vo2MaxSourceEndDate: Date?
    var vo2MaxCarriedForward: Bool?
    /// Age at the start of the exported calendar day. In-day samples are zero.
    var vo2MaxAgeSeconds: TimeInterval?
    var wheelchairDistance: Double? // in meters
    var downhillSnowSportsDistance: Double? // in meters
    var moveTime: Double? // in minutes
    var physicalEffort: Double? // kcal/hr/kg

    var hasData: Bool {
        steps != nil || activeCalories != nil || exerciseMinutes != nil ||
        flightsClimbed != nil || walkingRunningDistance != nil ||
        standTimeMinutes != nil || standHours != nil || basalEnergyBurned != nil ||
        cyclingDistance != nil || swimmingDistance != nil ||
        swimmingStrokes != nil || pushCount != nil || vo2Max != nil ||
        wheelchairDistance != nil || downhillSnowSportsDistance != nil ||
        moveTime != nil || physicalEffort != nil
    }
}

// MARK: - Heart Data

nonisolated struct HeartData: Codable, Sendable {
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
        case heartRateRecovery, atrialFibrillationBurden
    }

    init(
        restingHeartRate: Double? = nil, walkingHeartRateAverage: Double? = nil,
        averageHeartRate: Double? = nil, hrv: Double? = nil,
        heartRateMin: Double? = nil, heartRateMax: Double? = nil,
        heartRateSamples: [TimeSample] = [], hrvSamples: [TimeSample] = [],
        heartRateRecovery: Double? = nil, atrialFibrillationBurden: Double? = nil
    ) {
        self.restingHeartRate = restingHeartRate
        self.walkingHeartRateAverage = walkingHeartRateAverage
        self.averageHeartRate = averageHeartRate
        self.hrv = hrv
        self.heartRateMin = heartRateMin
        self.heartRateMax = heartRateMax
        self.heartRateSamples = heartRateSamples
        self.hrvSamples = hrvSamples
        self.heartRateRecovery = heartRateRecovery
        self.atrialFibrillationBurden = atrialFibrillationBurden
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
        heartRateRecovery = try container.decodeIfPresent(Double.self, forKey: .heartRateRecovery)
        atrialFibrillationBurden = try container.decodeIfPresent(Double.self, forKey: .atrialFibrillationBurden)
    }
}

// MARK: - Vitals Data

nonisolated struct VitalsData: Codable, Sendable {
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
    var bloodPressureSamples: [BloodPressureSample] = []

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
        inhalerUsage != nil || !bloodPressureSamples.isEmpty
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
        case bloodOxygenSamples, bloodGlucoseSamples, respiratoryRateSamples, bloodPressureSamples
        case basalBodyTemperature, wristTemperature, electrodermalActivity
        case forcedVitalCapacity, forcedExpiratoryVolume1, peakExpiratoryFlowRate, inhalerUsage
    }

    init(
        respiratoryRateAvg: Double? = nil, respiratoryRateMin: Double? = nil, respiratoryRateMax: Double? = nil,
        bloodOxygenAvg: Double? = nil, bloodOxygenMin: Double? = nil, bloodOxygenMax: Double? = nil,
        bodyTemperatureAvg: Double? = nil, bodyTemperatureMin: Double? = nil, bodyTemperatureMax: Double? = nil,
        bloodPressureSystolicAvg: Double? = nil, bloodPressureSystolicMin: Double? = nil, bloodPressureSystolicMax: Double? = nil,
        bloodPressureDiastolicAvg: Double? = nil, bloodPressureDiastolicMin: Double? = nil, bloodPressureDiastolicMax: Double? = nil,
        bloodGlucoseAvg: Double? = nil, bloodGlucoseMin: Double? = nil, bloodGlucoseMax: Double? = nil,
        bloodOxygenSamples: [TimeSample] = [], bloodGlucoseSamples: [TimeSample] = [], respiratoryRateSamples: [TimeSample] = [],
        bloodPressureSamples: [BloodPressureSample] = [],
        basalBodyTemperature: Double? = nil, wristTemperature: Double? = nil, electrodermalActivity: Double? = nil,
        forcedVitalCapacity: Double? = nil, forcedExpiratoryVolume1: Double? = nil,
        peakExpiratoryFlowRate: Double? = nil, inhalerUsage: Double? = nil
    ) {
        self.respiratoryRateAvg = respiratoryRateAvg; self.respiratoryRateMin = respiratoryRateMin; self.respiratoryRateMax = respiratoryRateMax
        self.bloodOxygenAvg = bloodOxygenAvg; self.bloodOxygenMin = bloodOxygenMin; self.bloodOxygenMax = bloodOxygenMax
        self.bodyTemperatureAvg = bodyTemperatureAvg; self.bodyTemperatureMin = bodyTemperatureMin; self.bodyTemperatureMax = bodyTemperatureMax
        self.bloodPressureSystolicAvg = bloodPressureSystolicAvg; self.bloodPressureSystolicMin = bloodPressureSystolicMin; self.bloodPressureSystolicMax = bloodPressureSystolicMax
        self.bloodPressureDiastolicAvg = bloodPressureDiastolicAvg; self.bloodPressureDiastolicMin = bloodPressureDiastolicMin; self.bloodPressureDiastolicMax = bloodPressureDiastolicMax
        self.bloodGlucoseAvg = bloodGlucoseAvg; self.bloodGlucoseMin = bloodGlucoseMin; self.bloodGlucoseMax = bloodGlucoseMax
        self.bloodOxygenSamples = bloodOxygenSamples; self.bloodGlucoseSamples = bloodGlucoseSamples; self.respiratoryRateSamples = respiratoryRateSamples
        self.bloodPressureSamples = bloodPressureSamples
        self.basalBodyTemperature = basalBodyTemperature; self.wristTemperature = wristTemperature; self.electrodermalActivity = electrodermalActivity
        self.forcedVitalCapacity = forcedVitalCapacity; self.forcedExpiratoryVolume1 = forcedExpiratoryVolume1
        self.peakExpiratoryFlowRate = peakExpiratoryFlowRate; self.inhalerUsage = inhalerUsage
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
        bloodPressureSamples = try container.decodeIfPresent([BloodPressureSample].self, forKey: .bloodPressureSamples) ?? []
        basalBodyTemperature = try container.decodeIfPresent(Double.self, forKey: .basalBodyTemperature)
        wristTemperature = try container.decodeIfPresent(Double.self, forKey: .wristTemperature)
        electrodermalActivity = try container.decodeIfPresent(Double.self, forKey: .electrodermalActivity)
        forcedVitalCapacity = try container.decodeIfPresent(Double.self, forKey: .forcedVitalCapacity)
        forcedExpiratoryVolume1 = try container.decodeIfPresent(Double.self, forKey: .forcedExpiratoryVolume1)
        peakExpiratoryFlowRate = try container.decodeIfPresent(Double.self, forKey: .peakExpiratoryFlowRate)
        inhalerUsage = try container.decodeIfPresent(Double.self, forKey: .inhalerUsage)
    }
}

// MARK: - Body Data

nonisolated struct BodyData: Codable, Sendable {
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

nonisolated struct NutritionData: Codable, Sendable {
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

nonisolated struct MindfulnessData: Codable, Sendable {
    var mindfulMinutes: Double?
    var mindfulSessions: Int?
    var stateOfMind: [StateOfMindEntry] = []

    /// Export-only view controls used by metric-level filtering.
    ///
    /// `stateOfMind` remains the immutable source population for the lifetime of
    /// an export. Each public State of Mind metric is an independent view over
    /// that population, so disabling one view never changes another view's
    /// entries or average. These controls stay out of Codable so persisted and
    /// synced source data remains unchanged.
    var isStateOfMindEntriesExportEnabled: Bool = true
    var isDailyMoodExportEnabled: Bool = true
    var isMomentaryEmotionExportEnabled: Bool = true
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
        isStateOfMindEntriesExportEnabled: Bool = true,
        isDailyMoodExportEnabled: Bool = true,
        isMomentaryEmotionExportEnabled: Bool = true,
        isAverageValenceExportEnabled: Bool = true
    ) {
        self.mindfulMinutes = mindfulMinutes
        self.mindfulSessions = mindfulSessions
        self.stateOfMind = stateOfMind
        self.isStateOfMindEntriesExportEnabled = isStateOfMindEntriesExportEnabled
        self.isDailyMoodExportEnabled = isDailyMoodExportEnabled
        self.isMomentaryEmotionExportEnabled = isMomentaryEmotionExportEnabled
        self.isAverageValenceExportEnabled = isAverageValenceExportEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mindfulMinutes = try container.decodeIfPresent(Double.self, forKey: .mindfulMinutes)
        mindfulSessions = try container.decodeIfPresent(Int.self, forKey: .mindfulSessions)
        stateOfMind = try container.decodeIfPresent([StateOfMindEntry].self, forKey: .stateOfMind) ?? []
        isStateOfMindEntriesExportEnabled = true
        isDailyMoodExportEnabled = true
        isMomentaryEmotionExportEnabled = true
        isAverageValenceExportEnabled = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mindfulMinutes, forKey: .mindfulMinutes)
        try container.encodeIfPresent(mindfulSessions, forKey: .mindfulSessions)
        try container.encode(stateOfMind, forKey: .stateOfMind)
    }

    var hasData: Bool {
        mindfulMinutes != nil || mindfulSessions != nil ||
        (isStateOfMindEntriesExportEnabled && !stateOfMind.isEmpty) ||
        (isDailyMoodExportEnabled && stateOfMind.contains { $0.kind == .dailyMood }) ||
        (isMomentaryEmotionExportEnabled && stateOfMind.contains { $0.kind == .momentaryEmotion }) ||
        (isAverageValenceExportEnabled && !stateOfMind.isEmpty)
    }

    // Computed properties for independent State of Mind export views.
    var exportedStateOfMindEntries: [StateOfMindEntry] {
        isStateOfMindEntriesExportEnabled ? stateOfMind : []
    }

    var dailyMoods: [StateOfMindEntry] {
        guard isDailyMoodExportEnabled else { return [] }
        return stateOfMind.filter { $0.kind == .dailyMood }
    }

    var momentaryEmotions: [StateOfMindEntry] {
        guard isMomentaryEmotionExportEnabled else { return [] }
        return stateOfMind.filter { $0.kind == .momentaryEmotion }
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
        Array(Set(exportedStateOfMindEntries.flatMap { $0.labels })).sorted()
    }

    var allAssociations: [String] {
        Array(Set(exportedStateOfMindEntries.flatMap { $0.associations })).sorted()
    }

    mutating func removeStateOfMindEntriesView() {
        isStateOfMindEntriesExportEnabled = false
    }

    mutating func removeDailyMoodEntries() {
        isDailyMoodExportEnabled = false
    }

    mutating func removeMomentaryEmotionEntries() {
        isMomentaryEmotionExportEnabled = false
    }
}

// MARK: - State of Mind Entry

nonisolated struct StateOfMindEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let endDate: Date
    let kind: StateOfMindKind
    let valence: Double  // -1.0 (very unpleasant) to 1.0 (very pleasant)
    let labels: [String]  // Emotion/mood labels like "Happy", "Anxious", etc.
    let associations: [String]  // Context like "Work", "Exercise", "Family", etc.
    let sourceRevision: HealthKitSourceRevision?
    let device: HealthKitDeviceProvenance?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date,
        endDate: Date? = nil,
        kind: StateOfMindKind,
        valence: Double,
        labels: [String],
        associations: [String],
        sourceRevision: HealthKitSourceRevision? = nil,
        device: HealthKitDeviceProvenance? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endDate = endDate ?? timestamp
        self.kind = kind
        self.valence = valence
        self.labels = labels
        self.associations = associations
        self.sourceRevision = sourceRevision
        self.device = device
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? timestamp
        kind = try container.decode(StateOfMindKind.self, forKey: .kind)
        valence = try container.decode(Double.self, forKey: .valence)
        labels = try container.decode([String].self, forKey: .labels)
        associations = try container.decode([String].self, forKey: .associations)
        sourceRevision = try container.decodeIfPresent(HealthKitSourceRevision.self, forKey: .sourceRevision)
        device = try container.decodeIfPresent(HealthKitDeviceProvenance.self, forKey: .device)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    enum StateOfMindKind: String, Codable {
        case momentaryEmotion = "Momentary Emotion"
        case dailyMood = "Daily Mood"
        case unknown = "Unknown"
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

nonisolated struct MobilityData: Codable, Sendable {
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

nonisolated struct HearingData: Codable, Sendable {
    var headphoneAudioLevel: Double? // dB
    var environmentalSoundLevel: Double? // dB

    var hasData: Bool {
        headphoneAudioLevel != nil || environmentalSoundLevel != nil
    }
}

// MARK: - Cycling Performance Data

nonisolated struct CyclingPerformanceData: Codable, Sendable {
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

nonisolated struct VitaminsData: Codable, Sendable {
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

nonisolated struct MineralsData: Codable, Sendable {
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

/// Compatibility representation for older granular symptom payloads received
/// without a canonical HealthKit archive.
nonisolated struct SymptomSample: Codable, Sendable {
    let metricId: String
    let startDate: Date
    let endDate: Date
    let rawValue: Int64
    let symbolicValue: String?
    let source: String?
    let metadata: [String: String]
    let originalUUID: UUID?

    init(
        metricId: String,
        startDate: Date,
        endDate: Date,
        rawValue: Int64,
        symbolicValue: String? = nil,
        source: String? = nil,
        metadata: [String: String] = [:],
        originalUUID: UUID? = nil
    ) {
        self.metricId = metricId
        self.startDate = startDate
        self.endDate = endDate
        self.rawValue = rawValue
        self.symbolicValue = symbolicValue
        self.source = source
        self.metadata = metadata
        self.originalUUID = originalUUID
    }
}

nonisolated struct SymptomsData: Codable, Sendable {
    /// Symptom metric ID → count of occurrences for the day.
    /// Keys match HealthMetrics IDs (e.g., "symptom_headache", "symptom_fatigue").
    var counts: [String: Int] = [:]
    var samples: [SymptomSample] = []

    var hasData: Bool { !counts.isEmpty || !samples.isEmpty }

    init(counts: [String: Int] = [:], samples: [SymptomSample] = []) {
        self.counts = counts
        self.samples = samples
    }

    private enum CodingKeys: String, CodingKey { case counts, samples }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        samples = try container.decodeIfPresent([SymptomSample].self, forKey: .samples) ?? []
    }
}

// MARK: - Other Health Data

nonisolated struct OtherHealthData: Codable, Sendable {
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

nonisolated struct ReproductiveHealthData: Codable, Sendable {
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

nonisolated enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case americanFootball
    case archery
    case australianFootball
    case badminton
    case baseball
    case basketball
    case bowling
    case boxing
    case climbing
    case cricket
    case crossTraining
    case curling
    case cycling
    case dance
    case danceInspiredTraining
    case elliptical
    case equestrianSports
    case fencing
    case fishing
    case functionalStrengthTraining
    case golf
    case gymnastics
    case handball
    case hiking
    case hockey
    case hunting
    case lacrosse
    case martialArts
    case mindAndBody
    case mixedMetabolicCardioTraining
    case paddleSports
    case play
    case rolling
    case racquetball
    case rowing
    case rugby
    case running
    case sailing
    case skatingSports
    case snowSports
    case soccer
    case softball
    case squash
    case stairClimbing
    case surfingSports
    case swimming
    case tableTennis
    case tennis
    case trackAndField
    case traditionalStrengthTraining
    case volleyball
    case walking
    case waterFitness
    case waterPolo
    case waterSports
    case wrestling
    case yoga
    case barre
    case coreTraining
    case crossCountrySkiing
    case downhillSkiing
    case flexibility
    case highIntensityIntervalTraining
    case jumpRope
    case kickboxing
    case pilates
    case snowboarding
    case stairs
    case stepTraining
    case wheelchairWalkPace
    case wheelchairRunPace
    case taiChi
    case mixedCardio
    case handCycling
    case discSports
    case fitnessGaming
    case cardioDance
    case socialDance
    case pickleball
    case cooldown
    case swimBikeRun
    case transition
    case underwaterDiving
    case other

    var displayName: String {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .cricket: return "Cricket"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .danceInspiredTraining: return "Dance Inspired Training"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian Sports"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind & Body"
        case .mixedMetabolicCardioTraining: return "Mixed Metabolic Cardio Training"
        case .paddleSports: return "Paddle Sports"
        case .play: return "Play"
        case .rolling: return "Rolling"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track & Field"
        case .traditionalStrengthTraining: return "Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossCountrySkiing: return "Cross-Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .flexibility: return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .pilates: return "Pilates"
        case .snowboarding: return "Snowboarding"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .wheelchairWalkPace: return "Wheelchair Walk Pace"
        case .wheelchairRunPace: return "Wheelchair Run Pace"
        case .taiChi: return "Tai Chi"
        case .mixedCardio: return "Mixed Cardio"
        case .handCycling: return "Hand Cycling"
        case .discSports: return "Disc Sports"
        case .fitnessGaming: return "Fitness Gaming"
        case .cardioDance: return "Cardio Dance"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .cooldown: return "Cooldown"
        case .swimBikeRun: return "Swim Bike Run"
        case .transition: return "Transition"
        case .underwaterDiving: return "Underwater Diving"
        case .other: return "Other"
        }
    }

    /// HealthKit's Swift case name. The Apple Watch label "Rolling" is exposed
    /// through HealthKit as `preparationAndRecovery`.
    var healthKitActivityTypeName: String {
        self == .rolling ? "preparationAndRecovery" : rawValue
    }
}

// MARK: - Workout Data

nonisolated struct WorkoutData: Identifiable, Codable, Sendable {
    /// Stable identity for newly fetched workouts: the original HKWorkout UUID.
    /// Legacy decoded values retain their previously persisted `id`.
    let id: UUID
    /// Explicit source identity for compatibility with models persisted before
    /// `id` became the HealthKit UUID.
    let sourceUUID: UUID?
    let workoutType: WorkoutType
    /// HealthKit's Swift activity case name, such as `running` or
    /// `preparationAndRecovery`. Nil only for legacy or unknown activity types.
    let healthKitActivityType: String?
    /// The original HKWorkoutActivityType raw value. Preserved so activity
    /// identity survives even when the installed SDK does not recognize it.
    let healthKitActivityTypeRawValue: UInt?
    let startTime: Date
    /// Actual elapsed end date from HealthKit, independent of active duration.
    /// Nil only for legacy values that did not persist it.
    let actualEndDate: Date?
    let sourceRevision: HealthKitSourceRevision?
    let device: HealthKitDeviceProvenance?
    let isIndoor: Bool?
    let metadata: [String: String]
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
    let elevationGainMeters: Double?     // total ascent
    let elevationLossMeters: Double?     // total descent
    let laps: [WorkoutLap]
    let splits: [WorkoutSplit]
    let route: [RoutePoint]
    let timeSeries: WorkoutTimeSeries

    init(
        id: UUID? = nil,
        sourceUUID: UUID? = nil,
        workoutType: WorkoutType,
        healthKitActivityType: String? = nil,
        healthKitActivityTypeRawValue: UInt? = nil,
        startTime: Date,
        actualEndDate: Date? = nil,
        sourceRevision: HealthKitSourceRevision? = nil,
        device: HealthKitDeviceProvenance? = nil,
        isIndoor: Bool? = nil,
        metadata: [String: String] = [:],
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
        maxPower: Double? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil,
        laps: [WorkoutLap] = [],
        splits: [WorkoutSplit] = [],
        route: [RoutePoint] = [],
        timeSeries: WorkoutTimeSeries = .empty
    ) {
        self.id = id ?? sourceUUID ?? UUID()
        self.sourceUUID = sourceUUID
        self.workoutType = workoutType
        self.healthKitActivityType = healthKitActivityType
        self.healthKitActivityTypeRawValue = healthKitActivityTypeRawValue
        self.startTime = startTime
        self.actualEndDate = actualEndDate
        self.sourceRevision = sourceRevision
        self.device = device
        self.isIndoor = isIndoor
        self.metadata = metadata
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
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.laps = laps
        self.splits = splits
        self.route = route
        self.timeSeries = timeSeries
    }

    // Backward-compatible decoder: tolerates older persisted JSON that lacks
    // HealthKit activity identity and granular workout fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceUUID = try c.decodeIfPresent(UUID.self, forKey: .sourceUUID)
        workoutType = try c.decode(WorkoutType.self, forKey: .workoutType)
        healthKitActivityType = try c.decodeIfPresent(String.self, forKey: .healthKitActivityType)
        healthKitActivityTypeRawValue = try c.decodeIfPresent(UInt.self, forKey: .healthKitActivityTypeRawValue)
        startTime = try c.decode(Date.self, forKey: .startTime)
        actualEndDate = try c.decodeIfPresent(Date.self, forKey: .actualEndDate)
        sourceRevision = try c.decodeIfPresent(HealthKitSourceRevision.self, forKey: .sourceRevision)
        device = try c.decodeIfPresent(HealthKitDeviceProvenance.self, forKey: .device)
        isIndoor = try c.decodeIfPresent(Bool.self, forKey: .isIndoor)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        calories = try c.decodeIfPresent(Double.self, forKey: .calories)
        distance = try c.decodeIfPresent(Double.self, forKey: .distance)
        avgHeartRate = try c.decodeIfPresent(Double.self, forKey: .avgHeartRate)
        maxHeartRate = try c.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        minHeartRate = try c.decodeIfPresent(Double.self, forKey: .minHeartRate)
        avgRunningCadence = try c.decodeIfPresent(Double.self, forKey: .avgRunningCadence)
        avgStrideLength = try c.decodeIfPresent(Double.self, forKey: .avgStrideLength)
        avgGroundContactTime = try c.decodeIfPresent(Double.self, forKey: .avgGroundContactTime)
        avgVerticalOscillation = try c.decodeIfPresent(Double.self, forKey: .avgVerticalOscillation)
        avgCyclingCadence = try c.decodeIfPresent(Double.self, forKey: .avgCyclingCadence)
        avgPower = try c.decodeIfPresent(Double.self, forKey: .avgPower)
        maxPower = try c.decodeIfPresent(Double.self, forKey: .maxPower)
        elevationGainMeters = try c.decodeIfPresent(Double.self, forKey: .elevationGainMeters)
        elevationLossMeters = try c.decodeIfPresent(Double.self, forKey: .elevationLossMeters)
        laps = try c.decodeIfPresent([WorkoutLap].self, forKey: .laps) ?? []
        splits = try c.decodeIfPresent([WorkoutSplit].self, forKey: .splits) ?? []
        route = try c.decodeIfPresent([RoutePoint].self, forKey: .route) ?? []
        timeSeries = try c.decodeIfPresent(WorkoutTimeSeries.self, forKey: .timeSeries) ?? .empty
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceUUID, workoutType, healthKitActivityType, healthKitActivityTypeRawValue,
             startTime, actualEndDate, sourceRevision, device,
             isIndoor, metadata, duration, calories, distance,
             avgHeartRate, maxHeartRate, minHeartRate,
             avgRunningCadence, avgStrideLength, avgGroundContactTime, avgVerticalOscillation,
             avgCyclingCadence, avgPower, maxPower,
             elevationGainMeters, elevationLossMeters,
             laps, splits, route, timeSeries
    }

    private var isUnknownHealthKitActivity: Bool {
        workoutType == .other &&
        healthKitActivityType == nil &&
        healthKitActivityTypeRawValue != nil &&
        healthKitActivityTypeRawValue != 3000
    }

    var workoutTypeName: String {
        isUnknownHealthKitActivity ? "Unknown HealthKit Activity" : workoutType.displayName
    }

    var workoutSportName: String {
        if isUnknownHealthKitActivity, let rawValue = healthKitActivityTypeRawValue {
            return "healthkit-\(rawValue)"
        }
        return workoutType.rawValue
    }

    /// Picks the right rate format for this workout type:
    /// speed (km/h) for cycling/skating/snow/water, swim pace (/100m) for
    /// swimming, otherwise pace (/km). Returns the user-facing label and the
    /// formatted value, or nil if distance/duration aren't suitable.
    @MainActor
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

/// A conventional five-zone heart-rate summary for a workout.
/// Ranges are derived from the workout/sample max HR using 50–60%, 60–70%,
/// 70–80%, 80–90%, and 90–100% buckets so Markdown exports can surface
/// HealthFit-style time-in-zone summaries without needing raw FIT files.
nonisolated struct WorkoutHeartRateZone: Codable, Equatable, Sendable {
    let index: Int
    let label: String
    let lowerBound: Int
    let upperBound: Int
    let seconds: TimeInterval

    var rangeDescription: String {
        "\(lowerBound)-\(upperBound)"
    }

    var durationClock: String {
        Self.clockDuration(seconds)
    }

    static func clockDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

extension WorkoutData {
    var endTime: Date {
        actualEndDate ?? startTime.addingTimeInterval(duration)
    }

    /// Computes time spent in conventional max-HR-based zones from the workout
    /// heart-rate time-series. Returns an empty array when no per-workout HR
    /// samples are available.
    ///
    /// The default reference max prevents low-intensity workouts from defining
    /// their own tiny zone range (for example, a walk peaking at 95 bpm should
    /// not render 86–95 bpm as “Max”). A future settings/profile layer can pass
    /// a user-specific max heart rate here.
    func heartRateZones(maxHeartRateReference: Double = 174) -> [WorkoutHeartRateZone] {
        let samples = timeSeries.heartRate.sorted { $0.timestamp < $1.timestamp }
        guard !samples.isEmpty else { return [] }

        let sampleMax = samples.map(\.value).max()
        guard let observedMax = [maxHeartRate, sampleMax].compactMap({ $0 }).max(),
              observedMax > 0 else {
            return []
        }
        let maxReference = max(maxHeartRateReference, observedMax)

        let labels = ["Recovery", "Aerobic", "Tempo", "Threshold", "Max"]
        let percentages = [0.50, 0.60, 0.70, 0.80, 0.90, 1.00]
        let boundaries = percentages.map { Int((maxReference * $0).rounded()) }
        let ranges: [(lower: Int, upper: Int)] = (0..<5).map { idx in
            let lower = boundaries[idx]
            let upper = idx == 4 ? Int(maxReference.rounded()) : max(lower, boundaries[idx + 1] - 1)
            return (lower, upper)
        }

        var secondsByZone = Array(repeating: 0.0, count: 5)
        // Preserve the established active-duration zone calculation. `endTime`
        // is the elapsed HealthKit end date and may include paused periods.
        let workoutEnd = startTime.addingTimeInterval(duration)

        for (idx, sample) in samples.enumerated() {
            let nextTimestamp = idx + 1 < samples.count ? samples[idx + 1].timestamp : workoutEnd
            let intervalStart = max(sample.timestamp, startTime)
            let intervalEnd = min(nextTimestamp, workoutEnd)
            let interval = intervalEnd.timeIntervalSince(intervalStart)
            guard interval > 0 else { continue }

            if let zoneIndex = ranges.firstIndex(where: { range in
                sample.value >= Double(range.lower) && sample.value <= Double(range.upper)
            }) {
                secondsByZone[zoneIndex] += interval
            } else if let last = ranges.last, sample.value > Double(last.upper) {
                secondsByZone[4] += interval
            }
        }

        return ranges.enumerated().map { idx, range in
            WorkoutHeartRateZone(
                index: idx + 1,
                label: labels[idx],
                lowerBound: range.lower,
                upperBound: range.upper,
                seconds: secondsByZone[idx]
            )
        }
    }
}

// MARK: - Complete Health Data

/// Timezone context captured when a daily HealthKit record is created.
///
/// Full machine-readable timestamps are always exported in UTC. The captured
/// calendar timezone controls day boundaries and human-readable calendar values
/// such as `date`, `bedtime`, and `wakeTime`, even if the record is later
/// serialized on another device.
nonisolated struct ExportTimeContext: Codable, Equatable, Sendable {
    static let timestampTimeZoneIdentifier = "UTC"

    let calendarTimeZoneIdentifier: String

    init(calendarTimeZoneIdentifier: String) {
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
    }

    init(timeZone: TimeZone) {
        self.init(calendarTimeZoneIdentifier: timeZone.identifier)
    }

    static func captured() -> ExportTimeContext {
        ExportTimeContext(timeZone: Calendar.current.timeZone)
    }

    var calendarTimeZone: TimeZone {
        TimeZone(identifier: calendarTimeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }
}

nonisolated struct ExportPartialFailure: Codable, Equatable, Sendable {
    let date: Date
    let dataType: String
    let dateRangeDescription: String
    let errorDescription: String

    var summary: String {
        "\(dataType) for \(dateRangeDescription): \(errorDescription)"
    }
}

nonisolated struct HealthData: Codable, Sendable {
    let date: Date
    let timeContext: ExportTimeContext
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
    /// Medication metadata and dose events are available on OS versions that
    /// support HealthKit's read-only medications API. Optional for backward
    /// compatibility with previously persisted/synced HealthData JSON.
    var medications: MedicationsData? = nil
    var other: OtherHealthData = OtherHealthData()
    var workouts: [WorkoutData] = []
    var partialFailures: [ExportPartialFailure] = []
    var healthKitRecordArchive: HealthKitRecordArchive? = nil
    private var healthKitRecordCaptureStatusStorage: HealthKitRecordCaptureStatus = .notRequested

    /// The archive is authoritative whenever it is present, preventing status drift after decoding or mutation.
    var healthKitRecordCaptureStatus: HealthKitRecordCaptureStatus {
        get { healthKitRecordArchive?.captureStatus ?? healthKitRecordCaptureStatusStorage }
        set { healthKitRecordCaptureStatusStorage = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case date, timeContext, sleep, activity, heart, vitals, body, nutrition, mindfulness, mobility, hearing
        case reproductiveHealth, cyclingPerformance, vitamins, minerals, symptoms, medications, other, workouts
        case partialFailures, healthKitRecordArchive, healthKitRecordCaptureStatus
    }

    init(
        date: Date,
        timeContext: ExportTimeContext = .captured(),
        sleep: SleepData = SleepData(),
        activity: ActivityData = ActivityData(),
        heart: HeartData = HeartData(),
        vitals: VitalsData = VitalsData(),
        body: BodyData = BodyData(),
        nutrition: NutritionData = NutritionData(),
        mindfulness: MindfulnessData = MindfulnessData(),
        mobility: MobilityData = MobilityData(),
        hearing: HearingData = HearingData(),
        reproductiveHealth: ReproductiveHealthData = ReproductiveHealthData(),
        cyclingPerformance: CyclingPerformanceData = CyclingPerformanceData(),
        vitamins: VitaminsData = VitaminsData(),
        minerals: MineralsData = MineralsData(),
        symptoms: SymptomsData = SymptomsData(),
        medications: MedicationsData? = nil,
        other: OtherHealthData = OtherHealthData(),
        workouts: [WorkoutData] = [],
        partialFailures: [ExportPartialFailure] = [],
        healthKitRecordArchive: HealthKitRecordArchive? = nil,
        healthKitRecordCaptureStatus: HealthKitRecordCaptureStatus = .notRequested
    ) {
        self.date = date
        self.timeContext = timeContext
        self.sleep = sleep
        self.activity = activity
        self.heart = heart
        self.vitals = vitals
        self.body = body
        self.nutrition = nutrition
        self.mindfulness = mindfulness
        self.mobility = mobility
        self.hearing = hearing
        self.reproductiveHealth = reproductiveHealth
        self.cyclingPerformance = cyclingPerformance
        self.vitamins = vitamins
        self.minerals = minerals
        self.symptoms = symptoms
        self.medications = medications
        self.other = other
        self.workouts = workouts
        self.partialFailures = partialFailures
        self.healthKitRecordArchive = healthKitRecordArchive
        self.healthKitRecordCaptureStatusStorage = healthKitRecordCaptureStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        // Records written before schema v3 did not capture timezone context.
        // Snapshot the decoder's current timezone once as a compatibility
        // fallback, then persist it on the next encode.
        timeContext = try container.decodeIfPresent(ExportTimeContext.self, forKey: .timeContext) ?? .captured()
        sleep = try container.decodeIfPresent(SleepData.self, forKey: .sleep) ?? SleepData()
        activity = try container.decodeIfPresent(ActivityData.self, forKey: .activity) ?? ActivityData()
        heart = try container.decodeIfPresent(HeartData.self, forKey: .heart) ?? HeartData()
        vitals = try container.decodeIfPresent(VitalsData.self, forKey: .vitals) ?? VitalsData()
        body = try container.decodeIfPresent(BodyData.self, forKey: .body) ?? BodyData()
        nutrition = try container.decodeIfPresent(NutritionData.self, forKey: .nutrition) ?? NutritionData()
        mindfulness = try container.decodeIfPresent(MindfulnessData.self, forKey: .mindfulness) ?? MindfulnessData()
        mobility = try container.decodeIfPresent(MobilityData.self, forKey: .mobility) ?? MobilityData()
        hearing = try container.decodeIfPresent(HearingData.self, forKey: .hearing) ?? HearingData()
        reproductiveHealth = try container.decodeIfPresent(ReproductiveHealthData.self, forKey: .reproductiveHealth) ?? ReproductiveHealthData()
        cyclingPerformance = try container.decodeIfPresent(CyclingPerformanceData.self, forKey: .cyclingPerformance) ?? CyclingPerformanceData()
        vitamins = try container.decodeIfPresent(VitaminsData.self, forKey: .vitamins) ?? VitaminsData()
        minerals = try container.decodeIfPresent(MineralsData.self, forKey: .minerals) ?? MineralsData()
        symptoms = try container.decodeIfPresent(SymptomsData.self, forKey: .symptoms) ?? SymptomsData()
        medications = try container.decodeIfPresent(MedicationsData.self, forKey: .medications)
        other = try container.decodeIfPresent(OtherHealthData.self, forKey: .other) ?? OtherHealthData()
        workouts = try container.decodeIfPresent([WorkoutData].self, forKey: .workouts) ?? []
        partialFailures = try container.decodeIfPresent([ExportPartialFailure].self, forKey: .partialFailures) ?? []
        healthKitRecordArchive = try container.decodeIfPresent(HealthKitRecordArchive.self, forKey: .healthKitRecordArchive)
        if let archive = healthKitRecordArchive {
            healthKitRecordCaptureStatusStorage = archive.captureStatus
        } else {
            healthKitRecordCaptureStatusStorage = try container.decodeIfPresent(
                HealthKitRecordCaptureStatus.self,
                forKey: .healthKitRecordCaptureStatus
            ) ?? .legacyUnavailable
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(timeContext, forKey: .timeContext)
        try container.encode(sleep, forKey: .sleep)
        try container.encode(activity, forKey: .activity)
        try container.encode(heart, forKey: .heart)
        try container.encode(vitals, forKey: .vitals)
        try container.encode(body, forKey: .body)
        try container.encode(nutrition, forKey: .nutrition)
        try container.encode(mindfulness, forKey: .mindfulness)
        try container.encode(mobility, forKey: .mobility)
        try container.encode(hearing, forKey: .hearing)
        try container.encode(reproductiveHealth, forKey: .reproductiveHealth)
        try container.encode(cyclingPerformance, forKey: .cyclingPerformance)
        try container.encode(vitamins, forKey: .vitamins)
        try container.encode(minerals, forKey: .minerals)
        try container.encode(symptoms, forKey: .symptoms)
        try container.encodeIfPresent(medications, forKey: .medications)
        try container.encode(other, forKey: .other)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(partialFailures, forKey: .partialFailures)
        try container.encodeIfPresent(healthKitRecordArchive, forKey: .healthKitRecordArchive)
        try container.encode(healthKitRecordCaptureStatus, forKey: .healthKitRecordCaptureStatus)
    }

    var hasSummaryData: Bool {
        sleep.hasData || activity.hasData || heart.hasData || vitals.hasData ||
        body.hasData || nutrition.hasData || mindfulness.hasData ||
        mobility.hasData || hearing.hasData || reproductiveHealth.hasData ||
        cyclingPerformance.hasData || vitamins.hasData || minerals.hasData ||
        symptoms.hasData || (medications?.hasData == true) || other.hasData || !workouts.isEmpty
    }

    var hasAnyData: Bool {
        hasSummaryData || healthKitRecordArchive != nil
    }
}

// MARK: - Export Formats

struct PreparedHealthDataExport {
    let filteredData: HealthData
    let snapshot: ExportDataSnapshot
    private let formatCustomization: FormatCustomization
    private let includeMetadata: Bool
    private let groupByCategory: Bool

    init(
        filteredData: HealthData,
        snapshot: ExportDataSnapshot,
        settings: AdvancedExportSettings
    ) {
        self.filteredData = filteredData
        self.snapshot = snapshot
        let frozenCustomization = FormatCustomization()
        FormatCustomizationSnapshot.from(settings.formatCustomization).apply(
            to: frozenCustomization
        )
        self.formatCustomization = frozenCustomization
        self.includeMetadata = settings.includeMetadata
        self.groupByCategory = settings.groupByCategory
    }

    var hasAnyData: Bool { filteredData.hasAnyData }

    func content(
        format: ExportFormat,
        settings _: AdvancedExportSettings
    ) throws -> String {
        let config = formatCustomization
        switch format {
        case .markdown:
            return filteredData.toMarkdown(
                snapshot: snapshot,
                includeMetadata: includeMetadata,
                groupByCategory: groupByCategory,
                config: config
            )
        case .obsidianBases:
            return filteredData.toObsidianBases(snapshot: snapshot, config: config)
        case .json:
            return try filteredData.toJSONThrowing(snapshot: snapshot, config: config)
        case .csv:
            return try filteredData.toCSVThrowing(snapshot: snapshot, config: config)
        }
    }
}

extension HealthData {
    /// Compatibility convenience for previews and call sites that cannot throw.
    /// File/API/strict-raw writers use `exportThrowing` so failed canonical
    /// serialization cannot be reported as a successful export.
    func export(format: ExportFormat, settings: AdvancedExportSettings) -> String {
        do {
            return try exportThrowing(format: format, settings: settings)
        } catch {
            switch format {
            case .json:
                return toJSON(customization: settings.formatCustomization)
            case .csv:
                return toCSV(customization: settings.formatCustomization)
            case .markdown, .obsidianBases:
                return "Export serialization failed; this file is incomplete."
            }
        }
    }

    func preparedExport(settings: AdvancedExportSettings) -> PreparedHealthDataExport {
        let filteredData = filtered(by: settings.metricSelection)
        return PreparedHealthDataExport(
            filteredData: filteredData,
            snapshot: filteredData.exportSnapshot(customization: settings.formatCustomization),
            settings: settings
        )
    }

    func exportThrowing(format: ExportFormat, settings: AdvancedExportSettings) throws -> String {
        try preparedExport(settings: settings).content(format: format, settings: settings)
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

        // Compatibility time-series arrays are not represented by frontmatter keys,
        // so field removal alone cannot prevent records for disabled metrics from
        // leaking into a filtered export.
        let enabledMetricIDs = metricSelection.enabledMetrics
        if enabledMetricIDs.isDisjoint(with: ["heart_rate_avg", "heart_rate_min", "heart_rate_max"]) {
            filtered.heart.heartRateSamples = []
        }
        if !enabledMetricIDs.contains("hrv") {
            filtered.heart.hrvSamples = []
        }
        if !enabledMetricIDs.contains("respiratory_rate") {
            filtered.vitals.respiratoryRateSamples = []
        }
        if !enabledMetricIDs.contains("blood_oxygen") {
            filtered.vitals.bloodOxygenSamples = []
        }
        if !enabledMetricIDs.contains("blood_glucose") {
            filtered.vitals.bloodGlucoseSamples = []
        }
        if !enabledMetricIDs.contains("blood_pressure_systolic") ||
            !enabledMetricIDs.contains("blood_pressure_diastolic") {
            // A compatibility sample contains both values and cannot safely redact one.
            filtered.vitals.bloodPressureSamples = []
        }

        let sleepStageMetricID: [String: String] = [
            "deep": "sleep_deep",
            "rem": "sleep_rem",
            "core": "sleep_core",
            "awake": "sleep_awake",
            "inBed": "sleep_in_bed",
            "unspecified": "sleep_total",
        ]
        filtered.sleep.stages = filtered.sleep.stages.filter { stage in
            guard let metricID = sleepStageMetricID[stage.stage] else { return false }
            return enabledMetricIDs.contains(metricID)
        }

        if let archive = filtered.healthKitRecordArchive {
            filtered.healthKitRecordArchive = archive.filtered(enabledMetricIDs: metricSelection.enabledMetrics)
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
        case "stand_time_minutes": activity.standTimeMinutes = nil
        case "stand_hours": activity.standHours = nil
        case "flights_climbed": activity.flightsClimbed = nil
        case "walking_running_km", "walking_running_mi": activity.walkingRunningDistance = nil
        case "cycling_km", "cycling_mi": activity.cyclingDistance = nil
        case "swimming_m": activity.swimmingDistance = nil
        case "swimming_strokes": activity.swimmingStrokes = nil
        case "wheelchair_pushes": activity.pushCount = nil
        case "vo2_max", "vo2_max_source_uuid", "vo2_max_source_start", "vo2_max_source_end",
             "vo2_max_carried_forward", "vo2_max_age_seconds":
            activity.vo2Max = nil
            activity.vo2MaxSourceUUID = nil
            activity.vo2MaxSourceStartDate = nil
            activity.vo2MaxSourceEndDate = nil
            activity.vo2MaxCarriedForward = nil
            activity.vo2MaxAgeSeconds = nil
        case "wheelchair_km", "wheelchair_mi": activity.wheelchairDistance = nil
        case "downhill_snow_km", "downhill_snow_mi": activity.downhillSnowSportsDistance = nil
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
        case "mood_entries", "mood_labels", "mood_associations": mindfulness.removeStateOfMindEntriesView()
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
            symptoms.samples.removeAll { $0.metricId == key }

        // Medications
        case "medication_count", "active_medication_count", "archived_medication_count",
             "medication_details", "medication_dose_count", "medication_dose_events",
             "medication_taken_count", "medication_skipped_count", "medications":
            medications = nil

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
        case "workout_count", "workout_minutes", "workout_calories", "workout_distance_km", "workout_distance_mi", "workouts":
            workouts = []

        default:
            break
        }
    }
}
