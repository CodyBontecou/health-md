import csv
from datetime import date
from decimal import Decimal
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

spec = importlib.util.spec_from_file_location('weekly_review', Path(__file__).with_name('weekly_review.py'))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

class WeeklyReviewTests(unittest.TestCase):
    def test_bundled_pack_reconciles_with_workbook(self):
        days = review.read_days(Path(__file__).parents[2] / 'assets/downloads/spreadsheet-sample/daily')
        rows = list(days.values())
        self.assertEqual(len(days), 28)
        self.assertEqual(sum(r.get('Steps', 0) for r in rows), 249630)
        self.assertEqual(sum('Total Duration' in r for r in rows), 27)
        self.assertNotIn('Total Duration', days[date(2026, 10, 8)])
        self.assertIn('| **Whole supplied range** | 28 | 28 | 249,630 | 27 | 7.49 |', review.render(days))

    def test_zero_is_observed_and_missing_date_is_not_zero(self):
        days = {date(2026, 10, 5): {'Steps': Decimal(0), 'Total Duration': Decimal(0)}, date(2026, 10, 7): {'Steps': Decimal(20), 'Total Duration': Decimal(7200)}}
        self.assertIn('| 2026-10-05 | 3 | 2 | 20 | 2 | 1.00 |', review.render(days))

    def fixture(self, rows):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        with (Path(folder.name) / '2026-10-05.csv').open('w', newline='') as f:
            writer = csv.writer(f); writer.writerow(review.HEADER); writer.writerows(rows)
        return folder.name

    def test_duplicate_totals_rejected(self):
        row = ['2026-10-05', 'Activity', 'Steps', '10', 'count', '']
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            review.read_days(self.fixture([row, row]))

    def test_seconds_not_mixed_with_hours(self):
        with self.assertRaisesRegex(ValueError, 'unexpected unit'):
            review.read_days(self.fixture([['2026-10-05', 'Sleep', 'Total Duration', '7', 'hours', '']]))

    def test_stage_intervals_do_not_inflate_summary(self):
        folder = self.fixture([['2026-10-05', 'Sleep', 'Total Duration', '7200', 'seconds'], ['2026-10-05', 'Sleep', 'Sleep Stage', 'deep (3600s)', 'seconds', '2026-10-05T06:00:00Z']])
        self.assertEqual(review.read_days(folder)[date(2026, 10, 5)]['Total Duration'], 7200)

    def test_truncated_target_row_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unexpected unit|missing its Value'):
            review.read_days(self.fixture([['2026-10-05', 'Activity', 'Steps']]))

    def test_timestamped_reading_is_not_a_daily_total(self):
        with self.assertRaisesRegex(ValueError, 'timestamped readings'):
            review.read_days(self.fixture([['2026-10-05', 'Activity', 'Steps', '10', 'count', '2026-10-05T12:00:00Z']]))

    def test_output_cannot_replace_input_csv(self):
        folder = self.fixture([['2026-10-05', 'Activity', 'Steps', '10', 'count', '']])
        source = Path(folder) / '2026-10-05.csv'
        original = source.read_bytes()
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('weekly_review.py')), '--input', folder, '--output', str(source)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must not replace an input CSV', result.stderr)
        self.assertEqual(source.read_bytes(), original)

    def test_nonfinite_and_wrong_date_rejected(self):
        for raw in ['NaN', 'Infinity', '-1']:
            with self.assertRaises(ValueError):
                review.read_days(self.fixture([['2026-10-05', 'Activity', 'Steps', raw, 'count']]))
        with self.assertRaisesRegex(ValueError, 'date differs'):
            review.read_days(self.fixture([['2026-10-06', 'Activity', 'Steps', '10', 'count']]))

if __name__ == '__main__':
    unittest.main()
