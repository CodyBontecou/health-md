import Foundation

// MARK: - Public typed provider sections

/// Optional provider namespace embedded in Apple `healthmd.health_data` v8 daily records.
/// Provider-native `ExternalDailyRecord` sidecars remain a separate fidelity layer.
nonisolated struct HealthProviderSections: Codable, Equatable, Sendable {
    var whoop: WHOOPDailyProviderSection?

    var isEmpty: Bool { whoop == nil }

    static func normalized(from records: [ExternalDailyRecord]) -> HealthProviderSections? {
        let whoopRecords = records.filter { $0.provider == .whoop }
        guard !whoopRecords.isEmpty else { return nil }
        return HealthProviderSections(whoop: WHOOPProviderNormalizer.normalize(whoopRecords))
    }
}

nonisolated enum WHOOPCaptureStatus: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case notRequested = "not_requested"
}

nonisolated enum WHOOPResourceName: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case cycles
    case recovery
    case sleep
    case workouts
    case body
}

nonisolated enum WHOOPResourceStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case skipped
    case unsupported
}

nonisolated struct WHOOPSafeError: Codable, Equatable, Sendable {
    let code: String
    let message: String
    let retryable: Bool
    let httpStatusCode: Int?
    let retryAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case code, message, retryable
        case httpStatusCode = "http_status_code"
        case retryAfterSeconds = "retry_after_seconds"
    }
}

nonisolated struct WHOOPResourceResult: Codable, Equatable, Sendable {
    let resource: WHOOPResourceName
    let status: WHOOPResourceStatus
    let recordCount: Int
    let error: WHOOPSafeError?

    enum CodingKeys: String, CodingKey {
        case resource, status, error
        case recordCount = "record_count"
    }
}

nonisolated struct WHOOPWarning: Codable, Equatable, Hashable, Sendable {
    let code: String
    let message: String
    let resource: WHOOPResourceName?
}

