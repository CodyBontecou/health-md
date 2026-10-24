"""Exercise the hosted readiness script against recorded launcher-focus states."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / 'apps/android/scripts/prepare-ci-emulator.sh'
FAKE_ADB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
assert a[:2] == ['-s', 'emulator-5554'], a
s['calls'].append(a[2:]); p.write_text(json.dumps(s))
a = a[2:]
mode = os.environ['MOCK_MODE']
if mode == 'disconnected': sys.exit(23)
if a == ['shell', 'getprop', 'ro.boot.qemu']:
 print('0' if mode == 'physical' else '1')
elif a == ['shell', 'getprop', 'sys.boot_completed']:
 s['boots'] += 1; p.write_text(json.dumps(s))
 print('0' if mode == 'booting' and s['boots'] == 1 else '1')
elif a[:3] == ['shell', 'cmd', 'package']:
 if mode in ('setup', 'setup-anr', 'stuck-setup', 'retired-setup', 'missing-setup', 'launch-transport-error') and not s['provisioned']:
  print('com.google.android.googlesdksetup/.DefaultActivity')
 else: print('other.launcher/.Home' if mode == 'wrong-home' else 'com.google.android.apps.nexuslauncher/.NexusLauncherActivity')
elif a == ['shell', 'dumpsys', 'window', 'windows']:
 sys.exit(0)  # Android 15's windows-only section omits mCurrentFocus.
elif a == ['shell', 'dumpsys', '-t', '2', 'window']:
 if mode == 'other-anr': focus = 'Application Not Responding: com.healthmd'
 elif mode == 'stuck' or (mode in ('launcher-anr', 'setup-anr') and not s['recovered']):
  focus = 'Application Not Responding: com.google.android.apps.nexuslauncher'
 elif mode == 'no-focus':
  print('  mCurrentFocus=null'); sys.exit(0)
 else: focus = 'com.google.android.apps.nexuslauncher/.NexusLauncherActivity'
 print('  mCurrentFocus=Window{30918a8 u0 ' + focus + '}')
elif a == ['shell', 'am', 'force-stop', 'com.google.android.apps.nexuslauncher']:
 s['recovered'] = True; p.write_text(json.dumps(s))
elif a[:4] == ['shell', 'am', 'start', '-W']:
 if mode == 'launch-transport-error':
  print('error: device offline', file=sys.stderr)
  sys.exit(23)
 if mode in ('retired-setup', 'missing-setup') and a[-1] == 'com.google.android.googlesdksetup/.DefaultActivity':
  s['provisioned'] = mode == 'retired-setup'; p.write_text(json.dumps(s))
  print('Error type 3', file=sys.stderr)
  print('Error: Activity class does not exist.', file=sys.stderr)
  sys.exit(1)
 if a[-1] == 'com.google.android.googlesdksetup/.DefaultActivity' and mode != 'stuck-setup':
  s['provisioned'] = True; p.write_text(json.dumps(s))
 print('Status: ok')
else: raise SystemExit('Unexpected adb command: ' + repr(a))
'''


class EmulatorReadinessTests(unittest.TestCase):
    def run_setup(self, mode='healthy', github='true'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / 'state.json'
            state.write_text(json.dumps({'calls': [], 'recovered': False, 'boots': 0, 'provisioned': False}))
            for name, code in [('adb', FAKE_ADB), ('sleep', '#!/bin/sh\nexit 0\n'),
                               ('timeout', '#!/bin/sh\nshift\nexec "$@"\n')]:
                p = root / name; p.write_text(code); p.chmod(0o755)
            result = subprocess.run(['bash', str(SCRIPT)], capture_output=True, text=True,
                timeout=15, env={**os.environ, 'PATH': f'{root}:{os.environ["PATH"]}',
                'MOCK_STATE': str(state), 'MOCK_MODE': mode, 'GITHUB_ACTIONS': github})
            return result, json.loads(state.read_text())

    def test_recorded_launcher_anr_is_recovered_once_before_home_is_admitted(self):
        result, state = self.run_setup('launcher-anr')
        self.assertEqual(0, result.returncode, result.stderr)
        stops = [c for c in state['calls'] if 'force-stop' in c]
        self.assertEqual([['shell', 'am', 'force-stop', 'com.google.android.apps.nexuslauncher']], stops)
        self.assertIn('Recovered', result.stdout)
        self.assertIn('ready', result.stdout)

    def test_first_boot_setup_is_started_once_before_launcher_admission(self):
        for mode in ('setup', 'setup-anr'):
            with self.subTest(mode=mode):
                result, state = self.run_setup(mode)
                self.assertEqual(0, result.returncode, result.stderr)
                starts = [c for c in state['calls'] if 'start' in c]
                self.assertEqual(1, sum(c[-1] == 'com.google.android.googlesdksetup/.DefaultActivity' for c in starts))
                self.assertEqual('com.google.android.apps.nexuslauncher/.NexusLauncherActivity', starts[-1][-1])

    def test_retired_setup_activity_requires_re_resolved_known_launcher(self):
        result, state = self.run_setup('retired-setup')
        self.assertEqual(0, result.returncode, result.stderr)
        starts = [c for c in state['calls'] if 'start' in c]
        self.assertEqual(2, len(starts))
        self.assertEqual('com.google.android.apps.nexuslauncher/.NexusLauncherActivity', starts[-1][-1])
        self.assertFalse(any('force-stop' in c for c in state['calls']))

    def test_launch_transport_failure_is_not_mistaken_for_retired_setup(self):
        result, state = self.run_setup('launch-transport-error')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('device offline', result.stderr)

    def test_missing_setup_without_launcher_transition_is_not_ignored(self):
        result, state = self.run_setup('missing-setup')
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any('force-stop' in c for c in state['calls']))

    def test_setup_that_never_selects_launcher_remains_a_failure(self):
        result, state = self.run_setup('stuck-setup')
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any('force-stop' in c for c in state['calls']))

    def test_healthy_launcher_is_not_restarted(self):
        result, state = self.run_setup()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(any('force-stop' in c for c in state['calls']))

    def test_unrelated_anr_fails_without_killing_any_app(self):
        result, state = self.run_setup('other-anr')
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any('force-stop' in c for c in state['calls']))
        self.assertIn('Unexpected ANR', result.stderr)

    def test_persistent_launcher_anr_fails_after_one_recovery(self):
        result, state = self.run_setup('stuck')
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(1, sum('force-stop' in c for c in state['calls']))

    def test_missing_focus_never_admits_the_emulator(self):
        result, _ = self.run_setup('no-focus')
        self.assertNotEqual(0, result.returncode)

    def test_boot_completion_is_required_before_launching_home(self):
        result, state = self.run_setup('booting')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertGreaterEqual(state['boots'], 2)

    def test_developer_devices_unexpected_images_and_adb_errors_fail_closed(self):
        result, state = self.run_setup(github='false')
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], state['calls'])
        for mode in ('physical', 'wrong-home', 'disconnected'):
            with self.subTest(mode=mode):
                result, state = self.run_setup(mode)
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(any('force-stop' in c for c in state['calls']))

    def test_workflow_builds_apks_before_boot_and_keeps_native_preflight(self):
        workflow = (ROOT / '.github/workflows/android-ci.yml').read_text()
        workers = workflow.split('\n  instrumentation-shards:\n')[1].split('\n  instrumentation:\n')[0]
        prepare = workers.index('name: Prepare instrumentation APKs before the emulator boots')
        boot = workers.index('uses: reactivecircus/android-emulator-runner@')
        self.assertLess(prepare, boot)
        for task in (':app:assemblePlayDebug', ':app:assemblePlayDebugAndroidTest'):
            self.assertIn(task, workers[prepare:boot])
        for deferred in (':app:assembleFdroidDebug', ':app:assembleFdroidDebugAndroidTest'):
            self.assertNotIn(deferred, workers[prepare:boot])
        self.assertLess(workers.index('./scripts/prepare-ci-emulator.sh'),
                        workers.index('./scripts/run-ci-instrumentation.sh'))
        runner = (SCRIPT.parent / 'run-ci-instrumentation.sh').read_text()
        self.assertIn('RunnerArguments.class=com.healthmd.presentation.accessibility.NativeInputReadinessTest', runner)
        self.assertNotIn('continue-on-error', workers)
        self.assertIn('timeout 90 ./scripts/prepare-ci-emulator.sh', workers)
        self.assertIn('bash -o pipefail', workers)
        self.assertIn('apps/android/build/logs/emulator-readiness.log', workers)
        self.assertIn(':app:assemblePlayE2eAndroidTest', workers[prepare:boot])
        self.assertIn('cargo test --locked -p healthmd-client --test android_live_listener --no-run', workers[prepare:boot])


if __name__ == '__main__':
    unittest.main()
