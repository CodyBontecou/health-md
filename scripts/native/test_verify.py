"""Behavior tests for queueing, source identity and failure receipts; no SDK required."""
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location('native_verify', Path(__file__).with_name('verify.py'))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


def hold_lock(path, ready):
    with verify.build_lock(Path(path), 2):
        ready.set()
        time.sleep(0.6)


class CoordinatorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Test')
        (self.root / '.gitignore').write_text('.pi/\nbuild/\n')
        (self.root / 'source').write_text('original')
        self.git('add', '.')
        self.git('commit', '-qm', 'initial')

    def git(self, *args):
        return verify.git(self.root, *args)

    def execute(self, code):
        output = self.root / '.pi/result'
        verify.execute(self.root, ['android'], [('fixture', self.root, [sys.executable, '-c', code])],
                       output, dict(os.environ), 3)
        return json.loads((output / 'receipt.json').read_text())

    def test_selection_preserves_shared_and_unknown_impact(self):
        self.assertEqual(verify.select_platforms(['apps/apple/Test.swift']), ['apple'])
        self.assertEqual(verify.select_platforms(['apps/android/app/src/Test.kt']), ['android'])
        self.assertEqual(verify.select_platforms(['apps/apple/Assets/image.png']), ['apple'])
        for path in ['packages/contracts/schema.json', 'scripts/native/verify.py', 'Makefile', 'new-owner/code']:
            self.assertEqual(verify.select_platforms([path]), ['android', 'apple'])
        self.assertEqual(verify.select_platforms(['docs/qa/testing.md', 'apps/cli/a.rs']), [])

    def test_apple_build_schemes_name_existing_app_targets(self):
        import xml.etree.ElementTree as ET
        project = verify.ROOT / 'apps/apple/HealthMd.xcodeproj'
        contents = (project / 'project.pbxproj').read_text()
        steps = verify.build_plan(verify.ROOT, ['apple'])
        for name, cwd, command in steps:
            if name not in ('apple-ios', 'apple-macos'):
                continue
            scheme = command[command.index('-scheme') + 1]
            tree = ET.parse(project / 'xcshareddata/xcschemes' / (scheme + '.xcscheme'))
            entries = tree.findall('./BuildAction/BuildActionEntries/BuildActionEntry')
            runnable = [entry.find('BuildableReference') for entry in entries
                        if entry.get('buildForRunning') == 'YES']
            self.assertTrue(runnable)
            for reference in runnable:
                self.assertIn(reference.get('BlueprintIdentifier'), contents)
            self.assertEqual(command[1], 'build')
            self.assertNotIn('test', command)

    def test_changes_include_committed_dirty_deleted_and_new(self):
        base = self.git('rev-parse', 'HEAD')
        (self.root / 'committed').write_text('new')
        self.git('add', '.')
        self.git('commit', '-qm', 'next')
        (self.root / 'source').unlink()
        (self.root / 'new').write_text('new')
        self.assertEqual(verify.changed_paths(self.root, base), ['committed', 'new', 'source'])

    def test_content_identity_detects_edits_new_files_and_deletions(self):
        before = verify.snapshot(self.root)
        (self.root / 'source').write_text('modified')
        self.assertNotEqual(before, verify.snapshot(self.root))
        (self.root / 'source').write_text('original')
        self.assertEqual(before, verify.snapshot(self.root))
        (self.root / 'new').write_text('new')
        self.assertNotEqual(before, verify.snapshot(self.root))
        (self.root / 'new').unlink()
        (self.root / 'source').unlink()
        self.assertNotEqual(before, verify.snapshot(self.root))

    def test_pass_records_command_output_and_source(self):
        receipt = self.execute("print('compiled')")
        self.assertEqual(receipt['status'], 'passed')
        self.assertEqual(receipt['source'], receipt['source_after'])
        self.assertIn('compiled', Path(receipt['steps'][0]['log']).read_text())

    def test_failed_build_has_failed_receipt(self):
        with self.assertRaises(RuntimeError):
            self.execute('raise SystemExit(7)')
        receipt = json.loads((self.root / '.pi/result/receipt.json').read_text())
        self.assertEqual(receipt['status'], 'failed')
        self.assertEqual(receipt['steps'][0]['exit_code'], 7)

    def test_source_edit_during_build_invalidates_pass(self):
        with self.assertRaisesRegex(RuntimeError, 'Source changed'):
            self.execute("from pathlib import Path; Path('source').write_text('edited')")
        receipt = json.loads((self.root / '.pi/result/receipt.json').read_text())
        self.assertEqual(receipt['status'], 'failed')

    def test_linked_worktrees_share_lock_and_lock_releases(self):
        linked = self.root / '.pi/linked'
        self.git('worktree', 'add', '-qb', 'linked', str(linked))
        common = Path(verify.git(linked, 'rev-parse', '--git-common-dir')).resolve()
        lock = common / 'native.lock'
        ready = multiprocessing.get_context('fork').Event()
        process = multiprocessing.get_context('fork').Process(target=hold_lock, args=(str(lock), ready))
        process.start()
        try:
            self.assertTrue(ready.wait(2))
            with self.assertRaises(TimeoutError):
                with verify.build_lock(self.root / '.git/native.lock', 0.1):
                    self.fail('Overlapping native builds')
            process.join(3)
            self.assertEqual(process.exitcode, 0)
            with verify.build_lock(lock, 0.1):
                pass
        finally:
            if process.is_alive():
                process.terminate()
                process.join()

    def test_timeout_stops_owned_child_processes(self):
        marker = self.root / 'survived'
        child = f"import time; from pathlib import Path; time.sleep(0.8); Path({str(marker)!r}).touch()"
        parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(10)"
        with self.assertRaises(subprocess.TimeoutExpired):
            verify.run_step([sys.executable, '-c', parent], self.root, dict(os.environ), self.root / 'log', 0.2)
        time.sleep(1)
        self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
