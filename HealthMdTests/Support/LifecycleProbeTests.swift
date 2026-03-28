//
//  LifecycleProbeTests.swift
//  HealthMdTests
//
//  Tests for DEBUG lifecycle probes on high-risk ObservableObject types.
//  Part of TODO-32c61b8b / E6 lifecycle stress epic.
//

import XCTest
@testable import HealthMd

final class LifecycleProbeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LifecycleTracker.reset()
    }

    // MARK: - Creation tracking

    func testCreationTracking_formatCustomization() {
        XCTAssertEqual(LifecycleTracker.creationCount(for: "FormatCustomization"), 0)
        let obj = FormatCustomization()
        LifecycleHarness.retain(obj)
        XCTAssertEqual(LifecycleTracker.creationCount(for: "FormatCustomization"), 1)
    }

    func testCreationTracking_frontmatterConfiguration() {
        // FrontmatterConfiguration is created as part of FormatCustomization init
        let beforeFrontmatter = LifecycleTracker.creationCount(for: "FrontmatterConfiguration")
        let obj = FormatCustomization()
        LifecycleHarness.retain(obj)
        XCTAssertGreaterThan(
            LifecycleTracker.creationCount(for: "FrontmatterConfiguration"),
            beforeFrontmatter
        )
    }

    func testCreationTracking_metricSelectionState() {
        XCTAssertEqual(LifecycleTracker.creationCount(for: "MetricSelectionState"), 0)
        let obj = MetricSelectionState()
        LifecycleHarness.retain(obj)
        XCTAssertEqual(LifecycleTracker.creationCount(for: "MetricSelectionState"), 1)
    }

    func testCreationTracking_dailyNoteInjectionSettings() {
        XCTAssertEqual(LifecycleTracker.creationCount(for: "DailyNoteInjectionSettings"), 0)
        let obj = DailyNoteInjectionSettings()
        LifecycleHarness.retain(obj)
        XCTAssertEqual(LifecycleTracker.creationCount(for: "DailyNoteInjectionSettings"), 1)
    }

    func testCreationTracking_individualTrackingSettings() {
        XCTAssertEqual(LifecycleTracker.creationCount(for: "IndividualTrackingSettings"), 0)
        let obj = IndividualTrackingSettings()
        LifecycleHarness.retain(obj)
        XCTAssertEqual(LifecycleTracker.creationCount(for: "IndividualTrackingSettings"), 1)
    }

    // MARK: - Multiple creations

    func testCreationTracking_multipleInstances() {
        for _ in 0..<5 {
            LifecycleHarness.retain(MetricSelectionState())
        }
        XCTAssertEqual(LifecycleTracker.creationCount(for: "MetricSelectionState"), 5)
    }

    // MARK: - Reset

    func testReset_clearsAllCounts() {
        LifecycleHarness.retain(FormatCustomization())
        LifecycleHarness.retain(MetricSelectionState())
        XCTAssertGreaterThan(LifecycleTracker.creationCount(for: "FormatCustomization"), 0)
        XCTAssertGreaterThan(LifecycleTracker.creationCount(for: "MetricSelectionState"), 0)

        LifecycleTracker.reset()
        XCTAssertEqual(LifecycleTracker.creationCount(for: "FormatCustomization"), 0)
        XCTAssertEqual(LifecycleTracker.creationCount(for: "MetricSelectionState"), 0)
    }
}
