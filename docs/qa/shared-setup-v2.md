# Share My Setup v2 transaction QA record

- Date: 2026-09-05
- Branch: `shared-setup-v2/c3-contract-manifest` (record written from the cycle-2 integrated tree at base `eae6feb97`)
- Worktree: `/private/tmp/healthmd-c3-contract-manifest`
- Reconciled: 2026-09-05 from `shared-setup-v2/c4-docs-capability-ci` (worktree `/private/tmp/healthmd-c4-docs-capability-ci`) after cycle 3 landed the native scenario suites and the production seams on main; see the [cycle-4 amendment](#cycle-4-amendment-2026-09-05) below. The original receipt tables above are retained unchanged as dated history.

## Status: deferred — not default

`healthmd.shared_setup` remains **version 2, status `deferred`**. This record makes **no enablement and no default-writer claims**:

- The v2 grammar and its Add/Replace/Undo transaction semantics are specified and implemented behind explicit, caller-supplied seams. They are **not wired into any production flow as of this record**.
- The **default portable document writer remains v1** on both platforms. Apply/Undo integration work does not flip any default writer, and this record must never be cited as evidence that it did.
- Canonicalization remains gated on native integration, physical-device interoperability, and accessibility QA, exactly as the v1 record requires. None of those gates are claimed here.
- This is a **host-side-only** QA record. It contains no simulator-manual, emulator, or physical-device claims.

The QA surface is the [v2 contract's transaction sections](../../packages/contracts/shared-setup/v2/contract.md) — *Add, Replace, and native materialization*, *Unbound and blocked imported profiles*, *Per-profile compatibility sidecar*, and *Atomic apply, rollback, and one-shot Undo* — with the frozen [transaction scenario fixture](../../packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json) as the conformance source.

## Automated gates (host-side only)

Receipts are from the cycle-2 integrated tree (`eae6feb97`) plus this cycle's contracts rerun with the finalized manifest inventory.

| Gate | Result |
|---|---|
| `python3 packages/contracts/test_validate_shared_setup.py` | 33 tests, OK — includes scenario Add/Replace exactness, selection rejection, name-collision suffixing, disabled unbound imports, sidecar preservation, verified rollback, one-shot Undo, and public-artifact isolation |
| `python3 packages/contracts/validate.py` (this lane, with extended `implementations`/`consumers`) | 15 contracts, 35 fixtures, 13 packaging mirrors, 2 inventories, 3 output profiles, 33 product capabilities, 55 local documentation links, exit 0 |
| Apple iOS Simulator union suite (cycle-2 receipt; `CODE_SIGNING_ALLOWED=NO`) | 123 tests, 0 failures, TEST SUCCEEDED — `SharedSetupV2ProfileTransactionTests` 9, `SharedSetupV1Tests` 25, `SharedSetupV2CodecMapperTests` 11, `SharedSetupV2CanonicalIOTests` 4, `SharedSetupV2CoordinatorIOTests` 6, plus coordinator/scheduling/intent/direct suites exercising the execution gate |
| Generic unsigned iOS Simulator build of `HealthMd` (cycle-2 receipt) | BUILD SUCCEEDED |
| Android JVM merged suite (cycle-2 receipt; `--offline --no-daemon --max-workers=2`) | 205 tests / 24 classes, 0 failures, 0 errors, 0 skipped, exit 0 — includes `SharedSetupV2ProfileTransactionTest` 16, `SharedSetupVersionedIoTest`, `SharedSetupSettingsTransactionTest` 4, service/intent/viewmodel/codec suites, and the gated scheduler/automation/direct/export call sites |
| Frozen-byte proofs vs `1e268b05e` (cycle-2 receipt) | Zero diff across `packages/contracts/shared-setup/v1/`, `HealthMetricsDictionary.swift`, and frozen export signature fixtures; SHA-256 equal to recorded baselines for both v1 fixtures, both canonical v2 fixtures, and the scenario fixture |

The scenario fixture bytes remain pinned by the manifest (`2f72266d…`) and are frozen, read-only conformance input; no native suite may regenerate them.

## Transaction behavior coverage

| Behavior | Contract requirement | Host-side evidence | Status |
|---|---|---|---|
| Bounded atomic Add | Selection is rejected before any write for empty/duplicate/unknown/padded IDs or a stale plan; normalized to document order; existing profiles, schedules, sidecar, and blocked rows preserved byte-for-byte; imported rows appended with deterministic name-collision suffixes | `SharedSetupV2ProfileTransactionTests` (Apple), `SharedSetupV2ProfileTransactionTest` (Android), scenario fixture expected Add state verified by the contracts validator | Covered host-side |
| Bounded atomic Replace | Existing profile/schedule/sidecar/blocked state discarded from the candidate; only selected profiles rebuilt in normalized order; source active-profile fallback exact | Same suites; scenario fixture expected Replace state verified by the contracts validator | Covered host-side |
| Fresh native IDs | Every selected profile receives a newly generated native identity unique against the existing store and other imports; `bundle_id` survives only as sidecar source identity | Transaction suites; validator rejects native-ID leakage into public artifacts | Covered host-side |
| Unbound destinations | Imported folder/API binding fields are `nil`; connected-Mac and cloud intent stay pending; no destination is resolved, listed, opened, paired, or authenticated during import | Transaction suites assert nil bindings; scenario fixture rejects inherited binding IDs | Covered host-side |
| Disabled schedules | Any imported schedule row is created disabled with empty runtime fields; `activation_requested` is inert review intent only | Transaction suites; scenario fixture rejects an enabled import row | Covered host-side |
| Sidecar preservation | Per-profile compatibility sidecar retains the complete closed source DTO plus foreign typed extensions and unsupported semantic IDs; bounded to 4 MiB, checked before mutation | Apple and Android transaction suites; validator rejects dropped foreign extension or unsupported-ID rows | Covered host-side |
| Blocked-profile fail-closed | Every generated profile ID enters the blocked set; activation, manual/profile-scoped export, scheduled execution, App Intent/automation, and direct profile resolution fail closed with a bounded non-secret reason | Apple gate + call-site suites (ExportProfileCoordinator, SchedulingManager, ExportIntent, IPhoneDirectFileJournal); Android gate suites (scheduler entry/adoption/cancellation, automation, direct, export ViewModels) | Covered host-side |
| Explicit rebind | Only a typed local confirmation clears the block: concrete folder binding, verified API endpoint plus persisted/verified credentials, or explicit Mac pairing confirmation; cloud remains blocked; editing/renaming/duplicating never clears | Android transaction tests cover folder-exact, API-URL-insufficient, credential-confirmation hook, and duplicate-stays-blocked rules; Apple gate tests cover confirm/persist/verify paths | Covered host-side |
| One-shot Undo | A successful apply persists exactly one prior-state snapshot; Undo restores and verifies it, then removes and verifies removal of itself; a second Undo returns `no_undo_snapshot` and writes nothing | Both transaction suites; scenario fixture rejects a replayable second Undo | Covered host-side |
| Undo bounds | Sidecar bounded to 4 MiB and complete Undo payload to 8 MiB; checks happen before the first write | Android transaction tests exercise both bound failures pre-mutation; Apple transaction error surface (`sidecarTooLarge`, `undoTooLarge`) | Covered host-side |
| Verified rollback | Any encoding/write/synchronization/verification failure restores and verifies prior bytes/order, active identity, schedules, sidecar, blocked set, and prior Undo value; unverifiable rollback fails closed as unverified | Apple verified-commit/restore suites; Android post-commit verification fault → compare-and-set rollback and concurrent-mutation `ROLLBACK_NOT_VERIFIED` tests | Covered host-side |
| Destination/credential isolation | Apply, Undo, and rollback never mutate the destination store or secure credential store | `SharedSetupSettingsTransactionTest` apply/undo/rollback/endpoint-confirmation persistence checks; scenario fixture asserts unchanged destination/secure-store markers | Covered host-side |
| Bounded versioned document IO | Reads accept at most 4 MiB with a one-byte overflow probe; versioned dispatch accepts only strict integer `1`/`2`; canonical writer output is sorted compact UTF-8 JSON with exactly one trailing LF | `SharedSetupV2CanonicalIOTests` + `SharedSetupV2CoordinatorIOTests` (Apple); `SharedSetupVersionedIoTest` (Android); contracts validator enforces the same rules on fixtures | Covered host-side |

## Conformance source

The deterministic [transaction scenario fixture](../../packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json) is the single conformance source for Add/Replace materialization, fresh native IDs, disabled unbound imports, per-profile sidecar preservation, blocked IDs, verified rollback, and one-shot Undo. It is **local-only test infrastructure**, not a `healthmd.shared_setup` document or a public wire field; its synthetic native/runtime sentinels are confined to the scenario envelope and are recursively proven absent from its embedded public source DTO and both canonical public v2 fixtures.

The contracts validator enforces the scenario end-to-end (selection normalization, exact Add/Replace states, rollback equality, Undo consumption, isolation scanning), and since cycle 3 both native suites drive their platform transaction directly against the frozen fixture bytes, as this record promised they would be cited:

- Apple: [`SharedSetupV2TransactionScenariosTests`](../../apps/apple/HealthMdTests/SharedSetup/SharedSetupV2TransactionScenariosTests.swift) — 6 tests, 0 failures on the cycle-4 rerun recorded in the amendment below (7 tests in the cycle-3 receipt, before the redundant alias-adjusted diagnostic mirror was removed).
- Android: [`SharedSetupV2TransactionScenariosTest`](../../apps/android/app/src/test/java/com/healthmd/sharedsetup/SharedSetupV2TransactionScenariosTest.kt) — 6/6 green in the cycle-3 integration receipt cited in the amendment below.

The suite-level evidence in the table above remains the per-behavior detail behind these conformance runs.

## Explicitly not claimed

- No physical-device, emulator, simulator-manual, share-channel, or accessibility QA. The v1 record's physical-device execution matrix remains the outstanding gate model; nothing here satisfies any row of it.
- No shipped-behavior claim for the v2 surface: the Apple apply/Undo adapter, all-profile v2 selection UI, rebind affordance, and Undo affordance, and the Android apply/undo callbacks, Apple-extension sidecar loader, and v2 selection/rebinding UI are **wired behind explicit, caller-supplied seams and host-side tested** (cycle-3 integration receipt plus this record's reruns). They remain **deferred** — not enabled in any default production path, no default-writer change — and **no physical-device behavior is claimed for them**.
- No default-writer change: v2 is not the default portable document writer on either platform.
- No status change: `healthmd.shared_setup` stays version 2 / `deferred`; no capability classification changes.

## Remaining gates before any enablement decision

1. Native transaction conformance suites against the frozen scenario fixture pass on both platforms — **satisfied since cycle 3**: Android `SharedSetupV2TransactionScenariosTest` 6/6 and Apple `SharedSetupV2TransactionScenariosTests` 6 tests / 0 failures (receipts in the amendment below).
2. Production apply/Undo wiring completes behind explicit seams on both platforms, still without flipping default writers — **satisfied since cycle 3**: the adapter, selection/rebind UI, callbacks, and sidecar loader landed host-side tested; default writers remain v1.
3. The full physical-device interoperability and accessibility matrix from the v1 record is executed for v2 multi-profile flows.
4. A deliberate, separately reviewed decision changes status, capability classification, or the default writer — never silently through integration work.

## Cycle-4 amendment (2026-09-05)

Reconciled from `shared-setup-v2/c4-docs-capability-ci` (worktree `/private/tmp/healthmd-c4-docs-capability-ci`, base `15ed228bc`). This section records the wired-but-deferred reconciliation and this cycle's receipts; the dated tables above are retained unchanged as history.

### Changes recorded by this cycle

1. **Redundant Apple diagnostic removed.** `SharedSetupV2TransactionScenariosTests.testDiagnosticFrozenScenarioExpectedStatesUnderAppleAdjustedAliasLedger` and its alias-adjusted `diagnosticScenarioDocument()` helper are deleted. The diagnostic existed only because Apple's alias-ledger decode was stricter than the shared contract; cycle 3 (`066f5e119`) made the decode contract-exact, so the unmodified frozen source document now decodes and the mirror became redundant. The six frozen-fixture scenario tests remain byte-driven and intact (7 tests before the removal, 6 after).
2. **Capability evidence refreshed.** `setup.share-portable-configuration` in `packages/contracts/product-capabilities.json` stays classification `planned` with both platforms `planned` — no availability bump. Its summary now records the wired host-side state (explicit caller-supplied seams, physical-device interoperability and accessibility QA outstanding) and its evidence list cites the v2 authorities on main: the v2 contract and schema, both profile field-coverage inventories, both platform transactions, the Apple execution gate and transaction adapter, both frozen scenario suites, and this record. The manifest sha256 pin was refreshed atomically with the inventory change, matching every prior precedent.
3. **Sanitizer-gate static-retention justifications.** The cycle-2/3 SharedSetup v2 Apple suites declared `static var retained` workarounds without the repository-standard `STATIC RETENTION JUSTIFICATION` comment, so the full `HealthMd-Tests-iOS` scheme failed `SanitizerGateTests.testNoUnexplainedStaticRetention` at base `15ed228bc` — the cycle-3 receipt ran a selected union that never executed that gate. Justification comments were added following the established pattern; comment-only, no behavior change.

### Cycle-4 receipts (host-side only)

| Gate | Result |
|---|---|
| `python3 packages/contracts/validate.py` | 15 contracts, 35 fixtures, 13 packaging mirrors, 2 inventories, 3 output profiles, 33 product capabilities, 55 local documentation links, exit 0 |
| `python3 -m unittest test_validate_shared_setup.py` (from `packages/contracts`) | 33 tests, OK |
| Full Apple `HealthMd-Tests-iOS` scheme on a dedicated iOS 26.5 simulator (unsigned, `CODE_SIGNING_ALLOWED=NO`) | Integrated-tree receipt at `15ed228bc`+cycle-4 (dedicated `c4int-iPhone17Pro` simulator, deleted after the run): **2277 tests executed: 2264 passed, 0 failed, 13 skipped — TEST SUCCEEDED**; includes the confirmation-flow suite (+10) and sidecar-compaction suite (+9) merged after this lane's intermediate 2258-test receipt. `SharedSetupV2TransactionScenariosTests` 6/6 against the frozen fixture after the diagnostic removal |
| Apple macOS test-target build (`HealthMd-Tests-macOS -configuration Debug`, unsigned `build-for-testing`) + generic unsigned iOS Simulator app build | Integrated-tree receipt: **BUILD SUCCEEDED** for both |
| Android JVM merged suite | Integrated-tree rerun after the confirmation-flow and l10n lanes landed: **373 tests across 47 classes (sharedsetup, data.settings, data.scheduler, automation, direct, presentation.export), 0 failures/errors/skipped, exit 0** — including `SharedSetupV2TransactionScenariosTest` 6/6, the new blocked-credential/Mac-pairing flows (+8 tests), and `SharedSetupSettingsTransactionTest` 4/4. The cycle-3 full-matrix receipt (337 tests) remains history at `/tmp/health-md-fleet-loop/cycle-3/integration-report.md` |

A first full-scheme Apple attempt on the shared booted `iPhone 17 Pro` simulator was discarded and is **not** a receipt: a sibling lane's concurrently installed test bundle (same bundle identifier) interleaved into that session's crash-restart phases, inflating the count to 2268 with foreign suites and producing signal-kill restarts. The receipt above was taken on a freshly created dedicated simulator with no other test session attached.

### CI path-gate survey (cycle 4)

Every shared-setup file added in cycles 2–3 (`git diff --name-only eae6feb97..15ed228bc`) is covered by at least one gate that validates it:

- `apps/android/**` (nine sharedsetup files, including the production transaction and both new suites) → `android-ci.yml` path `apps/android/**`; android-ci runs the JVM suite plus `packages/contracts/validate.py` and the shared-setup unittest.
- `apps/apple/**` (five SharedSetup files, including the transaction adapter and both suites) → `apple-ci.yml` has no path filter (every pull request and main push) and runs the iOS unit-test union via `make test-ios`.
- `packages/contracts/shared-setup/**` → the `packages/contracts/**` path entry in `android-ci`, `cli-ci`, `core-rust-ci`, and `website-ci`; android-ci, cli-ci, and core-rust-ci run `validate.py`, and android-ci additionally runs the shared-setup unittest.
- `docs/qa/shared-setup-v2.md` → deliberately not path-gated, matching `docs/qa/shared-setup-v1.md`: no CI step validates QA-record content (`validate.py`'s markdown-link pass scans only `packages/contracts/**/*.md`), and every pull request already runs all seven component workflows regardless of paths. Adding a path entry without a validating step would spend CI minutes without protecting anything, so no workflow was edited and the finding is recorded here instead.

### Still not claimed (unchanged)

No physical-device, emulator, simulator-manual, share-channel, or accessibility QA; no default-writer change; `healthmd.shared_setup` stays version 2 / `deferred`; capability classification stays `planned`.

## Cycle-5 localization amendment (2026-09-06)

Recorded from `shared-setup-v2/c5-android-v1-l10n` (worktree `/private/tmp/health-md-c5-l10n`, base `9cf250b73`). Android resource-string localization only; no Kotlin, Apple, contract, or English `values/strings.xml` change.

### Final localization coverage (all 15 non-English Android locales)

Every `shared_setup_*` key defined in `apps/android/app/src/main/res/values/strings.xml` at the base — 47 v1 keys (`shared_setup_*`) and 36 v2 keys (`shared_setup_v2_*`) — is translated in all 15 locale files (ar, b+pa+Guru, b+zh+Hans, bn, de, es, fr, hi, ja, kk, nl, pt-rBR, ro, ru, uk). This cycle backfilled the previously untranslated v1 block (0/47 in 13 locales, 10/47 in es/fr) and completed the 8 confirmation-flow v2 keys (`shared_setup_v2_rebind_api_*`, `shared_setup_v2_rebind_mac_*`, `shared_setup_v2_rebind_cloud_unavailable`) that were missing in every locale. The 8 v2 keys are exactly the set added to English by this cycle's sibling Android confirmation-flow lane; they were translated in this same pass, so **there is no pending next-l10n-pass set as of base `9cf250b73`** — coverage is complete. Terminology anchors were the cycle-4 v2 translations plus each file's established strings; per-key placeholder multisets (v1 `shared_setup_endpoint_no_auth` carries `%1$s`) match English exactly.

### Documented intentional identical-to-English values

The following render byte-identical to English because that is the natural, established term in that locale file (same rationale as the cycle-4 `shared_setup_v2_applied`/`_applied_count` note):

| Locale | Key | Value | Rationale |
|---|---|---|---|
| de | `shared_setup_v2_destination_cloud` | Cloud | Standard German term (file's own cycle-4 render) |
| nl | `shared_setup_v2_destination_cloud` | Cloud | Standard Dutch term (file's own cycle-4 render) |
| ro | `shared_setup_v2_destination_cloud` | Cloud | Standard Romanian term (file's own cycle-4 render) |
| fr | `shared_setup_v2_destination` | Destination | Identical French word (file's own cycle-4 render) |
| fr | `shared_setup_v2_destination_cloud` | Cloud | Standard French term (file's own cycle-4 render) |
| es | `shared_setup_endpoint` | Endpoint | Established es-file term (`api_export_section_endpoint`, v2 `Endpoint de API`) |
| nl | `shared_setup_endpoint` | Endpoint | Established nl-file term (`api_export_section_endpoint`, v2 `API-endpoint`) |
| pt-rBR | `shared_setup_endpoint` | Endpoint | Established pt-file term (`api_export_section_endpoint`, v2 `Endpoint da API`) |
| fr | `shared_setup_formats` | Formats | Identical French word (anchor `Formats par jour`) |

### Cycle-5 receipts (this lane)

| Gate | Result |
|---|---|
| `xmllint --noout` × 15 locale files | all "ok", exit 0 |
| Order/set/placeholder parity script (v1+v2 blocks, per key, vs English and vs base order) | `RESULT: ALL OK`, exit 0 |
| `cd apps/android && ./gradlew :app:processPlayDebugResources --offline --no-daemon --max-workers=2` (`ANDROID_HOME=$HOME/Library/Android/sdk`) | BUILD SUCCESSFUL in 40s, exit 0 |
| `git status --porcelain` | clean; only the 15 locale files changed before their commits, plus this file in its own commit |

### Cycle-5 integrated receipts (coordinator fleet-c5, integrated at `c395c1d96` → receipts below)

Lanes integrated serially via cherry-pick (8 lane commits, all patch-equivalent per `git cherry`), plus one integrator commit translating the cycle-5 endpoint-binding keys (`shared_setup_v2_rebind_api_url_*`, `shared_setup_v2_rebind_api_unretained`) into all 15 locales — closing the LocalizationContractTest gap this cycle's Android lane discovered as pre-existing at base `9cf250b73` (cycle-4's 8 EN-only keys; now repaired by the l10n lane + this commit: 42/42 v2 keys translated per locale).

| Gate | Result |
|---|---|
| Apple FULL `HealthMd-Tests-iOS` (`Debug-iOS`, dedicated fresh `c5int-iPhone17Pro` simulator, unsigned, isolated derived data) | Executed 2288 tests, 13 skipped, 0 failures — TEST SUCCEEDED (cycle-4: 2277; +11 in-flow endpoint-add/Mac-re-render tests) |
| Apple `HealthMd-Tests-macOS` build-for-testing (`Debug`, unsigned) | TEST BUILD SUCCEEDED |
| Apple generic iOS Simulator app build (`Debug-iOS`) | BUILD SUCCEEDED |
| Android FULL `:app:testPlayDebugUnitTest` (flavored, offline) | 1316 tests / 189 classes / 0 failures / 0 errors / 1 skipped; `LocalizationContractTest` 8/8 green |
| Android `:app:compilePlayDebugAndroidTestKotlin` | BUILD SUCCEEDED |
| Android `:app:processPlayDebugResources` | BUILD SUCCESSFUL (post-integrator-l10n re-run) |
| `python3 packages/contracts/validate.py` | 15 contracts, 35 fixtures, 13 packaging mirrors, 2 inventories, 3 output profiles, 33 capabilities, 55 doc links — exit 0 |
| `python3 packages/contracts/test_validate_shared_setup.py` | OK (33 tests) |
| Frozen bytes vs `9cf250b73` | `git diff -- packages/contracts/shared-setup/` = 0 lines; SHA-256 prefixes equal baselines (v1 contract `a7ab1e660fce`, v1 schema `0f2a9367b52d`, v1 fixtures `4101ba35c58e`/`817e30ce6c3e`, v2 fixtures `51c4151a040f`/`1072b48321ec`/`2f72266daa4a`); `HealthMetricsDictionary.swift` 0-diff |
| `git diff --check 9cf250b73..HEAD` | clean |

Known state after cycle 5: every English `shared_setup_*` and `shared_setup_v2_*` key (47 + 42) is translated in all 15 locales (with the 9 documented intentional identicals above); no known-untranslated shared-setup keys remain on Android.
