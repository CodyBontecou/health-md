//
//  LifecycleHarnessTests.swift
//  HealthMdTests
//
//  Tests for the lifecycle stress-test harness utilities.
//  Part of TODO-1ff7bb36 / E6 lifecycle stress epic.
//

import XCTest
@testable import HealthMd

final class LifecycleHarnessTests: XCTestCase {

    // MARK: - assertCreationStability with ObservableObject types

    func testCreationStability_metricSelectionState() {
        LifecycleHarness.assertCreationStability(
            iterations: 20,
            factory: { MetricSelectionState() },
            use: { state in
                state.selectAll()
                state.deselectAll()
                state.toggleMetric("steps")
                _ = state.totalEnabledCount
            }
        )
    }

    func testCreationStability_dailyNoteInjectionSettings() {
        LifecycleHarness.assertCreationStability(
            iterations: 20,
            factory: { DailyNoteInjectionSettings() },
            use: { settings in
                settings.enabled = true
                settings.folderPath = "TestFolder"
                settings.filenamePattern = "{date}"
                settings.createIfMissing = true
                _ = settings.formatFilename(for: Date())
                settings.reset()
            }
        )
    }

    func testCreationStability_individualTrackingSettings() {
        LifecycleHarness.assertCreationStability(
            iterations: 20,
            factory: { IndividualTrackingSettings() },
            use: { settings in
                settings.globalEnabled = true
                settings.setTrackIndividually("weight", enabled: true)
                _ = settings.shouldTrackIndividually("weight")
                settings.reset()
            }
        )
    }

    func testCreationStability_formatCustomization() {
        LifecycleHarness.assertCreationStability(
            iterations: 10,
            factory: { FormatCustomization() },
            use: { customization in
                customization.dateFormat = .iso8601
                customization.unitPreference = .imperial
                customization.markdownTemplate.useEmoji = true
                customization.frontmatterConfig.applyKeyStyle(.camelCase)
            }
        )
    }

    // MARK: - Static retention helper

    func testRetain_keepsObjectAlive() {
        weak var weakRef: MetricSelectionState?
        let obj = MetricSelectionState()
        weakRef = obj
        LifecycleHarness.retain(obj)
        XCTAssertNotNil(weakRef, "Statically retained object should remain alive")
    }

    func testCreate_factoryReturnsConfiguredObject() {
        let settings = LifecycleHarness.create({ DailyNoteInjectionSettings() }) { s in
            s.enabled = true
            s.folderPath = "Custom"
        }
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.folderPath, "Custom")
    }

    func testRetainedCount_incrementsOnRetain() {
        let before = LifecycleHarness.retainedCount
        LifecycleHarness.retain(MetricSelectionState())
        XCTAssertEqual(LifecycleHarness.retainedCount, before + 1)
    }

    // MARK: - Async cancellation cleanup

    func testCancellationCleanup_longRunningTask() async {
        await LifecycleHarness.assertCancellationCleanup { @Sendable in
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5s — will be cancelled
        }
    }

    func testCancellationCleanup_immediateCompletion() async {
        await LifecycleHarness.assertCancellationCleanup { @Sendable in
            // Completes immediately, before cancellation
        }
    }

    // MARK: - Run loop draining

    func testDrainMainRunLoop_doesNotCrash() {
        LifecycleHarness.drainMainRunLoop(cycles: 5)
    }
}
