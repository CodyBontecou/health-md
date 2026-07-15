import XCTest
@testable import HealthMd

final class WHOOPProviderAPIClientTests: XCTestCase {
    private var session: URLSession!
    private var client: ExternalProviderAPIClient!
    private var calendar: Calendar!
    private var exportDate: Date!

    override func setUp() {
        super.setUp()
        session = .externalIntegrationTestSession()
        client = ExternalProviderAPIClient(session: session)
        calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        exportDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 12))!
    }

    override func tearDown() {
        ExternalIntegrationURLProtocolStub.reset()
        session.invalidateAndCancel()
        session = nil
        client = nil
        calendar = nil
        exportDate = nil
        super.tearDown()
    }

    func testSuccessfulDailyFetchUsesV2EndpointsHalfOpenLocalDayAndCurrentBodySnapshot() async throws {
        var requests: [URLRequest] = []
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requests.append(request)
            let path = try XCTUnwrap(request.url?.path)
            if path.hasSuffix("/user/measurement/body") {
                return Self.response(request, status: 200, json: [
                    "height_meter": 1.8,
                    "weight_kilogram": 75.0,
                    "max_heart_rate": 190
                ])
            }
            return Self.response(request, status: 200, json: [
                "records": [["id": path, "updated_at": "2026-07-13T12:00:00Z"]]
            ])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: exportDate
        )

        XCTAssertEqual(record.provider, .whoop)
        XCTAssertEqual(record.date, "2026-07-13")
        XCTAssertEqual(record.payloads.map(\.name), [
            "cycles", "recovery", "sleep", "workouts", "body_measurements_snapshot"
        ])
        XCTAssertTrue(record.payloads.allSatisfy { $0.statusCode == 200 && $0.error == nil })
        XCTAssertEqual(requests.count, 5)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-token" })

        for request in requests where request.url?.path.hasSuffix("/user/measurement/body") == false {
            let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(query["start"]!, "2026-07-13T07:00:00Z")
            XCTAssertEqual(query["end"]!, "2026-07-14T07:00:00Z")
            XCTAssertEqual(query["limit"]!, "25")
        }
    }

    func testEmptyCollectionResponsesDoNotProduceExportableSidecar() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 200, json: ["records": []])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        XCTAssertEqual(record.payloads.count, 4)
        XCTAssertTrue(record.payloads.allSatisfy(\.isEmpty))
        XCTAssertFalse(record.shouldExport)
    }

    func testMissingGrantedScopesSkipEndpointsAndReturnActionablePayloadErrors() async throws {
        var requestedPaths: [String] = []
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestedPaths.append(try XCTUnwrap(request.url?.path))
            return Self.response(request, status: 200, json: ["records": []])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(scope: "offline read:cycles"),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        XCTAssertEqual(requestedPaths, ["/developer/v2/cycle"])
        XCTAssertEqual(record.payloads.filter { $0.statusCode == 403 }.count, 3)
        XCTAssertTrue(record.payloads.first { $0.name == "recovery" }?.error?.contains("read:recovery") == true)
        XCTAssertTrue(record.shouldExport)
    }

    func testUnauthorizedResponseThrowsForManagerRefreshAndSingleRetry() async {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 401, text: "Authorization was not valid")
        }

        do {
            _ = try await client.fetchDailyRecord(
                provider: .whoop,
                date: exportDate,
                token: token(),
                calendar: calendar,
                now: exportDate
            )
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? ExternalProviderAPIError, .unauthorized)
        }
    }

    func testRateLimitPayloadStartsClientCooldownAndSuppressesFurtherRequests() async throws {
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            if request.url?.path.hasSuffix("/cycle") == true {
                return Self.response(
                    request,
                    status: 429,
                    text: "Too Many Requests",
                    headers: ["X-RateLimit-Reset": "37"]
                )
            }
            return Self.response(request, status: 200, json: ["records": []])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        let rateLimited = try XCTUnwrap(record.payloads.first { $0.name == "cycles" })
        XCTAssertEqual(rateLimited.statusCode, 429)
        XCTAssertEqual(rateLimited.error, "WHOOP rate limit reached. Try again in about 37 seconds.")
        XCTAssertEqual(record.payloads.count, 4)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(record.payloads.dropFirst().allSatisfy {
            $0.statusCode == 429 && $0.error?.contains("cooldown") == true
        })

        let nextDay = calendar.date(byAdding: .day, value: 1, to: exportDate)!
        let laterRecord = try await client.fetchDailyRecord(
            provider: .whoop,
            date: nextDay,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 2, to: exportDate)!
        )
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(laterRecord.payloads.allSatisfy { $0.statusCode == 429 })
    }

    func testPaginationUsesNextTokenQueryAndRedactsCursorFromSidecar() async throws {
        var cycleRequests = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.path.hasSuffix("/cycle") == true {
                cycleRequests += 1
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                if components?.queryItems?.contains(where: { $0.name == "nextToken" && $0.value == "opaque-cursor" }) == true {
                    return Self.response(request, status: 200, json: ["records": [["id": 2]]])
                }
                return Self.response(request, status: 200, json: [
                    "records": [["id": 1]],
                    "next_token": "opaque-cursor"
                ])
            }
            return Self.response(request, status: 200, json: ["records": []])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        XCTAssertEqual(cycleRequests, 2)
        XCTAssertEqual(record.payloads.prefix(2).map(\.name), ["cycles", "cycles_page_2"])
        XCTAssertTrue(record.payloads[1].endpoint.contains("nextToken=%5Bredacted%5D"))
        XCTAssertFalse(record.payloads[1].endpoint.contains("opaque-cursor"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedSidecar = String(decoding: try encoder.encode(record), as: UTF8.self)
        XCTAssertFalse(encodedSidecar.contains("opaque-cursor"))
        XCTAssertTrue(encodedSidecar.contains("redacted"))
    }

    func testMalformedSuccessIsCapturedAsPartialPayloadError() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.path.hasSuffix("/recovery") == true {
                return Self.response(request, status: 200, text: "not-json")
            }
            return Self.response(request, status: 200, json: ["records": []])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        let recovery = try XCTUnwrap(record.payloads.first { $0.name == "recovery" })
        XCTAssertEqual(recovery.statusCode, 200)
        XCTAssertEqual(recovery.error, "WHOOP returned malformed JSON for recovery.")
        XCTAssertTrue(record.shouldExport)
    }

    func testPartialEndpointFailureKeepsSuccessfulPayloads() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.path.hasSuffix("/activity/sleep") == true {
                return Self.response(request, status: 500, json: ["message": "temporary failure"])
            }
            return Self.response(request, status: 200, json: ["records": [["id": "ok"]]])
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        XCTAssertEqual(record.payloads.count, 4)
        XCTAssertEqual(record.payloads.filter { $0.error == nil }.count, 3)
        XCTAssertEqual(record.payloads.first { $0.name == "sleep" }?.error, "temporary failure")
    }

    func testBodyMeasurementSingletonIsOnlyAssociatedWithCurrentDay() async throws {
        var bodyRequestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.path.hasSuffix("/user/measurement/body") == true {
                bodyRequestCount += 1
                return Self.response(request, status: 200, json: ["weight_kilogram": 75])
            }
            return Self.response(request, status: 200, json: ["records": []])
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: exportDate)!
        let historical = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: tomorrow
        )
        let current = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: exportDate
        )

        XCTAssertNil(historical.payloads.first { $0.name == "body_measurements_snapshot" })
        XCTAssertNotNil(current.payloads.first { $0.name == "body_measurements_snapshot" })
        XCTAssertEqual(bodyRequestCount, 1)
    }

    func testBodyMeasurementRateLimitUsesResetHeaderForLaterDays() async throws {
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            if request.url?.path.hasSuffix("/user/measurement/body") == true {
                return Self.response(
                    request,
                    status: 429,
                    text: "Too Many Requests",
                    headers: ["X-RateLimit-Reset": "123"]
                )
            }
            return Self.response(request, status: 200, json: ["records": []])
        }

        let current = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: exportDate
        )
        XCTAssertEqual(requestCount, 5)
        XCTAssertEqual(current.payloads.last?.statusCode, 429)
        XCTAssertTrue(current.payloads.last?.error?.contains("123 seconds") == true)

        let nextDay = calendar.date(byAdding: .day, value: 1, to: exportDate)!
        let later = try await client.fetchDailyRecord(
            provider: .whoop,
            date: nextDay,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 2, to: exportDate)!
        )
        XCTAssertEqual(requestCount, 5)
        XCTAssertTrue(later.payloads.allSatisfy { $0.statusCode == 429 })
    }

    func testRevokeUsesDeleteAndExtendsRateLimitCooldown() async throws {
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/developer/v2/user/access")
            return Self.response(request, status: 429, text: "", headers: ["X-RateLimit-Reset": "12"])
        }

        do {
            try await client.revokeAccess(provider: .whoop, token: token())
            XCTFail("Expected rate limit error")
        } catch {
            XCTAssertEqual(error as? ExternalProviderAPIError, .rateLimited(retryAfterSeconds: 12))
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(record.payloads.allSatisfy { $0.statusCode == 429 })
    }

    private func token(scope: String = "offline read:cycles read:recovery read:sleep read:workout read:body_measurement") -> ExternalIntegrationToken {
        ExternalIntegrationToken(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            scope: scope,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        json: Any,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return response(request, status: status, data: data, headers: headers)
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        text: String,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        response(request, status: status, data: Data(text.utf8), headers: headers)
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        data: Data,
        headers: [String: String]
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, data)
    }
}
