#!/usr/bin/env python3
"""Serialize local native compilation across a repository's linked worktrees."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time
import uuid
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[2]


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args]).decode().strip()


def select_platforms(paths):
    selected = set()
    for path in paths:
        if path.endswith('.md') or path.startswith('docs/'):
            continue
        if path.startswith('apps/apple/'):
            selected.add('apple')
        elif path.startswith('apps/android/'):
            selected.add('android')
        elif path.startswith(('packages/', 'scripts/')) or '/' not in path:
            selected.update(('apple', 'android'))
        elif not path.startswith(('apps/cli/', 'apps/website/', 'apps/practice/', 'apps/wake/', '.github/')):
            selected.update(('apple', 'android'))
    return sorted(selected)


def changed_paths(root, base):
    # Include committed changes, staged/unstaged edits, deletions and new source files.
    ancestor = git(root, 'merge-base', base, 'HEAD')
    changed = subprocess.check_output(['git', '-C', str(root), 'diff', '--name-only', '-z', ancestor])
    new = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--others', '--exclude-standard', '-z'])
    return sorted(set(os.fsdecode(p) for p in (changed + new).split(b'\0') if p))


def snapshot(root):
    """Conservative content identity, including dirty/new/deleted nonignored files."""
    digest = hashlib.sha256()
    revision = git(root, 'rev-parse', 'HEAD')
    digest.update(revision.encode())
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard', '-z'])
    for name in sorted(set(p for p in names.split(b'\0') if p)):
        path = root / os.fsdecode(name)
        digest.update(len(name).to_bytes(8, 'big') + name)
        if path.is_symlink():
            value = os.fsencode(os.readlink(path))
            digest.update(b'link' + len(value).to_bytes(8, 'big') + value)
        elif path.is_file():
            stat = path.stat()
            digest.update(f'file:{stat.st_mode}:{stat.st_size}:'.encode())
            with path.open('rb') as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(chunk)
        elif not path.exists():
            digest.update(b'deleted')
        else:
            raise RuntimeError(f'Unsupported source entry: {path}')
    return {'commit': revision, 'sha256': digest.hexdigest()}


@contextmanager
def build_lock(path, timeout):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+') as lock:
        start = time.monotonic()
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() - start >= timeout:
                    raise TimeoutError(f'Native build queue busy after {timeout}s: {path}')
                time.sleep(0.2)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def build_plan(root, selected):
    steps = [('rust-toolchain', root / 'packages/healthmd-core-rust', ['rustc', '--version'])] if selected else []
    if 'apple' in selected:
        steps.append(('xcode-toolchain', root / 'apps/apple', ['xcodebuild', '-version']))
        steps.append(('apple-core', root / 'apps/apple', ['make', 'prepare-healthmd-core-rust']))
        common = ['xcodebuild', 'build', '-project', 'HealthMd.xcodeproj', '-quiet',
                  '-derivedDataPath', str(root / 'apps/apple/build/native-verification'),
                  '-jobs', '2', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
                  'CODE_SIGN_IDENTITY=', 'DEVELOPMENT_TEAM=', 'PROVISIONING_PROFILE_SPECIFIER=',
                  'ONLY_ACTIVE_ARCH=YES', 'ARCHS=arm64']
        steps.extend([
            ('apple-ios', root / 'apps/apple', common + ['-scheme', 'HealthMd', '-configuration', 'Debug-iOS', '-destination', 'generic/platform=iOS Simulator']),
            ('apple-macos', root / 'apps/apple', common + ['-scheme', 'HealthMd-macOS', '-configuration', 'Debug', '-destination', 'platform=macOS,arch=arm64']),
        ])
    if 'android' in selected:
        steps.append(('android-toolchain', root / 'apps/android', ['./gradlew', '--version']))
        steps.append(('android', root / 'apps/android', ['./gradlew', ':app:assemblePlayDebug',
                     '-Phealthmd.ciAbi=arm64-v8a', '--max-workers=2', '--console=plain', '--no-daemon']))
    return steps


def run_step(command, cwd, environment, log, timeout):
    with log.open('w') as output:
        process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except BaseException:
            # Keep the repository lock until the entire owned build process group stops.
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise


def execute(root, selected, steps, results, environment, step_timeout):
    results.mkdir(parents=True)
    receipt = {'schema': 1, 'worktree': str(root), 'platforms': selected,
               'source': snapshot(root), 'status': 'running', 'steps': [],
               'started_at': time.time(), 'host': platform.platform(),
               'environment': {key: environment.get(key) for key in
                               ('DEVELOPER_DIR', 'JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT',
                                'HEALTHMD_CORE_APPLE_SCOPE', 'CARGO_TARGET_DIR')}}
    path = results / 'receipt.json'

    def save():
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(receipt, indent=2) + '\n')
        temporary.replace(path)

    save()
    try:
        for name, cwd, command in steps:
            entry = {'name': name, 'cwd': str(cwd), 'command': command,
                     'log': str(results / f'{name}.log'), 'started_at': time.time()}
            receipt['steps'].append(entry)
            save()
            print(f'Building {name}; log: {entry["log"]}', flush=True)
            entry['exit_code'] = run_step(command, cwd, environment, Path(entry['log']), step_timeout)
            entry['finished_at'] = time.time()
            save()
            if entry['exit_code']:
                raise RuntimeError(f'{name} failed ({entry["exit_code"]}); see {entry["log"]}')
        receipt['source_after'] = snapshot(root)
        if receipt['source_after'] != receipt['source']:
            raise RuntimeError('Source changed during compilation; rerun against the finished inputs')
        receipt['status'] = 'passed'
    except BaseException as error:
        receipt['status'] = 'failed'
        receipt['error'] = str(error) or type(error).__name__
        raise
    finally:
        receipt['finished_at'] = time.time()
        save()
        print(f'Receipt: {path}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['auto', 'apple', 'android', 'all'], default='auto')
    parser.add_argument('--base', default='origin/main', help='Auto selection uses merge-base plus dirty/new files')
    parser.add_argument('--plan', action='store_true', help='Print commands without acquiring the queue or building')
    parser.add_argument('--wait-seconds', type=float, default=1800)
    parser.add_argument('--step-timeout', type=float, default=1800)
    args = parser.parse_args()
    if args.wait_seconds < 0 or args.step_timeout <= 0:
        parser.error('Wait must be nonnegative and step timeout must be positive')
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    root = ROOT.resolve()
    common = Path(git(root, 'rev-parse', '--git-common-dir'))
    if not common.is_absolute():
        common = (root / common).resolve()
    lock = common / 'healthmd-native-verification.lock'
    # Selection is repeated after waiting, so edits made in the queue are included.
    def selection():
        return (select_platforms(changed_paths(root, args.base)) if args.platform == 'auto'
                else ['apple', 'android'] if args.platform == 'all' else [args.platform])
    if args.plan:
        print(json.dumps({'lock': str(lock), 'platforms': selection(), 'steps': [
            {'name': name, 'cwd': str(cwd), 'command': command}
            for name, cwd, command in build_plan(root, selection())]}, indent=2))
        return
    print(f'Waiting for local native build queue: {lock}', flush=True)
    with build_lock(lock, args.wait_seconds):
        selected = selection()
        if not selected:
            print('No native build selected; portable/focused checks still apply.')
            return
        if 'apple' in selected and (sys.platform != 'darwin' or platform.machine() != 'arm64'):
            raise RuntimeError('Apple verification requires an arm64 Mac with Xcode')
        environment = dict(os.environ)
        environment['HEALTHMD_CORE_APPLE_SCOPE'] = 'ci-arm64'
        # Keep this lane incremental and isolated from other worktrees/release targets.
        environment['CARGO_TARGET_DIR'] = str(root / 'packages/healthmd-core-rust/target/native-verification')
        results = root / '.pi/native-verification' / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
        execute(root, selected, build_plan(root, selected), results, environment, args.step_timeout)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, TimeoutError, subprocess.CalledProcessError, OSError) as error:
        print(f'Native verification failed: {error}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
