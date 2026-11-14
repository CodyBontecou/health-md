import Foundation
import XCTest
@testable import HealthMd

final class CloudRepairLinkTests: XCTestCase {
    func testOnlyExactStaticCloudRequestLinkMatches() throws {
        XCTAssertTrue(CloudRepairLink.matches(try XCTUnwrap(URL(string: "healthmd://cloud/requests"))))
        for raw in [
            "HEALTHMD://cloud/requests", "healthmd://Cloud/requests",
            "healthmd://cloud/requests/", "healthmd://cloud/%72equests",
            "healthmd://cloud/requests?date=2026-04-01",
            "healthmd://cloud/requests#token", "healthmd://user@cloud/requests",
            "healthmd://cloud:443/requests",
            "healthmd://direct-cli/pair?host=192.168.1.42",
            "https://account.healthmd.app/repair", " healthmd://cloud/requests",
            "healthmd://cloud/requests\n"
        ] {
            guard let url = URL(string: raw) else { continue }
            XCTAssertFalse(CloudRepairLink.matches(url), "Rejected link was accepted: \(raw)")
        }
    }
}
