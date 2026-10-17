#!/usr/bin/env python3
"""Repeat the unchanged synthetic Save journey for its exact Japanese display on hosted API35.

A green run means only that this attempt did not reproduce the intermittent failure.
Stop on the first failure; never alter device settings, permissions, or app storage.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

SERIAL = 'emulator-5554'
METHOD = 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField'
CLASS = 'com.healthmd.presentation.accessibility.ProfileScheduleAccessibilityTest'
EXPECTED = 1
ROOT = Path(__file__).resolve().parent


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def validate(text, expected_cases):
    completed = []
    pending = {}
    for line in text.splitlines():
        if line.startswith('INSTRUMENTATION_STATUS: '):
            key, sep, value = line.removeprefix('INSTRUMENTATION_STATUS: ').partition('=')
            if sep:
                pending[key] = value
        elif line.startswith('INSTRUMENTATION_STATUS_CODE: '):
            code = int(line.rsplit(': ', 1)[1])
            if code != 1 and pending.get('test', '').startswith(METHOD + '['):
                completed.append({'test': pending['test'], 'class': pending.get('class'), 'code': code})
            pending = {}
    assert len(completed) == EXPECTED, f'Expected all {EXPECTED} display cases, got {len(completed)}'
    assert len({c['test'] for c in completed}) == EXPECTED, 'Duplicate or partial display selection'
    assert {c['test'] for c in completed} == set(expected_cases), 'Display identities differ from the failed source selection'
    assert all(c['class'] == CLASS for c in completed), 'Wrong native class'
    assert all(c['code'] == 0 for c in completed), 'Native failure/error/skip: inspect the retained log'
    assert any('language=ja' in c['test'] and 'width=320, height=640, fontScale=2.0' in c['test'] for c in completed), 'Japanese failure configuration missing'
    assert not re.search(r'^(?:FAILURES!!!|INSTRUMENTATION_FAILED|INSTRUMENTATION_ABORTED|Error:|INSTRUMENTATION_RESULT: (?:shortMsg|longMsg)=)', text, re.M), 'Runner failed'
    assert re.search(r'^OK \(1 test\)', text, re.M), 'Missing complete native runner success'
    return completed


EXPECTED_CASES = ['nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=640, fontScale=2.0, language=ja, dark=false)]']


def prepare_launcher(output, index):
    """Clear only a disposable emulator launcher ANR; require its actual home focus."""
    shell = ['adb', '-s', SERIAL, 'shell']
    resolved = run(*shell, 'cmd', 'package', 'resolve-activity', '--brief',
                   '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME',
                   capture_output=True, timeout=30).stdout
    components = [line.strip() for line in resolved.splitlines() if '/' in line]
    assert len(components) == 1, f'Unexpected home resolution: {resolved}'
    component = components[0]
    package = component.split('/', 1)[0]
    assert package in {'com.google.android.apps.nexuslauncher', 'com.android.launcher3'}, component
    run(*shell, 'am', 'force-stop', package, capture_output=True, timeout=30)
    launch = run(*shell, 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
                 '-c', 'android.intent.category.HOME', capture_output=True, timeout=30).stdout
    focus = ''
    for _ in range(60):
        windows = run(*shell, 'dumpsys', 'window', capture_output=True, timeout=10).stdout
        focus = next((line.strip() for line in windows.splitlines() if 'mCurrentFocus=' in line), '')
        if package + '/' in focus and 'Application Error' not in focus and 'Not Responding' not in focus:
            record = {'home_component': component, 'focused_home_window': focus,
                      'launch_output': launch, 'scope': 'Disposable hosted emulator launcher only; no app test or production source changed.'}
            (output / f'launcher-{index:02d}.json').write_text(json.dumps(record, indent=2) + '\n')
            print(f'Launcher {index}: actual home window has focus before native instrumentation.', flush=True)
            return
        time.sleep(0.5)
    raise AssertionError(f'Emulator launcher did not regain its own home window: {focus}')


def main():
    output = Path('apps/android/build/native-save-repro')
    output.mkdir(parents=True, exist_ok=True)
    head = run('git', 'rev-parse', 'HEAD', capture_output=True).stdout.strip()
    trees = {p: run('git', 'rev-parse', f'HEAD:{p}', capture_output=True).stdout.strip() for p in ['apps/android', 'packages/healthmd-core-rust']}
    (output / 'source.json').write_text(json.dumps({'head': head, 'trees': trees}, indent=2) + '\n')
    for index in range(1, 11):
        log = output / f'attempt-{index:02d}.log'
        prepare_launcher(output, index)
        proc = subprocess.run(['adb', '-s', SERIAL, 'shell', 'am', 'instrument', '-w', '-r',
                               '-e', 'class', CLASS, '-e', 'tests_regex', '.*' + METHOD + '.*language=ja.*',
                               'com.healthmd.android.test/androidx.test.runner.AndroidJUnitRunner'],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log.write_text(proc.stdout)
        try:
            assert proc.returncode == 0, f'ADB failed: {log}'
            cases = validate(proc.stdout, EXPECTED_CASES)
        except AssertionError:
            with (output / f'failure-{index:02d}.png').open('wb') as image:
                subprocess.run(['adb', '-s', SERIAL, 'exec-out', 'screencap', '-p'], stdout=image, check=False)
            print(proc.stdout, flush=True)
            raise
        (output / f'attempt-{index:02d}.json').write_text(json.dumps({'head': head, 'cases': cases}, indent=2) + '\n')
        print(f'Attempt {index}: the exact Japanese display case passed without skips; failure not reproduced.', flush=True)
    print('No reproduction in these attempts. No fix or complete-head qualification is claimed.', flush=True)

if __name__ == '__main__':
    try:
        main()
    except (AssertionError, subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
        print(f'Reproduction stopped: {exc}', file=sys.stderr, flush=True)
        sys.exit(1)
