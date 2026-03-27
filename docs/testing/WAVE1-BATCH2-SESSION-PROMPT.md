# Wave 1 Batch 2 Session Prompt

Paste the text below into a fresh Claude Code session.

```text
You are working in `/Users/codybontecou/projects/health-md/app`.

## Context
Wave 0 and Wave 1 Batch 1 are COMPLETE (524 tests passing). You are now executing Wave 1 Batch 2 — Manager DI + Tests.

Read `docs/testing/WAVE1-EXECUTION-PLAN.md` for the full dependency graph and status.

## Non-negotiable process
1) Follow `docs/testing/TDD.md` — strict RED/GREEN/REFACTOR for every todo.
2) Use `docs/testing/TDD-COMPLETION-TEMPLATE.md` when appending evidence to todos.
3) Do NOT close a todo without explicit RED/GREEN/REFACTOR evidence in `.pi/todos/<hex>.md`.
4) Set `"status": "done"` in the todo JSON header when closing.
5) Keep commits small and scoped to one todo.

## Todo system
Todos are markdown files in `.pi/todos/`. ID mapping: `TODO-<hex>` → `.pi/todos/<hex>.md`

## What's already built (use these, don't recreate)
- **Protocol seams**: `HealthMd/Shared/Protocols/RuntimeProtocols.swift` — `KeychainStoring`, `UserDefaultsStoring`, `HTTPClientProtocol`, `FileSystemAccessing`
- **Production adapters**: `HealthMd/Shared/Protocols/ProductionAdapters.swift` — `SystemKeychainStore`, `SystemUserDefaults`, `URLSessionHTTPClient`, `SystemFileSystem`
- **HealthKit facade**: `HealthMd/Shared/Protocols/HealthStoreProtocol.swift` — `HealthStoreProviding`
- **Fake implementations** (in test files): `FakeKeychainStore`, `FakeUserDefaults`, `FakeHTTPClient`, `FakeFileSystem` in `HealthMdTests/Managers/RuntimeProtocolTests.swift`; `FakeHealthStore` in `HealthMdTests/Managers/HealthStoreFacadeTests.swift`
- **Export fixtures**: `HealthMdTests/Fixtures/Export/ExportFixtures.swift` — `.emptyDay`, `.partialDay`, `.fullDay`, `.edgeCaseDay`
- **Export contract tests**: `JSONExporterContractTests`, `CSVExporterContractTests`, `ObsidianBasesContractTests`, `WriteModesIntegrationTests` (Batch 1 done)
- **Coverage**: `make coverage` and `make coverage-report`

## CRITICAL: FormatCustomization deinit crash
Any `FormatCustomization` instance in tests MUST be `static let` to avoid macOS 26 crash. See `ExporterSmokeTests.swift` pattern.

## CRITICAL: PBXFileSystemSynchronizedRootGroup
Files added to `HealthMd/` or `HealthMdTests/` directories are auto-discovered — NO pbxproj edits needed.

## Batch 2 Todos (5 todos, all parallelizable)

### Recommended execution order (quick wins first):

**1. TODO-de41226b: HealthDataStore persistence tests (macOS)**
- File: `HealthMd/macOS/Managers/HealthDataStore.swift`
- Minimal change: inject `storeDirectory: URL?` parameter (defaults to app support path)
- Test file: `HealthMdTests/macOS/HealthDataStoreTests.swift`
- No fakes needed — use real temp directories (like WriteModesIntegrationTests pattern)
- Test: write/read/delete/metadata, dateRange, deleteAll, round-trip with ExportFixtures
- macOS-only (guard with `#if os(macOS)` or just run with macOS scheme)

**2. TODO-8bc77fb6: VaultManager DI + tests**
- File: `HealthMd/Shared/Managers/VaultManager.swift`
- DI changes: inject `UserDefaultsStoring` + `FileSystemAccessing` + new `BookmarkResolving` protocol
- Add `BookmarkResolving` to `RuntimeProtocols.swift`, `SystemBookmarkResolver` to `ProductionAdapters.swift`
- Test file: `HealthMdTests/Managers/VaultManagerTests.swift`
- Fakes: `FakeUserDefaults`, `FakeFileSystem` (existing), `FakeBookmarkResolver` (new, in test file)
- Test: bookmark load/save, stale refresh, vault selection, export path construction, write modes

**3. TODO-52990079: Scheduling/AppsFlyer/Review tests**
- Three sub-managers, each independent:
  - **ReviewManager** (`HealthMd/Shared/Utilities/ReviewManager.swift`): inject `UserDefaultsStoring` + `now: () -> Date`. Test milestone triggers (3, 33, 63), cooldown enforcement (14 days).
  - **AppsFlyerManager** (`HealthMd/iOS/AppsFlyerManager.swift`): make `resolveDevKey()`/`sanitizeKey()` internal. Test key resolution, placeholder rejection, whitespace trimming.
  - **SchedulingManager** (`HealthMd/iOS/SchedulingManager.swift` + `macOS/SchedulingManager+macOS.swift`): extract `calculateNextRunDate(schedule:now:)` and `catchUpDatesNeeded(schedule:now:)` as static functions. Test next-run-date for daily/weekly, catch-up date ranges.
- Test files: `HealthMdTests/Utilities/ReviewManagerTests.swift`, `HealthMdTests/iOS/AppsFlyerManagerTests.swift`, `HealthMdTests/iOS/SchedulingManagerTests.swift`

**4. TODO-d37d504d: PurchaseManager DI + state tests**
- File: `HealthMd/Shared/Managers/PurchaseManager.swift`
- DI changes: inject `KeychainStoring` + `HTTPClientProtocol` + `UserDefaultsStoring`. Replace inline `keychainRead`/`keychainWrite` with protocol calls.
- Change `private init()` to accept protocol params with production defaults. Keep `static let shared`.
- Test file: `HealthMdTests/Managers/PurchaseManagerTests.swift`
- Fakes: `FakeKeychainStore`, `FakeHTTPClient`, `FakeUserDefaults` (all existing)
- Test: `canExport`, `isUnlocked`, `freeExportsRemaining`, `recordExportUse`, `isLegacyVersion`, `isBuildNumber`, `sendToWorker`, keychain migration
- NO StoreKit calls in tests — test state machine and business logic only

**5. TODO-8077baec: SyncService protocol + tests**
- File: `HealthMd/Shared/Sync/SyncService.swift`
- Approach: test state machine and message handling, not MPC itself
- Make `handleReceivedData(_:)` internal. Inject `KeepAwakeProviding` protocol for idle timer.
- Consider extracting `MultipeerTransporting` protocol for send/disconnect operations.
- Test file: `HealthMdTests/Sync/SyncServiceTests.swift`
- Test: state transitions (connect/disconnect/connecting), peer discovery, payload encode/decode, keepAwake transitions, error handling

## Test commands
- Full suite: `xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""`
- Focused: append `-only-testing:HealthMdTests/<TestClass>`
- Coverage: `make coverage`

## Quality bar
- Protocol seams over monkey-patching
- Deterministic tests (fixed dates, fakes for OS/network/StoreKit/HealthKit)
- Temp directories for file system tests (auto-cleaned in tearDown)
- New protocols added to `RuntimeProtocols.swift`, production adapters to `ProductionAdapters.swift`

Begin by reading the todo files for the first item (TODO-de41226b), then implement via TDD.
```
