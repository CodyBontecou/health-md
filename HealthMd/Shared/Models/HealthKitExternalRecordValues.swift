import Foundation

/// Foundation-only representation of every public DateComponents field relevant to HealthKit.
/// Nil remains distinct from zero and omitted public calendar/time-zone context is not invented.
struct HealthKitDateComponentsValue: Codable, Equatable, Sendable {
    let calendarIdentifier: String?
    let timeZoneIdentifier: String?
    let era: Int?
    let year: Int?
    let month: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?
    let second: Int?
    let nanosecond: Int?
    let weekday: Int?
    let weekdayOrdinal: Int?
    let dayOfYear: Int?
    let quarter: Int?
    let weekOfMonth: Int?
    let weekOfYear: Int?
    let yearForWeekOfYear: Int?
    let isLeapMonth: Bool?

    init(
        calendarIdentifier: String? = nil,
        timeZoneIdentifier: String? = nil,
        era: Int? = nil,
        year: Int? = nil,
        month: Int? = nil,
        day: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        second: Int? = nil,
        nanosecond: Int? = nil,
        weekday: Int? = nil,
        weekdayOrdinal: Int? = nil,
        dayOfYear: Int? = nil,
        quarter: Int? = nil,
        weekOfMonth: Int? = nil,
        weekOfYear: Int? = nil,
        yearForWeekOfYear: Int? = nil,
        isLeapMonth: Bool? = nil
    ) {
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.era = era
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.nanosecond = nanosecond
        self.weekday = weekday
        self.weekdayOrdinal = weekdayOrdinal
        self.dayOfYear = dayOfYear
        self.quarter = quarter
        self.weekOfMonth = weekOfMonth
        self.weekOfYear = weekOfYear
        self.yearForWeekOfYear = yearForWeekOfYear
        self.isLeapMonth = isLeapMonth
    }

    var metadataValue: HealthKitMetadataValue {
        var fields: [String: HealthKitMetadataValue] = [:]
        if let calendarIdentifier { fields["calendarIdentifier"] = .string(calendarIdentifier) }
        if let timeZoneIdentifier { fields["timeZoneIdentifier"] = .string(timeZoneIdentifier) }
        let integers: [(String, Int?)] = [
            ("era", era), ("year", year), ("month", month), ("day", day),
            ("hour", hour), ("minute", minute), ("second", second),
            ("nanosecond", nanosecond), ("weekday", weekday),
            ("weekdayOrdinal", weekdayOrdinal), ("dayOfYear", dayOfYear),
            ("quarter", quarter),
            ("weekOfMonth", weekOfMonth), ("weekOfYear", weekOfYear),
            ("yearForWeekOfYear", yearForWeekOfYear),
        ]
        for (key, value) in integers {
            if let value { fields[key] = .signedInteger(Int64(value)) }
        }
        if let isLeapMonth { fields["isLeapMonth"] = .bool(isLeapMonth) }
        return .dictionary(fields)
    }

    var activitySummaryExternalIdentifier: String {
        let components: [(String, String?)] = [
            ("calendar", calendarIdentifier),
            ("timezone", timeZoneIdentifier),
            ("era", era.map(String.init)),
            ("year", year.map(String.init)),
            ("month", month.map(String.init)),
            ("day", day.map(String.init)),
        ]
        let identity = components.compactMap { key, value in value.map { "\(key)=\($0)" } }
            .joined(separator: "|")
        return "healthkit.activity_summary|\(identity)"
    }
}

struct HealthKitActivitySummaryRecordValue: Codable, Equatable, Sendable {
    let dateComponents: HealthKitDateComponentsValue
    let activityMoveModeRawValue: Int64
    let activityMoveModeSymbolicValue: String?
    let paused: Bool?
    let activeEnergyBurned: HealthKitExactQuantityValue
    let appleMoveTime: HealthKitExactQuantityValue?
    let appleExerciseTime: HealthKitExactQuantityValue
    let appleStandHours: HealthKitExactQuantityValue
    let activeEnergyBurnedGoal: HealthKitExactQuantityValue
    let appleMoveTimeGoal: HealthKitExactQuantityValue?
    let appleExerciseTimeGoal: HealthKitExactQuantityValue
    let exerciseTimeGoal: HealthKitExactQuantityValue?
    let appleStandHoursGoal: HealthKitExactQuantityValue
    let standHoursGoal: HealthKitExactQuantityValue?