/// Distinguishes an omitted cycle end from an explicit provider `null` for an in-progress cycle.
nonisolated enum WHOOPNullableTimestamp: Codable, Equatable, Sendable {
    case timestamp(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .timestamp(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .timestamp(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

nonisolated struct WHOOPCycle: Codable, Equatable, Sendable {
    let id: String
    let startTime: String
    let endTime: WHOOPNullableTimestamp?
    let timezoneOffset: String?
    let scoreState: String?
    let strainScore: Double?
    let energyKilojoules: Double?
    let averageHeartRateBPM: Double?
    let maxHeartRateBPM: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
        case strainScore = "strain_score"
        case energyKilojoules = "energy_kilojoules"
        case averageHeartRateBPM = "average_heart_rate_bpm"
        case maxHeartRateBPM = "max_heart_rate_bpm"
    }
}

nonisolated struct WHOOPRecovery: Codable, Equatable, Sendable {
    let cycleID: String
    let sleepID: String?
    let scoreState: String?
    let userCalibrating: Bool?
    let recoveryScorePercent: Double?
    let restingHeartRateBPM: Double?
    let hrvRMSSDMS: Double?
    let spo2Percent: Double?
    let skinTemperatureCelsius: Double?

    enum CodingKeys: String, CodingKey {
        case cycleID = "cycle_id"
        case sleepID = "sleep_id"
        case scoreState = "score_state"
        case userCalibrating = "user_calibrating"
        case recoveryScorePercent = "recovery_score_percent"
        case restingHeartRateBPM = "resting_heart_rate_bpm"
        case hrvRMSSDMS = "hrv_rmssd_ms"
        case spo2Percent = "spo2_percent"
        case skinTemperatureCelsius = "skin_temperature_celsius"
    }
}

nonisolated struct WHOOPSleep: Codable, Equatable, Sendable {
    let id: String
    let cycleID: String
    let startTime: String
    let endTime: String
    let timezoneOffset: String?
    let isNap: Bool
    let scoreState: String?
    let totalSleepMilliseconds: Int64?
    let totalInBedMilliseconds: Int64?
    let awakeMilliseconds: Int64?
    let lightSleepMilliseconds: Int64?
    let slowWaveSleepMilliseconds: Int64?
    let remSleepMilliseconds: Int64?
    let noDataMilliseconds: Int64?
    let sleepCycleCount: Int64?
    let disturbanceCount: Int64?
    let baselineSleepNeedMilliseconds: Int64?
    let sleepDebtNeedMilliseconds: Int64?
    let recentStrainNeedMilliseconds: Int64?
    let recentNapAdjustmentMilliseconds: Int64?
    let respiratoryRateBreathsPerMinute: Double?
    let sleepPerformancePercent: Double?
    let sleepConsistencyPercent: Double?
    let sleepEfficiencyPercent: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case cycleID = "cycle_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case timezoneOffset = "timezone_offset"
        case isNap = "is_nap"
        case scoreState = "score_state"
        case totalSleepMilliseconds = "total_sleep_milliseconds"
        case totalInBedMilliseconds = "total_in_bed_milliseconds"
        case awakeMilliseconds = "awake_milliseconds"
        case lightSleepMilliseconds = "light_sleep_milliseconds"
        case slowWaveSleepMilliseconds = "slow_wave_sleep_milliseconds"
        case remSleepMilliseconds = "rem_sleep_milliseconds"
        case noDataMilliseconds = "no_data_milliseconds"
        case sleepCycleCount = "sleep_cycle_count"
        case disturbanceCount = "disturbance_count"
        case baselineSleepNeedMilliseconds = "baseline_sleep_need_milliseconds"
        case sleepDebtNeedMilliseconds = "sleep_debt_need_milliseconds"
        case recentStrainNeedMilliseconds = "recent_strain_need_milliseconds"
        case recentNapAdjustmentMilliseconds = "recent_nap_adjustment_milliseconds"
        case respiratoryRateBreathsPerMinute = "respiratory_rate_breaths_per_minute"
        case sleepPerformancePercent = "sleep_performance_percent"
        case sleepConsistencyPercent = "sleep_consistency_percent"
        case sleepEfficiencyPercent = "sleep_efficiency_percent"
    }
}

nonisolated struct WHOOPZoneDurations: Codable, Equatable, Sendable {
    let zoneZeroMilliseconds: Int64?
    let zoneOneMilliseconds: Int64?
    let zoneTwoMilliseconds: Int64?
    let zoneThreeMilliseconds: Int64?
    let zoneFourMilliseconds: Int64?
    let zoneFiveMilliseconds: Int64?

    var hasValues: Bool {
        zoneZeroMilliseconds != nil || zoneOneMilliseconds != nil ||
            zoneTwoMilliseconds != nil || zoneThreeMilliseconds != nil ||
            zoneFourMilliseconds != nil || zoneFiveMilliseconds != nil
    }

    enum CodingKeys: String, CodingKey {
        case zoneZeroMilliseconds = "zone_zero_milliseconds"
        case zoneOneMilliseconds = "zone_one_milliseconds"
        case zoneTwoMilliseconds = "zone_two_milliseconds"
        case zoneThreeMilliseconds = "zone_three_milliseconds"
        case zoneFourMilliseconds = "zone_four_milliseconds"
        case zoneFiveMilliseconds = "zone_five_milliseconds"
    }
}

nonisolated struct WHOOPWorkout: Codable, Equatable, Sendable {
    let id: String
    let startTime: String
    let endTime: String
    let timezoneOffset: String?
    let sportName: String
    let scoreState: String?
    let strainScore: Double?
    let averageHeartRateBPM: Double?
    let maxHeartRateBPM: Double?
    let energyKilojoules: Double?
    let distanceMeters: Double?
    let altitudeGainMeters: Double?
    let altitudeChangeMeters: Double?
    let percentRecorded: Double?
    let zoneDurations: WHOOPZoneDurations?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case timezoneOffset = "timezone_offset"
        case sportName = "sport_name"
        case scoreState = "score_state"
        case strainScore = "strain_score"
        case averageHeartRateBPM = "average_heart_rate_bpm"
        case maxHeartRateBPM = "max_heart_rate_bpm"
        case energyKilojoules = "energy_kilojoules"
        case distanceMeters = "distance_meters"
        case altitudeGainMeters = "altitude_gain_meters"
        case altitudeChangeMeters = "altitude_change_meters"
        case percentRecorded = "percent_recorded"
        case zoneDurations = "zone_durations"
    }
}

nonisolated struct WHOOPBodySnapshot: Codable, Equatable, Sendable {
    let sourceKind: String
    let observedAt: String
    let heightMeters: Double?
    let weightKilograms: Double?
    let maxHeartRateBPM: Double?

    enum CodingKeys: String, CodingKey {
        case sourceKind = "source_kind"
        case observedAt = "observed_at"
        case heightMeters = "height_meters"
        case weightKilograms = "weight_kilograms"
        case maxHeartRateBPM = "max_heart_rate_bpm"
    }
}

nonisolated struct WHOOPDailyProviderSection: Codable, Equatable, Sendable {
    static let schemaIdentifier = "healthmd.provider.whoop_daily"
    static let currentSchemaVersion = 1

    var schema: String = Self.schemaIdentifier
    var schemaVersion: Int = Self.currentSchemaVersion
    let captureStatus: WHOOPCaptureStatus
    let fetchedAt: String?
    let resources: [WHOOPResourceResult]
    let cycles: [WHOOPCycle]
    let recoveries: [WHOOPRecovery]
    let sleep: [WHOOPSleep]
    let workouts: [WHOOPWorkout]
    let body: WHOOPBodySnapshot?
    let warnings: [WHOOPWarning]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureStatus = "capture_status"
        case fetchedAt = "fetched_at"
        case resources, cycles, recoveries, sleep, workouts, body, warnings
    }

    var recordCountsAreValid: Bool {
        let counts: [WHOOPResourceName: Int] = [
            .cycles: cycles.count,
            .recovery: recoveries.count,
            .sleep: sleep.count,
            .workouts: workouts.count,
            .body: body == nil ? 0 : 1,
        ]
        return Set(resources.map(\.resource)).count == resources.count
            && resources.allSatisfy { $0.recordCount == counts[$0.resource] }
            && (captureStatus == .complete
                ? resources.allSatisfy { $0.status == .success }
                : captureStatus != .partial || resources.contains { $0.status != .success })
    }
}

