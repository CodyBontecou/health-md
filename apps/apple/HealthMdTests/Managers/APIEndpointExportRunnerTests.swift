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

    func testDailyNotesOnlyRejectsAPIDestinationWithoutFetchingOrUploading() async {
        let exportDate = date(year: 2026, month: 5, day: 10)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var fetchCount = 0
        var uploadCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: [exportDate],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                fetchCount += 1
                return HealthData(date: requestedDate, activity: ActivityData(steps: 1))
            },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                uploadCount += 1
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertTrue(result.failedDateDetails.first?.errorDetails?.contains("Daily Notes Only") == true)
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
        XCTAssertEqual(result.completedDateCount, 2)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertTrue(result.didCompleteAllRequestedDates)
        XCTAssertTrue(result.isPartialSuccess)
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

    func testUploadFailureIsPrimaryAndDoesNotPersistEndpointResponseBody() async {
        let first = date(year: 2026, month: 5, day: 10)
        let second = date(year: 2026, month: 5, day: 11)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        let sensitiveResponse = "Authorization: Bearer secret-token; health_payload=private"

        let result = await APIEndpointExportRunner.export(
            dates: [first, second],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                if Calendar.current.isDate(requestedDate, inSameDayAs: first) {
                    return HealthData(date: requestedDate)
                }
                return HealthData(date: requestedDate, activity: ActivityData(steps: 1234))
            },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                throw APIExportClientError.serverRejected(
                    statusCode: 500,
                    body: sensitiveResponse
                )
            }
        )

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .fileWriteError)
        XCTAssertTrue(result.failedDateDetails.first?.errorDetails?.contains("500") == true)
        XCTAssertFalse(result.failedDateDetails.contains {
            $0.errorDetails?.contains("secret-token") == true
                || $0.errorDetails?.contains("health_payload") == true
        })
        XCTAssertEqual(result.failedDateDetails.count, 2)
        XCTAssertEqual(Set(result.failedDateDetails.map(\.date)), Set([first, second]))
    }

    func testUploadedRetryableHealthKitFailureRemainsIncomplete() async throws {
        let first = date(year: 2026, month: 5, day: 10)
        let locked = date(year: 2026, month: 5, day: 11)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"

        let result = await APIEndpointExportRunner.export(
            dates: [first, locked],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                if Calendar.current.isDate(requestedDate, inSameDayAs: locked) {
                    throw HealthKitManager.HealthKitError.dataProtectedWhileLocked
                }
                return HealthData(date: requestedDate, activity: ActivityData(steps: 1234))
            },
            fetchExternalDailyRecords: nil,
            upload: { _, failedDateDetails, _, _, _, _, _ in
                XCTAssertEqual(failedDateDetails.map(\.reason), [.deviceLocked])
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.completedDateCount, 1)
        XCTAssertEqual(result.completedDates, [first])
        XCTAssertEqual(result.remainingDates(from: [first, locked]), [locked])
        XCTAssertFalse(result.didCompleteAllRequestedDates)
        XCTAssertEqual(result.failedDateDetails.map(\.reason), [.deviceLocked])
    }

    func testDestinationAndAuthorizationAreSnapshottedBeforeFirstBatch() async throws {
        let dates = [
            date(year: 2026, month: 5, day: 10),
            date(year: 2026, month: 5, day: 11)
        ]
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let keychain = SystemKeychainStore(service: "APIEndpointExportRunnerTests.\(UUID().uuidString)")
        let apiSettings = APIExportSettings(userDefaults: defaults, keychain: keychain)
        apiSettings.endpointURLString = "https://first.example.com/healthmd"
        apiSettings.bearerToken = "first-token"
        defer { apiSettings.bearerToken = "" }
        var destinations: [APIExportDestinationSnapshot] = []

        _ = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 1234))
            },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, destination, _, _ in
                destinations.append(destination)
                if destinations.count == 1 {
                    apiSettings.endpointURLString = "https://second.example.com/other"
                    apiSettings.bearerToken = "second-token"
                }
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            },
            maxBatchDaySpan: 1
        )

        XCTAssertEqual(destinations.map(\.endpointURL.absoluteString), [
            "https://first.example.com/healthmd",
            "https://first.example.com/healthmd"
        ])
        XCTAssertEqual(destinations.map(\.authorizationHeaderValue), [
            "Bearer first-token",
            "Bearer first-token"
        ])
        XCTAssertEqual(destinations.map(\.displayName), ["first.example.com", "first.example.com"])
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
        XCTAssertEqual(result.completedDateCount, 7)
        XCTAssertEqual(result.totalCount, 15)
        XCTAssertFalse(result.didCompleteAllRequestedDates)
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

    func testFailureOnlyBatchUsesDedicatedScopedUploadBeforeNextSuccessfulBatch() async {
        // 8 days: the first batch (days 1-7) has no health data at all, and
        // the second batch (day 8) has data. Failure metadata must use its own
        // range instead of escaping into day 8's envelope.
        let dates = (0..<8).map { date(year: 2026, month: 6, day: 1 + $0) }
        let noDataCutoff = dates[6]
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCalls: [(recordCount: Int, failedDates: [Date], start: Date, end: Date)] = []

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
            upload: { records, failedDateDetails, _, _, _, rangeStart, rangeEnd in
                uploadCalls.append((records.count, failedDateDetails.map(\.date), rangeStart, rangeEnd))
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(uploadCalls.count, 2)
        XCTAssertEqual(uploadCalls[0].recordCount, 0)
        XCTAssertEqual(uploadCalls[0].start, dates[0])
        XCTAssertEqual(uploadCalls[0].end, dates[6])
        XCTAssertEqual(Set(uploadCalls[0].failedDates), Set(dates[0..<7]))
        XCTAssertTrue(uploadCalls[0].failedDates.allSatisfy {
            $0 >= uploadCalls[0].start && $0 <= uploadCalls[0].end
        })
        XCTAssertEqual(uploadCalls[1].recordCount, 1)
        XCTAssertTrue(uploadCalls[1].failedDates.isEmpty)
        XCTAssertEqual(uploadCalls[1].start, dates[7])
        XCTAssertEqual(uploadCalls[1].end, dates[7])
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.completedDateCount, 8)
        XCTAssertEqual(result.totalCount, 8)
        XCTAssertTrue(result.didCompleteAllRequestedDates)
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
        var uploadCalls: [(recordCount: Int, failedDates: [Date], start: Date, end: Date)] = []

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
            upload: { records, failedDateDetails, _, _, _, rangeStart, rangeEnd in
                uploadCalls.append((records.count, failedDateDetails.map(\.date), rangeStart, rangeEnd))
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(uploadCalls.count, 2)
        XCTAssertEqual(uploadCalls[0].recordCount, 7)
        XCTAssertTrue(uploadCalls[0].failedDates.isEmpty)
        XCTAssertEqual(uploadCalls[1].recordCount, 0)
        XCTAssertEqual(uploadCalls[1].failedDates.count, 1)
        XCTAssertTrue(Calendar.current.isDate(uploadCalls[1].failedDates[0], inSameDayAs: noDataDate))
        XCTAssertEqual(uploadCalls[1].start, noDataDate)
        XCTAssertEqual(uploadCalls[1].end, noDataDate)
        XCTAssertTrue(uploadCalls[1].failedDates.allSatisfy {
            $0 >= uploadCalls[1].start && $0 <= uploadCalls[1].end
        })
        XCTAssertEqual(result.successCount, 7)
        XCTAssertEqual(result.completedDateCount, 8)
        XCTAssertEqual(result.totalCount, 8)
        XCTAssertTrue(result.didCompleteAllRequestedDates)
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

    func testCompatibilityUploaderAndCountsRetainCollectedEmptyExternalRecords() async {
        let exportDate = date(year: 2026, month: 6, day: 1)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        let emptyRecord = ExternalDailyRecord(
            provider: .whoop,
            date: ExternalProviderAPIClient.dayString(exportDate),
            payloads: []
        )
        XCTAssertFalse(emptyRecord.shouldExport)
        var uploadedExternalRecords: [ExternalDailyRecord] = []

        let result = await APIEndpointExportRunner.export(
            dates: [exportDate],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: { _ in [emptyRecord] },
            upload: { _, _, externalRecords, _, _, _, _ in
                uploadedExternalRecords = externalRecords
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
        )

        XCTAssertEqual(uploadedExternalRecords, [emptyRecord])
        XCTAssertEqual(result.externalRecordFileCount, 1)
    }

    func testCancellationDoesNotCountPreparedButUnuploadedRecords() async {
        let dates = (0..<3).map { date(year: 2026, month: 6, day: 1 + $0) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var fetchCount = 0
        var uploadCallCount = 0

        let exportTask = Task { @MainActor in
            await APIEndpointExportRunner.export(
                dates: dates,
                settings: settings,
                apiSettings: apiSettings,
                fetchHealthData: { requestedDate, _, _ in
                    fetchCount += 1
                    if fetchCount == 2 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    return HealthData(
                        date: requestedDate,
                        activity: ActivityData(steps: 500)
                    )
                },
                fetchExternalDailyRecords: nil,
                upload: { _, _, _, _, _, _, _ in
                    uploadCallCount += 1
                    return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
                }
            )
        }

        let result = await exportTask.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(uploadCallCount, 0)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.totalCount, 3)
    }

    func testCancellationAfterPriorBatchCountsOnlyUploadedRecords() async {
        let dates = (0..<4).map { date(year: 2026, month: 6, day: 1 + $0) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var fetchCount = 0
        var uploadCallCount = 0

        let exportTask = Task { @MainActor in
            await APIEndpointExportRunner.export(
                dates: dates,
                settings: settings,
                apiSettings: apiSettings,
                fetchHealthData: { requestedDate, _, _ in
                    fetchCount += 1
                    if fetchCount == 3 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    return HealthData(
                        date: requestedDate,
                        activity: ActivityData(steps: 500)
                    )
                },
                fetchExternalDailyRecords: nil,
                upload: { _, _, _, _, _, _, _ in
                    uploadCallCount += 1
                    return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
                },
                maxBatchDaySpan: 2
            )
        }

        let result = await exportTask.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(fetchCount, 3)
        XCTAssertEqual(uploadCallCount, 1)
        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.completedDateCount, 2)
        XCTAssertEqual(result.totalCount, 4)
        XCTAssertFalse(result.didCompleteAllRequestedDates)
    }

    func testFailureOnlyUploadFailureHasUniqueSanitizedDetails() async {
        struct SensitiveTransportError: LocalizedError {
            var errorDescription: String? {
                "Authorization: Bearer secret-token; health_payload=private"
            }
        }

        let dates = (0..<8).map { date(year: 2026, month: 6, day: 1 + $0) }
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
                if requestedDate < dates[7] {
                    return HealthData(date: requestedDate)
                }
                return HealthData(
                    date: requestedDate,
                    activity: ActivityData(steps: 500)
                )
            },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                uploadCallCount += 1
                throw SensitiveTransportError()
            }
        )

        XCTAssertEqual(uploadCallCount, 1)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .fileWriteError)
        XCTAssertEqual(result.failedDateDetails.count, dates.count)
        XCTAssertEqual(Set(result.failedDateDetails.map(\.date)), Set(dates))
        XCTAssertFalse(result.failedDateDetails.contains {
            $0.errorDetails?.contains("secret-token") == true
                || $0.errorDetails?.contains("health_payload") == true
        })
        XCTAssertTrue(result.failedDateDetails.first?.errorDetails?.contains("API endpoint upload failed") == true)
    }

    func testEncodedByteTargetSplitsBeforeCalendarDayLimit() async {
        let dates = (0..<3).map { date(year: 2026, month: 6, day: 10 + $0) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadedDateGroups: [[Date]] = []

        let result = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: nil,
            upload: { records, _, _, _, _, _, _ in
                uploadedDateGroups.append(records.map(\.date))
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            },
            maxBatchDaySpan: 7,
            maxBatchPayloadBytes: 1
        )

        XCTAssertEqual(uploadedDateGroups, dates.map { [$0] })
        XCTAssertEqual(result.successCount, 3)
        XCTAssertEqual(result.completedDateCount, 3)
    }

    func testOversizedSingleDayUploadsExactlyOnce() async {
        let exportDate = date(year: 2026, month: 6, day: 10)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: [exportDate],
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: nil,
            upload: { records, _, _, _, _, _, _ in
                uploadCount += 1
                XCTAssertEqual(records.map(\.date), [exportDate])
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            },
            maxBatchPayloadBytes: 1
        )

        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(result.successCount, 1)
    }

    func testByteTriggeredFailurePreservesPriorCommitAndMarksFutureDateUnattempted() async {
        let dates = (0..<3).map { date(year: 2026, month: 6, day: 10 + $0) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadCount = 0

        let result = await APIEndpointExportRunner.export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { requestedDate, _, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 500))
            },
            fetchExternalDailyRecords: nil,
            upload: { _, _, _, _, _, _, _ in
                uploadCount += 1
                if uploadCount == 2 {
                    throw APIExportClientError.serverRejected(statusCode: 413, body: "too large")
                }
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            },
            maxBatchDaySpan: 7,
            maxBatchPayloadBytes: 1
        )

        XCTAssertEqual(uploadCount, 2)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.completedDates, [dates[0]])
        XCTAssertEqual(result.failedDateDetails.first {
            Calendar.current.isDate($0.date, inSameDayAs: dates[1])
        }?.reason, .fileWriteError)
        XCTAssertEqual(result.failedDateDetails.first {
            Calendar.current.isDate($0.date, inSameDayAs: dates[2])
        }?.reason, .unknown)
    }

    func testRepeatedSameDayExportsRefetchAndUploadLatestSnapshot() async {
        let exportDate = date(year: 2026, month: 7, day: 18)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiSettings = APIExportSettings(userDefaults: defaults)
        apiSettings.endpointURLString = "https://api.example.com/healthmd"
        var uploadedStepCounts: [Int] = []

        for currentSteps in [1_000, 2_500] {
            let result = await APIEndpointExportRunner.export(
                dates: [exportDate],
                settings: settings,
                apiSettings: apiSettings,
                fetchHealthData: { requestedDate, _, _ in
                    HealthData(
                        date: requestedDate,
                        activity: ActivityData(steps: currentSteps)
                    )
                },
                fetchExternalDailyRecords: nil,
                upload: { records, _, _, _, _, _, _ in
                    uploadedStepCounts.append(records.first?.activity.steps ?? 0)
                    return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
                }
            )

            XCTAssertTrue(result.isFullSuccess)
        }

        XCTAssertEqual(uploadedStepCounts, [1_000, 2_500])
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
        XCTAssertEqual(result.completedDateCount, 0)
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertFalse(result.didCompleteAllRequestedDates)
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
