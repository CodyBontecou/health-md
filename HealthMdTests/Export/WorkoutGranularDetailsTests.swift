//
//  WorkoutGranularDetailsTests.swift
//  HealthMdTests
//
//  Wave 1 — per-workout laps, splits, GPS route, and elevation gain.
//  Mirrors the patterns in WorkoutDetailsExportTests: directly construct
//  WorkoutData fixtures, call the four format renderers, and assert on the
//  emitted strings / parsed JSON.
//
//  Customizations are held in static lets per the macOS 26 deinit-crash
//  workaround documented in ExporterSmokeTests.
//

import XCTest
import HealthKit
@testable import HealthMd

private enum WorkoutGranularCustomizations {
    static let metric: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .metric
        return c
    }()

    static let imperial: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .imperial
        return c
    }()
}

private enum WorkoutGranularFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// 3 km run in 18:00 with 3 manual 1 km laps, 2 km splits with HR,
    /// 3 GPS route points, 152 m elevation gain.
    static var richRunWithGranular: HealthData {
        var data = HealthData(date: referenceDate)
        let laps: [WorkoutLap] = [
            WorkoutLap(startDate: referenceDate, endDate: referenceDate.addingTimeInterval(360),
                       duration: 360, distanceMeters: 1000),
            WorkoutLap(startDate: referenceDate.addingTimeInterval(360), endDate: referenceDate.addingTimeInterval(720),
                       duration: 360, distanceMeters: 1000),
            WorkoutLap(startDate: referenceDate.addingTimeInterval(720), endDate: referenceDate.addingTimeInterval(1080),
                       duration: 360, distanceMeters: 1000),
        ]
        let splits: [WorkoutSplit] = [
            WorkoutSplit(index: 1, startDate: referenceDate, duration: 360,
                         distanceMeters: 1000, avgHeartRate: 150),
            WorkoutSplit(index: 2, startDate: referenceDate.addingTimeInterval(360), duration: 360,
                         distanceMeters: 1000, avgHeartRate: 158),
        ]
        let route: [RoutePoint] = [
            RoutePoint(timestamp: referenceDate, latitude: 37.7749, longitude: -122.4194,
                       altitudeMeters: 50, speedMps: 2.78, courseDegrees: nil, horizontalAccuracyMeters: nil),
            RoutePoint(timestamp: referenceDate.addingTimeInterval(540), latitude: 37.7755, longitude: -122.4198,
                       altitudeMeters: 100, speedMps: 2.78, courseDegrees: nil, horizontalAccuracyMeters: nil),
            RoutePoint(timestamp: referenceDate.addingTimeInterval(1080), latitude: 37.7760, longitude: -122.4200,
                       altitudeMeters: 202, speedMps: 2.78, courseDegrees: nil, horizontalAccuracyMeters: nil),
        ]
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 1080,
                calories: 250,
                distance: 3000,
                avgHeartRate: 154.0,
                maxHeartRate: 175.0,
                minHeartRate: 95.0,
                elevationGainMeters: 152.0,
                elevationLossMeters: nil,
                laps: laps,
                splits: splits,
                route: route
            )
        ]
        return data
    }

    /// Workout with no granular fields — confirms the new sections are purely additive.
    static var minimalRun: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 1800,
                calories: 250,
                distance: 5000,
                avgHeartRate: 145.0
            )
        ]
        return data
    }
}

// MARK: - Markdown

final class WorkoutGranularMarkdownTests: XCTestCase {

    func testMarkdown_emitsElevationGainMetric() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("Elevation Gain:** 152 m"), "Metric elevation missing: \(md)")
    }

    func testMarkdown_emitsElevationGainImperial() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.imperial
        )
        // 152 m × 3.28084 = 498.69 ft → 499 ft (rounded)
        XCTAssertTrue(md.contains("Elevation Gain:** 499 ft"), "Imperial elevation missing: \(md)")
    }

    func testMarkdown_emitsLapsTable() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("**Laps:**"), "Laps heading missing")
        XCTAssertTrue(md.contains("| # | Distance | Time | Pace |"), "Lap table header missing")
        // 1.00 km in 360 s = 6:00, pace = 6:00 /km
        XCTAssertTrue(md.contains("| 1 | 1.00 km | 6:00 | 6:00 /km |"), "Lap 1 row missing: \(md)")
        XCTAssertTrue(md.contains("| 2 | 1.00 km | 6:00 | 6:00 /km |"), "Lap 2 row missing")
        XCTAssertTrue(md.contains("| 3 | 1.00 km | 6:00 | 6:00 /km |"), "Lap 3 row missing")
    }

    func testMarkdown_emitsSplitsTable() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("**Splits:**"), "Splits heading missing")
        XCTAssertTrue(md.contains("| # | Time | Pace | Avg HR |"), "Split table header missing")
        XCTAssertTrue(md.contains("| 1 | 6:00 | 6:00 /km | 150 bpm |"), "Split 1 row missing: \(md)")
        XCTAssertTrue(md.contains("| 2 | 6:00 | 6:00 /km | 158 bpm |"), "Split 2 row missing: \(md)")
    }

    func testMarkdown_emitsRouteSummary() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("GPS Route:** 3 points"), "Route summary missing: \(md)")
    }

    func testMarkdown_minimalRun_omitsAllGranularSections() {
        let md = WorkoutGranularFixtures.minimalRun.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertFalse(md.contains("Laps:**"), "Laps heading should not appear when no laps")
        XCTAssertFalse(md.contains("Splits:**"), "Splits heading should not appear when no splits")
        XCTAssertFalse(md.contains("Elevation Gain"), "Elevation should not appear when nil")
        XCTAssertFalse(md.contains("GPS Route"), "Route should not appear when no route")
    }
}

