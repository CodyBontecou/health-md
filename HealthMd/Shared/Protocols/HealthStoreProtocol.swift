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
nonisolated struct CategorySampleValue: Sendable {
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
nonisolated struct QuantitySampleValue: Sendable {
    let uuid: UUID?
    let value: Double
    let startDate: Date
    let endDate: Date
    let metadata: [String: String]

    init(
        uuid: UUID? = nil,
        value: Double,
        startDate: Date,
        endDate: Date,
        metadata: [String: String] = [:]
    ) {
        self.uuid = uuid
        self.value = value
        self.startDate = startDate
        self.endDate = endDate
        self.metadata = metadata
    }
}

/// Represents one paired blood pressure reading from a HealthKit correlation.
/// Keeping the components together prevents independently queried systolic and
/// diastolic values from being combined into a reading that never occurred.
nonisolated struct BloodPressureSampleValue: Sendable {
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
nonisolated struct WorkoutLap: Sendable, Codable, Equatable {
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
}

/// A single auto-distance split derived from the route + HR samples by the adapter.
/// Distances are stored in meters; renderers format pace/speed using the user's unit preference.
nonisolated struct WorkoutSplit: Sendable, Codable, Equatable {
    let index: Int
    let startDate: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let avgHeartRate: Double?
}

/// A single per-second sample of a workout time-series metric.
nonisolated struct TimeSeriesSample: Sendable, Codable, Equatable {
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
nonisolated struct WorkoutTimeSeries: Sendable, Codable, Equatable {
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
nonisolated struct RoutePoint: Sendable, Codable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let speedMps: Double?
    let courseDegrees: Double?
    let horizontalAccuracyMeters: Double?
}

/// A transient reference to the exact HealthKit object that produced a retained
/// canonical record. It never enters the portable archive. Production queries pass
/// the original object through so attachment capture does not reconstruct or
/// fabricate parents; protocol fakes may leave `sourceObject` nil.
struct HealthKitAttachmentParentReference: @unchecked Sendable {
    let parentUUID: UUID
    let objectTypeIdentifier: String
    let sourceObject: HKObject?
    let metricAttribution: HealthKitMetricAttribution?

    init(
        parentUUID: UUID,
        objectTypeIdentifier: String,
        sourceObject: HKObject? = nil,
        metricAttribution: HealthKitMetricAttribution? = nil
    ) {
        self.parentUUID = parentUUID
        self.objectTypeIdentifier = objectTypeIdentifier
        self.sourceObject = sourceObject
        self.metricAttribution = metricAttribution
    }

    init(object: HKSample, metricAttribution: HealthKitMetricAttribution? = nil) {
        self.init(
            parentUUID: object.uuid,
            objectTypeIdentifier: object.sampleType.identifier,
            sourceObject: object,
            metricAttribution: metricAttribution
        )
    }
}

struct HealthKitAttachmentParentRelationship: Sendable, Equatable {
    let parentUUID: UUID
    let relationship: HealthKitRecordRelationship
}

/// Deterministic output from the one post-capture attachment sweep.
struct HealthKitAttachmentQueryResult: Sendable {
    let records: [HealthKitExternalRecord]
    let parentRelationships: [HealthKitAttachmentParentRelationship]
    let queryResults: [HealthKitQueryResult]
    let integrityWarnings: [HealthKitRecordIntegrityWarning]

    init(
        records: [HealthKitExternalRecord] = [],
        parentRelationships: [HealthKitAttachmentParentRelationship] = [],
        queryResults: [HealthKitQueryResult] = [],
        integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    ) {
        var recordsByIdentifier: [String: HealthKitExternalRecord] = [:]
        for record in HealthKitExternalRecord.sortedDeterministically(records) {
            if let existing = recordsByIdentifier[record.externalIdentifier] {
                recordsByIdentifier[record.externalIdentifier] = existing.mergingRepeatedView(record)
            } else {
                recordsByIdentifier[record.externalIdentifier] = record
            }
        }
        self.records = HealthKitExternalRecord.sortedDeterministically(Array(recordsByIdentifier.values))
        var uniqueRelationships: [HealthKitAttachmentParentRelationship] = []
        for relationship in parentRelationships where !uniqueRelationships.contains(relationship) {
            uniqueRelationships.append(relationship)
        }
        self.parentRelationships = uniqueRelationships.sorted {
            if $0.parentUUID != $1.parentUUID {
                return $0.parentUUID.uuidString < $1.parentUUID.uuidString
            }
            let lhsTarget = $0.relationship.targetUUID?.uuidString
                ?? $0.relationship.targetExternalIdentifier ?? ""
            let rhsTarget = $1.relationship.targetUUID?.uuidString
                ?? $1.relationship.targetExternalIdentifier ?? ""
            if $0.relationship.kind != $1.relationship.kind {
                return $0.relationship.kind < $1.relationship.kind
            }
            if $0.relationship.role != $1.relationship.role {
                return $0.relationship.role < $1.relationship.role
            }
            return lhsTarget < rhsTarget
        }
        self.queryResults = queryResults.sorted {
            if $0.interval.startDate != $1.interval.startDate { return $0.interval.startDate < $1.interval.startDate }
            if $0.interval.endDate != $1.interval.endDate { return $0.interval.endDate < $1.interval.endDate }
            if $0.operation != $1.operation { return $0.operation < $1.operation }
            return $0.identifier < $1.identifier
        }
        self.integrityWarnings = integrityWarnings.sorted {
            if $0.code != $1.code { return $0.code < $1.code }
            if $0.message != $1.message { return $0.message < $1.message }
            if $0.metricIDs != $1.metricIDs {
                return $0.metricIDs.lexicographicallyPrecedes($1.metricIDs)
            }
            return $0.recordUUIDs.map(\.uuidString).lexicographicallyPrecedes(
                $1.recordUUIDs.map(\.uuidString)
            )
        }
    }
}

/// Parent canonical records plus independently isolated child-series diagnostics.
/// `parentRecordCount` is kept separate because correlation queries also return
/// component records and manifest counts must continue to count parents only.
struct HealthKitCanonicalRecordQueryResult: Sendable, RandomAccessCollection {
    typealias Index = Int

    let records: [HealthKitRecord]
    let parentRecordCount: Int
    let attachmentParents: [HealthKitAttachmentParentReference]
    let childQueryFailures: [HealthKitQueryResult]
    let integrityWarnings: [HealthKitRecordIntegrityWarning]

    init(
        records: [HealthKitRecord] = [],
        parentRecordCount: Int? = nil,
        attachmentParents: [HealthKitAttachmentParentReference] = [],
        childQueryFailures: [HealthKitQueryResult] = [],
        integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    ) {
        self.records = HealthKitRecord.sortedDeterministically(records)
        self.parentRecordCount = parentRecordCount ?? records.count
        self.attachmentParents = attachmentParents.sorted {
            if $0.objectTypeIdentifier != $1.objectTypeIdentifier {
                return $0.objectTypeIdentifier < $1.objectTypeIdentifier
            }
            return $0.parentUUID.uuidString < $1.parentUUID.uuidString
        }
        self.childQueryFailures = childQueryFailures
            .filter { $0.status == .failure || $0.status == .cancelled }
            .sorted(by: Self.queryResultSort)
        self.integrityWarnings = integrityWarnings.sorted { lhs, rhs in
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            if lhs.message != rhs.message { return lhs.message < rhs.message }
            return lhs.recordUUIDs.map(\.uuidString).lexicographicallyPrecedes(
                rhs.recordUUIDs.map(\.uuidString)
            )
        }
    }

    var startIndex: Int { records.startIndex }
    var endIndex: Int { records.endIndex }
    subscript(position: Int) -> HealthKitRecord { records[position] }

    nonisolated private static func queryResultSort(_ lhs: HealthKitQueryResult, _ rhs: HealthKitQueryResult) -> Bool {
        if lhs.interval.startDate != rhs.interval.startDate {
            return lhs.interval.startDate < rhs.interval.startDate
        }
        if lhs.interval.endDate != rhs.interval.endDate {
            return lhs.interval.endDate < rhs.interval.endDate
        }
        if lhs.operation != rhs.operation { return lhs.operation < rhs.operation }
        return lhs.identifier < rhs.identifier
    }
}

/// Result of the specialized canonical workout graph query.
///
/// Child failures are ordinary manifest results so route and statistic-sample
/// failures remain attributable to the exact workout/type instead of being
/// flattened into a successful empty result.
struct HealthKitWorkoutRecordQueryResult: Sendable {
    let records: [HealthKitRecord]
    let externalRecords: [HealthKitExternalRecord]
    let attachmentParents: [HealthKitAttachmentParentReference]
    /// Includes success-independent child diagnostics such as unavailable effort
    /// relationship APIs. Callers must not turn an unsupported child into an
    /// apparently complete workout graph.
    let childQueryResults: [HealthKitQueryResult]
    let integrityWarnings: [HealthKitRecordIntegrityWarning]

    var childQueryFailures: [HealthKitQueryResult] {
        childQueryResults.filter { $0.status == .failure || $0.status == .cancelled }
    }

    init(
        records: [HealthKitRecord] = [],
        externalRecords: [HealthKitExternalRecord] = [],
        attachmentParents: [HealthKitAttachmentParentReference] = [],
        childQueryFailures: [HealthKitQueryResult] = [],
        childQueryResults: [HealthKitQueryResult] = [],
        integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    ) {
        self.records = HealthKitRecord.sortedDeterministically(records)
        self.externalRecords = HealthKitExternalRecord.sortedDeterministically(externalRecords)
        self.attachmentParents = attachmentParents.sorted {
            if $0.objectTypeIdentifier != $1.objectTypeIdentifier {
                return $0.objectTypeIdentifier < $1.objectTypeIdentifier
            }
            return $0.parentUUID.uuidString < $1.parentUUID.uuidString
        }
        self.childQueryResults = (childQueryFailures + childQueryResults).sorted {
            if $0.interval.startDate != $1.interval.startDate {
                return $0.interval.startDate < $1.interval.startDate
            }
            if $0.operation != $1.operation { return $0.operation < $1.operation }
            return $0.identifier < $1.identifier
        }
        self.integrityWarnings = Self.sortedWarnings(integrityWarnings)
    }

    static func sortedWarnings(
        _ warnings: [HealthKitRecordIntegrityWarning]
    ) -> [HealthKitRecordIntegrityWarning] {
        warnings.sorted { lhs, rhs in
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            if lhs.message != rhs.message { return lhs.message < rhs.message }
            return lhs.recordUUIDs.map(\.uuidString).lexicographicallyPrecedes(
                rhs.recordUUIDs.map(\.uuidString)
            )
        }
    }
}

/// UUID-free WorkoutKit schedule values and an honest public-read status.
/// The scheduler is never authorized from an export query; `.skipped` means the
/// app deliberately avoided prompting or mutating the user's schedule.
struct HealthKitScheduledWorkoutPlanQueryResult: Sendable {
    let externalRecords: [HealthKitExternalRecord]
    let status: HealthKitQueryResultStatus
    let statusDescription: String?
    let childQueryResults: [HealthKitQueryResult]
    let integrityWarnings: [HealthKitRecordIntegrityWarning]

    init(
        externalRecords: [HealthKitExternalRecord] = [],
        status: HealthKitQueryResultStatus = .success,
        statusDescription: String? = nil,
        childQueryResults: [HealthKitQueryResult] = [],
        integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    ) {
        self.externalRecords = HealthKitExternalRecord.sortedDeterministically(externalRecords)
        self.status = status
        self.statusDescription = statusDescription
        self.childQueryResults = childQueryResults.sorted {
            if $0.operation != $1.operation { return $0.operation < $1.operation }
            return $0.identifier < $1.identifier
        }
        self.integrityWarnings = HealthKitWorkoutRecordQueryResult.sortedWarnings(integrityWarnings)
    }
}

/// Deterministic result of the single specialized source-record query path.
/// Parent object failures and child series/waveform failures are separated so
/// one malformed ECG or heartbeat series never erases successful siblings.
struct HealthKitSpecializedRecordQueryResult: Sendable {
    let records: [HealthKitRecord]
    let externalRecords: [HealthKitExternalRecord]
    let attachmentParents: [HealthKitAttachmentParentReference]
    let recordQueryResults: [HealthKitQueryResult]
    let childQueryFailures: [HealthKitQueryResult]
    let integrityWarnings: [HealthKitRecordIntegrityWarning]

    init(
        records: [HealthKitRecord] = [],
        externalRecords: [HealthKitExternalRecord] = [],
        attachmentParents: [HealthKitAttachmentParentReference] = [],
        recordQueryResults: [HealthKitQueryResult] = [],
        childQueryFailures: [HealthKitQueryResult] = [],
        integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    ) {
        self.records = HealthKitRecord.sortedDeterministically(records)
        self.externalRecords = HealthKitExternalRecord.sortedDeterministically(externalRecords)
        self.attachmentParents = attachmentParents.sorted {
            if $0.objectTypeIdentifier != $1.objectTypeIdentifier {
                return $0.objectTypeIdentifier < $1.objectTypeIdentifier
            }
            return $0.parentUUID.uuidString < $1.parentUUID.uuidString
        }
        self.recordQueryResults = recordQueryResults.sorted(by: Self.queryResultSort)
        self.childQueryFailures = childQueryFailures
            .filter { $0.status == .failure }
            .sorted(by: Self.queryResultSort)
        self.integrityWarnings = integrityWarnings.sorted { lhs, rhs in
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            if lhs.message != rhs.message { return lhs.message < rhs.message }
            if lhs.metricIDs != rhs.metricIDs {
                return lhs.metricIDs.lexicographicallyPrecedes(rhs.metricIDs)
            }
            return lhs.recordUUIDs.map(\.uuidString).lexicographicallyPrecedes(
                rhs.recordUUIDs.map(\.uuidString)
            )
        }
    }

    nonisolated private static func queryResultSort(
        _ lhs: HealthKitQueryResult,
        _ rhs: HealthKitQueryResult
    ) -> Bool {
        if lhs.interval.startDate != rhs.interval.startDate {
            return lhs.interval.startDate < rhs.interval.startDate
        }
        if lhs.interval.endDate != rhs.interval.endDate {
            return lhs.interval.endDate < rhs.interval.endDate
        }
        if lhs.operation != rhs.operation { return lhs.operation < rhs.operation }
        return lhs.identifier < rhs.identifier
    }
}

/// Represents a workout summary.
struct WorkoutValue: Sendable {
    /// Original HealthKit object identity. Nil only for legacy/test values that
    /// predate canonical workout capture.
    let sourceUUID: UUID?
    let activityType: UInt
    let duration: TimeInterval
    let startDate: Date
    /// Actual HealthKit end date (elapsed end, independent of active duration).
    let actualEndDate: Date
    /// Compatibility alias retained for existing summary callers.
    var endDate: Date { actualEndDate }
    let sourceRevision: HealthKitSourceRevision?
    let device: HealthKitDeviceProvenance?
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
        sourceUUID: UUID? = nil,
        activityType: UInt,
        duration: TimeInterval,
        startDate: Date,
        endDate: Date,
        sourceRevision: HealthKitSourceRevision? = nil,
        device: HealthKitDeviceProvenance? = nil,
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
        self.sourceUUID = sourceUUID
        self.activityType = activityType
        self.duration = duration
        self.startDate = startDate
        self.actualEndDate = endDate
        self.sourceRevision = sourceRevision
        self.device = device
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
    let conceptDomain: String
    /// Public NSSecureCoding representation when HealthKit exposes no clinical coding.
    let conceptIdentifierArchive: Data?
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
        conceptDomain: String = "HKHealthConceptDomainMedication",
        conceptIdentifierArchive: Data? = nil,
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
        self.conceptDomain = conceptDomain
        self.conceptIdentifierArchive = conceptIdentifierArchive
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
    let attachmentParents: [HealthKitAttachmentParentReference]
    /// Dose events and authorized inventory are independent public queries. A
    /// failed sibling is explicit here while successful sibling data survives.
    let childQueryResults: [HealthKitQueryResult]

    init(
        records: [HealthKitRecord] = [],
        inventoryRecords: [HealthKitMedicationInventoryRecord] = [],
        attachmentParents: [HealthKitAttachmentParentReference] = [],
        childQueryResults: [HealthKitQueryResult] = []
    ) {
        self.records = HealthKitRecord.sortedDeterministically(records)
        self.inventoryRecords = inventoryRecords.sorted {
            if $0.externalIdentifier != $1.externalIdentifier {
                return $0.externalIdentifier < $1.externalIdentifier
            }
            return ($0.displayName ?? "") < ($1.displayName ?? "")
        }
        self.attachmentParents = attachmentParents.sorted {
            if $0.objectTypeIdentifier != $1.objectTypeIdentifier {
                return $0.objectTypeIdentifier < $1.objectTypeIdentifier
            }
            return $0.parentUUID.uuidString < $1.parentUUID.uuidString
        }
        self.childQueryResults = childQueryResults.sorted {
            if $0.operation != $1.operation { return $0.operation < $1.operation }
            return $0.identifier < $1.identifier
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
    var supportsHealthRecords: Bool { get }
    var supportsCDADocuments: Bool { get }
    var supportsVerifiableClinicalRecords: Bool { get }
    var supportsVisionPrescriptionAuthorization: Bool { get }
    var supportsMedicationAuthorization: Bool { get }
    var supportsScheduledWorkoutPlans: Bool { get }

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
    ) async throws -> HealthKitCanonicalRecordQueryResult
    func queryCategoryRecords(
        identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult
    func queryBloodPressureRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult
    func queryFoodRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult
    func queryStateOfMindRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitCanonicalRecordQueryResult
    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String],
        includeInventory: Bool,
        limit: Int?
    ) async throws -> HealthKitMedicationRecordQueryResult
    func queryWorkoutRecords(
        predicate: NSPredicate?,
        associatedSampleEntries: [HealthKitRecordSelectionPlanEntry],
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitWorkoutRecordQueryResult
    func queryScheduledWorkoutPlanRecords(
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String]
    ) async -> HealthKitScheduledWorkoutPlanQueryResult
    func querySpecializedRecords(
        predicate: NSPredicate?,
        entries: [HealthKitRecordSelectionPlanEntry],
        interval: HealthKitQueryInterval,
        limit: Int?
    ) async -> HealthKitSpecializedRecordQueryResult

    /// Runs once after canonical parent capture. Implementations must isolate
    /// metadata and byte-stream failures per parent/attachment.
    func queryAttachmentRecords(
        parents: [HealthKitAttachmentParentReference],
        interval: HealthKitQueryInterval
    ) async -> HealthKitAttachmentQueryResult

    // Compatibility summary queries retained alongside canonical records.
    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue]

    // Special user-selection authorization. Vision uses HealthKit's per-object
    // selector; CDA and verifiable records authorize as part of their exact query.
    func requestVisionPrescriptionAuthorization(predicate: NSPredicate?) async throws

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
    ) async throws -> HealthKitCanonicalRecordQueryResult {
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
    ) async throws -> HealthKitCanonicalRecordQueryResult {
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
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        try await queryBloodPressureRecords(
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryFoodRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        try await queryFoodRecords(
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryStateOfMindRecords(
        predicate: NSPredicate?,
        selectedMetricIDs: [String]
    ) async throws -> HealthKitCanonicalRecordQueryResult {
        try await queryStateOfMindRecords(
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: nil
        )
    }

    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String],
        limit: Int?
    ) async throws -> HealthKitMedicationRecordQueryResult {
        try await queryMedicationDoseEventRecords(
            predicate: predicate,
            interval: interval,
            selectedMetricIDs: selectedMetricIDs,
            includeInventory: true,
            limit: limit
        )
    }

    func queryMedicationDoseEventRecords(
        predicate: NSPredicate?,
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String]
    ) async throws -> HealthKitMedicationRecordQueryResult {
        try await queryMedicationDoseEventRecords(
            predicate: predicate,
            interval: interval,
            selectedMetricIDs: selectedMetricIDs,
            includeInventory: true,
            limit: nil
        )
    }
}
