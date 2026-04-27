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
}

/// Represents a quantity sample (e.g., individual heart rate reading).
struct QuantitySampleValue: Sendable {
    let value: Double
    let startDate: Date
    let endDate: Date
}

/// Represents a workout summary.
struct WorkoutValue: Sendable {
    let activityType: UInt
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date
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

    init(
        activityType: UInt,
        duration: TimeInterval,
        startDate: Date,
        endDate: Date,
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
        maxPower: Double? = nil
    ) {
        self.activityType = activityType
        self.duration = duration
        self.startDate = startDate
        self.endDate = endDate
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
    }
}

/// Represents a State of Mind sample (iOS 18+).
/// Labels and associations are pre-mapped to display strings by the adapter.
struct StateOfMindSampleValue: Sendable {
    let kind: String              // "momentaryEmotion" or "dailyMood"
    let valence: Double           // -1.0 to 1.0
    let labels: [String]          // e.g. ["Happy", "Grateful"]
    let associations: [String]    // e.g. ["Family", "Fitness"]
    let startDate: Date
}

// MARK: - HealthStore Protocol

/// Abstracts HealthKit store operations used by HealthKitManager.
/// Production code uses SystemHealthStoreAdapter; tests use FakeHealthStore.
protocol HealthStoreProviding: Sendable {
    var isAvailable: Bool { get }

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws

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

    // State of Mind (iOS 18+) — returns empty on older OS
    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue]
}

// MARK: - Default Parameters

extension HealthStoreProviding {
    /// Convenience overload — calls through with `limit: nil`.
    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool) async throws -> [CategorySampleValue] {
        try await queryCategorySamples(identifier: identifier, predicate: predicate, ascending: ascending, limit: nil)
    }
}
