import XCTest
@testable import HealthMd

@MainActor
final class HealthKitDailyCaptureTests: XCTestCase {
    func testCaptureForwardsGranularAndSelectionAndReportsPartialFailures() async throws {
        let date = day(10)
        let selection = MetricSelectionState()
        let partial = ExportPartialFailure(
            date: date,
            dataType: "Heart Rate",
            dateRangeDescription: "2026-05-10",
            errorDescription: "Unavailable"
        )
        var receivedGranular: Bool?
        var receivedSelection: MetricSelectionState?

        let outcome = try await HealthKitDailyCapture.capture(
            date: date,
            includeGranularData: true,
            metricSelection: selection,
            transform: .none,
            emptyRecordPolicy: .retain,
            fetchExternalRecords: false,
            failurePolicy: .apiEndpoint,
            fetchHealthData: { requestedDate, granular, metricSelection in
                receivedGranular = granular
                receivedSelection = metricSelection
                return HealthData(
                    date: requestedDate,
                    activity: ActivityData(steps: 123),
                    partialFailures: [partial]
                )
            },
            fetchExternalDailyRecords: nil
        )

        XCTAssertEqual(receivedGranular, true)
        XCTAssertTrue(receivedSelection === selection)
        XCTAssertEqual(outcome.record?.activity.steps, 123)
        XCTAssertEqual(outcome.partialFailures, [partial])
        XCTAssertNil(outcome.failure)
    }

    func testSanitizeGranularRemovesUnrequestedCaptureStatus() async throws {
        let date = day(10)
        let selection = MetricSelectionState()

        let outcome = try await HealthKitDailyCapture.capture(
            date: date,
            includeGranularData: false,
            metricSelection: selection,
            transform: .sanitizeGranular,
            emptyRecordPolicy: .retain,
            fetchExternalRecords: false,
            failurePolicy: .connectedMac,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(
                    date: requestedDate,
                    activity: ActivityData(steps: 1),
                    healthKitRecordCaptureStatus: .complete
                )
            },
            fetchExternalDailyRecords: nil
        )

        XCTAssertEqual(outcome.record?.healthKitRecordCaptureStatus, .notRequested)
    }

    func testNoDataSuppressesProviderFetchAndReturnsTerminalDetail() async throws {
        let date = day(10)
        var providerFetchCount = 0

        let outcome = try await HealthKitDailyCapture.capture(
            date: date,
            includeGranularData: false,
            metricSelection: MetricSelectionState(),
            transform: .filterToSelection,
            emptyRecordPolicy: .reportNoData,
            fetchExternalRecords: true,
            failurePolicy: .apiEndpoint,
            fetchHealthData: { requestedDate, _, _ in HealthData(date: requestedDate) },
            fetchExternalDailyRecords: { _ in
                providerFetchCount += 1
                return [self.externalRecord(hasPayload: true)]
            }
        )

        XCTAssertNil(outcome.record)
        XCTAssertEqual(outcome.failure?.reason, .noHealthData)
        XCTAssertEqual(providerFetchCount, 0)
        XCTAssertTrue(outcome.externalDailyRecords.isEmpty)
    }

    func testProviderRecordsAreFilteredToExportableRecords() async throws {
        let outcome = try await HealthKitDailyCapture.capture(
            date: day(10),
            includeGranularData: false,
            metricSelection: MetricSelectionState(),
            transform: .none,
            emptyRecordPolicy: .retain,
            fetchExternalRecords: true,
            failurePolicy: .apiEndpoint,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 1))
            },
            fetchExternalDailyRecords: { _ in
                [self.externalRecord(hasPayload: true), self.externalRecord(hasPayload: false)]
            }
        )

        XCTAssertEqual(outcome.externalDailyRecords.count, 1)
        XCTAssertTrue(outcome.externalDailyRecords[0].shouldExport)
    }

    func testFailurePoliciesKeepEstablishedAuthorizationSemanticsExplicit() async throws {
        let api = try await captureFailure(.notAuthorized, policy: .apiEndpoint)
        let connected = try await captureFailure(.notAuthorized, policy: .connectedMac)
        let locked = try await captureFailure(.dataProtectedWhileLocked, policy: .connectedMac)

        XCTAssertEqual(api.failure?.reason, .healthKitError)
        XCTAssertEqual(connected.failure?.reason, .accessDenied)
        XCTAssertEqual(connected.failure?.errorDetails, "HealthKit access has not been granted on iPhone.")
        XCTAssertEqual(locked.failure?.reason, .deviceLocked)
    }

    func testUnknownConnectedFailureIsSanitized() async throws {
        struct SensitiveError: LocalizedError {
            var errorDescription: String? { "health-payload-secret" }
        }

        let outcome = try await HealthKitDailyCapture.capture(
            date: day(10),
            includeGranularData: false,
            metricSelection: MetricSelectionState(),
            transform: .none,
            emptyRecordPolicy: .retain,
            fetchExternalRecords: false,
            failurePolicy: .connectedMac,
            fetchHealthData: { _, _, _ in throw SensitiveError() },
            fetchExternalDailyRecords: nil
        )

        XCTAssertEqual(outcome.failure?.reason, .healthKitError)
        XCTAssertEqual(outcome.failure?.errorDetails, "HealthKit query failed for the requested day.")
        XCTAssertFalse(outcome.failure?.errorDetails?.contains("secret") == true)
    }

    func testCancellationPropagates() async {
        do {
            _ = try await HealthKitDailyCapture.capture(
                date: day(10),
                includeGranularData: false,
                metricSelection: MetricSelectionState(),
                transform: .none,
                emptyRecordPolicy: .retain,
                fetchExternalRecords: false,
                failurePolicy: .apiEndpoint,
                fetchHealthData: { _, _, _ in throw CancellationError() },
                fetchExternalDailyRecords: nil
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNormalizedDatesDeduplicatesAndSortsDays() {
        let first = day(10)
        let laterSameDay = Calendar.current.date(byAdding: .hour, value: 4, to: first)!
        let second = day(11)

        XCTAssertEqual(
            HealthKitDailyCapture.normalizedDates([second, laterSameDay, first]),
            [Calendar.current.startOfDay(for: first), Calendar.current.startOfDay(for: second)]
        )
    }

    private func captureFailure(
        _ error: HealthKitManager.HealthKitError,
        policy: HealthKitDailyCapture.FailurePolicy
    ) async throws -> HealthKitDailyCapture.Outcome {
        try await HealthKitDailyCapture.capture(
            date: day(10),
            includeGranularData: false,
            metricSelection: MetricSelectionState(),
            transform: .none,
            emptyRecordPolicy: .retain,
            fetchExternalRecords: false,
            failurePolicy: policy,
            fetchHealthData: { _, _, _ in throw error },
            fetchExternalDailyRecords: nil
        )
    }

    private func externalRecord(hasPayload: Bool) -> ExternalDailyRecord {
        ExternalDailyRecord(
            provider: .whoop,
            date: "2026-05-10",
            payloads: hasPayload ? [ExternalProviderPayload(
                name: "cycles",
                endpoint: "https://api.example.com/cycles",
                statusCode: 200,
                data: .object(["records": .array([.number(1)])])
            )] : []
        )
    }

    private func day(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: day))!
    }
}
