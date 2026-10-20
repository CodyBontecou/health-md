#!/usr/bin/env python3
"""Execute actual sharded workflow/owner boundaries with SDK-only interception.

Tests native, tee and parser exit propagation on phone and tablet. This is not
native UI qualification; exact device/case inventory is covered by host contracts.
"""
import json
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
        for shard in (0, 3):
            for native, tee, parser, expected in scenarios:
                with self.subTest(shard=shard, native=native, tee=tee, parser=parser):
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
