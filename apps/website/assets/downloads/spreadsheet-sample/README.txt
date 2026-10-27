Health.md spreadsheet sample

All values are fictional. September 28 to October 25, 2026.
This is an illustrative two-metric CSV subset, not a complete Health.md export or a schema fixture. No device or personal records were used.

Files
- healthmd-health-data-sample.xlsx: editable Excel workbook with native steps and sleep charts.
- combined.csv: all 28 dates, one header, 55 measurement rows.
- daily/: 28 daily CSV files for practicing import or combination.
- sample-summary.json: independently calculated totals and coverage.

Units and dates
Steps use count. Sleep durations use seconds in the CSVs and hours in the workbook (seconds / 3600). Dates are journal dates, not measurement timestamps; Timestamp is empty for daily summaries. Sleep journal dates use local noon to the following noon. A Tuesday 01:00 bedtime can belong to Monday's summary.

Missing data
Sleep on 2026-10-08 is deliberately absent. There are 28 step days and 27 sleep days. No missing value is filled with zero. The sleep chart uses an intentional #N/A helper for that gap; this is not an export failure. Averages use recorded days only.

Use the workbook
Open healthmd-health-data-sample.xlsx in Excel. Overview has two editable charts and formula-linked totals. Daily metrics calculates daily values from Raw data. Raw data preserves the six CSV columns; its separate Checked value column validates numeric inputs. Edit an existing numeric Value to try recalculation. This sample has fixed 28-day dates and bounded input ranges; adding more rows does not extend it automatically. Keep your own data separate and follow the guides to build your own workbook. The workbook has no macros or external data connections. It is a downloadable sample, not an XLSX export feature in the app.

Google Sheets
Import combined.csv into a new spreadsheet, choose Comma, and follow the existing Sheets guide to filter Category, Metric and Unit before charting. This uploads the sample to Google. This pack does not create a shared Google Sheet, and native Excel chart conversion in Sheets has not been verified.

Guides
https://healthmd.app/blog/apple-health-to-excel/
https://healthmd.app/blog/apple-health-to-google-sheets/
https://healthmd.app/apple-health-to-csv/#combine-csv-files

Source of the authored fiction
https://healthmd.app/blog/export-apple-health-data-to-obsidian/#starter-vault

No medical conclusions, targets or recommendations are implied.
