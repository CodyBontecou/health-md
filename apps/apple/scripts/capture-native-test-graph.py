#!/usr/bin/env python3
"""Capture a complete native target graph, stop the owned build, and qualify its nodes.

Diagnostic only: stopping at a graph never qualifies compilation or test results.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location('native_targets', Path(__file__).with_name('check-native-test-targets.py'))
targets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(targets)


def signal_owned_group(group, number):
    try:
        os.killpg(group, number)
    except ProcessLookupError:
        pass
    except PermissionError:
        # Darwin returns EPERM for an unreaped zombie-only group. Confirm there
        # are no live members; an actual permission denial remains a failure.
        snapshot = subprocess.run(['ps', '-axo', 'pgid=,stat='], check=True,
                                  capture_output=True, text=True, timeout=5)
        for line in snapshot.stdout.splitlines():
            fields = line.split()
            if len(fields) != 2:
                raise ValueError('Unable to observe diagnostic process-group state')
            if int(fields[0]) == group and not fields[1].startswith('Z'):
                raise


def capture(command, log, platform):
    child = subprocess.Popen(command, start_new_session=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, errors='replace')
    stopped = False
    cancelled = []

    def stop():
        nonlocal stopped
        if stopped:
            return
        stopped = True
        # Hold the direct child unreaped until the last group signal. Its PID
        # cannot be reused as a foreign process-group ID during cleanup.
        signal_owned_group(child.pid, signal.SIGTERM)
        time.sleep(.2)
        signal_owned_group(child.pid, signal.SIGKILL)
        child.wait(timeout=5)
        child.stdout.close()

    def cancel(signum, _frame):
        if not cancelled:
            cancelled.append(signum)
        if not stopped:
            raise SystemExit(128 + signum)

    previous = {sig: signal.signal(sig, cancel) for sig in (signal.SIGINT, signal.SIGTERM)}
    expected, seen, lines = None, 0, []
    try:
        with log.open('w') as output:
            for line in child.stdout:
                output.write(line)
                output.flush()
                print(line, end='', flush=True)
                header = re.search(r'note: Target dependency graph \((\d+) targets?\)', line)
                if header:
                    if expected is not None:
                        raise ValueError('Ambiguous target dependency graphs')
                    expected = int(header[1])
                    lines.append(line)
                elif expected is not None and re.fullmatch(r"\s*Target '[^']+' in project '[^']+'(?: \(no dependencies\))?\s*", line):
                    lines.append(line)
                    seen += 1
                    if seen == expected:
                        break
        if expected is None or seen != expected:
            raise ValueError('Build ended without a complete target dependency graph')
        return targets.qualify_targets(''.join(lines), platform)
    finally:
        try:
            stop()
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
            if cancelled:
                raise SystemExit(128 + cancelled[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--platform', choices=('iOS', 'macOS'), required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A build command is required after --')
    try:
        nodes = capture(command, args.log, args.platform)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Native graph diagnostic failed: {error}\n')
    print(json.dumps({'diagnostic_only': True, 'platform': args.platform, 'targets': nodes}))


if __name__ == '__main__':
    main()
