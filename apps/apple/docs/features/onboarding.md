# Onboarding

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** First launch onboarding
- **Source files:** `HealthMd/iOS/Views/OnboardingView.swift`, `HealthMd/iOS/ContentView.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Onboarding walks new iPhone users through the minimum setup needed to export Apple Health data. The current flow has five non-blocking steps: welcome, Health access, sample output plus the optional Obsidian plugin link, folder setup, and ready. Health access and folder selection can both be skipped and repaired later.

A root hard paywall now precedes setup/tracking for unpaid users. Choose Individual or native Apple Family Sharing weekly/yearly/Lifetime access, or restore an existing purchase. Eligible subscriptions include a seven-day store-backed trial; Lifetime is charged immediately. Existing paid and previously grandfathered owners retain access. There is no local free-export allowance or first/third-export upsell. See the [paid-access rollout](../experiments/subscription-pricing-rollout.md) for prices, product IDs, and release prerequisites.

## Who it is for

- First-time Health.md users.
- Obsidian users choosing an export folder.
- Users importing a current Share My Setup file.
- Users starting a store-backed trial or setting up existing paid access.

## Where to find it

Onboarding appears automatically on first launch. The same setup can later be changed through:

- **Export** → Health badge for HealthKit access.
- **Export** → Vault badge for folder selection.
- **Export** and **Settings** for formats, metrics, filenames, profiles, destinations, and schedules.
- **Sync → Mac Destination** for optional local Mac connectivity.

## Setup

1. Open Health.md, choose a paid plan/trial or restore existing access, then tap **Start Setup** or **Use a Shared Setup**.
2. Connect Apple Health or explicitly choose **Skip for Now**.
3. Review sample Markdown/JSON/CSV/Bases output and the compact optional Obsidian plugin link.
4. Choose an Obsidian vault, iCloud Drive, another Files provider, or **Skip for Now**.
5. On Ready, repair a missing Health/folder connection if desired and tap **Create My First Export**.
6. Review and close the normal export preview, then export using your active access.

## Example result

```text
Health Data: Connected
Export Folder: MyVault
Default export path: MyVault/Health/2026-05-12.md
Access: Active trial, subscription, or Lifetime
```

## Tips

- Pick the Obsidian vault itself if exported files should appear directly in Obsidian.
- Folder setup and Health access are recoverable; onboarding never traps a user after a denied permission or cancelled Files picker.
- Setup permissions can be skipped, but unpaid users cannot dismiss the root purchase gate to begin tracking. Restore remains available.
- Share My Setup transfers preferences only; the imported destination must still be rebound locally.
- Configure Connected Mac after onboarding if the files should be written on macOS.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export asks for a folder | Folder setup was skipped or access was revoked | Use the Export vault badge to choose the intended Files folder. |
| Health access is not connected | Permission was skipped, denied, or limited | Review Apple Health → Apps → Health.md and enable the intended reads. |
| A paywall appears on launch | No active access was found | Choose a plan or restore purchases using the purchasing Apple ID. |
| Access ends after a trial | Trial/subscription expired | Manage the subscription or choose Lifetime; existing exported files remain yours. |
| No data appears | Source data or permission is missing for the requested range | Check Apple Health, Health.md permission, and the date owner for overnight sleep. |

## Video outline

- **Suggested title:** Set Up Health.md in 60 Seconds
- **Hook:** “Turn Apple Health into files you own.”
- **Demo flow:** purchase/restore → welcome → Health access → sample/plugin link → folder → ready → first preview.
- **Key captures:** five-step progress, Health permission, sample format picker, folder choice, Ready repair actions, first preview.
- **CTA:** Continue with a one-day verified export.

## Implementation notes

- `OnboardingStep` contains exactly five cases: `welcome`, `healthAccess`, `sampleExport`, `folder`, and `ready`.
- The Obsidian plugin promo is folded into `SampleExportStep`; it is not a separate gate.
- `PurchaseAccessGate` in the app root gates both iPhone and iPad content; existing paid access skips the paywall. Historical post-preview code does not trigger for unlocked users.
- Setup steps intentionally do not gate advancement. Health and folder skips remain coarse analytics events with no health values or paths.
- The Ready CTA raises the one-shot first-preview request consumed by the normal Export surface.
- `PurchaseManager.freeExportLimit` is zero and `upgradePromptMilestones` is empty. Trial eligibility and duration come from StoreKit.
- Existing unlocked users do not receive the root purchase offer. Store product setup and device/sandbox qualification are separate from source implementation.
