//
//  FakeHealthStore.swift
//  HealthMdTests
//
//  Shared deterministic fake for HealthStoreProviding.
//  Used by all HealthKitManager test files.
//

import XCTest
import HealthKit
@testable import HealthMd

final class FakeHealthStore: HealthStoreProviding, @unchecked Sendable {
    var available = true
    var authRequested = false
    var shouldThrowOnAuth: Error?

    // Pre-configured statistics results keyed by HKQuantityTypeIdentifier raw value
    var statisticsSums: [String: Double] = [:]
    var statisticsAverages: [String: Double] = [:]
    var statisticsMins: [String: Double] = [:]
    var statisticsMaxes: [String: Double] = [:]
    var statisticsMostRecent: [String: Double] = [:]

    // Pre-configured category sample results
    var categorySampleResults: [String: [CategorySampleValue]] = [:]

    // Pre-configured workout results
    var workoutResults: [WorkoutValue] = []

    // Pre-configured quantity sample results
    var quantitySampleResults: [String: [QuantitySampleValue]] = [:]

    // Pre-configured State of Mind results
    var stateOfMindResults: [StateOfMindSampleValue] = []
    var errorForStateOfMind: Error?

    // Per-query error simulation keyed by identifier raw value
    var errorsForSum: [String: Error] = [:]
    var errorsForAverage: [String: Error] = [:]
    var errorsForMin: [String: Error] = [:]
    var errorsForMax: [String: Error] = [:]
    var errorsForMostRecent: [String: Error] = [:]
    var errorsForCategorySamples: [String: Error] = [:]
    var errorsForQuantitySamples: [String: Error] = [:]
    var errorForWorkouts: Error?

    // Tracking
    var queriedSumIdentifiers: [String] = []
    var queriedAverageIdentifiers: [String] = []
    var queriedCategoryIdentifiers: [String] = []

    var isAvailable: Bool { available }

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        if let error = shouldThrowOnAuth { throw error }
        authRequested = true
    }

    func querySum(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        queriedSumIdentifiers.append(identifier.rawValue)
        if let error = errorsForSum[identifier.rawValue] { throw error }
        return statisticsSums[identifier.rawValue]
    }

    func queryAverage(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        queriedAverageIdentifiers.append(identifier.rawValue)
        if let error = errorsForAverage[identifier.rawValue] { throw error }
        return statisticsAverages[identifier.rawValue]
    }

    func queryMin(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        if let error = errorsForMin[identifier.rawValue] { throw error }
        return statisticsMins[identifier.rawValue]
    }

    func queryMax(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        if let error = errorsForMax[identifier.rawValue] { throw error }
        return statisticsMaxes[identifier.rawValue]
    }

    func queryMostRecent(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        if let error = errorsForMostRecent[identifier.rawValue] { throw error }
        return statisticsMostRecent[identifier.rawValue]
    }

    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [CategorySampleValue] {
        queriedCategoryIdentifiers.append(identifier.rawValue)
        if let error = errorsForCategorySamples[identifier.rawValue] { throw error }
        var results = categorySampleResults[identifier.rawValue] ?? []
        results = ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryWorkouts(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [WorkoutValue] {
        if let error = errorForWorkouts { throw error }
        var results = ascending ? workoutResults.sorted { $0.startDate < $1.startDate } : workoutResults.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryQuantitySamples(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [QuantitySampleValue] {
        if let error = errorsForQuantitySamples[identifier.rawValue] { throw error }
        var results = quantitySampleResults[identifier.rawValue] ?? []
        results = ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryStateOfMind(predicate: NSPredicate?) async throws -> [StateOfMindSampleValue] {
        if let error = errorForStateOfMind { throw error }
        return stateOfMindResults
    }
}
