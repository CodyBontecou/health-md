#!/usr/bin/env python3
"""A stop request is not sufficient while the fixture daemon can still write."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('cache_fixture', Path(__file__).resolve().parents[1] / 'test-ci-gradle-cache.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class FixtureCleanupTest(unittest.TestCase):
    def test_waits_for_owned_writer_before_temporary_home_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            writer = subprocess.Popen([sys.executable, '-c',
                'import pathlib,sys,time; time.sleep(.2); pathlib.Path(sys.argv[1]).write_text("final daemon write")',
                str(root / 'registry.bin')])
            try:
                (root / f'daemon-{writer.pid}.out.log').touch()
                fixture.await_daemon_shutdown(root, timeout=5)
                self.assertEqual('final daemon write', (root / 'registry.bin').read_text())
            finally:
                writer.wait(timeout=5)

    def test_live_daemon_is_a_failure_and_is_not_killed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / f'daemon-{os.getpid()}.out.log').touch()
            with self.assertRaisesRegex(RuntimeError, 'did not stop'):
                fixture.await_daemon_shutdown(root, timeout=.01)
            os.kill(os.getpid(), 0)

    def test_no_fixture_daemon_needs_no_wait(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture.await_daemon_shutdown(Path(directory), timeout=.01)


if __name__ == '__main__':
    unittest.main()
