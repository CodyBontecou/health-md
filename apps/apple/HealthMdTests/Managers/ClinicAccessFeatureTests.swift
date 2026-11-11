import XCTest
@testable import HealthMd

final class ClinicAccessFeatureTests: XCTestCase {
    func testHiddenUnlessTheBuildSettingTurnsItOn() {
        XCTAssertFalse(ClinicAccessFeature.isEnabled(infoDictionary: [:]))
        XCTAssertFalse(ClinicAccessFeature.isEnabled(infoDictionary: ["ClinicAccessEnabled": ""]))
        XCTAssertFalse(ClinicAccessFeature.isEnabled(infoDictionary: ["ClinicAccessEnabled": "NO"]))
        XCTAssertFalse(ClinicAccessFeature.isEnabled(infoDictionary: ["ClinicAccessEnabled": "$(CLINIC_ACCESS_ENABLED)"]))
        XCTAssertTrue(ClinicAccessFeature.isEnabled(infoDictionary: ["ClinicAccessEnabled": "YES"]))
        XCTAssertTrue(ClinicAccessFeature.isEnabled(infoDictionary: ["ClinicAccessEnabled": "true"]))
    }

    func testTheShippedAppHidesClinicAccess() {
        XCTAssertFalse(ClinicAccessFeature.isEnabled)
    }
}
