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
        self.assertEqual(set(n for lane in shards.SHARDS[:3] for n in lane), set(EXPECTED_TESTS))
        self.assertEqual(len(actual), 23)
        self.assertEqual(len(actual), len(set((shards.device_family(i), n) for i, lane in enumerate(shards.SHARDS) for n in lane)))
        self.assertEqual(len(shards.SHARDS), 4)
        self.assertTrue(all(shards.SHARDS))
        owners = {}
        for index, lane in enumerate(shards.SHARDS):
            for name in lane:
                cls = (shards.device_family(index), name.split('/')[0])
                self.assertEqual(owners.setdefault(cls, index), index, "A stateful UI class was split")

    def test_actual_device_family_is_required_before_native_execution(self):
        destination = "platform=iOS Simulator,id=" + "1" * 36
        phone = {"udid": "1" * 36, "isAvailable": True, "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Synthetic"}
        self.assertEqual(shards.qualify_device({"devices": {"runtime": [phone]}}, destination, 0), "iPhone")
        tablet = dict(phone, deviceTypeIdentifier="com.apple.CoreSimulator.SimDeviceType.iPad-Synthetic")
        self.assertEqual(shards.qualify_device({"devices": {"runtime": [tablet]}}, destination, 3), "iPad")
        for devices, index in [([phone], 3), ([tablet], 0), ([], 0), ([phone, phone], 0),
                               ([dict(phone, isAvailable=False)], 0), ([dict(phone, deviceTypeIdentifier="")], 0)]:
            with self.assertRaises(ValueError): shards.qualify_device({"devices": {"runtime": devices}}, destination, index)

    def test_real_result_tree_and_summary_must_agree_with_each_selection(self):
        for index in range(len(shards.SHARDS)):
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
        for index in range(len(shards.SHARDS)):
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
        for index in range(len(shards.SHARDS)): self.write(index)

    def write(self, index, **updates):
        folder = self.root / f"ios-ui-12-1-shard-{index}"
        folder.mkdir(exist_ok=True)
        value = dict(source_sha=SHA, run_id="12", attempt="1", shard=index,
                     **shards.qualify_results(tree(index), summary(index), index))
        value.update(updates)
        path = folder / "ui-case-receipt.json"
        path.write_text(json.dumps(value))
        return path

    def test_all_exact_head_device_lanes_verify_twenty_three_passes(self):
        result = shards.verify_shards(self.root, "12", "1", SHA)
        self.assertEqual(result["passed"], 23)
        self.assertEqual(result["cases"], sorted([{"device_family": shards.device_family(i), "case": n} for i, lane in enumerate(shards.SHARDS) for n in lane], key=lambda x: (x["device_family"], x["case"])))

    def test_wrong_head_run_attempt_and_shard_are_rejected(self):
        for key, value in [("source_sha", "b" * 40), ("run_id", "11"), ("attempt", "2"), ("shard", 2), ("device_family", "iPad")]:
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
