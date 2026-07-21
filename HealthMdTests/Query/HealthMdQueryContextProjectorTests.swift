import XCTest
@testable import HealthMd

@MainActor
final class HealthMdQueryContextProjectorTests: XCTestCase {
    func testProjectsRepresentativeTypedSummaryFamiliesAndKeepsZeroDistinctFromEmpty() throws {
        let start = iso("2026-01-15T00:00:00Z")
        let end = iso("2026-01-16T00:00:00Z")
        let manifest = HealthKitQueryManifest(results: [
            query("steps", metricID: "steps", status: .success, count: 1, start: start, end: end),
            query("sleep", metricID: "sleep_total", status: .success, count: 0, start: start, end: end)
        ])
        let archive = makeArchive(start: start, end: end, queryManifest: manifest)
        let data = HealthData(
            date: start,
            timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
            activity: ActivityData(steps: 0),
            heart: HeartData(restingHeartRate: 61),
            nutrition: NutritionData(protein: 42.5),
            mindfulness: MindfulnessData(mindfulMinutes: 10, mindfulSessions: 2),
            reproductiveHealth: ReproductiveHealthData(menstrualFlow: "light"),
            vitamins: VitaminsData(vitaminD: 12.5),
            minerals: MineralsData(iron: 8.25),
            healthKitRecordArchive: archive
        )

        let day = try HealthMdQueryContextProjector.project(data, options: .init(enabledMetricIDs: [
            "steps", "sleep_total", "resting_heart_rate", "dietary_protein",
            "mindful_minutes", "menstrual_flow", "vitamin_d", "iron"
        ]))

        XCTAssertEqual(metric("steps", in: day).value, .quantity(value: 0, unit: "steps"))
        XCTAssertEqual(metric("steps", in: day).status, .available)
        XCTAssertEqual(metric("steps", in: day).dailyAggregation, .sum)
        XCTAssertNil(metric("sleep_total", in: day).value)
        XCTAssertEqual(metric("sleep_total", in: day).status, .completeEmpty)
        XCTAssertEqual(metric("sleep_total", in: day).dailyAggregation, .durationSum)
        XCTAssertEqual(metric("resting_heart_rate", in: day).value, .quantity(value: 61, unit: "bpm"))
        XCTAssertEqual(metric("dietary_protein", in: day).value, .quantity(value: 42.5, unit: "g"))
        XCTAssertEqual(metric("mindful_minutes", in: day).value, .duration(seconds: 600))
        XCTAssertEqual(metric("menstrual_flow", in: day).value, .category(.init(identifier: "light", display: "light")))
        XCTAssertEqual(metric("vitamin_d", in: day).value, .quantity(value: 12.5, unit: "µg"))
        XCTAssertEqual(metric("iron", in: day).value, .quantity(value: 8.25, unit: "mg"))
        XCTAssertEqual(day.source.schema, HealthMdExportSchema.identifier)
        XCTAssertEqual(day.source.schemaVersion, 7)
        XCTAssertFalse(day.source.digest.isEmpty)
    }

