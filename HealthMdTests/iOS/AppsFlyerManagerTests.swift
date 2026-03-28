//
//  AppsFlyerManagerTests.swift
//  HealthMdTests
//
//  Tests for AppsFlyerManager key resolution and sanitization.
//  iOS-only since AppsFlyerManager is guarded with #if os(iOS).
//

#if os(iOS)
import XCTest
@testable import HealthMd

final class AppsFlyerManagerTests: XCTestCase {

    // MARK: - sanitizeKey

    func testSanitizeKey_validKey_returnsKey() {
        XCTAssertEqual(AppsFlyerManager.sanitizeKey("abc123DEF"), "abc123DEF")
    }

    func testSanitizeKey_nil_returnsNil() {
        XCTAssertNil(AppsFlyerManager.sanitizeKey(nil))
    }

    func testSanitizeKey_empty_returnsNil() {
        XCTAssertNil(AppsFlyerManager.sanitizeKey(""))
    }

    func testSanitizeKey_whitespaceOnly_returnsNil() {
        XCTAssertNil(AppsFlyerManager.sanitizeKey("   \n  "))
    }

    func testSanitizeKey_trimsWhitespace() {
        XCTAssertEqual(AppsFlyerManager.sanitizeKey("  myKey  "), "myKey")
    }

    func testSanitizeKey_buildVariable_returnsNil() {
        XCTAssertNil(AppsFlyerManager.sanitizeKey("$(APPS_FLYER_DEV_KEY)"))
    }

    func testSanitizeKey_placeholder_returnsNil() {
        XCTAssertNil(AppsFlyerManager.sanitizeKey("YOUR_APPS_FLYER_DEV_KEY"))
    }

    func testSanitizeKey_partialBuildVariable_returnsNil() {
        XCTAssertNil(AppsFlyerManager.sanitizeKey("prefix$(var)suffix"))
    }
}
#endif
