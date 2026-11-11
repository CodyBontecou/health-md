# Fictional spreadsheet sample

The Excel and Google Sheets workflow articles link a sample pack under `assets/downloads/`. It contains 28 daily CSVs, one combined CSV and an editable Excel workbook with steps and sleep charts. This is authored fiction, not a production exporter fixture or an app feature that exports XLSX.

## Source and calculations

`scripts/build-spreadsheet-samples.mjs` derives the two-metric sample from the existing `DAYS` dataset in `scripts/build-starter-vault.mjs`. The dates are September 28–October 25, 2026. The October 8 sleep value is deliberately absent. Steps use `count`; sleep CSV values use `seconds`. Timestamps are empty for daily summaries.

The workbook has Overview, Daily metrics and Raw data sheets. Its first six raw columns match the CSV subset. A separate checked-value column rejects nonnumeric inputs. Daily formulas select exact date/category/metric/unit keys and reject duplicate metric rows. Sleep hours divide seconds by 3600. The chart helper uses `#N/A` for absent sleep; that deliberate error creates a gap. Averages count only recorded values. The sample has bounded input ranges and does not promise automatic extension or refresh.

## Regenerate

Normal website builds need only the committed workbook. After changing CSV packaging or prose, run these commands from `apps/website`:

```bash
npm run spreadsheet-sample:build
npm run spreadsheet-sample:check
node --test test/spreadsheet-sample.test.mjs test/starter-vault.test.mjs
```

If the source dataset or workbook changes, regenerate the workbook first. Its authoring script uses the bundled spreadsheet runtime rather than adding artifact authoring dependencies to the website. Obtain Node, Python, LibreOffice and package paths with `load_workspace_dependencies`. Create a temporary directory with a `node_modules` link to the bundled Node packages, then set:

- `HEALTHMD_ARTIFACT_RUNTIME`: that temporary directory.
- `HEALTHMD_SOFFICE`: the bundled LibreOffice executable.
- `HEALTHMD_PYTHON`: the bundled Python executable.

Using the bundled Node executable, run:

```bash
node scripts/build-spreadsheet-workbook.mjs --output /absolute/path/to/outputs/spreadsheet-sample
npm run spreadsheet-sample:build
node --test test/spreadsheet-sample.test.mjs
```

The authoring script exercises input changes, blanks, zero, invalid values, duplicate keys and date coverage, restores the original fiction, renders each sheet and exports the workbook. LibreOffice recalculates the saved formulas and populates chart caches. The final stdlib ZIP/XML step repairs only the chart missing-value setting that is not exposed by the documented authoring API; source rows, formulas and styling are not patched. Tests require live chart bindings, populated caches, a missing-sleep gap, exact source rows and independently computed totals.

Review every rendered sheet before committing. Commit the workbook, preview and regenerated CSV/archive files together. `build-site.mjs` rejects stale CSVs or pack bytes. Workbook checks run with the normal website tests. Spreadsheet UI behavior in Microsoft Excel and native Google Sheets import remain separate from host-side recalculation and package verification. The public Sheets guide uses `combined.csv` rather than assuming native Excel chart conversion.
