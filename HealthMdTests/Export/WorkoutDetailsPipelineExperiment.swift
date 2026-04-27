//
//  WorkoutDetailsPipelineExperiment.swift
//  HealthMdTests
//
//  End-to-end "experiment" that drives the full pipeline:
//    FakeHealthStore (rich workouts) → HealthKitManager.fetchHealthData
//      → HealthData.toMarkdown / toCSV / toJSON / toObsidianBases
//
//  This is the closest equivalent to running the app on a simulator with
//  populated HealthKit workouts. It exercises the same code path the
//  production SystemHealthStoreAdapter feeds, only with deterministic data.
//
//  The test prints the full output of each of the four formats so the
//  rendered exports can be inspected from `xcodebuild test` logs.
//

import XCTest
import HealthKit
@testable import HealthMd

final class WorkoutDetailsPipelineExperiment: XCTestCase {

    @MainActor
    func test_pipeline_richRunAndRide_producesExportsForAllFourFormats() async throws {
        let store = FakeHealthStore()
        let date = HealthKitFixtures.referenceDate
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let runStart = calendar.date(byAdding: .hour, value: 7, to: startOfDay)!
        let rideStart = calendar.date(byAdding: .hour, value: 17, to: startOfDay)!

        // Rich running workout — HR + full running form metrics.
        let run = WorkoutValue(
            activityType: HKWorkoutActivityType.running.rawValue,
            duration: 1800,
            startDate: runStart,
            endDate: runStart.addingTimeInterval(1800),
            totalEnergyBurned: 320,
            totalDistance: 5000,
            avgHeartRate: 162.4,
            maxHeartRate: 178.0,
            minHeartRate: 96.0,
            avgRunningCadence: 178.6,
            avgStrideLength: 1.18,
            avgGroundContactTime: 245.0,
            avgVerticalOscillation: 8.4,
            avgPower: 240.0,
            maxPower: 312.0
        )

        // Rich cycling workout — HR + cycling cadence + power.
        let ride = WorkoutValue(
            activityType: HKWorkoutActivityType.cycling.rawValue,
            duration: 3600,
            startDate: rideStart,
            endDate: rideStart.addingTimeInterval(3600),
            totalEnergyBurned: 540,
            totalDistance: 25_000,
            avgHeartRate: 145.0,
            maxHeartRate: 172.0,
            minHeartRate: 110.0,
            avgCyclingCadence: 85.0,
            avgPower: 195.0,
            maxPower: 410.0
        )

        store.workoutResults = [run, ride]

        let sut = HealthKitManager(store: store)
        let data = try await sut.fetchHealthData(for: date)

        // Pipeline assertions — workouts mapped through correctly.
        XCTAssertEqual(data.workouts.count, 2)
        let mappedRun = data.workouts[0]
        XCTAssertEqual(mappedRun.workoutType, .running)
        XCTAssertEqual(mappedRun.avgHeartRate, 162.4)
        XCTAssertEqual(mappedRun.maxHeartRate, 178.0)
        XCTAssertEqual(mappedRun.avgRunningCadence, 178.6)
        XCTAssertEqual(mappedRun.avgStrideLength, 1.18)
        XCTAssertEqual(mappedRun.avgPower, 240.0)
        XCTAssertEqual(mappedRun.maxPower, 312.0)

        let mappedRide = data.workouts[1]
        XCTAssertEqual(mappedRide.workoutType, .cycling)
        XCTAssertEqual(mappedRide.avgCyclingCadence, 85.0)
        XCTAssertEqual(mappedRide.avgPower, 195.0)
        XCTAssertNil(mappedRide.avgRunningCadence)
        XCTAssertNil(mappedRide.avgStrideLength)

        // Render all four formats. Print so they're readable in test logs.
        let customization = FormatCustomization()
        customization.unitPreference = .metric

        let md = data.toMarkdown(customization: customization)
        let csv = data.toCSV(customization: customization)
        let json = data.toJSON(customization: customization)
        let bases = data.toObsidianBases(customization: customization)

        print("\n========== EXPERIMENT: MARKDOWN ==========")
        print(md)
        print("\n========== EXPERIMENT: CSV ==========")
        print(csv)
        print("\n========== EXPERIMENT: JSON ==========")
        print(json)
        print("\n========== EXPERIMENT: OBSIDIAN BASES ==========")
        print(bases)
        print("==========================================\n")

        // Sanity — markdown contains the headline running and cycling fields.
        XCTAssertTrue(md.contains("Avg Heart Rate:** 162 bpm"))
        XCTAssertTrue(md.contains("Avg Pace:** 6:00 /km"))       // running
        XCTAssertTrue(md.contains("Avg Speed:** 25.0 km/h"))     // cycling
        XCTAssertTrue(md.contains("Avg Cadence:** 179 spm"))     // running
        XCTAssertTrue(md.contains("Avg Cadence:** 85 rpm"))      // cycling
        XCTAssertTrue(md.contains("Max Power:** 312 W"))         // run
        XCTAssertTrue(md.contains("Max Power:** 410 W"))         // ride

        // Obsidian Bases aggregates across both workouts.
        // Weighted avg HR: (1800*162.4 + 3600*145) / 5400 = 150.8 → "151"
        XCTAssertTrue(bases.contains("workout_avg_heart_rate: 151"), "Pipeline avg HR aggregate wrong: \(bases)")
        // max-of-maxes: max(178, 172) = 178
        XCTAssertTrue(bases.contains("workout_max_heart_rate: 178"))
        // Running-only aggregates appear since one run exists.
        XCTAssertTrue(bases.contains("workout_running_cadence: 179"))
        XCTAssertTrue(bases.contains("workout_running_stride_length: 1.18"))
        // Cycling-only aggregate.
        XCTAssertTrue(bases.contains("workout_cycling_cadence: 85"))
        // Power aggregates across both. Weighted avg: (1800*240 + 3600*195) / 5400 = 210
        XCTAssertTrue(bases.contains("workout_avg_power: 210"))
        XCTAssertTrue(bases.contains("workout_max_power: 410"))
    }
}
