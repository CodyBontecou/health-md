#!/usr/bin/env python3
"""Fixture regressions execute the production xcresult receipt CLI, not a copy."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPTS / "ci-automation-test-receipt.py"
FIXTURES = SCRIPTS / "fixtures" / "automation-test-results"
PLATFORMS = {"iOS": "ios", "macOS": "macos"}


class AutomationTestReceiptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def fixture(self, platform: str) -> dict:
        return json.loads((FIXTURES / f"{PLATFORMS[platform]}-complete.json").read_text())

    @staticmethod
    def cases(tree: dict) -> list:
        return tree["testNodes"][0]["children"][0]["children"]

    def run_cli(self, tree: dict, platform: str, diagnostics: bool = False) -> tuple:
        source = self.root / "tree.json"
        output = self.root / "qualification.txt"
        source.write_text(json.dumps(tree))
        command = [sys.executable, str(SCRIPT), str(source), str(output),
                   "--head", "synthetic-head", "--platform", platform]
        if diagnostics:
            command += ["--diagnostics", str(self.root / "diagnostics.txt")]
        process = subprocess.run(
            command,
            capture_output=True, text=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}, check=False,
        )
        return process, output

    def test_complete_passing_platform_suite_emits_receipt(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                process, output = self.run_cli(tree, platform)
                self.assertEqual(process.returncode, 0, process.stderr)
                records = [json.loads(line) for line in output.read_text().splitlines() if line.startswith("{")]
                self.assertEqual([record["identifier"] for record in records],
                                 [case["nodeIdentifier"] for case in self.cases(tree)])
                self.assertTrue(all(record["result"] == "Passed" for record in records))

    def test_skipped_case_rejects_qualification_without_writing_receipt(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                self.cases(tree)[0]["result"] = "Skipped"
                process, output = self.run_cli(tree, platform)
                self.assertNotEqual(process.returncode, 0, process.stdout)
                self.assertFalse(output.exists(), "Nonpassing output must not be qualification evidence")

    def test_missing_case_rejects_even_when_every_observed_result_passed(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                self.cases(tree).pop()
                process, output = self.run_cli(tree, platform)
                self.assertNotEqual(process.returncode, 0, process.stdout)
                self.assertFalse(output.exists())

    def test_duplicate_identity_rejects_a_same_count_passing_collection(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                self.cases(tree)[-1] = dict(self.cases(tree)[0])
                process, output = self.run_cli(tree, platform)
                self.assertNotEqual(process.returncode, 0, process.stdout)
                self.assertFalse(output.exists())

    def test_nonpassing_or_missing_results_reject_even_with_complete_identities(self) -> None:
        for platform in PLATFORMS:
            for result in ("Skipped", "Unknown", "Failed", "Expected Failure", None, "passed"):
                for all_cases in (False, True):
                    with self.subTest(platform=platform, result=result, all_cases=all_cases):
                        tree = self.fixture(platform)
                        for case in (self.cases(tree) if all_cases else self.cases(tree)[:1]):
                            if result is None:
                                case.pop("result")
                            else:
                                case["result"] = result
                        process, output = self.run_cli(tree, platform)
                        self.assertEqual(process.returncode, 1, process.stderr)
                        self.assertIn("Nonpassing test:", process.stderr)
                        self.assertFalse(output.exists())

    def test_one_case_empty_tree_and_skipped_suite_without_cases_cannot_qualify(self) -> None:
        for platform in PLATFORMS:
            for scenario in ("one", "empty", "skipped-suite"):
                with self.subTest(platform=platform, scenario=scenario):
                    tree = self.fixture(platform)
                    cases = self.cases(tree)
                    if scenario == "one":
                        del cases[1:]  # retain only one execution
                    else:
                        cases.clear()
                    if scenario == "skipped-suite":
                        tree["testNodes"][0]["children"][0]["result"] = "Skipped"
                    if scenario == "empty":
                        tree = {}
                    process, output = self.run_cli(tree, platform)
                    self.assertEqual(process.returncode, 1, process.stderr)
                    self.assertIn("Missing expected test:", process.stderr)
                    self.assertFalse(output.exists())

    def test_extra_duplicate_even_when_no_cases_missing_is_rejected(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                self.cases(tree).append(dict(self.cases(tree)[0]))
                process, output = self.run_cli(tree, platform)
                self.assertEqual(process.returncode, 1, process.stderr)
                self.assertIn("Duplicate test identity:", process.stderr)
                self.assertFalse(output.exists())

    def test_duplicate_bundle_qualified_identity_cannot_evade_uniqueness(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                duplicate = dict(self.cases(tree)[0])
                duplicate["nodeIdentifier"] = "HealthMdTests/" + duplicate["nodeIdentifier"]
                self.cases(tree).append(duplicate)
                process, output = self.run_cli(tree, platform)
                self.assertEqual(process.returncode, 1, process.stderr)
                self.assertIn("Duplicate test identity:", process.stderr)
                self.assertFalse(output.exists())

    def test_unknown_identity_cannot_replace_an_expected_case_at_same_count(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                case = self.cases(tree)[0]
                case["name"] = "testUnreviewed()"
                case["nodeIdentifier"] = "AppleContextAutomationTests/testUnreviewed()"
                process, output = self.run_cli(tree, platform)
                self.assertEqual(process.returncode, 1, process.stderr)
                self.assertIn("Unexpected test:", process.stderr)
                self.assertIn("Missing expected test:", process.stderr)
                self.assertFalse(output.exists())

    def test_missing_malformed_or_foreign_identity_and_name_mismatch_are_rejected(self) -> None:
        for platform in PLATFORMS:
            for scenario in ("missing", "foreign", "malformed", "name-mismatch"):
                with self.subTest(platform=platform, scenario=scenario):
                    tree = self.fixture(platform)
                    case = self.cases(tree)[0]
                    if scenario == "missing":
                        case.pop("nodeIdentifier")
                    elif scenario == "foreign":
                        case["nodeIdentifier"] = "Not" + case["nodeIdentifier"]
                    elif scenario == "malformed":
                        case["nodeIdentifier"] += "/unreviewed"
                    else:
                        case["name"] = "testUnreviewed()"
                    process, output = self.run_cli(tree, platform)
                    self.assertEqual(process.returncode, 1, process.stderr)
                    self.assertFalse(output.exists())

    def test_test_identifier_and_bundle_or_module_prefixes_preserve_exact_case_identity(self) -> None:
        for platform in PLATFORMS:
            for prefix in ("HealthMdTests/", "HealthMdTests."):
                with self.subTest(platform=platform, prefix=prefix):
                    tree = self.fixture(platform)
                    for case in self.cases(tree):
                        case["testIdentifier"] = prefix + case.pop("nodeIdentifier")
                    process, output = self.run_cli(tree, platform)
                    self.assertEqual(process.returncode, 0, process.stderr)
                    self.assertIn("qualification: Passed", output.read_text())

    def test_wrong_or_unsupported_platform_cannot_qualify(self) -> None:
        for platform in ("iOS", "macOS", "unknown"):
            with self.subTest(platform=platform):
                tree = self.fixture("macOS" if platform == "iOS" else "iOS")
                process, output = self.run_cli(tree, platform)
                self.assertEqual(process.returncode, 1, process.stderr)
                self.assertFalse(output.exists())

    def test_rejected_results_remove_stale_receipt_and_retain_separate_diagnostics(self) -> None:
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                tree = self.fixture(platform)
                process, output = self.run_cli(tree, platform, diagnostics=True)
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertTrue(output.exists())
                self.cases(tree)[0]["result"] = "Skipped"
                process, output = self.run_cli(tree, platform, diagnostics=True)
                self.assertEqual(process.returncode, 1, process.stderr)
                self.assertFalse(output.exists(), "A prior passing receipt must not survive a rejected run")
                diagnostic = (self.root / "diagnostics.txt").read_text()
                self.assertIn("NOT qualification evidence", diagnostic)
                self.assertIn("qualification: REJECTED", diagnostic)
                self.assertIn('"result": "Skipped"', diagnostic)
                self.assertEqual(process.stdout, "", "Rejected diagnostics must not be printed as a receipt")

    def test_diagnostic_output_cannot_alias_qualification_output(self) -> None:
        source = self.root / "tree.json"
        source.write_text(json.dumps(self.fixture("iOS")))
        output = self.root / "qualification.txt"
        output.write_text("stale passing receipt")
        process = subprocess.run(
            [sys.executable, str(SCRIPT), str(source), str(output), "--head", "synthetic-head", "--platform", "iOS",
             "--diagnostics", str(output)], capture_output=True, text=True, check=False,
        )
        self.assertEqual(process.returncode, 2, process.stderr)
        self.assertIn("diagnostics must not use the qualification output path", process.stderr)
        self.assertFalse(output.exists())

    def test_unreadable_or_invalid_json_tree_removes_stale_qualification(self) -> None:
        for scenario in ("missing", "invalid-json"):
            with self.subTest(scenario=scenario):
                source = self.root / "broken.json"
                if scenario == "invalid-json":
                    source.write_text("not JSON")
                output = self.root / "qualification.txt"
                output.write_text("stale passing receipt")
                process = subprocess.run(
                    [sys.executable, str(SCRIPT), str(source), str(output), "--head", "synthetic-head", "--platform", "iOS"],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(process.returncode, 1, process.stderr)
                self.assertIn("Unable to read native test tree:", process.stderr)
                self.assertFalse(output.exists())

    def test_explicit_platform_allowlists_and_fixtures_match_declared_native_inventory(self) -> None:
        # Maintenance/drift check only. This is not native execution evidence;
        # qualification still requires every explicit identity in the xcresult.
        module = runpy.run_path(str(SCRIPT))
        source = (SCRIPTS.parent / "HealthMdTests/Sync/AppleContextAutomationTests.swift").read_text()
        declared = {platform: set() for platform in PLATFORMS}
        active = set(PLATFORMS)
        stack = []
        for line in source.splitlines():
            condition = re.fullmatch(r"\s*#if os\((iOS|macOS)\)", line)
            if condition:
                stack.append(active)
                active = active & {condition.group(1)}
            elif line.strip() == "#endif":
                active = stack.pop()
            elif line.strip().startswith(("#if", "#else", "#elseif")):
                self.fail("Update inventory drift check for the changed native conditional")
            method = re.match(r"    func (test\w+)\(", line)
            if method:
                for platform in active:
                    declared[platform].add(f"AppleContextAutomationTests/{method.group(1)}()")
        self.assertFalse(stack)
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                expected = module["EXPECTED_IDENTITIES"][platform]
                fixture_cases = self.cases(self.fixture(platform))
                identities = [case["nodeIdentifier"] for case in fixture_cases]
                self.assertEqual(expected, declared[platform])
                self.assertEqual(set(identities), expected)
                self.assertEqual(len(identities), len(set(identities)))


if __name__ == "__main__":
    unittest.main()
