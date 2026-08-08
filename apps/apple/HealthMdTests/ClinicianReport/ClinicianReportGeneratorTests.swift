import XCTest
@testable import HealthMd

final class ClinicianReportGeneratorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }

    func testRangesAreInclusiveFutureClampedAndDSTSafe() {
        let today = date(2026, 8, 8)
        let range = ReportDateRange.preset(.days30, today: today, calendar: calendar)
        XCTAssertEqual(range.inclusiveDayCount(calendar: calendar), 30)
        let reversed = ReportDateRange.normalized(start: date(2026, 8, 12), end: date(2026, 8, 4), today: today, calendar: calendar)
        XCTAssertEqual(reversed.startDate, date(2026, 8, 4))
        XCTAssertEqual(reversed.endDate, today)
        let spring = ReportDateRange(startDate: date(2026, 3, 8), endDate: date(2026, 3, 8)).interval(calendar: calendar)
        XCTAssertEqual(spring.upperBound.timeIntervalSince(spring.lowerBound), 23 * 3600)
        XCTAssertTrue(spring.contains(spring.lowerBound))
        XCTAssertFalse(spring.contains(spring.upperBound))
    }

    func testMedianCoverageAndStableIdentityDedupe() {
        let range = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 30))
        let configuration = ReportConfiguration(dateRange: range, selectedMetrics: [.heartRate], detailLevel: .summaryAndReadings)
        let input = ClinicianReportInput(
            configuration: configuration,
            calendar: calendar,
            generatedAt: date(2026, 3, 31),
            scalarObservations: [
                .init(metric: .heartRate, timestamp: date(2026, 3, 1, 10), value: 60, stableID: "same", source: .init(label: "Watch")),
                .init(metric: .heartRate, timestamp: date(2026, 3, 1, 10), value: 60, stableID: "same", source: .init(label: "Watch")),
                .init(metric: .heartRate, timestamp: date(2026, 3, 1, 11), value: 64),
                .init(metric: .heartRate, timestamp: date(2026, 3, 2, 11), value: 66)
            ]
        )
        let section = ClinicianReportGenerator(locale: Locale(identifier: "en_US")).generate(input).sections[0]
        XCTAssertEqual(section.facts.first { $0.label == "Readings" }?.value, "3")
        XCTAssertEqual(section.facts.first { $0.label == "Median" }?.value, "64.0 bpm")
        XCTAssertEqual(section.table?.rows.count, 3)
        XCTAssertTrue(section.coverageDisclosure?.contains("2 of 30 days") == true)
    }

    func testBloodPressureMeansAndPulseIsAbsent() {
        let range = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 30))
        let input = ClinicianReportInput(
            configuration: ReportConfiguration(dateRange: range, selectedMetrics: [.bloodPressure], detailLevel: .summaryAndReadings),
            calendar: calendar,
            generatedAt: date(2026, 3, 31),
            bloodPressureObservations: [
                .init(timestamp: date(2026, 3, 3, 8), systolic: 120, diastolic: 80, stableID: nil, source: nil),
                .init(timestamp: date(2026, 3, 4, 8), systolic: 140, diastolic: 90, stableID: nil, source: nil)
            ]
        )
        let section = ClinicianReportGenerator(locale: Locale(identifier: "en_US")).generate(input).sections[0]
        XCTAssertEqual(section.facts.first { $0.label == "Average" }?.value, "130/85 mmHg")
        XCTAssertFalse(section.table?.columns.contains("Pulse") ?? true)
    }

    func testUnitConversionsAndLargeReadingTable() {
        let range = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 30))
        let weightInput = ClinicianReportInput(
            configuration: ReportConfiguration(dateRange: range, selectedMetrics: [.weight], unitPreference: .imperial),
            calendar: calendar,
            generatedAt: date(2026, 3, 31),
            dailyValues: [
                .init(metric: .weight, date: range.startDate, value: 80),
                .init(metric: .weight, date: range.endDate, value: 78)
            ]
        )
        let weightFacts = ClinicianReportGenerator(locale: Locale(identifier: "en_US")).generate(weightInput).sections[0].facts
        XCTAssertTrue(weightFacts.first { $0.label == "First" }?.value.contains("176.4 lbs") == true)
        XCTAssertTrue(weightFacts.first { $0.label == "Change over period" }?.value.contains("-4.4 lbs") == true)

        let start = range.interval(calendar: calendar).lowerBound
        let readings = (0..<10_001).map { ScalarReportObservation(metric: .heartRate, timestamp: start.addingTimeInterval(Double($0)), value: 50 + Double($0 % 100)) }
        let largeInput = ClinicianReportInput(
            configuration: ReportConfiguration(dateRange: range, selectedMetrics: [.heartRate], detailLevel: .summaryAndReadings),
            calendar: calendar,
            generatedAt: date(2026, 3, 31),
            scalarObservations: readings
        )
        XCTAssertEqual(ClinicianReportGenerator(locale: Locale(identifier: "en_US")).generate(largeInput).sections[0].table?.rows.count, 10_001)
    }

    func testEmptySelectedMetricStillProducesSection() {
        let range = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 1))
        let input = ClinicianReportInput(configuration: ReportConfiguration(dateRange: range, selectedMetrics: [.bloodGlucose]), calendar: calendar, generatedAt: date(2026, 3, 2))
        let copy = ClinicianReportCopy(locale: Locale(identifier: "en_US"))
        XCTAssertEqual(ClinicianReportGenerator(locale: Locale(identifier: "en_US")).generate(input).sections[0].noDataMessage, copy.string(.no_data))
    }

    func testLocaleIsPinnedAcrossModelVocabularyAndPlaceholderFormatting() {
        XCTAssertEqual(ClinicianReportCopy.Key.allCases.count, 194)
        let range = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 3))
        let input = ClinicianReportInput(
            configuration: ReportConfiguration(dateRange: range, selectedMetrics: [.steps]),
            calendar: calendar,
            generatedAt: date(2026, 3, 4),
            dailyValues: [.init(metric: .steps, date: range.startDate, value: 1234)]
        )
        let germanCopy = ClinicianReportCopy(locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(germanCopy.format(.coverage, "1", "3", "2"), "Daten für 1 von 3 Tagen verfügbar. Für die verbleibenden 2 Tage waren in Health.md keine Daten verfügbar.")
        let german = ClinicianReportGenerator(locale: Locale(identifier: "de_DE")).generate(input)
        XCTAssertEqual(german.title, "Gesundheitsübersicht")
        XCTAssertEqual(german.languageTag, "de")
        XCTAssertEqual(german.sections[0].localizedTitle, "Schritte")
        XCTAssertEqual(german.sections[0].facts.first?.label, "Tage mit Daten")
        XCTAssertFalse(german.sections[0].coverageDisclosure?.contains("Data available") ?? true)

        let japanese = ClinicianReportGenerator(locale: Locale(identifier: "ja_JP")).generate(input)
        XCTAssertEqual(japanese.title, "健康サマリー")
        XCTAssertEqual(japanese.sections[0].localizedTitle, "歩数")
        XCTAssertFalse(japanese.disclaimer.contains("This report summarizes"))
    }

    func testLocaleResolutionUsesSupportedResourcesAndEnglishFallback() {
        let unsupported = ClinicianReportCopy(locale: Locale(identifier: "ar_SA"))
        XCTAssertEqual(unsupported.localeIdentifier, "en")
        XCTAssertEqual(unsupported.languageTag, "en")
        XCTAssertEqual(unsupported.paperRegionCode, "SA")
        XCTAssertEqual(unsupported.string(.document_title), "Health Summary")
        let fallbackRange = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 1))
        let fallbackInput = ClinicianReportInput(
            configuration: ReportConfiguration(dateRange: fallbackRange, selectedMetrics: []),
            calendar: calendar,
            generatedAt: date(2026, 3, 2)
        )
        let fallbackReport = ClinicianReportGenerator(locale: Locale(identifier: "ar_SA")).generate(fallbackInput)
        XCTAssertEqual(fallbackReport.languageTag, "en")
        XCTAssertEqual(fallbackReport.paperRegionCode, "SA")
        XCTAssertEqual(fallbackReport.title, "Health Summary")

        let german = ClinicianReportCopy(locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(german.localeIdentifier, "de")
        XCTAssertEqual(german.paperRegionCode, "DE")
        XCTAssertEqual(german.string(.document_title), "Gesundheitsübersicht")
        XCTAssertEqual(WorkoutType.allCases.count, 84)
        XCTAssertTrue(WorkoutType.allCases.allSatisfy {
            !german.workoutType($0).isEmpty && !german.workoutType($0).hasPrefix("clinician_report_")
        })

        let brazilianPortuguese = ClinicianReportCopy(locale: Locale(identifier: "pt_BR"))
        XCTAssertEqual(brazilianPortuguese.localeIdentifier, "pt-BR")
        XCTAssertEqual(brazilianPortuguese.string(.metric_workouts), "Exercício / Treinos")

        let simplifiedChinese = ClinicianReportCopy(locale: Locale(identifier: "zh_Hans_CN"))
        XCTAssertEqual(simplifiedChinese.localeIdentifier, "zh-Hans")
        XCTAssertEqual(simplifiedChinese.string(.metric_workouts), "锻炼 / 训练")
    }

    func testWorkoutTypesRespiratoryUnitAndWeightNumbersUseResolvedLocale() {
        let range = ReportDateRange(startDate: date(2026, 3, 1), endDate: date(2026, 3, 2))
        let input = ClinicianReportInput(
            configuration: ReportConfiguration(
                dateRange: range,
                selectedMetrics: [.respiratoryRate, .weight, .workouts],
                detailLevel: .summaryAndReadings,
                unitPreference: .metric
            ),
            calendar: calendar,
            generatedAt: date(2026, 3, 3),
            scalarObservations: [
                .init(metric: .respiratoryRate, timestamp: date(2026, 3, 1, 8), value: 15)
            ],
            dailyValues: [
                .init(metric: .weight, date: range.startDate, value: 80.26),
                .init(metric: .weight, date: range.endDate, value: 79.75)
            ],
            workoutObservations: [
                .init(timestamp: date(2026, 3, 1, 9), type: .running, durationMinutes: 30, stableID: nil, source: nil)
            ]
        )
        let report = ClinicianReportGenerator(locale: Locale(identifier: "de_DE")).generate(input)
        let respiratory = try! XCTUnwrap(report.sections.first { $0.metric == .respiratoryRate })
        XCTAssertTrue(respiratory.facts.contains { $0.value.contains("Atemzüge/min") })
        let weight = try! XCTUnwrap(report.sections.first { $0.metric == .weight })
        XCTAssertTrue(weight.facts.contains { $0.value.contains("80,3 kg") })
        let workouts = try! XCTUnwrap(report.sections.first { $0.metric == .workouts })
        XCTAssertTrue(workouts.facts.contains { $0.value.contains("Laufen") })
        XCTAssertEqual(workouts.table?.rows.first?[2], "Laufen")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
