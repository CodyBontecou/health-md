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

    func testHistoryDiscoveryTraversesProviderCursorWithoutSyntheticStartDate() async throws {
        var cycleRequests = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            guard request.url?.path.hasSuffix("/cycle") == true else {
                return Self.response(request, status: 200, json: ["records": []])
            }
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertNil(components?.queryItems?.first { $0.name == "start" })
            XCTAssertNil(components?.queryItems?.first { $0.name == "end" })
            cycleRequests += 1
            if cycleRequests == 1 {
                return Self.response(request, status: 200, json: [
                    "records": [["id": 2, "start": "2024-06-01T12:00:00Z"]],
                    "next_token": "older"
                ])
            }
            return Self.response(request, status: 200, json: [
                "records": [["id": 1, "start": "2020-01-02T03:04:05Z"]]
            ])
        }

        let earliest = try await client.discoverEarliestAvailableDate(
            provider: .whoop,
            token: token()
        )

        XCTAssertEqual(cycleRequests, 2)
        XCTAssertEqual(
            earliest,
            ISO8601DateFormatter().date(from: "2020-01-02T03:04:05Z")
        )
    }

    func testHistoryDiscoveryContinuesBeyondHundredPagesAnd2500Records() async throws {
        var cycleRequests = 0
        var recordsReturned = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            guard request.url?.path.hasSuffix("/cycle") == true else {
                return Self.response(request, status: 200, json: ["records": []])
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertNil(query.first { $0.name == "start" })
            XCTAssertNil(query.first { $0.name == "end" })
            XCTAssertEqual(query.first { $0.name == "limit" }?.value, "25")
            XCTAssertEqual(
                query.first { $0.name == "nextToken" }?.value,
                cycleRequests == 0 ? nil : "history-cursor-\(cycleRequests)"
            )
            cycleRequests += 1
            let lastPage = cycleRequests == 101
            let count = lastPage ? 1 : 25
            recordsReturned += count
            var page: [String: Any] = [
                "records": (0..<count).map { [
                    "id": cycleRequests * 25 + $0,
                    "start": lastPage ? "2010-01-02T03:04:05Z" : "2026-01-01T00:00:00Z"
                ] as [String: Any] }
            ]
            if !lastPage { page["next_token"] = "history-cursor-\(cycleRequests)" }
            return Self.response(request, status: 200, json: page)
        }

        let earliest = try await client.discoverEarliestAvailableDate(
            provider: .whoop,
            token: token()
        )
        XCTAssertEqual(cycleRequests, 101)
        XCTAssertEqual(recordsReturned, 2501)
        XCTAssertEqual(earliest, ISO8601DateFormatter().date(from: "2010-01-02T03:04:05Z"))
    }

    func testDailyPaginationContinuesBeyondHundredPages() async throws {
        var cycleRequests = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            guard request.url?.path.hasSuffix("/cycle") == true else {
                return Self.response(request, status: 200, json: ["records": []])
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "start" }?.value, "2026-07-13T07:00:00Z")
            XCTAssertEqual(query.first { $0.name == "end" }?.value, "2026-07-14T07:00:00Z")
            XCTAssertEqual(
                query.first { $0.name == "nextToken" }?.value,
                cycleRequests == 0 ? nil : "cursor-\(cycleRequests)"
            )
            cycleRequests += 1
            var page: [String: Any] = [
                "records": (0..<25).map { [
                    "id": cycleRequests * 25 + $0,
                    "start": "2026-07-13T09:00:00Z"
                ] as [String: Any] }
            ]
            if cycleRequests < 102 { page["next_token"] = "cursor-\(cycleRequests)" }
            return Self.response(request, status: 200, json: page)
        }

        let record = try await client.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        XCTAssertEqual(cycleRequests, 102)
        XCTAssertEqual(record.payloads.filter { $0.name == "cycles" || $0.name.hasPrefix("cycles_page_") }.count, 102)
        XCTAssertTrue(record.payloads.allSatisfy { $0.error == nil })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sidecar = String(decoding: try encoder.encode(record), as: UTF8.self)
        XCTAssertFalse(sidecar.contains("cursor-"))
        XCTAssertTrue(sidecar.contains("cycles_page_101"))
        XCTAssertTrue(sidecar.contains("cycles_page_102"))
        let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record])?.whoop)
        XCTAssertEqual(whoop.captureStatus, .complete)
        XCTAssertEqual(whoop.cycles.count, 2550)
        XCTAssertEqual(whoop.resources.first { $0.resource == .cycles }?.recordCount, 2550)
        XCTAssertTrue(whoop.cycles.contains { $0.id == "2574" })
    }

    func testHistoryDiscoveryRejectsImmediateAndMultiCursorLoops() async {
        for cursors in [["same"], ["a", "b"], (0..<101).map { "long-loop-\($0)" }] {
            var requestCount = 0
            ExternalIntegrationURLProtocolStub.setHandler { request in
                requestCount += 1
                return Self.response(request, status: 200, json: [
                    "records": [["id": requestCount, "start": "2026-01-01T00:00:00Z"]],
                    "next_token": cursors[(requestCount - 1) % cursors.count]
                ])
            }
            do {
                _ = try await client.discoverEarliestAvailableDate(
                    provider: .whoop,
                    token: token(scope: "read:cycles")
                )
                XCTFail("Expected cursor-cycle rejection")
            } catch {
                XCTAssertEqual(error as? ExternalProviderAPIError, .invalidResponse)
            }
            // Constant-memory cycle detection can revisit a cursor, but must
            // reject even a >100-page cycle within a bounded number of requests.
            XCTAssertLessThanOrEqual(requestCount, cursors.count * 3 + 1)
        }
    }

    func testDailyPaginationRejectsImmediateAndMultiCursorLoopsWithoutExposingCursors() async throws {
        for cursors in [["same"], ["a", "b"], (0..<101).map { "long-loop-\($0)" }] {
            var cycleRequests = 0
            ExternalIntegrationURLProtocolStub.setHandler { request in
                guard request.url?.path.hasSuffix("/cycle") == true else {
                    return Self.response(request, status: 200, json: ["records": []])
                }
                cycleRequests += 1
                return Self.response(request, status: 200, json: [
                    "records": [["id": cycleRequests, "start": "2026-07-13T09:00:00Z"] as [String: Any]],
                    "next_token": cursors[(cycleRequests - 1) % cursors.count]
                ])
            }
            let record = try await client.fetchDailyRecord(
                provider: .whoop,
                date: exportDate,
                token: token(),
                calendar: calendar,
                now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
            )
            XCTAssertLessThanOrEqual(cycleRequests, cursors.count * 3 + 1)
            let failure = try XCTUnwrap(record.payloads.first { $0.name == "cycles_pagination" })
            XCTAssertEqual(failure.statusCode, 0)
            XCTAssertEqual(failure.error, "WHOOP returned a repeated pagination cursor.")
            XCTAssertTrue(record.payloads.contains { $0.name == "cycles" && $0.error == nil })
            XCTAssertTrue(record.payloads.filter { $0.name == "recovery" || $0.name == "sleep" || $0.name == "workouts" }.allSatisfy { $0.error == nil })
            let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record])?.whoop)
            XCTAssertEqual(whoop.captureStatus, .partial)
            XCTAssertEqual(whoop.cycles.count, cycleRequests)
            XCTAssertEqual(whoop.resources.first { $0.resource == .cycles }?.status, .failure)
            XCTAssertFalse(failure.endpoint.contains("long-loop-"))
            XCTAssertTrue(failure.endpoint.contains("redacted"))
        }
    }

    func testHistoryDiscoveryDeadlineBoundsFreshCursorStreamsWithoutReturningPartialLowerBound() async {
        let clock = WHOOPHistoryTestClock()
        let boundedClient = ExternalProviderAPIClient(session: session, whoopHistoryClock: clock.now)
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            clock.advance(by: .seconds(16 * 60))
            return Self.response(request, status: 200, json: [
                "records": [["start": "2026-01-01T00:00:00Z"]],
                "next_token": "fresh-\(requestCount)"
            ])
        }
        do {
            _ = try await boundedClient.discoverEarliestAvailableDate(provider: .whoop, token: token())
            XCTFail("Expected traversal deadline failure, not a partial history date")
        } catch {
            XCTAssertEqual(error as? ExternalProviderAPIError, .requestFailed(
                statusCode: 0,
                message: "WHOOP history discovery exceeded the time safety limit. Try again later."
            ))
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testHistoryDiscoveryExpiredTerminalPageDoesNotReturnALowerBound() async {
        let clock = WHOOPHistoryTestClock()
        let boundedClient = ExternalProviderAPIClient(session: session, whoopHistoryClock: clock.now)
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            clock.advance(by: .seconds(16 * 60))
            return Self.response(request, status: 200, json: [
                "records": [["start": "2010-01-02T03:04:05Z"]]
            ])
        }
        do {
            _ = try await boundedClient.discoverEarliestAvailableDate(
                provider: .whoop, token: token(scope: "read:cycles")
            )
            XCTFail("Expected deadline failure, not a terminal-page lower bound")
        } catch {
            XCTAssertEqual(error as? ExternalProviderAPIError, .requestFailed(
                statusCode: 0,
                message: "WHOOP history discovery exceeded the time safety limit. Try again later."
            ))
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testHistoryDiscoveryDeadlineCancelsAnInFlightResponse() async {
        let started = expectation(description: "History request started")
        let stopped = expectation(description: "History request cancelled")
        WHOOPHangingURLProtocol.setCallbacks(onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WHOOPHangingURLProtocol.self]
        let hangingSession = URLSession(configuration: configuration)
        defer {
            hangingSession.invalidateAndCancel()
            WHOOPHangingURLProtocol.reset()
        }
        let boundedClient = ExternalProviderAPIClient(session: hangingSession, whoopHistoryDuration: .seconds(1))
        do {
            _ = try await boundedClient.discoverEarliestAvailableDate(
                provider: .whoop, token: token(scope: "read:cycles")
            )
            XCTFail("Expected in-flight history deadline failure")
        } catch {
            XCTAssertEqual(error as? ExternalProviderAPIError, .requestFailed(
                statusCode: 0,
                message: "WHOOP history discovery exceeded the time safety limit. Try again later."
            ))
        }
        await fulfillment(of: [started, stopped], timeout: 2)
    }

    func testHistoryDiscoveryAndDailyPaginationCancelInFlightResponses() async {
        for historyDiscovery in [true, false] {
            let started = expectation(description: "Provider request started")
            let stopped = expectation(description: "Provider request cancelled")
            WHOOPHangingURLProtocol.setCallbacks(onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [WHOOPHangingURLProtocol.self]
            let hangingSession = URLSession(configuration: configuration)
            defer {
                hangingSession.invalidateAndCancel()
                WHOOPHangingURLProtocol.reset()
            }
            let hangingClient = ExternalProviderAPIClient(session: hangingSession)
            let operation = Task {
                if historyDiscovery {
                    _ = try await hangingClient.discoverEarliestAvailableDate(provider: .whoop, token: token())
                } else {
                    _ = try await hangingClient.fetchDailyRecord(
                        provider: .whoop, date: exportDate, token: token(), calendar: calendar, now: exportDate
                    )
                }
            }
            await fulfillment(of: [started], timeout: 2)
            operation.cancel()
            do {
                try await operation.value
                XCTFail("Expected cancellation rather than a partial result")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            await fulfillment(of: [stopped], timeout: 2)
        }
    }

    func testHistoryDiscoveryAndDailyPaginationHonorCancellationBeforeRequest() async {
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            return Self.response(request, status: 200, json: ["records": []])
        }
        let cancelledHistory = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.discoverEarliestAvailableDate(provider: .whoop, token: token())
        }
        do {
            _ = try await cancelledHistory.value
            XCTFail("Expected cancelled history traversal")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let cancelledDaily = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.fetchDailyRecord(
                provider: .whoop,
                date: exportDate,
                token: token(),
                calendar: calendar,
                now: exportDate
            )
        }
        do {
            _ = try await cancelledDaily.value
            XCTFail("Expected cancelled daily traversal")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(requestCount, 0)
    }

    func testHistoryDiscoveryAndDailyPaginationRejectMalformedOrOversizedContinuationCursors() async throws {
        for cursor: Any in [42, String(repeating: "x", count: 4_097)] {
            var requestCount = 0
            ExternalIntegrationURLProtocolStub.setHandler { request in
                requestCount += 1
                return Self.response(request, status: 200, json: [
                    "records": [["start": "2026-01-01T00:00:00Z"]],
                    "next_token": cursor
                ])
            }
            do {
                _ = try await client.discoverEarliestAvailableDate(
                    provider: .whoop, token: token(scope: "read:cycles")
                )
                XCTFail("Expected invalid continuation, not successful completion")
            } catch {
                XCTAssertEqual(error as? ExternalProviderAPIError, .invalidResponse)
            }
            XCTAssertEqual(requestCount, 1)
            let record = try await client.fetchDailyRecord(
                provider: .whoop,
                date: exportDate,
                token: token(scope: "read:cycles"),
                calendar: calendar,
                now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
            )
            XCTAssertEqual(requestCount, 2)
            XCTAssertTrue(record.payloads.contains { $0.name == "cycles" && $0.error != nil })
        }
    }

    func testDailyPaginationFreshCursorStreamRemainsBoundedByAggregateResponseBudget() async throws {
        let boundedClient = ExternalProviderAPIClient(
            session: session,
            maximumResponseBytes: 1_024,
            maximumProviderDayResponseBytes: 240
        )
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            return Self.response(request, status: 200, json: [
                "records": [], "next_token": "fresh-\(requestCount)"
            ])
        }
        let record = try await boundedClient.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(scope: "read:cycles"),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )
        XCTAssertLessThan(requestCount, 10)
        XCTAssertTrue(record.payloads.contains {
            $0.error == "WHOOP response exceeded the provider safety limit."
        })
        XCTAssertEqual(HealthProviderSections.normalized(from: [record])?.whoop?.captureStatus, .partial)
    }

    func testStravaPaginationContinuesUntilProviderReturnsPartialPage() async throws {
        var pages: [Int] = []
        ExternalIntegrationURLProtocolStub.setHandler { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let page = Int(components?.queryItems?.first(where: { $0.name == "page" })?.value ?? "") ?? 0
            pages.append(page)
            let count = page == 1 ? 200 : 1
            return Self.response(
                request,
                status: 200,
                json: (0..<count).map { ["id": page * 1_000 + $0] }
            )
        }

        let record = try await client.fetchDailyRecord(
            provider: .strava,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: exportDate
        )

        XCTAssertEqual(pages, [1, 2])
        XCTAssertEqual(record.payloads.map(\.name), ["activities", "activities_page_2"])
    }

    func testLaterCollectionSafetyFailureKeepsEarlierSuccessfulSiblings() async throws {
        let boundedClient = ExternalProviderAPIClient(
            session: session,
            maximumResponseBytes: 1_024,
            maximumProviderDayResponseBytes: 180
        )
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.path.hasSuffix("/cycle") == true {
                return Self.response(request, status: 200, json: [
                    "records": [["id": 1, "start": "2026-07-13T09:00:00Z"]]
                ])
            }
            return Self.response(request, status: 200, json: [
                "records": [["cycle_id": 1, "padding": String(repeating: "x", count: 200)]]
            ])
        }

        let record = try await boundedClient.fetchDailyRecord(
            provider: .whoop,
            date: exportDate,
            token: token(),
            calendar: calendar,
            now: calendar.date(byAdding: .day, value: 1, to: exportDate)!
        )

        XCTAssertNotNil(record.payloads.first { $0.name == "cycles" && $0.error == nil })
        let failure = try XCTUnwrap(record.payloads.first { $0.name == "recovery" })
        XCTAssertEqual(failure.statusCode, 0)
        XCTAssertEqual(failure.error, "WHOOP response exceeded the provider safety limit.")
        XCTAssertTrue(record.payloads.filter { $0.name == "sleep" || $0.name == "workouts" }.allSatisfy {
            $0.statusCode == 0 && $0.error == "WHOOP response exceeded the provider safety limit."
        })

        let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record])?.whoop)
        XCTAssertEqual(whoop.cycles.map(\.id), ["1"])
        XCTAssertEqual(whoop.captureStatus, .partial)
        XCTAssertEqual(whoop.resources.first { $0.resource == .recovery }?.error?.code, "response_too_large")
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

/// Produces headers but never finishes the body, so timeout/cancellation tests
/// exercise the real URLSession loader without sleeps or provider traffic.
private final class WHOOPHangingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var onStart: (() -> Void)?
    private static var onStop: (() -> Void)?

    static func setCallbacks(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.onStart = onStart
        self.onStop = onStop
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        onStart = nil
        onStop = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let callback = Self.onStart
        Self.lock.unlock()
        callback?()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    override func stopLoading() {
        Self.lock.lock()
        let callback = Self.onStop
        Self.lock.unlock()
        callback?()
    }
}

nonisolated private final class WHOOPHistoryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    @Sendable func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    func advance(by duration: Duration) {
        lock.lock()
        defer { lock.unlock() }
        instant = instant.advanced(by: duration)
    }
}
