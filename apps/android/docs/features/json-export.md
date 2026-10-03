# JSON export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `data/export/JsonExporter.kt`, `data/export/HealthMdExportSchema.kt`, `domain/model/ExportSettings.kt`

## What it does

Writes one structured JSON document per day under the `healthmd.health_data` contract, wire-compatible with the frozen v4 shape used by the Health.md Obsidian plugin and existing scripts. An additive **Android analytical v5** profile adds Android-native values and exact source details without changing any v4 field.

## Who it is for

- Users of the [Health.md Obsidian plugin](https://github.com/CodyBontecou/health-md-visualizations) and its charts.
- Anyone scripting against their health data (Python, jq, notebooks).
- People who want a machine-readable archive alongside Markdown notes.

## Where to find it

1. Enable **JSON** in **Export Format** on the Export tab.
2. Export; one `.json` file appears per day at your destination.

## Prerequisites

- Health Connect permission for the categories you want exported.
- A folder selected through the Android folder picker.
- JSON enabled in [multi-format export](./multi-format-export.md).

## Setup

1. Enable the JSON format card.
2. Choose your compatibility profile in Settings → Format customization (see below).
3. Preview a day to inspect the payload before writing.

## Example output

```json
{
  "date": "2026-05-12",
  "type": "health-data",
  "units": "metric",
  "schemaProfile": "android-analytical-v5",
  "schemaVersion": 5,
  "sleep": { "totalHours": 7.2, "deepHours": 1.4 },
  "activity": { "steps": 8432 }
}
```

Frozen v4 files look the same minus the `schemaProfile`/`schemaVersion` marker pair.

## Compatibility profiles

| Profile | What it is for |
|---|---|
| **Frozen v4** (default for saved settings) | Byte-stable shape consumed by the Obsidian plugin, the compatibility API export, and existing scripts. Never changes. |
| **Android analytical v5** (default for new installs) | Adds Android-native values and exact source details on top of v4 — everything v4 consumers expect, plus more. |

Two additional switches control extra keys: **legacy Android aliases** re-adds pre-parity key names, and **Android native fields** emits values that have no frozen v4 equivalent. The API endpoint export always embeds frozen v4 regardless of your local profile.

## Tips

- The Obsidian plugin is validated against Android JSON — see the [plugin compatibility report](../export-contract/compatibility-report.md).
- Timestamps are ISO 8601 in both profiles; sample values use the canonical `value` key.
- If a script breaks after switching to v5, switch the profile back to frozen v4 — v4 bytes are unchanged.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Script expects old Android keys | Legacy aliases switch off | Enable legacy Android aliases in Format customization |
| Unknown `schemaProfile` key in a consumer | File is analytical v5 | Consumers ignore unknown keys; or export frozen v4 |
| Plugin shows no data | Metric category not granted in Health Connect | Grant the category and re-export |

## Video outline

- **Suggested title:** Your Health Data as JSON: Plugin-Ready Exports
- **Hook:** "One file per day that your tools can actually read."
- **Demo flow:**
  1. Export a day as JSON and open it.
  2. Point out `date`, `type`, `units`, and one section.
  3. Show the same day rendering in the Obsidian plugin.
- **Key screenshot/recording moments:** JSON file open in a viewer, plugin chart from the same file.
- **CTA / next video:** [CSV export](./csv-export.md).

## Implementation notes

Contract identifier is `healthmd.health_data`; frozen wire version is 4 (`HealthMdExportSchema.VERSION`). The exporter implements the documented iOS parity fixes (sleep `stages` → `sleepStages`, ISO 8601 timestamps, unified `value` keys, `mindfulMinutes`, `pushCount` alias, vitals aliases) — the full Tier-0/Tier-1 ledger is in [`ios-export-contract.md`](../export-contract/ios-export-contract.md) and [`android-ios-gap-matrix.md`](../export-contract/android-ios-gap-matrix.md); profile policy and the freeze guardrail are in [`migration-plan.md`](../export-contract/migration-plan.md). v5 is additive-only and marked with `schemaProfile`/`schemaVersion` at the top of the document; `FormatCustomization.forFrozenApiV4()` pins API v1 delivery to v4. All-connected provenance (cloud providers) is embedded under `metadata.provenance`. Never change frozen v4 bytes to create parity — a new reviewed profile is required (see the repository cross-platform policy).
