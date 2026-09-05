# Share My Setup

## Status

- **Docs status:** needs QA (shipped in Settings on both platforms; contract is pre-canonical pending physical-device interoperability and accessibility QA — see [`packages/contracts/shared-setup/v2/contract.md`](../../../../packages/contracts/shared-setup/v2/contract.md); v2 has been the one and only profile contract since the 2026-09-05 sunset — [ADR-0006](../../../../docs/architecture/adr-0006-shared-setup-v2-only-contract.md))
- **Video priority:** medium
- **Primary screen:** Settings → Share My Setup (also offered on the onboarding Welcome page, and by opening a `.healthmdconfig` file from another app)
- **Source files:** `app/src/main/java/com/healthmd/sharedsetup/` — `SharedSetupScreen.kt`, `SharedSetupViewModel.kt`, `SharedSetupCoordinator.kt`, `SharedSetupDocumentStore.kt`, `SharedSetupService.kt`, `SharedSetupV2Codec.kt`, `SharedSetupV2Mapper.kt`, `SharedSetupV2ProfileTransaction.kt`, `SharedSetupV2ProductionTransaction.kt`

## What it does

Share My Setup packages your export profiles — metric selection, formats, naming/organization choices, and destination *intent* — into one bounded portable file you can hand to your other device (or a friend setting up Health.md). A v2 document can carry **multiple profiles**; the recipient reviews exactly what will change, applies it as a transactional **Add** or **Replace**, and can **Undo** once. The file deliberately contains **no health data, credentials, permissions, purchases, or folder access**.

## Who it is for

- Users moving between Android and iPhone (or two devices) who don't want to re-select metrics by hand.
- Anyone helping someone else replicate a known-good export configuration.

## Where to find it

1. Open Health.md → **Settings** tab and tap the **Share My Setup** card ("Review, import, save, or share a portable setup without health data or credentials.").
2. On first run, the onboarding Welcome page offers **Use a Shared Setup** instead of configuring by hand (see ./onboarding.md).
3. Opening a `.healthmdconfig` file from Files or another app routes into the same review flow. The app only accepts a document when the provider reports the exact Share My Setup media type or a display name ending in `.healthmdconfig` — a generic JSON document fails closed without reaching the decoder.

## Prerequisites

- No permissions needed — the document contains preferences only.
- Recipient device runs a Health.md version that supports `healthmd.shared_setup` v2 (post-sunset builds reject v1 files as an unsupported version).
- Android 9 / API 28 or newer (the app-wide floor).

## Setup

1. On the source device, open **Share My Setup** and either **Share My Setup** (Android Sharesheet) or **Save Setup File** (folder picker, suggested name `HealthMd-Shared-Setup.healthmdconfig`).
2. Send the file to the target device.
3. On the target, tap **Use a Shared Setup** to pick it from the document picker, or open the file with Health.md.
4. Review the multi-profile preview, choose the profiles to import and **Add** or **Replace**, then **Apply Shared Setup** — or **Undo** from the success screen to roll back.

## Example output

A bounded (≤ 4 MiB) JSON document, `healthmd.shared_setup` v2, media type `application/vnd.healthmd.configuration+json`, carrying one or more profiles — each listing selected metrics by registry alias, format toggles, and naming and organization preferences — with a preflight summary the recipient sees before anything is written. Writers emit v2 exclusively; a v1 file is rejected as an unsupported version.

## Tips

