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
                healthKitActivityType: "running",
                healthKitActivityTypeRawValue: 37,
                startTime: referenceDate,
                isIndoor: false,
                metadata: ["Device": "Apple Watch Ultra"],
                duration: 1080,
                calories: 250,
                distance: 3000,
                avgHeartRate: 154.0,
                maxHeartRate: 175.0,
                minHeartRate: 95.0,
                elevationGainMeters: 152.0,
                elevationLossMeters: 48.0,
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

    func testMarkdown_emitsHealthKitActivityIdentity() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("| Activity Type | Running |"), md)
        XCTAssertTrue(md.contains("| Sport | running |"), md)
        XCTAssertTrue(md.contains("| HealthKit Activity Type | running |"), md)
        XCTAssertTrue(md.contains("| HealthKit Activity Type Raw Value | 37 |"), md)
    }

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

    func testMarkdown_emitsElevationLoss() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("Elevation Loss:** 48 m"), "Elevation loss missing: \(md)")
    }

    func testMarkdown_emitsLapsTable() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("**Laps:**"), "Laps heading missing")
        XCTAssertTrue(md.contains("| # | Start | End | Distance | Time | Pace | Speed |"), "Lap table header missing")
        // 1.00 km in 360 s = 6:00, pace = 6:00 /km, speed = 10.0 km/h.
        XCTAssertTrue(md.contains("| 1.00 km | 6:00 | 6:00 /km | 10.0 km/h / 6.2 mph |"), "Lap row missing: \(md)")
        XCTAssertTrue(md.contains("| 2 |"), "Lap 2 row missing")
        XCTAssertTrue(md.contains("| 3 |"), "Lap 3 row missing")
    }

    func testMarkdown_emitsSplitsTable() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("**Splits:**"), "Splits heading missing")
        XCTAssertTrue(md.contains("| # | Start | End | Distance | Time | Pace | Speed | Avg HR | Max HR | Avg Power | Avg Cadence |"), "Split table header missing")
        XCTAssertTrue(md.contains("| 1.00 km | 6:00 | 6:00 /km | 10.0 km/h / 6.2 mph | 150 bpm |"), "Split 1 row missing: \(md)")
        XCTAssertTrue(md.contains("| 1.00 km | 6:00 | 6:00 /km | 10.0 km/h / 6.2 mph | 158 bpm |"), "Split 2 row missing: \(md)")
    }

    func testMarkdown_intervalTablesIncludeHeartRatePowerAndCadenceBreakdowns() {
        func sample(offset: TimeInterval, value: Double) -> TimeSeriesSample {
            TimeSeriesSample(timestamp: WorkoutGranularFixtures.referenceDate.addingTimeInterval(offset), value: value)
        }

        let lap = WorkoutLap(
            startDate: WorkoutGranularFixtures.referenceDate,
            endDate: WorkoutGranularFixtures.referenceDate.addingTimeInterval(300),
            duration: 300,
            distanceMeters: 1000
        )
        let split = WorkoutSplit(
            index: 1,
            startDate: WorkoutGranularFixtures.referenceDate,
            duration: 300,
            distanceMeters: 1000,
            avgHeartRate: 150
        )
        let series = WorkoutTimeSeries(
            heartRate: [100.0, 130.0, 150.0, 170.0, 190.0].enumerated().map { sample(offset: Double($0.offset) * 60, value: $0.element) },
            power: [100.0, 110.0, 120.0, 130.0, 140.0].enumerated().map { sample(offset: Double($0.offset) * 60, value: $0.element) },
            cadence: [80.0, 82.0, 84.0, 86.0, 88.0].enumerated().map { sample(offset: Double($0.offset) * 60, value: $0.element) }
        )

        var data = HealthData(date: WorkoutGranularFixtures.referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .cycling,
                startTime: WorkoutGranularFixtures.referenceDate,
                duration: 300,
                calories: 50,
                distance: 1000,
                avgHeartRate: 150,
                maxHeartRate: 190,
                avgCyclingCadence: 84,
                avgPower: 120,
                laps: [lap],
                splits: [split],
                timeSeries: series
            )
        ]

        let md = data.toMarkdown(customization: WorkoutGranularCustomizations.metric)
        XCTAssertTrue(md.contains("| # | Start | End | Distance | Time | Rate | Speed | Avg HR | Max HR | Avg Power | Avg Cadence |"), "Detailed interval header missing: \(md)")
        XCTAssertTrue(md.contains("| 1.00 km | 5:00 | 12.0 km/h | 12.0 km/h / 7.5 mph | 148 bpm | 190 bpm | 120 W | 84 rpm |"), "Lap breakdown row missing: \(md)")
        XCTAssertTrue(md.contains("| 1.00 km | 5:00 | 12.0 km/h | 12.0 km/h / 7.5 mph | 150 bpm | 190 bpm | 120 W | 84 rpm |"), "Split breakdown row missing: \(md)")
        XCTAssertTrue(md.contains("#### Samples"), "Samples section missing: \(md)")
        XCTAssertTrue(md.contains("| Heart Rate | 5 |"), "Heart rate sample count missing: \(md)")
    }

    func testMarkdown_emitsRouteSummary() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertTrue(md.contains("GPS Route:** 3 points"), "Route summary missing: \(md)")
    }

    func testMarkdown_rendersStructuredWorkoutDataAsReadableTables() {
        let md = WorkoutGranularFixtures.richRunWithGranular.toMarkdown(
            customization: WorkoutGranularCustomizations.metric
        )
        XCTAssertFalse(md.contains("<summary>Structured workout data</summary>"), "Markdown body should not include an inline YAML workout block: \(md)")
        XCTAssertFalse(md.contains("```yaml"), "Markdown body should not include a YAML code fence: \(md)")
        XCTAssertTrue(md.contains("#### Details"), "Details table missing: \(md)")
        XCTAssertTrue(md.contains("| Source | Health.md |"), "Source missing from details table: \(md)")
        XCTAssertTrue(md.contains("| Activity Type | Running |"), "Activity type missing from details table: \(md)")
        XCTAssertTrue(md.contains("| Distance | 3.00 km (3.00 km / 1.86 mi) |"), "Distance missing from details table: \(md)")
        XCTAssertTrue(md.contains("| Elevation Loss | 48 m |"), "Descent missing from details table: \(md)")
        XCTAssertTrue(md.contains("| GPS Route Points | 3 |"), "Route count missing from details table: \(md)")
        XCTAssertTrue(md.contains("#### Metadata"), "Readable workout metadata section missing: \(md)")
        XCTAssertTrue(md.contains("| Device | Apple Watch Ultra |"), "Metadata missing from table: \(md)")
    }

    func testMarkdown_escapesWorkoutMetadataTableCells() {
        var data = HealthData(date: WorkoutGranularFixtures.referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: WorkoutGranularFixtures.referenceDate,
                metadata: ["Route | Note": "mile 1\nsteady | effort\rcooldown"],
                duration: 1800,
                calories: 250,
                distance: 5000,
                avgHeartRate: 145.0
            )
        ]

        let md = data.toMarkdown(customization: WorkoutGranularCustomizations.metric)
        let metadataRow = md
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.contains("Route") && $0.contains("steady") }

        XCTAssertNotNil(metadataRow, "Escaped metadata row missing: \(md)")
        XCTAssertTrue(metadataRow?.contains("Route \\| Note") == true, "Pipe in key should be escaped: \(md)")
        XCTAssertTrue(metadataRow?.contains("mile 1<br>steady \\| effort<br>cooldown") == true, "Newlines and pipes in value should be escaped: \(md)")
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