// MARK: - Stable flat projections

nonisolated struct WHOOPFlatMetricDefinition: Equatable, Sendable {
    let key: String
    let displayName: String
    let category: String
    let unit: String

    static let all: [WHOOPFlatMetricDefinition] = [
        .init(key: "whoop_capture_status", displayName: "WHOOP Capture Status", category: "WHOOP Capture", unit: "status"),
        .init(key: "whoop_cycle_strain_score", displayName: "WHOOP Cycle Strain Score", category: "WHOOP Cycle", unit: "score"),
        .init(key: "whoop_cycle_energy_kilojoules", displayName: "WHOOP Cycle Energy", category: "WHOOP Cycle", unit: "kJ"),
        .init(key: "whoop_cycle_average_heart_rate_bpm", displayName: "WHOOP Cycle Average Heart Rate", category: "WHOOP Cycle", unit: "bpm"),
        .init(key: "whoop_cycle_max_heart_rate_bpm", displayName: "WHOOP Cycle Maximum Heart Rate", category: "WHOOP Cycle", unit: "bpm"),
        .init(key: "whoop_recovery_score_percent", displayName: "WHOOP Recovery Score", category: "WHOOP Recovery", unit: "percent"),
        .init(key: "whoop_resting_heart_rate_bpm", displayName: "WHOOP Resting Heart Rate", category: "WHOOP Recovery", unit: "bpm"),
        .init(key: "whoop_hrv_rmssd_ms", displayName: "WHOOP HRV (RMSSD)", category: "WHOOP Recovery", unit: "ms"),
        .init(key: "whoop_spo2_percent", displayName: "WHOOP SpO₂", category: "WHOOP Recovery", unit: "percent"),
        .init(key: "whoop_skin_temperature_celsius", displayName: "WHOOP Skin Temperature", category: "WHOOP Recovery", unit: "°C"),
        .init(key: "whoop_total_sleep_milliseconds", displayName: "WHOOP Total Sleep", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_total_in_bed_milliseconds", displayName: "WHOOP Total In Bed", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_awake_milliseconds", displayName: "WHOOP Awake Duration", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_light_sleep_milliseconds", displayName: "WHOOP Light Sleep Duration", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_slow_wave_sleep_milliseconds", displayName: "WHOOP Slow Wave Sleep Duration", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_rem_sleep_milliseconds", displayName: "WHOOP REM Sleep Duration", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_recent_nap_adjustment_milliseconds", displayName: "WHOOP Recent Nap Adjustment", category: "WHOOP Sleep", unit: "ms"),
        .init(key: "whoop_respiratory_rate_breaths_per_minute", displayName: "WHOOP Respiratory Rate", category: "WHOOP Sleep", unit: "breaths/min"),
        .init(key: "whoop_sleep_performance_percent", displayName: "WHOOP Sleep Performance", category: "WHOOP Sleep", unit: "percent"),
        .init(key: "whoop_sleep_consistency_percent", displayName: "WHOOP Sleep Consistency", category: "WHOOP Sleep", unit: "percent"),
        .init(key: "whoop_sleep_efficiency_percent", displayName: "WHOOP Sleep Efficiency", category: "WHOOP Sleep", unit: "percent"),
        .init(key: "whoop_workout_sport_name", displayName: "WHOOP Workout Sport", category: "WHOOP Workout", unit: ""),
        .init(key: "whoop_workout_strain_score", displayName: "WHOOP Workout Strain Score", category: "WHOOP Workout", unit: "score"),
        .init(key: "whoop_workout_average_heart_rate_bpm", displayName: "WHOOP Workout Average Heart Rate", category: "WHOOP Workout", unit: "bpm"),
        .init(key: "whoop_workout_max_heart_rate_bpm", displayName: "WHOOP Workout Maximum Heart Rate", category: "WHOOP Workout", unit: "bpm"),
        .init(key: "whoop_workout_energy_kilojoules", displayName: "WHOOP Workout Energy", category: "WHOOP Workout", unit: "kJ"),
        .init(key: "whoop_workout_distance_meters", displayName: "WHOOP Workout Distance", category: "WHOOP Workout", unit: "m"),
        .init(key: "whoop_body_height_meters", displayName: "WHOOP Body Height Snapshot", category: "WHOOP Body", unit: "m"),
        .init(key: "whoop_body_weight_kilograms", displayName: "WHOOP Body Weight Snapshot", category: "WHOOP Body", unit: "kg"),
        .init(key: "whoop_body_max_heart_rate_bpm", displayName: "WHOOP Maximum Heart Rate Snapshot", category: "WHOOP Body", unit: "bpm"),
    ]
}

