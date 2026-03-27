# Static-Retention Workaround Audit

> Generated: 2026-03-27
> Parent epic: `TODO-2b0cd43e`
> Task: `TODO-e4c602d1`

## Summary

This audit catalogs every instance in the test suite where `ObservableObject` instances are retained via `static let`, `static var`, or static arrays to prevent the **macOS 26 / Swift 6 reentrant-main-actor-deinit crash** (`swift_task_deinitOnExecutorMainActorBackDeploy` bug).

The core problem: when an `ObservableObject` is deallocated at the end of a test method, its `deinit` dispatches to the main actor. If that deallocation occurs inside another `ObservableObject`'s deinit (e.g., a test class teardown), the re-entrant main-actor dispatch triggers a runtime crash. The workaround is to hold these objects in `static` storage so they survive until process exit.

**Findings:**
- **4 test files** contain static-retention workarounds
- **9 test files** are clean (no workarounds needed)
- **6 distinct ObservableObject types** are affected
- **All workarounds are temporary** -- they exist solely to work around the Swift 6 runtime bug

## Audit Matrix

| File | Line(s) | Pattern | Object Type | Instance Count | Classification | Rationale |
|------|---------|---------|-------------|----------------|----------------|-----------|
| DailyNoteInjectorTests.swift | 24 | `static let` | `FormatCustomization` | 1 | Temporary workaround | ObservableObject deinit crash avoidance |
| DailyNoteInjectorTests.swift | 28-59 | `static let` (closures) | `DailyNoteInjectionSettings` | 4 | Temporary workaround | ObservableObject deinit crash avoidance; each instance has different config |
| DailyNoteInjectorTests.swift | 62-118 | `static let` (closures) | `MetricSelectionState` | 8 | Temporary workaround | ObservableObject deinit crash avoidance; each instance has different metric selections |
| ExporterSmokeTests.swift | 26-145 | `static let` in `enum TestCustomizations` | `FormatCustomization` | 16+ | Temporary workaround | File-level enum with static members avoids dealloc; dictionary-stored instances for date/time/bullet permutations |
| IndividualEntryExporterTests.swift | 28 | `static let` | `FormatCustomization` | 1 | Temporary workaround | ObservableObject deinit crash avoidance |
| IndividualEntryExporterTests.swift | 30-83 | `static let` (closures) | `IndividualTrackingSettings` | 7 | Temporary workaround | ObservableObject deinit crash avoidance; each instance has different tracking config |
| ModelTests.swift | 216 | `static var` (array) | `MetricSelectionState` | Dynamic (appended at runtime) | Temporary workaround | `HealthDataTests` uses `retainedMetricSelections` array to keep instances alive |
| ModelTests.swift | 397-398 | `static var` (arrays) | `AdvancedExportSettings`, `MetricSelectionState` | Dynamic (appended at runtime) | Temporary workaround | `AdvancedExportSettingsMigrationTests` retains both types in static arrays |
| ModelTests.swift | 461-494 | `static let` (closures) | `DailyNoteInjectionSettings` | 6 | Temporary workaround | `DailyNoteInjectionSettingsTests` holds all config variants statically |
| ModelTests.swift | 495 | `static var` (array) | `DailyNoteInjectionSettings` | Dynamic (appended at runtime) | Temporary workaround | Codable round-trip test retains both original and decoded instances |
| ModelTests.swift | 578-638 | `static let` (closures) | `IndividualTrackingSettings` | 9 | Temporary workaround | `IndividualTrackingSettingsTests` holds all config variants statically |
| ModelTests.swift | 579 | `static var` (array) | `IndividualTrackingSettings` | Dynamic (appended at runtime) | Temporary workaround | Codable round-trip test retains both original and decoded instances |

### Files with NO static-retention workarounds

