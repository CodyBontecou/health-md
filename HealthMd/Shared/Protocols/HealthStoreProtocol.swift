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

import Foundation
import HealthKit

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
    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool) async throws -> [CategorySampleValue]
    func queryWorkouts(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [WorkoutValue]
    func queryQuantitySamples(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [QuantitySampleValue]
}
