import importlib.util
import copy
import shutil
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('jvm_shards', Path(__file__).parents[1] / 'verify-jvm-shards.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
SHA = 'a' * 40
METHODS = ['first', 'native ACK with spaces', 'native retry', 'stop']
PROFILE = {'version': 1, 'compiler': {**{key: 'a' * 64 for key in m.PROFILE_COMPILER_HASH},
           'gradle': '8.13', 'ndk_revision': '27.1.12297006', 'os': 'Linux', 'arch': 'amd64'},
           'execution': {**{key: 'b' * 64 for key in m.PROFILE_EXECUTION_HASH}, 'max_parallel_forks': 2}}



def xml(path, cases):
    path.parent.mkdir(parents=True, exist_ok=True)
    suite = ET.Element('testsuite', tests=str(len(cases)), failures='0', errors='0', skipped='0')
    for owner, name in cases:
        ET.SubElement(suite, 'testcase', classname=owner, name=name)
    ET.ElementTree(suite).write(path)


class JVMShardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for variant, task in m.TASKS.items():
            for lane in m.LANES:
                folder = self.folder(variant, lane)
                selected = [] if lane == 'remaining' else METHODS[int(lane[-1])::2]
                meta = {'source_sha': SHA, 'run_id': '123', 'attempt': '1', 'variant': variant, 'lane': lane,
                        'task': ':app:' + task, 'native_class': m.NATIVE_CLASS, 'native_methods': METHODS,
                        'selected_methods': selected,
                        'include_patterns': sorted(m.NATIVE_CLASS + '.' + name for name in selected),
                        'exclude_patterns': [m.NATIVE_CLASS] if lane == 'remaining' else [],
                        'qualification_profile': copy.deepcopy(PROFILE)}
                path = folder / f'build/reports/ci/jvm-native-{variant}-{lane}.json'
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps(meta))
                cases = [('OtherTests', 'original remaining test')] if lane == 'remaining' else [(m.NATIVE_CLASS, name) for name in selected]
                xml(folder / f'app/build/test-results/{task}/TEST-lane.xml', cases)
                if variant == 'debug' and lane == 'remaining':
                    for module, module_task in m.MODULES.items():
                        xml(folder / f'{module}/build/test-results/{module_task}/TEST-shared.xml', [('SharedTest', module)])

    def folder(self, variant='debug', lane='native-0'):
        return self.root / f'android-jvm-{variant}-{lane}-results-123-1'

    def metadata(self, **changes):
        path = self.folder() / 'build/reports/ci/jvm-native-debug-native-0.json'
        value = json.loads(path.read_text()) | changes
        path.write_text(json.dumps(value))

    def verify(self): return m.verify(self.root, SHA, '123', '1')

    def test_every_variant_native_half_and_shared_module_is_required(self):
        result = self.verify()
        self.assertEqual(set(result['variants']), set(m.TASKS))
        self.assertEqual(result['shared_modules'], {name: 1 for name in m.MODULES})
        for value in result['variants'].values(): self.assertEqual(value, {'tests': 5, 'passed': 5, 'skipped': 0, 'native_methods': 4})

    def test_java_utf16_order_preserves_supplementary_native_method_names(self):
        methods = m.ordered(['a', '\ue000', '😀', 'native test'])
        self.assertEqual(methods, ['a', 'native test', '😀', '\ue000'])
        for variant, task in m.TASKS.items():
            for lane in m.LANES:
                folder = self.folder(variant, lane)
                path = folder / f'build/reports/ci/jvm-native-{variant}-{lane}.json'
                metadata = json.loads(path.read_text())
                selected = [] if lane == 'remaining' else methods[int(lane[-1])::2]
                metadata.update(native_methods=methods, selected_methods=selected,
                                include_patterns=m.ordered(m.NATIVE_CLASS + '.' + name for name in selected))
                path.write_text(json.dumps(metadata))
                if lane != 'remaining': xml(folder / f'app/build/test-results/{task}/TEST-lane.xml', [(m.NATIVE_CLASS, name) for name in selected])
        self.assertEqual(self.verify()['variants']['debug']['native_methods'], 4)

    def test_stale_source_run_attempt_and_task_metadata_reject(self):
        path = self.folder() / 'build/reports/ci/jvm-native-debug-native-0.json'
        original = path.read_text()
        for key, value in [('source_sha', 'b' * 40), ('run_id', '9'), ('attempt', '2'), ('variant', 'release'), ('lane', 'remaining'), ('task', ':app:other'), ('native_class', 'Other')]:
            path.write_text(original)
            self.metadata(**{key: value})
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify()

    def test_changed_compiled_inventory_or_filter_selection_rejects(self):
        path = self.folder() / 'build/reports/ci/jvm-native-debug-native-0.json'
        original = path.read_text()
        for changes in [{'native_methods': METHODS[:-1]}, {'native_methods': METHODS + [METHODS[-1]]},
                        {'selected_methods': METHODS}, {'include_patterns': ['*']}, {'exclude_patterns': ['OtherTests']}]:
            path.write_text(original)
            self.metadata(**changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError): self.verify()

    def test_missing_lane_and_unexpected_artifact_reject(self):
        self.folder().rename(self.root / 'unexpected')
        with self.assertRaises(ValueError): self.verify()

    def test_missing_or_duplicate_native_method_rejects(self):
        path = self.folder() / 'app/build/test-results/testPlayDebugUnitTest/TEST-lane.xml'
        for names in [[METHODS[0]], [METHODS[0], METHODS[0]], METHODS]:
            xml(path, [(m.NATIVE_CLASS, name) for name in names])
            with self.subTest(names=names), self.assertRaises(ValueError): self.verify()

    def test_native_class_cannot_leak_into_remaining_lane(self):
        path = self.folder(lane='remaining') / 'app/build/test-results/testPlayDebugUnitTest/TEST-lane.xml'
        xml(path, [('OtherTests', 'original remaining test'), (m.NATIVE_CLASS, METHODS[0])])
        with self.assertRaises(ValueError): self.verify()

    def test_missing_shared_module_results_reject(self):
        path = self.folder(lane='remaining') / 'direct-protocol/build/test-results/test/TEST-shared.xml'
        path.unlink()
        with self.assertRaises(ValueError): self.verify()

    def test_failures_and_inconsistent_xml_counts_reject(self):
        path = self.folder() / 'app/build/test-results/testPlayDebugUnitTest/TEST-lane.xml'
        original = path.read_bytes()
        for mode in ('failure', 'count', 'skip-count'):
            path.write_bytes(original)
            tree = ET.parse(path)
            if mode == 'failure': ET.SubElement(tree.getroot().find('testcase'), 'failure')
            elif mode == 'count': tree.getroot().set('tests', '9')
            else: tree.getroot().set('skipped', '1')
            tree.write(path)
            with self.subTest(mode=mode), self.assertRaises(ValueError): self.verify()

    def test_explicit_existing_skip_is_retained(self):
        path = self.folder() / 'app/build/test-results/testPlayDebugUnitTest/TEST-lane.xml'
        tree = ET.parse(path)
        tree.getroot().set('skipped', '1')
        ET.SubElement(tree.getroot().find('testcase'), 'skipped')
        tree.write(path)
        self.assertEqual(self.verify()['variants']['debug']['skipped'], 1)

    def retry(self, variant='debug', lane='native-0', attempt='2'):
        old = self.folder(variant, lane)
        new = self.root / f'android-jvm-{variant}-{lane}-results-123-{attempt}'
        shutil.copytree(old, new)
        path = new / f'build/reports/ci/jvm-native-{variant}-{lane}.json'
        value = json.loads(path.read_text())
        value['attempt'] = attempt
        path.write_text(json.dumps(value))
        return new

    def test_targeted_retry_preserves_every_case_and_records_real_lane_attempts(self):
        original = self.verify()
        self.retry()
        result = m.verify(self.root, SHA, '123', '2')
        self.assertEqual(result['variants'], original['variants'])
        self.assertEqual(result['shared_modules'], original['shared_modules'])
        self.assertEqual(result['lane_attempts']['debug:native-0'], '2')
        self.assertEqual(sum(value == '1' for value in result['lane_attempts'].values()), 8)
        self.assertEqual(result['compiler_profile'], PROFILE['compiler'])

    def test_latest_failed_retry_never_falls_back_to_older_passing_results(self):
        retry = self.retry()
        path = retry / 'app/build/test-results/testPlayDebugUnitTest/TEST-lane.xml'
        tree = ET.parse(path)
        ET.SubElement(tree.getroot().find('testcase'), 'failure')
        tree.write(path)
        with self.assertRaises(ValueError):
            m.verify(self.root, SHA, '123', '2')

    def test_future_attempt_and_other_run_artifacts_are_rejected(self):
        retry = self.retry(attempt='3')
        with self.assertRaises(ValueError):
            m.verify(self.root, SHA, '123', '2')
        retry.rename(self.root / retry.name.replace('results-123-', 'results-124-'))
        with self.assertRaises(ValueError):
            m.verify(self.root, SHA, '123', '3')

    def test_changed_compiler_dependencies_flags_or_environment_reject_reuse(self):
        retry = self.retry()
        path = retry / 'build/reports/ci/jvm-native-debug-native-0.json'
        original = path.read_text()
        for section, fields in [('compiler', m.PROFILE_COMPILER_HASH | m.PROFILE_TEXT),
                                ('execution', m.PROFILE_EXECUTION_HASH | {'max_parallel_forks'})]:
            for key in fields:
                with self.subTest(section=section, key=key):
                    value = json.loads(original)
                    previous = value['qualification_profile'][section][key]
                    value['qualification_profile'][section][key] = 1 if isinstance(previous, int) else ('c' * 64 if 'sha256' in key else 'different')
                    path.write_text(json.dumps(value))
                    with self.assertRaises(ValueError):
                        m.verify(self.root, SHA, '123', '2')

    def test_missing_or_malformed_profile_is_never_reused(self):
        for profile in [None, {}, {'version': True, 'compiler': {}, 'execution': {}},
                        dict(PROFILE, compiler={}), dict(PROFILE, execution={})]:
            self.metadata(qualification_profile=profile)
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                self.verify()

    def test_variant_execution_profiles_are_independent_but_its_lanes_must_match(self):
        for lane in m.LANES:
            path = self.folder('release', lane) / f'build/reports/ci/jvm-native-release-{lane}.json'
            value = json.loads(path.read_text())
            value['qualification_profile']['execution']['classpath_sha256'] = 'c' * 64
            path.write_text(json.dumps(value))
        self.assertEqual(self.verify()['execution_profiles']['release']['classpath_sha256'], 'c' * 64)

    def test_workflow_keeps_all_nine_lanes_and_shared_lint_package_gates(self):
        workflow = Path(__file__).resolve().parents[4] / '.github/workflows/android-ci.yml'
        source = workflow.read_text()
        worker = source.split('  jvm-tests:\n', 1)[1].split('  # Preserve', 1)[0]
        self.assertEqual(worker.count('            lane:'), 9)
        for name in m.LANES: self.assertEqual(worker.count('            lane: ' + name), 3)
        self.assertIn('fail-fast: false', worker)
        self.assertIn('--init-script scripts/ci-jvm-shards.init.gradle', worker)
        self.assertIn("debug:remaining", worker)
        self.assertEqual(worker.count("matrix.variant == 'debug' && matrix.lane == 'remaining'"), 2)
        for command in [':healthmd-core:testDebugUnitTest', ':wearable-contract:test', ':direct-protocol:test', ':app:lintPlayDebug', 'test_verify_google_play_generated_apk_evidence.sh --phone-only']:
            self.assertIn(command, worker)
        gate = source.split('  test:\n', 1)[1].split('  instrumentation-shards:\n', 1)[0]
        self.assertIn('needs: [changes, jvm-tests]', gate)
        self.assertIn('test "$JVM_RESULT" = success', gate)
        self.assertIn('verify-jvm-shards.py', gate)
        self.assertIn('pattern: android-jvm-*-results-${{ github.run_id }}-*', gate)
        self.assertNotIn('continue-on-error', worker + gate)


if __name__ == '__main__': unittest.main()
