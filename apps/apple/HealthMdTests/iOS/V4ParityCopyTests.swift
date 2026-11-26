#if os(iOS)
import XCTest
import UIKit
@testable import HealthMd

/// Copy rules restored for 4.0 parity: paywall prices state their billing period (X-03) and
/// device nouns follow the idiom (X-13).
@MainActor
final class V4ParityCopyTests: XCTestCase {
    // MARK: - X-03 price labels

    func testEveryPlanPriceNamesItsBillingPeriod() {
        XCTAssertEqual(HealthMdPurchaseOption.weekly.priceLabel(displayPrice: "$2.99"), "$2.99" + String(localized: "/week"))
        XCTAssertEqual(HealthMdPurchaseOption.familyWeekly.priceLabel(displayPrice: "$4.99"), "$4.99" + String(localized: "/week"))
        XCTAssertEqual(HealthMdPurchaseOption.yearly.priceLabel(displayPrice: "$29.99"), "$29.99" + String(localized: "/year"))
        XCTAssertEqual(HealthMdPurchaseOption.familyYearly.priceLabel(displayPrice: "$49.99"), "$49.99" + String(localized: "/year"))
        for lifetime in [HealthMdPurchaseOption.individual, .family, .familyUpgrade] {
            XCTAssertEqual(lifetime.priceLabel(displayPrice: "$79.99"), "$79.99" + String(localized: " one-time"), "\(lifetime)")
        }
    }

    func testNoPlanPriceIsBare() {
        for option in HealthMdPurchaseOption.allCases {
            XCTAssertFalse(option.priceSuffix.trimmingCharacters(in: .whitespaces).isEmpty, "\(option) has no billing period")
        }
        // Weekly, yearly and lifetime never share a suffix, so no two periods read alike.
        let suffixes = Set([HealthMdPurchaseOption.weekly, .yearly, .individual].map(\.priceSuffix))
        XCTAssertEqual(suffixes.count, 3)
    }

    func testOnboardingTrialTimelineStatesTheYearlyPeriod() {
        let eligible = OnboardingServices.defaultTrialTimeline(price: "$29.99")
        XCTAssertEqual(eligible.last, String(localized: "Day 7 · Billed \("$29.99") a year unless cancelled"))
        XCTAssertEqual(OnboardingServices.defaultTrialTimeline(price: nil).last,
                       String(localized: "Day 7 · Billed yearly unless cancelled"))
        XCTAssertEqual(OnboardingServices.defaultTrialTimeline(price: "$29.99", trialEligible: false),
                       [String(localized: "Billed \("$29.99") a year. Cancel anytime.")])
    }

    // MARK: - X-13 device nouns

    func testIdiomPicksTheDeviceNoun() {
        XCTAssertEqual(HostDevice.from(idiom: .phone), .iPhone)
        XCTAssertEqual(HostDevice.from(idiom: .pad), .iPad)
        XCTAssertEqual(HostDevice.from(idiom: .unspecified), .iPhone)
        XCTAssertEqual(HostDevice.iPhone.pick(iPhone: 1, iPad: 2), 1)
        XCTAssertEqual(HostDevice.iPad.pick(iPhone: 1, iPad: 2), 2)
    }

    func testSharedDeviceCopyNamesTheRightDevice() {
        XCTAssertEqual(HostDevice.iPhone.vaultTitle, String(localized: "Vault on this iPhone"))
        XCTAssertEqual(HostDevice.iPad.vaultTitle, String(localized: "Vault on this iPad"))
        XCTAssertEqual(HostDevice.iPad.folderName, String(localized: "iPad folder"))
        XCTAssertEqual(HostDevice.iPad.onMyDeviceTitle, String(localized: "On My iPad"))
        for copy in [HostDevice.iPad.vaultTitle, HostDevice.iPad.folderName, HostDevice.iPad.onMyDeviceTitle] {
            XCTAssertFalse(copy.contains("iPhone"), copy)
        }
    }
}
#endif
