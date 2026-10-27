#!/usr/bin/env python3
"""Local equivalent of the four parallel CI lanes; dependencies must be installed."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    os.chdir(ROOT)
    output = ROOT / '.pi' / 'ci' / ('local-' + uuid.uuid4().hex)
    output.mkdir(parents=True)
    started = time.monotonic()

    def run(lane):
        log = output / f'{lane}.log'
        command = [sys.executable, 'scripts/ci/budget.py', '--lane', lane,
                   '--budget-seconds', '90', '--receipt', str(output / f'{lane}.json'),
                   '--', 'bash', f'scripts/ci/{lane}.sh']
        with log.open('w') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
        print(f'{lane}: {"passed" if result.returncode == 0 else "FAILED"} ({log})', flush=True)
        return result.returncode == 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(run, ('rust', 'apple', 'android', 'web')))
    elapsed = time.monotonic() - started
    print(f'Complete suite: {elapsed:.3f}s; evidence: {output}')
    return 0 if all(results) and elapsed <= 120 else 1


if __name__ == '__main__':
    sys.exit(main())
