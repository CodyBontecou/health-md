#!/usr/bin/env python3
"""Run the unchanged synthetic Save journey on the repository-required Pixel 7.

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

SERIAL = 'emulator-5554'
METHOD = 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField'
CLASS = 'com.healthmd.presentation.accessibility.ProfileScheduleAccessibilityTest'
EXPECTED = 10
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
    assert re.search(r'^OK \(10 tests\)', text, re.M), 'Missing complete native runner success'
    return completed


EXPECTED_CASES = ['nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=411, height=720, fontScale=1.0, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=640, fontScale=1.0, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=480, fontScale=1.3, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=480, fontScale=2.0, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=640, fontScale=2.0, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=568, height=280, fontScale=2.0, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=640, height=280, fontScale=2.0, language=en, dark=false)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=480, fontScale=2.0, language=de, dark=true)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=480, fontScale=2.0, language=ar, dark=true)]', 'nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField[AccessibilityDisplayCase(width=320, height=640, fontScale=2.0, language=ja, dark=false)]']

def main():
    output = Path('apps/android/build/native-save-repro')
    output.mkdir(parents=True, exist_ok=True)
    head = run('git', 'rev-parse', 'HEAD', capture_output=True).stdout.strip()
    trees = {p: run('git', 'rev-parse', f'HEAD:{p}', capture_output=True).stdout.strip() for p in ['apps/android', 'packages/healthmd-core-rust']}
    (output / 'source.json').write_text(json.dumps({'head': head, 'trees': trees}, indent=2) + '\n')
    for index in range(1, 11):
        log = output / f'attempt-{index:02d}.log'
        proc = subprocess.run(['adb', '-s', SERIAL, 'shell', 'am', 'instrument', '-w', '-r',
                               '-e', 'class', CLASS, '-e', 'tests_regex', '.*' + METHOD + '.*',
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
        print(f'Attempt {index}: all 10 display cases passed without skips; failure not reproduced.', flush=True)
    print('No reproduction in these attempts. No fix or complete-head qualification is claimed.', flush=True)

if __name__ == '__main__':
    try:
        main()
    except (AssertionError, subprocess.CalledProcessError, OSError) as exc:
        print(f'Reproduction stopped: {exc}', file=sys.stderr, flush=True)
        sys.exit(1)