- Apply is a transactional Add or Replace: either every selected profile lands or none does; one-shot Undo restores the exact prior state, including blocked identities. A failed apply leaves your configuration untouched.
- Imported profiles land **blocked** until you rebind their destination locally — a concrete SAF folder, a verified API endpoint with a new credential, or an explicit Mac pairing attestation; cloud stays unsupported. Imported schedules stay off, and existing authorization is never inherited.
- Custom Markdown, frontmatter values, and the endpoint host/path are copied verbatim; review them for personal, tenant, routing, or secret text before sending.
- Files larger than 4 MiB or with an unsupported schema version — including v1 files — are rejected before anything is applied.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Shared Setup Couldn't Be Opened" — size rejection | Document exceeds the contract's 4 MiB bound | Regenerate on the source device with fewer selections or profiles |
| "Shared Setup Couldn't Be Opened" — unsupported version | Unsupported `schema_version` — v1 files are unsupported since the v2-only sunset | Update Health.md on both devices, then regenerate the file |
| "Shared Setup Couldn't Be Opened" — not a Health.md shared setup / not valid JSON | Wrong file type opened with Health.md | Use a file exported by Health.md's Share My Setup |
| Wrong preferences after apply | Imported profile was reviewed as-is | Use Undo immediately from the success screen, then re-review |

## Video outline

- **Suggested title:** Move Your Health.md Setup to a New Phone in One File
- **Hook:** "106 metric checkboxes. One file."
- **Demo flow:**
  1. Export on Android via the Sharesheet.
  2. Open on the other device.
  3. Review + Apply + Undo demo.
- **Key screenshot/recording moments:** review summary, apply confirmation, undo.
- **CTA / next video:** Metric selection (./metric-selection.md).

## Implementation notes

`SharedSetupScreen.kt` is the Compose UI with Idle/Review/Success/Error states, including the multi-select v2 review and the blocked/pending-rebind rows; `SharedSetupViewModel.kt` drives it, restores an in-flight review from `SavedStateHandle` across process death, and hosts the apply/Undo and trusted rebind hooks. `SharedSetupCoordinator.kt` retains external `ACTION_VIEW` imports at process scope so navigation can reveal the retained back-stack entry instead of replaying a warm intent into a hidden ViewModel. `SharedSetupV2Codec.kt` enforces the bounded read (4,194,304 bytes), the strict schema discriminator with **v2-only version dispatch** — `schema_version` 1 is rejected as unsupported exactly like any unknown version — generic JSON bounds, and a security scan; every failure fails closed as an `invalid` compatibility result with a bounded, non-secret message. `SharedSetupDocumentStore.kt` handles the document picker, create-document export, and Sharesheet artifacts through a private `FileProvider`; `SharedSetupV2Mapper.kt`/`SharedSetupCanonicalAliases.kt` translate metric selections through the shared registry alias ledger; `SharedSetupV2ProfileTransaction.kt`/`SharedSetupV2ProductionTransaction.kt` perform the atomic Add/Replace, blocked set, sidecar, and one-shot Undo with their pre-mutation bounds. The contract lives at [`packages/contracts/shared-setup/v2/`](../../../../packages/contracts/shared-setup/v2/) with a JSON Schema, per-platform field-coverage inventories, and the frozen transaction scenario fixture; it is **pre-canonical** until physical-device interoperability and accessibility QA complete, which is why this page's docs status is `needs QA`. Capabilities registry entry: `setup.share-portable-configuration` (`planned`).

Since the 2026-09-05 sunset decision ([ADR-0006](../../../../docs/architecture/adr-0006-shared-setup-v2-only-contract.md)), `healthmd.shared_setup` v2 is the one and only profile contract: default writers emit v2 exclusively on both platforms and v1 input fails closed as an unsupported version. Per the [v2 QA record](../../../../docs/qa/shared-setup-v2.md), the capability remains `deferred` / `planned` with the 24-row physical-device matrix still unexecuted — no enablement is claimed. Imported multi-profile setups land in the blocked/pending-destination set, and only a later explicit local rebind gate may clear the block.

Deliberate differences from Apple (see the Apple twin, [`apps/apple/docs/features/share-my-setup.md`](../../../apple/docs/features/share-my-setup.md)): Android shares through the Android Sharesheet and the Storage Access Framework document picker rather than AirDrop/Files, and opening a shared file from another app accepts only documents whose provider metadata identifies them as a `.healthmdconfig` file, failing closed otherwise.
