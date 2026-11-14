"""Exercise actual JDK metadata discovery without initializing or running tests."""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).parents[1] / 'NativeJvmInventory.java'


@unittest.skipUnless(shutil.which('java') and shutil.which('javac'), 'JDK required for compiled inventory fixture')
class CompiledJUnitInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        annotations = self.root / 'org/junit'
        annotations.mkdir(parents=True)
        (annotations / 'Test.java').write_text('package org.junit; @java.lang.annotation.Retention(java.lang.annotation.RetentionPolicy.RUNTIME) public @interface Test {}')
        runners = annotations / 'runner'
        runners.mkdir()
        (runners / 'RunWith.java').write_text('package org.junit.runner; @java.lang.annotation.Retention(java.lang.annotation.RetentionPolicy.RUNTIME) public @interface RunWith { Class<?> value(); }')
        self.marker = self.root / 'must-not-initialize'

    def discover(self, methods, annotation=''):
        source = self.root / 'FixtureTests.java'
        source.write_text(annotation + '''public class FixtureTests {
            static { try { java.nio.file.Files.writeString(java.nio.file.Path.of(System.getenv("INIT_MARKER")), "initialized"); }
                     catch (java.io.IOException error) { throw new RuntimeException(error); } }
            ''' + methods + '\n}')
        subprocess.run(['javac', '--release', '17', '-d', str(self.root), *map(str, self.root.rglob('*.java'))], check=True, capture_output=True, text=True)
        return subprocess.run(['java', '--source', '17', '--class-path', str(self.root), str(HELPER), 'FixtureTests'],
            env=dict(os.environ, INIT_MARKER=str(self.marker)), capture_output=True, text=True)

    def test_discovers_compiled_annotations_without_running_or_initializing(self):
        result = self.discover('@org.junit.Test public void first() { throw new AssertionError(); } @org.junit.Test public void second() { throw new AssertionError(); } public void helper() {}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([base64.b64decode(line).decode() for line in result.stdout.splitlines()], ['first', 'second'])
        self.assertFalse(self.marker.exists())

    def test_custom_runner_cannot_silently_change_inventory_semantics(self):
        result = self.discover('@org.junit.Test public void first() {}', '@org.junit.runner.RunWith(Object.class) ')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_invalid_or_empty_junit_signatures_reject(self):
        for methods in ['public void helper() {}', '@org.junit.Test public static void first() {}', '@org.junit.Test public int first() { return 1; }', '@org.junit.Test public void first(int argument) {}']:
            with self.subTest(methods=methods):
                result = self.discover(methods)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.marker.exists())


if __name__ == '__main__': unittest.main()
