"""Regressions for the batched, read-only macOS reference drift runner."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

APPLE = Path(__file__).resolve().parents[2]
SCRIPT = APPLE / "scripts/check-generated-reference-docs.sh"
SELECTORS = {
    "HealthMdTests/GeneratedExportDocumentationTests/testGeneratedExportDocumentationIsCurrent",
    "HealthMdTests/IndividualEntryDocumentationTests/testGeneratedIndividualEntryDocumentationHasNoDrift",
    "HealthMdTests/GeneratedRollupReferenceDocsTests/testGeneratedRollupReferenceDocsMatchProductionOutput",
    "HealthMdTests/GeneratedAutomationReferenceDocumentationTests/testGeneratedAutomationReferenceDocumentationHasNoDrift",
}
SUMMARY = dict(totalTestCount=4, passedTests=4, failedTests=0,
               skippedTests=0, expectedFailures=0, result="Passed")
MARKERS = (
    "HealthMdTests/Fixtures/Documentation/.generated-export-docs-output",
    "HealthMdTests/Documentation/.update-generated-individual-entry-docs",
    "HealthMdTests/.update-generated-rollup-reference-docs",
    "HealthMdTests/.update-generated-automation-reference-docs",
)


class ReferenceDocsRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="healthmd-reference-runner-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.root / "scripts/check-generated-reference-docs.sh")
        self.schema = self.root / "HealthMdTests/Fixtures/Export/export_schema_signature_v1.json"
        self.schema.parent.mkdir(parents=True)
        self.schema.write_text("original signature")
        self.core = self.root / "docs/reference/generated/core"
        self.core.mkdir(parents=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.tmp = self.root / "tmp"
        self.tmp.mkdir()
        self.invocations = self.root / "invocations.jsonl"
        self.env = dict(os.environ, PATH=f"{self.bin}:{Path(sys.executable).parent}:{os.environ['PATH']}",
                        TMPDIR=str(self.tmp), INVOCATIONS=str(self.invocations),
                        SUMMARY=json.dumps(SUMMARY))
        for key in ("DERIVED_DATA_PATH", "REFERENCE_DOCS_XCRESULT_PATH"):
            self.env.pop(key, None)
        self.tool("xcodebuild", '''
import json, os, pathlib, sys
with open(os.environ['INVOCATIONS'], 'a') as log:
    log.write(json.dumps({'args': sys.argv[1:], 'env': dict(os.environ)}) + '\\n')
if os.environ.get('MUTATE_SCHEMA'):
    pathlib.Path('HealthMdTests/Fixtures/Export/export_schema_signature_v1.json').write_text('changed')
args = sys.argv[1:]
for flag in ['-derivedDataPath', '-resultBundlePath']:
    pathlib.Path(args[args.index(flag) + 1]).mkdir(parents=True, exist_ok=True)
sys.exit(int(os.environ.get('BUILD_EXIT', '0')))
''')
        self.tool("xcrun", '''
import os, sys
assert sys.argv[1:5] == ['xcresulttool', 'get', 'test-results', 'summary']
assert sys.argv[5] == '--path'
print(os.environ['SUMMARY'])
sys.exit(int(os.environ.get('SUMMARY_EXIT', '0')))
''')

    def tool(self, name, source):
        executable = self.bin / name
        executable.write_text(f"#!{sys.executable}\n" + source)
        executable.chmod(0o755)

    def run_script(self, *args, **env):
        result = subprocess.run(["bash", "scripts/check-generated-reference-docs.sh", *args],
                                cwd=self.root, env=dict(self.env, **env), text=True,
                                capture_output=True)
        self.assertEqual(list(self.tmp.iterdir()), [], "task-owned temporary products leaked")
        return result

    def test_one_session_executes_exactly_the_four_existing_checks(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.invocations.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        args = calls[0]["args"]
        self.assertEqual({arg.removeprefix("-only-testing:") for arg in args
                          if arg.startswith("-only-testing:")}, SELECTORS)
        self.assertEqual(args[args.index("-scheme") + 1], "HealthMd-Tests-macOS")
        self.assertEqual(args[args.index("-parallel-testing-enabled") + 1], "NO")
        self.assertIn("4 tests, 0 skips", result.stdout)
        self.assertEqual(self.schema.read_text(), "original signature")

    def test_inherited_update_environment_cannot_disable_drift_comparisons(self):
        result = self.run_script(GENERATED_EXPORT_DOCS_OUTPUT_DIR="bad",
                                 GENERATED_INDIVIDUAL_ENTRY_DOCS_OUTPUT_BASENAME="bad",
                                 GENERATED_INDIVIDUAL_ENTRY_DOCS_MODE="update",
                                 UPDATE_GENERATED_ROLLUP_REFERENCE_DOCS="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        env = json.loads(self.invocations.read_text())["env"]
        for key in ("GENERATED_EXPORT_DOCS_OUTPUT_DIR", "GENERATED_INDIVIDUAL_ENTRY_DOCS_OUTPUT_BASENAME",
                    "GENERATED_INDIVIDUAL_ENTRY_DOCS_MODE", "UPDATE_GENERATED_ROLLUP_REFERENCE_DOCS"):
            self.assertNotIn(key, env)
        self.assertEqual(env["TZ"], "UTC")

    def test_generation_markers_are_preserved_and_stop_checking(self):
        for marker in MARKERS:
            with self.subTest(marker=marker):
                target = self.root / marker
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("owned by update")
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("generation marker exists", result.stderr)
                self.assertFalse(self.invocations.exists())
                self.assertEqual(target.read_text(), "owned by update")
                target.unlink()

    def test_missing_skipped_failed_and_expected_failure_tests_cannot_pass(self):
        for fields in (dict(totalTestCount=0, passedTests=0), dict(totalTestCount=3, passedTests=3),
                       dict(passedTests=3, skippedTests=1), dict(passedTests=3, failedTests=1),
                       dict(expectedFailures=1), dict(result="Failed")):
            with self.subTest(fields=fields):
                result = self.run_script(SUMMARY=json.dumps(dict(SUMMARY, **fields)))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("expected four passing documentation checks", result.stderr)

    def test_build_and_result_errors_propagate(self):
        self.assertEqual(self.run_script(BUILD_EXIT="65").returncode, 65)
        self.assertEqual(self.run_script(SUMMARY_EXIT="17").returncode, 17)
        self.assertNotEqual(self.run_script(SUMMARY="not json").returncode, 0)

    def test_schema_mutation_is_rejected(self):
        result = self.run_script(MUTATE_SCHEMA="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("schema-signature fixture changed", result.stderr)

    def test_caller_build_and_result_paths_are_preserved_even_on_failure(self):
        for status in ("0", "65"):
            with self.subTest(status=status):
                derived = self.root / "caller-derived"
                bundle = self.root / "caller-results.xcresult"
                result = self.run_script(DERIVED_DATA_PATH=str(derived),
                                         REFERENCE_DOCS_XCRESULT_PATH=str(bundle), BUILD_EXIT=status)
                self.assertEqual(result.returncode, int(status))
                self.assertTrue(derived.is_dir())
                self.assertTrue(bundle.is_dir())

    def test_invalid_arguments_do_not_run_xcode(self):
        self.assertEqual(self.run_script("update").returncode, 2)
        self.assertFalse(self.invocations.exists())

    def test_extra_core_directories_and_hidden_files_still_fail(self):
        for name, is_directory in (("unexpected", True), (".unexpected", False)):
            with self.subTest(name=name):
                target = self.core / name
                if is_directory:
                    target.mkdir()
                else:
                    target.write_text("extra")
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unexpected core reference entries", result.stderr)
                self.assertFalse(self.invocations.exists())
                if is_directory:
                    target.rmdir()
                else:
                    target.unlink()

    def test_make_target_retains_cli_and_links_after_the_batched_app_checks(self):
        result = subprocess.run(["make", "-n", "check-export-docs"], cwd=APPLE,
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.splitlines(), [
            "scripts/check-generated-reference-docs.sh",
            "scripts/generated-cli-reference-docs.sh check",
            "scripts/check-documentation-links.py",
        ])


if __name__ == "__main__":
    unittest.main()
