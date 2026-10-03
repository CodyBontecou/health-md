#!/usr/bin/env python3
"""Hosted-only actual-owner controls, POSIX Ubuntu + standard macOS.

Not native SDK/UI qualification. No /proc, subreaper or external timeout tool.
Independent observer checks process absence and no late raw/result writes.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid
import unittest

SOURCE = Path(__file__).with_name("run-owned-ui.py")
spec = importlib.util.spec_from_file_location("owned_ui", SOURCE)
owner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owner)

FIXTURE = '''import os, pathlib, signal, subprocess, sys, time
mode = sys.argv[1]
with pathlib.Path('calls').open('a') as f: f.write(mode + '\\n')
print('Test Case ownership fixture', flush=True)
if mode == 'late':
 signal.signal(signal.SIGTERM, signal.SIG_IGN)
 time.sleep(4)
 pathlib.Path('late-result').write_text('late write')
 print('Test Case late raw write', flush=True)
elif mode in ('hold', 'orphan'):
 output = None if mode == 'hold' else subprocess.DEVNULL
 subprocess.Popen([sys.executable, __file__, 'late'], stdout=output, stderr=output)
 pathlib.Path('ready').touch()
elif mode == 'near-exit':
 os.kill(int(pathlib.Path('supervisor').read_text()), signal.SIGTERM)
elif mode == 'slow':
 pathlib.Path('ready').touch()
 time.sleep(2)
else:
 sys.exit(int(mode))
'''


class OwnershipControls(unittest.TestCase):
    def setUp(self):
        self.supervisors = []
        self.temporary = tempfile.TemporaryDirectory(prefix="health172-process-")
        self.cwd = Path(self.temporary.name)
        (self.cwd / "native.py").write_text(FIXTURE)
        self.sentinel = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                        start_new_session=True)

    def tearDown(self):
        try:
            # Retained direct supervisor handles first, even after assertion failure.
            for process in self.supervisors:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=1)
            # Only test-created anchors whose LIVE command includes the actual
            # source path + anchor role + unique owner may authorize a final kill.
            # A receipt alone (including mutated sentinel PGIDs) never does.
            for path in (self.cwd / "records").glob("ui-owner-*.json"):
                try:
                    value = json.loads(path.read_text())
                    identifier = str(uuid.UUID(value["owner"]))
                    groups = value["groups"]
                except (ValueError, KeyError, TypeError):
                    continue
                for group in groups:
                    if not owner.positive_group(group):
                        continue
                    def anchored():
                        result = subprocess.run(["ps", "-ax", "-o", "pid=,pgid=,stat=,command="],
                                                capture_output=True, text=True, check=True, timeout=1)
                        for line in result.stdout.splitlines():
                            fields = line.split(maxsplit=3)
                            if len(fields) == 4 and int(fields[0]) == group and int(fields[1]) == group:
                                return (not fields[2].startswith("Z") and str(SOURCE) in fields[3]
                                        and "--anchor" in fields[3] and identifier in fields[3])
                        return False
                    if anchored():
                        os.killpg(group, signal.SIGTERM)
                        time.sleep(0.1)
                        if anchored():
                            os.killpg(group, signal.SIGKILL)  # Last numeric signal.
                            time.sleep(0.1)
                    self.assertFalse(owner.members(group), "uncertain owned cleanup blocks native qualification")
            self.assertIsNone(self.sentinel.poll(), "unrelated sentinel must survive owned cleanup")
        finally:
            # Never lose direct sentinel/pipe/temp ownership after an assertion.
            if self.sentinel.poll() is None:
                self.sentinel.terminate()
            self.sentinel.wait(timeout=2)
            for process in self.supervisors:
                for stream in (process.stdin, process.stdout, process.stderr):
                    if stream is not None:
                        stream.close()
            self.temporary.cleanup()

    def plan(self, modes):
        return {"pipelines": [{"command": [sys.executable, str(self.cwd / "native.py"), mode],
                               "raw": "records/raw", "filter": "Test Case"} for mode in modes]}

    def launch(self, modes, seconds=3, lane="phone", require=None, fault=None, blocked=False):
        args = [sys.executable, str(SOURCE), "--lane", lane, "--records", "records", "--seconds", str(seconds),
                "--cleanup-seconds", "0.4"]
        if require:
            args += ["--require-clean", require]
        if fault:
            # Import ACTUAL helper; only inspection/record/cleanup fault points
            # are overridden once. Aggregation/admission/group cleanup stays actual.
            program = f'''import importlib.util, pathlib, argparse, sys
s=importlib.util.spec_from_file_location('owner', {str(SOURCE)!r})
m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
name='print' if {fault!r}=='stdout' else ('atomic' if {fault!r}.startswith('publication-') else {fault!r})
original=getattr(m,name,print); count=[0]; final_seen=[False]
def injected(*a,**k):
 count[0]+=1
 if {fault!r}=='stdout' and str(a[0]).startswith('Owned UI lane='): raise BrokenPipeError('fixture final stdout failure')
 if {fault!r}=='publication-afterreplace' and a[1].get('eligible_to_continue') is True:
  original(*a,**k); raise RuntimeError('fixture error after positive replace')
 if {fault!r} in ('publication-deadline','publication-signal') and a[1].get('state')=='final' and not final_seen[0]:
  final_seen[0]=True
  if {fault!r}=='publication-deadline':
   import time; time.sleep(3)
  else:
   import os, signal; os.kill(os.getpid(),signal.SIGTERM)
 if {fault!r}=='settle':
  original(*a,**k); return False
 if {fault!r}=='atomic' and a[1].get('state')=='active': raise RuntimeError('injected ownership failure')
 if {fault!r}=='members' and count[0]==1: raise RuntimeError('injected ownership failure')
 return original(*a,**k)
setattr(m,name,injected)
try:
 result=m.run(argparse.Namespace(lane='phone',records=pathlib.Path('records'),seconds=2 if {fault!r}=='publication-deadline' else 3,cleanup_seconds=0.4,require_clean=None))
except Exception:
 result=125
sys.exit(result)
'''
            args = [sys.executable, "-c", program]
        process = subprocess.Popen(args, cwd=self.cwd, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.supervisors.append(process)
        (self.cwd / "supervisor").write_text(str(process.pid))
        if not blocked:
            process.stdin.write(json.dumps(self.plan(modes)))
            process.stdin.close()
            process.stdin = None
        return process

    def finish(self, process, code):
        stdout, stderr = process.communicate(timeout=8)
        self.assertEqual(process.returncode, code, (stdout, stderr))
        receipt = json.loads((self.cwd / "records/ui-owner-phone.json").read_text())
        if receipt["process_clean"]:
            self.assertTrue(all(not owner.members(g) for g in receipt["groups"]))
        self.assertIsNone(self.sentinel.poll())
        return receipt

    def ready(self, process):
        until = time.monotonic() + 3
        while not (self.cwd / "ready").exists() and time.monotonic() < until:
            self.assertIsNone(process.poll())
            time.sleep(0.01)
        self.assertTrue((self.cwd / "ready").exists())

    def observe_late_boundary(self):
        raw = self.cwd / "records/raw"
        before = raw.read_bytes() if raw.exists() else b""
        time.sleep(4.25)  # Beyond actual mocked delayed-write point, not just leader exit.
        self.assertEqual(raw.read_bytes() if raw.exists() else b"", before)
        self.assertFalse((self.cwd / "late-result").exists())

    def test_deadline_during_each_invocation_no_next_native_or_tablet(self):
        for modes in (("hold", "0"), ("0", "hold")):
            with self.subTest(modes=modes):
                process = self.launch(modes, seconds=2)
                receipt = self.finish(process, 124)
                self.assertTrue(receipt["process_clean"])
                self.assertFalse(receipt["eligible_to_continue"])
                self.assertEqual(receipt["abort"], "deadline")
                calls = (self.cwd / "calls").read_text().splitlines()
                self.assertEqual(calls.count("0"), 0 if modes[0] == "hold" else 1)
                self.assertRaises(RuntimeError, owner.prior, self.cwd / "records/ui-owner-phone.json", "phone")
                self.observe_late_boundary()
                for name in ("records/ui-owner-phone.json", "records/ui-owner-phone.owner.json", "calls", "ready"):
                    (self.cwd / name).unlink(missing_ok=True)

    def test_TERM_INT_each_invocation_and_repeat_signal(self):
        for number in (signal.SIGTERM, signal.SIGINT):
            for modes in (("slow", "0"), ("0", "slow")):
                with self.subTest(number=number, modes=modes):
                    process = self.launch(modes)
                    self.ready(process)
                    process.send_signal(number)
                    process.send_signal(number)
                    receipt = self.finish(process, 128 + number)
                    self.assertFalse(receipt["eligible_to_continue"])
                    self.assertEqual(receipt["abort"], "signal")
                    self.assertRaises(RuntimeError, owner.prior, self.cwd / "records/ui-owner-phone.json", "phone")
                    for name in ("records/ui-owner-phone.json", "records/ui-owner-phone.owner.json", "records/ui-owner-phone.abort", "calls", "ready"):
                        (self.cwd / name).unlink(missing_ok=True)

    def test_signal_before_admission_while_plan_stdin_blocked(self):
        process = self.launch(("0", "0"), blocked=True)
        until = time.monotonic() + 2
        while not (self.cwd / "records/ui-owner-phone.json").exists() and time.monotonic() < until:
            time.sleep(0.01)
        self.assertTrue((self.cwd / "records/ui-owner-phone.json").exists())
        process.send_signal(signal.SIGTERM)
        # Observe termination BEFORE EOF; blocked stdin must not delay abort.
        process.wait(timeout=3)
        process.stdin.close()
        process.stdin = None
        receipt = self.finish(process, 143)
        self.assertEqual(receipt["groups"], [])
        self.assertFalse((self.cwd / "calls").exists())

    def test_near_exit_abort_no_second_launch_no_stale_timer(self):
        receipt = self.finish(self.launch(("near-exit", "0")), 143)
        self.assertFalse(receipt["eligible_to_continue"])
        self.assertEqual((self.cwd / "calls").read_text().splitlines(), ["near-exit"])
        time.sleep(0.4)
        self.assertIsNone(self.sentinel.poll())

    def test_supervisor_SIGKILL_incomplete_receipt_blocks_tablet_no_stop_promise(self):
        process = self.launch(("slow", "0"))
        self.ready(process)
        process.kill()
        # Pipes are inherited by anchor/work; wait only beyond bounded fixture
        # exit here. SIGKILL does NOT assert helper cleanup or artifact durability.
        process.communicate(timeout=4)
        receipt = json.loads((self.cwd / "records/ui-owner-phone.json").read_text())
        self.assertFalse(receipt["eligible_to_continue"])
        self.assertRaises(RuntimeError, owner.prior, self.cwd / "records/ui-owner-phone.json", "phone")
        tablet = self.launch(("0",), lane="ipad", require="phone")
        tablet.communicate(timeout=3)
        self.assertEqual(tablet.returncode, 125)
        self.assertEqual((self.cwd / "calls").read_text().splitlines(), ["slow"])

    def test_native_parent_exits_leaving_stubborn_child_settles_before_second(self):
        receipt = self.finish(self.launch(("orphan", "0")), 0)
        self.assertTrue(receipt["process_clean"] and receipt["eligible_to_continue"])
        self.assertEqual(len(receipt["stages"]), 2)
        self.observe_late_boundary()

    def test_cleanup_inspection_and_record_failure_override_success(self):
        for fault in ("settle", "members", "atomic"):
            with self.subTest(fault=fault):
                receipt = self.finish(self.launch(("0", "0"), fault=fault), 125)
                self.assertFalse(receipt["eligible_to_continue"])
                self.assertRaises(RuntimeError, owner.prior, self.cwd / "records/ui-owner-phone.json", "phone")
                (self.cwd / "records/ui-owner-phone.json").unlink()
                (self.cwd / "records/ui-owner-phone.owner.json").unlink()
                (self.cwd / "calls").unlink(missing_ok=True)

    def test_final_publication_rechecks_deadline_and_signal_no_stale_permission(self):
        for fault, code in (("publication-deadline", 124), ("publication-signal", 143), ("stdout", 125), ("publication-afterreplace", 125)):
            with self.subTest(fault=fault):
                receipt = self.finish(self.launch(("0", "0"), fault=fault), code)
                self.assertTrue(receipt["process_clean"])
                self.assertFalse(receipt["eligible_to_continue"])
                self.assertRaises(RuntimeError, owner.prior, self.cwd / "records/ui-owner-phone.json", "phone")
                (self.cwd / "records/ui-owner-phone.json").unlink()
                (self.cwd / "records/ui-owner-phone.owner.json").unlink()
                (self.cwd / "records/ui-owner-phone.abort").unlink(missing_ok=True)
                (self.cwd / "calls").unlink(missing_ok=True)

    def test_nonfinite_execution_cleanup_budgets_rejected_without_any_anchor(self):
        for field in ("--seconds", "--cleanup-seconds"):
            for value in ("nan", "inf", "-inf"):
                with self.subTest(field=field, value=value):
                    args = [sys.executable, str(SOURCE), "--lane", "phone", "--records", "records", "--seconds=3"]
                    args.append(field + "=" + value)
                    result = subprocess.run(args, cwd=self.cwd, input=json.dumps(self.plan(("0", "0"))),
                                            capture_output=True, text=True, timeout=2)
                    self.assertEqual(result.returncode, 2)
                    self.assertFalse((self.cwd / "calls").exists())
                    self.assertFalse((self.cwd / "records/ui-owner-phone.json").exists())

    def test_malformed_missing_uncertain_wrong_lane_records_block_actual_tablet_launch(self):
        valid = self.finish(self.launch(("0", "0")), 0)
        (self.cwd / "calls").unlink()
        path = self.cwd / "records/ui-owner-phone.json"
        invalid = [None, "not json", {}]
        for field, value in (("version", True), ("lane", "ipad"), ("owner", ""), ("owner", "not-uuid"),
                             ("owner", str(uuid.uuid4())), ("state", "active"), ("process_clean", False), ("eligible_to_continue", False),
                             ("groups", [self.sentinel.pid, valid["groups"][1]]), ("groups", [True, 2]), ("groups", [0, 2]), ("groups", [-1, 2]),
                             ("abort", "deadline"), ("normal_completion", False), ("exit_status", True),
                             ("exit_status", "0"), ("exit_status", None), ("exit_status", -1),
                             ("exit_status", 256), ("exit_status", 65), ("stages", []),
                             ("stages", [{"native": False, "tee": 0, "parser": 0}] * 2),
                             ("stages", [{"native": 0, "tee": 0}] * 2)):
            invalid.append(dict(valid, **{field: value}))
        for field in valid:
            invalid.append({key: value for key, value in valid.items() if key != field})
        # Rightmost failure within each pipeline, FIRST failing invocation wins.
        # These clean-looking records retain actual owner/groups but lie about
        # ordinary status, and must not admit the actual tablet helper path.
        invalid.append(dict(valid, stages=[{"native": 65, "tee": 17, "parser": 0},
                                          {"native": 70, "tee": 0, "parser": 2}], exit_status=65))
        invalid.append(dict(valid, stages=[{"native": 65, "tee": 0, "parser": 0},
                                          {"native": 70, "tee": 0, "parser": 0}], exit_status=70))
        for value in invalid:
            with self.subTest(value=value):
                if value is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_text(value if isinstance(value, str) else json.dumps(value))
                process = self.launch(("0",), lane="ipad", require="phone")
                stdout, stderr = process.communicate(timeout=3)
                self.assertEqual(process.returncode, 125, (stdout, stderr))
                self.assertFalse((self.cwd / "calls").exists())
                self.assertIsNone(self.sentinel.poll(), "live unrelated group is verification-only, NEVER killed")
        path.write_text(json.dumps(valid))
        path.with_suffix(".abort").touch()
        tablet = self.launch(("0",), lane="ipad", require="phone")
        tablet.communicate(timeout=3)
        self.assertEqual(tablet.returncode, 125)
        self.assertFalse((self.cwd / "calls").exists())
        self.assertIsNone(self.sentinel.poll())

    def test_clean_ordinary_failed_tests_permit_actual_tablet(self):
        receipt = self.finish(self.launch(("65", "0")), 65)
        self.assertTrue(receipt["eligible_to_continue"])
        process = self.launch(("0",), lane="ipad", require="phone")
        stdout, stderr = process.communicate(timeout=3)
        self.assertEqual(process.returncode, 0, (stdout, stderr))
        self.assertEqual((self.cwd / "calls").read_text().splitlines(), ["65", "0", "0"])


if __name__ == "__main__":
    print(f"Hosted actual owner controls Python={sys.version} executable={sys.executable} platform={sys.platform}", flush=True)
    unittest.main(verbosity=2)
