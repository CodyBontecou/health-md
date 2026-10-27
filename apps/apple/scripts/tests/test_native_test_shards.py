import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("native_test_shards", Path(__file__).parents[1] / "native_test_shards.py")
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)
SHA = "a" * 40


def inventory(names):
    return {"errors": [], "values": [{"testPlan": "Native", "disabledTests": [],
            "enabledTests": [{"identifier": name} for name in names]}]}


def result(names, skip=()):
    # Shape captured from actual xcodebuild enumeration + xcresulttool, including
    # parameterized Swift Testing methods with argument nodes rather than IDs.
    cases = [{"nodeType": "Test Case", "nodeIdentifier": name.split("/", 1)[1],
              "result": "Skipped" if name in skip else "Passed"} for name in names]
    return {"devices": [{"platform": "macOS", "architecture": "arm64"}], "testNodes": [{"nodeType": "Unit test bundle", "name": "NativeTests", "children": cases}]}, {
        "result": "Passed", "totalTestCount": len(names), "passedTests": len(names) - len(skip),
        "skippedTests": len(skip), "failedTests": 0}


class NativeShardTests(unittest.TestCase):
    def setUp(self):
        self.names = ["NativeTests/ProbeTests/testFirst()", "NativeTests/SwiftProbeTests/parameterized(value:)",
                      "NativeTests/ProbeTests/testSecond()", "NativeTests/SwiftProbeTests/ordinary()"]
        self.plan = shards.make_plan(inventory(self.names), SHA, "123", "2", 2)

    def receipts(self):
        return [shards.qualify_results(self.plan, i, *result(names)) for i, names in enumerate(self.plan["shards"])]

    def test_every_compiled_method_is_assigned_exactly_once(self):
        names = [f"NativeTests/AgentBridgeExportPlanningTests/test{i}()" for i in range(40)]
        names += [f"NativeTests/OtherTests/test{i}()" for i in range(101)]
        plan = shards.make_plan(inventory(names), SHA, "123", "2")
        self.assertEqual(sorted(sum(plan["shards"], [])), sorted(names))
        loads = [sum(6 if "/AgentBridgeExportPlanningTests/" in name else 1 for name in lane) for lane in plan["shards"]]
        self.assertLessEqual(max(loads) - min(loads), 1)
        self.assertEqual(plan, shards.make_plan(inventory(list(reversed(names))), SHA, "123", "2") | {
            "inventory": plan["inventory"], "inventory_sha256": plan["inventory_sha256"]})

    def test_enumeration_errors_duplicates_and_empty_inventory_reject(self):
        for mode in ("error", "duplicate", "empty", "disabled-duplicate", "extra-plan"):
            value = inventory(self.names)
            if mode == "error": value["errors"] = ["discovery failed"]
            elif mode == "duplicate": value["values"][0]["enabledTests"].append({"identifier": self.names[0]})
            elif mode == "empty": value["values"][0]["enabledTests"] = []
            elif mode == "disabled-duplicate": value["values"][0]["disabledTests"] = [{"identifier": self.names[0]}]
            else: value["values"].append(copy.deepcopy(value["values"][0]))
            with self.subTest(mode=mode), self.assertRaises(ValueError): shards.identifiers(value)

    def test_original_scheme_disabled_tests_are_recorded_but_not_scheduled(self):
        value = inventory(self.names)
        value["values"][0]["disabledTests"] = [{"identifier": "NativeTests/Disabled/testOriginal()"}]
        plan = shards.make_plan(value, SHA, "123", "2", 2)
        self.assertEqual(plan["inventory"], value)
        self.assertEqual(sorted(sum(plan["shards"], [])), sorted(self.names))

    def test_tampered_plan_cannot_omit_duplicate_or_move_methods(self):
        for mode in ("omit", "duplicate", "move", "hash"):
            plan = copy.deepcopy(self.plan)
            if mode == "omit": plan["shards"][0].pop()
            elif mode == "duplicate": plan["shards"][0].append(plan["shards"][1][0])
            elif mode == "move": plan["shards"][0], plan["shards"][1] = plan["shards"][1], plan["shards"][0]
            else: plan["inventory_sha256"] = "0" * 64
            with self.subTest(mode=mode), self.assertRaises(ValueError): shards.validate_plan(plan)

    def test_real_method_tree_shape_and_explicit_skips_qualify(self):
        names = self.plan["shards"][0]
        tree, summary = result(names, names[:1])
        receipt = shards.qualify_results(self.plan, 0, tree, summary)
        self.assertEqual(receipt["skipped"], 1)
        self.assertEqual(receipt["passed"], len(names) - 1)

    def test_failed_parameterized_argument_cannot_hide_behind_passed_method(self):
        names = self.plan["shards"][0]
        tree, summary = result(names)
        method = tree["testNodes"][0]["children"][0]
        method["children"] = [{"nodeType": "Arguments", "result": "Failed"}]
        with self.assertRaises(ValueError): shards.qualify_results(self.plan, 0, tree, summary)
        method["children"][0]["result"] = "Passed"
        self.assertEqual(shards.qualify_results(self.plan, 0, tree, summary)["passed"], len(names))

    def test_missing_duplicate_failed_unknown_and_extra_actual_methods_reject(self):
        for mode in ("missing", "duplicate", "failed", "unknown", "extra", "no-bundle"):
            names = self.plan["shards"][0]
            tree, summary = result(names)
            bundle = tree["testNodes"][0]
            cases = bundle["children"]
            if mode == "missing": cases.pop()
            elif mode == "duplicate": cases.append(copy.deepcopy(cases[0]))
            elif mode == "failed": cases[0]["result"] = "Failed"
            elif mode == "unknown": cases[0]["result"] = "Unknown"
            elif mode == "no-bundle": bundle["nodeType"] = "Test Suite"
            else: cases.append({"nodeType": "Test Case", "nodeIdentifier": "Other/testExtra()", "result": "Passed"})
            with self.subTest(mode=mode), self.assertRaises(ValueError): shards.qualify_results(self.plan, 0, tree, summary)

    def test_wrong_or_ambiguous_native_execution_platform_rejects(self):
        tree, summary = result(self.plan["shards"][0])
        for devices in ([], [{"platform": "iOS", "architecture": "arm64"}],
                        [{"platform": "macOS", "architecture": "x86_64"}],
                        tree["devices"] * 2):
            with self.subTest(devices=devices), self.assertRaises(ValueError):
                shards.qualify_results(self.plan, 0, tree | {"devices": devices}, summary)

    def test_merged_results_accept_distinct_qualified_worker_macs_only(self):
        tree, summary = result(self.plan["shards"][0])
        tree["devices"] = [{"platform": "macOS", "architecture": "arm64", "deviceId": str(index)} for index in range(4)]
        self.assertEqual(shards.qualify_results(self.plan, 0, tree, summary, maximum_devices=4)["passed"], len(self.plan["shards"][0]))
        with self.assertRaises(ValueError): shards.qualify_results(self.plan, 0, tree, summary)
        tree["devices"][3]["architecture"] = "x86_64"
        with self.assertRaises(ValueError): shards.qualify_results(self.plan, 0, tree, summary, maximum_devices=4)

    def test_summary_must_match_actual_method_results(self):
        tree, summary = result(self.plan["shards"][0])
        for key, bad in (("result", "Failed"), ("totalTestCount", 0), ("passedTests", 0), ("skippedTests", 1), ("failedTests", 1)):
            changed = summary | {key: bad}
            with self.subTest(key=key), self.assertRaises(ValueError): shards.qualify_results(self.plan, 0, tree, changed)

    def test_complete_current_run_receipts_combine(self):
        actual = shards.verify_receipts(self.plan, self.receipts())
        self.assertEqual(actual["methods"], 4)
        self.assertEqual(actual["passed"], 4)

    def test_missing_stale_duplicate_or_forged_receipts_reject(self):
        for mode in ("missing", "stale-sha", "stale-run", "stale-attempt", "stale-inventory", "duplicate", "omitted", "count", "failure"):
            receipts = self.receipts()
            if mode == "missing": receipts.pop()
            elif mode.startswith("stale"):
                key = {"stale-sha": "source_sha", "stale-run": "run_id", "stale-attempt": "attempt", "stale-inventory": "inventory_sha256"}[mode]
                receipts[0][key] = "wrong"
            elif mode == "duplicate": receipts[1] = copy.deepcopy(receipts[0])
            elif mode == "omitted": receipts[0]["cases"].pop(next(iter(receipts[0]["cases"])))
            elif mode == "count": receipts[0]["passed"] = 0
            else: receipts[0]["cases"][next(iter(receipts[0]["cases"]))] = "Failed"
            with self.subTest(mode=mode), self.assertRaises(ValueError): shards.verify_receipts(self.plan, receipts)