    func testDerivesEveryIncompleteStatusWithoutFabricatingValues() throws {
        let start = iso("2026-02-01T00:00:00Z")
        let end = iso("2026-02-02T00:00:00Z")
        let archive = makeArchive(
            start: start,
            end: end,
            captureStatus: .partial,
            queryManifest: .init(results: [
                query("failed", metricID: "weight", status: .failure, count: 0, start: start, end: end),
                query("unsupported", metricID: "height", status: .unsupported, count: 0, start: start, end: end),
                query("skipped", metricID: "bmi", status: .skipped, count: 0, start: start, end: end),
                query("cancelled", metricID: "body_fat", status: .cancelled, count: 0, start: start, end: end),
                query("empty", metricID: "lean_body_mass", status: .success, count: 0, start: start, end: end),
                query("unsynced", metricID: "waist_circumference", status: .success, count: 1, start: start, end: end)
            ])
        )
        let data = HealthData(
            date: start,
            timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: archive
        )
        let day = try HealthMdQueryContextProjector.project(data, options: .init(
            enabledMetricIDs: [
                "weight", "height", "bmi", "body_fat", "lean_body_mass",
                "waist_circumference", "steps", "resting_heart_rate"
            ],
            unavailableMetricStatuses: [
                "steps": .notRequested,
                "resting_heart_rate": .legacyUnavailable
            ]
        ))

        XCTAssertEqual(metric("weight", in: day).status, .failed)
        XCTAssertEqual(metric("height", in: day).status, .unsupported)
        XCTAssertEqual(metric("bmi", in: day).status, .skipped)
        XCTAssertEqual(metric("body_fat", in: day).status, .cancelled)
        XCTAssertEqual(metric("lean_body_mass", in: day).status, .completeEmpty)
        XCTAssertEqual(metric("waist_circumference", in: day).status, .notSynchronized)
        XCTAssertEqual(metric("steps", in: day).status, .notRequested)
        XCTAssertEqual(metric("resting_heart_rate", in: day).status, .legacyUnavailable)
        XCTAssertTrue(day.metrics.allSatisfy { $0.value == nil })
        XCTAssertEqual(day.status, .partial)

        let partial = try HealthMdQueryContextProjector.project(
            HealthData(
                date: start,
                timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
                partialFailures: [.init(
                    date: start,
                    dataType: "steps",
                    dateRangeDescription: "2026-02-01",
                    errorDescription: "The capture branch failed."
                )],
                healthKitRecordCaptureStatus: .partial
            ),
            options: .init(enabledMetricIDs: ["steps"])
        )
        XCTAssertEqual(metric("steps", in: partial).status, .partial)

        let notRequested = try HealthMdQueryContextProjector.project(
            HealthData(date: start, timeContext: .init(calendarTimeZoneIdentifier: "UTC"), healthKitRecordCaptureStatus: .notRequested),
            options: .init(enabledMetricIDs: ["steps"])
        )
        XCTAssertEqual(metric("steps", in: notRequested).status, .notRequested)

        let legacy = try HealthMdQueryContextProjector.project(
            HealthData(date: start, timeContext: .init(calendarTimeZoneIdentifier: "UTC"), healthKitRecordCaptureStatus: .legacyUnavailable),
            options: .init(enabledMetricIDs: ["steps"])
        )
        XCTAssertEqual(metric("steps", in: legacy).status, .legacyUnavailable)
    }

    func testPreservesDSTOwnershipAndCreatesResolvableCanonicalEvidenceAndWorkout() throws {
        let start = iso("2026-03-08T08:00:00Z")
        let end = iso("2026-03-09T07:00:00Z")
        let workoutUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let quantityUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let record = HealthKitRecord(
            originalUUID: quantityUUID,
            objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
            recordKind: .quantity,
            selectedMetricIDs: ["steps"],
            includedBecause: .selectedMetric,
            startDate: start.addingTimeInterval(3_600),
            endDate: start.addingTimeInterval(3_601),
            sourceRevision: sourceRevision,
            payload: .quantity(.init(value: 3, unit: "count"))
        )
        let workoutRecord = HealthKitRecord(
            originalUUID: workoutUUID,
            objectTypeIdentifier: "HKWorkoutTypeIdentifier",
            recordKind: .workout,
            selectedMetricIDs: ["workouts"],
            includedBecause: .selectedMetric,
            startDate: start.addingTimeInterval(7_200),
            endDate: start.addingTimeInterval(9_000),
            sourceRevision: sourceRevision,
            payload: .structured(kind: "workout", fields: [:])
        )
        let external = HealthKitExternalRecord(
            externalIdentifier: "activity-summary:2026-03-08",
            externalIdentityKind: .activitySummaryDateComponents,
            objectTypeIdentifier: "HKActivitySummaryTypeIdentifier",
            recordKind: .activitySummary,
            selectedMetricIDs: ["activity_summary"],
            fields: ["active_energy": .floatingPoint(500)]
        )
        let archive = makeArchive(
            start: start,
            end: end,
            timeZone: "America/Los_Angeles",
            records: [record, workoutRecord],
            externalRecords: [external],
            queryManifest: .init(results: [query("steps-query", metricID: "steps", status: .success, count: 1, start: start, end: end)]),
            warnings: [.init(code: "sample_warning", message: "A source warning.", metricIDs: ["steps"], recordUUIDs: [quantityUUID])]
        )
        let workout = WorkoutData(
            id: workoutUUID,
            sourceUUID: workoutUUID,
            workoutType: .running,
            healthKitActivityType: "running",
            healthKitActivityTypeRawValue: 37,
            startTime: start.addingTimeInterval(7_200),
            actualEndDate: start.addingTimeInterval(9_000),
            isIndoor: false,
            duration: 1_700,
            calories: 200,
            distance: 5_000,
            avgHeartRate: 145
        )
        let data = HealthData(
            date: start,
            timeContext: .init(calendarTimeZoneIdentifier: "America/Los_Angeles"),
            activity: ActivityData(steps: 3),
            workouts: [workout],
            partialFailures: [.init(date: start, dataType: "steps", dateRangeDescription: "day", errorDescription: "Sibling detail failed")],
            healthKitRecordArchive: archive
        )

        let day = try HealthMdQueryContextProjector.project(data, options: .init(enabledMetricIDs: ["steps", "workouts", "activity_summary"]))
        XCTAssertEqual(day.ownerDate, "2026-03-08")
        XCTAssertEqual(day.intervalStart, start)
        XCTAssertEqual(day.intervalEnd, end)
        XCTAssertEqual(day.intervalEnd.timeIntervalSince(day.intervalStart), 23 * 3_600)
        XCTAssertEqual(day.calendarTimeZone, "America/Los_Angeles")
        XCTAssertEqual(day.workouts.count, 1)
        XCTAssertEqual(day.workouts[0].workoutID, workoutUUID.uuidString.lowercased())
        XCTAssertEqual(day.workouts[0].start, workout.startTime)
        XCTAssertEqual(day.workouts[0].end, workout.actualEndDate)
        XCTAssertEqual(day.workouts[0].details["distance"], .quantity(value: 5_000, unit: "m"))

        XCTAssertTrue(day.evidence.contains { if case .canonicalUUID(_, let uuid) = $0.reference.locator { return uuid == quantityUUID.uuidString.lowercased() }; return false })
        XCTAssertTrue(day.evidence.contains { if case .externalIdentity(_, let id) = $0.reference.locator { return id == external.externalIdentifier }; return false })
        XCTAssertTrue(day.evidence.contains { if case .queryManifest(_, let id) = $0.reference.locator { return id == "steps-query" }; return false })
        XCTAssertTrue(day.evidence.contains { if case .warning(_, let code) = $0.reference.locator { return code == "sample_warning" }; return false })
        XCTAssertTrue(day.evidence.contains { if case .partialFailure = $0.reference.locator { return true }; return false })
        XCTAssertTrue(HealthMdEvidenceResolver.allResolve(day.evidence.map(\.reference), in: [day]))
        let workoutEvidence = Set(day.workouts[0].evidenceIDs)
        XCTAssertFalse(workoutEvidence.isEmpty)
        XCTAssertTrue(workoutEvidence.isSubset(of: Set(day.evidence.map { $0.reference.evidenceID })))
    }

