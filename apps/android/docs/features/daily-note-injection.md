# Daily note injection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Settings
- **Source files:** `data/export/DailyNoteInjector.kt`, `domain/model/DailyNoteInjectionSettings.kt`, `presentation/settings/DailyNoteInjectionScreen.kt`

## What it does

Injects health metrics into the YAML frontmatter of your existing Obsidian daily notes. If a note for the day already exists, its frontmatter is refreshed in place; if it doesn't, Health.md can create one. Optionally, it also merges readable metric sections (Sleep, Activity, Heart, Vitals) into the note body — always preserving text you wrote yourself.

## Who it is for

- Daily-note journalers who want health properties available in every note without a separate export file.
- Dataview/Bases users querying daily notes directly.

## Where to find it

1. Open **Settings → Daily Note Injection**.
2. Toggle **Enable Injection**, set the folder and filename pattern.
3. Export; notes in your daily folder are updated (or created).

## Prerequisites

- Health Connect permission for the categories you want injected.
- Your daily-notes folder reachable from the export destination (injection paths are relative to it).
- Daily note injection enabled in Settings.

## Setup

1. Toggle **Enable Injection** ("Inject health data into daily notes").
2. **Daily Notes Folder:** relative to your export folder — for example `Daily` (default) or `Journal/Daily`.
3. **Filename Pattern:** default `{date}`; any [filename template](./filename-templates.md) placeholder works.
4. Toggle **Inject metric sections** if you also want Markdown sections merged into the body.
5. Export a day and check the note.

## Example output

`Daily/2026-05-12.md` after injection into your existing note:

```markdown
---
date: 2026-05-12
steps: 8432
sleep_total_hours: 7.2
---

# My day

Great weather, long walk at lunch.   ← your text, untouched

## Sleep                             ← injected section (if enabled)

- Total Sleep: 7.2 hours
```

## Tips

- Frontmatter keys follow your [frontmatter customization](./frontmatter-customization.md) settings — renames apply here too.
- When no note exists, one is created with a `# <date>` heading (matching long-standing Android behavior); the injector reports whether each note was updated, created, or skipped.
- Injected sections use the standard template style so notes stay readable; your own sections and preamble are preserved by the same merge rules as [Update mode](./write-modes.md).
- Days with no health data for any selected metric are skipped entirely — no empty notes.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Nothing was injected | Injection disabled, or no data for selected metrics | Check the toggle and metric selection, then re-export |
| Note not found | Folder path or filename pattern doesn't match your vault layout | Set **Daily Notes Folder** relative to the export destination and verify the pattern |
| Frontmatter duplicated | The note has two `---` blocks or malformed YAML | Fix the note's frontmatter; merging expects one block |
| Health sections landed in the wrong place | Merge replaces app-managed sections and appends new ones | Rename any custom sections that collide with managed headings (Sleep, Activity, Heart, Vitals) |

## Video outline

- **Suggested title:** Append Health Data to Your Daily Note
- **Hook:** "Your journal. Your metrics. One file."
- **Demo flow:**
  1. Show an existing daily note with your own text.
  2. Enable injection with frontmatter + sections.
  3. Export and show the merged note.
- **Key screenshot/recording moments:** settings screen, note before/after.
- **CTA / next video:** [Write modes](./write-modes.md).

## Implementation notes

`DailyNoteInjector.inject` builds injection content (frontmatter via `HealthDataFields` + `FrontmatterConfiguration`, optional Markdown sections rendered with the STANDARD template, `includeMetadata=false`) and merges it into the existing note with `MarkdownMerger`, returning `UPDATED`, `CREATED`, or `SKIPPED`. `DailyNoteInjectionSettings` carries `enabled`, `folderPath` (default `Daily`), `filenamePattern` (default `{date}`), `createIfMissing` (default true for backward compatibility with saved settings), and `injectMarkdownSections`. `resolvedPath(date)` applies filename placeholders and appends `.md`. Metric inclusion follows the export metric selection before the injector sees data.