nonisolated struct WHOOPFlatScalar: Equatable, Sendable {
    let definition: WHOOPFlatMetricDefinition
    let value: String
}

nonisolated extension WHOOPDailyProviderSection {
    var flatScalars: [WHOOPFlatScalar] {
        let definitions = Dictionary(uniqueKeysWithValues: WHOOPFlatMetricDefinition.all.map { ($0.key, $0) })
        var values: [(String, String)] = [("whoop_capture_status", captureStatus.rawValue)]

        func add(_ key: String, _ value: Double?) {
            if let value { values.append((key, Self.numberString(value))) }
        }
        func add(_ key: String, _ value: Int64?) {
            if let value { values.append((key, String(value))) }
        }
        func add(_ key: String, _ value: String?) {
            if let value { values.append((key, value)) }
        }

        if cycles.count == 1, let cycle = cycles.first {
            add("whoop_cycle_strain_score", cycle.strainScore)
            add("whoop_cycle_energy_kilojoules", cycle.energyKilojoules)
            add("whoop_cycle_average_heart_rate_bpm", cycle.averageHeartRateBPM)
            add("whoop_cycle_max_heart_rate_bpm", cycle.maxHeartRateBPM)
        }
        if recoveries.count == 1, let recovery = recoveries.first {
            add("whoop_recovery_score_percent", recovery.recoveryScorePercent)
            add("whoop_resting_heart_rate_bpm", recovery.restingHeartRateBPM)
            add("whoop_hrv_rmssd_ms", recovery.hrvRMSSDMS)
            add("whoop_spo2_percent", recovery.spo2Percent)
            add("whoop_skin_temperature_celsius", recovery.skinTemperatureCelsius)
        }
        if sleep.count == 1, let sleep = sleep.first {
            add("whoop_total_sleep_milliseconds", sleep.totalSleepMilliseconds)
            add("whoop_total_in_bed_milliseconds", sleep.totalInBedMilliseconds)
            add("whoop_awake_milliseconds", sleep.awakeMilliseconds)
            add("whoop_light_sleep_milliseconds", sleep.lightSleepMilliseconds)
            add("whoop_slow_wave_sleep_milliseconds", sleep.slowWaveSleepMilliseconds)
            add("whoop_rem_sleep_milliseconds", sleep.remSleepMilliseconds)
            add("whoop_recent_nap_adjustment_milliseconds", sleep.recentNapAdjustmentMilliseconds)
            add("whoop_respiratory_rate_breaths_per_minute", sleep.respiratoryRateBreathsPerMinute)
            add("whoop_sleep_performance_percent", sleep.sleepPerformancePercent)
            add("whoop_sleep_consistency_percent", sleep.sleepConsistencyPercent)
            add("whoop_sleep_efficiency_percent", sleep.sleepEfficiencyPercent)
        }
        if workouts.count == 1, let workout = workouts.first {
            add("whoop_workout_sport_name", workout.sportName)
            add("whoop_workout_strain_score", workout.strainScore)
            add("whoop_workout_average_heart_rate_bpm", workout.averageHeartRateBPM)
            add("whoop_workout_max_heart_rate_bpm", workout.maxHeartRateBPM)
            add("whoop_workout_energy_kilojoules", workout.energyKilojoules)
            add("whoop_workout_distance_meters", workout.distanceMeters)
        }
        if let body {
            add("whoop_body_height_meters", body.heightMeters)
            add("whoop_body_weight_kilograms", body.weightKilograms)
            add("whoop_body_max_heart_rate_bpm", body.maxHeartRateBPM)
        }

        return values.compactMap { key, value in
            definitions[key].map { WHOOPFlatScalar(definition: $0, value: value) }
        }
    }

    private static func numberString(_ value: Double) -> String {
        value == 0 ? "0" : String(describing: value)
    }
}

// MARK: - Single normalization boundary

