//
//  VerifiableHealthRecordsCapabilityTests.swift
//  HealthMdTests
//
//  Keeps the approved Verifiable Health Records managed capability aligned
//  across Health.md's source gate, iOS entitlements, and privacy declaration.
//

import Foundation
import XCTest

final class VerifiableHealthRecordsCapabilityTests: XCTestCase {

    private static let projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Utilities/
            .deletingLastPathComponent()  // HealthMdTests/
            .deletingLastPathComponent()  // app/
    }()

    func testIOSAppDeclaresVerifiableHealthRecordsAccess() throws {
        let entitlements = try plistDictionary("HealthMd/HealthMd.entitlements")

        XCTAssertEqual(
            entitlements["com.apple.developer.healthkit"] as? Bool,
            true,
            "The iOS app must retain the base HealthKit entitlement."
        )

        let access = try XCTUnwrap(
            entitlements["com.apple.developer.healthkit.access"] as? [String],
            "The iOS app must declare HealthKit's managed access entitlement."
        )
        XCTAssertTrue(
            access.contains("health-records"),
            "Apple approved HealthKit Access (Verifiable Health Records) for com.codybontecou.obsidianhealth; the signed app must request health-records."
        )
    }

    func testIOSAppProvidesClinicalRecordsPrivacyDescription() throws {
        let info = try plistDictionary("HealthMd/Info.plist")
        let description = try XCTUnwrap(
            info["NSHealthClinicalHealthRecordsShareUsageDescription"] as? String,
            "Health Records access requires NSHealthClinicalHealthRecordsShareUsageDescription."
        )

        XCTAssertFalse(
            description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "The clinical Health Records permission sheet must explain why Health.md reads these records."
        )
    }

    func testEveryIOSAppBuildConfigurationEnablesVerifiableRecordsCodePath() throws {
        let project = try source("HealthMd.xcodeproj/project.pbxproj")
        let appConfigurations = project
            .components(separatedBy: "isa = XCBuildConfiguration;")
            .filter { $0.contains("INFOPLIST_FILE = HealthMd/Info.plist;") }

        XCTAssertEqual(
            appConfigurations.count,
            4,
            "Expected Debug, Release, Debug-iOS, and Release-iOS configurations for the iOS app."
        )

        for configuration in appConfigurations {
            XCTAssertTrue(
                configuration.contains("CODE_SIGN_ENTITLEMENTS = HealthMd/HealthMd.entitlements;"),
                "Every iOS app configuration must sign with HealthMd/HealthMd.entitlements."
            )
            XCTAssertTrue(
                configuration.contains("HEALTHMD_VERIFIABLE_HEALTH_RECORDS_ENTITLEMENT"),
                "Every iOS app configuration must compile the Apple-approved Verifiable Health Records query path."
            )
        }
    }

    private func projectFile(_ relativePath: String) -> URL {
        Self.projectRoot.appendingPathComponent(relativePath)
    }

    private func plistDictionary(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectFile(relativePath))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any], "\(relativePath) must be a plist dictionary.")
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectFile(relativePath), encoding: .utf8)
    }
}
