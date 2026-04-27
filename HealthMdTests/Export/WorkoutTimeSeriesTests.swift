//
//  WorkoutTimeSeriesTests.swift
//  HealthMdTests
//
//  Wave 2 — per-workout time-series samples (HR, pace/speed, power, cadence,
//  vertical oscillation, ground contact time, stride length, altitude).
//
//  Time-series rendering strategy:
//   • JSON   — full `timeSeries` object with arrays of {t, v} per metric.
//   • Markdown — compact summary line per metric ("Heart Rate Samples: 5").
//   • CSV    — skipped (one row per sample explodes file size; opt-in later).
//

import XCTest
import HealthKit
@testable import HealthMd

private enum WorkoutTSCustomizations {
    static let metric: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .metric
        return c
    }()
}

private enum WorkoutTSFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Build a 5-sample time-series at 60-second intervals for a metric.
    private static func samples(_ values: [Double]) -> [TimeSeriesSample] {
        values.enumerated().map { i, v in
            TimeSeriesSample(timestamp: referenceDate.addingTimeInterval(Double(i) * 60), value: v)
        }
    }

    static var richRunWithTimeSeries: HealthData {
        var data = HealthData(date: referenceDate)
        let series = WorkoutTimeSeries(
            heartRate: samples([120, 140, 155, 165, 162]),
            speed: samples([2.5, 2.7, 2.8, 2.9, 2.8]),
            power: samples([180, 220, 240, 260, 250]),
            cadence: samples([170, 175, 178, 180, 178]),
            strideLength: samples([1.10, 1.15, 1.18, 1.20, 1.19]),
            groundContactTime: samples([260, 248, 245, 240, 244]),
            verticalOscillation: samples([9.0, 8.6, 8.4, 8.2, 8.4]),
            altitude: samples([50, 70, 95, 130, 152])
        )
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 300,
                calories: 80,
                distance: 850,
                avgHeartRate: 148.4,
                timeSeries: series
            )
        ]
        return data
    }

    static var minimalRun: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 300,
                calories: 80,
                distance: 850,
                avgHeartRate: 148.4
            )
        ]
        return data
    }
}

// MARK: - JSON

final class WorkoutTimeSeriesJSONTests: XCTestCase {

    private func parseWorkout(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workouts = root["workouts"] as? [[String: Any]],
              let first = workouts.first else { return nil }
        return first
    }

    func testJSON_emitsHeartRateSeries() {
        let json = WorkoutTSFixtures.richRunWithTimeSeries.toJSON(
            customization: WorkoutTSCustomizations.metric
        )
        guard let w = parseWorkout(json),
              let series = w["timeSeries"] as? [String: Any],
              let hr = series["heartRate"] as? [[String: Any]] else {
            XCTFail("heartRate series missing: \(json)"); return
        }
        XCTAssertEqual(hr.count, 5)
        XCTAssertEqual(hr[0]["value"] as? Double, 120)
        XCTAssertEqual(hr[3]["value"] as? Double, 165)
    }

    func testJSON_emitsAllPopulatedSeries() {
        let json = WorkoutTSFixtures.richRunWithTimeSeries.toJSON(
            customization: WorkoutTSCustomizations.metric
        )
        guard let w = parseWorkout(json),
              let series = w["timeSeries"] as? [String: Any] else {
            XCTFail("timeSeries missing"); return
        }
        XCTAssertNotNil(series["heartRate"], "heartRate missing")
        XCTAssertNotNil(series["speed"], "speed missing")
        XCTAssertNotNil(series["power"], "power missing")
        XCTAssertNotNil(series["cadence"], "cadence missing")
        XCTAssertNotNil(series["strideLength"], "strideLength missing")
        XCTAssertNotNil(series["groundContactTime"], "groundContactTime missing")
        XCTAssertNotNil(series["verticalOscillation"], "verticalOscillation missing")
        XCTAssertNotNil(series["altitude"], "altitude missing")
    }

    func testJSON_omitsTimeSeriesWhenEmpty() {
        let json = WorkoutTSFixtures.minimalRun.toJSON(
            customization: WorkoutTSCustomizations.metric
        )
        guard let w = parseWorkout(json) else { XCTFail("Workout missing"); return }
        XCTAssertNil(w["timeSeries"], "timeSeries should not appear when empty")
    }

    func testJSON_eachSampleHasTimestampAndValue() {
        let json = WorkoutTSFixtures.richRunWithTimeSeries.toJSON(
            customization: WorkoutTSCustomizations.metric
        )
        guard let w = parseWorkout(json),
              let series = w["timeSeries"] as? [String: Any],
              let power = series["power"] as? [[String: Any]] else {
            XCTFail("power series missing"); return
        }
        XCTAssertNotNil(power[0]["timestamp"], "timestamp missing on sample")
        XCTAssertEqual(power[0]["value"] as? Double, 180)
    }
}

// MARK: - Markdown (compact summary)

final class WorkoutTimeSeriesMarkdownTests: XCTestCase {

    func testMarkdown_listsPopulatedSeriesAsSummary() {
        let md = WorkoutTSFixtures.richRunWithTimeSeries.toMarkdown(
            customization: WorkoutTSCustomizations.metric
        )
        // Each populated series surfaces as a concise sample-count line.
        XCTAssertTrue(md.contains("Heart Rate Samples:** 5"), "HR samples line missing: \(md)")
        XCTAssertTrue(md.contains("Power Samples:** 5"), "Power samples line missing")
        XCTAssertTrue(md.contains("Cadence Samples:** 5"), "Cadence samples line missing")
    }

    func testMarkdown_minimalRun_omitsSummary() {
        let md = WorkoutTSFixtures.minimalRun.toMarkdown(
            customization: WorkoutTSCustomizations.metric
        )
        XCTAssertFalse(md.contains("Samples:**"), "Samples summary should not appear")
    }
}

// MARK: - Pipeline (FakeHealthStore → HealthKitManager → exporters)

final class WorkoutTimeSeriesPipelineTests: XCTestCase {

    @MainActor
    func test_fakeStoreTimeSeriesPropagatesToWorkoutData() async throws {
        let store = FakeHealthStore()
        let date = HealthKitFixtures.referenceDate
        let runStart = Calendar.current.date(byAdding: .hour, value: 7,
                                             to: Calendar.current.startOfDay(for: date))!

        let hr: [TimeSeriesSample] = (0..<5).map {
            TimeSeriesSample(timestamp: runStart.addingTimeInterval(Double($0) * 60), value: 120 + Double($0) * 10)
        }
        let series = WorkoutTimeSeries(heartRate: hr)

        store.workoutResults = [
            WorkoutValue(
                activityType: HKWorkoutActivityType.running.rawValue,
                duration: 300,
                startDate: runStart,
                endDate: runStart.addingTimeInterval(300),
                totalEnergyBurned: 80,
                totalDistance: 850,
                avgHeartRate: 140,
                timeSeries: series
            )
        ]

        let mgr = HealthKitManager(store: store)
        let data = try await mgr.fetchHealthData(for: date)

        XCTAssertEqual(data.workouts.count, 1)
        let w = data.workouts[0]
        XCTAssertEqual(w.timeSeries.heartRate.count, 5, "HR series did not propagate")
        XCTAssertEqual(w.timeSeries.heartRate[0].value, 120)
        XCTAssertEqual(w.timeSeries.heartRate[4].value, 160)
    }
}
