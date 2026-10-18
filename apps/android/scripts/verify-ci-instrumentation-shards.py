#!/usr/bin/env python3
"""Verify all device shards and retain their collision-free case inventory."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

SHARD_COUNT = 4


def report_kind(path: Path) -> str:
    value = path.as_posix()
    if value.startswith('healthmd-core/build/outputs/androidTest-results/connected/'):
        return 'core'
    if value.startswith('app/build/outputs/androidTest-results/connected/e2e/flavors/play/'):
        return 'direct_e2e'
    for flavor in ('play', 'fdroid'):
        if value.startswith(f'app/build/outputs/androidTest-results/connected/debug/flavors/{flavor}/'):
            return flavor
    raise ValueError(f'Unexpected instrumentation XML location: {path}')


def verify(reports: Path, run_id: str, attempt: str) -> dict:
    if not run_id.isdecimal() or not attempt.isdecimal() or int(run_id) < 1 or int(attempt) < 1:
        raise ValueError('Run ID and attempt must be positive integers')
    expected = {f'android-instrumentation-{run_id}-{attempt}-shard-{i}' for i in range(SHARD_COUNT)}
    found = {p.name for p in reports.iterdir() if p.is_dir()}
    if expected != found:
        raise ValueError(f'Shard artifact set mismatch: missing={sorted(expected-found)}, unexpected={sorted(found-expected)}')
    inventory = []
    seen = set()
    for index in range(SHARD_COUNT):
        directory = reports / f'android-instrumentation-{run_id}-{attempt}-shard-{index}'
        groups = set()
        files = sorted(directory.glob('**/outputs/androidTest-results/connected/**/*.xml'))
        for path in files:
            kind = report_kind(path.relative_to(directory))
            groups.add(kind)
            root = ET.parse(path).getroot()
            cases = list(root.iter('testcase'))
            if not cases:
                raise ValueError(f'Empty test report: {path}')
            if any(int(suite.get(key, '0')) for suite in root.iter('testsuite') for key in ('failures', 'errors')):
                raise ValueError(f'Failed test report: {path}')
            if root.find('.//failure') is not None or root.find('.//error') is not None:
                raise ValueError(f'Failed test case: {path}')
            if root.tag == 'testsuite' and int(root.get('tests', '-1')) != len(cases):
                raise ValueError(f'Test count disagrees with XML cases: {path}')
            for case in cases:
                key = (kind, case.get('classname'), case.get('name'))
                if not key[1] or not key[2]:
                    raise ValueError(f'Missing test identity: {path}')
                if key in seen:
                    raise ValueError(f'Duplicate test across shard reports: {key}')
                seen.add(key)
                inventory.append({'kind': kind, 'class': key[1], 'name': key[2], 'shard': index,
                                  'result': 'skipped' if case.find('skipped') is not None else 'passed'})
        required = {'play', 'fdroid', 'core', 'direct_e2e'} if index == 0 else {'play', 'fdroid'}
        if groups != required:
            raise ValueError(f'Shard {index} report groups mismatch: expected={sorted(required)}, found={sorted(groups)}')
    return {'run_id': run_id, 'attempt': attempt, 'shards': SHARD_COUNT,
            'tests': len(inventory), 'passed': sum(x['result'] == 'passed' for x in inventory),
            'skipped': sum(x['result'] == 'skipped' for x in inventory),
            'cases': sorted(inventory, key=lambda x: (x['kind'], x['class'], x['name']))}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--attempt', required=True)
    args = parser.parse_args()
    try:
        inventory = verify(args.reports, args.run_id, args.attempt)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f'Instrumentation shard verification failed: {error}\n')
    (args.reports / 'case-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    print(f"Verified {inventory['shards']} shards: {inventory['tests']} unique cases, "
          f"{inventory['passed']} passed, {inventory['skipped']} skipped")


if __name__ == '__main__':
    main()
