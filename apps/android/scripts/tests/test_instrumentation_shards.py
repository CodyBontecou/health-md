"""Reject incomplete or misleading reports at the stable instrumentation gate."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-ci-instrumentation-shards.py'
spec = importlib.util.spec_from_file_location('shards', SCRIPT)
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)


class ShardReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for index in range(6):
            for kind in ('play',) + (('core', 'direct_e2e') if index == 0 else ()):
                self.report(index, kind)

    def report(self, index, kind, *, name=None, failed=False, skipped=False, count=1):
        base = self.root / f'android-instrumentation-12-1-shard-{index}'
        paths = {'core': 'healthmd-core/build/outputs/androidTest-results/connected/debug',
                 'direct_e2e': 'app/build/outputs/androidTest-results/connected/e2e/flavors/play',
                 'play': 'app/build/outputs/androidTest-results/connected/debug/flavors/play',
                 'fdroid': 'app/build/outputs/androidTest-results/connected/debug/flavors/fdroid'}
        p = base / paths[kind] / 'TEST.xml'
        p.parent.mkdir(parents=True, exist_ok=True)
        suite = ET.Element('testsuite', tests=str(count), failures=str(int(failed)), errors='0')
        case = ET.SubElement(suite, 'testcase', classname='ExampleTest', name=name or f'test{index}')
        if failed:
            ET.SubElement(case, 'failure')
        if skipped:
            ET.SubElement(case, 'skipped')
        ET.ElementTree(suite).write(p)
        return p

    def test_full_distinct_union_and_skips_are_retained(self):
        self.report(2, 'play', skipped=True)
        result = shards.verify(self.root, '12', '1')
        self.assertEqual((8, 7, 1), (result['tests'], result['passed'], result['skipped']))
        self.assertEqual({0, 1, 2, 3, 4, 5}, {x['shard'] for x in result['cases']})

    def test_missing_artifact_report_or_required_group_fails(self):
        for kind in ('play', 'core', 'direct_e2e'):
            with self.subTest(kind=kind):
                p = self.report(0, kind)
                data = p.read_bytes()
                p.unlink()
                with self.assertRaisesRegex(ValueError, 'groups mismatch'):
                    shards.verify(self.root, '12', '1')
                p.write_bytes(data)
        (self.root / 'android-instrumentation-12-1-shard-3').rename(self.root / 'wrong-attempt')
        with self.assertRaisesRegex(ValueError, 'artifact set mismatch'):
            shards.verify(self.root, '12', '1')

    def test_each_of_the_six_worker_artifacts_is_required(self):
        for index in range(6):
            with self.subTest(shard=index):
                folder = self.root / f'android-instrumentation-12-1-shard-{index}'
                hidden = self.root.parent / (self.root.name + '-held')
                folder.rename(hidden)
                try:
                    with self.assertRaisesRegex(ValueError, 'artifact set mismatch'):
                        shards.verify(self.root, '12', '1')
                finally:
                    hidden.rename(folder)

    def test_duplicate_case_across_shards_fails(self):
        self.report(3, 'play', name='test0')
        with self.assertRaisesRegex(ValueError, 'Duplicate test'):
            shards.verify(self.root, '12', '1')

    def test_failed_case_and_inconsistent_summary_fail(self):
        self.report(0, 'play', failed=True)
        with self.assertRaisesRegex(ValueError, 'Failed test'):
            shards.verify(self.root, '12', '1')
        self.report(0, 'play', count=2)
        with self.assertRaisesRegex(ValueError, 'count disagrees'):
            shards.verify(self.root, '12', '1')

    def test_empty_report_fails(self):
        self.report(0, 'core').write_text('<testsuite tests="0"/>')
        with self.assertRaisesRegex(ValueError, 'Empty test'):
            shards.verify(self.root, '12', '1')

    def test_core_and_direct_e2e_must_run_once_on_shard_zero(self):
        self.report(1, 'core', name='extra')
        with self.assertRaisesRegex(ValueError, 'groups mismatch'):
            shards.verify(self.root, '12', '1')

class PartialRetryTests(unittest.TestCase):
    report = ShardReportTests.report
    source_sha = 'a' * 40

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for index in range(6):
            for kind in ('play',) + (('core', 'direct_e2e') if index == 0 else ()):
                self.report(index, kind)
            self.receipt(index, 1)

    def receipt(self, index, artifact_attempt, **changes):
        import json
        folder = self.root / f'android-instrumentation-12-{artifact_attempt}-shard-{index}'
        path = folder / 'build/logs/instrumentation-source.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        value = dict(version=1, run_id='12', attempt=str(artifact_attempt), shard=index, source_sha=self.source_sha)
        value.update(changes)
        path.write_text(json.dumps(value))
        return path

    def retry(self, index=4):
        import shutil
        original = self.root / f'android-instrumentation-12-1-shard-{index}'
        current = self.root / f'android-instrumentation-12-2-shard-{index}'
        shutil.copytree(original, current)
        self.receipt(index, 2)
        return current

    def verify(self):
        return shards.verify(self.root, '12', '2', source_sha=self.source_sha)

    def test_partial_retry_retains_every_successful_shard_and_original_case_checks(self):
        self.retry()
        result = self.verify()
        self.assertEqual((8, 8, 0), (result['tests'], result['passed'], result['skipped']))
        self.assertEqual({'0': '1', '1': '1', '2': '1', '3': '1', '4': '2', '5': '1'}, result['shard_attempts'])
        self.assertEqual(self.source_sha, result['source_sha'])
        self.assertEqual({0, 1, 2, 3, 4, 5}, {case['shard'] for case in result['cases']})

    def test_every_shard_and_source_receipt_is_still_required(self):
        import shutil
        current = self.retry()
        receipt = current / 'build/logs/instrumentation-source.json'
        receipt.unlink()
        with self.assertRaises((ValueError, OSError)):
            self.verify()
        self.receipt(4, 2)
        shutil.rmtree(self.root / 'android-instrumentation-12-1-shard-0')
        with self.assertRaises(ValueError):
            self.verify()

    def test_wrong_source_run_attempt_or_shard_receipt_is_rejected(self):
        self.retry()
        for changes in ({'source_sha': 'b' * 40}, {'run_id': '13'}, {'attempt': '1'}, {'shard': 3}):
            with self.subTest(changes=changes):
                self.receipt(4, 2, **changes)
                with self.assertRaises(ValueError):
                    self.verify()
                self.receipt(4, 2)

    def test_foreign_future_and_unknown_shard_artifacts_are_rejected(self):
        self.retry()
        for name in ('android-instrumentation-13-1-shard-0',
                     'android-instrumentation-12-3-shard-0',
                     'android-instrumentation-12-1-shard-6', 'unexpected'):
            with self.subTest(name=name):
                folder = self.root / name
                folder.mkdir()
                try:
                    with self.assertRaises(ValueError):
                        self.verify()
                finally:
                    folder.rmdir()

    def test_failed_latest_report_cannot_fall_back_to_older_success(self):
        current = self.retry()
        report = next(current.glob('**/TEST.xml'))
        report.write_text('<testsuite tests="1" failures="1"><testcase classname="ExampleTest" name="test4"><failure/></testcase></testsuite>')
        with self.assertRaisesRegex(ValueError, 'Failed test'):
            self.verify()

    def test_duplicate_case_in_retry_is_still_rejected(self):
        current = self.retry()
        report = next(current.glob('**/TEST.xml'))
        report.write_text('<testsuite tests="1"><testcase classname="ExampleTest" name="test0"/></testsuite>')
        with self.assertRaisesRegex(ValueError, 'Duplicate test'):
            self.verify()

    def test_cli_partial_retry_verifies_source_and_retains_complete_inventory(self):
        import json
        import subprocess
        import sys
        current = self.retry()
        command = [sys.executable, str(SCRIPT), '--reports', str(self.root),
                   '--run-id', '12', '--attempt', '2', '--source-sha', self.source_sha]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        inventory = json.loads((self.root / 'case-inventory.json').read_text())
        self.assertEqual(8, inventory['tests'])
        self.assertEqual('2', inventory['shard_attempts']['4'])
        receipt = current / 'build/logs/instrumentation-source.json'
        result = subprocess.run([sys.executable, str(SCRIPT), '--write-receipt', str(receipt),
                                 '--run-id', '12', '--attempt', '2', '--shard', '4',
                                 '--source-sha', 'b' * 40], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotEqual(0, subprocess.run(command, capture_output=True, text=True).returncode)

    def test_legacy_mode_still_rejects_mixed_attempts_without_source_receipts(self):
        self.retry()
        with self.assertRaisesRegex(ValueError, 'artifact set mismatch'):
            shards.verify(self.root, '12', '2')

    def test_production_receipt_writer_records_exact_source_and_attempt(self):
        import json
        path = self.root / 'written.json'
        shards.write_source_receipt(path, '12', '2', 4, self.source_sha)
        self.assertEqual(dict(version=1, run_id='12', attempt='2', shard=4, source_sha=self.source_sha),
                         json.loads(path.read_text()))
        for bad in ('', 'not-a-sha', 'g' * 40):
            with self.assertRaises(ValueError):
                shards.write_source_receipt(path, '12', '2', 4, bad)


class ShardWorkflowTests(unittest.TestCase):
    def test_all_six_workers_and_stable_release_gate_remain_mandatory(self):
        workflow = (SCRIPT.parents[3] / '.github/workflows/android-ci.yml').read_text()
        workers = workflow.split('\n  instrumentation-shards:\n', 1)[1].split('\n  instrumentation:\n', 1)[0]
        aggregate = workflow.split('\n  instrumentation:\n', 1)[1].split('\n  fdroid:\n', 1)[0]
        self.assertIn('fail-fast: false', workers)
        self.assertEqual(2, workers.count('./scripts/run-ci-gradle.sh --no-daemon --max-workers=2'))
        self.assertNotIn('./gradlew --no-daemon', workers)
        for selector in (':healthmd-core:prepareRustDebug', ':app:assemblePlayDebug',
                         ':app:assemblePlayDebugAndroidTest', ':healthmd-core:assembleDebugAndroidTest',
                         ':app:assemblePlayE2e', ':app:assemblePlayE2eAndroidTest'):
            self.assertIn(selector, workers)
        self.assertIn('timeout 90 ./scripts/prepare-ci-emulator.sh', workers)
        self.assertIn('./scripts/run-ci-instrumentation.sh', workers)
        self.assertIn('./scripts/run-direct-cli-ui-e2e.sh', workers)
        self.assertIn('shard: [0, 1, 2, 3, 4, 5]', workers)
        self.assertIn("HEALTHMD_ANDROID_SHARD_COUNT: '6'", workers)
        self.assertIn('HEALTHMD_ANDROID_SHARD_INDEX: ${{ matrix.shard }}', workers)
        self.assertIn('if [ "${{ matrix.shard }}" = 0 ]; then', workers)
        self.assertIn('HEALTHMD_ANDROID_ACCESSIBILITY_MATRIX: ${{ needs.changes.outputs.accessibility_matrix }}', workers)
        self.assertIn('needs: [changes, instrumentation-shards]', aggregate)
        self.assertIn('name: Emulator instrumentation and direct E2E', aggregate)
        self.assertIn('test "$SHARDS_RESULT" = success', aggregate)
        self.assertIn('verify-ci-instrumentation-shards.py', aggregate)
        self.assertNotIn('merge-multiple: true', aggregate)
        self.assertIn('name: android-instrumentation-${{ github.run_id }}-${{ github.run_attempt }}\n', aggregate)
        self.assertIn('INSTRUMENTATION_RESULT: ${{ needs.instrumentation.result }}', workflow)
        release = (SCRIPT.parents[3] / '.github/workflows/android-release.yml').read_text()
        self.assertIn('"Emulator instrumentation and direct E2E"', release)


    def test_partial_retry_download_and_verification_remain_bound_to_same_run_and_source(self):
        workflow = (SCRIPT.parents[3] / '.github/workflows/android-ci.yml').read_text()
        workers = workflow.split('\n  instrumentation-shards:\n', 1)[1].split('\n  instrumentation:\n', 1)[0]
        aggregate = workflow.split('\n  instrumentation:\n', 1)[1].split('\n  fdroid:\n', 1)[0]
        self.assertIn('pattern: android-instrumentation-${{ github.run_id }}-*-shard-*', aggregate)
        self.assertIn('test "$SHARDS_RESULT" = success', aggregate)
        self.assertIn('--source-sha "$(git rev-parse HEAD)"', aggregate)
        self.assertIn('--source-sha "$(git rev-parse HEAD)"', workers)
        self.assertIn('--write-receipt build/logs/instrumentation-source.json', workers)
        self.assertIn('apps/android/build/logs/instrumentation-source.json', workers)
        self.assertIn("--attempt '${{ github.run_attempt }}'", aggregate)
        self.assertNotIn('continue-on-error', aggregate)


if __name__ == '__main__':
    unittest.main()
