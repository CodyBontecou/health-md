"""Cloud security stays blocking in the existing portable lane; no SDKs or services."""
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMMANDS = [
    'ci --ignore-scripts --no-audit --no-fund',
    'run typecheck', 'run typecheck:vm',
    'exec -- vitest run --maxWorkers=1',
    'run verify:production-safety', 'audit --audit-level=moderate',
]


class CloudRoutingTests(unittest.TestCase):
    def test_wake_and_cloud_overlap_and_both_failures_remain_blocking(self):
        for failure in ('none', 'wake', 'cloud'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for component in ('wake', 'cloud'):
                    (root / 'apps' / component).mkdir(parents=True)
                (root / 'scripts/ci').mkdir(parents=True)
                (root / 'scripts/ci/cloud.sh').write_text((ROOT / 'scripts/ci/cloud.sh').read_text())
                (root / 'bin').mkdir()
                npm = root / 'bin/npm'
                # Each checker must observe the other before it can finish.
                # Sequential execution fails deterministically at that barrier.
                npm.write_text('''#!/usr/bin/env bash
set -eu
component=${PWD##*/}
touch "$FIXTURE_ROOT/$component.started"
if [[ "$component" == wake ]]; then other=cloud; else other=wake; fi
for ((attempt=0; attempt<100; attempt++)); do
  [[ -f "$FIXTURE_ROOT/$other.started" ]] && break
  sleep 0.01
done
[[ -f "$FIXTURE_ROOT/$other.started" ]] || exit 31
if [[ "$*" == ci* && "$component" == "$FAIL_COMPONENT" ]]; then
  touch "$FIXTURE_ROOT/$component.finished"
  exit 23
fi
if [[ "$*" == 'run check' || "$*" == 'audit --audit-level=moderate' ]]; then
  touch "$FIXTURE_ROOT/$component.finished"
fi
''')
                npm.chmod(0o755)
                result = subprocess.run(['bash', str(ROOT / 'scripts/ci/wake.sh')],
                    cwd=root, capture_output=True, text=True, timeout=10,
                    env={**os.environ, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                         'FIXTURE_ROOT': str(root), 'FAIL_COMPONENT': failure})
                self.assertEqual(result.returncode, 0 if failure == 'none' else 23, result.stderr)
                self.assertTrue((root / 'wake.finished').exists())
                self.assertTrue((root / 'cloud.finished').exists())

    def test_every_cloud_stage_runs_in_its_component_and_failure_stops_the_lane(self):
        for failed_stage in range(7):
            with self.subTest(failed_stage=failed_stage), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'apps/cloud').mkdir(parents=True)
                (root / 'bin').mkdir()
                npm = root / 'bin/npm'
                npm.write_text('''#!/usr/bin/env bash
set -eu
[[ "$PWD" == "$FIXTURE_ROOT/apps/cloud" ]]
printf '%s\\n' "$*" >> "$CALLS"
count=$(wc -l < "$CALLS")
if [[ "$count" -eq "$FAIL_STAGE" ]]; then exit 23; fi
''')
                npm.chmod(0o755)
                calls = root / 'calls'
                result = subprocess.run(['bash', str(ROOT / 'scripts/ci/cloud.sh')],
                    cwd=root, capture_output=True, text=True, timeout=10,
                    env={**os.environ, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                         'FIXTURE_ROOT': str(root), 'CALLS': str(calls), 'FAIL_STAGE': str(failed_stage)})
                self.assertEqual(result.returncode, 23 if failed_stage else 0, result.stderr)
                self.assertEqual(calls.read_text().splitlines(), COMMANDS[:failed_stage or 6])

    def test_six_groups_and_deadlines_remain_unchanged_with_cloud_in_wake(self):
        spec = importlib.util.spec_from_file_location('portable_ci_run', ROOT / 'scripts/ci/run.py')
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        self.assertEqual(set(runner.GROUPS), {'contracts', 'core', 'cli', 'practice', 'wake', 'consumer'})
        self.assertEqual(runner.GROUPS['wake'], ['bash', 'scripts/ci/wake.sh'])
        wake = (ROOT / 'scripts/ci/wake.sh').read_text()
        self.assertIn('bash scripts/ci/cloud.sh', wake)
        self.assertIn('cd apps/wake', wake)
        self.assertIn('npm run check', wake)
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('timeout-minutes: 2', workflow)
        for name in ('app-icon.png', 'favicon.png'):
            self.assertIn('          /apps/cloud/public/' + name, workflow)
        for forbidden in ('continue-on-error', 'wrangler deploy', '--testNamePattern', '--exclude'):
            self.assertNotIn(forbidden, (ROOT / 'scripts/ci/cloud.sh').read_text())

    def test_actual_sparse_checkout_retains_security_fixture_assets_only(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        patterns = workflow.split("<<'PATTERNS'\n", 1)[1].split('          PATTERNS', 1)[0]
        patterns = '\n'.join(line.removeprefix('          ') for line in patterns.splitlines()) + '\n'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.run(['git', *args], cwd=root, check=True,
                                      capture_output=True, text=True, timeout=10)
            git('init', '-q')
            for name in ('apps/cloud/public/app-icon.png', 'apps/cloud/public/favicon.png',
                         'apps/website/large.png', 'apps/cloud/src/auth.ts'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic')
            git('add', '.')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                '-c', 'commit.gpgsign=false', 'commit', '-qm', 'synthetic sparse fixture')
            git('config', 'core.sparseCheckout', 'true')
            (root / '.git/info/sparse-checkout').write_text(patterns)
            git('read-tree', '-mu', 'HEAD')
            self.assertTrue((root / 'apps/cloud/public/app-icon.png').is_file())
            self.assertTrue((root / 'apps/cloud/public/favicon.png').is_file())
            self.assertTrue((root / 'apps/cloud/src/auth.ts').is_file())
            self.assertFalse((root / 'apps/website/large.png').exists())

    def test_broad_diagnostics_are_manual_only_and_preserve_checks(self):
        workflow = (ROOT / '.github/workflows/cloud-ci.yml').read_text()
        triggers = workflow.split('on:\n', 1)[1].split('\npermissions:', 1)[0]
        self.assertEqual(re.findall(r'^  ([a-z_]+):', triggers, re.M), ['workflow_dispatch'])
        self.assertNotIn('continue-on-error', workflow)
        for command in ('npm run check', 'npm run verify:production-safety', 'npm run test:smoke',
                        'npm run build:vm', '--config wrangler.ingest.toml',
                        '--config wrangler.account.toml', '--config wrangler.maintenance.toml',
                        'npm audit --audit-level=moderate'):
            self.assertIn(command, workflow)
        for line in workflow.splitlines():
            if 'wrangler deploy' in line:
                self.assertIn('--dry-run', line)


if __name__ == '__main__':
    unittest.main()
