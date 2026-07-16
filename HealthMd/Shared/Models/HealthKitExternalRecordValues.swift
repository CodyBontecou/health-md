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

/// Foundation representation of WorkoutKit's public plan identity and exact
/// serialization. The bytes are authoritative; display fields are convenient,
/// non-inferred indexes into that representation.
struct HealthKitWorkoutPlanValue: Codable, Equatable, Sendable {
    let planIdentifier: UUID
    let workoutKind: String
    let activityTypeRawValue: UInt64
    let activityTypeSymbolicValue: String?
    let displayName: String?
    let dataRepresentation: Data

    init(
        planIdentifier: UUID,
        workoutKind: String,
        activityTypeRawValue: UInt64,
        activityTypeSymbolicValue: String? = nil,
        displayName: String? = nil,
        dataRepresentation: Data
    ) {
        self.planIdentifier = planIdentifier
        self.workoutKind = workoutKind
        self.activityTypeRawValue = activityTypeRawValue
        self.activityTypeSymbolicValue = activityTypeSymbolicValue
        self.displayName = displayName
        self.dataRepresentation = dataRepresentation
    }

    var metadataFields: [String: HealthKitMetadataValue] {
        var fields: [String: HealthKitMetadataValue] = [
            "planIdentifier": .string(planIdentifier.uuidString),
            "workoutKind": .string(workoutKind),
            "activityTypeRawValue": .unsignedInteger(activityTypeRawValue),
            "dataRepresentation": .data(dataRepresentation),
        ]
        if let activityTypeSymbolicValue {
            fields["activityTypeSymbolicValue"] = .string(activityTypeSymbolicValue)
        }
        if let displayName { fields["displayName"] = .string(displayName) }
        return fields
    }
}

/// Scheduled plans are public WorkoutKit values, not HKObjects. They therefore
/// intentionally use the external-record envelope and never invent an HK UUID,
/// source revision, or device.
struct HealthKitScheduledWorkoutPlanValue: Codable, Equatable, Sendable {
    let plan: HealthKitWorkoutPlanValue
    let dateComponents: HealthKitDateComponentsValue
    let complete: Bool

    init(
        plan: HealthKitWorkoutPlanValue,
        dateComponents: HealthKitDateComponentsValue,
        complete: Bool
    ) {
        self.plan = plan
        self.dateComponents = dateComponents
        self.complete = complete
    }

    var externalIdentifier: String {
        let dateIdentity = [
            dateComponents.calendarIdentifier.map { "calendar=\($0)" },
            dateComponents.timeZoneIdentifier.map { "timezone=\($0)" },
            dateComponents.era.map { "era=\($0)" },
            dateComponents.year.map { "year=\($0)" },
            dateComponents.month.map { "month=\($0)" },
            dateComponents.day.map { "day=\($0)" },
            dateComponents.hour.map { "hour=\($0)" },
            dateComponents.minute.map { "minute=\($0)" },
            dateComponents.second.map { "second=\($0)" },
        ].compactMap { $0 }.joined(separator: "|")
        return "workoutkit.scheduled_workout|plan=\(plan.planIdentifier.uuidString)|\(dateIdentity)"
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

    static func scheduledWorkoutPlan(
        _ value: HealthKitScheduledWorkoutPlanValue,
        objectTypeIdentifier: String,
        selectedMetricIDs: [String]
    ) -> HealthKitExternalRecord {
        HealthKitExternalRecord(
            externalIdentifier: value.externalIdentifier,
            externalIdentityKind: .other("workoutkit_scheduled_workout_plan"),
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: .other("scheduledWorkoutPlan"),
            selectedMetricIDs: selectedMetricIDs,
            fields: [
                "plan": .dictionary(value.plan.metadataFields),
                "scheduleDate": value.dateComponents.metadataValue,
                "complete": .bool(value.complete),
            ]
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
