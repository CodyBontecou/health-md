import datetime as dt
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from verify_junit import verify as verify_junit
from verify_run import (verify as verify_run, cache_publication_allowed,
                        write_cache_publication_decision)


class RunBudgetTests(unittest.TestCase):
    def setUp(self):
        self.start = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        self.now = self.start + dt.timedelta(seconds=119)
        self.receipts = [dict(lane=lane, status='passed', exit_code=0, source_sha='abc',
            working_tree_dirty=False, started_at=(self.start + dt.timedelta(seconds=15)).isoformat(),
            finished_at=(self.start + dt.timedelta(seconds=85)).isoformat(), elapsed_seconds=70)
            for lane in ('contracts', 'core', 'cli', 'practice', 'wake', 'consumer')]

    def test_complete_budget(self):
        self.assertEqual(verify_run(self.receipts, 'abc', self.start, self.now), 119)
        self.assertTrue(cache_publication_allowed(self.start, self.start + dt.timedelta(seconds=100)))
        for elapsed in (-1, 100.001, 119, 121):
            self.assertFalse(cache_publication_allowed(self.start, self.start + dt.timedelta(seconds=elapsed)))

    def test_setup_queue_and_reporting_count(self):
        self.assertFalse(cache_publication_allowed(self.start, self.start + dt.timedelta(seconds=121)))
        with self.assertRaises(ValueError):
            verify_run(self.receipts, 'abc', self.start, self.start + dt.timedelta(seconds=121))

    def test_missing_duplicate_old_dirty_failed_and_slow_receipts_fail(self):
        for change in ({'lane': 'core'}, {'source_sha': 'old'}, {'working_tree_dirty': True},
                       {'status': 'running'}, {'exit_code': 1}, {'elapsed_seconds': 91},
                       {'finished_at': (self.start - dt.timedelta(seconds=1)).isoformat()}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                receipts = [dict(r) for r in self.receipts]
                receipts[-1].update(change)
                self.assertFalse(cache_publication_allowed(self.start, self.now))
                verify_run(receipts, 'abc', self.start, self.now)
        with self.assertRaises(ValueError):
            verify_run(self.receipts[:5], 'abc', self.start, self.now)

    def test_uncertain_cache_clock_skips_upload_but_not_the_final_gate(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'output'
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(output)}), \
                    patch('verify_run.lookup_run_start', side_effect=ValueError('uncertain time')) as lookup:
                write_cache_publication_decision()
            lookup.assert_called_once_with(timeout=2)
            self.assertEqual(output.read_text(), 'save=false\n')
        workflow = (Path(__file__).resolve().parents[2] / '.github/workflows/ci.yml').read_text()
        self.assertIn("steps.cargo-cache-budget.outputs.save == 'true'", workflow)
        final_gate = workflow.split('- name: Require every group and the complete wall-clock budget', 1)[1]
        self.assertIn('if: ${{ !cancelled() }}', final_gate)
        self.assertIn('run: python3 scripts/ci/verify_run.py', final_gate)
        self.assertNotIn('cargo-cache-budget', final_gate)


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
