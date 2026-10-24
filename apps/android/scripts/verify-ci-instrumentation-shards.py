#!/usr/bin/env python3
"""Verify all device shards and retain their collision-free case inventory."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

SHARD_COUNT = 6


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


def source_receipt(run_id: str, attempt: str, shard: int, source_sha: str) -> dict:
    if not re.fullmatch(r'[1-9][0-9]*', run_id) or not re.fullmatch(r'[1-9][0-9]*', attempt):
        raise ValueError('Run ID and attempt must be positive integers')
    if not 0 <= shard < SHARD_COUNT or not re.fullmatch(r'[0-9a-f]{40}', source_sha):
        raise ValueError('Exact source SHA and valid shard required')
    return dict(version=1, run_id=run_id, attempt=attempt, shard=shard, source_sha=source_sha)


def write_source_receipt(path: Path, run_id: str, attempt: str, shard: int, source_sha: str) -> None:
    value = source_receipt(run_id, attempt, shard, source_sha)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def shard_directories(reports: Path, run_id: str, attempt: str, source_sha: str | None) -> dict:
    found = {p.name for p in reports.iterdir() if p.is_dir()}
    if source_sha is None:
        # Legacy callers remain strictly bound to one complete attempt.
        expected = {f'android-instrumentation-{run_id}-{attempt}-shard-{i}' for i in range(SHARD_COUNT)}
        if expected != found:
            raise ValueError(f'Shard artifact set mismatch: missing={sorted(expected-found)}, unexpected={sorted(found-expected)}')
        return {i: (attempt, reports / f'android-instrumentation-{run_id}-{attempt}-shard-{i}')
                for i in range(SHARD_COUNT)}
    source_receipt(run_id, attempt, 0, source_sha)
    selected = {}
    for name in sorted(found):
        match = re.fullmatch(rf'android-instrumentation-{run_id}-([1-9][0-9]*)-shard-([0-9])', name)
        if not match:
            raise ValueError(f'Unexpected shard artifact: {name}')
        artifact_attempt, index = match.group(1), int(match.group(2))
        if int(artifact_attempt) > int(attempt) or index >= SHARD_COUNT:
            raise ValueError(f'Future attempt or unknown shard artifact: {name}')
        directory = reports / name
        receipt = json.loads((directory / 'build/logs/instrumentation-source.json').read_text())
        if receipt != source_receipt(run_id, artifact_attempt, index, source_sha):
            raise ValueError(f'Shard source, run, attempt or identity mismatch: {name}')
        if index not in selected or int(artifact_attempt) > int(selected[index][0]):
            selected[index] = (artifact_attempt, directory)
    if set(selected) != set(range(SHARD_COUNT)):
        raise ValueError(f'Shard artifact set mismatch: missing shards={sorted(set(range(SHARD_COUNT))-set(selected))}')
    return selected


def verify(reports: Path, run_id: str, attempt: str, *, source_sha: str | None = None) -> dict:
    if not run_id.isdecimal() or not attempt.isdecimal() or int(run_id) < 1 or int(attempt) < 1:
        raise ValueError('Run ID and attempt must be positive integers')
    directories = shard_directories(reports, run_id, attempt, source_sha)
    inventory = []
    seen = set()
    for index in range(SHARD_COUNT):
        directory = directories[index][1]
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
        required = {'play', 'core', 'direct_e2e'} if index == 0 else {'play'}
        if groups != required:
            raise ValueError(f'Shard {index} report groups mismatch: expected={sorted(required)}, found={sorted(groups)}')
    provenance = {} if source_sha is None else {
        'source_sha': source_sha, 'shard_attempts': {str(i): directories[i][0] for i in range(SHARD_COUNT)}}
    return {**provenance, 'run_id': run_id, 'attempt': attempt, 'shards': SHARD_COUNT,
            'tests': len(inventory), 'passed': sum(x['result'] == 'passed' for x in inventory),
            'skipped': sum(x['result'] == 'skipped' for x in inventory),
            'cases': sorted(inventory, key=lambda x: (x['kind'], x['class'], x['name']))}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports', type=Path)
    parser.add_argument('--write-receipt', type=Path)
    parser.add_argument('--source-sha')
    parser.add_argument('--shard', type=int)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--attempt', required=True)
    args = parser.parse_args()
    try:
        if args.write_receipt:
            if args.shard is None or args.source_sha is None or args.reports is not None:
                raise ValueError('Receipt mode requires shard and source SHA without reports')
            write_source_receipt(args.write_receipt, args.run_id, args.attempt, args.shard, args.source_sha)
            return
        if args.reports is None:
            raise ValueError('Reports directory required')
        inventory = verify(args.reports, args.run_id, args.attempt, source_sha=args.source_sha)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f'Instrumentation shard verification failed: {error}\n')
    (args.reports / 'case-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    print(f"Verified {inventory['shards']} shards: {inventory['tests']} unique cases, "
          f"{inventory['passed']} passed, {inventory['skipped']} skipped")


if __name__ == '__main__':
    main()
