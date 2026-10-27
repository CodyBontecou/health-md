"""Build observability must preserve failure, cancellation and argument privacy."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'observe-ci-build.py'


class BuildObserverTests(unittest.TestCase):
    def test_success_failure_and_output_are_forwarded_without_argument_logging(self):
        for status in (0, 7):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                log = Path(directory) / 'processes.log'
                result = subprocess.run([sys.executable, str(SCRIPT), '--log', str(log), '--',
                                         sys.executable, '-c', f'print("build output"); raise SystemExit({status})',
                                         'synthetic-argument-must-not-be-logged'],
                                        capture_output=True, text=True)
                self.assertEqual(status, result.returncode, result.stderr)
                self.assertIn('build output', result.stdout.splitlines())
                self.assertNotIn('synthetic-argument-must-not-be-logged', log.read_text())
                self.assertNotIn('synthetic-argument-must-not-be-logged', result.stdout)

    def test_telemetry_io_failure_does_not_replace_build_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            blocked = Path(directory) / 'not-a-directory'
            blocked.write_text('fixture')
            result = subprocess.run([sys.executable, str(SCRIPT), '--log', str(blocked / 'log'), '--',
                                     sys.executable, '-c', 'raise SystemExit(7)'], capture_output=True)
            self.assertEqual(7, result.returncode)

    def test_cancellation_remains_failure_even_when_child_handles_signal_successfully(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'processes.log'
            ready = Path(directory) / 'ready'
            code = ('import signal,time,pathlib; '
                    'signal.signal(signal.SIGTERM, lambda *_: exit(0)); '
                    f'pathlib.Path({str(ready)!r}).write_text("ready"); time.sleep(60)')
            process = subprocess.Popen([sys.executable, str(SCRIPT), '--log', str(log), '--',
                                        sys.executable, '-c', code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not (ready.exists() and log.exists() and log.stat().st_size) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(ready.exists())
                pid = json.loads(log.read_text().splitlines()[0])['pid']
                process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(143, process.returncode, (stdout, stderr))
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)

    def test_cancellation_stops_descendants_after_leader_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'processes.log'
            fifo = Path(directory) / 'liveness'
            os.mkfifo(fifo)
            reader = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
            grandchild = ('import os,signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                          f'fd=os.open({str(fifo)!r}, os.O_WRONLY); os.write(fd,b"x"); time.sleep(60)')
            leader = ('import signal,subprocess,time; signal.signal(signal.SIGTERM, lambda *_: exit(0)); '
                      f'subprocess.Popen([{sys.executable!r},"-c",{grandchild!r}], '
                      'stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(60)')
            process = subprocess.Popen([sys.executable, str(SCRIPT), '--log', str(log), '--',
                                        sys.executable, '-c', leader], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            group = None
            try:
                self.assertTrue(select.select([reader], [], [], 5)[0], 'Descendant never became ready')
                self.assertEqual(b'x', os.read(reader, 1))
                group = json.loads(log.read_text().splitlines()[0])['pid']
                process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(143, process.returncode, (stdout, stderr))
                self.assertTrue(select.select([reader], [], [], 5)[0], 'Owned descendant survived cancellation')
                self.assertEqual(b'', os.read(reader, 1), 'Descendant must close its liveness pipe')
            finally:
                if group is not None:
                    try:
                        os.killpg(group, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)
                os.close(reader)


if __name__ == '__main__':
    unittest.main()
