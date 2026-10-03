# Share My Setup

## Status

- **Docs status:** needs QA (shipped in Settings on both platforms; contract is pre-canonical pending physical-device interoperability and accessibility QA — see `packages/contracts/shared-setup/v2/contract.md`; v2 has been the one and only profile contract since the 2026-09-05 sunset — `docs/architecture/adr-0006-shared-setup-v2-only-contract.md`)
- **Video priority:** medium
- **Primary screen:** Settings → Configuration (Apple); Settings → Share My Setup (Android)
- **Source files:** `HealthMd/Shared/SharedSetup/`, `HealthMd/iOS/SharedSetup/SharedSetupCoordinator.swift`; Android `sharedsetup/` package

## What it does

Share My Setup packages your export profiles — metric selection, formats, naming/organization choices, and destination *intent* — into one bounded portable file you can hand to your other device (or a friend setting up Health.md). A v2 document can carry **multiple profiles**; the recipient reviews exactly what will change, applies it as a transactional **Add** or **Replace**, and can **Undo** once. The file deliberately contains **no health data, credentials, device pairings, purchases, or runtime state**.

## Who it is for

- Users moving between iPhone and Android (or two devices) who don't want to re-select 100+ metrics by hand.
- Anyone helping someone else replicate a known-good export configuration.

## Where to find it

1. Open Health.md → **Settings** tab.
2. Under **Configuration**, use **Share My Setup** to export, review an incoming file, apply, or undo.
3. Share the file via Messages, AirDrop, or Files (Apple) or the Sharesheet/document picker (Android).

## Prerequisites

- No permissions needed — the document contains preferences only.
- Recipient device runs a Health.md version that supports `healthmd.shared_setup` v2 (post-sunset builds reject v1 files as an unsupported version).

## Setup

1. Tap **Share My Setup** → export the setup file (a v2 document can carry several profiles).
2. Send it to the target device.
3. On the target, open the file with Health.md (or import from the Configuration section).
4. Review the multi-profile preview, choose the profiles to import and **Add** or **Replace**, then **Apply** — or **Undo** from the success screen to roll back.

## Example output

A bounded (≤ 4 MiB) JSON document, `healthmd.shared_setup` v2, carrying one or more profiles — each listing selected metrics by registry alias, format toggles, and organization preferences — with a preflight summary the recipient sees before anything is written. Writers emit v2 exclusively; a v1 file is rejected as an unsupported version.

## Tips

- Apply is a transactional Add or Replace: either every selected profile lands or none does; one-shot Undo restores the exact prior state, including blocked identities.
- Imported profiles land **blocked** until you rebind their destination locally (concrete folder, verified API endpoint, or confirmed Mac pairing); imported schedules stay off; endpoints arrive without credentials.
- Files larger than 4 MiB or with an unsupported schema version — including v1 files — are rejected before anything is read.
- Re-export is canonical: sorted compact JSON with exactly one trailing newline, only allowlisted fields, and foreign typed extensions preserved exactly per profile — imported junk never round-trips.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "File not supported" on import | Wrong file or unsupported schema version (v1 files are unsupported since the v2-only sunset) | Regenerate on the source device with a current Health.md |
| Import rejected as oversized | Document exceeds the 4 MiB bound | Reduce selected metrics or profiles and retry |
| Wrong preferences after apply | Imported profile was reviewed as-is | Use Undo immediately, then re-review |

## Video outline

- **Suggested title:** Move Your Health.md Setup to a New Phone in One File
- **Hook:** "225 metric checkboxes. One file."
- **Demo flow:** 1. Export on iPhone. 2. Send to Android. 3. Review + Apply + Undo demo.
- **Key screenshot/recording moments:** preview diff, apply confirmation, undo.
- **CTA / next video:** Metric selection.

## Implementation notes

`SharedSetupV2` defines the bounded v2 envelope, and `SharedSetupVersionedCodec`/`SharedSetupV2Codec` enforce the v2-only dispatch: reads accept at most 4,194,304 bytes, require `schema_version` 2, and reject any other version — including 1 — before review. `SharedSetupV2ProfileTransaction` performs the atomic Add/Replace with the blocked set, per-profile compatibility sidecar, and one-shot Undo persistence plus their pre-mutation 4 MiB/8 MiB bounds; `SharedSetupV2ExecutionGate` is the fail-closed gate with typed rebind confirmations, driven in production by `SharedSetupV2TransactionAdapter`; the iOS `SharedSetupCoordinator` presents the multi-profile review and success views with the rebind and Undo affordances. Android mirrors the surface (`SharedSetupScreen`, `SharedSetupV2Codec`, `SharedSetupV2ProfileTransaction`, and the production transaction). The contract lives at `packages/contracts/shared-setup/v2/` with a JSON Schema, per-platform field-coverage inventories, and the frozen transaction scenario fixture; it is **pre-canonical** until physical-device interop and accessibility QA complete, which is why this page's docs status is `needs QA`. v2 became the one and only profile contract through the 2026-09-05 sunset decision recorded in ADR-0006 (`docs/architecture/adr-0006-shared-setup-v2-only-contract.md`), with the QA records at `docs/qa/shared-setup-v2.md` and `docs/qa/shared-setup-v1.md`. Capabilities registry entry: `setup.share-portable-configuration` (`planned`).
