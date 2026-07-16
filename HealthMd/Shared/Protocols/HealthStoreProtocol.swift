//
//  HealthStoreProtocol.swift
//  HealthMd
//
//  Protocol-based facade for HealthKit queries, enabling deterministic
//  unit testing of HealthKitManager without a real HKHealthStore.
//
//  Value types are used for query results because HKStatistics has no
//  public initializer, making it impossible to construct in tests.
//

@preconcurrency import Foundation
import HealthKit

// NSPredicate is effectively immutable once created — safe to send across actors.
extension NSPredicate: @retroactive @unchecked Sendable {}

// MARK: - Value Types for Query Results

/// Represents a category sample (e.g., sleep analysis stage).
struct CategorySampleValue: Sendable {
    let value: Int
    let startDate: Date
    let endDate: Date
    let metadata: [String: String]

    init(value: Int, startDate: Date, endDate: Date, metadata: [String: String] = [:]) {
        self.value = value
        self.startDate = startDate
        self.endDate = endDate
        self.metadata = metadata
    }
}

/// Represents a quantity sample (e.g., individual heart rate reading).
struct QuantitySampleValue: Sendable {
    let value: Double
    let startDate: Date
    let endDate: Date
    let metadata: [String: String]

    init(value: Double, startDate: Date, endDate: Date, metadata: [String: String] = [:]) {
        self.value = value
        self.startDate = startDate
        self.endDate = endDate
        self.metadata = metadata
    }
}

/// Represents one paired blood pressure reading from a HealthKit correlation.
/// Keeping the components together prevents independently queried systolic and
/// diastolic values from being combined into a reading that never occurred.
struct BloodPressureSampleValue: Sendable {
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
}

/// A single lap within a workout. Sourced from HKWorkoutEvent of type .lap
/// (manually-tapped lap markers on watchOS).
struct WorkoutLap: Sendable, Codable, Equatable {
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
}

/// A single auto-distance split derived from the route + HR samples by the adapter.
/// Distances are stored in meters; renderers format pace/speed using the user's unit preference.
struct WorkoutSplit: Sendable, Codable, Equatable {
    let index: Int
    let startDate: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let avgHeartRate: Double?
}

/// A single per-second sample of a workout time-series metric.
struct TimeSeriesSample: Sendable, Codable, Equatable {
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

/// Per-workout time-series, populated from HKQuantitySeriesSampleQuery /
/// HKAnchoredObjectQuery. Each array is empty when the metric was unavailable.
struct WorkoutTimeSeries: Sendable, Codable, Equatable {
    let heartRate: [TimeSeriesSample]
    let speed: [TimeSeriesSample]              // m/s
    let power: [TimeSeriesSample]              // W
    let cadence: [TimeSeriesSample]            // spm (run) or rpm (ride)
    let strideLength: [TimeSeriesSample]       // m
    let groundContactTime: [TimeSeriesSample]  // ms
    let verticalOscillation: [TimeSeriesSample]// cm
    let altitude: [TimeSeriesSample]           // m

    init(
        heartRate: [TimeSeriesSample] = [],
        speed: [TimeSeriesSample] = [],
        power: [TimeSeriesSample] = [],
        cadence: [TimeSeriesSample] = [],
        strideLength: [TimeSeriesSample] = [],
        groundContactTime: [TimeSeriesSample] = [],
        verticalOscillation: [TimeSeriesSample] = [],
        altitude: [TimeSeriesSample] = []
    ) {
        self.heartRate = heartRate
        self.speed = speed
        self.power = power
        self.cadence = cadence
        self.strideLength = strideLength
        self.groundContactTime = groundContactTime
        self.verticalOscillation = verticalOscillation
        self.altitude = altitude
    }

    var isEmpty: Bool {
        heartRate.isEmpty && speed.isEmpty && power.isEmpty && cadence.isEmpty &&
        strideLength.isEmpty && groundContactTime.isEmpty &&
        verticalOscillation.isEmpty && altitude.isEmpty
    }

    static let empty = WorkoutTimeSeries()
}

/// A single GPS sample from a workout route (HKWorkoutRoute / CLLocation).
struct RoutePoint: Sendable, Codable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let speedMps: Double?
    let courseDegrees: Double?
    let horizontalAccuracyMeters: Double?
}

