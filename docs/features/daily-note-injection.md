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
- **Markdown** selected as an export format. Daily Note Injection is a Markdown side effect and does not run when only JSON/CSV/Bases are selected.
- The daily note must already exist unless **Create note if missing** is enabled.

## Setup

1. In **Export → Daily Note Injection**, turn on **Inject into Daily Notes**.
2. Set **Folder** to the daily-note folder relative to Health.md's export root, for example `Daily` or `Journal/Daily`.
3. Set **Filename** to match your daily note naming scheme. The default is `{date}`.
4. Decide whether to enable **Create note if missing**.
5. Optionally enable **Inject metric sections** if you want Health.md to add Markdown sections to the body, not just frontmatter.
6. Return to **Export**, choose a date, and tap **Export**.

## Path behavior

Health.md resolves the target daily note as:

```text
<selected vault>/<Health.md subfolder>/<Daily Note Injection folder>/<filename>.md
```

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
MyVault/Health/Daily/2026-05-12.md
```

If you want to inject directly into `MyVault/Daily/2026-05-12.md`, set the Health.md subfolder to empty or align your folder settings accordingly.

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

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Nothing was injected | Markdown export format is disabled | Enable **Markdown** in Export Formats. |
| Daily note not found | Folder or filename pattern does not match your Obsidian daily notes | Check the path preview and align folder/filename settings. |
| Health.md created a note in the wrong place | Health.md subfolder is included in the target path | Adjust the Health.md subfolder or Daily Note Injection folder. |
| A metric is missing | Metric disabled or no HealthKit sample exists for that date | Enable it in **Health Metrics** and verify Apple Health has data. |
| Existing writing disappeared | This should not happen; injection is designed to merge frontmatter/managed sections | Stop exporting and open a GitHub issue with before/after file examples. |

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
- Daily-note injection runs once per exported date and only when `.markdown` is included in `AdvancedExportSettings.exportFormats`.
