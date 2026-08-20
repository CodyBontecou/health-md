import XCTest
@testable import HealthMd

private enum HealthRollupTestSettings {
    static func make() -> AdvancedExportSettings {
        let suiteName = "healthmd.tests.rollups.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown]
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = true
        settings.generateYearlyRollups = true
        settings.formatCustomization.unitPreference = .metric
        return LifecycleHarness.retain(settings)
    }
}

final class HealthRollupExporterTests: XCTestCase {

    func testWeeklyRollupAggregatesRepresentativeRules() throws {
        let settings = HealthRollupTestSettings.make()
        let summaries = HealthRollupExporter.makeSummaries(
            from: [makeDay(2026, 3, 14, steps: 1_000, activeCalories: 100, restingHR: 60, bloodOxygenMin: 0.95, workoutAverageHR: 100, workoutDuration: 3_600),
                   makeDay(2026, 3, 15, steps: 2_000, activeCalories: 150, restingHR: 70, bloodOxygenMin: 0.92, workoutAverageHR: 150, workoutDuration: 7_200)],
            settings: settings,
            periods: [.weekly],
            generatedAt: makeDate(2026, 6, 14)
        )

        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.period, .weekly)
        XCTAssertEqual(summary.periodID, "2026-W11")
        XCTAssertEqual(summary.daysExpected, 7)
        XCTAssertEqual(summary.daysCounted, 2)
        XCTAssertEqual(summary.coveragePercent, 100.0 * 2.0 / 7.0, accuracy: 0.01)

