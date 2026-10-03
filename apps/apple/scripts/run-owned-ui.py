#!/usr/bin/env python3
"""CI-only POSIX group ownership; ephemeral atomic receipts, NOT durability.

Stable anchors own native/shell/tee/parser groups. No stale-file/group-name kill,
no /proc/setsid/GNU timeout/subreaper dependency. Escaped descendants, simulator
services, SIGKILL/host loss and inspection races remain explicit limitations.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import uuid


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True) + "\n")
    temporary.replace(path)  # Ephemeral atomic publication; no fsync promise.


def members(group):
    result = subprocess.run(["ps", "-ax", "-o", "pid=,pgid=,stat="],
                            capture_output=True, text=True, check=True, timeout=1)
    return {int(p): state for line in result.stdout.splitlines()
            for p, g, state in [line.split()] if int(g) == group and not state.startswith("Z")}


def positive_group(value):
    return type(value) is int and value > 1


def prior(path, lane):
    value = json.loads(path.read_text())
    if (not isinstance(value, dict) or type(value.get("version")) is not int
            or value.get("version") != 1 or value.get("lane") != lane):
        raise RuntimeError("wrong/malformed prior lane receipt")
    mandatory = {"version", "lane", "owner", "state", "process_clean", "eligible_to_continue",
                 "normal_completion", "groups", "stages", "abort", "started_monotonic",
                 "exit_status", "stopped_monotonic"}
    if set(value) != mandatory:
        raise RuntimeError("missing/unknown prior receipt schema fields")
    if not isinstance(value.get("owner"), str):
        raise RuntimeError("missing prior owner")
    if str(uuid.UUID(value["owner"])) != value["owner"]:
        raise RuntimeError("noncanonical prior owner")
    binding = json.loads(path.with_suffix(".owner.json").read_text())
    if binding != {"lane": lane, "owner": value["owner"]}:
        raise RuntimeError("prior lane/owner binding mismatch")
    groups = value.get("groups")
    if (not isinstance(groups, list) or len(groups) not in ((2,) if lane == "phone" else (1, 2))
            or len(set(groups)) != len(groups) or not all(positive_group(g) for g in groups)
            or value.get("state") != "final" or value.get("process_clean") is not True
            or value.get("eligible_to_continue") is not True or value.get("abort") is not None
            or value.get("normal_completion") is not True
            or len(value.get("stages", [])) != (2 if lane == "phone" else 1)
            or path.with_suffix(".abort").exists()):
        raise RuntimeError("prior lane is not eligible to continue")
    for stage in value["stages"]:
        if not isinstance(stage, dict) or set(stage) != {"native", "tee", "parser"}:
            raise RuntimeError("malformed prior stage status")
        if not all(type(s) is int and 0 <= s <= 255 for s in stage.values()):
            raise RuntimeError("invalid prior stage status")
    expected_exit = next((rightmost(stage) for stage in value["stages"] if rightmost(stage)), 0)
    if type(value["exit_status"]) is not int or value["exit_status"] != expected_exit:
        raise RuntimeError("prior exit status disagrees with ordinary pipeline result")
    if any(members(g) for g in groups):
        raise RuntimeError("prior group active; verification never authorizes a kill")


def anchor(worker, event, abort, deadline, owner):
    # Remains the live group leader while parent signals inherited work. Parent
    # NEVER poll/waits/reaps this anchor until numeric group signalling is over.
    stopped = []
    def stop(number, _frame):
        stopped.append(number)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    permission = sys.stdin.readline()
    if permission != "GO\n" or stopped or abort.exists() or time.monotonic() >= deadline:
        atomic(event, {"owner": owner, "admitted": False})
    else:
        child = subprocess.Popen(["bash", str(worker)])
        status = child.wait()
        atomic(event, {"owner": owner, "admitted": True, "worker": status})
    # A normal worker exit is NOT group settlement. Keep this anchor live until
    # the supervisor has inspected/terminated any remaining group members.
    sys.stdin.read()


def settle(process, seconds):
    group = process.pid
    deadline = time.monotonic() + seconds
    def others():
        active = members(group)
        if group not in active:
            raise RuntimeError("live anchor lost; no reusable numeric-group signalling")
        return set(active) - {group}
    try:
        residual = others()
        if residual:
            os.killpg(group, signal.SIGTERM)  # Anchor ignores/latches TERM.
            grace = min(deadline, time.monotonic() + seconds / 2)
            while time.monotonic() < grace and others():
                time.sleep(0.02)
        if others():
            os.killpg(group, signal.SIGKILL)  # FINAL numeric signal, anchor included.
        else:
            process.stdin.close()  # Permit anchor to exit only after others gone.
            try:
                process.wait(timeout=max(0.01, min(1, deadline - time.monotonic())))
            except subprocess.TimeoutExpired:
                # Anchor still live; this is the final numeric signal.
                if group not in members(group):
                    raise RuntimeError("anchor lost before final signal")
                os.killpg(group, signal.SIGKILL)
        process.wait(timeout=max(0.01, min(1, deadline - time.monotonic())))
        # No subsequent numeric signals after reaping, even on inspection error.
        return not members(group)
    except Exception:
        # If still anchored, a final kill is safe to attempt before reaping.
        # Never infer ownership from a receipt, or signal after a completed wait.
        if process.returncode is None and group in members(group):
            os.killpg(group, signal.SIGKILL)
            process.wait(timeout=1)
        raise


def rightmost(stages):
    return next((stages[name] for name in ("parser", "tee", "native") if stages[name]), 0)


def run(args):
    started = time.monotonic()
    deadline = started + args.seconds
    path = args.records / ("ui-owner-" + args.lane + ".json")
    abort = path.with_suffix(".abort")
    signals = []
    def interrupted(number, _frame):
        if not signals:
            signals.append(number)
        try:
            abort.parent.mkdir(parents=True, exist_ok=True)
            abort.touch()  # Later continuation rejects abort even after final publication.
        except OSError:
            pass  # In-memory latch still aborts; final record failure is fail closed.
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, interrupted)
    def admission():
        if signals:
            raise InterruptedError(128 + signals[0])
        if time.monotonic() >= deadline:
            raise TimeoutError("lane deadline")
    if path.exists() or abort.exists() or path.with_suffix(".owner.json").exists():
        raise RuntimeError("refuse to overwrite prior ownership")
    if args.require_clean:
        prior(args.records / ("ui-owner-" + args.require_clean + ".json"), args.require_clean)
    record = {"version": 1, "lane": args.lane, "owner": str(uuid.uuid4()), "state": "starting",
              "process_clean": False, "eligible_to_continue": False, "normal_completion": False,
              "groups": [], "stages": [], "abort": None, "started_monotonic": started}
    atomic(path, record)
    atomic(path.with_suffix(".owner.json"), {"lane": args.lane, "owner": record["owner"]})
    process = None
    clean = True
    result = 125
    try:
        data = bytearray()
        # A blocked plan/stdin is inside the same deadline and abort latch.
        while True:
            admission()
            if not select.select([sys.stdin.buffer], [], [], 0.03)[0]:
                continue
            chunk = os.read(sys.stdin.fileno(), 65536)
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > 131072:
                raise RuntimeError("unbounded lane plan")
        plan = json.loads(data)
        admission()  # Includes cancellation while blocked reading plan, before Popen.
        pipelines = plan["pipelines"]
        if not isinstance(pipelines, list) or len(pipelines) != (2 if args.lane == "phone" else 1):
            raise RuntimeError("invalid pipeline count")
        setup = plan.get("setup")
        jobs = ([{"setup": setup}] if setup is not None else []) + pipelines
        with tempfile.TemporaryDirectory(prefix="health172-owned-") as temporary:
            root = Path(temporary)
            setup_file = root / "destination"
            for index, job in enumerate(jobs):
                admission()
                status_file = root / (str(index) + ".status")
                event = root / (str(index) + ".event")
                worker = root / (str(index) + ".sh")
                if "setup" in job:
                    if not isinstance(job["setup"], str):
                        raise RuntimeError("invalid setup")
                    script = "set -euo pipefail\n" + job["setup"] + "\n"
                else:
                    command = job["command"]
                    if not isinstance(command, list) or not command or not all(isinstance(s, str) for s in command):
                        raise RuntimeError("invalid native argv")
                    if "${IPAD_UDID}" in " ".join(command):
                        destination = setup_file.read_text().strip()
                        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", destination):
                            raise RuntimeError("invalid setup destination")
                        command = [s.replace("${IPAD_UDID}", destination) for s in command]
                    raw = shlex.quote(job["raw"])
                    pattern = shlex.quote(job["filter"])
                    script = ("set -uo pipefail\n" + shlex.join(command) + " 2>&1 | tee -a " + raw
                              + " | grep -E " + pattern + "\nstages=(\"${PIPESTATUS[@]}\")\n"
                              + "printf '{\"native\":%d,\"tee\":%d,\"parser\":%d}\\n' "
                              + '"${stages[0]}" "${stages[1]}" "${stages[2]}" > "$HEALTHMD_UI_STAGE_FILE"\n')
                worker.write_text(script)
                env = dict(os.environ, HEALTHMD_UI_STAGE_FILE=str(status_file),
                           HEALTHMD_UI_SETUP_FILE=str(setup_file))
                admission()
                process = subprocess.Popen([sys.executable, __file__, "--anchor", str(worker), str(event),
                                            str(abort.resolve()), str(deadline), record["owner"]], env=env,
                                           stdin=subprocess.PIPE, text=True, start_new_session=True)
                record["groups"].append(process.pid)
                record["state"] = "active"
                atomic(path, record)
                admission()  # Anchor has not admitted a native command yet.
                process.stdin.write("GO\n")
                process.stdin.flush()
                while not event.exists():
                    admission()
                    if process.pid not in members(process.pid):
                        raise RuntimeError("anchor unexpectedly exited")
                    time.sleep(0.03)
                event_value = json.loads(event.read_text())
                if event_value.get("owner") != record["owner"]:
                    raise RuntimeError("anchor event owner mismatch")
                admission()
                clean = settle(process, args.cleanup_seconds)
                process = None
                if not clean:
                    raise RuntimeError("owned group still live")
                if event_value.get("admitted") is not True or event_value.get("worker") != 0:
                    raise RuntimeError("worker not admitted or status publication failed")
                if "setup" not in job:
                    stages = json.loads(status_file.read_text())
                    if set(stages) != {"native", "tee", "parser"} or not all(type(s) is int and 0 <= s <= 255 for s in stages.values()):
                        raise RuntimeError("invalid independent pipeline statuses")
                    record["stages"].append(stages)
                    print(f"Owned UI stage {len(record['stages'])}: {stages}", flush=True)
                atomic(path, record)
                admission()  # No knowingly second native launch after abort/deadline.
        result = next((rightmost(s) for s in record["stages"] if rightmost(s)), 0)
        record["normal_completion"] = True
    except InterruptedError as error:
        result = error.args[0]
        record["abort"] = "signal"
    except TimeoutError:
        result = 124
        record["abort"] = "deadline"
    except Exception as error:
        result = 125
        record["abort"] = "ownership_or_record_failure"
        print(f"Owned UI fail-closed: {error}", file=sys.stderr)
    finally:
        if process is not None:
            try:
                clean = settle(process, args.cleanup_seconds)
            except Exception as error:
                clean = False
                print(f"Owned UI cleanup unverified: {error}", file=sys.stderr)
        if signals and record["abort"] is None:
            record["abort"] = "signal"
            result = 128 + signals[0]
        # Publish process evidence WITHOUT permission first. File/context cleanup
        # can consume the last budget interval; recheck before final eligibility.
        record.update(state="final", process_clean=clean, eligible_to_continue=False,
                      exit_status=result if clean else 125, stopped_monotonic=time.monotonic())
        atomic(path, record)
        # Fallible diagnostics MUST precede continuation publication. In
        # particular BrokenPipe cannot leave a positive receipt with exit125.
        print(f"Owned UI lane={args.lane} clean={clean} exit={record['exit_status']} continuation=pending", flush=True)
        if signals:
            record["abort"] = "signal"
            record["exit_status"] = 128 + signals[0] if clean else 125
        elif time.monotonic() >= deadline:
            record["abort"] = "deadline"
            record["exit_status"] = 124 if clean else 125
        record["eligible_to_continue"] = bool(clean and record["normal_completion"] and record["abort"] is None)
        try:
            atomic(path, record)
            # Do not return a stale positive if publication crossed deadline or
            # cancellation. No fallible stdout operation follows positive state.
            if record["eligible_to_continue"] and (signals or time.monotonic() >= deadline):
                abort.touch()
                record.update(eligible_to_continue=False, abort="signal" if signals else "deadline",
                              exit_status=128 + signals[0] if signals else 124)
                atomic(path, record)
        except BaseException:
            # An exception even AFTER replace is uncertain, never continuation.
            # Fence first; best-effort negative record is secondary. Filesystem/
            # host loss that prevents fencing remains an explicit open limit.
            abort.touch()
            record.update(eligible_to_continue=False, abort="publication_failure", exit_status=125)
            atomic(path, record)
            raise
    return record["exit_status"]


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--anchor":
        anchor(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), float(sys.argv[5]), sys.argv[6])
    else:
        parser = argparse.ArgumentParser()
        parser.add_argument("--lane", choices=("phone", "ipad"), required=True)
        parser.add_argument("--records", type=Path, required=True)
        parser.add_argument("--seconds", type=float, required=True)
        parser.add_argument("--cleanup-seconds", type=float, default=6)
        parser.add_argument("--require-clean", choices=("phone", "ipad"))
        args = parser.parse_args()
        if (not math.isfinite(args.seconds) or not math.isfinite(args.cleanup_seconds)
                or args.seconds <= 0 or not 0 < args.cleanup_seconds <= 8):
            parser.error("positive deadline, cleanup <=8 seconds required")
        args.records.mkdir(parents=True, exist_ok=True)
        try:
            sys.exit(run(args))
        except Exception as error:
            print(f"Owned UI receipt/admission failure: {error}", file=sys.stderr)
            sys.exit(125)
