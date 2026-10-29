"""Host-only tests for opt-in native diagnostics after nightly CI retirement."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[4]


class NativeDiagnosticTests(unittest.TestCase):
    def test_full_native_suites_remain_explicit_not_portable_regressions(self):
        policy = (REPO / 'docs/qa/two-minute-ci.md').read_text()
        self.assertIn('not PR regression', policy)
        self.assertFalse((REPO / '.github/workflows/apple-nightly.yml').exists())
        workflow = (REPO / '.github/workflows/ci.yml').read_text()
        for command in ('xcodebuild', 'make coverage', 'make test-ios', 'simctl'):
            self.assertNotIn(command, workflow)
        makefile = (REPO / 'apps/apple/Makefile').read_text()
        self.assertIn('test: test-ios test-macos', makefile)
        self.assertIn('coverage: prepare-healthmd-core-rust', makefile)
        self.assertIn('-enableCodeCoverage YES', makefile)

    def test_native_commands_preserve_full_selection_and_failures(self):
        # Every native executable is a stub. This test never boots or uses an SDK.
        for target, scheme in [('test-ios', 'HealthMd-Tests-iOS'), ('coverage', 'HealthMd-Tests-macOS')]:
            for status in (0, 65):
                with self.subTest(target=target, status=status), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    (root / 'Makefile').write_bytes((REPO / 'apps/apple/Makefile').read_bytes())
                    binary = root / 'bin'
                    binary.mkdir()
                    xcode = binary / 'xcodebuild'
                    xcode.write_text(f'#!{sys.executable}\n' + '''
import json, os, sys
from pathlib import Path
Path('arguments.json').write_text(json.dumps(sys.argv[1:]))
print('Test Case native suite output')
print('raw compiler diagnostic', file=sys.stderr)
sys.exit(int(os.environ['FAKE_STATUS']))
''')
                    xcode.chmod(0o755)
                    pretty = binary / 'xcpretty'
                    pretty.write_text('#!/bin/sh\ncat\n')
                    pretty.chmod(0o755)
                    xcrun = binary / 'xcrun'
                    xcrun.write_text('#!/bin/sh\nexit 0\n')
                    xcrun.chmod(0o755)
                    result = subprocess.run(['make', '-f', str(REPO / 'apps/apple/Makefile'),
                        target, 'CORE_RUST_PREPARE=:', 'IOS_SIM=platform=iOS Simulator,id=fake',
                        'IOS_TEST_BUILD_FLAGS=ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO'],
                        cwd=root, text=True, capture_output=True, env=dict(os.environ,
                        PATH=f'{binary}:{os.environ["PATH"]}', FAKE_STATUS=str(status)))
                    self.assertEqual(result.returncode == 0, status == 0, result.stderr)
                    args = json.loads((root / 'arguments.json').read_text())
                    self.assertEqual(args[0], 'test')
                    self.assertEqual(args[args.index('-scheme') + 1], scheme)
                    self.assertFalse(any(a.startswith(('-only-testing', '-skip-testing')) for a in args))
                    if target == 'test-ios':
                        self.assertIn('ARCHS=arm64', args)
                        self.assertIn('ONLY_ACTIVE_ARCH=YES', args)
                        self.assertIn('COMPILER_INDEX_STORE_ENABLE=NO', args)
                        self.assertIn('-resultBundlePath', args)
                        raw = (root / 'build/logs/xcodebuild-ios-raw.log').read_text()
                        self.assertIn('native suite output', raw)
                        self.assertIn('raw compiler diagnostic', raw)
                    else:
                        self.assertEqual(args[args.index('-enableCodeCoverage') + 1], 'YES')
                        self.assertIn('native suite output', result.stdout)
                        self.assertIn('raw compiler diagnostic', result.stderr)


if __name__ == '__main__':
    unittest.main()