        XCTAssertEqual(try metric("steps", in: summary).primaryValue, "3,000")
        XCTAssertEqual(try metric("active_calories", in: summary).primaryValue, "250")
        XCTAssertEqual(try metric("resting_heart_rate", in: summary).primaryValue, "65")
        XCTAssertEqual(try metric("blood_oxygen_min", in: summary).primaryValue, "92")
        XCTAssertEqual(try metric("workout_avg_heart_rate", in: summary).primaryValue, "133.33")
        XCTAssertEqual(try metric("workout_avg_heart_rate", in: summary).rule, "weighted_average")
    }

    func testWeeklyRollupRendersISOWeekBoundsInSuppliedCalendarTimeZone() throws {
        let settings = HealthRollupTestSettings.make()
        var utcCalendar = Calendar(identifier: .iso8601)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sourceDate = try XCTUnwrap(utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: 2026,
            month: 7,
            day: 11,
            hour: 12
        )))
        var data = HealthData(date: sourceDate)
        data.activity.steps = 1_000

        let summary = try XCTUnwrap(HealthRollupGenerator.generate(
            from: [data],
            settings: settings,
            periods: [.weekly],
            generatedAt: sourceDate,
            calendar: utcCalendar
        ).first)
        let json = try XCTUnwrap(summary.toRollupJSON().data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual(summary.periodID, "2026-W28")
        XCTAssertEqual(payload["start_date"] as? String, "2026-07-06")
        XCTAssertEqual(payload["end_date"] as? String, "2026-07-12")
        XCTAssertTrue(summary.toRollupMarkdown().contains("start_date: 2026-07-06"))
        XCTAssertTrue(summary.toRollupObsidianBases().contains("end_date: 2026-07-12"))
        XCTAssertTrue(summary.toRollupCSV().contains("weekly,2026-W28,2026-07-06,2026-07-12"))
    }

    func testWeeklyRollupCountsFetchedSourceDaysEvenWhenMetricsAreEmpty() throws {
        let settings = HealthRollupTestSettings.make()
        var fullWeek: [HealthData] = []
        for day in 9...15 {
            if day <= 13 {
                fullWeek.append(makeDay(2026, 3, day, steps: 1_000))
            } else {
                fullWeek.append(HealthData(date: makeDate(2026, 3, day)))
            }
        }

        let summary = try XCTUnwrap(HealthRollupExporter.makeSummaries(
            from: fullWeek,
            settings: settings,
            periods: [.weekly],
            generatedAt: makeDate(2026, 6, 14)
        ).first)

        XCTAssertEqual(summary.daysExpected, 7)
        XCTAssertEqual(summary.daysCounted, 7)
        XCTAssertEqual(summary.coveragePercent, 100.0, accuracy: 0.01)
        XCTAssertEqual(try metric("steps", in: summary).primaryValue, "5,000")
        XCTAssertEqual(try metric("steps", in: summary).daysCounted, 5)
    }

    func testMarkdownRollupIsSelfDescribingAndHumanReadable() throws {
        let settings = HealthRollupTestSettings.make()
        let summary = try XCTUnwrap(HealthRollupExporter.makeSummaries(
            from: [makeDay(2026, 3, 15, steps: 12_500, activeCalories: 520, restingHR: 58, bloodOxygenMin: 0.95, workoutAverageHR: 142, workoutDuration: 1_800)],
            settings: settings,
            periods: [.weekly],
            generatedAt: makeDate(2026, 6, 14)
        ).first)

        let markdown = summary.markdown()
        XCTAssertTrue(markdown.contains("schema: healthmd.rollup_summary"))
        XCTAssertTrue(markdown.contains("schema_version: \(HealthMdExportSchema.version)"))
        XCTAssertTrue(markdown.contains("rollup_period: weekly"))
        XCTAssertTrue(markdown.contains("period_id: 2026-W11"))
        XCTAssertTrue(markdown.contains("days_expected: 7"))
        XCTAssertTrue(markdown.contains("days_counted: 1"))
        XCTAssertTrue(markdown.contains("units:"))
        XCTAssertTrue(markdown.contains("  steps: steps"))
        XCTAssertTrue(markdown.contains("# Weekly Health Summary — 2026-W11"))
        XCTAssertTrue(markdown.contains("## Activity"))
        XCTAssertTrue(markdown.contains("| Steps | `steps` | 12,500 | steps | 1/7 | sum |"))
        XCTAssertTrue(markdown.contains("## Roll-up notes"))
    }

    func testMarkdownRollupKeepsMultilineValuesInsideTableCells() throws {
        let window = HealthRollupPeriodWindow.window(
            containing: makeDate(2026, 6, 28),
            period: .weekly,
            calendar: Calendar(identifier: .gregorian)
        )
        let summary = RollupDataSnapshot(
            window: window,
            generatedAt: makeDate(2026, 6, 28),
            sourceDates: [makeDate(2026, 6, 28)],
            metrics: [
                HealthRollupMetricSummary(
                    key: "medication_details",
                    canonicalKey: "medication_details",
                    displayName: "Medication Details",
                    category: "Medications",
                    unit: "",
                    rule: "latest",
                    primaryValue: "  - name: \"Aspirin, 81 mg\"\n    concept_identifier: \"rxnorm:123\"\n    note: \"contains | pipe\"",
                    daysCounted: 1,
                    statistics: [],
                    notes: nil
                )
            ]
        )

        let markdown = summary.markdown()
        let row = try XCTUnwrap(markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.contains("`medication_details`") })

        XCTAssertTrue(row.contains("Aspirin, 81 mg"))
        XCTAssertTrue(row.contains("<br>    concept_identifier"))
        XCTAssertTrue(row.contains("contains \\| pipe"))
        XCTAssertFalse(markdown.contains("\n    concept_identifier:"))
        XCTAssertTrue(markdown.contains("## Roll-up notes"))
    }

    func testRollupsRequireAnEnabledPeriodToggle() {
        let settings = HealthRollupTestSettings.make()
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false

        let summaries = HealthRollupExporter.makeSummaries(
            from: [makeDay(2026, 3, 15, steps: 1_000)],
            settings: settings
        )

        XCTAssertTrue(summaries.isEmpty)
    }

    func testOutputTargetsCoverEverySelectedFormat() throws {
        let settings = HealthRollupTestSettings.make()
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false

        let summary = try XCTUnwrap(HealthRollupExporter.makeSummaries(
            from: [makeDay(2026, 3, 15, steps: 1_000)],
            settings: settings,
            periods: [.weekly]
        ).first)

        let targets = HealthRollupExporter.outputTargets(
            for: [summary],
            healthSubfolder: "Health",
            settings: settings
        )

        XCTAssertEqual(targets.map(\.format), [.csv, .json, .markdown, .obsidianBases])
        XCTAssertEqual(targets.map(\.filename), ["2026-W11.csv", "2026-W11.json", "2026-W11.md", "2026-W11-bases.md"])
        XCTAssertTrue(try XCTUnwrap(targets.first { $0.format == .json }).content.contains("\"schema\" : \"healthmd.rollup_summary\""))
        XCTAssertTrue(try XCTUnwrap(targets.first { $0.format == .csv }).content.contains("Period,Period ID,Start Date"))
        XCTAssertTrue(try XCTUnwrap(targets.first { $0.format == .obsidianBases }).content.contains("rollup_metrics:"))
    }

    private func metric(_ key: String, in summary: HealthRollupSummary) throws -> HealthRollupMetricSummary {
        try XCTUnwrap(summary.metrics.first { $0.key == key }, "Missing roll-up metric: \(key)")
    }

    private func makeDay(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        steps: Int,
        activeCalories: Double? = nil,
        restingHR: Double? = nil,
        bloodOxygenMin: Double? = nil,
        workoutAverageHR: Double? = nil,
        workoutDuration: TimeInterval? = nil
    ) -> HealthData {
        let date = makeDate(year, month, day)
        var data = HealthData(date: date)
        data.activity.steps = steps
        data.activity.activeCalories = activeCalories
        data.heart.restingHeartRate = restingHR
        data.vitals.bloodOxygenMin = bloodOxygenMin
        if let workoutAverageHR, let workoutDuration {
            data.workouts = [
                WorkoutData(
                    workoutType: .running,
                    startTime: date,
                    duration: workoutDuration,
                    calories: nil,
                    distance: nil,
                    avgHeartRate: workoutAverageHR
                )
            ]
        }
        return data
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
