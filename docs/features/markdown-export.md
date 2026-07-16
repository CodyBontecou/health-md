# Markdown Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Export Formats; Export → Format Customization → Markdown Template
- **Source files:** `HealthMd/Shared/Export/MarkdownExporter.swift`, `HealthMd/Shared/Export/ExportHelpers.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Markdown export writes one readable `.md` health note per date. It keeps the familiar Sleep, Activity, Heart, Vitals, Body, Nutrition, Mindfulness, Mobility, Hearing, Workouts, and Medication summaries.

When **Lossless Health Records** is on, Markdown remains intentionally compact. With **Include Metadata** on (the default), it adds frontmatter diagnostics; the body adds a **Lossless Health Records** section with capture status, source/external record counts, query counts, medication inventory count, warnings, and concise failures. Turning **Include Metadata** off removes the entire frontmatter block, including schema, time context, units, and raw-capture keys, but does not remove the readable body. Markdown never embeds every canonical record. Use JSON or CSV for the complete source archive.

Sleep summary attribution retains its established journaling behavior: the exported date represents the night that begins that evening and continues into the next morning. Raw canonical records use strict start-time day ownership instead. See [Export formats](../reference/export-formats.md#markdown) for a complete production-generated note and exact format comparison.

## Setup

1. Open **Export → Export Formats** and enable **Markdown**.
2. Choose metrics and leave **Lossless Health Records** on unless you need summary-only files.
3. Configure metadata, date/time/units, frontmatter, and the Markdown template.
4. Choose filename/folder settings and write mode.
5. Preview one day, then export.

## Example output (abridged)

The complete production-generated note is [`docs/reference/generated/core/lossless-day.md`](../reference/generated/core/lossless-day.md).

```markdown
---
schema: healthmd.health_data
schema_version: 7
date: 2026-07-15
type: health-data
raw_capture_status: complete
raw_record_count: 842
raw_query_failure_count: 0
raw_integrity_warning_count: 1
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
---

# Health Data: 2026-07-15

## Sleep

- **Total:** 7h 30m

## Activity

- **Steps:** 8,432
- **Stand Time:** 42 min
- **Stand Hours:** 9

## Lossless Health Records

- **Capture status:** complete
- **Source records:** 842
- **External records:** 1
- **Queries:** 18 succeeded · 2 empty · 0 failed · 0 unsupported · 0 skipped
- **Integrity warnings:** 1
```

Example path:

```text
MyVault/Health/2026-07-15.md
```

## What Markdown does not contain

Markdown may show compatibility sample tables, workout summaries, counts, and diagnostics, but it is not the canonical source-record container. It intentionally omits full recursive metadata, exact binary data, route points, ECG waveforms, clinical payloads, attachments, and the record relationship graph.

For exact records:

- export JSON and read `healthkit_record_archive`; or
- export CSV and parse canonical JSON rows.

## Tips

- Use **Update** when you add custom Markdown sections; Health.md refreshes app-managed sections while preserving your writing.
- Keep frontmatter enabled when tools need schema, units, and lossless-capture diagnostics.
- A `partial` status means the visible summary may still be useful, but the source archive is not complete.
- `not_requested` means Lossless Health Records was off; Health.md does not show a prominent lossless section for that state.
- VO2 Max prose identifies carried-forward measurements and their actual source time.
- Blood-pressure tables show real paired correlations when available. Health.md does not infer sessions.
- Dense lossless records can make JSON/CSV much larger without making the Markdown body unreadable.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No `.md` file was written | Markdown is disabled | Enable **Markdown** in Export Formats. |
| `raw_capture_status` is `not_requested` | Lossless Health Records is off | Turn it on and re-export if you need canonical records. |
| Lossless section reports failures | One or more source queries did not complete | Read the diagnostic table and use JSON/CSV for the full manifest. |
| Expected raw records are absent | Markdown intentionally summarizes source capture | Export JSON or CSV. |
| Custom writing disappeared | Write mode was Overwrite | Use **Update** for hand-edited notes. |
| Sections duplicated | Write mode was Append | Use **Update** for repeat exports. |

## Video outline

- **Suggested title:** Readable Apple Health Notes with Lossless Capture Diagnostics
- **Hook:** “Keep your daily note readable without hiding whether the source archive was complete.”
- **Demo flow:** export Markdown, inspect summary/frontmatter/diagnostics, compare the same date's JSON archive, and demonstrate Update mode.

## Implementation notes

- `HealthData.toMarkdown(...)` renders summaries from `ExportDataSnapshot`.
- `ExportHelpers` adds v7 schema, units, and lossless diagnostic frontmatter.
- `MarkdownExporter.losslessHealthRecordsMarkdown(...)` renders counts and safe diagnostics, not canonical record JSON.
- `VaultManager.writeOneFormat(...)` writes the file; `.update` uses `MarkdownMerger` only for readable Markdown.
