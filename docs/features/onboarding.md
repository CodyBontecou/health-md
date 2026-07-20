# Onboarding

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** First launch onboarding
- **Source files:** `HealthMd/iOS/Views/OnboardingView.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Onboarding walks new iPhone users through the minimum setup needed to export Apple Health data: understand the app, grant HealthKit access, preview the Markdown output, see the Obsidian plugin visualization layer, optionally choose an export folder, optionally unlock Full Access, and confirm the setup is ready. After onboarding, users can optionally enable a connected Mac as a local export destination.

The flow is intentionally short. Health access can be skipped because iOS only shows the Health permission prompt once per install; users can grant or adjust access later in Apple Health. Folder selection is also optional during onboarding so users can see the value and reach the unlock decision before leaving the flow for the Files picker.

## Who it is for

- First-time Health.md users.
- Obsidian users setting up their export folder for the first time.
- Users deciding between the free export allowance and Individual or Family Lifetime Full Access.

## Where to find it

Onboarding appears automatically on first launch. After onboarding, the same core settings are available in the app:

- **Export** → Health badge for HealthKit access.
- **Export** → Vault badge for folder selection.
- **Export** → Export settings for formats, metrics, filenames, folders, and the iPhone Folder / Connected Mac target selector.
- **Mac Destination** → enable the local Mac destination and check readiness.

## Prerequisites

- iPhone running Health.md.
- Health data in Apple Health for the metrics you want to export.
- Optional during onboarding: a destination folder, such as an Obsidian vault, iCloud Drive folder, or local “On My iPhone” folder.
- Optional: Health.md for Mac installed if you want to save iPhone-configured exports directly to a Mac folder.

## Setup

1. Open Health.md.
2. Review the welcome screen.
3. Tap **Grant Access** on the Health Data Access step, then choose which Apple Health categories Health.md may read.
4. Review the sample Markdown note so you know what Health.md will create.
5. Review the Obsidian plugin preview to see how exported fields can become in-vault visual dashboards.
6. Tap **Select Folder Now** to choose an Obsidian vault or tap **Choose Later** to finish onboarding first.
7. Choose an Individual or Family Lifetime unlock, or continue with the free export allowance.
8. Confirm the Ready screen and tap **Get Started**.
9. Optional: open **Mac Destination** to connect Health.md for Mac, choose a Mac folder, then select **Connected Mac** from the Export tab when exporting.

## Example setup result with a selected folder

```text
Health Data: Connected
Export Folder: MyVault
Default export path: MyVault/Health/2026-05-12.md
```

By default, Health.md saves exports inside a `Health` subfolder of the selected folder.

## Tips

- Pick your Obsidian vault itself if you want exported files to appear directly in Obsidian.
- Continue with free exports if you only want to test the workflow before unlocking.
- Choose your export folder later if you are not ready to leave onboarding for the Files picker.
- If you deny Health access, you can still finish onboarding, but exports will not produce data until permission is granted.
- You can change the iPhone export folder later from the **Export** tab.
- If you want exports written on Mac, configure everything on iPhone and use **Mac Destination** only to connect and check folder readiness.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export asks for a folder after onboarding | No export folder selected during onboarding | Tap the vault/folder badge in **Export** and choose a folder in Files. |
| Health access still says not connected | Permission was denied or no categories were enabled | Open Apple Health → profile → Apps → Health.md and enable read permissions. |
| Export folder is wrong | The selected folder bookmark points to the wrong location | Use the vault badge in **Export** to select the correct iPhone folder, or choose a destination folder on Mac for Connected Mac exports. |
| Purchase did not unlock | StoreKit purchase or restore failed | Try **Restore Purchase** or retry when signed into the App Store. |
| No data after setup | HealthKit permission or Apple Health samples are missing | Check Apple Health data and Health.md read permissions. |

## Video outline

- **Suggested title:** Set Up Health.md in 60 Seconds
- **Hook:** “Turn Apple Health into files you own.”
- **Demo flow:**
  1. Launch Health.md fresh.
  2. Show the welcome and privacy promise.
  3. Grant Health access.
  4. Show the sample Markdown note preview.
  5. Show the Obsidian plugin visualization preview with activity rings.
  6. Select an Obsidian vault folder, or choose later to demonstrate the optional path.
  7. Explain free exports vs Full Access.
  8. Land on the Export tab and show the path preview or folder prompt.
  9. Briefly show the optional Connected Mac target and explain that Mac setup happens after onboarding.
- **Key screenshot/recording moments:** progress bar, Health access step, sample Markdown preview, Obsidian plugin visualization, optional folder choice, Ready screen.
- **CTA / next video:** “Next, we’ll choose exactly which health metrics to export.”

## Implementation notes

- `OnboardingView` has seven steps: welcome, Health access, sample export preview, Obsidian plugin visualization, folder setup, unlock, and ready.
- Folder setup is optional; `canAdvance` does not require `vaultManager.vaultURL != nil`.
- Health access is not gated so users are not trapped after denying the one-time iOS permission prompt.
- The unlock step uses `PurchaseManager` and can be skipped with **Continue with 3 free exports**. It presents the same Individual and Family Lifetime StoreKit options as the main paywall.
- Existing unlocked users skip the unlock step automatically.
