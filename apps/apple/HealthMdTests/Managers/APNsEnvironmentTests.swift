import Foundation
import XCTest
@testable import HealthMd

final class APNsEnvironmentTests: XCTestCase {
    func testDevelopmentAndDistributionProfilesUseTheirAPNsEntitlement() throws {
        for environment in [APNsEnvironment.development, .production] {
            let profile = try profileData(entitlements: ["aps-environment": environment.rawValue])
            XCTAssertEqual(APNsEnvironment.fromProvisioningProfile(profile), environment)
        }
    }

    func testCMSEnvelopeDoesNotInfluenceEnvironment() throws {
        for environment in [APNsEnvironment.development, .production] {
            var profile = Data([0x30, 0x82, 0x00, 0xff])
            profile.append(try profileData(entitlements: ["aps-environment": environment.rawValue]))
            profile.append(Data([0xff, 0x80, 0x30, 0x00]))
            XCTAssertEqual(APNsEnvironment.fromProvisioningProfile(profile), environment)
        }
    }

    func testProfileFreeAppStoreDistributionUsesProduction() {
        XCTAssertEqual(APNsEnvironment.fromProvisioningProfile(nil), .production)
    }

    func testMalformedOrUnsupportedProfileCannotGuessProduction() throws {
        for profile in [
            Data("invalid profile".utf8),
            Data("<plist><dict>".utf8),
            try profileData(entitlements: [:]),
            try profileData(entitlements: ["aps-environment": "staging"]),
            try profileData(entitlements: ["aps-environment": true]),
        ] {
            XCTAssertNil(APNsEnvironment.fromProvisioningProfile(profile))
        }
    }

    func testBuildDebuggingEntitlementDoesNotOverrideAPNsEnvironment() throws {
        let releaseDevelopment = try profileData(entitlements: [
            "aps-environment": "development", "get-task-allow": false,
        ])
        let debugProduction = try profileData(entitlements: [
            "aps-environment": "production", "get-task-allow": true,
        ])
        XCTAssertEqual(APNsEnvironment.fromProvisioningProfile(releaseDevelopment), .development)
        XCTAssertEqual(APNsEnvironment.fromProvisioningProfile(debugProduction), .production)
    }

    private func profileData(entitlements: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0
        )
    }
}
