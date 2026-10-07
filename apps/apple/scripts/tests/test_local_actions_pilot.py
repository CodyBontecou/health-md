#!/usr/bin/env python3
"""Safety regressions for the optional local pilot; no Apple tools are executed."""

from __future__ import annotations

from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

import local_actions_pilot as pilot  # noqa: E402


SHA = "a" * 40
SIMULATOR = "12345678-1234-1234-1234-123456789abc"
TOOLS = {"xcode": "Xcode 26.6", "swift": "Swift version 6.3", "sdk": "26.6",
         "device_type": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
         "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-5"}


def runtime(version: str, *, available: bool = True, phones: tuple[str, ...] = ("iPhone 17",)) -> dict:
    return {"identifier": f"com.apple.CoreSimulator.SimRuntime.iOS-{version}",
            "isAvailable": available, "supportedDeviceTypes": [
                {"name": name, "identifier": f"device.{name.replace(' ', '-')}",
                 "productFamily": "iPad" if name.startswith("iPad") else "iPhone"}
                for name in phones]}


class PilotSafetyTests(unittest.TestCase):
    def test_newest_available_compatible_runtime_and_preferred_phone_are_selected(self):
        payload = {"runtimes": [runtime("26-2"), runtime("27-0"),
                                runtime("26-6", available=False),
                                runtime("26-5", phones=("iPad Pro", "iPhone 15", "iPhone 17 Pro"))]}
        self.assertEqual(pilot.select_runtime(payload, "26.6"),
                         ("device.iPhone-17-Pro", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"))

    def test_no_usable_runtime_fails_without_selecting_unavailable_or_unsupported_devices(self):
        for candidates in ([], [runtime("27-0")], [runtime("26-5", available=False)],
                           [runtime("26-5", phones=("iPad Pro",))], [runtime("16-4")]):
            with self.subTest(candidates=candidates), self.assertRaises(ValueError):
                pilot.select_runtime({"runtimes": candidates}, "26.6")

    def test_empty_failed_or_invalid_test_counts_cannot_report_success(self):
        pilot.validate_summary({"result": "Passed", "passedTests": 2, "failedTests": 0})
        invalid = ({}, {"result": "Failed", "passedTests": 2, "failedTests": 1},
                   {"result": "Passed", "passedTests": 0},
                   {"result": "Passed", "passedTests": True},
                   {"result": "Passed", "passedTests": "2"},
                   {"result": "Passed", "passedTests": 2, "failedTests": False},
                   {"result": "Passed", "passedTests": 2, "failedTests": "0"},
                   {"result": "Passed", "passedTests": 2, "failedTests": 1})
        for summary in invalid:
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                pilot.validate_summary(summary)

    def exercise(self, output: Path, *, failing_command: str | None = None,
                 interrupt: bool = False, dirty: str = "", source: str = SHA):
        commands = []
        cleanup = []
        handlers = {}
        killed = []
        processes = []

        def capture(*args):
            if args[0] == "git":
                return SHA if "rev-parse" in args else dirty
            if args[:3] == ("xcrun", "simctl", "create"):
                return SIMULATOR
            if args[:2] == ("xcrun", "xcresulttool"):
                return json.dumps({"result": "Passed", "passedTests": 12, "failedTests": 0})
            raise AssertionError(f"Unexpected command: {args}")

        def install_handler(signum, handler):
            previous = handlers.get(signum, signal.SIG_DFL)
            handlers[signum] = handler
            return previous

        class Process:
            pid = 987654

            def __init__(self, args, **kwargs):
                commands.append(args)
                processes.append(self)
                self.args = args
                self.running = True
                self.assertion = kwargs
                if args[0] == "xcodebuild":
                    Path(args[args.index("-resultBundlePath") + 1]).mkdir()

            def poll(self):
                return None if self.running else 0

            def wait(self, timeout=None):
                if interrupt and self.args[0] == "xcodebuild" and self.running:
                    handlers[signal.SIGTERM](signal.SIGTERM, None)
                self.running = False
                return 65 if self.args[0] == failing_command else 0

        def killpg(pid, signum):
            killed.append((pid, signum))
            for process in processes:
                if process.pid == pid:
                    process.running = False

        def run(args, **kwargs):
            cleanup.append(args)
            return subprocess.CompletedProcess(args, 0)

        with ExitStack() as stack:
            stack.enter_context(patch.object(pilot, "preflight", return_value=TOOLS))
            stack.enter_context(patch.object(pilot, "capture", side_effect=capture))
            stack.enter_context(patch.object(pilot.subprocess, "Popen", side_effect=Process))
            stack.enter_context(patch.object(pilot.subprocess, "run", side_effect=run))
            stack.enter_context(patch.object(pilot.signal, "signal", side_effect=install_handler))
            stack.enter_context(patch.object(pilot.os, "killpg", side_effect=killpg))
            stack.enter_context(redirect_stdout(io.StringIO()))
            stack.enter_context(redirect_stderr(io.StringIO()))
            code = pilot.run_pilot(output, source)
        return code, commands, cleanup, handlers, killed, processes

    def test_source_mismatch_dirty_checkout_and_stale_outputs_fail_before_running_tools(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for case in ("mismatch", "dirty", "untracked", "stale"):
                output = root / case
                if case == "stale":
                    stale = output / "ios-unit"
                    stale.mkdir(parents=True)
                    (stale / "receipt.json").write_text("old evidence")
                def git_capture(*args):
                    self.assertEqual(args[0], "git")
                    if "rev-parse" in args:
                        return SHA
                    self.assertIn("--untracked-files=all", args)
                    return {"dirty": " M source.swift", "untracked": "?? injected.swift"}.get(case, "")

                with self.subTest(case=case), ExitStack() as stack:
                    stack.enter_context(patch.object(pilot, "preflight", return_value=TOOLS))
                    stack.enter_context(patch.object(pilot, "capture", side_effect=git_capture))
                    process = stack.enter_context(patch.object(pilot.subprocess, "Popen"))
                    error = FileExistsError if case == "stale" else ValueError
                    with self.assertRaises(error):
                        pilot.run_pilot(output, "b" * 40 if case == "mismatch" else SHA)
                    process.assert_not_called()
                if case == "stale":
                    self.assertEqual((output / "ios-unit" / "receipt.json").read_text(), "old evidence")
                else:
                    self.assertFalse(output.exists())

    def test_success_is_unsigned_uses_isolated_outputs_and_cleans_only_created_simulator(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "attempt"
            code, commands, cleanup, handlers, killed, processes = self.exercise(output)
            self.assertEqual(code, 0)
            self.assertEqual(cleanup, [["xcrun", "simctl", action, SIMULATOR]
                                       for action in ("shutdown", "delete")])
            xcode = next(args for args in commands if args[0] == "xcodebuild")
            self.assertEqual(xcode[xcode.index("-derivedDataPath") + 1], str(output / "ios-unit" / "DerivedData"))
            self.assertEqual(xcode[xcode.index("-destination") + 1], f"platform=iOS Simulator,id={SIMULATOR}")
            self.assertIn("CODE_SIGNING_ALLOWED=NO", xcode)
            self.assertTrue(all(process.assertion["start_new_session"] for process in processes))
            receipt = json.loads((output / "ios-unit" / "receipt.json").read_text())
            self.assertEqual((receipt["result"], receipt["source_sha"], receipt["passed_tests"]), ("passed", SHA, 12))
            self.assertEqual(handlers, {signal.SIGINT: signal.SIG_DFL, signal.SIGTERM: signal.SIG_DFL})
            self.assertEqual(killed, [])

    def test_failed_test_command_preserves_failure_and_confined_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "attempt"
            code, _, cleanup, _, _, _ = self.exercise(output, failing_command="xcodebuild")
            self.assertEqual(code, 1)
            receipt = json.loads((output / "ios-unit" / "receipt.json").read_text())
            self.assertEqual(receipt["result"], "failed")
            self.assertNotIn("passed_tests", receipt)
            self.assertEqual(cleanup, [["xcrun", "simctl", action, SIMULATOR]
                                       for action in ("shutdown", "delete")])

    def test_cancellation_terminates_only_active_process_group_and_own_simulator(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "attempt"
            code, _, cleanup, handlers, killed, _ = self.exercise(output, interrupt=True)
            self.assertEqual(code, 130)
            self.assertEqual(killed, [(987654, signal.SIGTERM)])
            self.assertEqual(cleanup, [["xcrun", "simctl", action, SIMULATOR]
                                       for action in ("shutdown", "delete")])
            self.assertEqual(handlers, {signal.SIGINT: signal.SIG_DFL, signal.SIGTERM: signal.SIG_DFL})
            self.assertEqual(json.loads((output / "ios-unit" / "receipt.json").read_text())["result"], "interrupted")

    def test_shell_wrapper_forwards_arguments_and_preserves_nonzero_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            interpreter = root / "python3"
            record = root / "arguments"
            interpreter.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$PILOT_TEST_RECORD"\nexit 17\n')
            interpreter.chmod(0o700)
            environment = dict(os.environ, PATH=f"{root}:/usr/bin:/bin", PILOT_TEST_RECORD=str(record))
            result = subprocess.run(["/bin/bash", str(SCRIPTS_DIR / "run-local-actions-pilot.sh"),
                                     "--output-dir", str(root / "output with spaces")],
                                    env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 17)
            self.assertEqual(record.read_text().splitlines(), [str(SCRIPTS_DIR / "local_actions_pilot.py"),
                                                               "--output-dir", str(root / "output with spaces")])


if __name__ == "__main__":
    unittest.main()
