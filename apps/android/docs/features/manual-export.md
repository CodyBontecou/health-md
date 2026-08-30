# Manual Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `app/src/main/java/com/healthmd/presentation/export/ExportScreen.kt`, `ExportViewModel.kt`, `domain/billing/FreemiumPolicy.kt`, `domain/export/ExportAccountingPolicy.kt`

## What it does

Manual export writes your Health Connect data for a chosen date range to the selected destination in one tap. Pick a range (Today, Yesterday, All Time, or custom start/end dates), choose folder or API endpoint as the target, toggle formats and output options, preview if you like, and tap **Export**. The free plan includes 10 export actions; each successful user-triggered export consumes exactly one action no matter how many days or files it writes.

## Who it is for

- Anyone building a daily or periodic health journal on demand.
- Obsidian users appending health sections to daily notes (see ./export-preview.md for inspect-before-write).
- Not for unattended recurring runs: use schedules or export profiles for that (see ./export-profiles.md).

## Where to find it

1. Open Health.md → **Export** tab.
2. Under **Date Range**, pick Today / Yesterday / All Time, or set custom start and end dates.
3. Under the target selector, keep the folder destination or switch to the API endpoint.
4. Configure formats and output options in the export configuration section.
5. Tap **Preview** to inspect files (optional), then **Export**.

## Prerequisites

- Health Connect read permission for the categories you export (see ./health-connect-permissions.md).
- A folder selected (see ./folder-destination.md) or a configured API endpoint.
- At least one export format enabled; the button is disabled with "Select at least one export format to continue." until then.
- A remaining free action or the lifetime unlock.

## Setup

1. Choose your date range.
2. Enable Markdown, Obsidian Bases, JSON, and/or CSV.
3. Adjust filename format, subfolder, folder organization, metadata, grouping, emoji headers, and units as needed.
4. Tap **Export** and watch the progress dialog; when it finishes, use **Open folder**, **Open with Files**, or **Open with Obsidian** to jump to the result.

## Example output

One export action for a three-day range with Markdown + JSON enabled writes six files (two formats × three days) and consumes one free action.

## Tips

- Free actions count exports, not files — batching days and formats in one run conserves your quota.
- All Time uses the earliest data Health Connect will give you; very old data may need the History permission.
- After a successful export you may be offered a Google Play review prompt — it is optional and appears only after clean full successes.
- Failed exports don't consume an action: only a run with at least one success counts.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Select at least one export format" | No formats toggled on | Enable one or more formats |
| Export button shows Unlock | Free actions exhausted | Unlock lifetime, or review whether you can batch ranges |
| No data in output | Permission missing, empty range, or no source app data | Check permissions; try a range you know has data |
| File write failure | Destination lost write access | Re-select the folder (./folder-destination.md) |
| Export stopped for device lock / rate limit / network | Health Connect or endpoint throttling | Retry from the failure guidance shown on screen |

## Video outline

- **Suggested title:** Your First Health Connect → Markdown Export
- **Hook:** "Pick days, pick formats, one button."
- **Demo flow:**
  1. Export tab, pick Yesterday.
  2. Toggle Markdown + Obsidian Bases.
  3. Preview quickly, then Export and open in Obsidian.
- **Key screenshot/recording moments:** date options, format toggles, progress dialog, Open with Obsidian.
- **CTA / next video:** ./export-preview.md.

## Implementation notes

`ExportScreen.kt` composes the date-range section (`DateRangeOption.Today/Yesterday/AllTime/Custom` with date pickers), the target selector (folder vs API endpoint), and `ExportConfigurationSection` (formats, write mode, filename format, subfolder, folder organization/structure, metadata, group-by-category, emoji, unit preference, and the compatibility/raw-snapshot export-mode switch — the raw snapshot product is documented separately in `../export-contract/raw-snapshot-v1.md`). Free accounting lives in `FreemiumPolicy` (limit 10; legacy installs before 2026-04-26 migrate from the old 3-action limit; unlocking resets usage) and `ExportAccountingPolicy` (one action per successful user-triggered export with `successCount > 0`; scheduled background exports are premium-only and never consume free actions; full successes qualify for the review prompt). Failure surfaces use the `export_failure_*`/`export_guidance_*` string families with per-cause labels. Configuration edits run through `attemptConfigurationChange`, which respects the "Prevent Accidental Changes" lock. Deliberate difference from Apple: the free limit counts the same way, but Android's destination set is SAF folders + API endpoint (no Mac sync target).