/// Represents a workout summary.
struct WorkoutValue: Sendable {
    let activityType: UInt
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date
    let isIndoor: Bool?
    let metadata: [String: String]
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let minHeartRate: Double?
    let avgRunningCadence: Double?      // steps per minute
    let avgStrideLength: Double?         // meters
    let avgGroundContactTime: Double?    // milliseconds
    let avgVerticalOscillation: Double?  // centimeters
    let avgCyclingCadence: Double?       // revolutions per minute
    let avgPower: Double?                // watts (running or cycling)
    let maxPower: Double?                // watts
    let elevationGainMeters: Double?     // meters
    let elevationLossMeters: Double?     // meters
    let laps: [WorkoutLap]
    let splits: [WorkoutSplit]
    let route: [RoutePoint]
    let timeSeries: WorkoutTimeSeries

    init(
        activityType: UInt,
        duration: TimeInterval,
        startDate: Date,
        endDate: Date,
        isIndoor: Bool? = nil,
        metadata: [String: String] = [:],
        totalEnergyBurned: Double?,
        totalDistance: Double?,
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
        self.activityType = activityType
        self.duration = duration
        self.startDate = startDate
        self.endDate = endDate
        self.isIndoor = isIndoor
        self.metadata = metadata
        self.totalEnergyBurned = totalEnergyBurned
        self.totalDistance = totalDistance
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
}

/// Represents a State of Mind sample (iOS 18+).
/// Labels and associations are pre-mapped to display strings by the adapter.
struct StateOfMindSampleValue: Sendable {
    let uuid: UUID
    let kind: String
    let valence: Double
    let labels: [String]
    let associations: [String]
    let startDate: Date
    let endDate: Date
    let sourceRevision: HealthKitSourceRevision?
    let device: HealthKitDeviceProvenance?
    let metadata: [String: String]

    init(
        uuid: UUID,
        kind: String,
        valence: Double,
        labels: [String],
        associations: [String],
        startDate: Date,
        endDate: Date? = nil,
        sourceRevision: HealthKitSourceRevision? = nil,
        device: HealthKitDeviceProvenance? = nil,
        metadata: [String: String] = [:]
    ) {
        self.uuid = uuid
        self.kind = kind
        self.valence = valence
        self.labels = labels
        self.associations = associations
        self.startDate = startDate
        self.endDate = endDate ?? startDate
        self.sourceRevision = sourceRevision
        self.device = device
        self.metadata = metadata
    }
}

/// A clinical coding attached to a medication concept (for example RxNorm).
struct MedicationCodingValue: Sendable {
    let system: String
    let version: String?
    let code: String
}

/// A user-authorized medication concept with Health app annotations.
struct MedicationValue: Sendable {
    let conceptIdentifier: String
    let displayName: String
    let nickname: String?
    let generalForm: String
    let isArchived: Bool
    let hasSchedule: Bool
    let relatedCodings: [MedicationCodingValue]
    let identifierStability: String
    let identifierStabilityNotes: String

    init(
        conceptIdentifier: String,
        displayName: String,
        nickname: String?,
        generalForm: String,
        isArchived: Bool,
        hasSchedule: Bool,
        relatedCodings: [MedicationCodingValue],
        identifierStability: String = "best_effort_healthkit_concept_identifier",
        identifierStabilityNotes: String = "HealthKit exposes an opaque medication concept identifier; clinical codings are preferred when available."
    ) {
        self.conceptIdentifier = conceptIdentifier
        self.displayName = displayName
        self.nickname = nickname
        self.generalForm = generalForm
        self.isArchived = isArchived
        self.hasSchedule = hasSchedule
        self.relatedCodings = relatedCodings
        self.identifierStability = identifierStability
        self.identifierStabilityNotes = identifierStabilityNotes
    }
}

/// Canonical medication dose events plus their authorized external inventory.
struct HealthKitMedicationRecordQueryResult: Sendable {
    let records: [HealthKitRecord]
    let inventoryRecords: [HealthKitMedicationInventoryRecord]

