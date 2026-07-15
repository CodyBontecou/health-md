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

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        ))!
    }
}
