# HealthKit partial fetch failure tests

Health.md uses `HealthStoreProviding` as the unit-test seam for HealthKit reads. Unit tests inject `FakeHealthStore` and populate deterministic data with `HealthKitFixtures.populateAllCategories(...)`; per-query failure dictionaries such as `errorsForCategorySamples`, `errorsForSum`, and medication error hooks simulate HealthKit read failures without touching real HealthKit data.

Focused command:

```bash
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:HealthMdTests/HealthKitManagerAuthTests/test_fetchHealthData_medicationFailure_recordsPartialFailureAndContinues \
  -only-testing:HealthMdTests/ExportOrchestratorTests/testExportDates_partialHealthKitFailure_writesSuccessfulCategoriesAndReturnsWarning
```

Coverage notes:

- `HealthKitManager` tests assert a non-lock HealthKit category failure is preserved in `HealthData.partialFailures` while other populated categories still return values.
- `ExportOrchestrator` tests run the manager through a fake vault export and assert the export file still contains successful activity/heart data while `ExportResult.partialFailures` exposes the failed category for user-visible warnings/history.
- Device-locked HealthKit errors remain hard failures and are mapped to `ExportFailureReason.deviceLocked`.
