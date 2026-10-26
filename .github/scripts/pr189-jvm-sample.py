#!/usr/bin/env python3
"""Temporary synthetic diagnostic: bounded JVM stats/stacks, never heap contents."""
from datetime import datetime, timezone
from pathlib import Path
import signal
import subprocess
import sys
import time


stop_requested = False


def stop(_signum, _frame):
    global stop_requested
    # Never raise across Popen: ownership must reach its cleanup block first.
    stop_requested = True


def pause(seconds: float) -> bool:
    deadline = time.monotonic() + seconds
    while not stop_requested:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return True
        time.sleep(min(0.1, remaining))
    return False


def capture(worker: int, operation: str, path: Path):
    if stop_requested:
        return
    with path.open('wb') as output:
        child = subprocess.Popen(['jcmd', str(worker), operation], stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 20
            while child.poll() is None and not stop_requested and time.monotonic() < deadline:
                time.sleep(0.05)
            if child.poll() is None and not stop_requested:
                output.write(b'\nDiagnostic snapshot exceeded20s; child will be reaped.\n')
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


def main():
    signal.signal(signal.SIGTERM, stop)
    output = Path(sys.argv[1])
    for delay in (60, 240, 300, 600):
        if not pause(delay):
            return
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        for proc in Path('/proc').glob('[0-9]*'):
            if stop_requested:
                return
            try:
                command = (proc / 'cmdline').read_bytes()
            except OSError:
                continue
            if b'worker.org.gradle.process.internal.worker.GradleWorkerMain' not in command:
                continue
            worker = int(proc.name)
            capture(worker, 'GC.heap_info', output / f'heap-{stamp}-{worker}.txt')
            capture(worker, 'Thread.print', output / f'threads-{stamp}-{worker}.txt')


if __name__ == '__main__':
    main()