    func testProjectionIsPermutationInvariantAndRetainsUnknownArchiveMetrics() throws {
        let start = iso("2026-04-01T00:00:00Z")
        let end = iso("2026-04-02T00:00:00Z")
        let firstUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let records = [
            HealthKitRecord(
                originalUUID: firstUUID,
                objectTypeIdentifier: "HKFutureTypeIdentifier",
                recordKind: .other("future"),
                selectedMetricIDs: ["future_archive_metric"],
                includedBecause: .selectedMetric,
                startDate: start.addingTimeInterval(20),
                endDate: start.addingTimeInterval(30),
                sourceRevision: sourceRevision,
                payload: .unknown(kind: "future_payload", fields: ["answer": .signedInteger(42)])
            ),
            HealthKitRecord(
                originalUUID: secondUUID,
                objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
                recordKind: .quantity,
                selectedMetricIDs: ["steps"],
                includedBecause: .selectedMetric,
                startDate: start.addingTimeInterval(10),
                endDate: start.addingTimeInterval(11),
                sourceRevision: sourceRevision,
                payload: .quantity(.init(value: 2, unit: "count"))
            )
        ]
        let workouts = [
            WorkoutData(id: UUID(uuidString: "00000000-0000-0000-0000-000000000211"), workoutType: .walking, startTime: start.addingTimeInterval(100), duration: 60, calories: 3, distance: 20),
            WorkoutData(id: UUID(uuidString: "00000000-0000-0000-0000-000000000212"), workoutType: .running, startTime: start.addingTimeInterval(200), duration: 120, calories: 9, distance: 100)
        ]
        let providerPayloads = [
            ExternalProviderPayload(name: "z", endpoint: "https://example.test/z", statusCode: 200, fetchedAt: start, data: .object(["value": .number(2)])),
            ExternalProviderPayload(name: "a", endpoint: "https://example.test/a", statusCode: 200, fetchedAt: start, data: .array([]))
        ]

        func context(reversed: Bool) throws -> HealthMdCompactContextDay {
            let archive = makeArchive(
                start: start,
                end: end,
                records: records.reversedIf(reversed),
                queryManifest: .init(results: [
                    query("future", metricID: "future_archive_metric", status: .success, count: 1, start: start, end: end),
                    query("steps", metricID: "steps", status: .success, count: 1, start: start, end: end)
                ].reversedIf(reversed)),
                warnings: [
                    .init(code: "b", message: "B"), .init(code: "a", message: "A")
                ].reversedIf(reversed)
            )
            let provider = ExternalDailyRecord(
                provider: .whoop,
                date: "2026-04-01",
                fetchedAt: start,
                payloads: providerPayloads.reversedIf(reversed),
                warnings: reversed ? ["second", "first"] : ["first", "second"]
            )
            return try HealthMdQueryContextProjector.project(
                HealthData(
                    date: start,
                    timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
                    activity: ActivityData(steps: 2),
                    workouts: workouts.reversedIf(reversed),
                    healthKitRecordArchive: archive
                ),
                externalProviderRecords: [provider]
            )
        }

        let first = try context(reversed: false)
        let second = try context(reversed: true)
        XCTAssertEqual(first.source.digest, second.source.digest)
        XCTAssertEqual(
            try HealthMdQueryCanonicalSerializer.data(for: first),
            try HealthMdQueryCanonicalSerializer.data(for: second)
        )
        let unknown = metric("future_archive_metric", in: first)
        XCTAssertEqual(unknown.status, .available)
        guard case .array(let details)? = unknown.value else { return XCTFail("Unknown archive metric detail was dropped") }
        XCTAssertFalse(details.isEmpty)
        XCTAssertFalse(unknown.evidenceIDs.isEmpty)
    }

