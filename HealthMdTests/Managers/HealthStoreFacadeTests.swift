//
//  HealthStoreFacadeTests.swift
//  HealthMdTests
//
//  TDD tests for the HealthKit query facade protocol.
//  Validates that fake implementations can drive deterministic tests.
//

import XCTest
import HealthKit
@testable import HealthMd

// MARK: - Fake Implementation

final class FakeHealthStore: HealthStoreProviding {
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

    var isAvailable: Bool { available }

    func requestAuth(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        if let error = shouldThrowOnAuth { throw error }
        authRequested = true
    }

    func querySum(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        statisticsSums[identifier.rawValue]
    }

    func queryAverage(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        statisticsAverages[identifier.rawValue]
    }

    func queryMin(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        statisticsMins[identifier.rawValue]
    }

    func queryMax(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        statisticsMaxes[identifier.rawValue]
    }

    func queryMostRecent(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?) async throws -> Double? {
        statisticsMostRecent[identifier.rawValue]
    }

    func queryCategorySamples(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, ascending: Bool) async throws -> [CategorySampleValue] {
        let results = categorySampleResults[identifier.rawValue] ?? []
        return ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
    }

    func queryWorkouts(predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [WorkoutValue] {
        var results = ascending ? workoutResults.sorted { $0.startDate < $1.startDate } : workoutResults.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func queryQuantitySamples(identifier: HKQuantityTypeIdentifier, predicate: NSPredicate?, ascending: Bool, limit: Int?) async throws -> [QuantitySampleValue] {
        var results = quantitySampleResults[identifier.rawValue] ?? []
        results = ascending ? results.sorted { $0.startDate < $1.startDate } : results.sorted { $0.startDate > $1.startDate }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }
}

// MARK: - HealthStoreProviding Protocol Tests

final class HealthStoreFacadeTests: XCTestCase {

    func testFakeStore_isAvailableDefault() {
        let store = FakeHealthStore()
        XCTAssertTrue(store.isAvailable)
    }

    func testFakeStore_isAvailableCanBeDisabled() {
        let store = FakeHealthStore()
        store.available = false
        XCTAssertFalse(store.isAvailable)
    }

    func testFakeStore_authorizationRequested() async throws {
        let store = FakeHealthStore()
        try await store.requestAuth(toShare: [], read: [])
        XCTAssertTrue(store.authRequested)
    }

    func testFakeStore_authorizationThrows() async {
        let store = FakeHealthStore()
        store.shouldThrowOnAuth = NSError(domain: "HK", code: 1)

        do {
            try await store.requestAuth(toShare: [], read: [])
            XCTFail("Expected error")
        } catch {
            XCTAssertFalse(store.authRequested)
        }
    }

    // MARK: - Statistics Queries

    func testFakeStore_querySumReturnsConfiguredValue() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 8500

        let result = try await store.querySum(identifier: .stepCount, predicate: nil)
        XCTAssertEqual(result, 8500)
    }

    func testFakeStore_querySumReturnsNilWhenNotConfigured() async throws {
        let store = FakeHealthStore()
        let result = try await store.querySum(identifier: .stepCount, predicate: nil)
        XCTAssertNil(result)
    }

    func testFakeStore_queryAverageReturnsConfiguredValue() async throws {
        let store = FakeHealthStore()
        store.statisticsAverages[HKQuantityTypeIdentifier.heartRate.rawValue] = 72.5

        let result = try await store.queryAverage(identifier: .heartRate, predicate: nil)
        XCTAssertEqual(result, 72.5)
    }

    func testFakeStore_queryMinMaxReturnConfiguredValues() async throws {
        let store = FakeHealthStore()
        store.statisticsMins[HKQuantityTypeIdentifier.heartRate.rawValue] = 55.0
        store.statisticsMaxes[HKQuantityTypeIdentifier.heartRate.rawValue] = 145.0

        let min = try await store.queryMin(identifier: .heartRate, predicate: nil)
        let max = try await store.queryMax(identifier: .heartRate, predicate: nil)
        XCTAssertEqual(min, 55.0)
        XCTAssertEqual(max, 145.0)
    }

    // MARK: - Category Sample Queries

    func testFakeStore_categorySamplesReturnConfiguredValues() async throws {
        let store = FakeHealthStore()
        let now = Date()
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: 3, startDate: now, endDate: now.addingTimeInterval(3600)),
            CategorySampleValue(value: 4, startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
        ]

        let results = try await store.queryCategorySamples(identifier: .sleepAnalysis, predicate: nil, ascending: true)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].value, 3)
        XCTAssertEqual(results[1].value, 4)
    }

    func testFakeStore_categorySamplesEmptyByDefault() async throws {
        let store = FakeHealthStore()
        let results = try await store.queryCategorySamples(identifier: .sleepAnalysis, predicate: nil, ascending: true)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Workout Queries

    func testFakeStore_workoutsReturnConfiguredValues() async throws {
        let store = FakeHealthStore()
        let now = Date()
        store.workoutResults = [
            WorkoutValue(activityType: HKWorkoutActivityType.running.rawValue, duration: 1800, startDate: now, endDate: now.addingTimeInterval(1800), totalEnergyBurned: 300, totalDistance: 5000)
        ]

        let results = try await store.queryWorkouts(predicate: nil, ascending: true, limit: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].activityType, HKWorkoutActivityType.running.rawValue)
        XCTAssertEqual(results[0].duration, 1800)
        XCTAssertEqual(results[0].totalDistance, 5000)
    }

    func testFakeStore_workoutsRespectsLimit() async throws {
        let store = FakeHealthStore()
        let now = Date()
        store.workoutResults = [
            WorkoutValue(activityType: 1, duration: 100, startDate: now, endDate: now.addingTimeInterval(100), totalEnergyBurned: nil, totalDistance: nil),
            WorkoutValue(activityType: 2, duration: 200, startDate: now.addingTimeInterval(200), endDate: now.addingTimeInterval(400), totalEnergyBurned: nil, totalDistance: nil),
            WorkoutValue(activityType: 3, duration: 300, startDate: now.addingTimeInterval(500), endDate: now.addingTimeInterval(800), totalEnergyBurned: nil, totalDistance: nil)
        ]

        let results = try await store.queryWorkouts(predicate: nil, ascending: true, limit: 2)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Quantity Sample Queries

    func testFakeStore_quantitySamplesReturnConfiguredValues() async throws {
        let store = FakeHealthStore()
        let now = Date()
        store.quantitySampleResults[HKQuantityTypeIdentifier.heartRate.rawValue] = [
            QuantitySampleValue(value: 72, startDate: now, endDate: now),
            QuantitySampleValue(value: 85, startDate: now.addingTimeInterval(60), endDate: now.addingTimeInterval(60))
        ]

        let results = try await store.queryQuantitySamples(identifier: .heartRate, predicate: nil, ascending: true, limit: nil)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].value, 72)
    }

    // MARK: - Production Adapter Conformance

    func testSystemHealthStore_conformsToProtocol() {
        let _: HealthStoreProviding = SystemHealthStoreAdapter()
    }
}
