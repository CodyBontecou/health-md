---
title: "Analyze Apple Health CSV with Python"
description: "Analyze Apple Health CSV locally with Python. Try a tested steps example, combine daily files, reject overlapping dates, and report weekly totals over recorded days."
lead: "Turn daily Health.md CSV exports into a weekly steps report on your computer, using Python’s standard library and a fictional sample before your own files."
date: "2026-10-27"
updated: "2026-10-27"
category: "Workflow guide"
related:
  - export-apple-health-steps-data
  - apple-health-to-excel
  - healthmd-cli-direct-iphone-mcp
draft: false
verified: "2026-10-27"
verified_by: "Codex (agent)"
verified_method: mixed
tags:
  - apple-health
  - python
  - csv
  - local-analysis
---

To analyze Apple Health data with Python, first export the metrics you need as CSV, then read those files locally. This walkthrough uses Health.md’s daily Summary CSV format and Python’s built in `csv` module. You do not need pandas, a notebook service, or a cloud upload for the example.

Apple’s built in Export All Health Data produces an XML archive. The code below reads fresh Health.md CSV exports; it does not parse `export.xml`, convert an existing archive, or read Apple Health directly from your computer. Start with the [XML export guide](/blog/apple-health-xml-export/) if you already have an Apple archive.

## 1. Export daily summaries for the metric you want

On the iPhone with your Apple Health records:

1. Open Health.md and authorize the metrics you want to export.
2. Select **CSV**, **Summary**, and **Steps**. Set the date format to **YYYY-MM-DD**.
3. Preview one known day and save it to a writable folder in Files. Follow [your first iPhone export](/docs/iphone-first-export/) for setup.
4. Transfer the files to your computer using your chosen folder or transfer method. A longer date range creates one file per day.

Use daily Summary files for this recipe. Keep weekly and monthly rollups, Detailed Time-Series samples, and older copies outside your input set. The script analyzes the exported daily totals, not individual sensor readings or source records. See [how step totals are exported](/blog/export-apple-health-steps-data/) before comparing a report with another app.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Health.md includes 5 free export actions, followed by one lifetime unlock. A Mac is not required to export on iPhone; the Python recipe runs on a computer with Python 3 installed.

## 2. Read the CSV contract before converting numbers

The header is `Date,Category,Metric,Value,Unit,Timestamp`. `Value` is mixed type: metadata, status strings, times and quoted JSON may appear alongside numbers. Filter to `Category = Activity`, `Metric = Steps`, and `Unit = count` before converting a value.

