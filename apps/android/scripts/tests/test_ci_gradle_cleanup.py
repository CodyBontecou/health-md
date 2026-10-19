#!/usr/bin/env python3
"""Exercise fixture teardown at the real main() boundary without running Gradle."""
from __future__ import annotations

import contextlib
import errno
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


FIXTURE_PATH = Path(__file__).resolve().parents[1] / "test-ci-gradle-cache.py"
SPEC = importlib.util.spec_from_file_location("ci_gradle_cache", FIXTURE_PATH)
assert SPEC and SPEC.loader
fixture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixture)


class FixtureCleanupTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="healthmd-fixture-cleanup-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name).resolve()
        self.directories: list[Path] = []
        self.cleanup_attempts = 0
        self.stop_calls: list[tuple[list[str], dict]] = []
        self.clock = 0.0
        self.test_runs = 0
        self.executions = 0

    def exercise(self, *, cleanup_errno: int | None = None, permanent: bool = False,
                 fail_scenario: bool = False, stop_exit: int = 0,
                 stop_timeout: bool = False) -> None:
        real_directory = tempfile.mkdtemp
        real_rmtree = shutil.rmtree

        def directory(*args, **kwargs):
            kwargs["dir"] = self.parent
            temporary = real_directory(*args, **kwargs)
            self.directories.append(Path(temporary))
            return temporary

        def rmtree(path, *args, **kwargs):
            if self.directories and Path(path) == self.directories[0]:
                self.cleanup_attempts += 1
                if cleanup_errno is not None and (permanent or self.cleanup_attempts == 1):
                    # Model a late daemon write at the same recursive cleanup boundary
                    # as CI, after the fixture's scoped --stop command has returned.
                    self.assertEqual(1, len(self.stop_calls))
                    daemon = Path(path) / "gradle-home" / "daemon"
                    daemon.mkdir(parents=True, exist_ok=True)
                    (daemon / "late-write.log").write_text("daemon shutdown\n")
                    raise OSError(cleanup_errno, "fixture cleanup injection", str(daemon))
            return real_rmtree(path, *args, **kwargs)

        def gradle(command, **kwargs):
            if command[-1] == "--stop":
                self.stop_calls.append((command, kwargs))
                if stop_timeout:
                    raise subprocess.TimeoutExpired(command, 30, output="shutdown stalled")
                return subprocess.CompletedProcess(command, stop_exit, "isolated daemon stop\n")
            self.test_runs += 1
            project = Path(command[command.index("--project-dir") + 1])
            if fail_scenario:
                return subprocess.CompletedProcess(command, 2, "safety scenario failed\n")
            if self.test_runs in (1, 4, 5, 6, 7):
                self.executions += 1
                (project / "executions.txt").write_text("executed\n" * self.executions)
            failed = self.test_runs == 7
            reports = project / "build" / "test-results" / "test"
            reports.mkdir(parents=True, exist_ok=True)
            (reports / "TEST-fixture.xml").write_text(
                '<testsuite tests="1" failures="' + str(int(failed)) +
                '" errors="0" skipped="0"/>'
            )
            compile_result = " FROM-CACHE" if self.test_runs in (2, 4, 5) else " UP-TO-DATE"
            test_result = {2: " FROM-CACHE", 3: " UP-TO-DATE", 7: " FAILED"}.get(self.test_runs, "")
            output = "> Task :compileJava" + compile_result + "\n> Task :test" + test_result + "\n"
            return subprocess.CompletedProcess(command, int(failed), output)

        def sleep(seconds):
            self.clock += seconds

        with patch.object(fixture.tempfile, "mkdtemp", side_effect=directory), \
                patch.object(fixture.shutil, "rmtree", side_effect=rmtree), \
                patch.object(fixture.subprocess, "run", side_effect=gradle), \
                patch.object(fixture.time, "monotonic", side_effect=lambda: self.clock), \
                patch.object(fixture.time, "sleep", side_effect=sleep), \
                patch.object(sys, "argv", ["test-ci-gradle-cache.py", "--gradle",
                                          str(self.parent / "gradle")]), \
                contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            fixture.main()

    def assert_removed_and_scoped(self) -> None:
        self.assertEqual(1, len(self.directories))
        self.assertFalse(self.directories[0].exists())
        self.assertEqual(1, len(self.stop_calls))
        command, options = self.stop_calls[0]
        self.assertEqual([str(self.parent / "gradle"), "--stop"], command)
        self.assertEqual(str(self.directories[0] / "gradle-home"),
                         options["env"]["GRADLE_USER_HOME"])
        self.assertEqual(30, options["timeout"])

    def test_late_daemon_write_retries_then_removes_the_owned_directory(self) -> None:
        self.exercise(cleanup_errno=errno.ENOTEMPTY)
        self.assertEqual(7, self.test_runs)
        self.assertEqual(5, self.executions)
        self.assertEqual(2, self.cleanup_attempts)
        self.assert_removed_and_scoped()

    def test_permanent_nonempty_directory_fails_after_a_bounded_wait(self) -> None:
        with self.assertRaises(OSError) as raised:
            self.exercise(cleanup_errno=errno.ENOTEMPTY, permanent=True)
        self.assertEqual(errno.ENOTEMPTY, raised.exception.errno)
        self.assertGreater(self.cleanup_attempts, 1)
        self.assertGreaterEqual(self.clock, 5)
        self.assertLessEqual(self.clock, 5.1)

    def test_other_filesystem_errors_are_not_retried(self) -> None:
        with self.assertRaises(OSError) as raised:
            self.exercise(cleanup_errno=errno.EACCES)
        self.assertEqual(errno.EACCES, raised.exception.errno)
        self.assertEqual(1, self.cleanup_attempts)
        self.assertEqual(0, self.clock)

    def test_safety_scenario_failure_survives_transient_cleanup_race(self) -> None:
        with self.assertRaisesRegex(AssertionError, "safety scenario failed"):
            self.exercise(cleanup_errno=errno.ENOTEMPTY, fail_scenario=True)
        self.assertEqual(2, self.cleanup_attempts)
        self.assert_removed_and_scoped()

    def test_safety_failure_is_preserved_when_cleanup_also_fails(self) -> None:
        with self.assertRaisesRegex(AssertionError, "safety scenario failed") as raised:
            self.exercise(cleanup_errno=errno.ENOTEMPTY, permanent=True, fail_scenario=True)
        self.assertTrue(any("cleanup" in note and str(self.directories[0]) in note
                            for note in raised.exception.__notes__))

    def test_failed_stop_propagates_and_still_removes_fixture_directory(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "isolated daemon stop"):
            self.exercise(stop_exit=9)
        self.assert_removed_and_scoped()

    def test_stop_timeout_propagates_and_still_removes_fixture_directory(self) -> None:
        with self.assertRaises(subprocess.TimeoutExpired):
            self.exercise(stop_timeout=True)
        self.assert_removed_and_scoped()

    def test_safety_failure_is_preserved_when_stop_also_fails(self) -> None:
        with self.assertRaisesRegex(AssertionError, "safety scenario failed") as raised:
            self.exercise(fail_scenario=True, stop_exit=9)
        self.assertTrue(any("isolated daemon stop" in note for note in raised.exception.__notes__))
        self.assert_removed_and_scoped()

    def test_writer_exit_is_awaited_after_stop_and_before_directory_removal(self) -> None:
        def wait(directory):
            self.assertEqual(1, len(self.stop_calls))
            self.assertEqual(0, self.cleanup_attempts)
            self.assertEqual(self.directories[0] / "gradle-home", directory)
            self.assertTrue(self.directories[0].exists())
        with patch.object(fixture, "await_daemon_shutdown", side_effect=wait) as awaited:
            self.exercise(cleanup_errno=errno.ENOTEMPTY)
            awaited.assert_called_once()
        self.assert_removed_and_scoped()

    def test_writer_shutdown_failure_fails_an_otherwise_successful_fixture(self) -> None:
        with patch.object(fixture, "await_daemon_shutdown", side_effect=RuntimeError("writer still active")):
            with self.assertRaisesRegex(RuntimeError, "writer still active"):
                self.exercise()
        self.assert_removed_and_scoped()

    def test_safety_failure_survives_writer_shutdown_failure(self) -> None:
        with patch.object(fixture, "await_daemon_shutdown", side_effect=RuntimeError("writer still active")):
            with self.assertRaisesRegex(AssertionError, "safety scenario failed") as raised:
                self.exercise(fail_scenario=True)
        self.assertTrue(any("writer still active" in note for note in raised.exception.__notes__))
        self.assert_removed_and_scoped()


if __name__ == "__main__":
    unittest.main()