    func testEveryCurrentCatalogMetricIsAccountedForAndDailyExportSchemaRemainsV7() throws {
        let start = iso("2026-05-01T00:00:00Z")
        let ids = Set(HealthMetrics.all.map(\.id))
        let day = try HealthMdQueryContextProjector.project(
            HealthData(date: start, timeContext: .init(calendarTimeZoneIdentifier: "UTC"), healthKitRecordCaptureStatus: .notRequested),
            options: .init(enabledMetricIDs: ids)
        )
        XCTAssertEqual(Set(day.metrics.map(\.metricID)), ids)
        XCTAssertEqual(HealthMdExportSchema.version, 7)
        XCTAssertEqual(day.source.schemaVersion, 7)
        XCTAssertEqual(day.schemaVersion, 1)
    }

    // MARK: Helpers

    private var sourceRevision: HealthKitSourceRevision {
        .init(name: "Tests", bundleIdentifier: "tech.isolated.healthmd.tests")
    }

    private func metric(_ id: String, in day: HealthMdCompactContextDay) -> HealthMdContextMetric {
        day.metrics.first(where: { $0.metricID == id })!
    }

    private func query(
        _ identifier: String,
        metricID: String,
        status: HealthKitQueryResultStatus,
        count: Int,
        start: Date,
        end: Date
    ) -> HealthKitQueryResult {
        .init(
            identifier: identifier,
            operation: "sample_query",
            metricIDs: [metricID],
            interval: .init(startDate: start, endDate: end, calendarTimeZoneIdentifier: "UTC"),
            status: status,
            recordCount: count,
            error: status == .failure ? .init(domain: "tests", code: 1, description: "failed") : nil
        )
    }

    private func makeArchive(
        start: Date,
        end: Date,
        timeZone: String = "UTC",
        captureStatus: HealthKitRecordCaptureStatus = .complete,
        records: [HealthKitRecord] = [],
        externalRecords: [HealthKitExternalRecord] = [],
        queryManifest: HealthKitQueryManifest? = nil,
        warnings: [HealthKitRecordIntegrityWarning] = []
    ) -> HealthKitRecordArchive {
        .init(
            captureStatus: captureStatus,
            dailyOwnership: .init(
                ownerDate: HealthKitDailyOwnershipMetadata.ownerDate(for: start, calendarTimeZoneIdentifier: timeZone),
                intervalStart: start,
                intervalEnd: end,
                calendarTimeZoneIdentifier: timeZone
            ),
            records: records,
            externalRecords: externalRecords,
            queryManifest: queryManifest ?? HealthKitQueryManifest(),
            integrityWarnings: warnings
        )
    }

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

private extension Array {
    func reversedIf(_ condition: Bool) -> [Element] {
        condition ? Array(reversed()) : self
    }
}
