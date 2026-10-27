import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("verify_xcresult", Path(__file__).with_name("verify_xcresult.py"))
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


def results(*cases):
    return {"testNodes": [{"nodeType": "Test Suite", "children": [
        {"nodeType": "Test Case", "nodeIdentifier": identity + "()", "result": result}
        for identity, result in cases
    ]}]}


class NativeInventoryTests(unittest.TestCase):
    def test_actual_passes_are_required(self):
        self.assertEqual(module.verify(results(("Suite/testA", "Passed")), ["Suite/testA"]), 1)
        for document in (results(), results(("Suite/testOther", "Passed")), results(("Suite/testA", "Passed"), ("Suite/testA", "Passed"))):
            with self.assertRaises(ValueError):
                module.verify(document, ["Suite/testA"])

    def test_skips_failures_and_unknown_verdicts_do_not_pass(self):
        for verdict in ("Failed", "Skipped", "Expected Failure", None):
            with self.assertRaises(ValueError):
                module.verify(results(("Suite/testA", verdict)), ["Suite/testA"])

    def test_empty_or_duplicate_expectations_do_not_pass(self):
        for expected in ([], ["Suite/testA", "Suite/testA"]):
            with self.assertRaises(ValueError):
                module.verify(results(("Suite/testA", "Passed")), expected)


if __name__ == "__main__":
    unittest.main()
