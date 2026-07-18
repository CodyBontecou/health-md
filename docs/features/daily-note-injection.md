# Daily Note Injection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Daily Note Injection
- **Source files:** `HealthMd/iOS/Views/DailyNoteInjectionView.swift`, `HealthMd/Shared/Export/DailyNoteInjector.swift`, `HealthMd/Shared/Models/DailyNoteInjectionSettings.swift`

## What it does

Daily Note Injection merges selected Apple Health metrics into an existing Obsidian daily note instead of creating only a separate health-data file. By default it writes YAML frontmatter properties and leaves the note body untouched. Optionally, it can also inject Health.md-managed Markdown sections like Sleep, Activity, Heart, and Workouts into the body.

This is the headline Obsidian workflow: your daily note becomes the single place where journaling, habits, and Apple Health metrics live together.

## Who it is for

- Obsidian users who already write daily notes.
- Users who want health metrics queryable as daily-note properties.
- Users who want to preserve their own daily-note template while adding health data automatically.

Do not use this if you want Health.md to create a completely separate health file per day; use normal Markdown export for that.

## Where to find it

1. Open Health.md on iPhone.
2. Go to **Export**.
3. Tap **Daily Note Injection**.
4. Enable **Inject into Daily Notes**.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected in Health.md.
- At least one export format selected, unless **Daily Notes Only** is enabled. Daily Note Injection runs during Manual Export, scheduled/background export, Shortcuts, Mac-local export, and Connected Mac export.
- The daily note must already exist unless **Create note if missing** is enabled.

## Setup

1. In **Export → Daily Note Injection**, turn on **Inject into Daily Notes**.
2. Set **Folder** to the daily-note folder relative to the selected vault/root destination, for example `Daily` or `Journal/Daily`.
3. Set **Filename** to match your daily note naming scheme. The default is `{date}`.
4. Decide whether to enable **Create note if missing**.
5. Turn on **Daily Notes Only** if the daily note should be the sole destination output. Health.md preserves your other output settings but skips aggregate formats, ZIP archives, roll-ups, individual entries, provider sidecars, and the data dictionary.
6. Optionally enable **Inject metric sections** if you want Health.md to add Markdown sections to the body, not just frontmatter.
7. Return to **Export**, choose a date, and tap **Export**.

## Path behavior

Health.md resolves the target daily note as:

```text
<selected vault>/<Daily Note Injection folder>/<filename>.md
```

The Health.md export subfolder is not included in this path. This lets you keep generated aggregate exports in `Health/` while injecting into existing daily notes in `Daily/`.

Example settings:

| Setting | Value |
|---|---|
| Selected vault | `MyVault` |
| Health.md subfolder | `Health` |
| Daily Note Injection folder | `Daily` |
| Filename | `{date}` |
| Export date | `2026-05-12` |

Target note:

```text
MyVault/Daily/2026-05-12.md
```

With **Daily Notes Only** off, the normal aggregate Markdown export for the same settings also goes to:

```text
MyVault/Health/2026-05-12.md
```

With **Daily Notes Only** on, that aggregate file and the Health.md data dictionary are not created.

## Daily Notes Only

Daily Notes Only is an explicit file-destination mode. It applies to local iPhone/iPad folders, Mac-local exports, Connected Mac exports, schedules, and Shortcuts. It is unavailable for API Endpoint exports because an HTTP endpoint has no vault filesystem where Health.md can resolve a daily note.

While active:

- selected aggregate formats and related preferences remain saved but inactive;
- lossless source-record capture is skipped because injection uses daily summaries;
- ZIP archives, roll-ups, individual-entry files, connected-provider sidecars, and `_healthmd_data_dictionary.json` are not written;
- a missing note is created only when **Create note if missing** is on;
- a missing note with creation off is reported as a completed skip and is not queued for retry, while an actual read/write error remains retryable;
- Connected Mac requires both devices to advertise Daily Notes Only support, preventing an older Mac from silently writing normal files.

## Supported filename placeholders

