//
//  WorkoutDetailsExportTests.swift
//  HealthMdTests
//
//  Verifies that per-workout detail fields (heart rate, pace, running and
//  cycling form metrics) are rendered correctly across Markdown, CSV, JSON,
//  and Obsidian Bases (YAML frontmatter) exporters.
//
//  FormatCustomization is held in static lets per the macOS 26 deinit-crash
//  workaround documented in ExporterSmokeTests.
//

import XCTest
@testable import HealthMd

private enum WorkoutDetailsCustomizations {
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

private enum WorkoutDetailsFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// 30-min run with full HR + running form metrics populated.
    static var richRun: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 1800,
                calories: 320,
                distance: 5000,
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
        ]
        return data
    }

    /// 60-min ride with cycling form metrics populated. 25 km in 60 min = 25.0 km/h.
    static var richRide: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .cycling,
                startTime: referenceDate,
                duration: 3600,
                calories: 540,
                distance: 25000,
                avgHeartRate: 145.0,
                maxHeartRate: 172.0,
                minHeartRate: 110.0,
                avgCyclingCadence: 85.0,
                avgPower: 195.0,
                maxPower: 410.0
            )
        ]
        return data
    }

    /// 30-min swim, 1500 m → 2:00 /100m.
    static var richSwim: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .swimming,
                startTime: referenceDate,
                duration: 1800,
                calories: 350,
                distance: 1500,
                avgHeartRate: 140.0,
                maxHeartRate: 165.0,
                minHeartRate: 100.0
            )
        ]
        return data
    }

    /// Two runs in one day — exercises Obsidian Bases duration-weighted aggregates.
    static var twoRuns: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            // 30 min @ 160 avg HR, 175 cadence, 230 power
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 1800,
                calories: 280,
                distance: 5000,
                avgHeartRate: 160.0,
                maxHeartRate: 175.0,
                minHeartRate: 110.0,
                avgRunningCadence: 175.0,
                avgPower: 230.0,
                maxPower: 290.0
            ),
            // 60 min @ 150 avg HR, 170 cadence, 200 power
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate.addingTimeInterval(7200),
                duration: 3600,
                calories: 480,
                distance: 9000,
                avgHeartRate: 150.0,
                maxHeartRate: 168.0,
                minHeartRate: 95.0,
                avgRunningCadence: 170.0,
                avgPower: 200.0,
                maxPower: 320.0
            )
        ]
        return data
    }

    /// Workout with only HR set, no form metrics — common for a watch without
    /// running power. Verifies optional fields are independently rendered.
    static var hrOnly: HealthData {
        var data = HealthData(date: referenceDate)
        data.workouts = [
            WorkoutData(
                workoutType: .other,
                startTime: referenceDate,
                duration: 1200,
                calories: 150,
                distance: nil,
                avgHeartRate: 130.0,
                maxHeartRate: 155.0,
                minHeartRate: 95.0
            )
        ]
        return data
    }
}

// MARK: - Markdown

final class WorkoutDetailsMarkdownTests: XCTestCase {