// MARK: - JSON

final class WorkoutGranularJSONTests: XCTestCase {

    private func parseWorkout(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workouts = root["workouts"] as? [[String: Any]],
              let first = workouts.first else { return nil }
        return first
    }

    func testJSON_includesLapsArray() {
        let json = WorkoutGranularFixtures.richRunWithGranular.toJSON(
            customization: WorkoutGranularCustomizations.metric
        )
        guard let w = parseWorkout(json), let laps = w["laps"] as? [[String: Any]] else {
            XCTFail("laps array missing from JSON: \(json)"); return
        }
        XCTAssertEqual(laps.count, 3)
        XCTAssertEqual(laps[0]["index"] as? Int, 1)
        XCTAssertEqual(laps[0]["duration"] as? Double, 360)
        XCTAssertEqual(laps[0]["distance"] as? Double, 1000)
        XCTAssertEqual(laps[0]["paceFormatted"] as? String, "6:00 /km")
    }

    func testJSON_includesSplitsArray() {
        let json = WorkoutGranularFixtures.richRunWithGranular.toJSON(
            customization: WorkoutGranularCustomizations.metric
        )
        guard let w = parseWorkout(json), let splits = w["splits"] as? [[String: Any]] else {
            XCTFail("splits array missing from JSON: \(json)"); return
        }
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0]["index"] as? Int, 1)
        XCTAssertEqual(splits[0]["avgHeartRate"] as? Int, 150)
        XCTAssertEqual(splits[0]["paceFormatted"] as? String, "6:00 /km")
        XCTAssertEqual(splits[1]["avgHeartRate"] as? Int, 158)
    }

    func testJSON_includesRouteArray() {
        let json = WorkoutGranularFixtures.richRunWithGranular.toJSON(
            customization: WorkoutGranularCustomizations.metric
        )
        guard let w = parseWorkout(json), let route = w["route"] as? [[String: Any]] else {
            XCTFail("route array missing from JSON: \(json)"); return
        }
        XCTAssertEqual(route.count, 3)
        XCTAssertEqual(route[0]["latitude"] as? Double, 37.7749)
        XCTAssertEqual(route[0]["longitude"] as? Double, -122.4194)
        XCTAssertEqual(route[0]["altitude"] as? Double, 50)
        XCTAssertEqual(route[2]["altitude"] as? Double, 202)
    }

    func testJSON_includesElevationGain() {
        let json = WorkoutGranularFixtures.richRunWithGranular.toJSON(
            customization: WorkoutGranularCustomizations.metric
        )
        guard let w = parseWorkout(json) else { XCTFail("Workout missing"); return }
        XCTAssertEqual(w["elevationGainMeters"] as? Double, 152)
    }

    func testJSON_minimalRun_omitsGranularKeys() {
        let json = WorkoutGranularFixtures.minimalRun.toJSON(
            customization: WorkoutGranularCustomizations.metric
        )
        guard let w = parseWorkout(json) else { XCTFail("Workout missing"); return }
        XCTAssertNil(w["laps"], "laps should not appear when empty")
        XCTAssertNil(w["splits"], "splits should not appear when empty")
        XCTAssertNil(w["route"], "route should not appear when empty")
        XCTAssertNil(w["elevationGainMeters"], "elevation should not appear when nil")
    }
}

// MARK: - CSV

final class WorkoutGranularCSVTests: XCTestCase {

