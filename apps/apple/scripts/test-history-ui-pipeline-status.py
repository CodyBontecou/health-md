#!/usr/bin/env python3
"""Execute actual sharded workflow/owner boundaries with SDK-only interception.

Tests native, tee and parser exit propagation on phone and tablet. This is not
native UI qualification; exact device/case inventory is covered by host contracts.
"""
import json
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).with_name("tests")))
import test_ios_ui_build_contract as fixtures


class PipelineStatusControls(unittest.TestCase):
    def test_phone_and_tablet_native_tee_parser_failures_remain_blocking(self):
        # One invocation per matrix job; a failure must never publish a passing
        # case receipt, regardless of the other independently successful shards.
        scenarios = [(0, 0, 0, 0), (73, 0, 0, 73), (0, 17, 0, 17),
                     (0, 0, 1, 1), (0, 0, 2, 2), (73, 17, 0, 17), (73, 0, 2, 2)]
        # Each scenario owns its temp directory, environment, process groups and
        # fixture cleanup. Overlap the real owner-settlement waits, not their
        # assertions or the time boundary those assertions must observe.
        def run_scenario(shard, native, tee, parser, expected):
            fixture = fixtures.WorkflowExecutionTests(methodName="runTest")
            fixture.setUp()
            try:
                artifact = fixture.build()
                for name, executable, status in [("tee", "/usr/bin/tee", tee), ("grep", "/usr/bin/grep", parser)]:
                    fixture.executable(fixture.bin / name,
                        f'#!/bin/bash\n{executable} "$@"\nresult=$?\n'
                        f'if [[ {status} -ne 0 ]]; then exit {status}; fi\nexit "$result"\n')
                if native:
                    fixture.environment["MD_MOCK_FAILURE"] = "test-without-building"
                result = fixture.run_step("Run UI smoke tests (iOS)", artifact, shard)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                owner = json.loads((fixture.root / "build/logs/ui-owner-shard.json").read_text())
                self.assertTrue(owner["process_clean"])
                self.assertTrue(owner["eligible_to_continue"])
                self.assertEqual(owner["stages"], [{"native": native, "tee": tee, "parser": parser}])
                self.assertEqual((fixture.root / "build/logs/ui-case-receipt.json").exists(), expected == 0)
                self.assertTrue((fixture.root / "build/logs/build-ios-ui.log").is_file())
            finally:
                fixture.doCleanups()

        with ThreadPoolExecutor(max_workers=4) as pool:
            pending = [(shard, values, pool.submit(run_scenario, shard, *values))
                       for shard in (0, 3) for values in scenarios]
            # Report every scenario on unittest's main thread, including all
            # failures; no worker may turn an assertion into a passing result.
            for shard, (native, tee, parser, expected), future in pending:
                with self.subTest(shard=shard, native=native, tee=tee, parser=parser):
                    future.result()


if __name__ == "__main__":
    unittest.main(verbosity=2)
