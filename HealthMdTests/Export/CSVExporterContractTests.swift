//
//  CSVExporterContractTests.swift
//  HealthMdTests
//
//  Structural contract tests for CSV exporter output.
//  Parses CSV rows and asserts header schema, row counts, and values.
//

import XCTest
@testable import HealthMd

// Static customizations to avoid macOS 26 deinit crash.
private enum CSVContractCustomizations {
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

final class CSVExporterContractTests: XCTestCase {

    // MARK: - Helpers

    /// Parse CSV string into rows, each row split by comma.
    /// Returns (header, dataRows).
    private func parseCSV(_ data: HealthData, customization: FormatCustomization = CSVContractCustomizations.metric) -> (header: [String], rows: [[String]]) {
        let csv = data.toCSV(customization: customization)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let headerLine = lines.first else {
            XCTFail("CSV has no header row")
            return ([], [])
        }
        let header = headerLine.components(separatedBy: ",")
        let dataRows = lines.dropFirst().map { $0.components(separatedBy: ",") }
        return (header, Array(dataRows))
    }

    /// Get all rows for a specific category.
    private func rows(for category: String, in allRows: [[String]]) -> [[String]] {
        allRows.filter { $0.count > 1 && $0[1] == category }
    }

    /// Get all unique categories from rows.
    private func categories(in allRows: [[String]]) -> Set<String> {
        Set(allRows.compactMap { $0.count > 1 ? $0[1] : nil })
    }

    // MARK: - Header Schema

    func testCSV_headerSchema_fiveColumns() {
        let (header, _) = parseCSV(ExportFixtures.fullDay)
        XCTAssertEqual(header, ["Date", "Category", "Metric", "Value", "Unit"],
                       "CSV header schema must be Date,Category,Metric,Value,Unit")
    }

    func testCSV_emptyDay_hasOnlyHeaderRow() {
        let csv = ExportFixtures.emptyDay.toCSV(customization: CSVContractCustomizations.metric)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1, "Empty day should only have the header row")
    }

    // MARK: - Full Day Category Presence

