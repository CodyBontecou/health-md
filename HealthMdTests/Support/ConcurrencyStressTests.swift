//
//  ConcurrencyStressTests.swift
//  HealthMdTests
//
//  Bounded, deterministic stress tests for main-actor objects, cancellation
//  paths, and repeated init/teardown under async load.
//  Part of TODO-5d392723 / E6 lifecycle stress epic.
//

import XCTest
@testable import HealthMd

@MainActor
final class ConcurrencyStressTests: XCTestCase {

    // MARK: - Concurrent updates on main-actor objects

    func testConcurrentMetricSelectionUpdates() async {
        let state = LifecycleHarness.create({ MetricSelectionState() })

        // 50 concurrent tasks toggling metrics
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let metricId = "metric_\(i % 10)"
                group.addTask { @MainActor in
                    state.toggleMetric(metricId)
                }
            }
        }

        // Invariant: totalEnabledCount should not be negative or crash
        XCTAssertGreaterThanOrEqual(state.totalEnabledCount, 0)
    }

    func testConcurrentDailyNoteSettingsMutation() async {
        let settings = LifecycleHarness.create({ DailyNoteInjectionSettings() })

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    settings.enabled = (i % 2 == 0)
                    settings.folderPath = "folder_\(i)"
                    settings.filenamePattern = "{date}_\(i)"
                    _ = settings.formatFilename(for: Date())
                }
            }
        }

        // Should not crash; final state is deterministic (last write wins)
        XCTAssertFalse(settings.folderPath.isEmpty)
    }

    func testConcurrentIndividualTrackingMutation() async {
        let settings = LifecycleHarness.create({ IndividualTrackingSettings() }) { s in
            s.globalEnabled = true
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let metricId = "metric_\(i % 10)"
                group.addTask { @MainActor in
                    settings.toggleMetric(metricId)
                    _ = settings.shouldTrackIndividually(metricId)
                    _ = settings.totalEnabledCount
                }
            }
        }

        XCTAssertGreaterThanOrEqual(settings.totalEnabledCount, 0)
    }

    // MARK: - Rapid cancellation paths

    func testRapidCancellation_metricSelectionToggle() async {
        for _ in 0..<20 {
            await LifecycleHarness.assertCancellationCleanup { @Sendable in
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }
    }

    func testRapidCancellation_taskGroupWithCancelledChildren() async {
        let state = LifecycleHarness.create({ MetricSelectionState() })

        let task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask { @MainActor in
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                        state.toggleMetric("metric_\(i)")
                    }
                }
            }
        }

        // Cancel quickly
        try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        task.cancel()
        await task.value

        // Should not crash; state is consistent
        XCTAssertGreaterThanOrEqual(state.totalEnabledCount, 0)
    }

    // MARK: - Repeated init/teardown under async load

    func testRepeatedCreation_underAsyncLoad() async {
        // Create 50 instances rapidly, each exercised asynchronously
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    let state = LifecycleHarness.create({ MetricSelectionState() })
                    state.selectAll()
                    state.deselectAll()
                    state.toggleMetric("steps")
                    _ = state.totalEnabledCount
                }
            }
        }
        // Survived without crash
    }

    func testRepeatedCreation_formatCustomizationUnderLoad() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { @MainActor in
                    let c = LifecycleHarness.create({ FormatCustomization() })
                    c.dateFormat = .iso8601
                    c.unitPreference = .imperial
                    c.markdownTemplate.useEmoji = true
                    c.frontmatterConfig.applyKeyStyle(.camelCase)
                }
            }
        }
    }

    func testRepeatedCreation_mixedTypesUnderLoad() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask { @MainActor in
                    switch i % 3 {
                    case 0:
                        let s = LifecycleHarness.create({ MetricSelectionState() })
                        s.toggleMetric("steps")
                    case 1:
                        let s = LifecycleHarness.create({ DailyNoteInjectionSettings() })
                        s.enabled = true
                        _ = s.formatFilename(for: Date())
                    default:
                        let s = LifecycleHarness.create({ IndividualTrackingSettings() })
                        s.globalEnabled = true
                        s.setTrackIndividually("weight", enabled: true)
                    }
                }
            }
        }
    }

    // MARK: - Fixed iteration deterministic stress

    func testDeterministicStress_selectAllDeselectAllCycle() {
        let state = LifecycleHarness.create({ MetricSelectionState() })
        let totalMetrics = state.totalMetricCount

        for _ in 0..<100 {
            state.selectAll()
            XCTAssertEqual(state.totalEnabledCount, totalMetrics)
            state.deselectAll()
            XCTAssertEqual(state.totalEnabledCount, 0)
        }
    }

    func testDeterministicStress_resetCycle() {
        for _ in 0..<50 {
            let s = LifecycleHarness.create({ DailyNoteInjectionSettings() }) { s in
                s.enabled = true
                s.folderPath = "Custom"
                s.createIfMissing = true
            }
            s.reset()
            XCTAssertFalse(s.enabled)
            XCTAssertEqual(s.folderPath, "Daily")
        }
    }
}