Some daily summary rows contain five fields, omitting Timestamp. Other rows contain all six fields. A CSV parser handles quoted commas and embedded newlines; splitting each line on commas does not. This example reads UTF-8 with an optional byte order mark and uses `csv.reader` with `newline=""`, following [Python’s CSV documentation](https://docs.python.org/3/library/csv.html).

The script selects matching rows with an empty or omitted Timestamp. It rejects repeated dates instead of summing overlapping exports. It also rejects invalid dates, unexpected row shapes, and values that are not nonnegative whole counts. Those checks validate this recipe’s input; they do not prove that the underlying Apple Health history is complete.

## 3. Copy the local Python example

Save the following as `analyze_steps.py` in a working folder. It reads only the file paths you pass, leaves those files unchanged, and prints a report after all inputs pass validation. No package installation is needed.

```python
import csv
import re
import sys
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal

HEADER = ["Date", "Category", "Metric", "Value", "Unit", "Timestamp"]


def report(paths):
    if not paths:
        raise ValueError("Pass one or more daily Summary CSV files")
    days = {}
    for path in paths:
        with open(path, encoding="utf-8-sig", newline="") as source:
            rows = csv.reader(source, strict=True)
            if next(rows, None) != HEADER:
                raise ValueError("Expected the Health.md six-column CSV header")
            for row in rows:
                if not row:
                    continue
                if row == HEADER:
                    raise ValueError("Repeated header: combine data rows only")
                if len(row) not in (5, 6):
                    raise ValueError("Unexpected CSV row shape")
                if row[1:3] != ["Activity", "Steps"] or row[4] != "count":
                    continue
                if len(row) == 6 and row[5]:
                    continue  # This recipe uses daily totals, not timed samples.
                day = date.fromisoformat(row[0])
                if day.isoformat() != row[0]:
                    raise ValueError("Use YYYY-MM-DD export dates")
                if day in days:
                    raise ValueError("Repeated steps date: review overlapping exports")
                if not re.fullmatch(r"[0-9]+(?:\.0+)?", row[3]):
                    raise ValueError("Expected a nonnegative whole steps count")
                days[day] = int(row[3].split(".")[0])
    if not days:
        raise ValueError("No matching daily steps rows found")
    weeks = defaultdict(list)
    for day, steps in days.items():
        monday = day - timedelta(days=day.weekday())
        weeks[monday].append(steps)
    result = [["WeekStarting", "RecordedDays", "Steps", "AveragePerRecordedDay"]]
    for monday, counts in sorted(weeks.items()):
        total = sum(counts)
        average = Decimal(total) / len(counts)
        result.append([monday.isoformat(), len(counts), total, f"{average:.2f}"])
    return result


if __name__ == "__main__":
    try:
        result = report(sys.argv[1:])
    except (ValueError, OSError, csv.Error) as error:
        print(f"Cannot build report: {error}", file=sys.stderr)
        sys.exit(1)
    csv.writer(sys.stdout, lineterminator="\n").writerows(result)
```

The week begins on Monday, using Python’s [date arithmetic](https://docs.python.org/3/library/datetime.html#date-objects). The average uses [Decimal](https://docs.python.org/3/library/decimal.html) and is displayed to two decimal places. The report does not fill absent dates or weeks with zeroes.

## 4. Verify the fictional sample, then combine your dates

Download the [synthetic daily CSV sample](/docs/reference/generated/core/summary-day.csv) into the working folder. The file contains fictional exporter test data, including a daily steps row for 2026-03-15 with 12500 steps. Run:

```bash
python3 analyze_steps.py summary-day.csv
```

On Windows, use `py -3` instead of `python3` if that is how your Python installation is launched. The expected report is:

```csv
WeekStarting,RecordedDays,Steps,AveragePerRecordedDay
2026-03-09,1,12500,12500.00
```

That is one recorded day, not a complete seven day week. The Monday label groups the date; it does not move the original measurement to Monday.

For your own exports, pass the intended daily files explicitly. Replace these example names with the files you saved:

```bash
python3 analyze_steps.py 2026-03-15.csv 2026-03-16.csv
```

The script combines the matching daily rows in memory. You can also pass a combined file from the [browser CSV combiner](/apple-health-to-csv/#combine-csv-files), provided it contains only the intended daily exports. That tool preserves duplicates; this analysis script rejects duplicate steps dates for you to resolve.

A week’s `RecordedDays` counts exported daily steps rows, including an explicit zero. `Steps` sums only those rows. `AveragePerRecordedDay` divides by RecordedDays, not seven. Missing dates do not establish inactivity. The recipe neither fills gaps nor estimates missing steps.

To save the printed report, redirect it to a **new output file** outside your source files:

```bash
python3 analyze_steps.py 2026-03-15.csv 2026-03-16.csv > weekly-steps.csv
```

Keep your originals. Shell redirection can create an empty output file even when validation fails, so check the command’s exit status and error text before using a saved report. Never use an input filename as the output filename.

## 5. Fix missing rows or unexpected totals

- **No matching daily steps rows:** check the selected metrics and dates, and confirm the exact category, metric and unit in your CSV. An absent row is not a zero or proof that permission was denied. Follow [export troubleshooting](/docs/troubleshooting/).
- **Repeated steps date:** remove overlapping copies after reviewing which export you intend to use. The script does not choose the latest file or silently discard a duplicate.
- **Unexpected header or row shape:** use a fresh Health.md CSV export. An XML archive, JSON export, report CSV or another app’s CSV needs its own parser.
- **Wrong date format:** re-export with YYYY-MM-DD. Do not guess whether a date means month first or day first.
- **Unexpected count:** inspect the original matching row. The recipe rejects text, blanks, negative values and fractional counts rather than turning errors into zero.

This report describes the exported data. It does not reconcile devices, diagnose a health condition, or establish that every day was captured. For JSON validation and canonical source records, use the [integration recipes](/docs/reference/integration-recipes/). For direct device queries rather than saved CSV files, see the [Health.md CLI and MCP guide](/blog/healthmd-cli-direct-iphone-mcp/).

## Keep the analysis on your computer

The core folder export needs no Health.md account and creates no Health.md server copy by default. This Python example makes no network requests. Files in a synced folder, remote notebook, shared computer or backed up destination follow that provider’s storage and privacy rules; choose your working folder accordingly.

The separate optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. It has no public signup and no automatic device sync. This CSV and Python workflow does not upload to the pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

Start with the fictional sample, verify one known day, then run your intended date range. Return to [Apple Health to CSV](/apple-health-to-csv/) for export setup, samples and other analysis destinations.
