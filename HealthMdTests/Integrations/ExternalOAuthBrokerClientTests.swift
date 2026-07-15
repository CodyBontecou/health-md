import XCTest
@testable import HealthMd

final class ExternalOAuthBrokerClientTests: XCTestCase {
    private var session: URLSession!
    private var client: ExternalOAuthBrokerClient!

    override func setUp() {
        super.setUp()
        session = .externalIntegrationTestSession()
        client = ExternalOAuthBrokerClient(
            baseURL: URL(string: "https://broker.example.com")!,
            clientToken: "mobile-gate",
            session: session
        )
    }

    override func tearDown() {
        ExternalIntegrationURLProtocolStub.reset()
        session.invalidateAndCancel()
        session = nil
        client = nil
        super.tearDown()
    }

    func testAuthorizeURLBuildsExpectedBrokerRequest() async throws {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://broker.example.com/v1/oauth/authorize-url")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mobile-gate")
            let body = try request.externalIntegrationHTTPBody()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["provider"] as? String, "whoop")
            XCTAssertEqual(json["redirect_uri"] as? String, "healthmd://oauth/callback")
            XCTAssertEqual(json["state"] as? String, "12345678")
            XCTAssertEqual(
                json["scope"] as? String,
                "offline read:recovery read:cycles read:sleep read:workout read:body_measurement"
            )
            XCTAssertNil(json["code_challenge"])
            return Self.response(request, status: 200, json: [
                "provider": "whoop",
                "authorization_url": "https://api.prod.whoop.com/oauth/oauth2/auth?state=12345678"
            ])
        }

        let response = try await client.authorizeURL(
            provider: .whoop,
            redirectURI: "healthmd://oauth/callback",
            state: "12345678"
        )

        XCTAssertEqual(response.provider, .whoop)
        XCTAssertEqual(response.authorizationURL.host, "api.prod.whoop.com")
    }

    func testExchangeCodeAndRefreshDecodeNormalizedTokens() async throws {
        var paths: [String] = []
        ExternalIntegrationURLProtocolStub.setHandler { request in
            paths.append(try XCTUnwrap(request.url?.path))
            let body = try request.externalIntegrationHTTPBody()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            if request.url?.path.hasSuffix("/token") == true {
                XCTAssertEqual(json["grant_type"] as? String, "authorization_code")
                XCTAssertEqual(json["code"] as? String, "oauth-code")
            } else {
                XCTAssertEqual(json["grant_type"] as? String, "refresh_token")
                XCTAssertEqual(json["refresh_token"] as? String, "refresh-1")
            }
            return Self.response(request, status: 200, json: [
                "access_token": paths.count == 1 ? "access-1" : "access-2",
                "refresh_token": paths.count == 1 ? "refresh-1" : "refresh-2",
                "token_type": "bearer",
                "expires_in": 3600,
                "scope": "offline read:cycles"
            ])
        }

        let exchanged = try await client.exchangeCode(
            provider: .whoop,
            code: "oauth-code",
            redirectURI: "healthmd://oauth/callback"
        )
        let refreshed = try await client.refresh(provider: .whoop, refreshToken: "refresh-1")

        XCTAssertEqual(paths, ["/v1/oauth/token", "/v1/oauth/refresh"])
        XCTAssertEqual(exchanged.accessToken, "access-1")
        XCTAssertEqual(exchanged.refreshToken, "refresh-1")
        XCTAssertEqual(refreshed.accessToken, "access-2")
        XCTAssertEqual(refreshed.refreshToken, "refresh-2")
    }

    func testBrokerErrorMessageIsNormalizedForDisplay() async {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 400, json: [
                "ok": false,
                "error": "invalid_grant",
                "message": "WHOOP authorization expired or was revoked. Reconnect the account."
            ])
        }

        do {
            _ = try await client.refresh(provider: .whoop, refreshToken: "revoked")
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(
                error as? ExternalOAuthBrokerError,
                .brokerRejected("WHOOP authorization expired or was revoked. Reconnect the account.")
            )
        }
    }

    func testMalformedSuccessIsRejected() async {
        ExternalIntegrationURLProtocolStub.setHandler { request in
            Self.response(request, status: 200, json: ["ok": true])
        }

        do {
            _ = try await client.refresh(provider: .whoop, refreshToken: "refresh")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? ExternalOAuthBrokerError, .invalidResponse)
        }
    }

    func testMissingConfigurationFailsWithoutNetworkRequest() async {
        let unconfigured = ExternalOAuthBrokerClient(baseURL: nil, clientToken: nil, session: session)
        do {
            _ = try await unconfigured.authorizeURL(
                provider: .whoop,
                redirectURI: "healthmd://oauth/callback",
                state: "12345678"
            )
            XCTFail("Expected not configured")
        } catch {
            XCTAssertEqual(error as? ExternalOAuthBrokerError, .notConfigured)
        }
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        json: Any
    ) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}
