#if os(iOS)
import AuthenticationServices
import CryptoKit
import XCTest
@testable import HealthMd

@MainActor
final class ExternalIntegrationManagerTests: XCTestCase {
    private var session: URLSession!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var secureStore: MemoryExternalIntegrationSecureStore!
    private var tokenStore: ExternalIntegrationTokenStore!

    override func setUp() {
        super.setUp()
        session = .externalIntegrationTestSession()
        suiteName = "ExternalIntegrationManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        secureStore = MemoryExternalIntegrationSecureStore()
        tokenStore = ExternalIntegrationTokenStore(keychain: secureStore, userDefaults: defaults)
    }

    override func tearDown() {
        ExternalIntegrationURLProtocolStub.reset()
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suiteName)
        session = nil
        defaults = nil
        secureStore = nil
        tokenStore = nil
        super.tearDown()
    }

    func testConnectCarriesPKCEThroughBrowserAndExchangeBeforeReportingSuccess() async throws {
        var challenge: String?
        var verifier: String?
        ExternalIntegrationURLProtocolStub.setHandler { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.externalIntegrationHTTPBody()) as? [String: Any])
            if request.url?.path == "/v1/oauth/authorize-url" {
                challenge = try XCTUnwrap(body["code_challenge"] as? String)
                XCTAssertEqual(challenge?.count, 43)
                let state = try XCTUnwrap(body["state"] as? String)
                return Self.response(request, status: 200, json: [
                    "provider": "whoop",
                    "authorization_url": "https://api.prod.whoop.com/oauth/oauth2/auth?state=\(state)&code_challenge=\(challenge!)&code_challenge_method=S256"
                ])
            }
            XCTAssertEqual(request.url?.path, "/v1/oauth/token")
            XCTAssertEqual(body["code"] as? String, "code+with space")
            XCTAssertEqual(body["redirect_uri"] as? String, ExternalIntegrationManager.redirectURI)
            verifier = try XCTUnwrap(body["code_verifier"] as? String)
            return Self.response(request, status: 200, json: [
                "access_token": "access-new",
                "refresh_token": "refresh-new",
                "expires_in": 3600,
                "scope": "offline read:cycles"
            ])
        }
        weak var connectingManager: ExternalIntegrationManager?
        let manager = makeManager { url in
            XCTAssertEqual(connectingManager?.connectionStatus?.kind, .progress)
            if let status = connectingManager?.connectionStatus {
                connectingManager?.dismissConnectionStatus(id: status.id)
                XCTAssertNotNil(connectingManager?.connectionStatus, "In-flight progress cannot be dismissed")
            }
            let state = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value)
            return URL(string: "healthmd://oauth/callback?code=code%2Bwith+space&state=\(state)")!
        }
        connectingManager = manager
        await manager.connect(provider: .whoop)

        let digest = SHA256.hash(data: Data(try XCTUnwrap(verifier).utf8))
        let expectedChallenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, expectedChallenge)
        XCTAssertTrue(manager.isConnected(.whoop))
        XCTAssertTrue(makeManager().isConnected(.whoop), "Success must survive reloading account metadata")
        XCTAssertEqual(tokenStore.token(for: .whoop)?.refreshToken, "refresh-new")
        XCTAssertEqual(manager.connectionStatus?.kind, .success)
        XCTAssertNil(manager.isConnectingProvider)

        let status = try XCTUnwrap(manager.connectionStatus)
        manager.dismissConnectionStatus(id: UUID())
        XCTAssertEqual(manager.connectionStatus?.id, status.id, "A stale timer must not clear a newer notice")
        manager.dismissConnectionStatus(id: status.id)
        XCTAssertNil(manager.connectionStatus)
    }

    func testProviderRejectionShowsSafeErrorWithoutExchangingCodeOrSavingCredentials() async throws {
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            return try Self.authorizationResponse(request)
        }
        let manager = makeManager { url in
            let state = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value)
            return URL(string: "healthmd://oauth/callback?error=invalid_request&error_description=The+request+is+malformed+secret-token&error_hint=client_secret%3Dsecret&state=\(state)")!
        }
        await manager.connect(provider: .whoop)

        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(manager.isConnected(.whoop))
        XCTAssertNil(tokenStore.token(for: .whoop))
        XCTAssertEqual(manager.connectionStatus?.kind, .error)
        XCTAssertTrue(manager.statusMessage?.contains("Try connecting again") == true)
        XCTAssertFalse(manager.statusMessage?.contains("+") == true)
        XCTAssertFalse(manager.statusMessage?.contains("secret") == true)
        XCTAssertNil(manager.isConnectingProvider)
    }

    func testBrowserCancellationIsWarningRatherThanConnectionFailure() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            try Self.authorizationResponse(request)
        }
        let manager = makeManager { _ in
            throw ASWebAuthenticationSessionError(.canceledLogin)
        }
        await manager.connect(provider: .whoop)

        XCTAssertEqual(manager.connectionStatus?.kind, .warning)
        XCTAssertEqual(manager.statusMessage, "Cancelled WHOOP connection")
        XCTAssertNil(manager.isConnectingProvider)
        XCTAssertFalse(manager.isConnected(.whoop))
    }

    func testConnectionIsNotSuccessfulWhenCredentialPersistenceFails() async throws {
        secureStore.failAccountWrites = true
        var revoked = false
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.path == "/v1/oauth/authorize-url" {
                return try Self.authorizationResponse(request)
            }
            if request.httpMethod == "DELETE" {
                revoked = true
                return Self.response(request, status: 204, text: "")
            }
            return Self.response(request, status: 200, json: [
                "access_token": "access-new",
                "refresh_token": "refresh-new"
            ])
        }
        let manager = makeManager { url in
            let state = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value)
            return URL(string: "healthmd://oauth/callback?code=code&state=\(state)")!
        }
        await manager.connect(provider: .whoop)

        XCTAssertTrue(revoked)
        XCTAssertFalse(manager.isConnected(.whoop))
        XCTAssertNil(tokenStore.token(for: .whoop))
        XCTAssertEqual(manager.connectionStatus?.kind, .error)
        XCTAssertNil(manager.isConnectingProvider)
    }

    func testManagerUsesSuppliedExportCalendarForProviderDayOwnership() async throws {
        try tokenStore.save(
            token: ExternalIntegrationToken(
                accessToken: "access",
                scope: "read:cycles read:recovery read:sleep read:workout"
            ),
            provider: .whoop
        )
        var starts: [String] = []
        ExternalIntegrationURLProtocolStub.setHandler { request in
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            if let start = components?.queryItems?.first(where: { $0.name == "start" })?.value {
                starts.append(start)
            }
            return Self.response(request, status: 200, json: ["records": []])
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let instant = ISO8601DateFormatter().date(from: "2026-07-12T12:00:00Z")!

        let records = await makeManager().fetchDailyRecords(for: instant, calendar: calendar)

        XCTAssertEqual(records.first?.date, "2026-07-13")
        XCTAssertEqual(Set(starts), ["2026-07-12T10:00:00Z"])
    }

    func testIndependentProviderEndpointsPreserveStableOrdering() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 200, json: ["ok": true])
        }

        let record = try await ExternalProviderAPIClient(session: session).fetchDailyRecord(
            provider: .fitbit,
            date: Self.day(2026, 7, 12),
            token: ExternalIntegrationToken(accessToken: "access")
        )

        XCTAssertEqual(record.payloads.map(\.name), [
            "activities", "sleep", "heart_rate", "hrv", "weight"
        ])
    }

    func testConcurrentUnauthorizedOutranksEarlierTransportFailure() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            let path = request.url?.path ?? ""
            if path.contains("/activities/date/") {
                throw URLError(.networkConnectionLost)
            }
            if path.contains("/sleep/date/") {
                Thread.sleep(forTimeInterval: 0.05)
                return Self.response(
                    request,
                    status: 401,
                    data: Data("unauthorized".utf8),
                    headers: [:]
                )
            }
            return Self.response(request, status: 200, json: ["ok": true])
        }

        do {
            _ = try await ExternalProviderAPIClient(session: session).fetchDailyRecord(
                provider: .fitbit,
                date: Self.day(2026, 7, 12),
                token: ExternalIntegrationToken(accessToken: "expired")
            )
            XCTFail("Expected the concurrent 401 to trigger token refresh")
        } catch let error as ExternalProviderAPIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testOversizedUnauthorizedResponsePreservesRefreshSemantics() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(
                request,
                status: 401,
                data: Data(repeating: 0x61, count: 5),
                headers: [:]
            )
        }

        do {
            _ = try await ExternalProviderAPIClient(
                session: session,
                maximumResponseBytes: 4
            ).fetchDailyRecord(
                provider: .fitbit,
                date: Self.day(2026, 7, 12),
                token: ExternalIntegrationToken(accessToken: "expired")
            )
            XCTFail("Expected the oversized 401 to remain unauthorized")
        } catch let error as ExternalProviderAPIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testOversizedRateLimitResponseUpdatesWHOOPGate() async throws {
        let gate = WHOOPRateLimitGate()
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(
                request,
                status: 429,
                data: Data(repeating: 0x61, count: 5),
                headers: ["Retry-After": "37"]
            )
        }

        do {
            try await ExternalProviderAPIClient(
                session: session,
                whoopRateLimitGate: gate,
                maximumResponseBytes: 4
            ).revokeAccess(
                provider: .whoop,
                token: ExternalIntegrationToken(accessToken: "access")
            )
            XCTFail("Expected the oversized 429 to remain rate limited")
        } catch let error as ExternalProviderAPIError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 37))
        }
        let remainingSeconds = await gate.remainingSeconds()
        XCTAssertEqual(remainingSeconds, 37)
    }

    func testWHOOPPaginationEnforcesAggregateProviderDayResponseBudget() async throws {
        let firstPage = try JSONSerialization.data(withJSONObject: [
            "records": [["id": 1, "value": String(repeating: "a", count: 32)]],
            "next_token": "page-2"
        ])
        let secondPage = try JSONSerialization.data(withJSONObject: [
            "records": [["id": 2, "value": String(repeating: "b", count: 32)]]
        ])
        let aggregateLimit = firstPage.count + secondPage.count - 1
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            let hasCursor = URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )?.queryItems?.contains(where: {
                $0.name == "nextToken" && $0.value == "page-2"
            }) == true
            return Self.response(
                request,
                status: 200,
                data: hasCursor ? secondPage : firstPage,
                headers: [:]
            )
        }

        let record = try await ExternalProviderAPIClient(
            session: session,
            maximumResponseBytes: max(firstPage.count, secondPage.count) + 1,
            maximumProviderDayResponseBytes: aggregateLimit
        ).fetchDailyRecord(
            provider: .whoop,
            date: Self.day(2026, 7, 12),
            token: ExternalIntegrationToken(
                accessToken: "access",
                scope: "read:cycles"
            ),
            now: Self.day(2026, 7, 13)
        )
        XCTAssertEqual(requestCount, 2)
        XCTAssertNotNil(record.payloads.first { $0.name == "cycles" && $0.error == nil })
        guard case .object(let firstRoot)? = record.payloads.first?.data,
              case .array(let retainedRecords)? = firstRoot["records"] else {
            return XCTFail("Expected retained first WHOOP page")
        }
        XCTAssertEqual(retainedRecords.count, 1)
        XCTAssertEqual(
            record.payloads.first { $0.name.hasPrefix("cycles_page_") }?.error,
            "WHOOP response exceeded the provider safety limit."
        )
    }

    func testProviderBoundedConcurrentMapUsesConfiguredWindow() async throws {
        let counter = ExternalProviderConcurrencyCounter()
        let outputs = try await ExternalProviderAPIClient.boundedConcurrentMap(
            Array(0..<9),
            maximumConcurrency: 4
        ) { value in
            await counter.perform(value)
        }

        let maximumActive = await counter.maximumActive
        XCTAssertEqual(outputs, Array(0..<9))
        XCTAssertGreaterThan(maximumActive, 1)
        XCTAssertLessThanOrEqual(maximumActive, 4)
    }

    func testMultiDayExportActionCachesTokenAndPersistsSuccessOnce() async throws {
        let token = ExternalIntegrationToken(
            accessToken: "access",
            refreshToken: "refresh",
            scope: "offline read:cycles read:recovery read:sleep read:workout",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        try tokenStore.save(token: token, provider: .whoop)
        let manager = makeManager()
        secureStore.resetCounters()
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 200, json: ["records": []])
        }

        manager.beginExportAction()
        _ = await manager.fetchDailyRecords(for: Self.day(2026, 7, 11))
        _ = await manager.fetchDailyRecords(for: Self.day(2026, 7, 12))
        manager.endExportAction()

        XCTAssertEqual(secureStore.tokenReadCount, 0)
        XCTAssertEqual(secureStore.accountWriteCount, 1)
        XCTAssertNotNil(tokenStore.accounts[.whoop]?.lastSuccessfulExportAt)
    }

    func testScopedDailyFetchDoesNotContactUnselectedConnectedProvider() async throws {
        try tokenStore.save(
            token: ExternalIntegrationToken(
                accessToken: "access",
                refreshToken: "refresh",
                scope: "offline read:cycles read:recovery read:sleep read:workout",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
            provider: .whoop
        )
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            return Self.response(request, status: 200, json: ["records": []])
        }
        let manager = makeManager()

        let records = await manager.fetchDailyRecords(
            for: Self.day(2026, 7, 12),
            providerIDs: ["oura"]
        )

        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(requestCount, 0)
    }

    func testScopedFetchAndHistoryReportRequestedDisconnectedProvider() async throws {
        var requestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            requestCount += 1
            return Self.response(request, status: 200, json: ["records": []])
        }
        let manager = makeManager()

        let records = await manager.fetchDailyRecords(
            for: Self.day(2026, 7, 12),
            providerIDs: ["whoop"]
        )
        let discovery = await manager.discoverEarliestAvailableDate(
            providerIDs: ["whoop"]
        )

        XCTAssertEqual(records.map(\.provider), [.whoop])
        XCTAssertTrue(records[0].payloads.isEmpty)
        XCTAssertFalse(records[0].warnings.isEmpty)
        XCTAssertEqual(discovery.unresolvedProviderIDs, ["whoop"])
        XCTAssertFalse(discovery.isComplete)
        XCTAssertEqual(requestCount, 0)
    }

    func testFailedExportActionDoesNotPersistSuccessfulFetchTimestamp() async throws {
        let token = ExternalIntegrationToken(
            accessToken: "access",
            refreshToken: "refresh",
            scope: "offline read:cycles read:recovery read:sleep read:workout",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        try tokenStore.save(token: token, provider: .whoop)
        let manager = makeManager()
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 200, json: ["records": []])
        }

        manager.beginExportAction()
        _ = await manager.fetchDailyRecords(for: Self.day(2026, 7, 12))
        manager.endExportAction(succeeded: false)

        XCTAssertNil(tokenStore.accounts[.whoop]?.lastSuccessfulExportAt)
    }

    func testUnauthorizedDailyFetchRefreshesOnceAndRetriesWithRotatedToken() async throws {
        let original = ExternalIntegrationToken(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            scope: "offline read:cycles read:recovery read:sleep read:workout read:body_measurement",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try tokenStore.save(token: original, provider: .whoop)

        var refreshCount = 0
        var oldAccessRequestCount = 0
        var newAccessRequestCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.host == "broker.example.com" {
                refreshCount += 1
                let body = try request.externalIntegrationHTTPBody()
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["refresh_token"] as? String, "refresh-1")
                return Self.response(request, status: 200, json: [
                    "access_token": "access-2",
                    "refresh_token": "refresh-2",
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "scope": original.scope!
                ])
            }

            if request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" {
                oldAccessRequestCount += 1
                return Self.response(request, status: 401, text: "Authorization was not valid")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization")?.lowercased(), "bearer access-2")
            newAccessRequestCount += 1
            return Self.response(request, status: 200, json: ["records": []])
        }

        let manager = makeManager()
        let records = await manager.fetchDailyRecords(for: Self.day(2026, 7, 12))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(oldAccessRequestCount, 1)
        XCTAssertEqual(newAccessRequestCount, 4)
        XCTAssertEqual(tokenStore.token(for: .whoop)?.accessToken, "access-2")
        XCTAssertEqual(tokenStore.token(for: .whoop)?.refreshToken, "refresh-2")
    }

    func testDisconnectRevokesWHOOPBeforeRemovingKeychainCredentials() async throws {
        try tokenStore.save(
            token: ExternalIntegrationToken(
                accessToken: "access-token",
                refreshToken: "refresh-token",
                scope: "offline read:cycles",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            provider: .whoop
        )
        var revokeCount = 0
        ExternalIntegrationURLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/developer/v2/user/access")
            revokeCount += 1
            return Self.response(request, status: 204, text: "")
        }

        let manager = makeManager()
        await manager.disconnect(provider: .whoop)

        XCTAssertEqual(revokeCount, 1)
        XCTAssertNil(tokenStore.token(for: .whoop))
        XCTAssertFalse(manager.isConnected(.whoop))
        XCTAssertEqual(manager.statusMessage, "Disconnected WHOOP and revoked access")
        XCTAssertEqual(manager.connectionStatus?.kind, .success)
    }

    func testFailedRevocationPreservesCredentialsForRetry() async throws {
        try tokenStore.save(
            token: ExternalIntegrationToken(
                accessToken: "access-token",
                refreshToken: "refresh-token",
                scope: "offline read:cycles",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            provider: .whoop
        )
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 429, text: "", headers: ["X-RateLimit-Reset": "20"])
        }

        let manager = makeManager()
        await manager.disconnect(provider: .whoop)

        XCTAssertNotNil(tokenStore.token(for: .whoop))
        XCTAssertTrue(manager.isConnected(.whoop))
        XCTAssertTrue(manager.statusMessage?.contains("Try again") == true)
        XCTAssertEqual(manager.connectionStatus?.kind, .error)
        XCTAssertNil(manager.isDisconnectingProvider)
    }

    func testLateUnauthorizedCallerReusesAlreadyRotatedStoredPair() async throws {
        let stale = ExternalIntegrationToken(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            scope: "offline read:cycles",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let rotated = ExternalIntegrationToken(
            accessToken: "access-2",
            refreshToken: "refresh-2",
            scope: stale.scope,
            expiresAt: Date().addingTimeInterval(3600)
        )
        try tokenStore.save(token: stale, provider: .whoop)
        let manager = makeManager()
        try tokenStore.save(token: rotated, provider: .whoop)
        ExternalIntegrationURLProtocolStub.setHandler { _ in
            XCTFail("A stale caller must not submit the invalidated refresh token")
            throw URLError(.badServerResponse)
        }

        let resolved = try await manager.refreshToken(for: .whoop, replacing: stale)

        XCTAssertEqual(resolved.accessToken, rotated.accessToken)
        XCTAssertEqual(resolved.refreshToken, rotated.refreshToken)
        XCTAssertEqual(resolved.scope, rotated.scope)
    }

    func testInitialAccountMetadataFailureRollsBackHiddenToken() throws {
        secureStore.failAccountWrites = true
        XCTAssertThrowsError(try tokenStore.save(
            token: ExternalIntegrationToken(
                accessToken: "access-token",
                refreshToken: "refresh-token",
                scope: "offline read:cycles"
            ),
            provider: .whoop
        ))
        XCTAssertNil(tokenStore.token(for: .whoop))
        XCTAssertNil(tokenStore.accounts[.whoop])
    }

    func testFailedTokenRollbackNeverCachesUnverifiedPreviousCredential() throws {
        let original = ExternalIntegrationToken(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            scope: "offline read:cycles"
        )
        let replacement = ExternalIntegrationToken(
            accessToken: "access-2",
            refreshToken: "refresh-2",
            scope: "offline read:cycles"
        )
        try tokenStore.save(token: original, provider: .whoop)
        secureStore.failAccountWrites = true
        secureStore.failTokenWriteNumbers = [3]

        XCTAssertThrowsError(try tokenStore.save(token: replacement, provider: .whoop))

        XCTAssertEqual(tokenStore.token(for: .whoop), replacement)
    }

    func testRotatedTokenRemainsAuthoritativeWhenAccountMetadataRepairFails() async throws {
        let original = ExternalIntegrationToken(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            scope: "offline read:cycles",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try tokenStore.save(token: original, provider: .whoop)
        secureStore.failAccountWrites = true
        ExternalIntegrationURLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.host, "broker.example.com")
            return Self.response(request, status: 200, json: [
                "access_token": "access-2",
                "refresh_token": "refresh-2",
                "token_type": "bearer",
                "expires_in": 3600,
                "scope": original.scope!
            ])
        }

        let refreshed = try await makeManager().refreshToken(for: .whoop, replacing: original)

        XCTAssertEqual(refreshed.accessToken, "access-2")
        XCTAssertEqual(tokenStore.token(for: .whoop)?.accessToken, "access-2")
        XCTAssertEqual(tokenStore.token(for: .whoop)?.refreshToken, "refresh-2")
        XCTAssertNotNil(tokenStore.accounts[.whoop])
    }

    func testRefreshPersistenceFailureDoesNotReportSuccessfulRotation() async throws {
        let original = ExternalIntegrationToken(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            scope: "offline read:cycles read:recovery read:sleep read:workout",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try tokenStore.save(token: original, provider: .whoop)
        secureStore.failWrites = true

        ExternalIntegrationURLProtocolStub.setHandler { request in
            if request.url?.host == "broker.example.com" {
                return Self.response(request, status: 200, json: [
                    "access_token": "access-2",
                    "refresh_token": "refresh-2",
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "scope": original.scope!
                ])
            }
            return Self.response(request, status: 401, text: "Authorization was not valid")
        }

        let records = await makeManager().fetchDailyRecords(for: Self.day(2026, 7, 12))

        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].warnings.first?.contains("Keychain") == true)
        XCTAssertEqual(tokenStore.token(for: .whoop)?.accessToken, "access-1")
        XCTAssertEqual(tokenStore.token(for: .whoop)?.refreshToken, "refresh-1")
    }

    func testWHOOPStateIsExactlyEightCharactersAndCallbackMustMatchRegisteredRoute() throws {
        let state = ExternalIntegrationManager.makeState(for: .whoop)
        XCTAssertEqual(state.count, 8)

        let callback = try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/callback?code=oauth-code&state=\(state)")!,
            expectedState: state
        )
        XCTAssertEqual(callback.code, "oauth-code")

        XCTAssertThrowsError(try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/other?code=oauth-code&state=\(state)")!,
            expectedState: state
        ))
        XCTAssertThrowsError(try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/callback?code=oauth-code&state=wrong123")!,
            expectedState: state
        ))
        XCTAssertThrowsError(try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/callback?error=access_denied&error_description=Denied&state=wrong123")!,
            expectedState: state
        )) { error in
            XCTAssertEqual(error as? ExternalOAuthBrokerError, .brokerRejected("OAuth state mismatch."))
        }
        XCTAssertThrowsError(try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/callback?error=access_denied&error_description=Permission%20denied&state=\(state)")!,
            expectedState: state
        )) { error in
            XCTAssertEqual(error as? ExternalOAuthBrokerError, .authorizationRejected("access_denied"))
        }
    }

    func testWHOOPAuthorizationUsesPKCEInAdditionToBrokerHeldClientSecret() {
        XCTAssertTrue(ExternalIntegrationProvider.whoop.usesPKCE)
    }

    func testOAuthCallbackDecodesFormEncodedValuesWithoutChangingLiteralPluses() throws {
        let callback = try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/callback?code=code%2Bwith+space&state=12345678")!,
            expectedState: "12345678"
        )
        XCTAssertEqual(callback.code, "code+with space")

        XCTAssertThrowsError(try ExternalIntegrationManager.parseCallback(
            URL(string: "healthmd://oauth/callback?error=invalid_request&error_description=The+request+is+missing+a+required+parameter&state=12345678")!,
            expectedState: "12345678"
        )) { error in
            XCTAssertEqual(
                error as? ExternalOAuthBrokerError,
                .authorizationRejected("invalid_request")
            )
            XCTAssertFalse(error.localizedDescription.contains("+"))
            XCTAssertTrue(error.localizedDescription.contains("Try connecting again"))
        }
    }

    func testOAuthCallbackRejectsDuplicateSecurityParameters() {
        for query in [
            "state=12345678&state=wrong123&code=code",
            "state=12345678&code=first&code=second",
            "state=12345678&error=access_denied&error=invalid_request",
            "state=12345678&code=code&error=access_denied"
        ] {
            XCTAssertThrowsError(try ExternalIntegrationManager.parseCallback(
                URL(string: "healthmd://oauth/callback?\(query)")!,
                expectedState: "12345678"
            ))
        }
    }

    func testWHOOPRefreshTokenResponseMustContainRotatedRefreshToken() {
        let response = ExternalOAuthTokenResponse(
            accessToken: "access-2",
            refreshToken: nil,
            tokenType: "bearer",
            expiresIn: 3600,
            scope: "offline",
            providerUserID: nil
        )

        XCTAssertThrowsError(try ExternalIntegrationManager.validatedToken(
            from: response,
            provider: .whoop,
            replacing: ExternalIntegrationToken(accessToken: "access-1", refreshToken: "refresh-1")
        ))
    }

    private func makeManager(
        authenticate: (@MainActor (URL) async throws -> URL)? = nil
    ) -> ExternalIntegrationManager {
        ExternalIntegrationManager(
            tokenStore: tokenStore,
            enabledProviders: [.whoop],
            brokerClient: ExternalOAuthBrokerClient(
                baseURL: URL(string: "https://broker.example.com")!,
                clientToken: "client-token",
                session: session
            ),
            apiClient: ExternalProviderAPIClient(session: session),
            authenticate: authenticate
        )
    }

    private static func authorizationResponse(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.externalIntegrationHTTPBody()) as? [String: Any])
        let state = try XCTUnwrap(body["state"] as? String)
        return response(request, status: 200, json: [
            "provider": "whoop",
            "authorization_url": "https://api.prod.whoop.com/oauth/oauth2/auth?state=\(state)"
        ])
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        json: Any,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        response(
            request,
            status: status,
            data: try! JSONSerialization.data(withJSONObject: json),
            headers: headers
        )
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
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!,
            data
        )
    }
}

