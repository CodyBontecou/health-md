"""Coverage and failure contracts for nightly UI fan-out."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parents[2]
sys.path.insert(0, str(SCRIPTS))


class TopologyTests(unittest.TestCase):
    def test_unit_job_does_not_wait_for_or_run_ui_suite(self):
        text = (REPO / '.github/workflows/apple-nightly.yml').read_text()
        unit = text.split('  extended-ios:\n', 1)[1].split('\n  extended-macos:', 1)[0]
        self.assertIn('make test-ios CORE_RUST_PREPARE=:', unit)
        self.assertNotIn('HealthMd-UITests-iOS', unit)
        self.assertNotIn('-only-testing', unit)
        self.assertNotIn('-skip-testing', unit)


    def test_build_once_enumerates_unfiltered_bundle_before_partitioning(self):
        text = (REPO / '.github/workflows/apple-nightly.yml').read_text()
        build = text.split('  prepare-ui:\n', 1)[1].split('\n  ui-shards:', 1)[0]
        self.assertEqual(build.count('xcodebuild build-for-testing'), 1)
        self.assertIn('-scheme HealthMd-UITests-iOS', build)
        self.assertIn('ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES', build)
        self.assertIn('-enumerate-tests', build)
        self.assertNotIn('-only-testing', build)
        self.assertNotIn('-skip-testing', build)
        self.assertLess(build.index('validate_ios_ui_xctestrun.py'), build.index('-enumerate-tests'))
        self.assertLess(build.index('-enumerate-tests'), build.index('apple_nightly_ui.py plan'))
        self.assertLess(build.index('apple_nightly_ui.py plan'), build.index('apple_nightly_ui.py pack'))
        self.assertIn('scripts/check-warnings.sh', build)

    def test_all_workers_and_exact_inventory_gate_are_required(self):
        text = (REPO / '.github/workflows/apple-nightly.yml').read_text()
        workers = text.split('  ui-shards:\n', 1)[1].split('\n  ui-inventory:', 1)[0]
        self.assertIn('needs: prepare-shared-core', workers)
        self.assertNotIn('extended-ios', workers)
        self.assertIn('shard: [1, 2, 3]', workers)
        builder = text.split('  prepare-ui:\n', 1)[1].split('\n  ui-shards:', 1)[0]
        self.assertIn('--shard 0', builder)
        self.assertIn('name: nightly-ui-inventory-0', builder)
        self.assertIn('name: nightly-ui-results-0', builder)
        self.assertLess(builder.index('Upload prepared UI products'),
                        builder.index('Prepare builder simulator and run UI shard zero'))
        self.assertIn('fail-fast: false', workers)
        self.assertNotIn('continue-on-error', workers)
        gate = text.split('  ui-inventory:\n', 1)[1]
        self.assertIn('needs: [prepare-ui, ui-shards]', gate)
        self.assertIn('if: ${{ !cancelled() }}', gate)
        self.assertIn('needs.ui-shards.result', gate)
        self.assertIn('apple_nightly_ui.py aggregate', gate)
        self.assertIn('nightly-ui-inventory-*', gate)


# Every SDK-free test here exercises the real planner, artifact or process boundary.
import copy
import contextlib
import io
import os
import plistlib
from unittest.mock import patch
from apple_nightly_ui import (SHARDS, aggregate, audit_shard, cases, identifiers,
                              main, pack, plan, ready_simulator, start_simulator, unpack, validate_plan, wait_products)
from test_ios_ui_build_contract import make_products
from validate_ios_ui_xctestrun import BUILD_MARKER

SHA = 'a' * 40
TESTS = [f'HealthMdUITests/Journey{i % 5}Tests/testCase{i}' for i in range(20)]


def enumeration(tests):
    return {'errors': [], 'values': [{'disabledTests': [],
                                    'enabledTests': [{'identifier': t} for t in tests]}]}


def transcript(tests, result='passed'):
    return '\n'.join(f"Test Case '-[HealthMdUITests.{t.split('/')[1]} {t.split('/')[2]}]' {result} (1.000 seconds)."
                     for t in tests) + '\n** TEST EXECUTE SUCCEEDED **\n'


class SimulatorOverlapTests(unittest.TestCase):
    def test_only_shutdown_simulator_needs_a_nonblocking_boot_request(self):
        identifier = 'A' * 8 + '-' + 'B' * 4 + '-' + 'C' * 4 + '-' + 'D' * 4 + '-' + 'E' * 12
        for state in ('Shutdown', 'Booting', 'Booted'):
            devices = {'devices': {'iOS': [{'udid': identifier, 'state': state}]}}
            with self.subTest(state=state), patch('apple_nightly_ui.subprocess.check_output',
                    return_value=json.dumps(devices)), patch('apple_nightly_ui.subprocess.run') as boot, \
                    contextlib.redirect_stdout(io.StringIO()):
                start_simulator('platform=iOS Simulator,id=' + identifier)
                if state == 'Shutdown':
                    boot.assert_called_once_with(['xcrun', 'simctl', 'boot', identifier], check=True)
                else:
                    boot.assert_not_called()
        with self.assertRaises(ValueError):
            start_simulator('platform=iOS,id=physical-device')
        with patch('apple_nightly_ui.subprocess.check_output', return_value='{"devices":{}}'), \
             self.assertRaises(ValueError):
            start_simulator('platform=iOS Simulator,id=' + identifier)

    def test_readiness_waits_for_boot_and_starts_files_before_xctest(self):
        destination = 'platform=iOS Simulator,id=' + 'A' * 36
        with patch('apple_nightly_ui.start_simulator') as start, \
             patch('apple_nightly_ui.subprocess.run') as run:
            ready_simulator(destination)
            start.assert_called_once_with(destination)
            self.assertEqual([call.args[0] for call in run.call_args_list], [
                ['xcrun', 'simctl', 'bootstatus', 'A' * 36, '-b'],
                ['xcrun', 'simctl', 'launch', 'A' * 36, 'com.apple.DocumentsApp']])
            self.assertTrue(all(call.kwargs['check'] for call in run.call_args_list))
        text = (REPO / '.github/workflows/apple-nightly.yml').read_text()
        worker = text.split('  ui-shards:\n', 1)[1].split('\n  ui-inventory:', 1)[0]
        self.assertLess(worker.index('Wait for simulator and native Files providers'),
                        worker.index('Wait for exact-run UI products'))
        self.assertLess(worker.index('Wait for exact-run UI products'),
                        worker.index('Download exact-run prepared UI products'))
        self.assertLess(worker.index('Wait for simulator and native Files providers'),
                        worker.index('Run and audit assigned UI shard'))

    def test_prepare_boot_overlaps_compilation_and_worker_boot_precedes_download(self):
        text = (REPO / '.github/workflows/apple-nightly.yml').read_text()
        prepare = text.split('  prepare-ui:\n', 1)[1].split('\n  ui-shards:', 1)[0]
        worker = text.split('  ui-shards:\n', 1)[1].split('\n  ui-inventory:', 1)[0]
        self.assertLess(prepare.index('Start simulator before independent work'),
                        prepare.index('xcodebuild build-for-testing'))
        self.assertLess(worker.index('Start simulator before independent work'),
                        worker.index('Download exact-run prepared UI products'))
        self.assertIn('steps.ui_simulator.outputs.ios_destination', prepare)
        self.assertIn('steps.ui_simulator.outputs.ios_destination', worker)
        self.assertNotIn('bootstatus', prepare)
        self.assertNotIn('bootstatus', worker)


class ProductWaitTests(unittest.TestCase):
    def test_waits_only_for_current_source_run_and_never_retries_tests(self):
        responses = [
            {'head_sha': SHA}, {'artifacts': []},
            {'jobs': [{'name': 'prepare-ui', 'status': 'in_progress'}]},
            {'artifacts': [{'name': 'nightly-ui-products', 'expired': False}]}]
        with patch('apple_nightly_ui.subprocess.check_output',
                   side_effect=map(json.dumps, responses)) as api, \
             patch('apple_nightly_ui.time.sleep') as sleep, contextlib.redirect_stdout(io.StringIO()):
            wait_products('owner/repo', 123, SHA)
            sleep.assert_called_once_with(15)
            for call in api.call_args_list:
                self.assertEqual(call.args[0][:2], ['gh', 'api'])
                self.assertTrue(call.args[0][2].startswith('repos/owner/repo/actions/runs/123'))

    def test_wrong_source_failed_producer_and_deadline_are_fatal(self):
        scenarios = [
            [{'head_sha': 'b' * 40}],
            [{'head_sha': SHA}, {'artifacts': []},
             {'jobs': [{'name': 'prepare-ui', 'status': 'completed', 'conclusion': 'failure'}]}],
            [{'head_sha': SHA}, {'artifacts': []}, {'jobs': []}],
        ]
        for responses in scenarios:
            with self.subTest(responses=responses), \
                 patch('apple_nightly_ui.subprocess.check_output', side_effect=map(json.dumps, responses)), \
                 patch('apple_nightly_ui.time.sleep') as sleep, self.assertRaises(ValueError):
                wait_products('owner/repo', 123, SHA, timeout=0)
            sleep.assert_not_called()


class PartitionTests(unittest.TestCase):
    def setUp(self):
        self.value = plan(TESTS, {TESTS[0]: 90}, SHA)

    def test_compiled_inventory_includes_new_tests_without_editing_weights(self):
        tests = TESTS + ['HealthMdUITests/NewJourney/testFutureCase()']
        actual = identifiers(enumeration(tests))
        self.assertIn('HealthMdUITests/NewJourney/testFutureCase', actual)
        value = plan(actual, {}, SHA)
        validate_plan(value, SHA)
        self.assertEqual(sorted(t for group in value['shards'] for t in group), sorted(actual))
        self.assertTrue(all(value['shards']))

    def test_each_complete_class_remains_on_one_worker_in_canonical_order(self):
        value = plan(TESTS, {TESTS[0]: 90}, SHA)
        validate_plan(value, SHA)
        for cls in {test.split('/')[1] for test in TESTS}:
            groups = [group for group in value['shards'] if any('/' + cls + '/' in t for t in group)]
            self.assertEqual(len(groups), 1)
            self.assertEqual([t for t in groups[0] if '/' + cls + '/' in t],
                             sorted(t for t in TESTS if '/' + cls + '/' in t))
        bad = copy.deepcopy(value)
        source = next(i for i, group in enumerate(bad['shards']) if len(group) > 1)
        bad['shards'][(source + 1) % SHARDS].append(bad['shards'][source].pop())
        with self.assertRaises(ValueError):
            validate_plan(bad, SHA)

    def test_partial_disabled_or_duplicate_compiled_enumeration_fails(self):
        for mutation in ('error', 'disabled', 'duplicate', 'unexpected'):
            value = enumeration(TESTS)
            if mutation == 'error': value['errors'] = ['collection failed']
            if mutation == 'disabled': value['values'][0]['disabledTests'] = [{'identifier': TESTS[0]}]
            if mutation == 'duplicate': value['values'][0]['enabledTests'].append({'identifier': TESTS[0]})
            if mutation == 'unexpected': value['values'][0]['enabledTests'].append({'identifier': 'OtherTests/Other/testWrong'})
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                identifiers(value)

    def test_empty_enumeration_and_duplicate_plans_fail(self):
        with self.assertRaises(ValueError):
            identifiers({'values': []})
        with self.assertRaises(ValueError):
            plan(TESTS + TESTS, {}, SHA)
        for mutation in ('missing', 'duplicate', 'source', 'empty'):
            value = copy.deepcopy(self.value)
            if mutation == 'missing': value['shards'][0].pop()
            if mutation == 'duplicate': value['shards'][1].append(value['shards'][0][0])
            if mutation == 'source': value['source_sha'] = 'b' * 40
            if mutation == 'empty': value['tests'] = []
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate_plan(value, SHA)

    def test_shard_and_aggregate_require_every_case_once_and_passed(self):
        receipts = [audit_shard(self.value, i, transcript(group))
                    for i, group in enumerate(self.value['shards'])]
        self.assertEqual(aggregate(self.value, receipts)['passed'], len(TESTS))
        for result in ('failed', 'skipped'):
            with self.subTest(result=result), self.assertRaises(ValueError):
                audit_shard(self.value, 0, transcript(self.value['shards'][0], result))
        group = self.value['shards'][0]
        for tests in (group[:-1], group + group[:1], group + ['HealthMdUITests/Other/testWrong']):
            with self.assertRaises(ValueError):
                audit_shard(self.value, 0, transcript(tests))
        with self.assertRaises(ValueError):
            audit_shard(self.value, 0, transcript(group).replace('** TEST EXECUTE SUCCEEDED **', ''))
        with self.assertRaises(ValueError):
            aggregate(self.value, receipts[:-1])
        with self.assertRaises(ValueError):
            aggregate(self.value, receipts + receipts[:1])
        wrong = copy.deepcopy(receipts)
        wrong[0]['source_sha'] = 'b' * 40
        with self.assertRaises(ValueError):
            aggregate(self.value, wrong)
        wrong = copy.deepcopy(receipts)
        wrong[0]['tests'][0] = (group[0], 'skipped')
        with self.assertRaises(ValueError):
            aggregate(self.value, wrong)


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'original'
        self.root.mkdir()
        (self.root / BUILD_MARKER).touch()
        self.manifest, self.payload = make_products(self.root)
        (self.root / 'ui-plan.json').write_text(json.dumps(plan(TESTS, {}, SHA)))
        (self.root / 'ui-enumeration.json').write_text(json.dumps(enumeration(TESTS)))
        self.artifact = self.base / 'artifact'
        self.toolchain = patch('apple_nightly_ui.toolchain', return_value='Xcode matching build')
        self.toolchain.start()
        self.addCleanup(self.toolchain.stop)

    def test_relocated_products_preserve_generated_manifest_bytes(self):
        pack(self.root, self.artifact, SHA)
        result = unpack(self.artifact, self.base / 'relocated', SHA)
        self.assertEqual(result.read_bytes(), self.manifest.read_bytes())
        self.assertNotEqual(result, self.manifest)
        with self.assertRaises(ValueError):
            unpack(self.artifact, self.base / 'relocated', SHA)

    def test_wrong_source_toolchain_or_archive_bytes_fail_closed(self):
        pack(self.root, self.artifact, SHA)
        with self.assertRaises(ValueError):
            unpack(self.artifact, self.base / 'wrong-source', 'b' * 40)
        with patch('apple_nightly_ui.toolchain', return_value='Other Xcode'), self.assertRaises(ValueError):
            unpack(self.artifact, self.base / 'wrong-toolchain', SHA)
        with patch('apple_nightly_ui.platform.machine', return_value='other-architecture'), self.assertRaises(ValueError):
            unpack(self.artifact, self.base / 'wrong-architecture', SHA)
        with (self.artifact / 'products.tar.gz').open('ab') as stream: stream.write(b'tampered')
        with self.assertRaises(ValueError):
            unpack(self.artifact, self.base / 'wrong-bytes', SHA)

    def test_plan_cannot_omit_a_compiled_case(self):
        (self.root / 'ui-plan.json').write_text(json.dumps(plan(TESTS[:-1], {}, SHA)))
        with self.assertRaises(ValueError):
            pack(self.root, self.artifact, SHA)

    def test_filtered_generated_manifest_cannot_be_published(self):
        self.payload['HealthMdUITests']['SkipTestIdentifiers'] = ['JourneyTests/testHidden']
        self.manifest.write_bytes(plistlib.dumps(self.payload))
        with self.assertRaises(ValueError):
            pack(self.root, self.artifact, SHA)


class ProcessBoundaryTests(unittest.TestCase):
    def test_actual_worker_preserves_xcode_failure_and_audits_success(self):
        for status in (0, 65):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                value = plan(TESTS, {}, SHA)
                staged = root / 'staged'
                staged.mkdir()
                (staged / 'ui-plan.json').write_text(json.dumps(value))
                binary = root / 'bin'
                binary.mkdir()
                fake = binary / 'xcodebuild'
                fake.write_text(f'#!{sys.executable}\n' + '''
import json, os, sys
from pathlib import Path
Path('args.json').write_text(json.dumps(sys.argv[1:]))
print('raw stdout')
print('raw diagnostic', file=sys.stderr)
for arg in sys.argv[1:]:
    if arg.startswith('-only-testing:'):
        _, cls, method = arg.split(':', 1)[1].split('/')
        print(f"Test Case '-[HealthMdUITests.{cls} {method}]' passed (1.000 seconds).")
print('** TEST EXECUTE SUCCEEDED **')
sys.exit(int(os.environ['FAKE_STATUS']))
''')
                fake.chmod(0o755)
                cwd = Path.cwd()
                try:
                    os.chdir(root)
                    with patch.dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", FAKE_STATUS=str(status)), \
                         patch('apple_nightly_ui.unpack', return_value=staged / 'generated.xctestrun'), \
                         patch.object(sys, 'argv', ['apple_nightly_ui.py', 'run', '--root', str(staged),
                                                   '--artifact', 'artifact', '--source-sha', SHA,
                                                   '--shard', '0', '--destination', 'synthetic-simulator']), \
                         contextlib.redirect_stdout(io.StringIO()):
                        if status:
                            with self.assertRaises(SystemExit) as failure: main()
                            self.assertEqual(failure.exception.code, status)
                        else:
                            main()
                    log = (root / 'build/logs/nightly-ui-0.log').read_text()
                    self.assertIn('raw stdout', log)
                    self.assertIn('raw diagnostic', log)
                    receipt = root / 'build/logs/ui-shard-0.json'
                    self.assertEqual(receipt.exists(), status == 0)
                    args = json.loads((root / 'args.json').read_text())
                    self.assertEqual(args[0], 'test-without-building')
                    self.assertEqual([a.split(':', 1)[1] for a in args if a.startswith('-only-testing:')],
                                     value['shards'][0])
                    self.assertNotIn('-skip-testing', args)
                    self.assertEqual(args[args.index('-default-test-execution-time-allowance') + 1], '180')
                    self.assertEqual(args[args.index('-maximum-test-execution-time-allowance') + 1], '300')
                finally:
                    os.chdir(cwd)


if __name__ == '__main__':
    unittest.main()