private nonisolated enum WHOOPProviderNormalizer {
    private struct ResourceBuild {
        var payloads: [ExternalProviderPayload] = []
        var mappingFailed = false
        var retentionTruncated = false
    }

    private static let maximumRecordsPerCollection = 10_000

    static func normalize(_ records: [ExternalDailyRecord]) -> WHOOPDailyProviderSection {
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.fetchedAt != rhs.fetchedAt { return lhs.fetchedAt < rhs.fetchedAt }
            return lhs.date < rhs.date
        }
        let fetchedDate = sortedRecords.map(\.fetchedAt).max() ?? Date(timeIntervalSince1970: 0)
        let fetchedAt = CanonicalRFC3339UTC.string(from: fetchedDate)
        let payloads = sortedRecords.flatMap(\.payloads)
        let nativeWarnings = sortedRecords.flatMap(\.warnings)

        var builds = Dictionary(uniqueKeysWithValues: WHOOPResourceName.allCases.map { ($0, ResourceBuild()) })
        var planned: Set<WHOOPResourceName> = [.cycles, .recovery, .sleep, .workouts]
        for payload in payloads {
            guard let resource = resourceName(for: payload.name) else { continue }
            planned.insert(resource)
            builds[resource]?.payloads.append(payload)
        }

        var warnings: [WHOOPWarning] = nativeWarnings.isEmpty ? [] : [WHOOPWarning(
            code: "provider_capture_failed",
            message: "WHOOP capture could not complete. Retry after checking the connection.",
            resource: nil
        )]
        var cycles: [WHOOPCycle] = []
        var recoveries: [WHOOPRecovery] = []
        var sleep: [WHOOPSleep] = []
        var workouts: [WHOOPWorkout] = []
        var body: WHOOPBodySnapshot?

        for resource in WHOOPResourceName.allCases where planned.contains(resource) {
            let resourcePayloads = builds[resource]?.payloads ?? []
            for payload in resourcePayloads where payload.error == nil && (200..<300).contains(payload.statusCode) {
                switch resource {
                case .cycles:
                    let mapped = collectionRecords(payload).map(cycle(from:))
                    cycles.append(contentsOf: mapped.compactMap { $0 })
                    if mapped.contains(where: { $0 == nil }) { builds[resource]?.mappingFailed = true }
                case .recovery:
                    let mapped = collectionRecords(payload).map(recovery(from:))
                    recoveries.append(contentsOf: mapped.compactMap { $0 })
                    if mapped.contains(where: { $0 == nil }) { builds[resource]?.mappingFailed = true }
                case .sleep:
                    let mapped = collectionRecords(payload).map(sleep(from:))
                    sleep.append(contentsOf: mapped.compactMap { $0 })
                    if mapped.contains(where: { $0 == nil }) { builds[resource]?.mappingFailed = true }
                case .workouts:
                    let mapped = collectionRecords(payload).map(workout(from:))
                    workouts.append(contentsOf: mapped.compactMap { $0 })
                    if mapped.contains(where: { $0 == nil }) { builds[resource]?.mappingFailed = true }
                case .body:
                    if let value = payload.data {
                        if let mapped = bodySnapshot(
                            from: value,
                            observedAt: CanonicalRFC3339UTC.string(from: payload.fetchedAt)
                        ) {
                            body = mapped
                        } else if !value.isEmptyCollection {
                            builds[resource]?.mappingFailed = true
                        }
                    }
                }
            }
        }

        cycles.sort {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id < $1.id
        }
        let cycleStart = Dictionary(cycles.map { ($0.id, $0.startTime) }, uniquingKeysWith: min)
        recoveries.sort {
            let lhsStart = cycleStart[$0.cycleID]
            let rhsStart = cycleStart[$1.cycleID]
            if lhsStart != rhsStart { return (lhsStart ?? "") < (rhsStart ?? "") }
            return $0.cycleID < $1.cycleID
        }
        sleep.sort {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id < $1.id
        }
        workouts.sort {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id < $1.id
        }

        func enforceRetentionLimit<T>(_ values: inout [T], resource: WHOOPResourceName) {
            guard values.count > maximumRecordsPerCollection else { return }
            values = Array(values.prefix(maximumRecordsPerCollection))
            builds[resource]?.retentionTruncated = true
            warnings.append(WHOOPWarning(
                code: "record_limit_reached",
                message: "WHOOP returned more typed records than one daily section can retain.",
                resource: resource
            ))
        }
        enforceRetentionLimit(&cycles, resource: .cycles)
        enforceRetentionLimit(&recoveries, resource: .recovery)
        enforceRetentionLimit(&sleep, resource: .sleep)
        enforceRetentionLimit(&workouts, resource: .workouts)

        let counts: [WHOOPResourceName: Int] = [
            .cycles: cycles.count,
            .recovery: recoveries.count,
            .sleep: sleep.count,
            .workouts: workouts.count,
            .body: body == nil ? 0 : 1,
        ]
        var resourceResults: [WHOOPResourceResult] = []
        for resource in WHOOPResourceName.allCases where planned.contains(resource) {
            let build = builds[resource] ?? ResourceBuild()
            let failedPayload = build.payloads.first { $0.error != nil || !(200..<300).contains($0.statusCode) }
            let safeError: WHOOPSafeError?
            let status: WHOOPResourceStatus
            if let failedPayload {
                let classification = classify(failedPayload)
                status = classification.status
                safeError = classification.error
            } else if build.retentionTruncated {
                status = .failure
                safeError = WHOOPSafeError(
                    code: "record_limit_reached",
                    message: "WHOOP returned more typed records than one daily section can retain.",
                    retryable: false,
                    httpStatusCode: nil,
                    retryAfterSeconds: nil
                )
            } else if build.mappingFailed {
                status = .failure
                safeError = WHOOPSafeError(
                    code: "malformed_response",
                    message: "WHOOP returned a record that could not be normalized.",
                    retryable: true,
                    httpStatusCode: nil,
                    retryAfterSeconds: nil
                )
                warnings.append(WHOOPWarning(
                    code: "malformed_record",
                    message: "One or more WHOOP records were omitted because required typed fields were invalid.",
                    resource: resource
                ))
            } else if build.payloads.isEmpty {
                status = .failure
                safeError = WHOOPSafeError(
                    code: "provider_capture_failed",
                    message: "WHOOP capture did not return this planned resource.",
                    retryable: true,
                    httpStatusCode: nil,
                    retryAfterSeconds: nil
                )
            } else {
                status = .success
                safeError = nil
            }
            resourceResults.append(WHOOPResourceResult(
                resource: resource,
                status: status,
                recordCount: counts[resource] ?? 0,
                error: safeError
            ))
        }

        let captureStatus: WHOOPCaptureStatus = resourceResults.allSatisfy { $0.status == .success }
            ? .complete
            : .partial
        warnings = Array(Set(warnings)).sorted {
            if $0.resource?.rawValue != $1.resource?.rawValue {
                return ($0.resource?.rawValue ?? "") < ($1.resource?.rawValue ?? "")
            }
            if $0.code != $1.code { return $0.code < $1.code }
            return $0.message < $1.message
        }

        return WHOOPDailyProviderSection(
            captureStatus: captureStatus,
            fetchedAt: fetchedAt,
            resources: resourceResults,
            cycles: cycles,
            recoveries: recoveries,
            sleep: sleep,
            workouts: workouts,
            body: body,
            warnings: warnings
        )
    }

    private static func resourceName(for payloadName: String) -> WHOOPResourceName? {
        if payloadName == "cycles" || payloadName.hasPrefix("cycles_page_") || payloadName == "cycles_pagination" { return .cycles }
        if payloadName == "recovery" || payloadName.hasPrefix("recovery_page_") || payloadName == "recovery_pagination" { return .recovery }
        if payloadName == "sleep" || payloadName.hasPrefix("sleep_page_") || payloadName == "sleep_pagination" { return .sleep }
        if payloadName == "workouts" || payloadName.hasPrefix("workouts_page_") || payloadName == "workouts_pagination" { return .workouts }
        if payloadName == "body_measurements_snapshot" { return .body }
        return nil
    }

    private static func collectionRecords(_ payload: ExternalProviderPayload) -> [JSONValue] {
        guard case .object(let root)? = payload.data,
              case .array(let records)? = root["records"] else { return [] }
        return records
    }

    private static func cycle(from value: JSONValue) -> WHOOPCycle? {
        guard let object = value.object,
              let id = providerID(object["id"]),
              let start = timestamp(object["start"]) else { return nil }
        let score = object["score"]?.object ?? [:]
        return WHOOPCycle(
            id: id,
            startTime: start,
            endTime: nullableTimestamp(object["end"]),
            timezoneOffset: timezoneOffset(object["timezone_offset"]),
            scoreState: boundedString(object["score_state"], maximum: 64),
            strainScore: boundedNumber(score["strain"], minimum: 0, maximum: 21),
            energyKilojoules: boundedNumber(score["kilojoule"], minimum: 0),
            averageHeartRateBPM: boundedNumber(score["average_heart_rate"], minimumExclusive: 0, maximum: 300),
            maxHeartRateBPM: boundedNumber(score["max_heart_rate"], minimumExclusive: 0, maximum: 300)
        )
    }

    private static func recovery(from value: JSONValue) -> WHOOPRecovery? {
        guard let object = value.object,
              let cycleID = providerID(object["cycle_id"]) else { return nil }
        let score = object["score"]?.object ?? [:]
        return WHOOPRecovery(
            cycleID: cycleID,
            sleepID: providerID(object["sleep_id"]),
            scoreState: boundedString(object["score_state"], maximum: 64),
            userCalibrating: score["user_calibrating"]?.bool,
            recoveryScorePercent: boundedNumber(score["recovery_score"], minimum: 0, maximum: 100),
            restingHeartRateBPM: boundedNumber(score["resting_heart_rate"], minimumExclusive: 0, maximum: 300),
            hrvRMSSDMS: boundedNumber(score["hrv_rmssd_milli"], minimum: 0),
            spo2Percent: boundedNumber(score["spo2_percentage"], minimumExclusive: 0, maximum: 100),
            skinTemperatureCelsius: boundedNumber(score["skin_temp_celsius"], minimum: -100, maximum: 100)
        )
    }

    private static func sleep(from value: JSONValue) -> WHOOPSleep? {
        guard let object = value.object,
              let id = providerID(object["id"]),
              let cycleID = providerID(object["cycle_id"]),
              let start = timestamp(object["start"]),
              let end = timestamp(object["end"]),
              let isNap = object["nap"]?.bool else { return nil }
        let score = object["score"]?.object ?? [:]
        let stages = score["stage_summary"]?.object ?? [:]
        let needed = score["sleep_needed"]?.object ?? [:]
        let light = nonnegativeInteger(stages["total_light_sleep_time_milli"])
        let slowWave = nonnegativeInteger(stages["total_slow_wave_sleep_time_milli"])
        let rem = nonnegativeInteger(stages["total_rem_sleep_time_milli"])
        let totalSleep: Int64?
        if let light, let slowWave, let rem {
            let first = light.addingReportingOverflow(slowWave)
            let second = first.partialValue.addingReportingOverflow(rem)
            totalSleep = first.overflow || second.overflow ? nil : second.partialValue
        } else {
            totalSleep = nil
        }
        return WHOOPSleep(
            id: id,
            cycleID: cycleID,
            startTime: start,
            endTime: end,
            timezoneOffset: timezoneOffset(object["timezone_offset"]),
            isNap: isNap,
            scoreState: boundedString(object["score_state"], maximum: 64),
            totalSleepMilliseconds: totalSleep,
            totalInBedMilliseconds: nonnegativeInteger(stages["total_in_bed_time_milli"]),
            awakeMilliseconds: nonnegativeInteger(stages["total_awake_time_milli"]),
            lightSleepMilliseconds: light,
            slowWaveSleepMilliseconds: slowWave,
            remSleepMilliseconds: rem,
            noDataMilliseconds: nonnegativeInteger(stages["total_no_data_time_milli"]),
            sleepCycleCount: nonnegativeInteger(stages["sleep_cycle_count"]),
            disturbanceCount: nonnegativeInteger(stages["disturbance_count"]),
            baselineSleepNeedMilliseconds: nonnegativeInteger(needed["baseline_milli"]),
            sleepDebtNeedMilliseconds: nonnegativeInteger(needed["need_from_sleep_debt_milli"]),
            recentStrainNeedMilliseconds: nonnegativeInteger(needed["need_from_recent_strain_milli"]),
            recentNapAdjustmentMilliseconds: nonpositiveInteger(needed["need_from_recent_nap_milli"]),
            respiratoryRateBreathsPerMinute: boundedNumber(score["respiratory_rate"], minimum: 0, maximum: 100),
            sleepPerformancePercent: boundedNumber(score["sleep_performance_percentage"], minimum: 0, maximum: 100),
            sleepConsistencyPercent: boundedNumber(score["sleep_consistency_percentage"], minimum: 0, maximum: 100),
            sleepEfficiencyPercent: boundedNumber(score["sleep_efficiency_percentage"], minimum: 0, maximum: 100)
        )
    }

    private static func workout(from value: JSONValue) -> WHOOPWorkout? {
        guard let object = value.object,
              let id = providerID(object["id"]),
              let start = timestamp(object["start"]),
              let end = timestamp(object["end"]),
              let sportName = boundedString(object["sport_name"], maximum: 128),
              !sportName.isEmpty else { return nil }
        let score = object["score"]?.object ?? [:]
        let zone = score["zone_duration"]?.object ?? [:]
        let zoneDurations = WHOOPZoneDurations(
            zoneZeroMilliseconds: nonnegativeInteger(zone["zone_zero_milli"]),
            zoneOneMilliseconds: nonnegativeInteger(zone["zone_one_milli"]),
            zoneTwoMilliseconds: nonnegativeInteger(zone["zone_two_milli"]),
            zoneThreeMilliseconds: nonnegativeInteger(zone["zone_three_milli"]),
            zoneFourMilliseconds: nonnegativeInteger(zone["zone_four_milli"]),
            zoneFiveMilliseconds: nonnegativeInteger(zone["zone_five_milli"])
        )
        return WHOOPWorkout(
            id: id,
            startTime: start,
            endTime: end,
            timezoneOffset: timezoneOffset(object["timezone_offset"]),
            sportName: sportName,
            scoreState: boundedString(object["score_state"], maximum: 64),
            strainScore: boundedNumber(score["strain"], minimum: 0, maximum: 21),
            averageHeartRateBPM: boundedNumber(score["average_heart_rate"], minimumExclusive: 0, maximum: 300),
            maxHeartRateBPM: boundedNumber(score["max_heart_rate"], minimumExclusive: 0, maximum: 300),
            energyKilojoules: boundedNumber(score["kilojoule"], minimum: 0),
            distanceMeters: boundedNumber(score["distance_meter"], minimum: 0),
            altitudeGainMeters: boundedNumber(score["altitude_gain_meter"]),
            altitudeChangeMeters: boundedNumber(score["altitude_change_meter"]),
            percentRecorded: boundedNumber(score["percent_recorded"], minimum: 0, maximum: 100),
            zoneDurations: zoneDurations.hasValues ? zoneDurations : nil
        )
    }

    private static func bodySnapshot(from value: JSONValue, observedAt: String) -> WHOOPBodySnapshot? {
        guard let object = value.object else { return nil }
        let height = boundedNumber(object["height_meter"], minimumExclusive: 0, maximum: 3)
        let weight = boundedNumber(object["weight_kilogram"], minimumExclusive: 0, maximum: 1_000)
        let maxHeartRate = boundedNumber(object["max_heart_rate"], minimumExclusive: 0, maximum: 300)
        guard height != nil || weight != nil || maxHeartRate != nil else { return nil }
        return WHOOPBodySnapshot(
            sourceKind: "current_profile_snapshot",
            observedAt: observedAt,
            heightMeters: height,
            weightKilograms: weight,
            maxHeartRateBPM: maxHeartRate
        )
    }

    private static func classify(_ payload: ExternalProviderPayload) -> (status: WHOOPResourceStatus, error: WHOOPSafeError) {
        let text = payload.error?.lowercased() ?? ""
        let retryAfter = retrySeconds(from: text)
        if payload.statusCode == 403 {
            let missing = text.contains("permission read:") || text.contains("scope")
            return (.skipped, WHOOPSafeError(
                code: missing ? "missing_scope" : "permission_denied",
                message: missing
                    ? "WHOOP permission is missing. Reconnect WHOOP and approve the requested scope."
                    : "WHOOP denied this resource. Reconnect WHOOP and review permissions.",
                retryable: false,
                httpStatusCode: 403,
                retryAfterSeconds: nil
            ))
        }
        if payload.statusCode == 429 {
            return (.failure, WHOOPSafeError(
                code: "rate_limited",
                message: "WHOOP rate limited this resource. Retry later.",
                retryable: true,
                httpStatusCode: 429,
                retryAfterSeconds: retryAfter
            ))
        }
        if payload.statusCode == 0 {
            let cancelled = text.contains("cancel")
            let safetyLimit = text.contains("safety limit")
            return (.failure, WHOOPSafeError(
                code: cancelled ? "cancelled" : (safetyLimit ? "response_too_large" : "network_unavailable"),
                message: cancelled
                    ? "WHOOP capture was cancelled."
                    : (safetyLimit
                        ? "WHOOP response exceeded the provider safety limit."
                        : "WHOOP could not be reached for this resource. Retry later."),
                retryable: !cancelled,
                httpStatusCode: nil,
                retryAfterSeconds: nil
            ))
        }
        if payload.statusCode == 200 && payload.error != nil {
            return (.failure, WHOOPSafeError(
                code: "malformed_response",
                message: "WHOOP returned a response that could not be normalized.",
                retryable: true,
                httpStatusCode: 200,
                retryAfterSeconds: nil
            ))
        }
        return (.failure, WHOOPSafeError(
            code: "provider_request_failed",
            message: "WHOOP could not complete this resource. Retry later.",
            retryable: payload.statusCode >= 500 || payload.statusCode == 408,
            httpStatusCode: (100...599).contains(payload.statusCode) ? payload.statusCode : nil,
            retryAfterSeconds: retryAfter
        ))
    }

    private static func retrySeconds(from text: String) -> Int? {
        let pieces = text.split { !$0.isNumber }
        return pieces.compactMap { Int($0) }.first.map { min(max($0, 0), 604_800) }
    }

    private static func providerID(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let raw):
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value.utf8.count > 256 ? nil : value
        case .number(let number):
            guard number.isFinite, number.rounded(.towardZero) == number else { return nil }
            let value = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), number)
            return value.utf8.count <= 256 ? value : nil
        default:
            return nil
        }
    }

    private static func timestamp(_ value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ordinary = ISO8601DateFormatter()
        ordinary.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: raw) ?? ordinary.date(from: raw) else { return nil }
        return CanonicalRFC3339UTC.string(from: date)
    }

    private static func nullableTimestamp(_ value: JSONValue?) -> WHOOPNullableTimestamp? {
        guard let value else { return nil }
        if case .null = value { return .null }
        return timestamp(value).map(WHOOPNullableTimestamp.timestamp)
    }

    private static func timezoneOffset(_ value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else { return nil }
        if raw == "Z" { return raw }
        guard raw.count == 6,
              raw.first == "+" || raw.first == "-",
              raw[raw.index(raw.startIndex, offsetBy: 3)] == ":",
              let hour = Int(raw.dropFirst().prefix(2)),
              let minute = Int(raw.suffix(2)),
              hour <= 14, minute <= 59 else { return nil }
        return raw
    }

    private static func boundedString(_ value: JSONValue?, maximum: Int) -> String? {
        guard case .string(let raw)? = value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximum else { return nil }
        return trimmed
    }

    private static func boundedNumber(
        _ value: JSONValue?,
        minimum: Double? = nil,
        minimumExclusive: Double? = nil,
        maximum: Double? = nil
    ) -> Double? {
        guard case .number(let number)? = value, number.isFinite else { return nil }
        if let minimum, number < minimum { return nil }
        if let minimumExclusive, number <= minimumExclusive { return nil }
        if let maximum, number > maximum { return nil }
        return number
    }

    private static func integer(_ value: JSONValue?) -> Int64? {
        guard case .number(let number)? = value,
              number.isFinite,
              number.rounded(.towardZero) == number else { return nil }
        return Int64(exactly: number)
    }

    private static func nonnegativeInteger(_ value: JSONValue?) -> Int64? {
        integer(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func nonpositiveInteger(_ value: JSONValue?) -> Int64? {
        integer(value).flatMap { $0 <= 0 ? $0 : nil }
    }
}

nonisolated extension HealthProviderSections {
    func foundationJSONObject() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return object
    }
}

private nonisolated extension JSONValue {
    var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