    init(
        dateComponents: HealthKitDateComponentsValue,
        activityMoveModeRawValue: Int64,
        activityMoveModeSymbolicValue: String?,
        paused: Bool?,
        activeEnergyBurned: HealthKitExactQuantityValue,
        appleMoveTime: HealthKitExactQuantityValue?,
        appleExerciseTime: HealthKitExactQuantityValue,
        appleStandHours: HealthKitExactQuantityValue,
        activeEnergyBurnedGoal: HealthKitExactQuantityValue,
        appleMoveTimeGoal: HealthKitExactQuantityValue?,
        appleExerciseTimeGoal: HealthKitExactQuantityValue,
        exerciseTimeGoal: HealthKitExactQuantityValue?,
        appleStandHoursGoal: HealthKitExactQuantityValue,
        standHoursGoal: HealthKitExactQuantityValue?
    ) {
        self.dateComponents = dateComponents
        self.activityMoveModeRawValue = activityMoveModeRawValue
        self.activityMoveModeSymbolicValue = activityMoveModeSymbolicValue
        self.paused = paused
        self.activeEnergyBurned = activeEnergyBurned
        self.appleMoveTime = appleMoveTime
        self.appleExerciseTime = appleExerciseTime
        self.appleStandHours = appleStandHours
        self.activeEnergyBurnedGoal = activeEnergyBurnedGoal
        self.appleMoveTimeGoal = appleMoveTimeGoal
        self.appleExerciseTimeGoal = appleExerciseTimeGoal
        self.exerciseTimeGoal = exerciseTimeGoal
        self.appleStandHoursGoal = appleStandHoursGoal
        self.standHoursGoal = standHoursGoal
    }
}

enum HealthKitExternalRecordMapper {
    static func activitySummary(
        _ value: HealthKitActivitySummaryRecordValue,
        objectTypeIdentifier: String,
        selectedMetricIDs: [String]
    ) -> HealthKitExternalRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "dateComponents": value.dateComponents.metadataValue,
            "activityMoveMode": rawEnum(
                rawValue: value.activityMoveModeRawValue,
                symbolicValue: value.activityMoveModeSymbolicValue
            ),
            "activeEnergyBurned": value.activeEnergyBurned.metadataValue,
            "appleExerciseTime": value.appleExerciseTime.metadataValue,
            "appleStandHours": value.appleStandHours.metadataValue,
            "activeEnergyBurnedGoal": value.activeEnergyBurnedGoal.metadataValue,
            "appleExerciseTimeGoal": value.appleExerciseTimeGoal.metadataValue,
            "appleStandHoursGoal": value.appleStandHoursGoal.metadataValue,
        ]
        if let paused = value.paused { fields["paused"] = .bool(paused) }
        if let quantity = value.appleMoveTime { fields["appleMoveTime"] = quantity.metadataValue }
        if let quantity = value.appleMoveTimeGoal { fields["appleMoveTimeGoal"] = quantity.metadataValue }
        if let quantity = value.exerciseTimeGoal { fields["exerciseTimeGoal"] = quantity.metadataValue }
        if let quantity = value.standHoursGoal { fields["standHoursGoal"] = quantity.metadataValue }

        return HealthKitExternalRecord(
            externalIdentifier: value.dateComponents.activitySummaryExternalIdentifier,
            externalIdentityKind: .activitySummaryDateComponents,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: .activitySummary,
            selectedMetricIDs: selectedMetricIDs,
            fields: fields
        )
    }

    static func characteristic(
        objectTypeIdentifier: String,
        selectedMetricIDs: [String],
        fields: [String: HealthKitMetadataValue]
    ) -> HealthKitExternalRecord {
        HealthKitExternalRecord(
            externalIdentifier: "healthkit.characteristic|\(objectTypeIdentifier)",
            externalIdentityKind: .characteristicSingleton,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: .characteristic,
            selectedMetricIDs: selectedMetricIDs,
            fields: fields
        )
    }

    static func rawEnum(rawValue: Int64, symbolicValue: String?) -> HealthKitMetadataValue {
        SpecializedHealthKitRecordMapper.rawEnum(
            rawValue: rawValue,
            symbolicValue: symbolicValue
        )
    }
}
