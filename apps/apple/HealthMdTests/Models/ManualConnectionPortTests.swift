import XCTest
@testable import HealthMd

final class ManualConnectionPortTests: XCTestCase {
    func testExplicitValidPortsArePreserved() {
        for value in ["1", "17646", "17647", "65535", " 17647\n", "017647"] {
            XCTAssertEqual(ManualConnectionPort.parse(value), UInt16(value.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    func testInvalidDraftsNeverProduceADefaultPort() {
        for value in ["", " ", "0", "-1", "65536", "999999999999999999999", "17.647", "1e4", "abc", "17647/path"] {
            XCTAssertNil(ManualConnectionPort.parse(value), value)
        }
    }
}
