# Export Profiles

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings → Export Profiles
- **Source files:** `app/src/main/java/com/healthmd/presentation/export/ExportProfilesScreen.kt`, `ExportProfilesViewModel.kt`, `data/scheduler/ScheduledProfileExportWorker.kt`

## What it does

Export profiles save complete export configurations — metrics, formats, output options, and their own destination — so you can switch between setups with one tap instead of reconfiguring. Each profile carries a stable ID you can pin in automation, its own optional schedule, and an overlap warning when two profiles would write the same files. One profile is always active, and the Export tab edits that active profile directly.

## Who it is for

- Users with distinct workflows (e.g. a lean nightly Markdown note vs. a weekly full JSON archive).
- Anyone automating specific exports by profile ID (Tasker/adb intents, see `../android-automation-intents.md`).
- Not for one-off exports; the Export tab already handles those (see ./manual-export.md).

## Where to find it

1. Open Health.md → **Settings** tab.
2. Tap the **Export Profiles** card.
3. Use **New** to create a profile from your current export settings, or manage existing ones from their rows.

## Prerequisites

- A destination in mind: each profile binds its own folder (via the Android folder picker) or API endpoint.
- Schedules on profiles require the lifetime unlock; profile management itself does not.

## Setup

1. Configure the Export tab the way you want the profile to start.
2. Settings → Export Profiles → **New**: name it, pick the target (folder or API endpoint), and save — it captures your current settings and becomes active.
3. Open a profile's row for details: destination, cadence summary, formats, metric count, and its profile ID.
4. From the row actions choose **Edit**, **Make Active & Edit**, **Schedule…**, **Rename**, **Duplicate**, or **Delete**.

## Example output

Two profiles: "Nightly Note" (Markdown-only, daily 07:00, writes `Vault/Health/`) and "Weekly Archive" (all formats, Sundays, own folder) — switching between them is one tap, and both can hold independent schedules.

## Tips

- The Export tab always edits the active profile; edits there flow back into it automatically.
- Copy the **profile ID** from the detail view to pin that exact profile in automation or API references — IDs stay stable across renames.
- If a profile shows "Overlapping exports", it writes the same files as another profile; keep destinations or filename layouts distinct to avoid one run clobbering another.
- New profiles start with their schedule disabled; open **Schedule…** to arm a cadence.
- The last remaining profile cannot be deleted — Health.md always needs one configuration.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Edits on the Export tab changed a profile | That profile is active | Activate a different profile first if you wanted a one-off tweak |
| "Overlapping exports" warning | Same destination and rendered paths as another profile | Change destination, subfolder, or filename layout |
| Schedule didn't fire at the exact time | WorkManager scheduling without exact-alarm access | Grant Alarms & reminders access, or accept the target-time behavior (see scheduling docs) |
| Automation can't find the profile | Using the name instead of the ID | Copy the stable ID from the profile detail |
| Duplicate looks identical | Duplication copies everything including destination | Edit the copy to change its destination or layout |

## Video outline

- **Suggested title:** Multiple Export Setups, One Tap to Switch
- **Hook:** "Nightly note. Weekly archive. Same app."
- **Demo flow:**
  1. Create a profile from current settings.
  2. Duplicate it, change formats and folder.
  3. Show the overlap warning after pointing both at the same folder, then fix it.
  4. Arm a schedule on one profile.
- **Key screenshot/recording moments:** New form, profile row actions, ID copy, overlap warning.
- **CTA / next video:** scheduled exports.

## Implementation notes

`ExportProfilesViewModel` is the authority: rows combine `ExportProfileRepository` profiles, the active ID, `ScheduledProfileEntryStore` schedule entries, and live folder/settings for `ExportProfileOverlapDetector` path-identity overlap detection (destination root + rendered paths). Activation applies a profile's frozen settings snapshot onto live settings through `ExportProfileCoordinator`; the Export tab edits the active profile and flushes back, while editing a non-active profile never touches live state. Creation seeds from the current live snapshot and activates (iOS parity); the full-field editor (`ExportProfileEditorDraft`) covers name, target, bound SAF folder URI or API endpoint URL, and the settings projection. Schedules: `ScheduledProfileEntry` (cadence value/unit with an anchor day), armed via `ScheduledProfileScheduler`; `ScheduledProfileExportWorker` executes each due occurrence under a unique WorkManager name `profile-export-<profileId>` (in-flight guard) with backoff retries and a post-run `reconcile()`; `BootReceiver` re-arms after reboot. Scheduled runs are premium-only and never consume free actions. Tested in `ExportProfilesViewModelTest.kt`. Deliberate difference from Apple: the management surface mirrors the iOS `ExportProfilesView`, but schedules run on WorkManager (with exact-alarm admission) rather than iOS notification scheduling.
