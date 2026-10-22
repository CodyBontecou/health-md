"""Coverage and failure-path regressions for the real UI shard runner/gate."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ios_ui_shards as shards
from test_ios_ui_build_contract import EXPECTED_TESTS

SHA = "a" * 40


def tree(index):
    return {"testNodes": [{"nodeType": "Test Suite", "children": [
        {"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": "Passed"}
        for name in shards.SHARDS[index]
    ]}]}


def summary(index):
    return {"result": "Passed", "totalTestCount": len(shards.SHARDS[index]),
            "passedTests": len(shards.SHARDS[index]), "failedTests": 0, "skippedTests": 0}


class UiCoverageTests(unittest.TestCase):
    def test_exact_existing_inventory_is_disjoint_and_complete(self):
        actual = [name for lane in shards.SHARDS for name in lane]
        self.assertEqual(set(actual), set(EXPECTED_TESTS))
        self.assertEqual(len(actual), 15)
        self.assertEqual(len(actual), len(set(actual)))
        self.assertEqual(len(shards.SHARDS), 3)
        self.assertTrue(all(shards.SHARDS))
        owners = {}
        for index, lane in enumerate(shards.SHARDS):
            for name in lane:
                cls = name.split('/')[0]
                self.assertEqual(owners.setdefault(cls, index), index, "A stateful UI class was split")

    def test_real_result_tree_and_summary_must_agree_with_each_selection(self):
        for index in range(3):
            receipt = shards.qualify_results(tree(index), summary(index), index)
            self.assertEqual(receipt["cases"], sorted(shards.SHARDS[index]))
            self.assertEqual(receipt["passed"], len(shards.SHARDS[index]))

    def test_missing_unexpected_duplicate_failed_and_skipped_cases_fail_closed(self):
        for scenario in ("missing", "extra", "duplicate", "failed", "skipped", "unknown"):
            with self.subTest(scenario=scenario):
                value = tree(0)
                cases = value["testNodes"][0]["children"]
                if scenario == "missing": cases.pop()
                elif scenario == "extra": cases.append({"nodeType": "Test Case", "nodeIdentifier": "Other/testUnexpected()", "result": "Passed"})
                elif scenario == "duplicate": cases.append(copy.deepcopy(cases[0]))
                else: cases[0]["result"] = scenario.capitalize()
                with self.assertRaises(ValueError):
                    shards.qualify_results(value, summary(0), 0)

    def test_green_tree_does_not_override_failed_or_incomplete_summary(self):
        for key, value in [("result", "Failed"), ("totalTestCount", 0), ("failedTests", 1),
                           ("skippedTests", 1), ("passedTests", 0)]:
            bad = summary(0)
            bad[key] = value
            with self.assertRaises(ValueError):
                shards.qualify_results(tree(0), bad, 0)

    def test_run_only_command_preserves_timeouts_and_uses_one_destination(self):
        for index in range(3):
            args = shards.test_command(Path("fresh.xctestrun"), "platform=iOS Simulator,id=PHONE", Path("result.xcresult"), index)
            self.assertEqual(args[:2], ["xcodebuild", "test-without-building"])
            self.assertEqual(args[args.index("-parallel-testing-enabled") + 1], "NO")
            self.assertEqual(args[args.index("-maximum-test-execution-time-allowance") + 1], "300")
            actual = [a.removeprefix("-only-testing:HealthMdUITests/") for a in args if a.startswith("-only-testing:")]
            self.assertEqual(actual, list(shards.SHARDS[index]))
            self.assertNotIn("-retry-tests-on-failure", args)
            self.assertNotIn("-skip-testing", args)


class UiAggregateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for index in range(3): self.write(index)

    def write(self, index, **updates):
        folder = self.root / f"ios-ui-12-1-shard-{index}"
        folder.mkdir(exist_ok=True)
        value = dict(source_sha=SHA, run_id="12", attempt="1", shard=index,
                     **shards.qualify_results(tree(index), summary(index), index))
        value.update(updates)
        path = folder / "ui-case-receipt.json"
        path.write_text(json.dumps(value))
        return path

    def test_all_exact_head_shards_verify_fifteen_passes(self):
        result = shards.verify_shards(self.root, "12", "1", SHA)
        self.assertEqual(result["passed"], 15)
        self.assertEqual(result["cases"], sorted(EXPECTED_TESTS))

    def test_wrong_head_run_attempt_and_shard_are_rejected(self):
        for key, value in [("source_sha", "b" * 40), ("run_id", "11"), ("attempt", "2"), ("shard", 2)]:
            with self.subTest(key=key):
                self.write(0, **{key: value})
                with self.assertRaises(ValueError): shards.verify_shards(self.root, "12", "1", SHA)
                self.write(0)

    def test_missing_extra_and_duplicate_receipts_cannot_pass(self):
        path = self.write(0)
        path.unlink()
        with self.assertRaises(ValueError): shards.verify_shards(self.root, "12", "1", SHA)
        self.write(0)
        extra = path.parent / "nested"
        extra.mkdir()
        (extra / path.name).write_bytes(path.read_bytes())
        with self.assertRaises(ValueError): shards.verify_shards(self.root, "12", "1", SHA)

    def test_receipt_count_and_selection_are_revalidated_at_aggregate(self):
        for updates in ({"passed": 0}, {"cases": []}, {"cases": list(shards.SHARDS[1])}):
            self.write(0, **updates)
            with self.assertRaises(ValueError): shards.verify_shards(self.root, "12", "1", SHA)
            self.write(0)


if __name__ == "__main__": unittest.main()
