# Share My Setup

## Status

- **Docs status:** needs QA (shipped in Settings on both platforms; contract is pre-canonical pending physical-device interoperability and accessibility QA — see [`packages/contracts/shared-setup/v1/contract.md`](../../../../packages/contracts/shared-setup/v1/contract.md))
- **Video priority:** medium
- **Primary screen:** Settings → Share My Setup (also offered on the onboarding Welcome page, and by opening a `.healthmdconfig` file from another app)
- **Source files:** `app/src/main/java/com/healthmd/sharedsetup/` — `SharedSetupScreen.kt`, `SharedSetupViewModel.kt`, `SharedSetupService.kt`, `SharedSetupCoordinator.kt`, `SharedSetupCodec.kt`, `SharedSetupDocumentStore.kt`

## What it does

Share My Setup packages your export preferences — metric selection, formats, naming/organization choices — into one small portable file you can hand to your other device (or a friend setting up Health.md). The recipient reviews exactly what will change and applies it in one transaction, with Undo. The file deliberately contains **no health data, credentials, permissions, purchases, or folder access**.

## Who it is for

- Users moving between Android and iPhone (or two devices) who don't want to re-select metrics by hand.
- Anyone helping someone else replicate a known-good export configuration.

## Where to find it

1. Open Health.md → **Settings** tab and tap the **Share My Setup** card ("Review, import, save, or share a portable setup without health data or credentials.").
2. On first run, the onboarding Welcome page offers **Use a Shared Setup** instead of configuring by hand (see ./onboarding.md).
3. Opening a `.healthmdconfig` file from Files or another app routes into the same review flow. The app only accepts a document when the provider reports the exact Share My Setup media type or a display name ending in `.healthmdconfig` — a generic JSON document fails closed without reaching the decoder.

## Prerequisites

- No permissions needed — the profile contains preferences only.
- Recipient device runs a Health.md version that supports `healthmd.shared_setup` v1.
- Android 9 / API 28 or newer (the app-wide floor).

## Setup

1. On the source device, open **Share My Setup** and either **Share My Setup** (Android Sharesheet) or **Save Setup File** (folder picker, suggested name `HealthMd-Shared-Setup.healthmdconfig`).
2. Send the file to the target device.
3. On the target, tap **Use a Shared Setup** to pick it from the document picker, or open the file with Health.md.
4. Review the preview of what will change, then **Apply Shared Setup** — or **Undo** from the success screen to roll back.

## Example output

A bounded (≤ 256 KiB) JSON document, `healthmd.shared_setup` v1, media type `application/vnd.healthmd.configuration+json`, listing selected metrics by registry alias, format toggles, naming and organization preferences — with a preflight summary the recipient sees before anything is written.

## Tips

- Apply is transactional: either every preference lands or none does; Undo restores the prior state from a bounded local snapshot. A failed apply leaves your configuration untouched.
- Files larger than 256 KiB or with an unknown schema version are rejected before anything is applied.
- Custom Markdown, frontmatter values, and the endpoint host/path are copied verbatim; review them for personal, tenant, routing, or secret text before sending.
- An imported schedule never turns on by itself — the review shows "Will remain off" and activation is a separate local step.
- An imported API endpoint arrives without authentication: you confirm the endpoint locally with a new credential, and existing authorization is never inherited.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Shared Setup Couldn't Be Opened" — "Shared setup exceeds 256 KB." | Profile exceeds the contract's 256 KiB bound | Regenerate on the source device with fewer selections |
| "Shared Setup Couldn't Be Opened" — "This shared setup version is not supported." | Newer or unknown schema version | Update Health.md on both devices, then regenerate the file |
| "Shared Setup Couldn't Be Opened" — "This is not a Health.md shared setup." / "Shared setup is not valid JSON." | Wrong file type opened with Health.md | Use a file exported by Health.md's Share My Setup |
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

`SharedSetupScreen.kt` is the Compose UI with Idle/Review/Success/Error states; `SharedSetupViewModel.kt` drives it and restores an in-flight review from `SavedStateHandle` across process death. `SharedSetupCoordinator.kt` retains external `ACTION_VIEW` imports at process scope so navigation can reveal the retained back-stack entry instead of replaying a warm intent into a hidden ViewModel. `SharedSetupCodec.kt` enforces the bounded read (262,144 bytes), the strict schema discriminator and version check, generic JSON bounds, and a security scan — every failure fails closed as an `invalid` compatibility result with a bounded, non-secret message. `SharedSetupDocumentStore.kt` handles the document picker, create-document export, and Sharesheet artifacts through a private `FileProvider`; `SharedSetupMapper.kt`/`SharedSetupCanonicalAliases.kt` translate metric selections through the shared registry alias ledger. The contract lives at [`packages/contracts/shared-setup/v1/`](../../../../packages/contracts/shared-setup/v1/) with a JSON Schema, security checks (bounded read, allowlist write, recursive preflight), and cross-language fixtures; it is **pre-canonical** until physical-device interoperability and accessibility QA complete, which is why this page's docs status is `needs QA`. Capabilities registry entry: `setup.share-portable-configuration` (`planned`).

Share My Setup v2 import support exists wired-but-deferred: per [`docs/qa/shared-setup-v2.md`](../../../../docs/qa/shared-setup-v2.md), "`healthmd.shared_setup` remains **version 2, status `deferred`**" and "the **default portable document writer remains v1** on both platforms" — no enablement or default-writer change is claimed. Under the v2 contract, imported multi-profile setups land in the blocked/pending-destination set, and only a later explicit local rebind gate may clear the block.

Deliberate differences from Apple (see the Apple twin, [`apps/apple/docs/features/share-my-setup.md`](../../../apple/docs/features/share-my-setup.md)): Android shares through the Android Sharesheet and the Storage Access Framework document picker rather than AirDrop/Files, and opening a shared file from another app accepts only documents whose provider metadata identifies them as a `.healthmdconfig` file, failing closed otherwise.
