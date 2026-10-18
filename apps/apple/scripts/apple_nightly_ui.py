#!/usr/bin/env python3
"""Plan, transport, run, and audit the complete compiled nightly UI suite."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from validate_ios_ui_xctestrun import BUILD_MARKER, qualify

SHARDS = 4


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def toolchain() -> str:
    return subprocess.check_output(['xcodebuild', '-version'], text=True).strip()


def identifiers(value) -> list[str]:
    if not isinstance(value, dict) or value.get('errors') != []:
        raise ValueError('compiled UI enumeration must complete without errors')
    values = value.get('values', [])
    if len(values) != 1 or values[0].get('disabledTests') != []:
        raise ValueError('compiled UI inventory must have one configuration and no disabled cases')
    entries = values[0].get('enabledTests', [])
    tests = []
    for entry in entries:
        name = entry.get('identifier', '')
        if not re.fullmatch(r'HealthMdUITests/[^/]+/test[^/]+', name):
            raise ValueError('unexpected compiled UI test method identifier')
        tests.append(name.removesuffix('()'))
    if not tests or len(set(tests)) != len(tests):
        raise ValueError('compiled UI inventory must be nonempty and unique')
    return sorted(tests)


def plan(tests: list[str], weights: dict, source_sha: str) -> dict:
    if len(tests) < SHARDS or len(tests) != len(set(tests)):
        raise ValueError('compiled inventory is empty, too small, or duplicated')
    groups = [[] for _ in range(SHARDS)]
    totals = [0.0] * SHARDS
    for test in sorted(tests, key=lambda t: (-weights.get(t, 30.0), t)):
        index = min(range(SHARDS), key=lambda i: (totals[i], len(groups[i]), i))
        groups[index].append(test)
        totals[index] += weights.get(test, 30.0)
    return {'source_sha': source_sha, 'tests': sorted(tests),
            'shards': [sorted(group) for group in groups], 'estimated_seconds': totals}


def validate_plan(value: dict, source_sha: str) -> None:
    if value['source_sha'] != source_sha or len(value['shards']) != SHARDS:
        raise ValueError('UI plan has the wrong source revision or shard count')
    expected = value['tests']
    if not expected or len(set(expected)) != len(expected):
        raise ValueError('UI plan inventory must be nonempty and unique')
    actual = [test for group in value['shards'] for test in group]
    if any(not group for group in value['shards']) or Counter(actual) != Counter(expected):
        raise ValueError('UI shards must be an exact disjoint partition of the compiled inventory')


def validate_inventory(root: Path, source_sha: str) -> dict:
    value = json.loads((root / 'ui-plan.json').read_text())
    validate_plan(value, source_sha)
    tests = identifiers(json.loads((root / 'ui-enumeration.json').read_text()))
    if sorted(value['tests']) != tests:
        raise ValueError('UI plan does not match the full compiled inventory')
    return value


def cases(log: str) -> list[tuple[str, str]]:
    entries = re.findall(r"Test Case '-\[HealthMdUITests\.([^ ]+) ([^]]+)\]' (passed|failed|skipped) ", log)
    return [(f'HealthMdUITests/{cls}/{method}', result) for cls, method, result in entries]


def audit_shard(value: dict, index: int, log: str) -> dict:
    actual = cases(log)
    expected = value['shards'][index]
    if Counter(test for test, _ in actual) != Counter(expected):
        raise ValueError(f'shard {index} executed missing, extra, or duplicate UI cases')
    if any(result != 'passed' for _, result in actual) or not re.search(
            r'^\*\* TEST(?: EXECUTE)? SUCCEEDED \*\*$', log, re.MULTILINE):
        raise ValueError(f'shard {index} contains failed/skipped tests or incomplete Xcode execution')
    return {'source_sha': value['source_sha'], 'shard': index, 'tests': actual, 'passed': len(actual)}


def aggregate(value: dict, receipts: list[dict]) -> dict:
    if sorted(r['shard'] for r in receipts) != list(range(SHARDS)):
        raise ValueError('missing or duplicated UI shard receipt')
    actual = []
    for receipt in receipts:
        if receipt['source_sha'] != value['source_sha']:
            raise ValueError('mixed source revisions in UI results')
        entries = receipt['tests']
        if Counter(t for t, _ in entries) != Counter(value['shards'][receipt['shard']]):
            raise ValueError('shard receipt does not match its assigned inventory')
        if any(result != 'passed' for _, result in entries):
            raise ValueError('UI results contain a failed or skipped case')
        actual.extend(test for test, _ in entries)
    if Counter(actual) != Counter(value['tests']):
        raise ValueError('UI results do not cover the full compiled suite exactly once')
    return {'source_sha': value['source_sha'], 'passed': len(actual), 'failed': 0,
            'skipped': 0, 'tests': sorted(actual), 'shards': SHARDS}


def pack(root: Path, output: Path, source_sha: str) -> None:
    manifest, _ = qualify(root, source_sha)
    validate_inventory(root, source_sha)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / 'products.tar.gz'
    subprocess.run(['tar', '-czf', str(archive.resolve()), '-C', str(root),
                    'Build/Products', BUILD_MARKER, 'ui-plan.json', 'ui-enumeration.json'], check=True)
    receipt = {'source_sha': source_sha, 'xcode': toolchain(), 'archive_sha256': digest(archive),
               'manifest': manifest.name, 'manifest_sha256': digest(manifest)}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


def unpack(artifact: Path, root: Path, source_sha: str) -> Path:
    receipt = json.loads((artifact / 'receipt.json').read_text())
    archive = artifact / 'products.tar.gz'
    if receipt['source_sha'] != source_sha or receipt['xcode'] != toolchain():
        raise ValueError('prepared UI artifacts do not match the checked-out source and Xcode')
    if digest(archive) != receipt['archive_sha256']:
        raise ValueError('prepared UI archive digest mismatch')
    if root.exists():
        raise ValueError('UI artifacts must be extracted into a fresh directory')
    root.mkdir(parents=True)
    subprocess.run(['tar', '-xzf', str(archive.resolve()), '-C', str(root)], check=True)
    manifest, _ = qualify(root, source_sha)
    if manifest.name != receipt['manifest'] or digest(manifest) != receipt['manifest_sha256']:
        raise ValueError('generated xctestrun bytes changed in transport')
    validate_inventory(root, source_sha)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'pack', 'run', 'aggregate'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--artifact', type=Path)
    parser.add_argument('--shard', type=int, choices=range(SHARDS))
    parser.add_argument('--destination')
    args = parser.parse_args()
    if args.action in ('pack', 'run') and args.artifact is None:
        parser.error('--artifact is required for pack/run')
    if args.action == 'run' and (args.shard is None or not args.destination):
        parser.error('--shard and --destination are required for run')
    if args.action == 'plan':
        tests = identifiers(json.loads((args.root / 'ui-enumeration.json').read_text()))
        weights = json.loads((Path(__file__).parent / 'fixtures/apple-nightly-ui-timings.json').read_text())['seconds']
        value = plan(tests, weights, args.source_sha)
        validate_plan(value, args.source_sha)
        (args.root / 'ui-plan.json').write_text(json.dumps(value, indent=2) + '\n')
        print(json.dumps({'tests': len(tests), 'shard_seconds': value['estimated_seconds']}))
    elif args.action == 'pack':
        pack(args.root, args.artifact, args.source_sha)
    elif args.action == 'run':
        manifest = unpack(args.artifact, args.root, args.source_sha)
        value = json.loads((args.root / 'ui-plan.json').read_text())
        results = Path('build/test-results')
        results.mkdir(parents=True, exist_ok=True)
        log_path = Path(f'build/logs/nightly-ui-{args.shard}.log')
        log_path.parent.mkdir(parents=True, exist_ok=True)
        command = ['xcodebuild', 'test-without-building', '-xctestrun', str(manifest),
                   '-destination', args.destination, '-parallel-testing-enabled', 'NO',
                   '-resultBundlePath', str(results / f'Nightly-UI-{args.shard}.xcresult'),
                   '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '180',
                   '-maximum-test-execution-time-allowance', '300']
        command.extend(f'-only-testing:{test}' for test in value['shards'][args.shard])
        with log_path.open('w') as log, subprocess.Popen(
                command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
            code = process.wait()
        if code:
            raise SystemExit(code)
        receipt = audit_shard(value, args.shard, log_path.read_text())
        (log_path.parent / f'ui-shard-{args.shard}.json').write_text(json.dumps(receipt, indent=2) + '\n')
    else:
        value = validate_inventory(args.root, args.source_sha)
        receipts = [json.loads(p.read_text()) for p in sorted(args.root.glob('**/ui-shard-*.json'))]
        receipt = aggregate(value, receipts)
        (args.root / 'ui-inventory.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(1)