    func testCSV_emitsLapRows() {
        let csv = WorkoutGranularFixtures.richRunWithGranular.toCSV(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Running Lap 1 Distance,1.00,km"), "Lap 1 distance missing: \(csv)")
        XCTAssertTrue(csv.contains("Running Lap 1 Duration,360,seconds"), "Lap 1 duration missing")
        XCTAssertTrue(csv.contains("Running Lap 1 Pace,6:00 /km,"), "Lap 1 pace missing")
        XCTAssertTrue(csv.contains("Running Lap 2 Distance,1.00,km"), "Lap 2 distance missing")
        XCTAssertTrue(csv.contains("Running Lap 3 Distance,1.00,km"), "Lap 3 distance missing")
    }

    func testCSV_emitsSplitRows() {
        let csv = WorkoutGranularFixtures.richRunWithGranular.toCSV(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Running Split 1 Pace,6:00 /km,"), "Split 1 pace row missing")
        XCTAssertTrue(csv.contains("Running Split 1 Avg Heart Rate,150,bpm"), "Split 1 HR row missing")
        XCTAssertTrue(csv.contains("Running Split 2 Avg Heart Rate,158,bpm"), "Split 2 HR row missing")
    }

    func testCSV_emitsElevationGain() {
        let csv = WorkoutGranularFixtures.richRunWithGranular.toCSV(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Running Elevation Gain,152,m"), "Elevation row missing: \(csv)")
    }

    func testCSV_minimalRun_omitsGranularRows() {
        let csv = WorkoutGranularFixtures.minimalRun.toCSV(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertFalse(csv.contains("Running Lap"), "Lap row should not appear when empty")
        XCTAssertFalse(csv.contains("Running Split "), "Split row should not appear when empty")
        XCTAssertFalse(csv.contains("Elevation Gain"), "Elevation row should not appear when nil")
    }
}

// MARK: - Pipeline (FakeHealthStore → HealthKitManager → exporters)

final class WorkoutGranularPipelineTests: XCTestCase {

    @MainActor
    func test_fakeStoreLapsRouteSplitsPropagateToWorkoutData() async throws {
        let store = FakeHealthStore()
        let date = HealthKitFixtures.referenceDate
        let runStart = Calendar.current.date(byAdding: .hour, value: 7,
                                             to: Calendar.current.startOfDay(for: date))!

        let laps = [
            WorkoutLap(startDate: runStart, endDate: runStart.addingTimeInterval(360),
                       duration: 360, distanceMeters: 1000),
            WorkoutLap(startDate: runStart.addingTimeInterval(360), endDate: runStart.addingTimeInterval(720),
                       duration: 360, distanceMeters: 1000),
        ]
        let route = [
            RoutePoint(timestamp: runStart, latitude: 37.7749, longitude: -122.4194,
                       altitudeMeters: 50, speedMps: 2.78, courseDegrees: nil, horizontalAccuracyMeters: nil),
            RoutePoint(timestamp: runStart.addingTimeInterval(720), latitude: 37.7760, longitude: -122.4200,
                       altitudeMeters: 202, speedMps: 2.78, courseDegrees: nil, horizontalAccuracyMeters: nil),
        ]
        let splits = [
            WorkoutSplit(index: 1, startDate: runStart, duration: 360,
                         distanceMeters: 1000, avgHeartRate: 150),
        ]

        store.workoutResults = [
            WorkoutValue(
                activityType: HKWorkoutActivityType.running.rawValue,
                duration: 720,
                startDate: runStart,
                endDate: runStart.addingTimeInterval(720),
                totalEnergyBurned: 200,
                totalDistance: 2000,
                avgHeartRate: 155,
                maxHeartRate: 170,
                minHeartRate: 100,
                elevationGainMeters: 152,
                elevationLossMeters: nil,
                laps: laps,
                splits: splits,
                route: route
            )
        ]

        let mgr = HealthKitManager(store: store)
        let data = try await mgr.fetchHealthData(for: date)

        XCTAssertEqual(data.workouts.count, 1)
        let w = data.workouts[0]
        XCTAssertEqual(w.laps.count, 2, "Laps did not propagate")
        XCTAssertEqual(w.splits.count, 1, "Splits did not propagate")
        XCTAssertEqual(w.route.count, 2, "Route did not propagate")
        XCTAssertEqual(w.elevationGainMeters, 152, "Elevation did not propagate")

        // Pipeline → markdown sanity checks
        let customization = FormatCustomization()
        customization.unitPreference = .metric
        let md = data.toMarkdown(customization: customization)
        XCTAssertTrue(md.contains("Elevation Gain:** 152 m"))
        XCTAssertTrue(md.contains("**Laps:**"))
        XCTAssertTrue(md.contains("**Splits:**"))
        XCTAssertTrue(md.contains("GPS Route:** 2 points"))
    }
}