    func testMarkdown_runningWorkout_includesHeartRateAndPace() {
        let md = WorkoutDetailsFixtures.richRun.toMarkdown(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(md.contains("Avg Heart Rate:** 162 bpm"), "Avg HR missing")
        XCTAssertTrue(md.contains("Max Heart Rate:** 178 bpm"), "Max HR missing")
        XCTAssertTrue(md.contains("Min Heart Rate:** 96 bpm"), "Min HR missing")
        XCTAssertTrue(md.contains("Avg Pace:** 6:00 /km"), "Pace missing or wrong: \(md)")
    }

    func testMarkdown_runningWorkout_includesRunningFormMetrics() {
        let md = WorkoutDetailsFixtures.richRun.toMarkdown(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(md.contains("Avg Cadence:** 179 spm"), "Cadence missing")
        XCTAssertTrue(md.contains("Avg Stride Length:** 1.18 m"), "Stride missing")
        XCTAssertTrue(md.contains("Avg Ground Contact:** 245 ms"), "GCT missing")
        XCTAssertTrue(md.contains("Avg Vertical Oscillation:** 8.4 cm"), "Vert osc missing")
        XCTAssertTrue(md.contains("Avg Power:** 240 W"), "Avg power missing")
        XCTAssertTrue(md.contains("Max Power:** 312 W"), "Max power missing")
    }

    func testMarkdown_runningWorkout_imperialPace() {
        let md = WorkoutDetailsFixtures.richRun.toMarkdown(
            customization: WorkoutDetailsCustomizations.imperial
        )
        // 5000 m in 1800 s → 3.107 mi → ~9:39 /mi
        XCTAssertTrue(md.contains("Avg Pace:** 9:39 /mi"), "Imperial pace wrong: \(md)")
    }

    func testMarkdown_cyclingWorkout_emitsSpeedNotPace() {
        let md = WorkoutDetailsFixtures.richRide.toMarkdown(
            customization: WorkoutDetailsCustomizations.metric
        )
        // 25 km in 60 min → 25.0 km/h. Cyclists read speed, not pace.
        XCTAssertTrue(md.contains("Avg Speed:** 25.0 km/h"), "Cycling speed missing or wrong: \(md)")
        XCTAssertFalse(md.contains("Avg Pace:**"), "Cycling should not emit pace")
        XCTAssertTrue(md.contains("Avg Cadence:** 85 rpm"), "Cycling cadence missing")
        XCTAssertTrue(md.contains("Avg Power:** 195 W"), "Cycling avg power missing")
        XCTAssertTrue(md.contains("Max Power:** 410 W"), "Cycling max power missing")
        XCTAssertFalse(md.contains("Stride Length"), "Stride should not appear for cycling")
        XCTAssertFalse(md.contains("Ground Contact"), "GCT should not appear for cycling")
    }

    func testMarkdown_cyclingWorkout_imperialSpeed() {
        let md = WorkoutDetailsFixtures.richRide.toMarkdown(
            customization: WorkoutDetailsCustomizations.imperial
        )
        // 25 km / 1.609344 = 15.534 mi over 1 h → 15.5 mph
        XCTAssertTrue(md.contains("Avg Speed:** 15.5 mph"), "Imperial cycling speed wrong: \(md)")
    }

    func testMarkdown_swimWorkout_emitsSwimPacePer100m() {
        let md = WorkoutDetailsFixtures.richSwim.toMarkdown(
            customization: WorkoutDetailsCustomizations.metric
        )
        // 1500 m in 1800 s → 2:00 per 100 m
        XCTAssertTrue(md.contains("Avg Pace:** 2:00 /100m"), "Swim pace missing or wrong: \(md)")
        XCTAssertFalse(md.contains("/km"), "Swim should not emit /km pace")
        XCTAssertFalse(md.contains("Avg Speed:**"), "Swim should not emit speed")
    }

    func testMarkdown_swimWorkout_imperialPacePer100yd() {
        let md = WorkoutDetailsFixtures.richSwim.toMarkdown(
            customization: WorkoutDetailsCustomizations.imperial
        )
        // 1500 m / 91.44 = 16.404 100yd units over 1800 s → 109.7 sec/100yd → 1:50 /100yd
        XCTAssertTrue(md.contains("Avg Pace:** 1:50 /100yd"), "Imperial swim pace wrong: \(md)")
    }

    func testMarkdown_hrOnly_omitsFormMetrics() {
        let md = WorkoutDetailsFixtures.hrOnly.toMarkdown(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(md.contains("Avg Heart Rate:** 130 bpm"))
        XCTAssertFalse(md.contains("Cadence"), "Cadence should not appear when nil")
        XCTAssertFalse(md.contains("Power"), "Power should not appear when nil")
        XCTAssertFalse(md.contains("Pace"), "Pace should not appear without distance")
    }
}

// MARK: - CSV

final class WorkoutDetailsCSVTests: XCTestCase {

    func testCSV_runningWorkout_includesHeartRateAndPaceRows() {
        let csv = WorkoutDetailsFixtures.richRun.toCSV(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Running Avg Heart Rate,162,bpm"), "Avg HR row missing")
        XCTAssertTrue(csv.contains("Running Max Heart Rate,178,bpm"), "Max HR row missing")
        XCTAssertTrue(csv.contains("Running Min Heart Rate,96,bpm"), "Min HR row missing")
        XCTAssertTrue(csv.contains("Running Avg Pace,6:00 /km,"), "Pace row missing")
    }

    func testCSV_runningWorkout_includesRunningFormRows() {
        let csv = WorkoutDetailsFixtures.richRun.toCSV(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Running Avg Cadence,179,spm"), "Cadence row missing")
        XCTAssertTrue(csv.contains("Running Avg Stride Length,1.18,m"), "Stride row missing")
        XCTAssertTrue(csv.contains("Running Avg Ground Contact,245,ms"), "GCT row missing")
        XCTAssertTrue(csv.contains("Running Avg Vertical Oscillation,8.4,cm"), "Vert osc row missing")
        XCTAssertTrue(csv.contains("Running Avg Power,240,W"), "Avg power row missing")
        XCTAssertTrue(csv.contains("Running Max Power,312,W"), "Max power row missing")
    }

    func testCSV_cyclingWorkout_emitsSpeedAndCyclingFields() {
        let csv = WorkoutDetailsFixtures.richRide.toCSV(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Cycling Avg Speed,25.0 km/h,"), "Cycling speed row missing")
        XCTAssertFalse(csv.contains("Cycling Avg Pace"), "Cycling should not emit pace row")
        XCTAssertTrue(csv.contains("Cycling Avg Cadence,85,rpm"), "Cycling cadence row missing")
        XCTAssertTrue(csv.contains("Cycling Avg Power,195,W"), "Cycling avg power row missing")
        XCTAssertTrue(csv.contains("Cycling Max Power,410,W"), "Cycling max power row missing")
    }

    func testCSV_swimWorkout_emitsSwimPaceRow() {
        let csv = WorkoutDetailsFixtures.richSwim.toCSV(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Swimming Avg Pace,2:00 /100m,"), "Swim pace row missing")
        XCTAssertFalse(csv.contains("Swimming Avg Speed"), "Swim should not emit speed row")
    }

    func testCSV_hrOnly_omitsFormRows() {
        let csv = WorkoutDetailsFixtures.hrOnly.toCSV(
            customization: WorkoutDetailsCustomizations.metric
        )
        XCTAssertTrue(csv.contains("Avg Heart Rate,130,bpm"))
        XCTAssertFalse(csv.contains("Cadence,"), "Cadence row should not appear when nil")
        XCTAssertFalse(csv.contains("Power,"), "Power row should not appear when nil")
        XCTAssertFalse(csv.contains("Avg Pace"), "Pace row should not appear without distance")
    }
}

// MARK: - JSON

final class WorkoutDetailsJSONTests: XCTestCase {

    private func parseWorkout(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workouts = root["workouts"] as? [[String: Any]],
              let first = workouts.first else {
            return nil
        }
        return first
    }

    func testJSON_runningWorkout_includesHeartRateFields() {
        let json = WorkoutDetailsFixtures.richRun.toJSON(
            customization: WorkoutDetailsCustomizations.metric
        )
        guard let w = parseWorkout(json) else {
            XCTFail("Failed to parse workout from JSON")
            return
        }
        XCTAssertEqual(w["avgHeartRate"] as? Int, 162)
        XCTAssertEqual(w["maxHeartRate"] as? Int, 178)
        XCTAssertEqual(w["minHeartRate"] as? Int, 96)
        XCTAssertEqual(w["avgPaceFormatted"] as? String, "6:00 /km")
    }

    func testJSON_runningWorkout_includesRunningFormFields() {
        let json = WorkoutDetailsFixtures.richRun.toJSON(
            customization: WorkoutDetailsCustomizations.metric
        )
        guard let w = parseWorkout(json) else {
            XCTFail("Failed to parse workout from JSON")
            return
        }
        XCTAssertEqual(w["avgRunningCadence"] as? Int, 179)
        XCTAssertEqual(w["avgGroundContactTime"] as? Int, 245)
        XCTAssertEqual(w["avgPower"] as? Int, 240)
        XCTAssertEqual(w["maxPower"] as? Int, 312)
        XCTAssertEqual(w["avgStrideLength"] as? Double, 1.18)
        XCTAssertEqual(w["avgVerticalOscillation"] as? Double, 8.4)
    }

    func testJSON_cyclingWorkout_includesSpeedAndCyclingFields() {
        let json = WorkoutDetailsFixtures.richRide.toJSON(
            customization: WorkoutDetailsCustomizations.metric
        )
        guard let w = parseWorkout(json) else {
            XCTFail("Failed to parse workout from JSON")
            return
        }
        XCTAssertEqual(w["avgSpeedFormatted"] as? String, "25.0 km/h")
        XCTAssertNil(w["avgPaceFormatted"], "Cycling should not emit pace")
        XCTAssertEqual(w["avgCyclingCadence"] as? Int, 85)
        XCTAssertEqual(w["avgPower"] as? Int, 195)
        XCTAssertEqual(w["maxPower"] as? Int, 410)
        XCTAssertNil(w["avgRunningCadence"])
        XCTAssertNil(w["avgStrideLength"])
    }

    func testJSON_swimWorkout_emitsSwimPaceUnderPaceKey() {
        let json = WorkoutDetailsFixtures.richSwim.toJSON(
            customization: WorkoutDetailsCustomizations.metric
        )
        guard let w = parseWorkout(json) else {
            XCTFail("Failed to parse workout from JSON")
            return
        }
        XCTAssertEqual(w["avgPaceFormatted"] as? String, "2:00 /100m")
        XCTAssertNil(w["avgSpeedFormatted"], "Swim should not emit speed")
    }

    func testJSON_hrOnly_omitsFormFields() {
        let json = WorkoutDetailsFixtures.hrOnly.toJSON(
            customization: WorkoutDetailsCustomizations.metric
        )
        guard let w = parseWorkout(json) else {
            XCTFail("Failed to parse workout from JSON")
            return
        }
        XCTAssertEqual(w["avgHeartRate"] as? Int, 130)
        XCTAssertNil(w["avgRunningCadence"])
        XCTAssertNil(w["avgPower"])
        XCTAssertNil(w["avgPaceFormatted"])
    }
}

// MARK: - Obsidian Bases (YAML frontmatter)

final class WorkoutDetailsObsidianBasesTests: XCTestCase {

    private func parseFrontmatter(_ output: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed.isEmpty { continue }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                pairs[key] = val
            }
        }
        return pairs
    }

    func testObsidianBases_singleRun_emitsHeartRateAggregates() {
        let output = WorkoutDetailsFixtures.richRun.toObsidianBases(
            customization: WorkoutDetailsCustomizations.metric
        )
        let fm = parseFrontmatter(output)
        XCTAssertEqual(fm["workout_avg_heart_rate"], "162")
        XCTAssertEqual(fm["workout_max_heart_rate"], "178")
        XCTAssertEqual(fm["workout_min_heart_rate"], "96")
    }

    func testObsidianBases_singleRun_emitsRunningFormAggregates() {
        let output = WorkoutDetailsFixtures.richRun.toObsidianBases(
            customization: WorkoutDetailsCustomizations.metric
        )
        let fm = parseFrontmatter(output)
        XCTAssertEqual(fm["workout_running_cadence"], "179")
        XCTAssertEqual(fm["workout_running_stride_length"], "1.18")
        XCTAssertEqual(fm["workout_running_ground_contact"], "245")
        XCTAssertEqual(fm["workout_running_vertical_oscillation"], "8.4")
        XCTAssertEqual(fm["workout_avg_power"], "240")
        XCTAssertEqual(fm["workout_max_power"], "312")
    }

    func testObsidianBases_singleRide_emitsCyclingCadenceAndPower() {
        let output = WorkoutDetailsFixtures.richRide.toObsidianBases(
            customization: WorkoutDetailsCustomizations.metric
        )
        let fm = parseFrontmatter(output)
        XCTAssertEqual(fm["workout_cycling_cadence"], "85")
        XCTAssertEqual(fm["workout_avg_power"], "195")
        XCTAssertEqual(fm["workout_max_power"], "410")
        XCTAssertNil(fm["workout_running_cadence"])
        XCTAssertNil(fm["workout_running_stride_length"])
    }

    func testObsidianBases_twoRuns_durationWeightedAvgHeartRate() {
        // 30 min @ 160 + 60 min @ 150 → weighted avg = (1800*160 + 3600*150) / 5400 = 153.33 → "153"
        let output = WorkoutDetailsFixtures.twoRuns.toObsidianBases(
            customization: WorkoutDetailsCustomizations.metric
        )
        let fm = parseFrontmatter(output)
        XCTAssertEqual(fm["workout_avg_heart_rate"], "153", "Weighted HR avg wrong")
        // Max-of-maxes across runs: 175 vs 168 → 175
        XCTAssertEqual(fm["workout_max_heart_rate"], "175")
        // Min-of-mins: 110 vs 95 → 95
        XCTAssertEqual(fm["workout_min_heart_rate"], "95")
    }

    func testObsidianBases_twoRuns_durationWeightedFormMetrics() {
        // Cadence: 30min @ 175 + 60min @ 170 → (1800*175 + 3600*170) / 5400 = 171.67 → "172"
        // Power avg: 30min @ 230 + 60min @ 200 → (1800*230 + 3600*200) / 5400 = 210
        // Max power: max(290, 320) = 320
        let output = WorkoutDetailsFixtures.twoRuns.toObsidianBases(
            customization: WorkoutDetailsCustomizations.metric
        )
        let fm = parseFrontmatter(output)
        XCTAssertEqual(fm["workout_running_cadence"], "172")
        XCTAssertEqual(fm["workout_avg_power"], "210")
        XCTAssertEqual(fm["workout_max_power"], "320")
    }

    func testObsidianBases_hrOnly_emitsHRButOmitsFormKeys() {
        let output = WorkoutDetailsFixtures.hrOnly.toObsidianBases(
            customization: WorkoutDetailsCustomizations.metric
        )
        let fm = parseFrontmatter(output)
        XCTAssertEqual(fm["workout_avg_heart_rate"], "130")
        XCTAssertEqual(fm["workout_max_heart_rate"], "155")
        XCTAssertEqual(fm["workout_min_heart_rate"], "95")
        XCTAssertNil(fm["workout_running_cadence"])
        XCTAssertNil(fm["workout_cycling_cadence"])
        XCTAssertNil(fm["workout_avg_power"])
        XCTAssertNil(fm["workout_max_power"])
    }

    func testObsidianBases_emptyWorkouts_omitsAllAggregates() {
        var data = HealthData(date: WorkoutDetailsFixtures.referenceDate)
        data.activity.steps = 5000  // ensure data.hasAnyData
        let output = data.toObsidianBases(customization: WorkoutDetailsCustomizations.metric)
        let fm = parseFrontmatter(output)
        XCTAssertNil(fm["workout_avg_heart_rate"])
        XCTAssertNil(fm["workout_max_heart_rate"])
        XCTAssertNil(fm["workout_running_cadence"])
        XCTAssertNil(fm["workout_avg_power"])
    }
}