| File | Notes |
|------|-------|
| ExportHelpersTests.swift | Uses value types only (`HealthData` is a struct); no ObservableObject involvement |
| MarkdownMergerTests.swift | Tests pure functions on `MarkdownMerger`; no ObservableObject involvement |
| ExportOrchestratorTests.swift | Tests static methods and value-type `ExportResult`; no ObservableObject involvement |
| RuntimeProtocolTests.swift | Tests protocol fakes (final classes, not ObservableObject); no deinit issues |
| SleepCalculationTests.swift | Tests pure static methods on `HealthKitManager`; no ObservableObject involvement |
| ExportHistoryTests.swift | Tests Codable value types and enums; no ObservableObject involvement |
| FrontmatterKeyStyleTests.swift | Tests pure static functions; no ObservableObject involvement |
| HealthKitUnitsTests.swift | Tests HKUnit constants; no ObservableObject involvement |
| UnitConverterTests.swift | Tests `UnitConverter` struct (value type); no ObservableObject involvement |

## Classification Key

| Classification | Meaning | Action required |
|----------------|---------|-----------------|
| **Temporary workaround** | Exists solely to avoid the macOS 26 / Swift 6 `swift_task_deinitOnExecutorMainActorBackDeploy` crash. Should be removed when Apple ships a runtime fix or when affected types are migrated away from `ObservableObject`. | Track for removal via parent epic TODO-2b0cd43e |
| **Accepted design constraint** | A static instance that serves a legitimate architectural purpose (e.g., a true singleton). | No action needed |

> All entries in this audit are classified as **Temporary workaround**. None represent accepted design constraints.

## Affected ObservableObject Types

| Type | Conformance | Test files affected |
|------|------------|---------------------|
| `FormatCustomization` | `ObservableObject` | ExporterSmokeTests, DailyNoteInjectorTests, IndividualEntryExporterTests |
| `DailyNoteInjectionSettings` | `ObservableObject` | DailyNoteInjectorTests, ModelTests |
| `MetricSelectionState` | `ObservableObject` | DailyNoteInjectorTests, ModelTests |
| `IndividualTrackingSettings` | `ObservableObject` | IndividualEntryExporterTests, ModelTests |
| `AdvancedExportSettings` | `ObservableObject` | ModelTests |
| `FrontmatterConfiguration` | `ObservableObject` (nested in `FormatCustomization`) | ExporterSmokeTests (indirectly via FormatCustomization) |

## Retention Patterns Used

1. **`private static let` with closure initializer** -- Most common. A static property is initialized with a closure that creates and configures the ObservableObject. The instance lives for the entire test process. Used in DailyNoteInjectorTests, IndividualEntryExporterTests, ModelTests.

2. **`static let` in a file-level `enum`** -- Used in ExporterSmokeTests via `TestCustomizations`. The caseless enum acts as a namespace for static properties. Same lifetime semantics as pattern 1 but groups many instances together.

3. **`private static var` array with runtime appending** -- Used in ModelTests for Codable round-trip tests and filtered-by-selection tests where the exact instance count depends on test execution. The array grows during the test run but is never cleared, preventing deallocation.

## Recommendations

1. **Monitor Swift runtime fixes**: The underlying bug is in Swift 6's `ObservableObject` deinit dispatch. When Apple resolves this (likely in a future Xcode/Swift toolchain), all temporary workarounds can be reverted to standard `let` instance properties.

2. **Consider `@Observable` migration**: Swift's newer `@Observable` macro (Observation framework) does not suffer from the same main-actor deinit re-entrancy issue. Migrating the 6 affected types from `ObservableObject` to `@Observable` would eliminate the need for these workarounds. This is tracked as a potential follow-up in the parent epic.

3. **Do not add new static-retention workarounds without documenting them here**. Any new test file that retains ObservableObject instances statically should add a row to the Audit Matrix above.

4. **Risk assessment**: The workarounds have no functional impact on test correctness. The only downside is that test instances are never deallocated, which increases peak memory during test runs. Given the small size of these objects (~100 bytes each), this is negligible.

## References

- Parent epic: `.pi/todos/2b0cd43e.md`
- This task: `.pi/todos/e4c602d1.md`
- TDD protocol: `docs/testing/TDD.md`
