#!/usr/bin/env python3
"""Run the real Apple manifest XCTest, including isolated inventory mutations.

Requires macOS/Xcode; no application build, simulator, or health-data access.
The Swift test source is copied byte-for-byte, so its normal #filePath lookup
finds only a disposable manifest. Frozen repository contracts are never edited.
Run: python3 apps/apple/scripts/tests/test_product_capability_manifest.py -v
Set HEALTHMD_CAPABILITY_TEST_RECEIPTS to retain each subprocess's output.
"""

from __future__ import annotations

import copy
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path("apps/apple/HealthMdTests/Contracts/ProductCapabilityManifestTests.swift")
MANIFEST = Path("packages/contracts/product-capabilities.json")
CORPUS_ID = "direct.full_public_authorized_corpus"

RUNNER = """import Foundation
import XCTest

let suite = XCTestSuite(forTestCaseClass: ProductCapabilityManifestTests.self)
suite.run()
guard let run = suite.testRun, run.executionCount == 1 else {
    fputs("Expected exactly one real ProductCapabilityManifestTests case\\n", stderr)
    exit(2)
}
print("MANIFEST_XCTEST executed=\\(run.executionCount) failures=\\(run.totalFailureCount)")
exit(run.hasSucceeded ? 0 : 1)
"""


class ProductCapabilityManifestRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="healthmd-capability-xctest-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.manifest = cls.root / MANIFEST
        cls.manifest.parent.mkdir(parents=True)
        cls.manifest_bytes = (ROOT / MANIFEST).read_bytes()
        cls.inventory = json.loads(cls.manifest_bytes)
        source = cls.root / SOURCE
        source.parent.mkdir(parents=True)
        source.write_bytes((ROOT / SOURCE).read_bytes())
        runner = cls.root / "main.swift"
        runner.write_text(RUNNER)
        cls.binary = cls.root / "manifest-xctest"

        developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
        platform = developer / "Platforms/MacOSX.platform/Developer"
        frameworks = platform / "Library/Frameworks"
        private_frameworks = platform / "Library/PrivateFrameworks"
        libraries = platform / "usr/lib"
        command = [
            "xcrun", "--sdk", "macosx", "swiftc",
            "-module-cache-path", str(cls.root / "module-cache"),
            "-F", str(frameworks), "-I", str(libraries), "-L", str(libraries),
            "-lXCTestSwiftSupport",
        ]
        for path in (frameworks, private_frameworks, libraries):
            command.extend(["-Xlinker", "-rpath", "-Xlinker", str(path)])
        command.extend([str(source), str(runner), "-o", str(cls.binary)])
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        cls.record("build", result)
        if result.returncode != 0:
            raise AssertionError(f"Real manifest XCTest compilation failed:\n{result.stdout}{result.stderr}")

    @staticmethod
    def record(label: str, result: subprocess.CompletedProcess[str]) -> None:
        if directory := os.environ.get("HEALTHMD_CAPABILITY_TEST_RECEIPTS"):
            receipts = Path(directory)
            receipts.mkdir(parents=True, exist_ok=True)
            (receipts / f"{label}.log").write_text(result.stdout + result.stderr)
            (receipts / f"{label}.exit").write_text(f"{result.returncode}\n")

    def run_inventory(self, label: str, inventory: dict | None = None) -> subprocess.CompletedProcess[str]:
        self.manifest.write_bytes(
            self.manifest_bytes if inventory is None else json.dumps(inventory).encode()
        )
        result = subprocess.run([str(self.binary)], capture_output=True, text=True, timeout=10)
        self.record(label, result)
        return result

    def assert_xctest_result(self, label: str, inventory: dict | None, failures: int) -> None:
        result = self.run_inventory(label, inventory)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0 if failures == 0 else 1, output)
        self.assertIn(f"MANIFEST_XCTEST executed=1 failures={failures}", output)
        if failures:
            self.assertIn("XCTAssert", output)

    def capability(self, inventory: dict, identifier: str) -> dict:
        return next(item for item in inventory["capabilities"] if item["id"] == identifier)

    def test_real_inventory_matches_apple_expectations(self) -> None:
        self.assert_xctest_result("real-inventory", None, failures=0)

    def test_missing_full_corpus_capability_is_rejected(self) -> None:
        inventory = copy.deepcopy(self.inventory)
        inventory["capabilities"] = [
            item for item in inventory["capabilities"] if item["id"] != CORPUS_ID
        ]
        self.assert_xctest_result("missing-full-corpus", inventory, failures=3)

    def test_unexpected_capability_is_rejected(self) -> None:
        inventory = copy.deepcopy(self.inventory)
        extra = copy.deepcopy(self.capability(inventory, CORPUS_ID))
        extra["id"] = "regression.unexpected-capability"
        inventory["capabilities"].append(extra)
        self.assert_xctest_result("unexpected-capability", inventory, failures=2)

    def test_same_size_replacement_does_not_bypass_set_equality(self) -> None:
        inventory = copy.deepcopy(self.inventory)
        self.capability(inventory, "export.daily-files")["id"] = "regression.replacement"
        self.assert_xctest_result("same-size-replacement", inventory, failures=2)

    def test_duplicate_capability_is_rejected(self) -> None:
        inventory = copy.deepcopy(self.inventory)
        inventory["capabilities"].append(copy.deepcopy(inventory["capabilities"][0]))
        result = self.run_inventory("duplicate-capability", inventory)
        # The real source's uniqueKeysWithValues initializer traps before its
        # count assertion. Require that specific rejection, not an arbitrary crash.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate values for key", result.stdout + result.stderr)

    def test_schema_identity_and_version_are_exact(self) -> None:
        for key, value in (("schema", "regression.schema"), ("schema_version", 2)):
            with self.subTest(key=key):
                inventory = copy.deepcopy(self.inventory)
                inventory[key] = value
                self.assert_xctest_result(f"wrong-{key}", inventory, failures=1)

    def test_output_profile_set_is_exact(self) -> None:
        for mutation in ("missing", "unexpected", "replacement"):
            with self.subTest(mutation=mutation):
                inventory = copy.deepcopy(self.inventory)
                profiles = inventory["output_profiles"]
                if mutation == "missing":
                    profiles.pop()
                elif mutation == "unexpected":
                    profiles.append({"id": "regression.profile"})
                else:
                    profiles[0]["id"] = "regression.profile"
                self.assert_xctest_result(f"{mutation}-profile", inventory, failures=1)

    def test_availability_sets_are_exact(self) -> None:
        for identifier, state in (
            (CORPUS_ID, "planned"),
            (CORPUS_ID, "unavailable"),
            ("android.activity-intensity", "available"),
            ("core.shared-rust-profile-engine", "available"),
        ):
            with self.subTest(identifier=identifier, state=state):
                inventory = copy.deepcopy(self.inventory)
                self.capability(inventory, identifier)["platforms"]["apple"] = {
                    "state": state,
                    "reason": "Synthetic unavailable evidence",
                    "target": "Synthetic planned target",
                }
                self.assert_xctest_result(f"{identifier}-{state}", inventory, failures=2)

    def test_classification_checks_are_preserved(self) -> None:
        for identifier in ("automation.cancel-active-export", "direct.cli_agent_push_wake", CORPUS_ID):
            with self.subTest(identifier=identifier):
                inventory = copy.deepcopy(self.inventory)
                self.capability(inventory, identifier)["classification"] = "android_only"
                self.assert_xctest_result(f"{identifier}-classification", inventory, failures=1)

    def test_unavailable_reason_and_planned_target_are_required(self) -> None:
        for identifier, field in (
            ("source.private-platform-database", "reason"),
            ("core.shared-rust-profile-engine", "target"),
        ):
            for missing in (True, False):
                with self.subTest(identifier=identifier, field=field, missing=missing):
                    inventory = copy.deepcopy(self.inventory)
                    availability = self.capability(inventory, identifier)["platforms"]["apple"]
                    if missing:
                        del availability[field]
                    else:
                        availability[field] = ""
                    label = f"{identifier}-{field}-{'missing' if missing else 'empty'}"
                    self.assert_xctest_result(label, inventory, failures=1)


if __name__ == "__main__":
    unittest.main()
