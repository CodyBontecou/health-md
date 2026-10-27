#!/usr/bin/env python3
"""Retain build-process telemetry without logging arguments or replacing build failure."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A build command is required after --')
    try:
        child = subprocess.Popen(command, start_new_session=True)
    except OSError as error:
        print(f'Build command could not start: {error}', file=sys.stderr)
        return 127
    stop = threading.Event()
    interrupted = []

    def observe():
        try:
            args.log.parent.mkdir(parents=True, exist_ok=True)
            with args.log.open('w') as log:
                log.write(json.dumps({'event': 'started', 'pid': child.pid}) + '\n')
                log.flush()
                while not stop.is_set():
                    log.write(json.dumps({'utc_seconds': time.time()}) + '\n')
                    try:
                        # comm is the executable name/path; args and environment are excluded.
                        snapshot = subprocess.run(
                            ['ps', '-axo', 'pid,ppid,state,pcpu,rss,etime,comm'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            text=True, timeout=5, check=True,
                        )
                        log.write(snapshot.stdout)
                        rows = [line.split(None, 6) for line in snapshot.stdout.splitlines()[1:]]
                        rows = [row for row in rows if len(row) == 7]
                        owned = {str(child.pid)}
                        while True:
                            expanded = owned | {row[0] for row in rows if row[1] in owned}
                            if expanded == owned:
                                break
                            owned = expanded
                        print(f'[build observer] epoch={time.time():.0f} pid={child.pid}', flush=True)
                        for row in rows:
                            if row[0] in owned:
                                print(' '.join(row), flush=True)
                    except (OSError, subprocess.SubprocessError) as error:
                        log.write(f'Process snapshot unavailable: {type(error).__name__}\n')
                    log.flush()
                    stop.wait(30)
        except OSError:
            print('Build process telemetry unavailable; build result remains authoritative', file=sys.stderr)

    def forward(signum, _frame):
        if not interrupted:
            interrupted.extend((signum, time.monotonic()))
        try:
            os.killpg(child.pid, signum)
        except ProcessLookupError:
            pass

    previous = {sig: signal.signal(sig, forward) for sig in (signal.SIGINT, signal.SIGTERM)}
    monitor = threading.Thread(target=observe, daemon=True)
    monitor.start()
    try:
        while True:
            try:
                result = child.wait(timeout=1)
                break
            except subprocess.TimeoutExpired:
                if interrupted and time.monotonic() - interrupted[1] >= 5:
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
        return 128 + interrupted[0] if interrupted else (128 - result if result < 0 else result)
    finally:
        # The leader may handle TERM and exit while a compiler descendant stays
        # alive. Cancellation still owns the whole session after wait() returns.
        if interrupted:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stop.set()
        monitor.join(timeout=6)
        for sig, handler in previous.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    raise SystemExit(main())
