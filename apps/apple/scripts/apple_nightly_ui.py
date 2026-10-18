#!/usr/bin/env python3
"""Plan, transport, run, and audit the complete compiled nightly UI suite."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import platform
from pathlib import Path
import re
import subprocess
import sys
import time

from validate_ios_ui_xctestrun import BUILD_MARKER, qualify

SHARDS = 4


def start_simulator(destination: str) -> None:
    match = re.fullmatch(r'platform=iOS Simulator,id=([A-Fa-f0-9-]{36})', destination)
    if not match:
        raise ValueError('expected one selected iOS simulator UUID')
    identifier = match[1]
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
    matches = [d for group in devices['devices'].values() for d in group if d['udid'] == identifier]
    if len(matches) != 1 or matches[0]['state'] not in ('Shutdown', 'Booting', 'Booted'):
        raise ValueError('selected simulator is unavailable or in an unexpected state')
    if matches[0]['state'] == 'Shutdown':
        subprocess.run(['xcrun', 'simctl', 'boot', identifier], check=True)
    print(f"Simulator startup requested: {identifier}; compilation/download can run while it boots.")


def simulator_profile(destination: str) -> dict:
    match = re.fullmatch(r'platform=iOS Simulator,id=([A-Fa-f0-9-]{36})', destination)
    if not match:
        raise ValueError('expected one selected iOS simulator UUID')
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
    matches = [(runtime, device) for runtime, group in devices['devices'].items()
               for device in group if device['udid'] == match[1]]
    if len(matches) != 1:
        raise ValueError('selected simulator profile is unavailable or ambiguous')
    runtime, device = matches[0]
    model = device.get('deviceTypeIdentifier', '')
    if not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-') or not model:
        raise ValueError('selected simulator has no iOS runtime or model identifier')
    return {'runtime': runtime, 'device_type': model}


def ready_simulator(destination: str) -> None:
    start_simulator(destination)
    identifier = destination.rsplit('=', 1)[1]
    subprocess.run(['xcrun', 'simctl', 'bootstatus', identifier, '-b'], check=True)
    # Fresh hosted devices have not opened Files as the serial unit/UI runner
    # had. Start its native providers before XCTest installs and launches the
    # app, preserving the existing document-picker assertions and deadlines.
    subprocess.run(['xcrun', 'simctl', 'launch', identifier, 'com.apple.DocumentsApp'], check=True)


def workflow_reader(repository: str, run_id: int, source_sha: str):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) or run_id <= 0:
        raise ValueError('expected the current workflow repository and run ID')
    prefix = f'repos/{repository}/actions/runs/{run_id}'

    def api(suffix=''):
        return json.loads(subprocess.check_output(['gh', 'api', prefix + suffix], text=True))

    if api()['head_sha'] != source_sha:
        raise ValueError('workflow wait targets a different source revision')
    return api


def wait_build_runners(repository: str, run_id: int, source_sha: str, timeout: float = 900) -> None:
    api = workflow_reader(repository, run_id, source_sha)
    deadline = time.monotonic() + timeout
    required = {'extended-ios', 'prepare-ui'}
    while True:
        jobs = [j for j in api('/jobs?per_page=100')['jobs'] if j['name'] in required]
        if any(j['status'] == 'completed' and j['conclusion'] != 'success' for j in jobs):
            raise ValueError('a critical Apple build failed before worker scheduling')
        if ({j['name'] for j in jobs} == required
                and all(j['status'] in ('in_progress', 'completed') for j in jobs)):
            print('Both critical Apple build runners are allocated; remaining workers may start.')
            return
        if time.monotonic() >= deadline:
            raise ValueError('timed out waiting for critical Apple build runners')
        time.sleep(15)


def wait_products(repository: str, run_id: int, source_sha: str, timeout: float = 900) -> None:
    api = workflow_reader(repository, run_id, source_sha)
    deadline = time.monotonic() + timeout
    while True:
        artifacts = api('/artifacts?per_page=100')['artifacts']
        matches = [a for a in artifacts if a['name'] == 'nightly-ui-products' and not a['expired']]
        if len(matches) == 1:
            print('Exact-run UI products are available; continuing with verified artifact download.')
            return
        if matches:
            raise ValueError('duplicate UI product artifacts in this workflow run')
        builders = [j for j in api('/jobs?per_page=100')['jobs'] if j['name'] == 'prepare-ui']
        if any(j['status'] == 'completed' and j['conclusion'] != 'success' for j in builders):
            raise ValueError('UI producer failed before publishing products')
        if time.monotonic() >= deadline:
            raise ValueError('timed out waiting for exact-run UI products')
        time.sleep(15)


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
    # Existing journeys intentionally share installed-app fixture state within
    # their XCTest class. Keep canonical method order and never split a class.
    classes = {}
    for test in tests:
        classes.setdefault(test.split('/')[1], []).append(test)
    if len(classes) < SHARDS:
        raise ValueError('nightly UI sharding requires at least four complete classes')
    duration = lambda group: sum(weights.get(test, 30.0) for test in group)
    groups = [[] for _ in range(SHARDS)]
    totals = [0.0] * SHARDS
    for name in sorted(classes, key=lambda cls: (-duration(classes[cls]), cls)):
        index = min(range(SHARDS), key=lambda i: (totals[i], len(groups[i]), i))
        groups[index].extend(classes[name])
        totals[index] += duration(classes[name])
    return {'source_sha': source_sha, 'tests': sorted(tests),
            'shards': [sorted(group) for group in groups], 'estimated_seconds': totals}


def validate_plan(value: dict, source_sha: str) -> None:
    if value['source_sha'] != source_sha or len(value['shards']) != SHARDS:
        raise ValueError('UI plan has the wrong source revision or shard count')
    expected = value['tests']
    if not expected or len(set(expected)) != len(expected):
        raise ValueError('UI plan inventory must be nonempty and unique')
    owners = {}
    for index, group in enumerate(value['shards']):
        for test in group:
            cls = test.split('/')[1]
            if cls in owners and owners[cls] != index:
                raise ValueError('a UI test class was split between workers')
            owners[cls] = index
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


def pack(root: Path, output: Path, source_sha: str, destination: str) -> None:
    manifest, _ = qualify(root, source_sha)
    validate_inventory(root, source_sha)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / 'products.tar.gz'
    subprocess.run(['tar', '-czf', str(archive.resolve()), '-C', str(root),
                    'Build/Products', BUILD_MARKER, 'ui-plan.json', 'ui-enumeration.json'], check=True)
    receipt = {'source_sha': source_sha, 'xcode': toolchain(), 'architecture': platform.machine(),
               'simulator': simulator_profile(destination),
               'archive_sha256': digest(archive),
               'manifest': manifest.name, 'manifest_sha256': digest(manifest)}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


def unpack(artifact: Path, root: Path, source_sha: str, destination: str) -> Path:
    receipt = json.loads((artifact / 'receipt.json').read_text())
    archive = artifact / 'products.tar.gz'
    if (receipt['source_sha'] != source_sha or receipt['xcode'] != toolchain()
            or receipt['architecture'] != platform.machine()
            or receipt['simulator'] != simulator_profile(destination)):
        raise ValueError('prepared UI artifacts do not match the checked-out source, Xcode, architecture, simulator model, and runtime')
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
    parser.add_argument('action', choices=['start-simulator', 'ready-simulator', 'wait-products', 'wait-build-runners', 'plan', 'pack', 'run', 'aggregate'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--artifact', type=Path)
    parser.add_argument('--shard', type=int, choices=range(SHARDS))
    parser.add_argument('--destination')
    parser.add_argument('--repository')
    parser.add_argument('--run-id', type=int)
    args = parser.parse_args()
    if args.action in ('pack', 'run') and args.artifact is None:
        parser.error('--artifact is required for pack/run')
    if args.action == 'pack' and not args.destination:
        parser.error('--destination is required for the prepared simulator profile')
    if args.action == 'run' and (args.shard is None or not args.destination):
        parser.error('--shard and --destination are required for run')
    if args.action in ('start-simulator', 'ready-simulator'):
        if not args.destination:
            parser.error('--destination is required for simulator readiness')
        if args.action == 'ready-simulator':
            ready_simulator(args.destination)
        else:
            start_simulator(args.destination)
    elif args.action in ('wait-products', 'wait-build-runners'):
        if not args.repository or args.run_id is None:
            parser.error('--repository and --run-id are required for workflow waiting')
        wait = wait_products if args.action == 'wait-products' else wait_build_runners
        wait(args.repository, args.run_id, args.source_sha)
    elif args.action == 'plan':
        tests = identifiers(json.loads((args.root / 'ui-enumeration.json').read_text()))
        weights = json.loads((Path(__file__).parent / 'fixtures/apple-nightly-ui-timings.json').read_text())['seconds']
        value = plan(tests, weights, args.source_sha)
        validate_plan(value, args.source_sha)
        (args.root / 'ui-plan.json').write_text(json.dumps(value, indent=2) + '\n')
        print(json.dumps({'tests': len(tests), 'shard_seconds': value['estimated_seconds']}))
    elif args.action == 'pack':
        pack(args.root, args.artifact, args.source_sha, args.destination)
    elif args.action == 'run':
        manifest = unpack(args.artifact, args.root, args.source_sha, args.destination)
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
