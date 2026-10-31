#!/usr/bin/env python3
"""Host-only checks for the current portable CI entry point and Apple wrapper.

The former per-platform planner/final gate was retired by the two-minute CI
strategy. Behavioral deadline, receipt and source checks live in scripts/ci/test_*.py.
Native diagnostic helpers have their own SDK-free regressions.
"""
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[4]


class WorkflowRoutingTests(unittest.TestCase):
    def test_one_hosted_job_runs_the_current_portable_suite(self):
        text = (REPO / '.github/workflows/ci.yml').read_text()
        jobs = re.findall(r'^  ([a-z][a-z0-9-]*):\n', text.split('jobs:\n', 1)[1], re.M)
        self.assertEqual(jobs, ['test'])
        for required in ('name: CI', 'runs-on: ubuntu-24.04', 'timeout-minutes: 2',
                         'node-version: \'24\'', 'dtolnay/rust-toolchain@1.88.0',
                         'run: python3 scripts/ci/run.py', 'run: python3 scripts/ci/verify_run.py',
                         'cancel-in-progress: ${{ !inputs.release_sha }}'):
            self.assertIn(required, text)
        self.assertLess(text.index('scripts/ci/run.py'), text.index('scripts/ci/verify_run.py'))
        self.assertIn('if: ${{ !cancelled() }}', text)
        self.assertNotIn('continue-on-error', text)

    def test_native_components_delegate_to_the_same_suite(self):
        for name in ('apple', 'android', 'cli', 'practice'):
            with self.subTest(component=name):
                text = (REPO / f'.github/workflows/{name}-ci.yml').read_text()
                self.assertIn('uses: ./.github/workflows/ci.yml', text)
                self.assertIn('release_sha: ${{ inputs.release_sha || github.sha }}', text)
                self.assertNotIn('xcodebuild', text)
                self.assertNotIn('gradlew', text)

    def test_every_change_and_exact_release_source_are_checked(self):
        text = (REPO / '.github/workflows/ci.yml').read_text()
        self.assertIn('pull_request:', text)
        self.assertIn('branches: [main, testing]', text)
        self.assertNotIn('paths-ignore:', text)
        self.assertNotIn('paths:', text.split('permissions:', 1)[0])
        self.assertIn('SOURCE_REVISION: ${{ inputs.release_sha || github.sha }}', text)
        self.assertIn('test "$(git rev-parse HEAD)" = "$SOURCE_REVISION"', text)
        self.assertIn('HEALTHMD_CI_SOURCE_SHA: ${{ env.SOURCE_REVISION }}', text)

    def test_external_consumer_is_pinned_before_the_suite(self):
        text = (REPO / '.github/workflows/ci.yml').read_text()
        self.assertIn("require('./apps/website/external-sources.json').obsidian_plugin.revision", text)
        self.assertIn('fetch -q --depth=1 origin "$revision"', text)
        self.assertLess(text.index('Check out the pinned Obsidian consumer'), text.index('scripts/ci/run.py'))


if __name__ == '__main__':
    unittest.main()
