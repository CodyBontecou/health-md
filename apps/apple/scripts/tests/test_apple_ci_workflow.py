#!/usr/bin/env python3
"""Exercise the real Apple final-gate shell and PR dependency wiring without Xcode."""
from __future__ import annotations

import ast
import itertools
import tempfile
import os
import re
import shlex
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
WORKFLOW = REPO / ".github/workflows/apple-ci.yml"
JOBS = {"prepare": "prepare-shared-core", "ios": "test-ios", "ios_ui": "test-ios-ui",
        "macos": "test-macos", "connectivity": "connectivity-package", "policy": "workflow-policy"}


def jobs():
    pieces = re.split(r"^  ([a-z][a-z0-9-]*):\n", WORKFLOW.read_text(), flags=re.MULTILINE)
    return dict(zip(pieces[1::2], pieces[2::2]))


def gate_script():
    return "\n".join(line[10:] for line in jobs()["gate"].split("        run: |\n", 1)[1].splitlines())


class WorkflowRoutingTests(unittest.TestCase):
    def test_native_policy_failure_blocks_shared_core_fanout_before_app_builds(self):
        blocks = jobs()
        probe = blocks["probe-shared-core"]
        step = probe.split("      - name: Run native workflow policy before expensive preparation\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("run: python3 scripts/run-ci-quality-gates.py", step)
        self.assertNotIn("continue-on-error", step)
        self.assertLess(probe.index("run-ci-quality-gates.py"), probe.index("Restore exact-source shared-core cache"))
        self.assertIn("needs: [changes, probe-shared-core]", blocks["prepare-core-slices"])
        self.assertIn("needs.probe-shared-core.result == 'success'", blocks["prepare-core-slices"])

    def test_each_job_uses_its_own_planner_output_and_keeps_existing_dependencies(self):
        blocks = jobs()
        for output, job in JOBS.items():
            with self.subTest(job=job):
                if output == "ios_ui":
                    self.assertIn("if: ${{ always() && needs.changes.outputs.ios_ui == 'true' }}", blocks[job])
                    self.assertIn("needs: [changes, prepare-ui-artifacts, ios-ui-shards]", blocks[job])
                    self.assertIn("test \"$SHARDS_RESULT\" = success", blocks[job])
                    self.assertIn("ios_ui_shards.py verify", blocks[job])
                elif output == "ios":
                    self.assertIn("if: ${{ always() && needs.changes.outputs.ios == 'true' }}", blocks[job])
                    self.assertIn("needs: [changes, prepare-ios-artifacts, ios-native-shards, ios-device-candidate]", blocks[job])
                    self.assertIn('test "$SHARDS_RESULT" = success', blocks[job])
                    self.assertIn('test "$PRODUCTS_RESULT" = success', blocks[job])
                elif output == "macos":
                    self.assertIn("if: ${{ always() && needs.changes.outputs.macos == 'true' }}", blocks[job])
                    self.assertIn("needs: [changes, prepare-macos-artifacts, macos-native-shards]", blocks[job])
                    self.assertIn('test "$SHARDS_RESULT" = success', blocks[job])
                    self.assertIn('test "$PRODUCTS_RESULT" = success', blocks[job])
                elif output == "prepare":
                    self.assertIn("always() && needs.changes.outputs.prepare == 'true'", blocks[job])
                else:
                    self.assertIn(f"if: ${{{{ needs.changes.outputs.{output} == 'true' }}}}", blocks[job])
                if output in {"ios", "macos"}:
                    self.assertIn("name: apple-sdk27-shared-core", blocks[job])
                self.assertIn(f"      {output}: ${{{{ steps.detect.outputs.{output} }}}}", blocks["changes"])

    def test_planner_and_gate_regressions_and_links_run_before_selection_on_every_pr(self):
        changes = jobs()["changes"]
        self.assertIn("runs-on: ubuntu-24.04", changes)
        self.assertIn("python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_apple_ci_*.py'", changes)
        self.assertIn("python3 apps/apple/scripts/check-documentation-links.py", changes)
        self.assertLess(changes.index("test_apple_ci_*.py"), changes.index("id: detect"))
        self.assertNotIn("if:", changes)
        self.assertIn("FORCE_FULL_QUALIFICATION: ${{ inputs.full_qualification || false }}", changes)
        self.assertIn('python3 apps/apple/scripts/apple-ci-plan.py --release-sha "$RELEASE_SHA"', changes)
        call = WORKFLOW.read_text().split("  workflow_call:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.assertRegex(call, r"full_qualification:[\s\S]+type: boolean\s+default: true")

    def test_gate_waits_for_all_preserved_jobs_and_keeps_stable_status_name(self):
        gate = jobs()["gate"]
        self.assertIn("name: Apple CI", gate)
        self.assertIn("if: ${{ always() }}", gate)
        self.assertIn("      - changes", gate)
        for output, job in JOBS.items():
            with self.subTest(job=job):
                self.assertIn(f"      - {job}\n", gate)
                self.assertIn(f"{output.upper()}_SELECTED: ${{{{ needs.changes.outputs.{output} }}}}", gate)
                self.assertIn(f"{output.upper()}_RESULT: ${{{{ needs.{job}.result }}}}", gate)

    def test_known_external_test_inputs_trigger_push_qualification(self):
        push = WORKFLOW.read_text().split("  push:\n", 1)[1].split("  pull_request:", 1)[0]
        for path in ("apps/website/external-sources.json", "apps/website/assets/healthmd-plugin-visualizations.js",
                     "apps/website/assets/visualizations-data/health-sample.json",
                     "apps/website/assets/visualizations-data/health-rollups.json",
                     ".github/workflows/apple-nightly.yml", ".github/workflows/release-ios.yml",
                     "packages/contracts/**", "packages/healthmd-core-rust/**"):
            with self.subTest(path=path):
                self.assertIn(f"'{path}'", push)
        self.assertIn("      - main\n", push)
        self.assertIn("      - testing\n", push)

    def test_all_original_test_commands_and_ui_coverage_remain(self):
        workflow = WORKFLOW.read_text()
        for command in ("make build-ios-tests CORE_RUST_PREPARE=:", "python3 scripts/native_test_shards.py combine",
                        "make check-export-docs-after-tests", "scripts/check-coverage.sh build/coverage/HealthMd.xcresult",
                        "swift test --package-path apps/apple/Packages/HealthMdConnectivity"):
            self.assertIn(command, workflow)
        import sys
        sys.path.insert(0, str(REPO / "apps/apple/scripts"))
        from ios_ui_shards import SHARDS
        self.assertEqual(24, sum(map(len, SHARDS)))
        workers = jobs()["ios-ui-shards"]
        self.assertIn("shard: [0, 1, 2, 3]", workers)
        self.assertIn("fail-fast: false", workers)
        self.assertIn("needs: [changes, prepare-ui-artifacts]", workers)
        self.assertIn("name: apple-sdk27-shared-core", workers)
        self.assertIn("ios_ui_shards.py run", workers)
        self.assertNotIn("continue-on-error", workflow)

    def test_validated_bundle_cache_is_checked_before_native_slice_fanout(self):
        blocks = jobs()
        self.assertIn("probe-shared-core", blocks)
        probe = blocks["probe-shared-core"]
        self.assertIn("needs: changes", probe)
        self.assertIn("uses: actions/cache/restore@v4", probe)
        self.assertNotIn("restore-keys:", probe)
        self.assertIn("apple-source-digest.sh", probe)
        self.assertIn("validate-apple-xcframework.sh", probe)
        self.assertLess(probe.index("validate-apple-xcframework.sh"), probe.index("ready=true"))
        self.assertLess(probe.index("generate-apple-bindings.sh --check"), probe.index("ready=true"))
        workers = blocks["prepare-core-slices"]
        self.assertIn("needs: [changes, probe-shared-core]", workers)
        self.assertIn("needs.probe-shared-core.outputs.cache-hit == 'false'", workers)
        collector = blocks["assemble-shared-core"]
        self.assertIn("always() && needs.changes.outputs.prepare == 'true'", collector)
        self.assertIn("needs.probe-shared-core.result == 'success'", collector)
        self.assertIn("needs.prepare-core-slices.result == 'success'", collector)
        self.assertIn("needs.probe-shared-core.outputs.cache-hit == 'false'", collector)
        self.assertIn("name: apple-sdk27-shared-core", probe)
        self.assertIn("runs-on: ubuntu-24.04", blocks['prepare-shared-core'])
        self.assertNotIn('apple-sdk27-cached-core', WORKFLOW.read_text())

    def test_hot_bundle_admission_rejects_digest_and_framework_failures(self):
        probe = jobs()["probe-shared-core"]
        body = probe.split("      - name: Admit only an exact validated bundle\n", 1)[1]
        body = body.split("        run: |\n", 1)[1].split("      - name:", 1)[0]
        body = "\n".join(line[10:] for line in body.splitlines())
        for cached, digest, valid_framework in itertools.product(("true", "false"), (True, False), (True, False)):
            with self.subTest(cached=cached, digest=digest, valid_framework=valid_framework), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                cwd = root / "apps/apple"
                artifacts = cwd / "Packages/HealthMdCoreRust/Artifacts"
                artifacts.mkdir(parents=True)
                (artifacts / ".healthmd-core-source.sha256").write_text("synthetic" if digest else "wrong")
                scripts = root / "packages/healthmd-core-rust/scripts"
                scripts.mkdir(parents=True)
                for name, script in {
                    "apple-source-digest.sh": "#!/bin/sh\necho synthetic\n",
                    "validate-apple-xcframework.sh": "#!/bin/sh\nexit " + ("0" if valid_framework else "1") + "\n",
                }.items():
                    path = scripts / name
                    path.write_text(script)
                    path.chmod(0o755)
                output = root / "output"
                command = body.replace("${{ steps.shared-core-cache.outputs.cache-hit }}", cached)
                result = subprocess.run(["bash", "-c", command], cwd=cwd,
                                        env=dict(os.environ, GITHUB_OUTPUT=str(output)), capture_output=True, text=True)
                recorded = output.read_text() if output.exists() else ""
                if cached == "false":
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(recorded, "ready=false\n")
                elif digest and valid_framework:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(recorded, "ready=true\n")
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("ready=true", recorded)

    def test_cold_assembler_requires_complete_consistent_prerequisites(self):
        collector = jobs()["assemble-shared-core"]
        expression = re.search(r"^    if: \$\{\{ (.+) \}\}$", collector, re.MULTILINE).group(1)
        statuses = ("success", "failure", "cancelled", "skipped", "")
        for selected, probe, cached, slices in itertools.product(("true", "false"), statuses, ("true", "false", ""), statuses):
            values = {"needs.changes.outputs.prepare": selected, "needs.probe-shared-core.result": probe,
                      "needs.probe-shared-core.outputs.cache-hit": cached, "needs.prepare-core-slices.result": slices}
            actual = expression.replace("always()", "True").replace("&&", " and ").replace("||", " or ")
            for key, value in values.items(): actual = actual.replace(key, repr(value))
            tree = ast.parse(actual, mode="eval")
            allowed = (ast.Expression, ast.BoolOp, ast.And, ast.Or, ast.Compare, ast.Eq, ast.Constant)
            self.assertTrue(all(isinstance(node, allowed) for node in ast.walk(tree)))
            admitted = eval(compile(tree, "<workflow admission>", "eval"), {"__builtins__": {}})
            self.assertEqual(admitted, selected == "true" and probe == "success" and cached == "false" and slices == "success", values)

    def test_native_products_start_from_exact_validated_path_without_gate_handoff(self):
        blocks = jobs()
        statuses = ('success', 'failure', 'cancelled', 'skipped', '')
        for job, output in [('prepare-ios-artifacts', 'ios'), ('prepare-macos-artifacts', 'macos'),
                            ('prepare-ui-artifacts', 'ios_ui')]:
            producer = blocks[job]
            self.assertIn('needs: [changes, probe-shared-core, prepare-core-slices, assemble-shared-core]', producer)
            self.assertNotIn('prepare-shared-core', producer)
            expression = re.search(r'^    if: \$\{\{ (.+) \}\}$', producer, re.MULTILINE).group(1)
            for cancelled, selected, changes, probe, slices, assembly, cached in itertools.product(
                    (True, False), ('true', 'false'), statuses, statuses, statuses, statuses, ('true', 'false', '')):
                values = {f'needs.changes.outputs.{output}': selected, 'needs.changes.result': changes,
                          'needs.probe-shared-core.result': probe, 'needs.prepare-core-slices.result': slices,
                          'needs.assemble-shared-core.result': assembly, 'needs.probe-shared-core.outputs.cache-hit': cached}
                actual = expression.replace('always()', 'True').replace('!cancelled()', repr(not cancelled)).replace('&&', ' and ').replace('||', ' or ')
                for key, value in values.items(): actual = actual.replace(key, repr(value))
                tree = ast.parse(actual, mode='eval')
                allowed = (ast.Expression, ast.BoolOp, ast.And, ast.Or, ast.Compare, ast.Eq, ast.Constant)
                self.assertTrue(all(isinstance(node, allowed) for node in ast.walk(tree)))
                admitted = eval(compile(tree, '<native producer admission>', 'eval'), {'__builtins__': {}})
                expected = not cancelled and selected == 'true' and changes == probe == 'success' and (
                    cached, slices, assembly) in {('true', 'skipped', 'skipped'), ('false', 'success', 'success')}
                self.assertEqual(admitted, expected, (job, values))
        # The required stable gate still independently rejects inconsistent paths.
        self.assertIn('      - prepare-shared-core\n', blocks['gate'])
        for downstream in ('ios-native-shards', 'ios-device-candidate', 'test-ios',
                           'macos-native-shards', 'test-macos', 'ios-ui-shards'):
            self.assertNotIn('needs: [changes, prepare-shared-core', blocks[downstream])

    def test_lightweight_core_gate_requires_exactly_one_complete_producer_path(self):
        gate = jobs()['prepare-shared-core']
        self.assertIn('needs: [changes, probe-shared-core, prepare-core-slices, assemble-shared-core]', gate)
        self.assertIn('runs-on: ubuntu-24.04', gate)
        script = "\n".join(line[10:] for line in gate.split('        run: |\n', 1)[1].splitlines())
        statuses = ('success', 'failure', 'cancelled', 'skipped', '')
        for changes, probe, slices, assembly, cached in itertools.product(statuses, statuses, statuses, statuses, ('true', 'false', '')):
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                env=dict(os.environ, CHANGES_RESULT=changes, PROBE_RESULT=probe, SLICES_RESULT=slices, ASSEMBLY_RESULT=assembly, CACHE_HIT=cached))
            expected = changes == probe == 'success' and (cached, slices, assembly) in {('true', 'skipped', 'skipped'), ('false', 'success', 'success')}
            self.assertEqual(result.returncode == 0, expected, (changes, probe, slices, assembly, cached))

    def test_native_parallel_slices_remain_complete_and_source_validated(self):
        blocks = jobs()
        workers = blocks['prepare-core-slices']
        self.assertIn('fail-fast: false', workers)
        self.assertIn('target: [aarch64-apple-ios, aarch64-apple-ios-sim, x86_64-apple-ios, aarch64-apple-darwin, x86_64-apple-darwin]', workers)
        self.assertIn("--slice '${{ matrix.target }}'", workers)
        self.assertIn('ci_apple_core_slices.py receipt', workers)
        collector = blocks['assemble-shared-core']
        self.assertIn('needs: [changes, probe-shared-core, prepare-core-slices]', collector)
        self.assertIn('ci_apple_core_slices.py verify', collector)
        self.assertIn('generate-apple-bindings.sh --check', collector)
        self.assertIn('--assemble "$PWD/build/apple-core-slices"', collector)
        self.assertIn('validate-apple-xcframework.sh', collector)
        self.assertIn('name: apple-sdk27-shared-core', collector)

    def test_ios_inventory_shards_keep_complete_suite_and_overlap_boot_with_compile(self):
        blocks = jobs()
        producer, worker, collector = (blocks[name] for name in ('prepare-ios-artifacts', 'ios-native-shards', 'test-ios'))
        self.assertIn('IOS_TEST_BUILD_FLAGS="ARCHS=$(uname -m) ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"', producer)
        self.assertNotIn('-only-testing', producer)
        self.assertNotIn('-skip-testing', producer)
        self.assertLess(producer.index('scripts/start-ci-ios-simulator.sh'), producer.index('make build-ios-tests'))
        self.assertIn('Verify build-number format', producer)
        self.assertIn("--platform 'iOS Simulator'", producer)
        self.assertIn('native_test_shards.py prepare', producer)
        self.assertIn('shard: [0, 1, 2, 3]', worker)
        self.assertIn('fail-fast: false', worker)
        self.assertIn('native_test_shards.py run', worker)
        self.assertIn('--destination', worker)
        self.assertIn('scripts/start-ci-ios-simulator.sh', worker)
        self.assertIn('native_test_shards.py combine', collector)
        self.assertIn('--result build/test-results/HealthMd-iOS.xcresult', collector)
        self.assertIn('scripts/check-warnings.sh build/logs/xcodebuild-ios-raw.log', collector)
        self.assertIn('scripts/check-tdd-evidence.sh', collector)
        self.assertIn('ci-automation-test-receipt.py', collector)
        for native in (producer, worker, collector, blocks['ios-device-candidate']):
            self.assertIn('compare-history-sdk27-receipts.py', native)
            self.assertIn('name: apple-sdk27-shared-core', native)

    def test_ios_device_candidate_runs_alongside_shards_after_guarded_preparation(self):
        blocks = jobs()
        candidate = blocks['ios-device-candidate']
        self.assertIn('needs: [changes, prepare-ios-artifacts]', candidate)
        self.assertNotIn('ios-native-shards', candidate)
        self.assertIn("github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch'", candidate)
        for command in ('xcodebuild build', '-configuration Debug', "-destination 'generic/platform=iOS'", 'verify-device --plist', 'xcrun lipo -verify_arch arm64', 'ios-unsigned-device-candidate'):
            self.assertIn(command, candidate)
        self.assertNotIn('Build unsigned physical-device QA candidate', blocks['prepare-ios-artifacts'])
        self.assertNotIn('Build unsigned physical-device QA candidate', blocks['ios-native-shards'])

    def test_ios_collector_requires_every_selected_candidate_and_native_lane(self):
        native = jobs()['test-ios']
        step = native.split('      - name: Require every iOS producer, shard and selected device candidate\n', 1)[1].split('      - name:', 1)[0]
        script = "\n".join(line[10:] for line in step.split('        run: |\n', 1)[1].splitlines())
        for products, workers, required, candidate in itertools.product(('success', 'failure', 'skipped'), ('success', 'failure', 'skipped'), ('true', 'false'), ('success', 'failure', 'cancelled', 'skipped', '')):
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                env=dict(os.environ, PRODUCTS_RESULT=products, SHARDS_RESULT=workers, CANDIDATE_REQUIRED=required, CANDIDATE_RESULT=candidate))
            expected = products == workers == 'success' and (required, candidate) in {('true', 'success'), ('false', 'skipped')}
            with self.subTest(products=products, workers=workers, required=required, candidate=candidate):
                self.assertEqual(result.returncode == 0, expected)

    def test_ios_prebuild_and_local_full_execution_share_original_compilation_profile(self):
        def command(target):
            result = subprocess.run(['make', '-n', target, 'CORE_RUST_PREPARE=:',
                'IOS_SIM=platform=iOS Simulator,id=00000000-0000-0000-0000-000000000001',
                'IOS_DERIVED_DATA_DIR=build/ios-unit-derived',
                'IOS_TEST_BUILD_FLAGS=ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO', 'TEST_FILTER='],
                cwd=REPO / 'apps/apple', check=True, capture_output=True, text=True)
            expanded = result.stdout.replace('\\\n', ' ')
            line = next(line.strip() for line in expanded.splitlines() if 'xcodebuild ' in line)
            return shlex.split(line)
        build, test = command('build-ios-tests'), command('test-ios')
        for flag in ('-project', '-scheme', '-derivedDataPath', '-configuration'):
            self.assertEqual(build[build.index(flag) + 1], test[test.index(flag) + 1])
        self.assertIn('build-for-testing', build)
        self.assertIn('test', test)
        self.assertEqual(test[test.index('-test-timeouts-enabled') + 1], 'NO')
        for args in (build, test):
            self.assertIn('ARCHS=arm64', args)
            self.assertIn('ONLY_ACTIVE_ARCH=YES', args)
            self.assertIn('COMPILER_INDEX_STORE_ENABLE=NO', args)
            self.assertIn('CODE_SIGNING_ALLOWED=NO', args)
            self.assertNotIn('-only-testing', args)
            self.assertNotIn('-skip-testing', args)

    def test_macos_prebuild_preserves_bounded_execution_and_warning_coverage_gates(self):
        blocks = jobs()
        producer, worker, native = (blocks[name] for name in ('prepare-macos-artifacts', 'macos-native-shards', 'test-macos'))
        build = producer.split('      - name: Build macOS unit-test products\n', 1)[1].split('      - name:', 1)[0]
        execution = worker.split('      - name: Execute complete selected native methods with coverage\n', 1)[1].split('      - name:', 1)[0]
        self.assertIn('timeout-minutes: 25', build)
        self.assertIn('timeout-minutes: 45', execution)
        self.assertIn('MACOS_CODE_COVERAGE=YES', build)
        self.assertIn('MACOS_DERIVED_DATA_DIR=build/macos-qa-derived', build)
        self.assertIn('| tee build/logs/build-macos.log', build)
        self.assertIn('native_test_shards.py prepare', producer)
        self.assertIn('shard: [0, 1, 2, 3]', worker)
        self.assertIn('fail-fast: false', worker)
        self.assertIn('native_test_shards.py run', execution)
        self.assertIn('--prepared-sha256', execution)
        self.assertIn("needs: [changes, prepare-macos-artifacts]", worker)
        for job in (producer, worker, native):
            self.assertIn('name: apple-sdk27-shared-core', job)
            self.assertIn('compare-history-sdk27-receipts.py', job)
            self.assertNotIn('continue-on-error', job)
        for step in (build, execution):
            self.assertIn('set -euo pipefail', step)
            self.assertNotIn('TEST_FILTER', step)
        self.assertIn('native_test_shards.py combine', native)
        self.assertIn('--result build/coverage/HealthMd.xcresult', native)
        self.assertLess(native.index('native_test_shards.py combine'), native.index('Retain tested macOS QA candidate'))
        self.assertIn('scripts/check-warnings.sh build/logs/build-macos.log', native)
        self.assertIn('scripts/check-coverage.sh build/coverage/HealthMd.xcresult', native)
        self.assertIn('make check-export-docs-after-tests', native)
        self.assertIn('ci-automation-test-receipt.py', native)

    def test_macos_collector_executes_only_after_every_native_prerequisite_succeeds(self):
        native = jobs()['test-macos']
        step = native.split('      - name: Require every native producer and shard\n', 1)[1].split('      - name:', 1)[0]
        script = "\n".join(line[10:] for line in step.split('        run: |\n', 1)[1].splitlines())
        for products, workers in itertools.product(('success', 'failure', 'cancelled', 'skipped', ''), repeat=2):
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                                    env=dict(os.environ, PRODUCTS_RESULT=products, SHARDS_RESULT=workers))
            with self.subTest(products=products, workers=workers):
                self.assertEqual(result.returncode == 0, products == workers == 'success')

    def test_macos_make_prebuild_and_execution_share_products_without_test_filtering(self):
        def command(target):
            result = subprocess.run(
                ['make', '-n', target, 'CORE_RUST_PREPARE=:',
                 'MACOS_DERIVED_DATA_DIR=build/macos-qa-derived',
                 'MACOS_CODE_COVERAGE=YES', 'TEST_FILTER='],
                cwd=REPO / 'apps/apple', check=True, capture_output=True, text=True)
            expanded = result.stdout.replace('\\\n', ' ')
            return shlex.split(next(line.strip() for line in expanded.splitlines()
                                    if line.strip().startswith('xcodebuild ')))
        build, execution = command('build-macos-tests'), command('coverage')
        self.assertEqual(['xcodebuild', 'build-for-testing'], build[:2])
        self.assertEqual(['xcodebuild', 'test'], execution[:2])
        for flag in ('-project', '-scheme', '-destination', '-derivedDataPath', '-enableCodeCoverage'):
            self.assertEqual(build[build.index(flag) + 1], execution[execution.index(flag) + 1])
        self.assertEqual('YES', build[build.index('-enableCodeCoverage') + 1])
        for args in (build, execution):
            self.assertIn('CODE_SIGNING_ALLOWED=NO', args)
            self.assertIn('CODE_SIGNING_REQUIRED=NO', args)
            self.assertFalse(any(arg.startswith(('-only-testing', '-skip-testing')) for arg in args))
        for flag, value in (('-test-timeouts-enabled', 'YES'),
                            ('-default-test-execution-time-allowance', '120'),
                            ('-maximum-test-execution-time-allowance', '300'),
                            ('-resultBundlePath', 'build/coverage/HealthMd.xcresult')):
            self.assertEqual(value, execution[execution.index(flag) + 1])


