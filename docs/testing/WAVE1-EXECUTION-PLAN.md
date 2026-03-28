# Wave 1 Execution Plan

## Status: Wave 0 COMPLETE, Wave 1 IN PROGRESS

### What's done (Wave 0 + early Wave 1)
All Wave 0 foundation todos are closed with TDD evidence:
- TODO-8c1f46d5 (DONE) — Protocol seams: `KeychainStoring`, `UserDefaultsStoring`, `HTTPClientProtocol`, `FileSystemAccessing` in `HealthMd/Shared/Protocols/`
- TODO-4a1235b3 (DONE) — HealthKit facade: `HealthStoreProviding` + value types + `SystemHealthStoreAdapter` in `HealthMd/Shared/Protocols/`
- TODO-b17073fc (DONE) — UI test target: `HealthMdUITests` target, `HealthMd-UITests-iOS` scheme, baseline smoke test
- TODO-6ec96488 (DONE) — Coverage CI: `make coverage` + `make coverage-report` + GitHub Actions artifact upload + step summary
- TODO-e4c602d1 (DONE) — Lifecycle audit: `docs/testing/lifecycle-audit.md` — 4 files with 37+ static lets to avoid macOS 26 deinit crash
- TODO-030548a9 (DONE) — Export fixtures: `ExportFixtures` (4 datasets) + `GoldenTestHarness` in `HealthMdTests/Fixtures/Export/`
- TODO-ea804396 (DONE) — Markdown contracts: 19 tests covering frontmatter, sections, units, emoji, ordering

**Test count: 524 passing, 0 failures**

### What's done (Batch 1 — Export Contracts)
- TODO-bc0165f1 (DONE) — JSON + CSV structural contract tests: 23 JSON + 22 CSV tests parsing output, asserting key graphs, types, values
- TODO-62b7743d (DONE) — Obsidian Bases strict contracts: 32 tests covering frontmatter parse, key-style variants, disabled fields, parity
- TODO-8b99740d (DONE) — VaultManager write mode integration: 18 tests with real temp files for overwrite/append/update modes + MarkdownMerger
- TODO-f4593f18 (DONE) — Refactor smoke tests: trimmed weak assertions, kept crash-safety layer, pointed to contract files

### Critical knowledge for next session
1. **FormatCustomization deinit crash**: Any `FormatCustomization` instance created in tests MUST be `static let` to avoid macOS 26 / Swift 6 reentrant-main-actor-deinit crash. See `ExporterSmokeTests.swift` pattern.
2. **Xcode project uses PBXFileSystemSynchronizedRootGroup**: Files added to `HealthMd/` or `HealthMdTests/` directories are auto-discovered — no pbxproj edits needed for source files.
3. **Test command**: `xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""`
4. **Focused test**: append `-only-testing:HealthMdTests/<TestClass>` to the above
5. **Todo files**: `.pi/todos/<hex>.md` — set `"status": "done"` and append TDD evidence block
6. **Fake implementations**: Put fakes in the test file itself (like `FakeKeychainStore` in `RuntimeProtocolTests.swift`)

---

## Wave 1 Remaining Todos — Dependency-Ordered Batches

### Batch 1: Export contracts (no new deps, highest parallelism)
These can all run in parallel — they only need the fixtures from TODO-030548a9.

| TODO | Title | Key Details |
|------|-------|-------------|
| **bc0165f1** | JSON + CSV structural contracts | Parse JSON output, assert key graph. Parse CSV rows, assert header schema + row counts. Use `ExportFixtures.fullDay`. |
| **62b7743d** | Obsidian Bases strict contracts | Full frontmatter parse, key-style variants, disabled fields absent. |
| **8b99740d** | VaultManager write mode integration | Temp dirs, overwrite/append/update with real files, MarkdownMerger for update mode. |
| **f4593f18** | Refactor smoke tests | Trim weak assertions, keep crash-safety layer, move strict checks to contract files. |

### Batch 2: Manager DI + tests (depends on Wave 0 Lane A protocols)
These use the `KeychainStoring`, `UserDefaultsStoring`, `HTTPClientProtocol`, `FileSystemAccessing` protocols.

