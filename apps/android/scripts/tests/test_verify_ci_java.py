import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify-ci-java.sh"


class JavaRuntimePinTests(unittest.TestCase):
    def run_guard(self, runtime="17.0.21+9", vendor="Eclipse Adoptium", exit_code=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            java = root / "java"
            java.write_text('''#!/usr/bin/env python3
import os, sys
assert sys.argv[1:] == ['-XshowSettings:properties', '-version']
print('    java.runtime.version = ' + os.environ['FIXTURE_JAVA_RUNTIME'], file=sys.stderr)
print('    java.vendor = ' + os.environ['FIXTURE_JAVA_VENDOR'], file=sys.stderr)
sys.exit(int(os.environ['FIXTURE_JAVA_EXIT']))
''')
            java.chmod(0o755)
            return subprocess.run(["bash", str(SCRIPT)], text=True, capture_output=True,
                                  env=dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                                           FIXTURE_JAVA_RUNTIME=runtime, FIXTURE_JAVA_VENDOR=vendor,
                                           FIXTURE_JAVA_EXIT=str(exit_code)), timeout=10)

    def test_exact_runtime_and_vendor_pass(self):
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_previous_image_runtime_and_other_build_are_rejected(self):
        for runtime in ("17.0.20.1+1", "17.0.21+7", "21.0.9+10", ""):
            with self.subTest(runtime=runtime):
                self.assertNotEqual(self.run_guard(runtime=runtime).returncode, 0)

    def test_other_vendor_is_rejected(self):
        self.assertNotEqual(self.run_guard(vendor="Other vendor").returncode, 0)

    def test_failed_java_query_is_not_accepted(self):
        self.assertNotEqual(self.run_guard(exit_code=23).returncode, 0)

    def test_android_ci_setup_and_runtime_guards_cover_every_java_lane(self):
        workflow = SCRIPT.parents[3] / ".github/workflows/android-ci.yml"
        source = workflow.read_text()
        self.assertEqual(source.count("java-version: '17.0.21+9'"), 5)
        self.assertEqual(source.count("run: bash apps/android/scripts/verify-ci-java.sh"), 5)
        self.assertNotIn("java-version: '17'", source)


if __name__ == "__main__":
    unittest.main()