class GateExecutionTests(unittest.TestCase):
    def run_gate(self, selected=(), **updates):
        environment = dict(os.environ, CHANGES_RESULT="success")
        for output in JOBS:
            environment[output.upper() + "_SELECTED"] = str(output in selected).lower()
            environment[output.upper() + "_RESULT"] = "success" if output in selected else "skipped"
        environment["PREPARE_UI_RESULT"] = "success" if "ios_ui" in selected else "skipped"
        environment.update(updates)
        return subprocess.run(["bash", "-e", "-c", gate_script()], env=environment, text=True, capture_output=True)

    def test_all_selection_combinations_pass_only_when_selected_jobs_succeeded(self):
        for flags in itertools.product((False, True), repeat=len(JOBS)):
            selected = {job for job, enabled in zip(JOBS, flags) if enabled}
            with self.subTest(selected=selected):
                result = self.run_gate(selected)
                self.assertEqual(0, result.returncode, result.stderr + result.stdout)

    def test_selected_jobs_skipped_failed_cancelled_or_missing_never_pass(self):
        for job in JOBS:
            for status in ("skipped", "failure", "cancelled", "", "unknown"):
                with self.subTest(job=job, status=status):
                    result = self.run_gate({job}, **{job.upper() + "_RESULT": status})
                    self.assertNotEqual(0, result.returncode)

    def test_selected_ui_preparation_must_succeed(self):
        for status in ("skipped", "failure", "cancelled", "", "unknown"):
            self.assertNotEqual(0, self.run_gate({"ios_ui"}, PREPARE_UI_RESULT=status).returncode)

    def test_empty_or_invalid_selection_never_passes_as_an_unrelated_pr(self):
        for job in JOBS:
            for selected in ("", "FALSE", "0", "unexpected"):
                with self.subTest(job=job, selected=selected):
                    result = self.run_gate(**{job.upper() + "_SELECTED": selected})
                    self.assertNotEqual(0, result.returncode)

    def test_failed_or_missing_planner_never_passes(self):
        for status in ("failure", "cancelled", "skipped", ""):
            with self.subTest(status=status):
                self.assertNotEqual(0, self.run_gate(CHANGES_RESULT=status).returncode)

    def test_unselected_jobs_cannot_hide_failures_but_extra_success_is_safe(self):
        for job in JOBS:
            for status in ("failure", "cancelled", "", "unknown"):
                with self.subTest(job=job, status=status):
                    self.assertNotEqual(0, self.run_gate(**{job.upper() + "_RESULT": status}).returncode)
            self.assertEqual(0, self.run_gate(**{job.upper() + "_RESULT": "success"}).returncode)


if __name__ == "__main__":
    unittest.main()
