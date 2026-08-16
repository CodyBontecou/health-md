//
//  AdvancedExportSettingsIndividualTrackingTests.swift
//  HealthMdTests
//
//  Individual tracking must stay coupled to the export metric selection:
//  unselected metrics are filtered out of HealthData before individual
//  entries are extracted, so tracking without selection can never produce
//  files in any mode (lossless or compatibility).
//

import XCTest
@testable import HealthMd

@MainActor
final class AdvancedExportSettingsIndividualTrackingTests: XCTestCase {

    private func makeSettings() -> AdvancedExportSettings {
        let suite = "AdvancedExportSettingsIndividualTrackingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AdvancedExportSettings(userDefaults: defaults)
    }

    // MARK: - Explicit mutator

    func testEnablingTrackingAlsoEnablesMetricSelection() {
        let settings = makeSettings()
        settings.metricSelection.deselectAll()
        settings.individualTracking.globalEnabled = true

        settings.setIndividuallyTracked("weight", enabled: true)

        XCTAssertTrue(settings.individualTracking.shouldTrackIndividually("weight"))
        XCTAssertTrue(settings.metricSelection.isMetricEnabled("weight"))
    }

    func testDisablingTrackingLeavesMetricSelectionEnabled() {
        let settings = makeSettings()
        settings.metricSelection.deselectAll()
        settings.individualTracking.globalEnabled = true
        settings.setIndividuallyTracked("weight", enabled: true)

        settings.setIndividuallyTracked("weight", enabled: false)

        XCTAssertFalse(settings.individualTracking.shouldTrackIndividually("weight"))
        XCTAssertTrue(settings.metricSelection.isMetricEnabled("weight"))
    }

    // MARK: - Sync

    func testSyncAddsMissingTrackedMetricsToSelection() {
        let settings = makeSettings()
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("weight", enabled: true)
        settings.individualTracking.setTrackIndividually("steps", enabled: true)
        settings.metricSelection.deselectAll()

        XCTAssertTrue(settings.syncMetricSelectionWithIndividualTracking())

        XCTAssertTrue(settings.metricSelection.isMetricEnabled("weight"))
        XCTAssertTrue(settings.metricSelection.isMetricEnabled("steps"))
    }

    func testSyncIgnoresAlreadySelectedAndUntrackedMetrics() {
        let settings = makeSettings()
        settings.individualTracking.globalEnabled = true
        settings.metricSelection.selectAll()
        let selected = settings.metricSelection.enabledMetrics

        XCTAssertFalse(settings.syncMetricSelectionWithIndividualTracking())
        XCTAssertEqual(settings.metricSelection.enabledMetrics, selected)
    }

    func testSyncDoesNothingWhileGlobalTrackingIsDisabled() {
        let settings = makeSettings()
        settings.individualTracking.globalEnabled = false
        settings.individualTracking.setTrackIndividually("weight", enabled: true)
        settings.metricSelection.deselectAll()

        XCTAssertFalse(settings.syncMetricSelectionWithIndividualTracking())
        XCTAssertFalse(settings.metricSelection.isMetricEnabled("weight"))
    }

    func testSyncNeverReenablesBuildUnavailableMetrics() {
        let settings = makeSettings()
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.metricConfigs["__unavailable_metric__"] =
            MetricTrackingConfig(trackIndividually: true)
        settings.metricSelection.deselectAll()

        XCTAssertFalse(settings.syncMetricSelectionWithIndividualTracking())
        XCTAssertFalse(settings.metricSelection.isMetricEnabled("__unavailable_metric__"))
    }

    func testSyncNeverResurrectsAuthorizationGatedMetrics() throws {
        let settings = makeSettings()
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("weight", enabled: true)
        let medicationMetricID = try XCTUnwrap(
            HealthMetrics.byCategory[.medications]?.first?.id
        )
        settings.individualTracking.setTrackIndividually(medicationMetricID, enabled: true)
        settings.individualTracking.metricConfigs["verifiable_clinical_records"] =
            MetricTrackingConfig(trackIndividually: true)
        settings.metricSelection.deselectAll()

        XCTAssertTrue(settings.syncMetricSelectionWithIndividualTracking())

        XCTAssertTrue(settings.metricSelection.isMetricEnabled("weight"))
        XCTAssertFalse(settings.metricSelection.isMetricEnabled(medicationMetricID),
                       "medication capture requires the explicit per-object authorization flow")
        XCTAssertFalse(settings.metricSelection.isMetricEnabled("verifiable_clinical_records"),
                       "Verifiable Clinical Records must be re-opted-in explicitly")
    }

    // MARK: - Load-time reconciliation

    func testPersistedDormantTrackedMetricIsReselectedOnLoad() throws {
        let suite = "AdvancedExportSettingsIndividualTrackingTests.load.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // First instance: enable tracking globally, then narrow the selection
        // so the tracked metric becomes unselected (legacy dormant state).
        let first = AdvancedExportSettings(userDefaults: defaults)
        first.individualTracking.globalEnabled = true
        first.individualTracking.setTrackIndividually("weight", enabled: true)
        first.metricSelection.deselectAll()
        first.metricSelection.setMetric("steps", enabled: true)
        // Persist the deliberately inconsistent state.
        let encoder = JSONEncoder()
        defaults.set(try encoder.encode(first.individualTracking), forKey: "advancedExportSettings.individualTracking")
        defaults.set(try encoder.encode(first.metricSelection), forKey: "advancedExportSettings.metricSelection")

        let second = AdvancedExportSettings(userDefaults: defaults)

        XCTAssertTrue(second.individualTracking.shouldTrackIndividually("weight"))
        XCTAssertTrue(second.metricSelection.isMetricEnabled("weight"),
                      "load must re-select metrics that are individually tracked but unselected")
        XCTAssertTrue(second.metricSelection.isMetricEnabled("steps"))
    }

    // MARK: - MetricSelectionState.setMetric

    func testSetMetricEnablesAndDisablesWithCategoryState() {
        let selection = MetricSelectionState()

        selection.deselectAll()
        selection.setMetric("weight", enabled: true)
        XCTAssertTrue(selection.enabledMetrics.contains("weight"))

        selection.setMetric("weight", enabled: false)
        XCTAssertFalse(selection.enabledMetrics.contains("weight"))

        // Idempotent no-ops never corrupt category state.
        selection.setMetric("weight", enabled: false)
        XCTAssertFalse(selection.enabledMetrics.contains("weight"))
    }

    func testSetMetricRefusesUnknownAndUnavailableMetrics() throws {
        let selection = MetricSelectionState()
        selection.deselectAll()

        // Unknown metric IDs can never be enabled.
        selection.setMetric("__no_such_metric__", enabled: true)
        XCTAssertFalse(selection.enabledMetrics.contains("__no_such_metric__"))

        // When this build gates any metric behind approval or availability,
        // it must refuse that one too.
        if let unavailable = HealthMetrics.all.first(where: {
            $0.isPendingAppleApproval || !$0.availability.isAvailableOnCurrentPlatform
        }) {
            selection.setMetric(unavailable.id, enabled: true)
            XCTAssertFalse(selection.enabledMetrics.contains(unavailable.id))
        }
    }
}
