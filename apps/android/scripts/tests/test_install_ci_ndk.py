import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "install-ci-ndk.sh"


class InstallNdkTests(unittest.TestCase):
    def run_installer(self, outcomes, revision="27.1.12297006"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / "sdk with spaces"
            package = sdk / "ndk/27.1.12297006"
            package.mkdir(parents=True)
            (package / "source.properties").write_text(f"Pkg.Revision = {revision}\n")
            (root / "outcomes").write_text("\n".join(outcomes) + "\n")
            command = root / "sdkmanager"
            command.write_text(r'''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ['FAKE_SDK_STATE'])
assert sys.argv[1:] == ['ndk;27.1.12297006']
calls = root / 'calls'
n = len(calls.read_text().splitlines()) if calls.exists() else 0
with calls.open('a') as f: f.write('install\n')
outcome = (root / 'outcomes').read_text().splitlines()[n]
if outcome == 'corrupt':
    print('Warning: Error on ZipFile unknown archive.', file=sys.stderr)
    sys.exit(17)
if outcome == 'error':
    print('License not accepted', file=sys.stderr)
    sys.exit(23)
assert outcome == 'success'
''')
            command.chmod(0o755)
            environment = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                               ANDROID_SDK_ROOT=str(sdk), GITHUB_ENV=str(root / "env"),
                               FAKE_SDK_STATE=str(root))
            result = subprocess.run(["bash", str(SCRIPT)], env=environment,
                                    text=True, capture_output=True, timeout=10)
            calls = (root / "calls").read_text().splitlines()
            exported = (root / "env").read_text() if (root / "env").exists() else ""
            return result, calls, exported

    def test_success_installs_once_and_exports_verified_revision(self):
        result, calls, exported = self.run_installer(["success"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)
        self.assertIn("ANDROID_NDK_HOME=", exported)
        self.assertIn("ANDROID_NDK_ROOT=", exported)

    def test_corrupt_download_retries_once(self):
        result, calls, exported = self.run_installer(["corrupt", "success"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertIn("ANDROID_NDK_HOME=", exported)

    def test_second_corrupt_download_preserves_failure(self):
        result, calls, exported = self.run_installer(["corrupt", "corrupt"])
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertEqual(exported, "")

    def test_other_errors_do_not_retry(self):
        result, calls, exported = self.run_installer(["error"])
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(len(calls), 1)
        self.assertEqual(exported, "")

    def test_wrong_installed_revision_fails_without_export(self):
        result, calls, exported = self.run_installer(["success"], revision="27.2.000")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(exported, "")


if __name__ == "__main__":
    unittest.main()