private actor ExternalProviderConcurrencyCounter {
    private var active = 0
    private(set) var maximumActive = 0

    func perform(_ value: Int) async -> Int {
        active += 1
        maximumActive = max(maximumActive, active)
        try? await Task.sleep(nanoseconds: 20_000_000)
        active -= 1
        return value
    }
}

private final class MemoryExternalIntegrationSecureStore: ExternalIntegrationSecureStoring {
    enum Failure: LocalizedError {
        case write

        var errorDescription: String? { "Simulated Keychain write failure." }
    }

    private var values: [String: String] = [:]
    var failWrites = false
    var failAccountWrites = false
    var failTokenWriteNumbers: Set<Int> = []
    private(set) var tokenReadCount = 0
    private(set) var tokenWriteCount = 0
    private(set) var accountWriteCount = 0

    func resetCounters() {
        tokenReadCount = 0
        accountWriteCount = 0
    }

    func readString(key: String) -> String? {
        if key.contains(".token.") { tokenReadCount += 1 }
        return values[key]
    }

    func writeStringOrThrow(key: String, value: String) throws {
        if key.contains(".token.") {
            tokenWriteCount += 1
            if failTokenWriteNumbers.contains(tokenWriteCount) { throw Failure.write }
        }
        if failWrites || (failAccountWrites && key.contains(".account.")) { throw Failure.write }
        if key.contains(".account.") { accountWriteCount += 1 }
        values[key] = value
    }

    func removeOrThrow(key: String) throws { values[key] = nil }
}
#endif
