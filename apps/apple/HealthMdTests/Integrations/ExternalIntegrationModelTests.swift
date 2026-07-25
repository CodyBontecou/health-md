import XCTest
@testable import HealthMd

final class ExternalIntegrationModelTests: XCTestCase {
    func testWHOOPRolloutFlagEnablesOnlyWHOOP() {
        XCTAssertEqual(
            ConnectedAppsFeature.enabledProviders(infoDictionary: [
                ConnectedAppsFeature.whoopFlagKey: "YES"
            ]),
            [.whoop]
        )
        XCTAssertEqual(
            ConnectedAppsFeature.enabledProviders(infoDictionary: [
                ConnectedAppsFeature.whoopFlagKey: false
            ]),
            []
        )
        XCTAssertEqual(
            ConnectedAppsFeature.enabledProviders(infoDictionary: [:]),
            []
        )
    }

    func testSidecarEncodingRedactsSensitiveEndpointAndPayloadValues() throws {
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-07-13",
            payloads: [ExternalProviderPayload(
                name: "cycles",
                endpoint: "https://api.example.com/cycles?nextToken=cursor&access_token=secret&start=2026-07-13",
                statusCode: 200,
                data: .object([
                    "access_token": .string("secret"),
                    "nested": .object(["refresh_token": .string("also-secret")]),
                    "records": .array([])
                ])
            )]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = String(decoding: try encoder.encode(record), as: UTF8.self)

        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("also-secret"))
        XCTAssertFalse(text.contains("cursor"))
        XCTAssertTrue(text.contains("redacted"))
        XCTAssertTrue(text.contains("start=2026-07-13"))
    }

    func testSidecarExportDateRejectsTraversalAndInvalidCalendarDates() {
        XCTAssertTrue(makeRecord(date: "2026-07-13").hasValidExportDate)
        XCTAssertFalse(makeRecord(date: "../2026-07-13").hasValidExportDate)
        XCTAssertFalse(makeRecord(date: "2026-02-30").hasValidExportDate)
        XCTAssertFalse(makeRecord(date: "2026-7-3").hasValidExportDate)
    }

    func testWrappedEmptyWHOOPRecordsAreNotExportable() {
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-07-13",
            payloads: [ExternalProviderPayload(
                name: "cycles",
                endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                statusCode: 200,
                data: .object(["records": .array([])])
            )]
        )

        XCTAssertTrue(record.payloads[0].isEmpty)
        XCTAssertFalse(record.shouldExport)
    }

    private func makeRecord(date: String) -> ExternalDailyRecord {
        ExternalDailyRecord(
            provider: .whoop,
            date: date,
            payloads: [ExternalProviderPayload(
                name: "cycles",
                endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                statusCode: 200,
                data: .object(["records": .array([.object(["id": .number(1)])])])
            )]
        )
    }
}
