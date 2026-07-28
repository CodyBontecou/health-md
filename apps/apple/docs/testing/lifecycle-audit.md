# Static-Retention Workaround Audit

> Last updated: 2026-03-28 (E6 lifecycle stress epic)
> Parent epic: `TODO-2b0cd43e`
> Initial audit: `TODO-e4c602d1`
> E6 debt closure: `TODO-e8508ecb`

## Summary

This audit catalogs every instance in the test suite where `ObservableObject` instances are retained via `static let`, `static var`, `LifecycleHarness.retain()`, or `LifecycleHarness.create()` to prevent the **macOS 26 / Swift 6 reentrant-main-actor-deinit crash** (`swift_task_deinitOnExecutorMainActorBackDeploy` bug).

The core problem: when an `ObservableObject` is deallocated during a test run, it triggers a `malloc: pointer being freed was not allocated` crash. This affects ALL ObservableObject subclasses on macOS 26 / Swift 6, not only nested ones. The `autoreleasepool`-based deallocation pattern also triggers this crash. The workaround is to hold these objects in `static` storage (or via `LifecycleHarness`) so they survive until process exit.

### E6 Migrations (2026-03-28)

The E6 lifecycle stress epic (`TODO-2b0cd43e`) introduced:
- **LifecycleHarness** (`HealthMdTests/Support/LifecycleHarness.swift`) — centralized static retention via `LifecycleHarness.retain()` and per-test factory via `LifecycleHarness.create()`.
- **Migrated patterns**: 5 `static var` arrays and 3 mutable `static let` instances in ModelTests.swift were replaced with `LifecycleHarness.retain()` / `LifecycleHarness.create()` calls.
- **DEBUG lifecycle probes**: `LifecycleTracker` (`#if DEBUG`) tracks creation and deinit counts for 5 high-risk ObservableObject types.
- **All remaining** `static var retained*` arrays now have `STATIC RETENTION JUSTIFICATION` comments.

**Current state:**
- **7 test files** contain static-retention workarounds (4 original + 3 discovered during E6 scan)
- **9 ObservableObject types** are affected (6 original + VaultManager, PurchaseManager, ReviewManager)
- **All workarounds are temporary** -- they exist solely to work around the Swift 6 runtime bug

## Audit Matrix

### Files using LifecycleHarness (migrated in E6)

| File | Pattern | Object Type | Classification | Notes |
|------|---------|-------------|----------------|-------|
| ModelTests.swift (HealthDataTests) | `LifecycleHarness.retain()` in `makeSelection()` | `MetricSelectionState` | Migrated (E6) | Replaced `static var retainedMetricSelections` |
| ModelTests.swift (AdvancedExportSettingsMigrationTests) | `LifecycleHarness.retain()` | `AdvancedExportSettings`, `MetricSelectionState` | Migrated (E6) | Replaced 2 `static var` arrays |
| ModelTests.swift (DailyNoteInjectionSettingsTests) | `LifecycleHarness.create()` | `DailyNoteInjectionSettings` | Migrated (E6) | Per-test factory for mutable instances (testReset, testCodable) |
| ModelTests.swift (IndividualTrackingSettingsTests) | `LifecycleHarness.create()` | `IndividualTrackingSettings` | Migrated (E6) | Per-test factory for mutable instances (testToggle, testReset, testCodable) |

### Files with static retention (justified)

| File | Line(s) | Pattern | Object Type | Instance Count | Justification |
|------|---------|---------|-------------|----------------|---------------|
| DailyNoteInjectorTests.swift | 24 | `static let` | `FormatCustomization` | 1 | Immutable shared fixture. Deinit crash avoidance. |
| DailyNoteInjectorTests.swift | 28-59 | `static let` (closures) | `DailyNoteInjectionSettings` | 4 | Immutable shared fixtures, read-only. |
| DailyNoteInjectorTests.swift | 62-118 | `static let` (closures) | `MetricSelectionState` | 8 | Immutable shared fixtures, read-only. |
| ExporterSmokeTests.swift | 26-145 | `static let` in `enum TestCustomizations` | `FormatCustomization` | 16+ | Immutable namespace for shared read-only smoke test fixtures. |
| ExporterSmokeTests.swift | 848 | `static var` (array) | `AdvancedExportSettings` | Dynamic | `ExportMetricSelectionTests` retains settings per test. |
| IndividualEntryExporterTests.swift | 28 | `static let` | `FormatCustomization` | 1 | Immutable shared fixture. |
| IndividualEntryExporterTests.swift | 30-83 | `static let` (closures) | `IndividualTrackingSettings` | 8 | Immutable shared fixtures, read-only. |
| ModelTests.swift | 470-491 | `static let` (closures) | `DailyNoteInjectionSettings` | 4 | Immutable read-only fixtures (yearMonthDay, quarter, dailyFolder, emptyFolder). |
| ModelTests.swift | 580-625 | `static let` (closures) | `IndividualTrackingSettings` | 6 | Immutable read-only fixtures (various configs). |
| VaultManagerTests.swift | 53-54 | `static var` (arrays) | `VaultManager`, `AdvancedExportSettings` | Dynamic | Manager tests retain per-test instances. |
| PurchaseManagerTests.swift | 16 | `static var` (array) | `PurchaseManager` | Dynamic | Manager tests retain per-test instances. |
| ReviewManagerTests.swift | 15 | `static var` (array) | `ReviewManager` | Dynamic | Manager tests retain per-test instances. |

