import XCTest
@testable import HealthMd

final class ExportTargetReadinessTests: XCTestCase {
    func testLocalTarget_requiresHealthAuthorizationFormatAndLocalFolder() {
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: false,
            hasSelectedFormat: true,
            target: .localIPhoneFolder,
            hasLocalFolder: true,
            canExportToConnectedMac: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: false,
            target: .localIPhoneFolder,
            hasLocalFolder: true,
            canExportToConnectedMac: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .localIPhoneFolder,
            hasLocalFolder: false,
            canExportToConnectedMac: true
        ))
        XCTAssertTrue(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .localIPhoneFolder,
            hasLocalFolder: true,
            canExportToConnectedMac: false
        ))
    }

    func testMacTarget_requiresHealthAuthorizationFormatAndMacReadinessOnly() {
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: false,
            hasSelectedFormat: true,
            target: .connectedMac,
            hasLocalFolder: false,
            canExportToConnectedMac: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: false,
            target: .connectedMac,
            hasLocalFolder: false,
            canExportToConnectedMac: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .connectedMac,
            hasLocalFolder: true,
            canExportToConnectedMac: false
        ))
        XCTAssertTrue(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .connectedMac,
            hasLocalFolder: false,
            canExportToConnectedMac: true
        ))
    }

    func testDailyNotesOnlyAllowsFileTargetsWithoutFormatsButRejectsAPI() {
        XCTAssertTrue(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: false,
            dailyNotesOnlyModeEnabled: true,
            target: .localIPhoneFolder,
            hasLocalFolder: true,
            canExportToConnectedMac: false
        ))
        XCTAssertTrue(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: false,
            dailyNotesOnlyModeEnabled: true,
            target: .connectedMac,
            hasLocalFolder: false,
            canExportToConnectedMac: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            dailyNotesOnlyModeEnabled: true,
            target: .apiEndpoint,
            hasLocalFolder: true,
            canExportToConnectedMac: true,
            apiEndpointConfigured: true
        ))
    }

    func testAPITarget_requiresHealthAuthorizationFormatAndConfiguredEndpointOnly() {
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: false,
            hasSelectedFormat: true,
            target: .apiEndpoint,
            hasLocalFolder: true,
            canExportToConnectedMac: true,
            apiEndpointConfigured: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: false,
            target: .apiEndpoint,
            hasLocalFolder: true,
            canExportToConnectedMac: true,
            apiEndpointConfigured: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .apiEndpoint,
            hasLocalFolder: true,
            canExportToConnectedMac: true,
            apiEndpointConfigured: false
        ))
        XCTAssertTrue(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .apiEndpoint,
            hasLocalFolder: false,
            canExportToConnectedMac: false,
            apiEndpointConfigured: true
        ))
    }
}