| TODO | Title | Key Details |
|------|-------|-------------|
| **8bc77fb6** | VaultManager DI + tests | Inject `FileSystemAccessing` + `UserDefaultsStoring`. Test bookmark load/save, export paths, write modes. Use temp dirs. |
| **d37d504d** | PurchaseManager DI + state tests | Inject `KeychainStoring` + `HTTPClientProtocol`. Test `canExport`, `isUnlocked`, free quota, legacy version detection. No StoreKit calls. |
| **8077baec** | SyncService protocol + tests | Extract MPC transport facade. Test state transitions, peer discovery, payload encode/decode. No Bluetooth. |
| **de41226b** | HealthDataStore persistence tests | macOS-only. Inject store directory path. Test write/read/delete/metadata. |
| **52990079** | Scheduling/AppsFlyer/Review tests | Inject BGTaskScheduler + UNNotificationCenter. Test next-run dates, catch-up ranges, milestone triggers. |

### Batch 3: HealthKit tests (depends on Wave 0 Lane B facade)
These use `HealthStoreProviding` + `FakeHealthStore`.

| TODO | Title | Key Details |
|------|-------|-------------|
| **5fa156af** | HealthKit authorization tests | Test `requestAuthorization` flow via fake. |
| **e0f18bb4** | HealthKit fetch data tests | Test `fetchHealthData(for:)` with various fake configurations. |
| **4fac60b8** | HealthKit statistics query tests | Test sum/avg/min/max with fake returns. |
| **847ca530** | HealthKit sample query tests | Test category/quantity/workout queries. |
| **c389cf56** | HealthKit background delivery tests | Test observer query setup, background delivery enable/disable. |

### Batch 4: UI infra (depends on Wave 0 Lane C target)
| TODO | Title | Key Details |
|------|-------|-------------|
| **7d7b3e68** | Add accessibility identifiers | Add `.accessibilityIdentifier()` to key views. No behavior change. |
| **e21370a4** | UI journey tests | Export flow, settings navigation. Use identifiers from 7d7b3e68. |

### Batch 5: Lifecycle stress (depends on Wave 0 Lane E audit)
| TODO | Title | Key Details |
|------|-------|-------------|
| **1ff7bb36** | ObservableObject deinit stress test | Bounded loops, deterministic timeouts. |
| **1eac8522** | Concurrent export stress test | Multi-date parallel exports. |
| **32c61b8b** | Background task lifecycle test | Simulate background/foreground transitions. |
| **5d392723** | Memory pressure / leak detection | Autoreleasepool loops, allocation tracking. |

### Batch 6: CI quality gates (depends on coverage infra)
| TODO | Title | Key Details |
|------|-------|-------------|
| **55c3e0ec** | Coverage threshold enforcement | Fail CI if below threshold. |
| **eb0b1b50** | Warning count gate | Fail CI if new warnings introduced. |
| **a55c5428** | TDD evidence guard | Script to verify todos have RED/GREEN/REFACTOR before merge. |
| **74fdb59f** | Test result summary in PR comments | Post test counts to PR. |
| **188d2f69** | Flaky test detection | Track test timing variance. |
| **9f8571ce** | CI workflow optimization | Parallel jobs, caching. |

---

## Recommended execution order for next session

1. **Start with Batch 1** (export contracts) — 4 todos, fully parallelizable, no new infrastructure needed
2. **Then Batch 2** (manager DI) — 5 todos, highest business value, uses the protocol seams we built
3. **Then Batch 3** (HealthKit) — 5 todos, uses the facade we built
4. **Batches 4-6** as time permits

## Implementation tips
- Use `ExportFixtures.fullDay` / `.partialDay` / `.edgeCaseDay` for all export tests
- Use `FakeKeychainStore`, `FakeUserDefaults`, `FakeHTTPClient`, `FakeFileSystem` from `RuntimeProtocolTests.swift` as starting points for manager fakes
- Use `FakeHealthStore` from `HealthStoreFacadeTests.swift` for HealthKit tests
- Always use `static let` for `FormatCustomization` instances in tests
- Run `make coverage` periodically to track progress toward coverage gates
