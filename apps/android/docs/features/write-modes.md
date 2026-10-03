# Write modes

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `domain/model/ExportFormat.kt`, `data/export/MarkdownMerger.kt`, `presentation/export/ExportConfigurationSection.kt`

## What it does

Chooses what happens when an exported file already exists at the destination: **Overwrite** replaces it, **Append** adds the new data to the end, or **Update** refreshes Health.md's own sections while preserving everything you wrote yourself.

## Who it is for

- **Update** — Obsidian users whose daily notes are partly hand-written; Health.md refreshes its sections and leaves your prose untouched.
- **Overwrite** — anyone who wants exports to be a pure function of Health Connect data.
- **Append** — users building a running log inside one file.

## Where to find it

1. Open the **Export** tab.
2. In the **Write Mode** section, choose **Overwrite**, **Append**, or **Update**.

## Prerequisites

- Health Connect permission for the categories being exported.
- A folder selected through the Android folder picker.

## Setup

1. Pick a write mode in the export configuration.
2. Export a day that already has a file at the destination.
3. For **Update**, open the note and confirm your own text survived.

## Example output

With **Update**, re-exporting a day whose note you edited:

```markdown
---
date: 2026-05-12
steps: 8432          ← refreshed by Health.md
---

# My morning reflection      ← your heading, untouched

Felt great after the run.    ← your text, untouched

## Sleep                     ← app-managed section, replaced

- Total Sleep: 7.2 hours     ← refreshed values
```

## How Update merges

- **Frontmatter:** app-written keys are refreshed with new values; your custom keys stay.
- **Sections:** Health.md's managed headings (Health Data, Sleep, Activity, Heart, Vitals, Body, Nutrition, Mobility, Reproductive Health, Mindfulness, Workouts) are replaced with fresh content; any other section you added is kept exactly as-is.
- **Text above the first heading** (your preamble) is preserved.

## Tips

- **Update is Markdown-specific** — it relies on headings and frontmatter, so it applies to Markdown (and daily-note injection), not to JSON or CSV. Those formats write whole files.
- Combine **Update** with [daily note injection](./daily-note-injection.md) to keep a single hand-curated note per day.
- If a heading you wrote happens to match a managed name exactly (for example `## Sleep`), Update will treat it as app-managed and refresh it — rename your custom sections if you want them left alone.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| My sections were replaced | Their headings match managed names like `Sleep` or `Heart` | Rename custom sections to distinct headings |
| Append produced duplicated metrics | The same day was appended twice | Use **Overwrite** or **Update** for re-exports |
| JSON/CSV files never merge | Update is Markdown-only | Expected — structured formats are rewritten whole |

## Video outline

- **Suggested title:** Re-export Without Destroying Your Notes
- **Hook:** "Health.md refreshes its half. Your half stays yours."
- **Demo flow:**
  1. Export a day, then edit the note in Obsidian.
  2. Re-export with **Update**.
  3. Show the custom text intact and metrics refreshed.
- **Key screenshot/recording moments:** before/after diff of the note, managed-heading highlight.
- **CTA / next video:** [Daily note injection](./daily-note-injection.md).

## Implementation notes

`WriteMode` enum: `OVERWRITE`, `APPEND`, `UPDATE`. `MarkdownMerger.merge` splits frontmatter and body, merges frontmatter key-by-key (new values win), preserves the preamble, and replaces only sections whose normalized heading matches the managed set (`APP_MANAGED_HEADINGS`), appending any new managed sections at the end. Heading normalization lowercases and strips Markdown decoration before matching. Update semantics are intentionally Markdown-specific per the merger's contract; JSON/CSV exporters always write complete files.
