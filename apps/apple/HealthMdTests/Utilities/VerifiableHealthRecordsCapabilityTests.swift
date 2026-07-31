//
//  VerifiableHealthRecordsCapabilityTests.swift
//  HealthMdTests
//
//  Prevents Clinical Health Records access from returning to App Store builds
//  without an explicit source, entitlement, privacy, and signing review.
//

import Foundation
import XCTest
@testable import HealthMd

final class HealthRecordsCapabilityTests: XCTestCase {

    private static let projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Utilities/
            .deletingLastPathComponent()  // HealthMdTests/
            .deletingLastPathComponent()  // app/
    }()

    func testIOSAppRetainsBaseHealthKitButOmitsHealthRecordsAccess() throws {
        let entitlements = try plistDictionary("HealthMd/HealthMd.entitlements")

        XCTAssertEqual(
            entitlements["com.apple.developer.healthkit"] as? Bool,
            true,
            "The iOS app must retain ordinary HealthKit access."
        )
        XCTAssertNil(
            entitlements["com.apple.developer.healthkit.access"],
            "App Store builds must not request health-records or verifiable-health-records."
        )
    }

    func testEveryShippingHealthKitTargetOmitsManagedHealthRecordsAccess() throws {
        let entitlementPaths = [
            "HealthMd/HealthMd.entitlements",
            "HealthMdWatch/HealthMdWatch.entitlements",
            "HealthMdWidgets/HealthMdWidgets.entitlements",
            "HealthMdWatchWidgets/HealthMdWatchWidgets.entitlements",
        ]

        for path in entitlementPaths {
            let entitlements = try plistDictionary(path)
            XCTAssertNil(
                entitlements["com.apple.developer.healthkit.access"],
                "\(path) must not declare managed Health Records access."
            )
        }
    }

    func testIOSAppOmitsClinicalRecordsPrivacyDescription() throws {
        let info = try plistDictionary("HealthMd/Info.plist")
        XCTAssertNil(
            info["NSHealthClinicalHealthRecordsShareUsageDescription"],
            "The Clinical Health Records usage description must stay absent while access is disabled."
        )
        XCTAssertNotNil(
            info["NSHealthShareUsageDescription"],
            "Ordinary Apple Health read access still requires its privacy description."
        )
    }

    func testEveryIOSAppBuildConfigurationOmitsHealthRecordsSourceFlags() throws {
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
            XCTAssertFalse(
                configuration.contains("HEALTHMD_HEALTH_RECORDS_ACCESS"),
                "Clinical Health Records source must stay disabled in every iOS app configuration."
            )
            XCTAssertFalse(
                configuration.contains("HEALTHMD_VERIFIABLE_HEALTH_RECORDS_ENTITLEMENT"),
                "Verifiable Health Records source must stay disabled in every iOS app configuration."
            )
        }
    }

    @MainActor
    func testProductionHealthStoreAdapterReportsClinicalRecordsUnavailable() {
        XCTAssertFalse(ClinicalHealthRecordsBuildConfiguration.isEnabled)
        XCTAssertFalse(HealthMetricCategory.availableCases.contains(.clinicalRecords))
        XCTAssertFalse(HealthMetricCategory.availableCases.contains(.clinicalDocuments))
        XCTAssertTrue(HealthMetrics.availableMetricIDsInCurrentBuild.isDisjoint(with: [
            "clinical_lab_result_records",
            "cda_documents",
            "verifiable_clinical_records",
        ]))

        let store = SystemHealthStoreAdapter()
        XCTAssertFalse(store.supportsHealthRecords)
        XCTAssertFalse(store.supportsCDADocuments)
        XCTAssertFalse(store.supportsVerifiableClinicalRecords)
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
