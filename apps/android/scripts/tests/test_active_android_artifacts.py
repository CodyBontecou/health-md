"""The active phone CI build must not require a deferred Wear artifact."""
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[4]


class ActiveAndroidArtifactTests(unittest.TestCase):
    def test_phone_assembly_does_not_invoke_paired_wear_evidence_test(self):
        workflow = (ROOT / '.github/workflows/android-ci.yml').read_text()
        step = workflow.split('      - name: Assemble Play debug app', 1)[1].split('      - name:', 1)[0]
        command = textwrap.dedent(step.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'scripts'
            (scripts / 'tests').mkdir(parents=True)
            gradle = scripts / 'run-ci-gradle.sh'
            gradle.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > built-tasks\n')
            gradle.chmod(0o755)
            # This real-artifact check requires both phone and Wear APKs. Its
            # SDK-free receipt regressions run separately in the policy job.
            (scripts / 'tests/test_verify_google_play_generated_apk_evidence.sh').write_text('exit 19\n')
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', command], cwd=root,
                                    env=os.environ, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(':app:assemblePlayDebug :app:bundlePlayDebug --stacktrace',
                             (root / 'built-tasks').read_text().strip())


if __name__ == '__main__':
    unittest.main()
