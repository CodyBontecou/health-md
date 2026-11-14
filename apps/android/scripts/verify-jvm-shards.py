#!/usr/bin/env python3
"""Require every fresh Play JVM lane and the exact compiled native method set."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

NATIVE_CLASS = 'com.healthmd.direct.AgentBridgeNativeConfigurationReaderTest'
TASKS = {'debug': 'testPlayDebugUnitTest', 'release': 'testPlayReleaseUnitTest', 'e2e': 'testPlayE2eUnitTest'}
LANES = ('remaining', 'native-0', 'native-1')
MODULES = {'healthmd-core': 'testDebugUnitTest', 'wearable-contract': 'test', 'direct-protocol': 'test'}


def ordered(values):
    # Match Java/Groovy String.compareTo, including supplementary method names.
    return sorted(values, key=lambda value: value.encode('utf-16-be'))


def read_cases(directory: Path) -> dict:
    files = sorted(directory.glob('TEST-*.xml'))
    if not files:
        raise ValueError(f'Missing actual JVM XML in {directory}')
    cases = {}
    for path in files:
        if path.is_symlink():
            raise ValueError('JVM result must be a regular file')
        root = ET.parse(path).getroot()
        if root.tag != 'testsuite' or int(root.get('failures', '-1')) != 0 or int(root.get('errors', '-1')) != 0:
            raise ValueError('JVM suite failed or has no trustworthy summary')
        rows = root.findall('testcase')
        if len(rows) != int(root.get('tests', '-1')) or not rows:
            raise ValueError('JVM summary does not match actual test cases')
        skipped = 0
        for case in rows:
            name, owner = case.get('name'), case.get('classname')
            if not name or not owner or case.find('failure') is not None or case.find('error') is not None:
                raise ValueError('Incomplete or failing actual JVM case')
            key = (owner, name)
            if key in cases:
                raise ValueError('Duplicate actual JVM case')
            status = 'Skipped' if case.find('skipped') is not None else 'Passed'
            skipped += status == 'Skipped'
            cases[key] = status
        if skipped != int(root.get('skipped', '-1')):
            raise ValueError('JVM skipped count differs from actual cases')
    return cases


def verify(reports: Path, source_sha: str, run_id: str, attempt: str) -> dict:
    if not re.fullmatch('[0-9a-f]{40}', source_sha) or any(not re.fullmatch('[1-9][0-9]*', item) for item in (run_id, attempt)):
        raise ValueError('Exact current source/run/attempt required')
    expected = {f'android-jvm-{variant}-{lane}-results-{run_id}-{attempt}' for variant in TASKS for lane in LANES}
    if {path.name for path in reports.iterdir()} != expected:
        raise ValueError('Missing or unexpected Play JVM lane artifacts')
    result = {'source_sha': source_sha, 'run_id': run_id, 'attempt': attempt, 'variants': {}}
    for variant, task in TASKS.items():
        combined, native_methods = {}, None
        for lane in LANES:
            folder = reports / f'android-jvm-{variant}-{lane}-results-{run_id}-{attempt}'
            if folder.is_symlink() or not folder.is_dir():
                raise ValueError('JVM artifact must be a regular directory')
            metadata = json.loads((folder / f'build/reports/ci/jvm-native-{variant}-{lane}.json').read_text())
            binding = {'source_sha': source_sha, 'run_id': run_id, 'attempt': attempt,
                       'variant': variant, 'lane': lane, 'task': ':app:' + task, 'native_class': NATIVE_CLASS}
            if any(metadata.get(key) != value for key, value in binding.items()):
                raise ValueError('JVM lane source/run/task differs from current qualification')
            methods = metadata.get('native_methods')
            if (not isinstance(methods, list) or not methods or any(not isinstance(name, str) or not name for name in methods)
                    or methods != ordered(set(methods))):
                raise ValueError('Missing or ambiguous compiled native inventory')
            if native_methods is None:
                native_methods = methods
            elif native_methods != methods:
                raise ValueError('Compiled native inventories differ between workers')
            selected = [] if lane == 'remaining' else methods[int(lane[-1])::2]
            included = [] if lane == 'remaining' else ordered(NATIVE_CLASS + '.' + name for name in selected)
            excluded = [NATIVE_CLASS] if lane == 'remaining' else []
            if (metadata.get('selected_methods') != selected or metadata.get('include_patterns') != included
                    or metadata.get('exclude_patterns') != excluded):
                raise ValueError('JVM filters differ from the exhaustive lane partition')
            actual = read_cases(folder / f'app/build/test-results/{task}')
            actual_native = ordered(name for (owner, name) in actual if owner == NATIVE_CLASS)
            if actual_native != selected:
                raise ValueError('Actual native methods differ from compiled lane selection')
            if lane != 'remaining' and any(owner != NATIVE_CLASS for owner, _ in actual):
                raise ValueError('Unexpected non-native case in native-only lane')
            if combined.keys() & actual.keys():
                raise ValueError('A JVM test ran in more than one lane')
            combined.update(actual)
            if variant == 'debug' and lane == 'remaining':
                result['shared_modules'] = {module: len(read_cases(folder / f'{module}/build/test-results/{module_task}'))
                                            for module, module_task in MODULES.items()}
        if ordered(name for (owner, name) in combined if owner == NATIVE_CLASS) != native_methods:
            raise ValueError('Combined native JVM inventory is incomplete')
        result['variants'][variant] = {'tests': len(combined), 'passed': sum(value == 'Passed' for value in combined.values()),
                                       'skipped': sum(value == 'Skipped' for value in combined.values()), 'native_methods': len(native_methods)}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--attempt', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.reports, args.source_sha, args.run_id, args.attempt)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__': main()