class ProductRestoreTests(unittest.TestCase):
    def fixture(self, root, malicious=None):
        import io
        import json
        import tarfile
        from types import SimpleNamespace
        products = root / "products"
        products.mkdir()
        sdk = root / "sdk.txt"
        sdk.write_text("ImageOS=macos27 ImageVersion=first\nCompiler=pinned\n")
        payload = inventory(["NativeTests/Probe/testFirst()", "NativeTests/Probe/testSecond()"])
        plan = shards.make_plan(payload, SHA, "123", "2", 2)
        (products / "native-test-plan.json").write_text(json.dumps(plan))
        archive = products / "macos-products.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            name = malicious if malicious else "Build/Products/native.xctestrun"
            member = tarfile.TarInfo(name)
            data = b"manifest"
            member.size = len(data)
            output.addfile(member, io.BytesIO(data))
        receipt = {"source_sha": SHA, "run_id": "123", "attempt": "2",
                   "prepared_archive_sha256": shards.file_digest(archive),
                   "xctestrun": "Build/Products/native.xctestrun", "sdk_receipt_sha256": shards.sdk_digest(sdk)}
        (products / "native-products-receipt.json").write_text(json.dumps(receipt))
        return SimpleNamespace(products=products, derived=root / "derived", source_sha=SHA,
                               run_id="123", attempt="2", sdk_receipt=sdk,
                               prepared_sha256=receipt["prepared_archive_sha256"])

    def test_exact_producer_products_restore_to_fresh_root(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            args = self.fixture(Path(directory))
            plan, path = shards.restore(args)
            self.assertEqual(path.read_text(), "manifest")
            self.assertEqual(plan["source_sha"], SHA)
            with self.assertRaises(ValueError): shards.restore(args)

    def test_archive_digest_current_source_and_sdk_drift_reject_before_extraction(self):
        import tempfile
        for mode in ("archive", "source", "run", "attempt", "sdk", "sdk-newlines"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory))
                if mode == "archive": args.prepared_sha256 = "0" * 64
                elif mode == "source": args.source_sha = "b" * 40
                elif mode == "run": args.run_id = "999"
                elif mode == "attempt": args.attempt = "9"
                elif mode == "sdk": args.sdk_receipt.write_text("ImageOS=macos27 ImageVersion=first\nCompiler=changed\n")
                else: args.sdk_receipt.write_bytes(args.sdk_receipt.read_bytes().replace(b"\n", b"\r\n"))
                with self.assertRaises(ValueError): shards.restore(args)
                self.assertFalse(args.derived.exists())

    def test_runner_image_diagnostic_rollout_preserves_canonical_provenance(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            args = self.fixture(Path(directory))
            args.sdk_receipt.write_text(args.sdk_receipt.read_text().replace("ImageVersion=first", "ImageVersion=second"))
            _, path = shards.restore(args)
            self.assertTrue(path.is_file())

    def test_archive_traversal_and_unexpected_roots_reject_before_extraction(self):
        import tempfile
        for name in ("../escape", "/tmp/escape", "Build/Products/../../escape", "Build/._Products", "other/file"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory), name)
                with self.assertRaises(ValueError): shards.restore(args)
                self.assertFalse(args.derived.exists())

    def test_archive_symlink_must_remain_inside_products(self):
        import json
        import tarfile
        import tempfile
        for target in ("../../../../escape", "/tmp/escape"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory))
                archive = args.products / "macos-products.tar.gz"
                with tarfile.open(archive, "w:gz") as output:
                    member = tarfile.TarInfo("Build/Products/link")
                    member.type, member.linkname = tarfile.SYMTYPE, target
                    output.addfile(member)
                args.prepared_sha256 = shards.file_digest(archive)
                receipt = json.loads((args.products / "native-products-receipt.json").read_text())
                receipt["prepared_archive_sha256"] = args.prepared_sha256
                (args.products / "native-products-receipt.json").write_text(json.dumps(receipt))
                with self.assertRaises(ValueError): shards.restore(args)
                self.assertFalse(args.derived.exists())


if __name__ == "__main__": unittest.main()
