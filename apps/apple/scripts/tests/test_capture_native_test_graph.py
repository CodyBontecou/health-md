"""Actual process-group controls for graph-only diagnostics; never launch apps."""
from pathlib import Path
import importlib.util
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace

SCRIPT = Path(__file__).resolve().parents[1] / 'capture-native-test-graph.py'
FIXTURE = '''import os,pathlib,signal,subprocess,sys,time
root=pathlib.Path(sys.argv[1]);mode=sys.argv[2]
signal.signal(signal.SIGTERM,signal.SIG_IGN)
(root/'leader').write_text(str(os.getpid()))
child=subprocess.Popen([sys.executable,'-c', "import os,pathlib,signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);p=pathlib.Path("+repr(str(root))+ ");(p/'descendant').write_text(str(os.getpid()));time.sleep(1);(p/'late').write_text('late')"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
while not (root/'descendant').exists():time.sleep(.01)
(root/'ready').touch()
if mode!='cancel':
 print('note: Target dependency graph ('+('3' if mode=='unexpected' else '2')+' targets)',flush=True)
 print("    Target 'HealthMdTests' in project 'HealthMd'",flush=True)
 if mode!='incomplete':print("    Target 'HealthMd' in project 'HealthMd' (no dependencies)",flush=True)
 if mode=='unexpected':print("    Target 'HealthMd-macOS' in project 'HealthMd' (no dependencies)",flush=True)
if mode=='incomplete':sys.exit(7)
time.sleep(2)
'''


class GraphCaptureTests(unittest.TestCase):
    def test_permission_denial_is_only_tolerated_for_observed_zombie_only_group(self):
        spec = importlib.util.spec_from_file_location('capture_graph', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for state in ['Z', 'S']:
            with self.subTest(state=state), patch.object(module.os, 'killpg', side_effect=PermissionError), \
                    patch.object(module.subprocess, 'run', return_value=SimpleNamespace(stdout=f'123 {state}\n456 S\n')):
                if state == 'Z': module.signal_owned_group(123, signal.SIGTERM)
                else:
                    with self.assertRaises(PermissionError): module.signal_owned_group(123, signal.SIGTERM)

    def run_fixture(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / 'fixture.py'
            fixture.write_text(FIXTURE)
            sentinel = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(10)'], start_new_session=True)
            process = subprocess.Popen([sys.executable, str(SCRIPT), '--platform', 'iOS', '--log', str(root / 'build.log'),
                                        '--', sys.executable, str(fixture), str(root), mode],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                if mode == 'cancel':
                    deadline = time.monotonic() + 5
                    while not (root / 'ready').exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    self.assertTrue((root / 'ready').exists())
                    process.send_signal(signal.SIGTERM)
                    time.sleep(.05)
                    process.send_signal(signal.SIGTERM)
                output, _ = process.communicate(timeout=10)
                self.assertEqual(process.returncode, {'success': 0, 'cancel': 143}.get(mode, 1), output)
                if mode == 'success': self.assertIn('"diagnostic_only": true', output)
                else: self.assertNotIn('"diagnostic_only": true', output)
                self.assertIsNone(sentinel.poll(), 'Unrelated process must survive diagnostic cleanup')
                # Observe past the actual late-write point, even if the leader
                # exited. Natural fixture expiry alone is not cleanup evidence.
                time.sleep(1.1)
                self.assertFalse((root / 'late').exists(), output)
                self.assertIsNone(sentinel.poll())
            finally:
                if process.poll() is None: process.terminate()
                process.communicate(timeout=5)
                sentinel.terminate()
                sentinel.wait(timeout=5)

    def test_complete_graph_stops_leader_and_term_ignoring_descendant(self): self.run_fixture('success')
    def test_unexpected_root_remains_failure_after_owned_cleanup(self): self.run_fixture('unexpected')
    def test_incomplete_graph_never_qualifies(self): self.run_fixture('incomplete')
    def test_repeated_cancellation_still_cleans_owned_group_and_returns143(self): self.run_fixture('cancel')


if __name__ == '__main__': unittest.main()
