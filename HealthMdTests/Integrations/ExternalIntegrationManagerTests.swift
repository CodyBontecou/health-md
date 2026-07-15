#if os(iOS)
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
            XCTAssertEqual(error as? ExternalOAuthBrokerError, .brokerRejected("Permission denied"))
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

    private func makeManager() -> ExternalIntegrationManager {
        ExternalIntegrationManager(
            tokenStore: tokenStore,
            enabledProviders: [.whoop],
            brokerClient: ExternalOAuthBrokerClient(
                baseURL: URL(string: "https://broker.example.com")!,
                clientToken: "client-token",
                session: session
            ),
            apiClient: ExternalProviderAPIClient(session: session)
        )
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

private final class MemoryExternalIntegrationSecureStore: ExternalIntegrationSecureStoring {
    enum Failure: LocalizedError {
        case write

        var errorDescription: String? { "Simulated Keychain write failure." }
    }

    private var values: [String: String] = [:]
    var failWrites = false
    var failAccountWrites = false

    func readString(key: String) -> String? { values[key] }

    func writeStringOrThrow(key: String, value: String) throws {
        if failWrites || (failAccountWrites && key.contains(".account.")) { throw Failure.write }
        values[key] = value
    }

    func removeOrThrow(key: String) throws { values[key] = nil }
}
#endif
