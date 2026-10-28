#!/usr/bin/env python3
"""Create an offline weekly review from Health.md daily summary CSV files.

This demonstration starts with files already on disk. It does not pair devices,
read HealthKit, schedule iOS exports, watch folders, or upload data.
"""
import argparse
import csv
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
import re

HEADER = ['Date', 'Category', 'Metric', 'Value', 'Unit', 'Timestamp']
TARGETS = {('Activity', 'Steps'): 'count', ('Sleep', 'Total Duration'): 'seconds'}


def read_days(folder):
    files = sorted(p for p in Path(folder).glob('*.csv') if re.fullmatch(r'\d{4}-\d{2}-\d{2}', p.stem))
    if not files:
        raise ValueError('No daily YYYY-MM-DD.csv files found. Use the daily folder, not combined.csv or rollups.')
    days = {}
    for path in files:
        file_day = date.fromisoformat(path.stem)
        days[file_day] = {}
        with path.open(encoding='utf-8-sig', newline='') as stream:
            reader = csv.DictReader(stream)
            if reader.fieldnames != HEADER:
                raise ValueError(f'{path.name}: expected the six Health.md CSV column names')
            seen = set()
            for row in reader:
                key = (row['Category'], row['Metric'])
                if key not in TARGETS:
                    continue  # Metadata and stage intervals are not daily totals.
                if row['Date'] != file_day.isoformat():
                    raise ValueError(f'{path.name}: target row date differs from the daily filename')
                if row['Unit'] != TARGETS[key]:
                    raise ValueError(f'{path.name}: unexpected unit for {key[1]}')
                if key in seen:
                    raise ValueError(f'{path.name}: duplicate daily total for {key[1]}; do not sum copies')
                seen.add(key)
                raw_value = row.get('Value')
                if raw_value is None:
                    raise ValueError(f'{path.name}: daily total is missing its Value field')
                raw = raw_value.strip()
                if not raw:
                    continue  # Blank remains missing. Zero is an observed value.
                try:
                    value = Decimal(raw)
                except InvalidOperation as error:
                    raise ValueError(f'{path.name}: nonnumeric daily total for {key[1]}') from error
                if not value.is_finite() or value < 0:
                    raise ValueError(f'{path.name}: daily totals must be finite and nonnegative')
                if key == ('Activity', 'Steps') and value != value.to_integral_value():
                    raise ValueError(f'{path.name}: steps must be a whole count')
                days[file_day][key[1]] = value
    return days


def render(days):
    first, last = min(days), max(days)
    span = (last - first).days + 1
    weeks = {}
    for offset in range(span):
        day = first + timedelta(days=offset)
        monday = day - timedelta(days=day.weekday())
        weeks.setdefault(monday, []).append((day, days.get(day, {})))

    def stats(entries):
        steps = [values['Steps'] for _, values in entries if 'Steps' in values]
        sleep = [values['Total Duration'] for _, values in entries if 'Total Duration' in values]
        total = f'{sum(steps):,.0f}' if steps else '—'
        mean = f'{sum(sleep) / Decimal(len(sleep)) / Decimal(3600):.2f}' if sleep else '—'
        return [str(len(entries)), str(len(steps)), total, str(len(sleep)), mean]

    entries = [(first + timedelta(days=n), days.get(first + timedelta(days=n), {})) for n in range(span)]
    lines = ['# Weekly review from fictional Health.md CSVs', '',
             f'Date range: {first.isoformat()}–{last.isoformat()}. All bundled measurements are fictional.', '',
             '| Week beginning Monday | Days in range | Steps recorded days | Total steps | Sleep recorded days | Mean recorded sleep (hours) |',
             '| --- | ---: | ---: | ---: | ---: | ---: |']
    for monday, rows in sorted(weeks.items()):
        lines.append('| ' + ' | '.join([monday.isoformat()] + stats(rows)) + ' |')
    lines += ['| **Whole supplied range** | ' + ' | '.join(stats(entries)) + ' |', '',
              'Missing values are excluded from averages; recorded zero values remain included. Days in range counts calendar dates between the first and last daily filenames, not proof of complete source coverage.', '',
              'Sleep uses the exported journal Date. The script does not reassign nights from timestamps, add stage intervals to totals, or interpret health outcomes.', '',
              'This example runs after files are on disk. It does not demonstrate iPhone-to-Mac transfer or background scheduling. Re-run the command after replacing the input files.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', default=str(Path(__file__).parent / 'daily'))
    parser.add_argument('--output', default=str(Path(__file__).parent / 'weekly-review.md'))
    args = parser.parse_args()
    try:
        result = render(read_days(args.input))
    except (ValueError, OSError) as error:
        parser.exit(1, f'Cannot build review: {error}\n')
    Path(args.output).write_text(result, encoding='utf-8')
    print(f'Wrote {args.output}')


if __name__ == '__main__':
    main()