    init(
        records: [HealthKitRecord] = [],
        inventoryRecords: [HealthKitMedicationInventoryRecord] = []
    ) {
        self.records = HealthKitRecord.sortedDeterministically(records)
        self.inventoryRecords = inventoryRecords.sorted {
            if $0.externalIdentifier != $1.externalIdentifier {
                return $0.externalIdentifier < $1.externalIdentifier
            }
            return ($0.displayName ?? "") < ($1.displayName ?? "")
        }
    }
}

/// A HealthKit medication dose event sample, flattened for compatibility exports.
struct MedicationDoseEventValue: Sendable {
    let uuid: UUID
    let medicationConceptIdentifier: String
    let medicationName: String?
    let startDate: Date
    let endDate: Date
    let scheduledDate: Date?
    let doseQuantity: Double?
    let scheduledDoseQuantity: Double?
    let unit: String
    let logStatus: String
    let scheduleType: String
    let metadata: [String: String]

    init(
        uuid: UUID,
        medicationConceptIdentifier: String,
        medicationName: String?,
        startDate: Date,
        endDate: Date,
        scheduledDate: Date?,
        doseQuantity: Double?,
        scheduledDoseQuantity: Double?,
        unit: String,
        logStatus: String,
        scheduleType: String,
        metadata: [String: String] = [:]
    ) {
        self.uuid = uuid
        self.medicationConceptIdentifier = medicationConceptIdentifier
        self.medicationName = medicationName
        self.startDate = startDate
        self.endDate = endDate
        self.scheduledDate = scheduledDate
        self.doseQuantity = doseQuantity
        self.scheduledDoseQuantity = scheduledDoseQuantity
        self.unit = unit
        self.logStatus = logStatus
        self.scheduleType = scheduleType
        self.metadata = metadata
    }
}

// MARK: - HealthStore Protocol

/// Abstracts HealthKit store operations used by HealthKitManager.
/// Production code uses SystemHealthStoreAdapter; tests use FakeHealthStore.
protocol HealthStoreProviding: Sendable {
    var isAvailable: Bool { get }
    var supportsMedicationAuthorization: Bool { get }

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func authorizationRequestStatus(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus

    // Statistics queries — return extracted numeric values
    func querySum(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double?
    func queryAverage(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double?
    func queryMin(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double?
    func queryMax(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double?
    func queryMostRecent(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double?

    // Sample queries — return value types
    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [CategorySampleValue]
    func queryWorkouts(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [WorkoutValue]
    func queryQuantitySamples(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [QuantitySampleValue]
    func queryBloodPressureSamples(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [BloodPressureSampleValue]

    // Canonical record queries — preserve HealthKit identity and provenance.
    // Results are deterministically ordered ascending and limited after that ordering.
    func queryQuantityRecords(
        identifier: HKQuantityTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord]
    func queryCategoryRecords(
        identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord]
    func queryBloodPressureRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord]
    func queryStateOfMindRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> [HealthKitRecord]
    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitMedicationRecordQueryResult

    // Compatibility summary queries retained alongside canonical records.
    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue]

    // Medications (iOS/macOS 26+) — no-op / empty on older OS
    func requestMedicationAuthorization() async throws
    func queryMedications() async throws -> [MedicationValue]
    func queryMedicationDoseEvents(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [MedicationDoseEventValue]
}

// MARK: - Default Parameters

extension HealthStoreProviding {
    /// Convenience overload — calls through with `limit: nil`.
    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool) async throws -> [CategorySampleValue] {
        try await queryCategorySamples(identifier: identifier, predicate: predicate, ascending: ascending, limit: nil)
    }

    func queryQuantityRecords(
        identifier: HKQuantityTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> [HealthKitRecord] {
        try await queryQuantityRecords(
            identifier: identifier,
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryCategoryRecords(
        identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> [HealthKitRecord] {
        try await queryCategoryRecords(
            identifier: identifier,
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryBloodPressureRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> [HealthKitRecord] {
        try await queryBloodPressureRecords(
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryStateOfMindRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> [HealthKitRecord] {
        try await queryStateOfMindRecords(
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> HealthKitMedicationRecordQueryResult {
        try await queryMedicationDoseEventRecords(
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }
}
