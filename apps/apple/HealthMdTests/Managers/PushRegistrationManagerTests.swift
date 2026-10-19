import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class PushRegistrationManagerTests: XCTestCase {
    override func tearDown() {
        ExternalIntegrationURLProtocolStub.reset()
        super.tearDown()
    }

    func testDeviceRegistrationTransmitsTheResolvedAPNsEnvironment() async throws {
        for environment in [APNsEnvironment.development, .production] {
            let session = URLSession.externalIntegrationTestSession()
            defer { session.invalidateAndCancel() }
            let registered = expectation(description: "Registered \(environment.rawValue) APNs token")
            ExternalIntegrationURLProtocolStub.setHandler { request in
                XCTAssertEqual(request.url?.absoluteString, "https://notifications.example.test/devices/register")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let body = try request.externalIntegrationHTTPBody()
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["apnsEnvironment"] as? String, environment.rawValue)
                XCTAssertEqual(json["userId"] as? String, "synthetic-install")
                XCTAssertEqual(json["apnsToken"] as? String, "synthetic-apns-token")
                XCTAssertEqual(json["bundleId"] as? String,
                               Bundle.main.bundleIdentifier ?? "com.codybontecou.obsidianhealth")
                #if os(iOS)
                XCTAssertEqual(json["platform"] as? String, "ios")
                #elseif os(macOS)
                XCTAssertEqual(json["platform"] as? String, "macos")
                #endif
                registered.fulfill()
                return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!, Data())
            }
            let manager = PushRegistrationManager(
                session: session,
                baseURL: URL(string: "https://notifications.example.test")!,
                apnsEnvironment: { environment },
                userIdProvider: { "synthetic-install" }
            )
            await manager.postRegisterDevice(apnsToken: "synthetic-apns-token")
            await fulfillment(of: [registered], timeout: 1)
        }
    }

    func testUnresolvedAPNsEnvironmentDoesNotRegisterAnAmbiguousToken() async {
        let session = URLSession.externalIntegrationTestSession()
        defer { session.invalidateAndCancel() }
        ExternalIntegrationURLProtocolStub.setHandler { request in
            XCTFail("An ambiguous APNs token must not be registered with a guessed environment")
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, Data())
        }
        let manager = PushRegistrationManager(
            session: session,
            baseURL: URL(string: "https://notifications.example.test")!,
            apnsEnvironment: { nil },
            userIdProvider: { "synthetic-install" }
        )
        await manager.postRegisterDevice(apnsToken: "synthetic-apns-token")
    }
}