### Files with NO static-retention workarounds

| File | Notes |
|------|-------|
| ExportHelpersTests.swift | Uses value types only |
| MarkdownMergerTests.swift | Tests pure functions |
| ExportOrchestratorTests.swift | Tests static methods and value types |
| RuntimeProtocolTests.swift | Tests protocol fakes (final classes, not ObservableObject) |
| SleepCalculationTests.swift | Tests pure static methods |
| ExportHistoryTests.swift | Tests Codable value types and enums |
| FrontmatterKeyStyleTests.swift | Tests pure static functions |
| HealthKitUnitsTests.swift | Tests HKUnit constants |
| UnitConverterTests.swift | Tests `UnitConverter` struct (value type) |
| LifecycleHarnessTests.swift | Uses LifecycleHarness (manages own retention) |
| LifecycleProbeTests.swift | Uses LifecycleHarness (manages own retention) |
| ConcurrencyStressTests.swift | Uses LifecycleHarness (manages own retention) |
| SanitizerGateTests.swift | Tests audit/infrastructure only |

## Classification Key

| Classification | Meaning | Action required |
|----------------|---------|-----------------|
| **Temporary workaround** | Exists solely to avoid the macOS 26 / Swift 6 deinit crash. Should be removed when Apple ships a runtime fix or when affected types are migrated to `@Observable`. | Track for removal via parent epic TODO-2b0cd43e |
| **Migrated (E6)** | Previously used `static var` arrays; now uses `LifecycleHarness.retain()` or `LifecycleHarness.create()` for centralized retention and per-test factory isolation. | No action needed unless runtime fix arrives |

> All entries in this audit are temporary workarounds. None represent accepted design constraints.

## Affected ObservableObject Types

| Type | Test files affected | DEBUG probe installed |
|------|---------------------|---------------------|
| `FormatCustomization` | ExporterSmokeTests, DailyNoteInjectorTests, IndividualEntryExporterTests | Yes |
| `FrontmatterConfiguration` | ExporterSmokeTests (indirectly via FormatCustomization) | Yes |
| `MetricSelectionState` | DailyNoteInjectorTests, ModelTests | Yes |
| `DailyNoteInjectionSettings` | DailyNoteInjectorTests, ModelTests | Yes |
| `IndividualTrackingSettings` | IndividualEntryExporterTests, ModelTests | Yes |
| `AdvancedExportSettings` | ModelTests, ExporterSmokeTests, VaultManagerTests | No |
| `VaultManager` | VaultManagerTests | No |
| `PurchaseManager` | PurchaseManagerTests | No |
| `ReviewManager` | ReviewManagerTests | No |

## Retention Patterns Used

1. **`LifecycleHarness.create()`** — E6 pattern. Creates and statically retains via centralized `retainedObjects` array. Returns the instance for use. Preferred for mutable per-test instances.

2. **`LifecycleHarness.retain()`** — E6 pattern. Statically retains an already-created instance. Preferred for Codable round-trip tests where `decoded` instances need retention.

3. **`private static let` with closure initializer** — Pre-E6 pattern. A static property initialized with a closure that creates and configures the ObservableObject. The instance lives for the entire test process. Used for immutable shared fixtures.

4. **`static let` in a file-level `enum`** — Pre-E6 pattern. Used in ExporterSmokeTests via `TestCustomizations`. The caseless enum acts as a namespace for static properties.

5. **`private static var` array with runtime appending** — Pre-E6 pattern (partially migrated). Arrays grow during the test run but are never cleared.

## Diagnostics

### Thread Sanitizer

Run with: `make test-tsan`

Command: `xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' -enableThreadSanitizer YES CODE_SIGNING_ALLOWED=NO ...`

### DEBUG Lifecycle Probes

`LifecycleTracker` (compiled only under `#if DEBUG`) tracks creation and deinit counts for high-risk ObservableObject types. Usage in tests:

```swift
LifecycleTracker.reset()
let obj = FormatCustomization()
XCTAssertEqual(LifecycleTracker.creationCount(for: "FormatCustomization"), 1)
```

## Recommendations

1. **Monitor Swift runtime fixes**: The underlying bug is in Swift 6's ObservableObject dealloc path. When Apple resolves this (likely in a future Xcode/Swift toolchain), all temporary workarounds can be reverted to standard `let` instance properties.

2. **Consider `@Observable` migration**: Swift's newer `@Observable` macro (Observation framework) does not suffer from the same deinit crash. Migrating affected types would eliminate the need for these workarounds.

3. **Do not add new static-retention workarounds without documenting them here.** Any new test file that retains ObservableObject instances statically should add a `STATIC RETENTION JUSTIFICATION` comment and a row to the Audit Matrix above.

4. **Risk assessment**: The workarounds have no functional impact on test correctness. The only downside is that test instances are never deallocated, increasing peak memory during test runs. Given the small size of these objects, this is negligible.

## References

- Parent epic: `.pi/todos/2b0cd43e.md`
- Initial audit: `.pi/todos/e4c602d1.md`
- E6 debt closure: `.pi/todos/e8508ecb.md`
- Lifecycle harness: `HealthMdTests/Support/LifecycleHarness.swift`
- Lifecycle tracker: `HealthMd/Shared/Models/LifecycleTracker.swift`
- TDD protocol: `docs/testing/TDD.md`
