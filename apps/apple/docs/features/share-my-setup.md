# Share My Setup

## Status

- **Docs status:** needs QA (shipped in Settings on both platforms; contract is pre-canonical pending physical-device interoperability and accessibility QA — see `packages/contracts/shared-setup/v1/contract.md`)
- **Video priority:** medium
- **Primary screen:** Settings → Configuration (Apple); Settings → Share My Setup (Android)
- **Source files:** `HealthMd/Shared/SharedSetup/`, `HealthMd/iOS/SharedSetup/SharedSetupCoordinator.swift`; Android `sharedsetup/` package

## What it does

Share My Setup packages your export preferences — metric selection, formats, naming/organization choices — into one small portable file you can hand to your other device (or a friend setting up Health.md). The recipient reviews exactly what will change and applies it in one transaction, with Undo. The file deliberately contains **no health data, credentials, device pairings, purchases, or runtime state**.

## Who it is for

- Users moving between iPhone and Android (or two devices) who don't want to re-select 100+ metrics by hand.
- Anyone helping someone else replicate a known-good export configuration.

## Where to find it

1. Open Health.md → **Settings** tab.
2. Under **Configuration**, use **Share My Setup** to export, review an incoming file, apply, or undo.
3. Share the file via Messages, AirDrop, or Files (Apple) or the Sharesheet/document picker (Android).

## Prerequisites

- No permissions needed — the profile contains preferences only.
- Recipient device runs a Health.md version that supports `healthmd.shared_setup` v1.

## Setup

1. Tap **Share My Setup** → export the profile file.
2. Send it to the target device.
3. On the target, open the file with Health.md (or import from the Configuration section).
4. Review the preview of what will change, then **Apply** — or **Undo** to roll back.

## Example output

A bounded (≤ 256 KiB) JSON document, `healthmd.shared_setup` v1, listing selected metrics by registry alias, format toggles, and organization preferences — with a preflight summary the recipient sees before anything is written.

## Tips

- Apply is transactional: either every preference lands or none does; Undo restores the prior state from a local snapshot.
- Files larger than 256 KiB or with an unknown schema version are rejected before anything is read.
- Re-exporting an applied profile emits only the allowlisted fields — imported junk never round-trips.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "File not supported" on import | Wrong file or newer schema version | Regenerate on the source device |
| Import rejected as oversized | Profile exceeds the 256 KiB bound | Reduce selected metrics and retry |
| Wrong preferences after apply | Imported profile was reviewed as-is | Use Undo immediately, then re-review |

## Video outline

- **Suggested title:** Move Your Health.md Setup to a New Phone in One File
- **Hook:** "225 metric checkboxes. One file."
- **Demo flow:** 1. Export on iPhone. 2. Send to Android. 3. Review + Apply + Undo demo.
- **Key screenshot/recording moments:** preview diff, apply confirmation, undo.
- **CTA / next video:** Metric selection.

## Implementation notes

`SharedSetupV1` defines the bounded envelope; `SharedSetupCoordinator` (Apple) drives export/review/apply/undo with a `FileDocument` (size-checked, codec-validated before accept). Android mirrors it (`SharedSetupScreen`, codec, document store, registry-backed alias mapping). The contract lives at `packages/contracts/shared-setup/v1/` with a JSON Schema, security checks (bounded read, allowlist write, recursive preflight), and cross-language fixtures; it is **pre-canonical** until physical-device interop and accessibility QA complete, which is why this page's docs status is `needs QA`. Capabilities registry entry: `setup.share-portable-configuration` (`planned`).