// MARK: - Obsidian Bases

final class WorkoutGranularObsidianBasesTests: XCTestCase {

    func testBases_includesDetailedWorkoutHeaderData() {
        let bases = WorkoutGranularFixtures.richRunWithGranular.toObsidianBases(
            customization: WorkoutGranularCustomizations.metric
        )

        XCTAssertTrue(bases.contains("workout_details:"), "Detailed workout header missing: \(bases)")
        XCTAssertTrue(bases.contains("  - index: 1"), "Workout detail list item missing: \(bases)")
        XCTAssertTrue(bases.contains("    source: Health.md"), "Source missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    activity_type: \"Running\""), "Activity type missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    sport: running"), "Sport missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    healthkit_activity_type: running"), "HealthKit type missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    healthkit_activity_type_raw_value: 37"), "HealthKit raw value missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    distance_km: 3.00"), "Distance km missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    distance_mi: 1.86"), "Distance mi missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    pace_per_km: \"6:00 /km\""), "Stable km pace missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    pace_per_mi: \"9:39 /mi\""), "Stable mi pace missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    descent_m: 48"), "Descent missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    route_points: 3"), "Route count missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    laps:\n      - lap: 1"), "Lap detail missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    splits:\n      - split: 1"), "Split detail missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("        pace_per_km: \"6:00 /km\""), "Interval km pace missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("        pace_per_mi: \"9:39 /mi\""), "Interval mi pace missing from workout detail header: \(bases)")
        XCTAssertTrue(bases.contains("    metadata:\n      Device: \"Apple Watch Ultra\""), "Metadata missing from workout detail header: \(bases)")
    }

    func testBases_cyclingIntervalsExposeStableSpeedFields() {
        let lap = WorkoutLap(
            startDate: WorkoutGranularFixtures.referenceDate,
            endDate: WorkoutGranularFixtures.referenceDate.addingTimeInterval(300),
            duration: 300,
            distanceMeters: 1000
        )
        var data = HealthData(date: WorkoutGranularFixtures.referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .cycling,
                startTime: WorkoutGranularFixtures.referenceDate,
                duration: 300,
                calories: 50,
                distance: 1000,
                laps: [lap]
            )
        ]

        let bases = data.toObsidianBases(customization: WorkoutGranularCustomizations.imperial)
        XCTAssertTrue(bases.contains("    speed_kmh_formatted: \"12.0 km/h\""), "Top-level km/h speed missing: \(bases)")
        XCTAssertTrue(bases.contains("    speed_mph_formatted: \"7.5 mph\""), "Top-level mph speed missing: \(bases)")
        XCTAssertTrue(bases.contains("        speed_kmh_formatted: \"12.0 km/h\""), "Interval km/h speed missing: \(bases)")
        XCTAssertTrue(bases.contains("        speed_mph_formatted: \"7.5 mph\""), "Interval mph speed missing: \(bases)")
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
        XCTAssertNotNil(laps[0]["startTimeISO"], "lap start timestamp missing")
        XCTAssertNotNil(laps[0]["endTimeISO"], "lap end timestamp missing")
        XCTAssertEqual(laps[0]["duration"] as? Double, 360)
        XCTAssertEqual(laps[0]["distance"] as? Double, 1000)
        XCTAssertEqual(laps[0]["distanceKm"] as? Double, 1.0)
        XCTAssertEqual(laps[0]["distanceMi"] as? Double ?? 0, 0.621, accuracy: 0.001)
        XCTAssertEqual(laps[0]["paceFormatted"] as? String, "6:00 /km")
        XCTAssertEqual(laps[0]["pacePerKmFormatted"] as? String, "6:00 /km")
        XCTAssertEqual(laps[0]["pacePerMiFormatted"] as? String, "9:39 /mi")
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
        XCTAssertNotNil(splits[0]["startTimeISO"], "split start timestamp missing")
        XCTAssertNotNil(splits[0]["endTimeISO"], "split end timestamp missing")
        XCTAssertEqual(splits[0]["avgHeartRate"] as? Int, 150)
        XCTAssertEqual(splits[0]["distanceKm"] as? Double, 1.0)
        XCTAssertEqual(splits[0]["distanceMi"] as? Double ?? 0, 0.621, accuracy: 0.001)
        XCTAssertEqual(splits[0]["paceFormatted"] as? String, "6:00 /km")
        XCTAssertEqual(splits[0]["pacePerKmFormatted"] as? String, "6:00 /km")
        XCTAssertEqual(splits[0]["pacePerMiFormatted"] as? String, "9:39 /mi")
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
        XCTAssertTrue(csv.contains("Running Lap 1 Distance,1000,meters"), "Lap 1 distance missing: \(csv)")
        XCTAssertTrue(csv.contains("Running Lap 1 Duration,360,seconds"), "Lap 1 duration missing")
        XCTAssertTrue(csv.contains("Running Lap 1 Pace,6:00 /km,"), "Lap 1 pace missing")
        XCTAssertTrue(csv.contains("Running Lap 2 Distance,1000,meters"), "Lap 2 distance missing")
        XCTAssertTrue(csv.contains("Running Lap 3 Distance,1000,meters"), "Lap 3 distance missing")
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
