# Markdown Template Customization

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Format Customization → Markdown Template
- **Source files:** `HealthMd/iOS/Views/FormatCustomizationView.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Export/MarkdownExporter.swift`

## What it does

Markdown Template Customization controls the body of Health.md Markdown exports. You can choose a template style, section header level, bullet style, emoji headers, summary behavior, and a custom template with placeholders and conditional sections.

Use it to make generated notes match your Obsidian vault style.

## Who it is for

- Users who want cleaner or more personal Markdown notes.
- Obsidian users matching an existing daily-note or database style.
- Creators showing Health.md output in docs, videos, or shared vaults.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Tap **Format Customization**.
4. Tap **Markdown Template**.

## Prerequisites

- Markdown export selected.
- At least one metric enabled.
- For custom templates, basic familiarity with Markdown placeholders.

## Setup

1. Choose a **Style**: Standard, Compact, Detailed, or Custom.
2. Set **Section Headers** to `# H1`, `## H2`, or `### H3`.
3. Choose **Bullet Style**: dash, asterisk, or plus.
4. Toggle **Use Emoji in Headers**.
5. Toggle **Include Summary**.
6. If using **Custom**, edit the template text.
7. Check the preview and export.

## Custom placeholders

Supported placeholders include:

- `{{date}}`
- `{{summary}}`
- `{{metrics}}`
- `{{sleep_metrics}}`
- `{{activity_metrics}}`
- `{{heart_metrics}}`
- `{{vitals_metrics}}`
- `{{body_metrics}}`
- `{{nutrition_metrics}}`
- `{{mindfulness_metrics}}`
- `{{mobility_metrics}}`
- `{{hearing_metrics}}`
- `{{workout_list}}` / `{{workouts_metrics}}`

Conditional blocks render only when that section has data:

```markdown
{{#sleep}}
## Sleep
{{sleep_metrics}}
{{/sleep}}
```

## Example output

```markdown
# Health Data — 2026-05-12

7h 30m sleep · 8,432 steps · 1 workout

## Sleep

- **Total:** 7h 30m
- **Bedtime:** 23:15

## Activity

- **Steps:** 8,432
```

## Tips

- Use `## H2` sections if your file title is `# Health Data`.
- Turn off emoji headers if you rely on exact heading names in scripts.
- Use conditional blocks so empty sections do not appear.
- Use `{{metrics}}` for a quick full-body custom template.
- Keep section names stable if you use Update mode; the merger matches app-managed sections by heading name.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Custom section did not render | Conditional block had no data | Verify that category has data and metrics enabled. |
| Placeholder appears literally | Placeholder name is misspelled or unsupported | Use one of the supported placeholders. |
| Update mode duplicated sections | Custom headings do not match managed section names | Use standard names like Sleep, Activity, Heart, Vitals. |
| Output is too noisy | Summary, emoji, or detailed sections enabled | Turn off summary/emoji or use fewer enabled metrics. |
| Frontmatter did not change | Template controls body, not YAML fields | Use **Frontmatter Fields** for YAML customization. |

## Video outline

- **Suggested title:** Customize Health.md Markdown Templates
- **Hook:** “Health.md doesn’t have to write notes in one fixed style.”
- **Demo flow:**
  1. Show the default Markdown output.
  2. Change header level, bullet style, emoji, and summary.
  3. Switch to Custom.
  4. Build a short template using `{{date}}`, `{{summary}}`, and conditional sleep/activity blocks.
  5. Export and compare output.
- **Key screenshot/recording moments:** template controls, custom template editor, before/after Markdown.
- **CTA / next video:** “Next, we’ll customize filenames and folders.”

## Implementation notes

- `MarkdownTemplateConfig` stores style, custom template, header level, emoji, summary, and bullet style.
- `HealthData.toMarkdown(...)` chooses standard rendering unless style is `.custom`.
- Custom rendering replaces placeholders and applies `{{#section}}...{{/section}}` conditional blocks.
- `MarkdownTemplateView.previewText` renders a lightweight preview with sample sleep/activity data.
- Section merge behavior depends on `MarkdownMerger.detectSectionLevel(...)` and normalized managed section names.
