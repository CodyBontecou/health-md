import datetime as dt
from pathlib import Path
import tempfile
import unittest
from verify_junit import verify as verify_junit
from verify_run import verify as verify_run


class RunBudgetTests(unittest.TestCase):
    def setUp(self):
        self.start = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        self.now = self.start + dt.timedelta(seconds=119)
        self.receipts = [dict(lane=lane, status='passed', exit_code=0, source_sha='abc',
            working_tree_dirty=False, started_at=(self.start + dt.timedelta(seconds=15)).isoformat(),
            finished_at=(self.start + dt.timedelta(seconds=85)).isoformat(), elapsed_seconds=70)
            for lane in ('rust', 'apple', 'android', 'web')]

    def test_complete_budget(self):
        self.assertEqual(verify_run(self.receipts, 'abc', self.start, self.now), 119)

    def test_setup_queue_and_reporting_count(self):
        with self.assertRaises(ValueError):
            verify_run(self.receipts, 'abc', self.start, self.start + dt.timedelta(seconds=121))

    def test_missing_duplicate_old_dirty_failed_and_slow_receipts_fail(self):
        for change in ({'lane': 'rust'}, {'source_sha': 'old'}, {'working_tree_dirty': True},
                       {'status': 'running'}, {'exit_code': 1}, {'elapsed_seconds': 91},
                       {'finished_at': (self.start - dt.timedelta(seconds=1)).isoformat()}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                receipts = [dict(r) for r in self.receipts]
                receipts[-1].update(change)
                verify_run(receipts, 'abc', self.start, self.now)
        with self.assertRaises(ValueError):
            verify_run(self.receipts[:3], 'abc', self.start, self.now)


class JUnitInventoryTests(unittest.TestCase):
    def test_required_identity_and_failure_modes(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / 'test.xml'
            for body in ('', '<testcase classname="A" name="other"/>',
                         '<testcase classname="A" name="x"><skipped/></testcase>',
                         '<testcase classname="A" name="x"><failure/></testcase>',
                         '<testcase classname="A" name="x"/><testcase classname="A" name="x"/>'):
                p.write_text('<testsuite>' + body + '</testsuite>')
                with self.subTest(body=body), self.assertRaises(ValueError):
                    verify_junit([folder], ['A#x'])
            p.write_text('<testsuite><testcase classname="A" name="x"/></testsuite>')
            verify_junit([folder], ['A#x'])