- `{date}` → `2026-05-12`
- `{year}` → `2026`
- `{month}` → `05`
- `{day}` → `12`
- `{weekday}` → `Tuesday`
- `{monthName}` → `May`
- `{quarter}` → `Q2`

## Example output

Existing note before export:

```markdown
---
mood: focused
---

# 2026-05-12

## Journal

Today I worked on Health.md docs.
```

After frontmatter-only injection:

```markdown
---
mood: focused
steps: 8432
active_calories: 420
sleep_total_hours: 7.50
resting_heart_rate: 58
hrv_ms: 52.3
---

# 2026-05-12

## Journal

Today I worked on Health.md docs.
```

If **Inject metric sections** is enabled, Health.md also merges app-managed sections into the body while preserving user-written sections.

## How metric selection works

The injected metrics are the same metrics enabled under **Export → Health Metrics**. There is no separate metric picker for daily notes. If a field does not appear in the daily note, first confirm the metric is enabled in Health Metrics and that Apple Health has data for that date.

Frontmatter key names respect **Format Customization → Frontmatter Fields**, so custom field names and snake_case/camelCase choices carry into daily note injection.

## Tips

- Use frontmatter-only injection if you want clean Obsidian Bases views.
- Use **Inject metric sections** if you want a readable health summary inside the note body.
- Leave **Create note if missing** off if another plugin or template system owns daily-note creation.
- Turn **Create note if missing** on if you want Health.md to backfill historical daily notes.
- Turn **Daily Notes Only** on when the Obsidian daily note should be the only user-visible output.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Nothing was injected | Daily Note Injection is disabled, no output mode is configured, or no selected metric has data | Enable Daily Note Injection, select a format or turn on Daily Notes Only, and verify metric data exists. |
| Daily note not found | Folder or filename pattern does not match your Obsidian daily notes | Check the path preview and align folder/filename settings. |
| Health.md created a note in the wrong place | Daily Note Injection folder or filename pattern does not match your vault's daily-note setup | Daily Note Injection folder is vault/root-relative; include only the daily-note folder path you want, such as `Daily`. |
| A metric is missing | Metric disabled or no HealthKit sample exists for that date | Enable it in **Health Metrics** and verify Apple Health has data. |
| Existing writing disappeared | This should not happen; injection is designed to merge frontmatter/managed sections | Stop exporting and open a GitHub issue with before/after file examples. |
| Export reports a Daily Note Injection conflict | The aggregate export path and daily note target are the same `.md` file | Change Output folder/filename or Daily Note Injection folder/filename. Health.md blocks the aggregate write so the daily note is not overwritten. |

## Video outline

- **Suggested title:** Append Apple Health to Your Obsidian Daily Note
- **Hook:** “What if your Obsidian daily note automatically included your sleep, steps, HRV, and workouts?”
- **Demo flow:**
  1. Show an existing Obsidian daily note with journal text but no health metrics.
  2. Open Health.md → Export → Daily Note Injection.
  3. Enable injection, set folder/filename, and show the path preview.
  4. Export yesterday's data.
  5. Return to Obsidian and show frontmatter filled in while the note body is preserved.
  6. Optional: enable metric sections and show the body merge.
- **Key screenshot/recording moments:** path preview, frontmatter preview, before/after Obsidian daily note.
- **CTA / next video:** “Next, we’ll turn these same properties into an Obsidian Bases dashboard.”

## Implementation notes

- `DailyNoteInjector.inject(...)` returns `.updated`, `.skipped`, or `.failed`.
- Missing daily notes are skipped unless `createIfMissing` is true.
- Frontmatter merging uses `MarkdownMerger.mergeFrontmatter`.
- Body section merging uses `MarkdownMerger.mergePreservingPreamble` when `injectMarkdownSections` is enabled.
- Daily-note injection runs once per requested date when enabled. Daily Notes Only is valid without a selected aggregate format.
- Daily Notes Only suppresses every other destination writer and reports note update/skip counts separately from generated-file counts.
- Collision protection blocks aggregate Markdown or Obsidian Bases writes when their target path is the same file as the daily note injection target. No collision check is needed in Daily Notes Only mode because aggregate targets are inactive.
