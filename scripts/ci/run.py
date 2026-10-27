#!/usr/bin/env python3
"""Run the minimal, platform-neutral regression groups concurrently."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys
import uuid
import time

ROOT = Path(__file__).resolve().parents[2]
GROUPS = {
    "contracts": ["bash", "scripts/ci/contracts.sh"],
    "core": ["bash", "scripts/ci/core.sh"],
    "cli": ["bash", "scripts/ci/cli.sh"],
    "practice": ["bash", "scripts/ci/practice.sh"],
    "wake": ["bash", "scripts/ci/wake.sh"],
    "consumer": ["bash", "scripts/ci/consumer-smoke.sh"],
}


def main():
    os.chdir(ROOT)
    output = Path(os.environ.get("HEALTHMD_CI_RESULTS", ROOT / '.pi' / 'ci' / ('local-' + uuid.uuid4().hex)))
    output.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()

    def run(item):
        lane, command = item
        log = output / f'{lane}.log'
        args = [sys.executable, 'scripts/ci/budget.py', '--lane', lane,
                '--budget-seconds', '90', '--receipt', str(output / f'{lane}.json'), '--', *command]
        with log.open('w') as stream:
            result = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT)
        print(f'{lane}: {"passed" if result.returncode == 0 else "FAILED"} ({log})', flush=True)
        if result.returncode:
            print(log.read_text()[-12000:], flush=True)
        return result.returncode == 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(GROUPS)) as pool:
        results = list(pool.map(run, GROUPS.items()))
    elapsed = time.monotonic() - started
    print(f'Complete suite: {elapsed:.3f}s; evidence: {output}')
    return 0 if all(results) and elapsed <= 110 else 1


if __name__ == '__main__':
    sys.exit(main())
