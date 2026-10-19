"""Run the real root/component Makefiles with fake tools and a concurrency latch."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
ANDROID_TASKS = [
    ':app:testPlayDebugUnitTest', ':app:testPlayReleaseUnitTest', ':app:testPlayE2eUnitTest',
    ':healthmd-core:testDebugUnitTest', ':wearable-contract:test', ':direct-protocol:test',
]

FAKE = r'''
import fcntl, json, os, sys, time
from pathlib import Path
root = Path(os.environ['FIXTURE_ROOT'])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
component = Path.cwd().relative_to(root).as_posix()
job = name + ':' + component
if name == 'python3':
    job = 'contracts' if args == ['packages/contracts/validate.py'] else 'registry:' + args[0]
elif name == 'xcodebuild':
    scheme = args[args.index('-scheme') + 1]
    job = 'ios' if scheme == 'HealthMd-Tests-iOS' else 'macos'
elif name == 'prepare':
    job = 'prepare'

def log(event):
    with (root / 'calls.jsonl').open('a') as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        file.write(json.dumps({'job':job, 'event':event, 'args':args, 'cwd':component}) + '\n')
        file.flush()
log('start')
(root / (job.replace('/', '_').replace(':', '_') + '.started')).touch()
# Four jobs must coexist: two root gates and both native destinations. A serial
# child, missing destination, or broken jobserver cannot satisfy this latch.
if os.environ.get('LATCH') == '1' and job in ('contracts', 'gradlew:apps/android', 'ios', 'macos'):
    deadline = time.monotonic() + 8
    while not all((root / (n + '.started')).exists() for n in ('contracts', 'gradlew_apps_android', 'ios', 'macos')):
        if time.monotonic() >= deadline:
            log('end'); print('Executed latch timeout'); sys.exit(91)
        time.sleep(.01)
log('end')
print('Executed synthetic gate ' + job)
sys.exit(23 if os.environ.get('FAIL_JOB') == job else 0)
'''


class LocalRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='healthmd-root-make-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        for component in ('apple', 'android', 'cli', 'practice', 'wake', 'cloud', 'website'):
            (self.root / 'apps' / component).mkdir(parents=True)
        (self.root / 'packages/healthmd-core-rust').mkdir(parents=True)
        shutil.copyfile(ROOT / 'Makefile', self.root / 'Makefile')
        shutil.copyfile(ROOT / 'apps/apple/Makefile', self.root / 'apps/apple/Makefile')
        binary = self.root / 'bin'
        binary.mkdir()
        for name in ('python3', 'cargo', 'npm', 'xcodebuild', 'prepare'):
            file = binary / name
            file.write_text(f'#!{sys.executable}\n' + FAKE)
            file.chmod(0o755)
        (self.root / 'apps/android/gradlew').symlink_to(binary / 'cargo')
        self.env = dict(os.environ, PATH=f'{binary}:/usr/bin:/bin', FIXTURE_ROOT=str(self.root))

    def run_make(self, *args, **env):
        result = subprocess.run([
            'make', *args, f'CORE_RUST_PREPARE={self.root / "bin/prepare"}',
            'IOS_SIM=platform=iOS Simulator,id=synthetic',
        ], cwd=self.root, env={**self.env, **env}, capture_output=True, text=True, timeout=20)
        log = self.root / 'calls.jsonl'
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls

    def assert_all_gates(self, calls):
        starts = [x for x in calls if x['event'] == 'start']
        expected = {'contracts', 'cargo:packages/healthmd-core-rust', 'ios', 'macos',
                    'gradlew:apps/android', 'cargo:apps/cli', 'npm:apps/practice',
                    'npm:apps/wake', 'npm:apps/cloud', 'npm:apps/website'}
        self.assertTrue(expected <= {x['job'] for x in starts})
        self.assertEqual(1, sum(x['job'] == 'prepare' for x in starts))
        self.assertEqual([['test'], ['run', 'check']], [x['args'] for x in starts if x['job'] == 'npm:apps/wake'])
        self.assertIn(['test', '--workspace', '--all-features', '--locked'],
                      [x['args'] for x in starts if x['job'] == 'cargo:packages/healthmd-core-rust'])
        self.assertEqual(ANDROID_TASKS + ['--max-workers=2', '--init-script', 'scripts/ci-gradle.init.gradle'],
                         next(x['args'] for x in starts if x['job'] == 'gradlew:apps/android'))
        native = {x['job']: x['args'] for x in starts if x['job'] in ('ios', 'macos')}
        derived = []
        for platform, args in native.items():
            self.assertEqual('test', args[0])
            self.assertFalse(any('only-testing' in a or 'skip-testing' in a for a in args))
            derived.append(args[args.index('-derivedDataPath') + 1])
            self.assertEqual(str(self.root / 'apps/apple/build/local-test-derived-data' / platform), derived[-1])
        self.assertEqual(2, len(set(derived)))

    def test_default_parallel_run_preserves_every_gate_and_separates_xcode_databases(self):
        result, calls = self.run_make('test', LATCH='1')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assert_all_gates(calls)
        active = maximum = 0
        for call in calls:
            active += 1 if call['event'] == 'start' else -1
            maximum = max(active, maximum)
        self.assertEqual(0, active)
        self.assertEqual(4, maximum)

    def test_serial_override_runs_same_commands_without_overlap(self):
        result, calls = self.run_make('test', 'TEST_JOBS=1')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assert_all_gates(calls)
        active = maximum = 0
        for call in calls:
            active += 1 if call['event'] == 'start' else -1
            maximum = max(active, maximum)
        self.assertEqual(1, maximum)

    def test_failed_component_or_native_pipeline_fails_after_other_gates_finish(self):
        for failure in ('contracts', 'ios', 'macos'):
            with self.subTest(failure=failure):
                (self.root / 'calls.jsonl').unlink(missing_ok=True)
                result, calls = self.run_make('test', FAIL_JOB=failure)
                self.assertNotEqual(0, result.returncode)
                self.assert_all_gates(calls)

    def test_direct_component_invocation_keeps_default_xcode_paths(self):
        result, calls = self.run_make('-C', 'apps/apple', 'test-ios')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        native = next(c for c in calls if c['job'] == 'ios')
        self.assertNotIn('-derivedDataPath', native['args'])

    def test_optional_gradle_arguments_reach_android_gate(self):
        result, calls = self.run_make('test', 'ANDROID_TEST_ARGS=--init-script scripts/ci-gradle.init.gradle')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        android = next(c for c in calls if c['job'] == 'gradlew:apps/android')
        self.assertEqual(ANDROID_TASKS + ['--init-script', 'scripts/ci-gradle.init.gradle'], android['args'])

    def test_invalid_job_count_runs_no_gates(self):
        result, calls = self.run_make('test', 'TEST_JOBS=invalid')
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], calls)


if __name__ == '__main__':
    unittest.main()
