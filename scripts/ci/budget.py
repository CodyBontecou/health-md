#!/usr/bin/env python3
"""Run one CI lane with a real deadline and a machine-readable timing receipt.

The budget includes this process's setup and command execution. Workflow dispatch,
checkout, dependency restoration and final reporting must also fit the overall
120-second target; this receipt alone never attests to that overall target.
"""

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def stop_process_group(child):
    # macOS can attach protected helpers to a group. A denied group signal must
    # not prevent stopping our direct child or writing a failing receipt.
    denied = False
    for requested_signal in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(child.pid, requested_signal)
        except ProcessLookupError:
            break
        except PermissionError:
            denied = True
            try:
                child.send_signal(requested_signal)
            except ProcessLookupError:
                pass
            except PermissionError:
                denied = True
        if requested_signal == signal.SIGTERM:
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        return "process_did_not_stop"
    return "permission_denied" if denied else None


def run(command, *, lane, budget_seconds, receipt, cwd=None):
    if not command or not math.isfinite(budget_seconds) or budget_seconds <= 0:
        raise ValueError("A command and a positive finite time budget are required")
    if os.name != "posix":
        raise ValueError("CI lanes require a POSIX runner for descendant cleanup")
    started = time.monotonic()
    receipt = Path(receipt)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    # A killed run must never leave an earlier passing receipt for collection.
    receipt.unlink(missing_ok=True)
    record = {
        "schema": "healthmd.ci.lane/v1",
        "lane": lane,
        "started_at": utc_now(),
        "budget_seconds": budget_seconds,
        "command": command,
        "source_sha": None,
        "working_tree_dirty": None,
        "status": "running",
        "exit_code": None,
    }
    child = None
    previous_handlers = {}

    def cancelled(signum, _frame):
        raise InterruptedError(signum)

    try:
        for signum in (signal.SIGTERM, signal.SIGINT):
            previous_handlers[signum] = signal.signal(signum, cancelled)
        record["source_sha"] = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=cwd, text=True, timeout=5,
        ).strip()
        record["working_tree_dirty"] = bool(subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=normal"],
            cwd=cwd, text=True, timeout=5,
        ).strip())
        remaining = budget_seconds - (time.monotonic() - started)
        if remaining <= 0:
            raise subprocess.TimeoutExpired(command, budget_seconds)
        receipt.write_text(json.dumps(record, indent=2) + "\n")
        print(f"[{lane}] budget={budget_seconds:g}s command={command!r}", flush=True)
        child = subprocess.Popen(command, cwd=cwd, start_new_session=True)
        code = child.wait(timeout=remaining)
        elapsed = time.monotonic() - started
        if elapsed > budget_seconds:
            record.update(status="timed_out", exit_code=124)
        else:
            record.update(status="passed" if code == 0 else "failed", exit_code=code if code >= 0 else 128 - code)
    except subprocess.TimeoutExpired:
        record.update(status="timed_out", exit_code=124)
    except (InterruptedError, KeyboardInterrupt):
        record.update(status="cancelled", exit_code=130)
    except (OSError, subprocess.SubprocessError) as error:
        # Report setup failures without dumping environment variables or secrets.
        print(f"[{lane}] cannot execute lane: {type(error).__name__}", file=sys.stderr)
        record.update(status="failed", exit_code=1)
    finally:
        # Prevent another cancellation from interrupting descendant cleanup/receipt.
        for signum in previous_handlers:
            signal.signal(signum, signal.SIG_IGN)
        try:
            if child is not None and record["status"] != "passed":
                cleanup_error = stop_process_group(child)
                if cleanup_error:
                    record["cleanup_error"] = cleanup_error
            record["finished_at"] = utc_now()
            record["elapsed_seconds"] = round(time.monotonic() - started, 3)
            receipt = Path(receipt)
            receipt.parent.mkdir(parents=True, exist_ok=True)
            temporary = receipt.with_suffix(receipt.suffix + ".tmp")
            temporary.write_text(json.dumps(record, indent=2) + "\n")
            temporary.replace(receipt)
            print(f"[{lane}] {record['status']} in {record['elapsed_seconds']:.3f}s", flush=True)
        finally:
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)
    return record["exit_code"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", required=True)
    parser.add_argument("--budget-seconds", required=True, type=float)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not math.isfinite(args.budget_seconds) or args.budget_seconds <= 0:
        parser.error("a command and a positive finite time budget are required")
    return run(command, lane=args.lane, budget_seconds=args.budget_seconds, receipt=args.receipt)


if __name__ == "__main__":
    sys.exit(main())
