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
PROFILE_TEXT = {'gradle', 'ndk_revision', 'os', 'arch'}
PROFILE_COMPILER_HASH = {'test_java_sha256', 'gradle_java_sha256', 'rustc_sha256', 'cargo_ndk_sha256'}
PROFILE_EXECUTION_HASH = {'environment_sha256', 'classpath_sha256', 'jvm_args_sha256', 'host_core_sha256'}


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
    selected_artifacts = {}
    for path in reports.iterdir():
        match = re.fullmatch(rf'android-jvm-(debug|release|e2e)-(remaining|native-0|native-1)-results-{run_id}-([1-9][0-9]*)', path.name)
        if not match or int(match[3]) > int(attempt) or path.is_symlink() or not path.is_dir():
            raise ValueError('Future, missing or unexpected Play JVM lane artifact')
        key = (match[1], match[2])
        if key not in selected_artifacts or int(match[3]) > int(selected_artifacts[key][0]):
            selected_artifacts[key] = (match[3], path)
    if set(selected_artifacts) != {(variant, lane) for variant in TASKS for lane in LANES}:
        raise ValueError('Missing Play JVM lane artifacts')
    result = {'source_sha': source_sha, 'run_id': run_id, 'attempt': attempt, 'variants': {},
              'lane_attempts': {f'{variant}:{lane}': selected_artifacts[(variant, lane)][0] for variant in TASKS for lane in LANES}}
    compiler_profile = None
    execution_profiles = {}
    for variant, task in TASKS.items():
        combined, native_methods = {}, None
        for lane in LANES:
            artifact_attempt, folder = selected_artifacts[(variant, lane)]
            if folder.is_symlink() or not folder.is_dir():
                raise ValueError('JVM artifact must be a regular directory')
            metadata = json.loads((folder / f'build/reports/ci/jvm-native-{variant}-{lane}.json').read_text())
            binding = {'source_sha': source_sha, 'run_id': run_id, 'attempt': artifact_attempt,
                       'variant': variant, 'lane': lane, 'task': ':app:' + task, 'native_class': NATIVE_CLASS}
            if any(metadata.get(key) != value for key, value in binding.items()):
                raise ValueError('JVM lane source/run/task differs from current qualification')
            profile = metadata.get('qualification_profile')
            if (not isinstance(profile, dict) or set(profile) != {'version', 'compiler', 'execution'}
                    or type(profile['version']) is not int or profile['version'] != 1):
                raise ValueError('Missing or invalid JVM qualification profile')
            compiler, execution = profile['compiler'], profile['execution']
            if (not isinstance(compiler, dict) or set(compiler) != PROFILE_TEXT | PROFILE_COMPILER_HASH
                    or any(not isinstance(compiler[key], str) or not compiler[key].strip() for key in PROFILE_TEXT)
                    or any(not isinstance(compiler[key], str) or not re.fullmatch('[a-f0-9]{64}', compiler[key]) for key in PROFILE_COMPILER_HASH)
                    or compiler['ndk_revision'] != '27.1.12297006'
                    or not isinstance(execution, dict) or set(execution) != PROFILE_EXECUTION_HASH | {'max_parallel_forks'}
                    or any(not isinstance(execution[key], str) or not re.fullmatch('[a-f0-9]{64}', execution[key]) for key in PROFILE_EXECUTION_HASH)
                    or type(execution['max_parallel_forks']) is not int or execution['max_parallel_forks'] < 1):
                raise ValueError('Missing or invalid JVM compiler/execution profile')
            if compiler_profile is None:
                compiler_profile = compiler
            elif compiler != compiler_profile:
                raise ValueError('JVM compiler profiles differ between lanes')
            if variant not in execution_profiles:
                execution_profiles[variant] = execution
            elif execution != execution_profiles[variant]:
                raise ValueError('JVM execution/dependency profiles differ within a variant')
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
    result['compiler_profile'] = compiler_profile
    result['execution_profiles'] = execution_profiles
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
