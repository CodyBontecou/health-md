# Share My Setup v2 transaction QA record

- Date: 2026-09-05
- Branch: `shared-setup-v2/c3-contract-manifest` (record written from the cycle-2 integrated tree at base `eae6feb97`)
- Worktree: `/private/tmp/healthmd-c3-contract-manifest`

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

Today the contracts validator enforces the scenario end-to-end (selection normalization, exact Add/Replace states, rollback equality, Undo consumption, isolation scanning). Native suites that drive both platform transactions directly against the frozen fixture bytes are staged for the current integration cycle; when they land and pass, this record will be updated to cite them per platform. Until then, native coverage is the suite-level evidence in the table above.

## Explicitly not claimed

- No physical-device, emulator, simulator-manual, share-channel, or accessibility QA. The v1 record's physical-device execution matrix remains the outstanding gate model; nothing here satisfies any row of it.
- No production wiring: the Apple apply/Undo adapter, all-profile v2 selection UI, rebind affordance, and Undo affordance, and the Android apply/undo callbacks, Apple-extension sidecar loader, and v2 selection/rebinding UI are integration work in flight and are **not** claimed as shipped behavior.
- No default-writer change: v2 is not the default portable document writer on either platform.
- No status change: `healthmd.shared_setup` stays version 2 / `deferred`; no capability classification changes.

## Remaining gates before any enablement decision

1. Native transaction conformance suites against the frozen scenario fixture pass on both platforms.
2. Production apply/Undo wiring completes behind explicit seams on both platforms, still without flipping default writers.
3. The full physical-device interoperability and accessibility matrix from the v1 record is executed for v2 multi-profile flows.
4. A deliberate, separately reviewed decision changes status, capability classification, or the default writer — never silently through integration work.
