# Frontmatter customization

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings
- **Source files:** `presentation/settings/FrontmatterCustomizationScreen.kt`, `domain/model/FrontmatterConfig.kt`

## What it does

Controls the YAML block at the top of your [Markdown](./markdown-export.md) and [Obsidian Bases](./obsidian-bases.md) files: rename metric keys, switch between snake_case and camelCase, toggle the date and type entries, and add your own static or blank placeholder fields.

## Who it is for

- Obsidian users aligning property names with an existing vault convention (for example `steps` → `dailySteps`).
- Bases view builders who want short, consistent keys.
- Anyone adding fixed metadata (a `source:` tag) to every exported note.

## Where to find it

1. Open **Settings → Frontmatter Fields**.
2. Adjust key style, date/type entries, custom fields, and per-metric renames.

## Prerequisites

- Markdown or Obsidian Bases export enabled — frontmatter applies to those formats (and [daily note injection](./daily-note-injection.md)).
- Health Connect permission for any metric you want in frontmatter.

## Setup

1. **Key style:** pick `snake_case` or `camelCase` for every metric key at once.
2. **Date and type:** toggle **Include date** and rename its **Date key** (default `date`); same for the type entry (**Type key**, **Type value**).
3. **Static custom fields:** add key/value pairs written verbatim into every file.
4. **Placeholder fields:** add keys emitted with blank values for you to fill in later.
5. **Metric fields:** search a metric, disable it to drop it from frontmatter entirely, or set a custom **Output key** for it.

## Example output

Default `steps` renamed to `dailySteps`, plus a static field and a placeholder:

```markdown
---
date: 2026-05-12
source: healthmd
mood:
dailySteps: 8432
---
```

## Tips

- Renames apply to Markdown frontmatter, Bases properties, and injected daily-note frontmatter — JSON keeps canonical keys so scripts and the Obsidian plugin stay stable.
- Disabled metric fields simply don't appear; they aren't written as blank.
- Static fields are emitted in sorted key order for stable diffs.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Rename didn't reach JSON | JSON intentionally stays canonical | Renames apply to Markdown/Bases/daily-note frontmatter only |
| Key still snake_case after switching style | The metric has a custom Output key set | Custom output keys override the global key style — clear the rename |
| Placeholder shows in Bases as empty property | That is its purpose | Fill it in Obsidian, or remove the placeholder field |

## Video outline

- **Suggested title:** Make Exported Frontmatter Match Your Vault
- **Hook:** "Your property names. Your conventions."
- **Demo flow:**
  1. Show default frontmatter.
  2. Switch to camelCase and rename `steps`.
  3. Add a static `source` field and re-export.
- **Key screenshot/recording moments:** settings screen, before/after frontmatter diff.
- **CTA / next video:** [Daily note injection](./daily-note-injection.md).

## Implementation notes

`FrontmatterConfiguration` carries `keyStyle` (`SNAKE_CASE`/`CAMEL_CASE`), `includeDate`/`customDateKey`, `includeType`/`customTypeKey`/`customTypeValue`, `customFields` map, `placeholderFields` list, and per-field enable/output-key state resolved by `outputKey(key)`. All three consumers — `MarkdownExporter.buildFrontmatter`, `ObsidianBasesExporter`, and `DailyNoteInjector.buildFrontmatterValues` — render through the same config, so renames stay consistent across surfaces. `JsonExporter` deliberately ignores frontmatter renames to preserve the frozen v4 / analytical v5 wire contract (see [JSON export](./json-export.md)).
