import XCTest
final class HostProbeTests: XCTestCase {
  func testPrivateIdentifierAndNoHealthEntitlementDeclaration() {
    XCTAssertEqual(Bundle.main.bundleIdentifier, "com.healthmd.effecthost.ioscandidate")
    XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription"))
    XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription"))
  }
}
