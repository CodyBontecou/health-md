import XCTest
@testable import HealthMd

@MainActor
final class OnboardingMetricPackTests: XCTestCase {
    func testPackIDsMatchTheSharedCrossPlatformIdentifiers() {
        XCTAssertEqual(
            OnboardingMetricPack.allCases.map(\.rawValue),
            ["sleep", "activity", "heart", "body", "mind", "nutrition", "cycle"]
        )
    }

    func testDefaultSelectionIsSleepActivityAndHeartWithCycleOptIn() {
        XCTAssertEqual(OnboardingMetricPack.defaultSelection, [.sleep, .activity, .heart])
        XCTAssertFalse(OnboardingMetricPack.defaultSelection.contains(.cycle))
    }

    func testEveryCandidateMetricExistsInTheCatalog() {
        let catalog = Set(HealthMetrics.all.map(\.id))
        for pack in OnboardingMetricPack.allCases {
            for id in pack.candidateMetricIDs {
                XCTAssertTrue(catalog.contains(id), "\(pack.rawValue) references unknown metric \(id)")
            }
            XCTAssertFalse(pack.metricIDs.isEmpty, "\(pack.rawValue) has no readable metrics")
        }
    }

    func testPacksDoNotOverlapSoCountsAddUp() {
        var seen: [String: OnboardingMetricPack] = [:]
        for pack in OnboardingMetricPack.allCases {
            for id in pack.candidateMetricIDs {
                XCTAssertNil(seen[id], "\(id) is in both \(seen[id]?.rawValue ?? "") and \(pack.rawValue)")
                seen[id] = pack
            }
        }
        let packs: Set<OnboardingMetricPack> = [.sleep, .heart]
        XCTAssertEqual(
            OnboardingMetricPack.metricIDs(for: packs).count,
            OnboardingMetricPack.sleep.metricCount + OnboardingMetricPack.heart.metricCount
        )
    }

    func testPacksNeverIncludeSeparatelyAuthorizedCategories() {
        let separate = Set(HealthMetrics.all.filter { $0.category.requiresSeparateAuthorization }.map(\.id))
        let all = OnboardingMetricPack.metricIDs(for: Set(OnboardingMetricPack.allCases))
        XCTAssertTrue(all.isDisjoint(with: separate))
    }

    func testApplyReplacesSelectionWithExactlyThePackMetrics() {
        let selection = MetricSelectionState()
        XCTAssertGreaterThan(selection.enabledMetrics.count, 50)

        OnboardingMetricPack.apply([.sleep, .activity], to: selection)

        XCTAssertEqual(
            selection.enabledMetrics,
            OnboardingMetricPack.metricIDs(for: [.sleep, .activity])
        )
    }

    func testCoveredPacksRestoreAPreviousOnboardingChoice() {
        let selection = MetricSelectionState()
        OnboardingMetricPack.apply([.heart, .nutrition], to: selection)
        XCTAssertEqual(OnboardingMetricPack.packs(coveredBy: selection.enabledMetrics), [.heart, .nutrition])
    }
}
