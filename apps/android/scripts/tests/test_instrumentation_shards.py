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
        for index in range(4):
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
        self.assertEqual((6, 5, 1), (result['tests'], result['passed'], result['skipped']))
        self.assertEqual({0, 1, 2, 3}, {x['shard'] for x in result['cases']})

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

class ShardWorkflowTests(unittest.TestCase):
    def test_all_four_workers_and_stable_release_gate_remain_mandatory(self):
        workflow = (SCRIPT.parents[3] / '.github/workflows/android-ci.yml').read_text()
        workers = workflow.split('\n  instrumentation-shards:\n', 1)[1].split('\n  instrumentation:\n', 1)[0]
        aggregate = workflow.split('\n  instrumentation:\n', 1)[1].split('\n  fdroid:\n', 1)[0]
        self.assertIn('fail-fast: false', workers)
        self.assertIn('shard: [0, 1, 2, 3]', workers)
        self.assertIn("HEALTHMD_ANDROID_SHARD_COUNT: '4'", workers)
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


if __name__ == '__main__':
    unittest.main()
