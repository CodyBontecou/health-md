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
        XCTAssertEqual(header, ["Date", "Category", "Metric", "Value", "Unit", "Timestamp"],
                       "CSV header schema must be Date,Category,Metric,Value,Unit,Timestamp")
    }

    func testCSV_emptyDay_hasHeaderAndSchemaMetadataRows() {
        let csv = ExportFixtures.emptyDay.toCSV(customization: CSVContractCustomizations.metric)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 7, "Empty day should include the header, schema metadata, timezone context, and raw capture status")
    }

    func testCSV_includesSchemaMetadataRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let schemaRow = allRows.first { $0.count > 3 && $0[1] == "Metadata" && $0[2] == "schema" }
        let versionRow = allRows.first { $0.count > 3 && $0[1] == "Metadata" && $0[2] == "schema_version" }
        let unitSystemRow = allRows.first { $0.count > 3 && $0[1] == "Metadata" && $0[2] == "unit_system" }
        let calendarTimezoneRow = allRows.first {
            $0.count > 3 && $0[1] == "Metadata" && $0[2] == "time_context.calendar_timezone"
        }
        let timestampTimezoneRow = allRows.first {
            $0.count > 3 && $0[1] == "Metadata" && $0[2] == "time_context.timestamp_timezone"
        }

        XCTAssertEqual(schemaRow?[3], HealthMdExportSchema.identifier, "CSV should include a schema metadata row")
        XCTAssertEqual(versionRow?[3], "\(HealthMdExportSchema.version)", "CSV should include a schema_version metadata row")
        XCTAssertEqual(unitSystemRow?[3], "metric", "CSV should include a unit_system metadata row")
        XCTAssertEqual(calendarTimezoneRow?[3], "UTC")
        XCTAssertEqual(timestampTimezoneRow?[3], "UTC")
    }

    // MARK: - Full Day Category Presence

    func testCSV_fullDay_containsAllCategories() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let cats = categories(in: allRows)
        let expected: Set<String> = ["Sleep", "Activity", "Heart", "Vitals", "Body", "Nutrition", "Mindfulness", "Mobility", "Hearing", "Workouts", "Medications"]
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
                        "Walking Running Distance", "Stand Time", "Stand Hours", "Basal Energy",
                        "Cycling Distance", "Cardio Fitness (VO2 Max)"]
        for metric in expected {
            XCTAssertTrue(metrics.contains(metric), "Activity missing metric: \(metric)")
        }
    }

    func testCSV_fullDay_standSummariesRemainSeparate() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let activityRows = rows(for: "Activity", in: allRows)
        let standTime = activityRows.first { $0.count > 4 && $0[2] == "Stand Time" }
        let standHours = activityRows.first { $0.count > 4 && $0[2] == "Stand Hours" }

        XCTAssertEqual(standTime?[3], "37.5")
        XCTAssertEqual(standTime?[4], "minutes")
        XCTAssertEqual(standHours?[3], "11")
        XCTAssertEqual(standHours?[4], "hours")
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

    func testCSV_imperialPreference_storesActivityDistancesInCanonicalMeters() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        data.activity.walkingRunningDistance = 9500
        data.activity.cyclingDistance = 3200
        data.activity.swimmingDistance = 1500
        data.activity.wheelchairDistance = 5000
        data.activity.downhillSnowSportsDistance = 12000

        let (_, allRows) = parseCSV(data, customization: CSVContractCustomizations.imperial)
        let activityRows = rows(for: "Activity", in: allRows)

        func row(named metric: String) -> [String]? {
            activityRows.first { $0.count > 4 && $0[2] == metric }
        }

        XCTAssertEqual(row(named: "Walking Running Distance")?[3], "9500.0")
        XCTAssertEqual(row(named: "Walking Running Distance")?[4], "meters")
        XCTAssertEqual(row(named: "Cycling Distance")?[3], "3200.0")
        XCTAssertEqual(row(named: "Cycling Distance")?[4], "meters")
        XCTAssertEqual(row(named: "Swimming Distance")?[3], "1500.0")
        XCTAssertEqual(row(named: "Swimming Distance")?[4], "meters")
        XCTAssertEqual(row(named: "Wheelchair Distance")?[3], "5000.0")
        XCTAssertEqual(row(named: "Wheelchair Distance")?[4], "meters")
        XCTAssertEqual(row(named: "Downhill Snow Sports Distance")?[3], "12000.0")
        XCTAssertEqual(row(named: "Downhill Snow Sports Distance")?[4], "meters")
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

    func testCSV_imperialPreference_stillStoresWeightInKg() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay, customization: CSVContractCustomizations.imperial)
        let bodyRows = rows(for: "Body", in: allRows)
        let weightRow = bodyRows.first { $0.count > 2 && $0[2] == "Weight" }
        XCTAssertNotNil(weightRow)
        XCTAssertEqual(weightRow?[3], "75.0", "Structured CSV weight should remain canonical kg")
        XCTAssertEqual(weightRow?[4], "kg", "Structured CSV weight unit should remain kg")
    }

    func testCSV_imperialPreference_storesCanonicalTemperatureHeightAndWater() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        data.vitals.bodyTemperatureAvg = 37.0
        data.body.height = 1.78
        data.nutrition.water = 2.5

        let (_, allRows) = parseCSV(data, customization: CSVContractCustomizations.imperial)
        let tempRow = rows(for: "Vitals", in: allRows).first { $0.count > 2 && $0[2] == "Body Temperature Avg" }
        let heightRow = rows(for: "Body", in: allRows).first { $0.count > 2 && $0[2] == "Height" }
        let waterRow = rows(for: "Nutrition", in: allRows).first { $0.count > 2 && $0[2] == "Water" }

        XCTAssertEqual(tempRow?[3], "37.0")
        XCTAssertEqual(tempRow?[4], "°C")
        XCTAssertEqual(heightRow?[3], "1.78")
        XCTAssertEqual(heightRow?[4], "m")
        XCTAssertEqual(waterRow?[3], "2.5")
        XCTAssertEqual(waterRow?[4], "L")
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

    func testCSV_extendedStructuredMetricsUseCanonicalDictionaryUnits() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        data.cyclingPerformance = CyclingPerformanceData(cyclingCadence: 88)
        data.vitamins = VitaminsData(vitaminA: 800)
        data.minerals = MineralsData(chromium: 35)

        let (_, allRows) = parseCSV(data)
        let cyclingCadence = rows(for: "Cycling", in: allRows).first { $0.count > 4 && $0[2] == "Cycling Cadence" }
        let vitaminA = rows(for: "Vitamins", in: allRows).first { $0.count > 4 && $0[2] == "Vitamin A" }
        let chromium = rows(for: "Minerals", in: allRows).first { $0.count > 4 && $0[2] == "Chromium" }

        XCTAssertEqual(cyclingCadence?[4], "rpm")
        XCTAssertEqual(vitaminA?[4], "µg")
        XCTAssertEqual(chromium?[4], "µg")
    }

    // MARK: - Medication Rows

    func testCSV_fullDay_medicationRowsExposeFetchedDetails() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let medicationRows = rows(for: "Medications", in: allRows)
        let metrics = Set(medicationRows.compactMap { $0.count > 2 ? $0[2] : nil })

        let expectedMetrics = [
            "Medication Concept Identifier",
            "Medication Display Name",
            "Medication General Form",
            "Medication Archived",
            "Medication Has Schedule",
            "Medication Related Coding",
            "Medication RxNorm Code",
            "Dose Event ID",
            "Dose Event Medication Concept Identifier",
            "Dose Event Medication Name",
            "Dose Event Start",
            "Dose Event End",
            "Dose Event Scheduled Date",
            "Dose Event Dose Quantity",
            "Dose Event Scheduled Dose Quantity",
            "Dose Event Unit",
            "Dose Event Status",
            "Dose Event Schedule Type"
        ]

        for metric in expectedMetrics {
            XCTAssertTrue(metrics.contains(metric), "Medications CSV missing detail metric: \(metric)")
        }

        let doseID = medicationRows.first { $0.count > 3 && $0[2] == "Dose Event ID" }
        XCTAssertEqual(doseID?[3], "00000000-0000-0000-0000-000000000321")
        XCTAssertFalse(doseID?[5].isEmpty ?? true, "Dose event detail rows should include the event timestamp")
    }

    func testCSV_medicationMetadataEscapesControlCharacters() {
        var data = HealthData(date: ExportFixtures.referenceDate)
        let syncIdentifier = "medication\u{001F}|0\u{001F}|urn:apple:health:ontology\u{001F}|1082238120_803412000.000000"
        data.medications = MedicationsData(
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000331")!,
                    medicationConceptIdentifier: "rxnorm:310964",
                    medicationName: "Ibuprofen",
                    startDate: ExportFixtures.referenceDate,
                    endDate: ExportFixtures.referenceDate,
                    scheduledDate: nil,
                    doseQuantity: 2,
                    scheduledDoseQuantity: nil,
                    unit: "count",
                    logStatus: .taken,
                    scheduleType: .scheduled,
                    metadata: ["HKMetadataKeySyncIdentifier": syncIdentifier]
                )
            ]
        )

        let csv = data.toCSV(customization: CSVContractCustomizations.metric)
        XCTAssertFalse(csv.contains("\u{001F}"), "CSV should not include literal invisible HealthKit metadata separators")
        XCTAssertTrue(csv.contains(#"medication\u001F|0\u001F|urn:apple:health:ontology\u001F|1082238120_803412000.000000"#), csv)
    }

    // MARK: - Workout Rows

    func testCSV_fullDay_workoutRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let workoutRows = rows(for: "Workouts", in: allRows)
        // Running workout: start time, duration, distance, calories = 4 rows
        XCTAssertGreaterThanOrEqual(workoutRows.count, 3, "Should have at least 3 workout rows")
        let metrics = Set(workoutRows.compactMap { $0.count > 2 ? $0[2] : nil })
        XCTAssertTrue(metrics.contains { $0.contains("Running") }, "Should have Running workout rows")

        let activityType = workoutRows.first { $0.count > 3 && $0[2] == "Workout Activity Type" }
        XCTAssertEqual(activityType?[3], "Running")
        XCTAssertEqual(activityType?[5], "2026-03-15T00:00:00Z")
        let sport = workoutRows.first { $0.count > 3 && $0[2] == "Workout Sport" }
        XCTAssertEqual(sport?[3], "running")
        let healthKitType = workoutRows.first { $0.count > 3 && $0[2] == "HealthKit Activity Type" }
        XCTAssertEqual(healthKitType?[3], "running")
        let rawValue = workoutRows.first { $0.count > 3 && $0[2] == "HealthKit Activity Type Raw Value" }
        XCTAssertEqual(rawValue?[3], "37")
    }

    func testCSV_rollingUsesDisplayCanonicalAndHealthKitNames() {
        var data = HealthData(date: ExportFixtures.referenceDate, timeContext: ExportFixtures.timeContext)
        data.workouts = [
            WorkoutData(
                workoutType: .rolling,
                healthKitActivityType: "preparationAndRecovery",
                healthKitActivityTypeRawValue: 33,
                startTime: ExportFixtures.referenceDate,
                duration: 600,
                calories: nil,
                distance: nil
            )
        ]

        let (_, allRows) = parseCSV(data)
        let workoutRows = rows(for: "Workouts", in: allRows)
        XCTAssertTrue(workoutRows.contains { $0.count > 3 && $0[2] == "Workout Activity Type" && $0[3] == "Rolling" })
        XCTAssertTrue(workoutRows.contains { $0.count > 3 && $0[2] == "Workout Sport" && $0[3] == "rolling" })
        XCTAssertTrue(workoutRows.contains { $0.count > 3 && $0[2] == "HealthKit Activity Type" && $0[3] == "preparationAndRecovery" })
        XCTAssertTrue(workoutRows.contains { $0.count > 3 && $0[2] == "HealthKit Activity Type Raw Value" && $0[3] == "33" })
        XCTAssertTrue(workoutRows.contains { $0.count > 2 && $0[2] == "Rolling Duration" })
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

    // MARK: - Granular Data

    func testCSV_fullDayGranular_hasHeartRateSampleRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDayGranular)
        let heartRows = rows(for: "Heart", in: allRows)
        let sampleRows = heartRows.filter { $0.count > 2 && $0[2] == "Heart Rate Sample" }
        XCTAssertEqual(sampleRows.count, 5, "Should have 5 heart rate sample rows")
        // Sample rows should have a non-empty 6th column (timestamp)
        for row in sampleRows {
            XCTAssertTrue(row.count >= 6, "Sample rows should have 6 columns")
            XCTAssertFalse(row[5].isEmpty, "Timestamp column should be non-empty for sample rows")
            XCTAssertTrue(row[5].hasSuffix("Z"), "Complete sample timestamps should be UTC")
        }
    }

    func testCSV_fullDayGranular_hasBloodPressureSampleRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDayGranular)
        let vitalRows = rows(for: "Vitals", in: allRows)
        let sampleRows = vitalRows.filter { $0.count > 2 && $0[2] == "Blood Pressure Sample" }

        XCTAssertEqual(sampleRows.count, 2)
        XCTAssertEqual(sampleRows.first?[3], "124/81")
        XCTAssertEqual(sampleRows.first?[4], "mmHg")
        XCTAssertTrue(sampleRows.first?[5].hasSuffix("Z") == true)
    }

    func testCSV_fullDayGranular_hasSleepStageRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDayGranular)
        let sleepRows = rows(for: "Sleep", in: allRows)
        let stageRows = sleepRows.filter { $0.count > 2 && $0[2] == "Sleep Stage" }
        XCTAssertEqual(stageRows.count, 4, "Should have 4 sleep stage rows")
    }

    func testCSV_fullDayGranular_aggregateRowsStillFiveColumns() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDayGranular)
        let heartRows = rows(for: "Heart", in: allRows)
        let aggregateRows = heartRows.filter { $0.count > 2 && $0[2] == "Resting Heart Rate" }
        XCTAssertFalse(aggregateRows.isEmpty, "Should have aggregate heart rows")
        for row in aggregateRows {
            // Aggregate rows have 5 columns (or 6 with empty timestamp)
            if row.count == 6 {
                XCTAssertTrue(row[5].isEmpty, "Aggregate rows should have empty timestamp column")
            } else {
                XCTAssertEqual(row.count, 5, "Aggregate rows should have 5 columns")
            }
        }
    }

    func testCSV_fullDay_noSampleRows() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay)
        let heartRows = rows(for: "Heart", in: allRows)
        let heartSampleRows = heartRows.filter { $0.count > 2 && $0[2] == "Heart Rate Sample" }
        XCTAssertTrue(heartSampleRows.isEmpty, "fullDay without granular data should not have heart sample rows")

        let vitalRows = rows(for: "Vitals", in: allRows)
        let bloodPressureRows = vitalRows.filter { $0.count > 2 && $0[2] == "Blood Pressure Sample" }
        XCTAssertTrue(bloodPressureRows.isEmpty, "fullDay without granular data should not have blood pressure sample rows")
    }

    // MARK: - Row Consistency

    func testCSV_fullDay_allRowsHaveFiveColumns() {
        let csv = ExportFixtures.fullDay.toCSV(customization: CSVContractCustomizations.metric)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        // Note: some values might contain commas in quoted strings
        // Aggregate rows have 5 columns; sample rows (with timestamp) have 6.
        // Header always has 6 columns.
        for (i, line) in lines.enumerated() {
            if !line.contains("\"") {
                let cols = line.components(separatedBy: ",")
                XCTAssertTrue(cols.count == 5 || cols.count == 6, "Row \(i) should have 5 or 6 columns: \(line)")
            }
        }
    }

    // MARK: - Date Format

    func testCSV_fullDay_dateColumnMatchesFormat() {
        let (_, allRows) = parseCSV(ExportFixtures.fullDay, customization: CSVContractCustomizations.metric)
        let dateString = CSVContractCustomizations.metric.dateFormat.format(
            date: ExportFixtures.referenceDate,
            timeZone: ExportFixtures.timeContext.calendarTimeZone
        )
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
