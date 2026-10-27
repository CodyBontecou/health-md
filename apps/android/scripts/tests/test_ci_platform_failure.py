"""Replay the runner's failure boundary without an emulator or Gradle build."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'run-ci-instrumentation.sh'


class PlatformFailureTests(unittest.TestCase):
    def replay(self, github='true', qemu='1', diagnostic_failure=False, blocked_log=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            runner = root / 'scripts' / SCRIPT.name
            runner.write_text(SCRIPT.read_text())
            (root / 'gradlew').write_text('#!/bin/sh\nexit 19\n')
            (root / 'gradlew').chmod(0o755)
            (root / 'bin').mkdir()
            if blocked_log:
                (root / 'build').write_text('unavailable log directory')
            adb = root / 'bin/adb'
            adb.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a = sys.argv[1:]
with Path(os.environ['CALLS']).open('a') as f: f.write(json.dumps(a) + '\\n')
assert a[:2] == ['-s', 'emulator-5554']
if a[2:] == ['shell', 'getprop', 'ro.boot.qemu']: print(os.environ['QEMU'])
elif os.environ['DIAGNOSTIC_FAILURE'] == 'true': sys.exit(23)
elif 'window' in a: print('mCurrentFocus=Window{61818aa u0 Application Not Responding: com.google.android.apps.nexuslauncher}')
else: print('Reason: Input dispatching timed out (launcher fixture)')
''')
            adb.chmod(0o755)
            result = subprocess.run(['bash', str(runner)], capture_output=True, text=True,
                timeout=10, env={**os.environ, 'PATH': f'{root / "bin"}:{os.environ["PATH"]}',
                'GITHUB_ACTIONS': github, 'QEMU': qemu, 'CALLS': str(root / 'calls'),
                'DIAGNOSTIC_FAILURE': str(diagnostic_failure).lower()})
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()] if (root / 'calls').exists() else []
            log = root / 'build/logs/instrumentation-platform-failure.log'
            return result, calls, log.read_text() if log.exists() else None

    def test_recorded_launcher_failure_retains_reason_and_original_exit_status(self):
        result, calls, log = self.replay()
        self.assertEqual(19, result.returncode, result.stderr)
        self.assertIsNotNone(log)
        self.assertIn('Application Not Responding: com.google.android.apps.nexuslauncher', log)
        self.assertIn('Reason: Input dispatching timed out', log)
        self.assertTrue(any(a[2:] == ['shell', 'dumpsys', '-t', '2', 'activity', 'lastanr'] for a in calls))

    def test_developer_run_never_collects_other_apps(self):
        result, calls, log = self.replay(github='false')
        self.assertEqual(19, result.returncode)
        self.assertEqual([], calls)
        self.assertIsNone(log)

    def test_non_emulator_never_collects_platform_state(self):
        result, calls, log = self.replay(qemu='0')
        self.assertEqual(19, result.returncode)
        self.assertEqual([['-s', 'emulator-5554', 'shell', 'getprop', 'ro.boot.qemu']], calls)
        self.assertIsNone(log)

    def test_failed_diagnostics_cannot_replace_original_failure(self):
        result, _, _ = self.replay(diagnostic_failure=True)
        self.assertEqual(19, result.returncode)

    def test_unavailable_log_directory_cannot_replace_original_failure(self):
        result, _, _ = self.replay(blocked_log=True)
        self.assertEqual(19, result.returncode)
