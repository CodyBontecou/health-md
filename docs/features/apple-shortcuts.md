# Apple Shortcuts

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** iOS Shortcuts app; Health.md Export/Schedule settings
- **Source files:** `HealthMd/iOS/AppIntents/*.swift`, `HealthMd/iOS/AppIntents/HealthMdAppShortcuts.swift`, `HealthMd/iOS/AppIntents/ExportIntentRunner.swift`

## What it does

Health.md exposes App Intents to Apple Shortcuts and Siri so users can export health data, backfill date ranges, retrieve structured health summaries, and toggle scheduled exports without opening the app.

Shortcuts are useful for personal automations like:

- export yesterday’s health data every morning;
- catch up the last 7 days after a trip;
- fetch yesterday’s sleep/steps/HRV and send them into another Shortcut;
- alert yourself if the last export failed;
- pause scheduled exports while traveling.

## Available actions

| Shortcut action | What it does | Parameters | Returns |
|---|---|---|---|
| **Export Yesterday** | Exports yesterday’s HealthKit data. | None | Dialog with success/failure summary |
| **Export Last N Days** | Exports the most recent complete days ending yesterday. | Number of days, 1–366 | Dialog with success/failure summary |
| **Export a Specific Day** | Exports one chosen date. | Date | Dialog with success/failure summary |
| **Export Date Range** | Exports every day from start to end, inclusive. | Start date, end date | Dialog; capped at 366 days |
| **Get Health Summary** | Reads headline metrics without writing files. | Date | Structured `Health Summary` entity |
| **Get Last Export Status** | Returns the most recent export result. | None | Structured `Last Export Status` entity or nil |
| **Set Scheduled Export** | Turns Health.md scheduled exports on or off. | Enabled boolean | Boolean + dialog |

## Siri phrases

Health.md registers a small set of high-traffic Siri phrases to avoid ambiguity:

- “Export yesterday’s health data with Health.md”
- “Run Health.md export”
- “Health.md export yesterday”
- “Export the last week of health data with Health.md”
- “Catch up Health.md export”
- “Get health summary from Health.md”
- “Health.md summary”

All actions are available in the Shortcuts app even if they do not have multiple Siri phrases.

## Prerequisites

- HealthKit permission granted in Health.md.
- A vault/folder selected for export actions.
- At least one export format selected.
- Free export quota remaining or Full Access unlocked.
- For scheduled-export toggling, Full Access is required when turning the schedule on.

## Setup: daily morning export

1. Open Apple **Shortcuts**.
2. Create a new personal automation.
3. Choose **Time of Day**, for example 8:00 AM.
4. Add the Health.md action **Export Yesterday**.
5. Turn off “Ask Before Running” if you want it fully automatic.
6. Save the automation.

This is the simplest Shortcuts equivalent of the Schedule tab.

## Setup: catch up the last N days

1. Open **Shortcuts**.
2. Add **Export Last N Days of Health Data**.
3. Set **Number of Days** to `7` or another value from 1–366.
4. Run the shortcut.
5. Health.md exports the selected lookback window ending yesterday.

## Setup: build a health summary shortcut

Use **Get Health Summary** when you want values inside Shortcuts rather than files in your vault.

Example automation:

1. Add **Get Health Summary**.
2. Set Date to **Yesterday**.
3. Use returned fields like:
   - Steps
   - Active Calories
   - Exercise Minutes
   - Walking + Running Distance
   - Sleep Hours
   - Resting Heart Rate
   - Average Heart Rate
   - HRV
   - Workouts
4. Pass those values into another action, such as a notification, message, note, or LLM prompt.

## Example health summary output

Shortcut dialog:

```text
8432 steps, 420 active kcal, 7h 30m sleep, 58 bpm resting HR, 1 workout.
```

Structured fields returned to Shortcuts:

```text
Date: 2026-05-12
Steps: 8432
Active Calories: 420
Exercise Minutes: 45
Sleep Hours: 7.5
Resting Heart Rate: 58
Average Heart Rate: 72
HRV: 52.3
Workouts: 1
```

## Export behavior

Export Shortcuts call the same export pipeline as the app:

- uses the current vault/folder;
- uses selected formats and metrics;
- respects filename/folder templates;
- respects write mode;
- records export history;
- counts against the free export quota when successful;
- updates schedule bookkeeping when yesterday is part of the run.

## Tips

- Use **Export Yesterday** for daily automations.
- Use **Export Last N Days** for “catch up” automations.
- Use **Get Health Summary** when another Shortcut needs values, not files.
- Use **Get Last Export Status** to notify yourself when an automation failed.
- Keep Health.md configured first; Shortcuts depend on the app’s saved settings.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Shortcut says no vault selected | Health.md has not saved folder access yet | Open Health.md and select a vault/folder. |
| Shortcut hits the paywall | Free export quota exhausted | Unlock Full Access in Health.md. |
| Scheduled export cannot be enabled | Scheduled exports require unlock | Unlock Full Access, then rerun the Shortcut. |
| Export Date Range refuses to run | Date range is over 366 days | Split the backfill into smaller ranges. |
| No health data returned | No HealthKit data for that date or permission missing | Check Apple Health and Health.md permissions. |
| Action appears but fails in Simulator | App Intents can be unreliable in simulator builds | Verify on a real iPhone before filming or shipping docs. |

## Video outline

- **Suggested title:** Run Health.md from Apple Shortcuts
- **Hook:** “You can export Apple Health to Obsidian without opening Health.md.”
- **Demo flow:**
  1. Show the Health.md actions inside Shortcuts.
  2. Build a one-tap **Export Yesterday** shortcut.
  3. Build a **Time of Day** automation for every morning.
  4. Run **Export Last N Days** for backfill.
  5. Use **Get Health Summary** and show the returned fields.
  6. Use **Get Last Export Status** to create a failure notification.
- **Key screenshot/recording moments:** Shortcuts action list, Export Last N Days parameter, Health Summary variables, successful export dialog.
- **CTA / next video:** “Next, we’ll use scheduled exports for a fully automatic Health.md workflow.”

## Implementation notes

- `HealthMdAppShortcuts` registers the App Shortcuts visible in the Shortcuts app.
- Export actions delegate to `ExportIntentRunner.run(dates:source:)`.
- `ExportIntentRunner` centralizes paywall checks, vault access, export orchestration, export history, free quota accounting, and schedule bookkeeping.
- `GetHealthSummaryForDateIntent` returns a `HealthSummary` AppEntity with typed properties.
- `GetLastExportStatusIntent` returns a `LastExportStatus` AppEntity from `ExportHistoryManager.shared.history.first`.
- `SetScheduledExportEnabledIntent` checks unlock status before enabling scheduled exports.
