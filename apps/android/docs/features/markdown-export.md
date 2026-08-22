# Markdown export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Settings
- **Source files:** `data/export/MarkdownExporter.kt`, `presentation/settings/FormatCustomizationScreen.kt`, `domain/model/MarkdownTemplateConfig.kt`

## What it does

Writes one readable Markdown file per day — `# Health Data — 2026-05-12` followed by grouped sections (Sleep, Activity, Heart, Vitals, Body, Nutrition, Mobility, Reproductive Health, Mindfulness, Workouts) with optional YAML frontmatter. You choose the template style, bullet character, section header level, and emoji headers.

## Who it is for

- Anyone journaling in Obsidian, Notion, or any Markdown app.
- People who read their health data, not just query it.

## Where to find it

1. Enable **Markdown** in **Export Format** on the Export tab.
2. Open **Settings → Format customization** for template options.
3. Export; one `.md` file appears per day at your destination.

## Prerequisites

- Health Connect permission for the categories you want in the note.
- A folder selected through the Android folder picker.
- Markdown enabled in [multi-format export](./multi-format-export.md).

## Setup

1. In **Settings → Format customization**, pick a **Markdown Template Style**:
   - **Standard** — balanced format with sections and bullet points
   - **Compact** — condensed single-line metrics, minimal whitespace
   - **Detailed** — expanded format with descriptions and context
   - **Custom** — your own template with placeholders
2. Choose **Bullet Style**: Dash (`-`), Asterisk (`*`), or Plus (`+`).
3. Choose **Section Header Level** (`##` through `######`) and toggle **Emoji in Headers**.
4. For **Custom**, write your template and tap **Preview**.

## Example output

```markdown
---
date: 2026-05-12
sleep_total_hours: 7.2
steps: 8432
---

# Health Data — 2026-05-12

## 😴 Sleep

- Total Sleep: 7.2 hours
- Deep Sleep: 1.4 hours

## 🏃 Activity

- Steps: 8,432
```

## Custom templates

Custom templates support tokens and conditional blocks:

- `{{date}}`, `{{metrics}}`, `{{sleep_metrics}}`, `{{activity_metrics}}`, `{{heart_metrics}}`, `{{vitals_metrics}}`, `{{workout_list}}`
- Category blocks like `{{#sleep}}…{{/sleep}}` or `{{#activity}}…{{/activity}}` — a block is removed entirely when that category has no data for the day.

Tap **Reset template** to return to the default layout.

## Tips

- Frontmatter appears when metadata is included; rename its keys in [Frontmatter customization](./frontmatter-customization.md).
- When cloud providers (Fitbit, Oura, WHOOP, Withings) merge into a day, a short provenance blockquote at the top lists which provider supplied each category and how duplicate workouts were deduplicated.
- On the analytical v5 profile, frontmatter gains a `healthmd_schema_profile: android-analytical-v5` marker line.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Sections missing from the note | No Health Connect data for that category that day | Grant the category permission or pick a day with data |
| Custom template rendered empty | All blocks used categories with no data | Check tokens and block syntax; tap **Reset template** |
| Emoji/headers look different from preview | Emoji headers toggle changed after preview | Re-run preview after toggling **Emoji in Headers** |

## Video outline

- **Suggested title:** Readable Health Notes: Customize Your Markdown Template
- **Hook:** "Your health data, written like a journal — not a spreadsheet."
- **Demo flow:**
  1. Export one day as Standard.
  2. Switch to Compact and re-export the same day.
  3. Build a tiny custom template with `{{#sleep}}` and preview it.
- **Key screenshot/recording moments:** Standard vs Compact side by side, custom template editor with live preview.
- **CTA / next video:** [Obsidian Bases export](./obsidian-bases.md).

## Implementation notes

`MarkdownExporter.export` renders frontmatter (`includeMetadata`) then either `renderCustomTemplate` (style `CUSTOM`) or the heading plus `renderAllSections`. Template config (`MarkdownTemplateConfig`) carries style, bullet symbol, `sectionHeaderLevel`, `useEmoji`, and the custom template string; defaults are `STANDARD`. Frontmatter values and section rows both flow through `HealthDataFields.extract`, honoring unit conversion, time format, and the legacy-alias/native-field switches. All-connected provenance rendering matches `compatibilityProvenance` on `HealthData`. Keep this page in sync with the exporter's token list in `strings.xml` (`custom_markdown_template_tokens`).
