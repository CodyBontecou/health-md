import XCTest
@testable import HealthMd

@MainActor
final class APIEndpointExportRunnerTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings contains nested
    // observation state that can crash during test-process teardown on macOS 26.
    private static var retainedSettings: [AdvancedExportSettings] = []
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "APIEndpointExportRunnerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUploadsOnlyDatesWithDataAndReportsEmptyDates() async throws {
        let first = date(year: 2026, month: 5, day: 10)
        let second = date(year: 2026, month: 5, day: 11)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadedRecordDates: [Date] = []
        var uploadedFailedDates: [Date] = []
        var uploadedRange: (Date, Date)?

        let result = await APIEndpointExportRunner.export(
            dates: [first, second],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                if Calendar.current.isDate(requestedDate, inSameDayAs: first) {
                    return HealthData(
                        date: requestedDate,
                        activity: ActivityData(steps: 1234)
                    )
                }
                return HealthData(date: requestedDate)
            },
            fetchExternalDailyRecords: nil,
            upload: { records, failedDateDetails, _, _, _, rangeStart, rangeEnd in
                uploadedRecordDates = records.map(\.date)
                uploadedFailedDates = failedDateDetails.map(\.date)
                uploadedRange = (rangeStart, rangeEnd)
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.noHealthData])
        XCTAssertEqual(uploadedRecordDates, [first])
        XCTAssertEqual(uploadedFailedDates, [second])
        XCTAssertEqual(uploadedRange?.0, first)
        XCTAssertEqual(uploadedRange?.1, second)
    }

    func testProviderOnlyDayRemainsSupplementalAndDoesNotTriggerUpload() async {
        let exportDate = date(year: 2026, month: 5, day: 10)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var externalFetchCount = 0
        var uploadCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: [exportDate],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in HealthData(date: requestedDate) },
            fetchExternalDailyRecords: { date in
                externalFetchCount += 1
                return [ExternalDailyRecord(
                    provider: .whoop,
                    date: ExternalProviderAPIClient.dayString(date),
                    payloads: [ExternalProviderPayload(
                        name: "cycles",
                        endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                        statusCode: 200,
                        data: .object(["records": .array([.object(["id": .number(1)])])])
                    )]
                )]
            },
            upload: { _, _, _, _, _, _, _ in
                uploadCount += 1
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .noHealthData)
        XCTAssertEqual(externalFetchCount, 0)
        XCTAssertEqual(uploadCount, 0)
    }

    func testUploadFailureReturnsFileWriteFailureWithoutCountingPreparedRecordsAsSuccess() async {
        let exportDate = date(year: 2026, month: 5, day: 10)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"

        let result = await APIEndpointExportRunner.export(
            dates: [exportDate],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 1234))
            },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                throw APIExportClientError.serverRejected(statusCode: 500, body: "boom")
            }
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .fileWriteError)
        XCTAssertTrue(result.failedDateDetails.first?.errorDetails?.contains("500") == true)
    }

    // MARK: - Batching

    func testFifteenDayRangeSplitsIntoThreeSequentialSevenDayBatches() async throws {
        let dates = (0..<15).map { date(year: 2026, month: 5, day: 1 + $0) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"

        struct BatchCall {
            let dayCount: Int
            let rangeStart: Date
            let rangeEnd: Date
        }
        var calls: [BatchCall] = []

        let result = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 1000))
            },
            fetchExternalDailyRecords: nil,
            upload: { records, failedDateDetails, _, _, _, rangeStart, rangeEnd in
                XCTAssertTrue(failedDateDetails.isEmpty)
                XCTAssertEqual(records.map(\.date).min(), rangeStart)
                XCTAssertEqual(records.map(\.date).max(), rangeEnd)
                calls.append(BatchCall(dayCount: records.count, rangeStart: rangeStart, rangeEnd: rangeEnd))
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls.map(\.dayCount), [7, 7, 1])
        XCTAssertEqual(calls[0].rangeStart, dates[0])
        XCTAssertEqual(calls[0].rangeEnd, dates[6])
        XCTAssertEqual(calls[1].rangeStart, dates[7])
        XCTAssertEqual(calls[1].rangeEnd, dates[13])
        XCTAssertEqual(calls[2].rangeStart, dates[14])
        XCTAssertEqual(calls[2].rangeEnd, dates[14])
        XCTAssertEqual(result.successCount, 15)
        XCTAssertEqual(result.totalCount, 15)
        XCTAssertTrue(result.failedDateDetails.isEmpty)
    }

    func testBatchFailureStopsSubsequentBatchesAndPreservesPriorSuccess() async {
        let dates = (0..<15).map { date(year: 2026, month: 5, day: 1 + $0) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCallCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 1000))
            },
            fetchExternalDailyRecords: nil,
            upload: { records, _, _, _, _, _, _ in
                uploadCallCount += 1
                if uploadCallCount == 2 {
                    throw APIExportClientError.serverRejected(statusCode: 500, body: "boom")
                }
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        // Batch 1 (7 days) succeeded, batch 2 (7 days) failed, batch 3 (1 day)
        // must never have been attempted.
        XCTAssertEqual(uploadCallCount, 2)
        XCTAssertEqual(result.successCount, 7)
        XCTAssertEqual(result.totalCount, 15)
        XCTAssertTrue(result.failedDateDetails.contains {
            $0.reason == .fileWriteError && ($0.errorDetails?.contains("500") ?? false)
        })

        // Every date from the failed batch onward (days 8-15) must be
        // reported as failed/not-attempted, not just the batch start date,
        // so retry UI can identify every missing date.
        let reportedFailedDates = Set(result.failedDateDetails.map { Calendar.current.startOfDay(for: $0.date) })
        let expectedFailedDates = Set(dates[7...].map { Calendar.current.startOfDay(for: $0) })
        XCTAssertEqual(reportedFailedDates, expectedFailedDates)

        // Batch 3 (the untried trailing batch) must be marked as not
        // attempted, distinct from an actual upload failure.
        let day15Detail = result.failedDateDetails.first {
            Calendar.current.isDate($0.date, inSameDayAs: dates[14])
        }
        XCTAssertEqual(day15Detail?.reason, .unknown)
    }

    func testFailureOnlyBatchIsCarriedForwardToNextSuccessfulUpload() async {
        // 8 days: the first batch (days 1-7) has no health data at all, the
        // second batch (day 8) has data. The first batch's failures must
        // still reach the endpoint -- attached to the next upload -- rather
        // than being silently dropped because that batch itself had nothing
        // to upload.
        let dates = (0..<8).map { date(year: 2026, month: 6, day: 1 + $0) }
        let noDataCutoff = dates[6] // last day of the empty first batch
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCallCount = 0
        var lastUploadFailedDates: [Date] = []

        let result = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                if requestedDate <= noDataCutoff {
                    return HealthData(date: requestedDate)
                }
                return HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: nil,
            upload: { records, failedDateDetails, _, _, _, _, _ in
                uploadCallCount += 1
                lastUploadFailedDates = failedDateDetails.map(\.date)
                XCTAssertEqual(records.count, 1)
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        // Only one upload call (for the batch with records), but it must
        // carry all 7 of the first batch's failed dates along with it.
        XCTAssertEqual(uploadCallCount, 1)
        XCTAssertEqual(Set(lastUploadFailedDates.map { Calendar.current.startOfDay(for: $0) }),
                       Set(dates[0..<7].map { Calendar.current.startOfDay(for: $0) }))
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.totalCount, 8)
    }

    func testTrailingFailureOnlyBatchIsFlushedInDedicatedUpload() async {
        // 8 days: first batch (days 1-7) has data, second batch (day 8) has
        // no data. There's no later batch to attach day 8's failure to, so
        // it must be flushed via its own failure-only upload call since a
        // prior batch already succeeded.
        let dates = (0..<8).map { date(year: 2026, month: 6, day: 1 + $0) }
        let noDataDate = dates[7]
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCalls: [(recordCount: Int, failedDates: [Date])] = []

        let result = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                if Calendar.current.isDate(requestedDate, inSameDayAs: noDataDate) {
                    return HealthData(date: requestedDate)
                }
                return HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: nil,
            upload: { records, failedDateDetails, _, _, _, _, _ in
                uploadCalls.append((records.count, failedDateDetails.map(\.date)))
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(uploadCalls.count, 2)
        XCTAssertEqual(uploadCalls[0].recordCount, 7)
        XCTAssertTrue(uploadCalls[0].failedDates.isEmpty)
        XCTAssertEqual(uploadCalls[1].recordCount, 0)
        XCTAssertEqual(uploadCalls[1].failedDates.count, 1)
        XCTAssertTrue(Calendar.current.isDate(uploadCalls[1].failedDates[0], inSameDayAs: noDataDate))
        XCTAssertEqual(result.successCount, 7)
        XCTAssertEqual(result.totalCount, 8)
    }

    func testExternalRecordCountOnlyIncludesSuccessfullyUploadedBatches() async {
        // Two single-day batches (batch span of 1) so each date is its own
        // batch: the first upload succeeds, the second is rejected. The
        // rejected batch's external/provider records must not be counted in
        // the result even though they were fetched.
        let first = date(year: 2026, month: 6, day: 1)
        let second = date(year: 2026, month: 6, day: 2)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCallCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: [first, second],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: { requestedDate in
                [ExternalDailyRecord(
                    provider: .whoop,
                    date: ExternalProviderAPIClient.dayString(requestedDate),
                    payloads: [ExternalProviderPayload(
                        name: "cycles",
                        endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                        statusCode: 200,
                        data: .object(["records": .array([.object(["id": .number(1)])])])
                    )]
                )]
            },
            upload: { _, _, _, _, _, _, _ in
                uploadCallCount += 1
                if uploadCallCount == 2 {
                    throw APIExportClientError.serverRejected(statusCode: 500, body: "boom")
                }
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            },
            maxBatchDaySpan: 1
        )

        XCTAssertEqual(uploadCallCount, 2)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.externalRecordFileCount, 1)
    }

    func testEmptyDatesReturnsZeroCounts() async {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCallCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: [],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in HealthData(date: requestedDate) },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                uploadCallCount += 1
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertTrue(result.failedDateDetails.isEmpty)
        XCTAssertEqual(uploadCallCount, 0)
    }

    func testSingleDayWithNoDataReportsNoHealthDataAndSkipsUpload() async {
        let exportDate = date(year: 2026, month: 5, day: 10)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCallCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: [exportDate],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in HealthData(date: requestedDate) },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                uploadCallCount += 1
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.noHealthData])
        XCTAssertEqual(uploadCallCount, 0)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        ))!
    }
}
