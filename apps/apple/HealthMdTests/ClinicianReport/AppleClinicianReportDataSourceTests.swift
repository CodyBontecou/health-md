import XCTest
@testable import HealthMd

@MainActor
final class AppleClinicianReportDataSourceTests: XCTestCase {
    func testOnlyCorrelationReferencedBloodPressureComponentsArePaired() async throws {
        let day = Date(timeIntervalSince1970: 1_767_225_600) // synthetic fixed day
        let systolicID = UUID()
        let diastolicID = UUID()
        let unrelatedID = UUID()
        let correlationID = UUID()
        let records = [
            quantity(id: systolicID, type: "HKQuantityTypeIdentifierBloodPressureSystolic", value: 122, unit: "mmHg", date: day),
            quantity(id: diastolicID, type: "HKQuantityTypeIdentifierBloodPressureDiastolic", value: 78, unit: "mmHg", date: day),
            quantity(id: unrelatedID, type: "HKQuantityTypeIdentifierBloodPressureSystolic", value: 199, unit: "mmHg", date: day.addingTimeInterval(2)),
            HealthKitRecord(
                originalUUID: correlationID,
                objectTypeIdentifier: "HKCorrelationTypeIdentifierBloodPressure",
                recordKind: .correlation,
                selectedMetricIDs: ["blood_pressure_systolic", "blood_pressure_diastolic"],
                includedBecause: .selectedMetric,
                startDate: day,
                endDate: day,
                sourceRevision: revision,
                payload: .correlation(componentUUIDs: [systolicID, diastolicID])
            )
        ]
        let data = HealthData(date: day, healthKitRecordArchive: archive(records: records, day: day), healthKitRecordCaptureStatus: .complete)
        let source = AppleClinicianReportDataSource(fetch: { _, selection, _ in
            XCTAssertTrue(selection.enabledMetrics.contains("blood_pressure_systolic"))
            XCTAssertTrue(selection.enabledMetrics.contains("blood_pressure_diastolic"))
            return data
        }, now: { day })
        let input = try await source.load(configuration: ReportConfiguration(
            dateRange: ReportDateRange(startDate: day, endDate: day),
            selectedMetrics: [.bloodPressure]
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(input.bloodPressureObservations.count, 1)
        XCTAssertEqual(input.bloodPressureObservations[0].systolic, 122)
        XCTAssertEqual(input.bloodPressureObservations[0].diastolic, 78)
        XCTAssertEqual(input.bloodPressureObservations[0].stableID, "healthkit:\(correlationID.uuidString)")
    }

    func testCanonicalScalarKeepsIdentityManualEntryAndSource() async throws {
        let day = Date(timeIntervalSince1970: 1_767_225_600)
        let id = UUID()
        let record = HealthKitRecord(
            originalUUID: id,
            objectTypeIdentifier: "HKQuantityTypeIdentifierBloodGlucose",
            recordKind: .quantity,
            selectedMetricIDs: ["blood_glucose"],
            includedBecause: .selectedMetric,
            startDate: day,
            endDate: day,
            sourceRevision: revision,
            device: HealthKitDeviceProvenance(model: "Synthetic Watch"),
            metadata: ["HKWasUserEntered": .bool(true)],
            payload: .quantity(.init(value: 104, unit: "mg/dL"))
        )
        let data = HealthData(date: day, vitals: VitalsData(bloodGlucoseAvg: 999), healthKitRecordArchive: archive(records: [record], day: day), healthKitRecordCaptureStatus: .complete)
        let source = AppleClinicianReportDataSource(fetch: { _, _, _ in data }, now: { day })
        let input = try await source.load(configuration: ReportConfiguration(dateRange: .init(startDate: day, endDate: day), selectedMetrics: [.bloodGlucose]), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(input.scalarObservations.map(\.value), [104])
        XCTAssertTrue(input.dailyValues.isEmpty)
        XCTAssertEqual(input.scalarObservations[0].stableID, "healthkit:\(id.uuidString)")
        let sourceLabel = input.scalarObservations[0].source?.displayLabel(using: ClinicianReportCopy(locale: Locale(identifier: "en_US")))
        XCTAssertTrue(sourceLabel?.contains("manual entry") == true)
        XCTAssertTrue(sourceLabel?.contains("Health Source") == true)
    }

    func testCanonicalOxygenNormalizesPercentAndWeightUsesLatestDailyValue() async throws {
        let day = Date(timeIntervalSince1970: 1_767_225_600)
        let oxygen = HealthKitRecord(
            originalUUID: UUID(),
            objectTypeIdentifier: "HKQuantityTypeIdentifierOxygenSaturation",
            recordKind: .quantity,
            selectedMetricIDs: ["blood_oxygen"],
            includedBecause: .selectedMetric,
            startDate: day,
            endDate: day,
            sourceRevision: revision,
            payload: .quantity(.init(value: 0.96, unit: "%"))
        )
        let firstWeight = HealthKitRecord(
            originalUUID: UUID(),
            objectTypeIdentifier: "HKQuantityTypeIdentifierBodyMass",
            recordKind: .quantity,
            selectedMetricIDs: ["weight"],
            includedBecause: .selectedMetric,
            startDate: day,
            endDate: day,
            sourceRevision: revision,
            payload: .quantity(.init(value: 80, unit: "kg"))
        )
        let latestWeight = HealthKitRecord(
            originalUUID: UUID(),
            objectTypeIdentifier: "HKQuantityTypeIdentifierBodyMass",
            recordKind: .quantity,
            selectedMetricIDs: ["weight"],
            includedBecause: .selectedMetric,
            startDate: day.addingTimeInterval(3_600),
            endDate: day.addingTimeInterval(3_600),
            sourceRevision: revision,
            payload: .quantity(.init(value: 79, unit: "kg"))
        )
        let data = HealthData(
            date: day,
            healthKitRecordArchive: archive(records: [oxygen, firstWeight, latestWeight], day: day),
            healthKitRecordCaptureStatus: .complete
        )
        let source = AppleClinicianReportDataSource(fetch: { _, _, _ in data }, now: { day })
        let input = try await source.load(
            configuration: ReportConfiguration(
                dateRange: .init(startDate: day, endDate: day),
                selectedMetrics: [.oxygenSaturation, .weight]
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let oxygenValue = try XCTUnwrap(input.scalarObservations.first { $0.metric == .oxygenSaturation }?.value)
        XCTAssertEqual(oxygenValue, 0.96, accuracy: 0.000_001)
        let weights = input.dailyValues.filter { $0.metric == .weight }
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(weights[0].value, 79)
        let report = ClinicianReportGenerator(locale: Locale(identifier: "en_US")).generate(input)
        XCTAssertEqual(report.sections.first { $0.metric == .oxygenSaturation }?.facts.first { $0.label == "Median" }?.value, "96.0 %")
        XCTAssertEqual(report.sections.first { $0.metric == .weight }?.availabilitySummary, "Days with data: 1/1")
    }

    func testWorkoutAdapterPreservesNormalizedTypeForPinnedLocalization() async throws {
        let day = Date(timeIntervalSince1970: 1_767_225_600)
        let data = HealthData(
            date: day,
            workouts: [WorkoutData(
                workoutType: .running,
                startTime: day,
                duration: 1_800,
                calories: nil,
                distance: nil
            )],
            healthKitRecordArchive: archive(records: [], day: day),
            healthKitRecordCaptureStatus: .complete
        )
        let source = AppleClinicianReportDataSource(fetch: { _, _, _ in data }, now: { day })
        let input = try await source.load(
            configuration: ReportConfiguration(
                dateRange: .init(startDate: day, endDate: day),
                selectedMetrics: [.workouts],
                detailLevel: .summaryAndReadings
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "de_DE")
        )
        XCTAssertEqual(input.workoutObservations.first?.type, .running)
        XCTAssertEqual(
            ClinicianReportGenerator(locale: Locale(identifier: "de_DE"))
                .generate(input).sections.first?.table?.rows.first?[2],
            "Laufen"
        )
    }

    func testDayFailureBecomesWarningAndDoesNotDiscardOtherDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let second = calendar.date(byAdding: .day, value: 1, to: first)!
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            if calendar.isDate(date, inSameDayAs: first) { throw CocoaError(.fileReadNoPermission) }
            return HealthData(
                date: second,
                activity: ActivityData(steps: 1234),
                healthKitRecordArchive: self.archive(records: [], day: second),
                healthKitRecordCaptureStatus: .complete
            )
        }, now: { second })
        let input = try await source.load(configuration: ReportConfiguration(dateRange: .init(startDate: first, endDate: second), selectedMetrics: [.steps]), timeZone: calendar.timeZone)
        XCTAssertEqual(input.dailyValues.map(\.value), [1234])
        XCTAssertEqual(input.warnings.count, 1)
    }

    func testLoadReportsProgressForEveryRequestedDayIncludingFailures() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let last = calendar.date(byAdding: .day, value: 2, to: first)!
        var fetchedDay = 0
        let source = AppleClinicianReportDataSource(fetch: { date, _, _ in
            fetchedDay += 1
            if fetchedDay == 2 { throw CocoaError(.fileReadNoPermission) }
            return HealthData(date: date, healthKitRecordCaptureStatus: .complete)
        }, now: { last })
        var updates: [String] = []

        _ = try await source.load(
            configuration: ReportConfiguration(
                dateRange: .init(startDate: first, endDate: last),
                selectedMetrics: [.steps]
            ),
            timeZone: calendar.timeZone,
            progress: { completed, total in updates.append("\(completed)/\(total)") }
        )

        XCTAssertEqual(updates, ["0/3", "1/3", "2/3", "3/3"])
    }

    private var revision: HealthKitSourceRevision {
        HealthKitSourceRevision(name: "Health Source", bundleIdentifier: "example.synthetic")
    }

    private func quantity(id: UUID, type: String, value: Double, unit: String, date: Date) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: id,
            objectTypeIdentifier: type,
            recordKind: .quantity,
            selectedMetricIDs: ["blood_pressure_systolic", "blood_pressure_diastolic"],
            includedBecause: .relationshipDependency,
            startDate: date,
            endDate: date,
            sourceRevision: revision,
            payload: .quantity(.init(value: value, unit: unit))
        )
    }

    private func archive(records: [HealthKitRecord], day: Date) -> HealthKitRecordArchive {
        HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-01-01",
                intervalStart: day,
                intervalEnd: day.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            records: records
        )
    }
}
