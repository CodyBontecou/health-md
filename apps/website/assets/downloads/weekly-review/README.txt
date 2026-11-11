Health.md weekly CSV review example

Try fictional files before using your own records. The included 28 daily CSVs reuse the published spreadsheet sample: September 28 to October 25, 2026. They are an illustrative two-metric subset, not complete exports or a schema fixture.

Requirements
Python 3.9 or later must already be installed. The example uses only Python's standard library; there are no packages to install. Health.md does not install Python. The commands below use python3; a configured Windows Python launcher can use py -3 instead.

Run
1. Unzip the archive and open a terminal in the Health.md Weekly Review Example folder.
2. Inspect weekly_review.py before running it.
3. Run:
   python3 weekly_review.py
4. Open weekly-review.md in a text editor, Markdown viewer, or Obsidian.
5. Compare it with expected-weekly-review.md. The two files should be identical for the bundled input.

Expected result
28 calendar days and 28 recorded step days: 249,630 total steps.
27 recorded sleep days: 7.49 hours mean recorded sleep.
October 8 has no sleep row. It remains missing, not zero.
The final week, October 19–25: 66,580 steps and 7.63 hours mean recorded sleep across seven recorded days.

Use a different folder
After verifying your own exported daily CSVs and keeping them separate from the sample, run:
   python3 weekly_review.py --input "/path/to/your/daily-csvs" --output "/path/to/your/weekly-review.md"
The output path is written or replaced each time. The script refuses to replace an input CSV. Inspect the output path before rerunning.

Input boundaries
- Read only YYYY-MM-DD.csv files in the chosen folder. Each target row's Date must match its filename. combined.csv, rollups, and files in nested folders are not selected.
- Only Activity / Steps / count and Sleep / Total Duration / seconds daily summary rows contribute.
- Timestamped target rows, duplicate daily totals, incompatible units, nonnumeric/nonfinite values, negative totals, and fractional step counts fail with an error instead of being silently combined.
- Blank or absent target values are excluded. Recorded zeros remain included. Metadata, sleep-stage intervals, and unrelated metrics are not added to totals.
- Weeks begin Monday. The first and last week may cover fewer than seven days. Days in range counts the calendar dates between the first and last daily filenames, not proof of complete source records.
- Sleep uses the already-exported journal Date. The script does not infer a different day from bedtime or timestamps. Compare dates, time zones, and units with your source before combining your own files.

What this demonstrates
Local processing of files already on disk. The script makes no network requests, reads no HealthKit data, and does not pair devices, install a folder watcher, or schedule exports. Running it manually does not verify iPhone-to-Mac transfer or iOS background execution. An empty or partial report is not proof that the underlying health data is absent or inaccessible. No medical conclusions or targets are implied.

Guides
https://healthmd.app/blog/health-md-for-macos/#section-turn-daily-csvs-into-a-weekly-review
https://healthmd.app/apple-health-to-csv/#weekly-review-example
https://healthmd.app/apple-health-to-csv/#spreadsheet-sample
https://healthmd.app/docs/sleep-date-attribution/