    func testCSV_fullDay_containsAllCategories() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let cats = categories(in: allRows)
        let expected: Set<String> = ["Sleep", "Activity", "Heart", "Vitals", "Body", "Nutrition", "Mindfulness", "Mobility", "Hearing", "Workouts"]
        for cat in expected {
            XCTAssertTrue(cats.contains(cat), "Full day CSV missing category: \(cat)")
        }
    }

    // MARK: - Sleep Rows

    func testCSV_fullDay_sleepRowCount() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let sleepRows = rows(for: "Sleep", in: allRows)
        // fullDay has: totalDuration, deepSleep, remSleep, coreSleep, awakeTime, inBedTime = 6 rows
        XCTAssertEqual(sleepRows.count, 6, "Full day should have 6 sleep rows")
    }

    func testCSV_fullDay_sleepTotalDuration() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let sleepRows = rows(for: "Sleep", in: allRows)
        let totalRow = sleepRows.first { $0.count > 2 && $0[2] == "Total Duration" }
        XCTAssertNotNil(totalRow, "Sleep should have Total Duration row")
        if let row = totalRow {
            XCTAssertEqual(row[4], "seconds", "Sleep duration unit should be seconds")
        }
    }

    // MARK: - Activity Rows

    func testCSV_fullDay_activityRowMetrics() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let activityRows = rows(for: "Activity", in: allRows)
        let metrics = Set(activityRows.compactMap { $0.count > 2 ? $0[2] : nil })
        let expected = ["Steps", "Active Calories", "Exercise Minutes", "Flights Climbed",
                        "Walking Running Distance", "Stand Hours", "Basal Energy",
                        "Cycling Distance", "Cardio Fitness (VO2 Max)"]
        for metric in expected {
            XCTAssertTrue(metrics.contains(metric), "Activity missing metric: \(metric)")
        }
    }

    func testCSV_fullDay_stepsValue() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let activityRows = rows(for: "Activity", in: allRows)
        let stepsRow = activityRows.first { $0.count > 2 && $0[2] == "Steps" }
        XCTAssertNotNil(stepsRow, "Should have Steps row")
        if let row = stepsRow {
            XCTAssertEqual(row[3], "12500", "Steps value should be 12500")
            XCTAssertEqual(row[4], "count", "Steps unit should be count")
        }
    }

    // MARK: - Heart Rows

    func testCSV_fullDay_heartRowMetrics() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let heartRows = rows(for: "Heart", in: allRows)
        let metrics = Set(heartRows.compactMap { $0.count > 2 ? $0[2] : nil })
        let expected = ["Resting Heart Rate", "Walking Heart Rate Average", "Average Heart Rate",
                        "Min Heart Rate", "Max Heart Rate", "HRV"]
        for metric in expected {
            XCTAssertTrue(metrics.contains(metric), "Heart missing metric: \(metric)")
        }
    }

    func testCSV_fullDay_heartUnitsAreBpm() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let heartRows = rows(for: "Heart", in: allRows)
        let hrRows = heartRows.filter { $0.count > 2 && $0[2].contains("Heart Rate") }
        for row in hrRows {
            XCTAssertEqual(row[4], "bpm", "\(row[2]) unit should be bpm")
        }
    }

    func testCSV_fullDay_hrvUnitIsMs() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let heartRows = rows(for: "Heart", in: allRows)
        let hrvRow = heartRows.first { $0.count > 2 && $0[2] == "HRV" }
        XCTAssertNotNil(hrvRow)
        XCTAssertEqual(hrvRow?[4], "ms", "HRV unit should be ms")
    }

    // MARK: - Vitals Rows

    func testCSV_fullDay_vitalsRowMetrics() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let vitalsRows = rows(for: "Vitals", in: allRows)
        let metrics = Set(vitalsRows.compactMap { $0.count > 2 ? $0[2] : nil })
        let expected = ["Respiratory Rate Avg", "Blood Oxygen Avg"]
        for metric in expected {
            XCTAssertTrue(metrics.contains(metric), "Vitals missing metric: \(metric)")
        }
    }

    func testCSV_fullDay_bloodOxygenIsPercent() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let vitalsRows = rows(for: "Vitals", in: allRows)
        let spo2Row = vitalsRows.first { $0.count > 2 && $0[2] == "Blood Oxygen Avg" }
        XCTAssertNotNil(spo2Row)
        if let row = spo2Row {
            XCTAssertEqual(row[4], "percent", "Blood oxygen unit should be percent")
            // 0.97 * 100 = 97.0
            XCTAssertTrue(row[3].contains("97"), "Blood oxygen should be in percent scale")
        }
    }

    // MARK: - Body Rows

    func testCSV_fullDay_bodyRowMetrics() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let bodyRows = rows(for: "Body", in: allRows)
        let metrics = Set(bodyRows.compactMap { $0.count > 2 ? $0[2] : nil })
        let expected = ["Weight", "Height", "BMI", "Body Fat Percentage"]
        for metric in expected {
            XCTAssertTrue(metrics.contains(metric), "Body missing metric: \(metric)")
        }
    }

    func testCSV_metricUnits_weightInKg() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay, customization: CSVContractCustomizations.metric)
        let bodyRows = rows(for: "Body", in: allRows)
        let weightRow = bodyRows.first { $0.count > 2 && $0[2] == "Weight" }
        XCTAssertNotNil(weightRow)
        XCTAssertEqual(weightRow?[4], "kg", "Metric weight unit should be kg")
    }

    func testCSV_imperialUnits_weightInLbs() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay, customization: CSVContractCustomizations.imperial)
        let bodyRows = rows(for: "Body", in: allRows)
        let weightRow = bodyRows.first { $0.count > 2 && $0[2] == "Weight" }
        XCTAssertNotNil(weightRow)
        XCTAssertEqual(weightRow?[4], "lbs", "Imperial weight unit should be lbs")
    }

    // MARK: - Nutrition Rows

    func testCSV_fullDay_nutritionRowMetrics() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let nutritionRows = rows(for: "Nutrition", in: allRows)
        let metrics = Set(nutritionRows.compactMap { $0.count > 2 ? $0[2] : nil })
        let expected = ["Dietary Energy", "Protein", "Carbohydrates", "Fat", "Fiber", "Sugar", "Water", "Caffeine"]
        for metric in expected {
            XCTAssertTrue(metrics.contains(metric), "Nutrition missing metric: \(metric)")
        }
    }

    // MARK: - Workout Rows

    func testCSV_fullDay_workoutRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let workoutRows = rows(for: "Workouts", in: allRows)
        // Running workout: start time, duration, distance, calories = 4 rows
        XCTAssertGreaterThanOrEqual(workoutRows.count, 3, "Should have at least 3 workout rows")
        let metrics = Set(workoutRows.compactMap { $0.count > 2 ? $0[2] : nil })
        XCTAssertTrue(metrics.contains { $0.contains("Running") }, "Should have Running workout rows")
    }

    // MARK: - Partial Day

    func testCSV_partialDay_onlySleepAndActivity() {
        let (_, allRows) = parseCSV(ExportFixtures.partialDay)
        let cats = categories(in: allRows)
        XCTAssertTrue(cats.contains("Sleep"), "Partial day should have Sleep")
        XCTAssertTrue(cats.contains("Activity"), "Partial day should have Activity")
        XCTAssertFalse(cats.contains("Heart"), "Partial day should not have Heart")
        XCTAssertFalse(cats.contains("Vitals"), "Partial day should not have Vitals")
        XCTAssertFalse(cats.contains("Body"), "Partial day should not have Body")
    }

    func testCSV_partialDay_sleepRows() {
        let (_, allRows) = parseCSV(ExportFixtures.partialDay)
        let sleepRows = rows(for: "Sleep", in: allRows)
        // partialDay has: totalDuration, deepSleep, remSleep, coreSleep = 4 rows
        XCTAssertEqual(sleepRows.count, 4, "Partial day should have 4 sleep rows")
    }

    // MARK: - Row Consistency

    func testCSV_fullDay_allRowsHaveFiveColumns() {
        let csv = ExportFixtures.fullDay.toCSV(customization: CSVContractCustomizations.metric)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        // Note: some values might contain commas in quoted strings
        // For simple rows, check non-quoted lines have 5 columns
        for (i, line) in lines.enumerated() {
            if !line.contains("\"") {
                let cols = line.components(separatedBy: ",")
                XCTAssertEqual(cols.count, 5, "Row \(i) should have 5 columns: \(line)")
            }
        }
    }

    // MARK: - Date Format

    func testCSV_fullDay_dateColumnMatchesFormat() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay, customization: CSVContractCustomizations.metric)
        let dateString = CSVContractCustomizations.metric.dateFormat.format(date: ExportFixtures.referenceDate)
        for row in allRows {
            if row.count > 0 && !row[0].isEmpty {
                XCTAssertEqual(row[0], dateString, "All rows should use the configured date format")
                break // Just check the first data row
            }
        }
    }

    // MARK: - Edge Cases

    func testCSV_edgeCaseDay_handlesZeroSleep() {
        let (_, allRows) = parseCSV(ExportFixtures.edgeCaseDay)
        let cats = categories(in: allRows)
        // edgeCaseDay has vitals (bodyTemperatureAvg) and mindfulness (stateOfMind)
        XCTAssertTrue(cats.contains("Vitals") || cats.contains("Mindfulness") || cats.contains("State of Mind"),
                      "Edge case should have at least vitals or mindfulness data")
    }
}
