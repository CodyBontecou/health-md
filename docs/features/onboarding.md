# Onboarding

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** First launch onboarding
- **Source files:** `HealthMd/iOS/Views/OnboardingView.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Onboarding walks new iPhone users through the minimum setup needed to export Apple Health data: understand the app, grant HealthKit access, choose an export folder, optionally unlock Full Access, and confirm the setup is ready.

The flow is intentionally short. Health access can be skipped because iOS only shows the Health permission prompt once per install; users can grant or adjust access later in Apple Health.

## Who it is for

- First-time Health.md users.
- Obsidian users setting up their export folder for the first time.
- Users deciding between the free export allowance and the one-time Full Access unlock.

## Where to find it

Onboarding appears automatically on first launch. After onboarding, the same core settings are available in the app:

- **Export** → Health badge for HealthKit access.
- **Export** → Vault badge for folder selection.
- **Export** → Export settings for formats, metrics, filenames, and folders.

## Prerequisites

- iPhone running Health.md.
- Health data in Apple Health for the metrics you want to export.
- A destination folder, such as an Obsidian vault, iCloud Drive folder, or local “On My iPhone” folder.

## Setup

1. Open Health.md.
2. Review the welcome screen.
3. Tap **Grant Access** on the Health Data Access step, then choose which Apple Health categories Health.md may read.
4. Tap **Select Folder** and choose an Obsidian vault or another folder in Files.
5. Choose whether to **Unlock Full Access** or continue with the free export allowance.
6. Confirm the Ready screen and tap **Get Started**.

## Example setup result

```text
Health Data: Connected
Export Folder: MyVault
Default export path: MyVault/Health/2026-05-12.md
```

By default, Health.md saves exports inside a `Health` subfolder of the selected folder.

## Tips

- Pick your Obsidian vault itself if you want exported files to appear directly in Obsidian.
- Continue with free exports if you only want to test the workflow before unlocking.
- If you deny Health access, you can still finish onboarding, but exports will not produce data until permission is granted.
- You can change the export folder later from the **Export** tab.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Continue is disabled on folder setup | No export folder selected | Tap **Select Folder** and choose a folder in Files. |
| Health access still says not connected | Permission was denied or no categories were enabled | Open Apple Health → profile → Apps → Health.md and enable read permissions. |
| Export folder is wrong | The selected folder bookmark points to the wrong location | Use the vault badge in **Export** to select the correct folder. |
| Purchase did not unlock | StoreKit purchase or restore failed | Try **Restore Purchase** or retry when signed into the App Store. |
| No data after setup | HealthKit permission or Apple Health samples are missing | Check Apple Health data and Health.md read permissions. |

## Video outline

- **Suggested title:** Set Up Health.md in 60 Seconds
- **Hook:** “Turn Apple Health into files you own.”
- **Demo flow:**
  1. Launch Health.md fresh.
  2. Show the welcome and privacy promise.
  3. Grant Health access.
  4. Select an Obsidian vault folder.
  5. Explain free exports vs Full Access.
  6. Land on the Export tab and show the path preview.
- **Key screenshot/recording moments:** progress bar, Health access step, folder picker, Ready screen.
- **CTA / next video:** “Next, we’ll choose exactly which health metrics to export.”

## Implementation notes

- `OnboardingView` has five steps: welcome, Health access, folder setup, unlock, and ready.
- Folder setup is the only gated step; `canAdvance` requires `vaultManager.vaultURL != nil`.
- Health access is not gated so users are not trapped after denying the one-time iOS permission prompt.
- The unlock step uses `PurchaseManager` and can be skipped with **Continue with 3 free exports**.
- Existing unlocked users skip the unlock step automatically.
