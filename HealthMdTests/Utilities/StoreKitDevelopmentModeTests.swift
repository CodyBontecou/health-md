//
//  StoreKitDevelopmentModeTests.swift
//  HealthMdTests
//
//  Verifies local development guardrails that keep StoreKit from surfacing
//  Apple's account sign-in sheet during normal simulator launches.
//

import XCTest
@testable import HealthMd

final class StoreKitDevelopmentModeTests: XCTestCase {

    func testTruthyEnvironmentParsing() {
        XCTAssertTrue(StoreKitDevelopmentMode.isTruthy("1"))
        XCTAssertTrue(StoreKitDevelopmentMode.isTruthy(" true "))
        XCTAssertTrue(StoreKitDevelopmentMode.isTruthy("YES"))
        XCTAssertTrue(StoreKitDevelopmentMode.isTruthy("on"))

        XCTAssertFalse(StoreKitDevelopmentMode.isTruthy(nil))
        XCTAssertFalse(StoreKitDevelopmentMode.isTruthy(""))
        XCTAssertFalse(StoreKitDevelopmentMode.isTruthy("0"))
        XCTAssertFalse(StoreKitDevelopmentMode.isTruthy("false"))
    }

    func testDebugSimulatorSkipsStoreKitByDefault() {
        XCTAssertTrue(StoreKitDevelopmentMode.shouldSkipStoreKitAccess(
            isDebugBuild: true,
            isSimulator: true,
            isUITesting: false,
            isExplicitlyEnabledInSimulator: false
        ))
    }

    func testExplicitOptInAllowsStoreKitOnDebugSimulator() {
        XCTAssertFalse(StoreKitDevelopmentMode.shouldSkipStoreKitAccess(
            isDebugBuild: true,
            isSimulator: true,
            isUITesting: false,
            isExplicitlyEnabledInSimulator: true
        ))
    }

    func testRealDeviceDebugBuildDoesNotSkipStoreKit() {
        XCTAssertFalse(StoreKitDevelopmentMode.shouldSkipStoreKitAccess(
            isDebugBuild: true,
            isSimulator: false,
            isUITesting: false,
            isExplicitlyEnabledInSimulator: false
        ))
    }

    func testReleaseSimulatorBuildDoesNotSkipStoreKit() {
        XCTAssertFalse(StoreKitDevelopmentMode.shouldSkipStoreKitAccess(
            isDebugBuild: false,
            isSimulator: true,
            isUITesting: false,
            isExplicitlyEnabledInSimulator: false
        ))
    }

    func testUITestingAlwaysSkipsStoreKit() {
        XCTAssertTrue(StoreKitDevelopmentMode.shouldSkipStoreKitAccess(
            isDebugBuild: false,
            isSimulator: false,
            isUITesting: true,
            isExplicitlyEnabledInSimulator: true
        ))
    }
}
