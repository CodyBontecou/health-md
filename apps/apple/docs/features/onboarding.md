# Onboarding

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** First launch onboarding
- **Source files:** `HealthMd/iOS/Views/OnboardingView.swift`, `HealthMd/iOS/ContentView.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Onboarding walks new iPhone users through the minimum setup needed to export Apple Health data. The current flow has five non-blocking steps: welcome, Health access, sample output plus the optional Obsidian plugin link, folder setup, and ready. Health access and folder selection can both be skipped and repaired later.

The unlock paywall no longer occupies an onboarding step. After onboarding opens the first real export preview, an eligible locked user receives a one-time, dismissible offer after that preview closes. Separate soft prompts can appear after the 3rd and 7th completed free exports; the hard quota remains 10 successful export actions.

## Who it is for

- First-time Health.md users.
- Obsidian users choosing an export folder.
- Users importing a current Share My Setup file.
- Users evaluating the free allowance before Individual or Family Lifetime Full Access.

## Where to find it

Onboarding appears automatically on first launch. The same setup can later be changed through:

- **Export** → Health badge for HealthKit access.
- **Export** → Vault badge for folder selection.
- **Export** and **Settings** for formats, metrics, filenames, profiles, destinations, and schedules.
- **Sync → Mac Destination** for optional local Mac connectivity.

## Setup

1. Open Health.md and tap **Start Setup**, or choose **Use a Shared Setup**.
2. Connect Apple Health or explicitly choose **Skip for Now**.
3. Review sample Markdown/JSON/CSV/Bases output and the compact optional Obsidian plugin link.
4. Choose an Obsidian vault, iCloud Drive, another Files provider, or **Skip for Now**.
5. On Ready, repair a missing Health/folder connection if desired and tap **Create My First Export**.
6. Review and close the normal export preview. If eligible, the one-time post-onboarding Full Access offer appears after dismissal and can itself be dismissed.

## Example result

```text
Health Data: Connected
Export Folder: MyVault
Default export path: MyVault/Health/2026-05-12.md
Free export allowance: 10 successful actions
```

## Tips

- Pick the Obsidian vault itself if exported files should appear directly in Obsidian.
- Folder setup and Health access are recoverable; onboarding never traps a user after a denied permission or cancelled Files picker.
- The purchase offer is non-blocking. Dismissing it preserves the free allowance.
- Share My Setup transfers preferences only; the imported destination must still be rebound locally.
- Configure Connected Mac after onboarding if the files should be written on macOS.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export asks for a folder | Folder setup was skipped or access was revoked | Use the Export vault badge to choose the intended Files folder. |
| Health access is not connected | Permission was skipped, denied, or limited | Review Apple Health → Apps → Health.md and enable the intended reads. |
| A paywall appears after preview | One-time post-onboarding offer | Dismiss it to continue with free exports or choose a Lifetime option. |
| A reminder appears after the 3rd or 7th export | Non-blocking value-moment prompt | Dismiss it; remaining free exports are unchanged. |
| No data appears | Source data or permission is missing for the requested range | Check Apple Health, Health.md permission, and the date owner for overnight sleep. |

## Video outline

- **Suggested title:** Set Up Health.md in 60 Seconds
- **Hook:** “Turn Apple Health into files you own.”
- **Demo flow:** welcome → Health access → sample/plugin link → folder → ready → first preview → optional non-blocking offer.
- **Key captures:** five-step progress, Health permission, sample format picker, folder choice, Ready repair actions, first preview.
- **CTA:** Continue with a one-day verified export.

## Implementation notes

- `OnboardingStep` contains exactly five cases: `welcome`, `healthAccess`, `sampleExport`, `folder`, and `ready`.
- The Obsidian plugin promo is folded into `SampleExportStep`; it is not a separate gate.
- The unlock step was removed. `ContentView` and `iPadContentView` arm a one-time post-onboarding offer that fires after the first preview closes.
- Setup steps intentionally do not gate advancement. Health and folder skips remain coarse analytics events with no health values or paths.
- The Ready CTA raises the one-shot first-preview request consumed by the normal Export surface.
- `PurchaseManager.upgradePromptMilestones` contains 3 and 7; those prompts are distinct from the hard quota block at 10.
- Existing unlocked users do not receive the offer.
