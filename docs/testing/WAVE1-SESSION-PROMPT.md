# Wave 1 Session Prompt

Paste the text below into a fresh Claude Code session.

```text
You are working in `/Users/codybontecou/projects/health-md/app`.

## Context
Wave 0 of the testing epics is COMPLETE (5 foundation todos done, 430 tests passing). You are now executing Wave 1.

Read `docs/testing/WAVE1-EXECUTION-PLAN.md` for the full dependency graph, batch ordering, and implementation tips.

## Non-negotiable process
1) Follow `docs/testing/TDD.md` — strict RED/GREEN/REFACTOR for every todo.
2) Use `docs/testing/TDD-COMPLETION-TEMPLATE.md` when appending evidence to todos.
3) Do NOT close a todo without explicit RED/GREEN/REFACTOR evidence in `.pi/todos/<hex>.md`.
4) Set `"status": "done"` in the todo JSON header when closing.
5) Keep commits small and scoped to one todo.

## Todo system
Todos are markdown files in `.pi/todos/`. Full index: `docs/testing/TODO-INDEX.md`.
ID mapping: `TODO-<hex>` → `.pi/todos/<hex>.md`

## What's already built (use these, don't recreate)
- **Protocol seams**: `HealthMd/Shared/Protocols/RuntimeProtocols.swift` — `KeychainStoring`, `UserDefaultsStoring`, `HTTPClientProtocol`, `FileSystemAccessing`
- **Production adapters**: `HealthMd/Shared/Protocols/ProductionAdapters.swift` — `SystemKeychainStore`, `SystemUserDefaults`, `URLSessionHTTPClient`, `SystemFileSystem`
- **HealthKit facade**: `HealthMd/Shared/Protocols/HealthStoreProtocol.swift` — `HealthStoreProviding`, `CategorySampleValue`, `QuantitySampleValue`, `WorkoutValue`
- **HK adapter**: `HealthMd/Shared/Protocols/SystemHealthStoreAdapter.swift`
- **Fake implementations** (in test files): `FakeKeychainStore`, `FakeUserDefaults`, `FakeHTTPClient`, `FakeFileSystem` in `RuntimeProtocolTests.swift`; `FakeHealthStore` in `HealthStoreFacadeTests.swift`
- **Export fixtures**: `HealthMdTests/Fixtures/Export/ExportFixtures.swift` — `.emptyDay`, `.partialDay`, `.fullDay`, `.edgeCaseDay`
- **Golden harness**: `HealthMdTests/Fixtures/Export/GoldenTestHarness.swift` — `assertGoldenMatch()`, `normalizeExportOutput()`
- **UI test target**: `HealthMdUITests` with `HealthMd-UITests-iOS` scheme
- **Coverage**: `make coverage` and `make coverage-report`

## CRITICAL: FormatCustomization deinit crash
Any `FormatCustomization` instance in tests MUST be `static let` to avoid macOS 26 crash. See `ExporterSmokeTests.swift` pattern.

## Execution order
Start with **Batch 1** (export contracts — 4 todos, fully parallel):
- TODO-bc0165f1: JSON + CSV structural contracts
- TODO-62b7743d: Obsidian Bases strict contracts
- TODO-8b99740d: VaultManager write mode integration tests
- TODO-f4593f18: Refactor smoke tests

Then **Batch 2** (manager DI + tests — 5 todos):
- TODO-8bc77fb6: VaultManager DI + tests
- TODO-d37d504d: PurchaseManager DI + state tests
- TODO-8077baec: SyncService protocol + tests
- TODO-de41226b: HealthDataStore persistence tests (macOS)
- TODO-52990079: Scheduling/AppsFlyer/Review tests

Then **Batch 3** (HealthKit tests — 5 todos):
- TODO-5fa156af, TODO-e0f18bb4, TODO-4fac60b8, TODO-847ca530, TODO-c389cf56

Then **Batches 4-6** (UI, lifecycle, CI gates) as time permits.

## Test commands
- Full suite: `make test` or `xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""`
- Focused: append `-only-testing:HealthMdTests/<TestClass>`
- Coverage: `make coverage`

## Quality bar
- Protocol seams over monkey-patching
- Deterministic tests (fixed dates, fakes for OS/network/StoreKit/HealthKit)
- Accessibility identifiers for UI tests
- Fixture/golden comparisons for exporters
- Bounded stress loops for lifecycle tests

Begin by reading the first batch of todo files, then implement via TDD.
```
