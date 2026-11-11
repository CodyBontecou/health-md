"""Exercise the local listing entry point without credentials or store access."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "validate-play-listing.sh"


class ValidatePlayListingTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="listing validation ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / "scripts"
        tests = scripts / "tests"
        tests.mkdir(parents=True)
        shutil.copy2(SCRIPT, scripts / SCRIPT.name)
        # The release entry point must not discover historical CI diagnostics.
        (tests / "test_obsolete_ci_policy.py").write_text(
            "raise AssertionError('obsolete CI policy was discovered')\n"
        )
        (tests / "test_prepare_play_metadata.py").write_text(
            "import os, unittest\n"
            "class MetadataTest(unittest.TestCase):\n"
            "    def test_metadata(self):\n"
            "        self.assertNotEqual(os.environ.get('FAIL_STAGE'), 'tests')\n"
        )
        # Keep the explicit entry-point regression module available, without
        # recursively running this fixture harness inside itself.
        (tests / Path(__file__).name).write_text("import unittest\n")
        (scripts / "prepare-play-metadata.py").write_text(
            "import os, pathlib, sys\n"
            "stage = 'all' if '--include-drafts' in sys.argv else 'reviewed'\n"
            "with open(os.environ['CALL_LOG'], 'a') as log:\n"
            "    log.write('prepare ' + stage + '\\n')\n"
            "if os.environ.get('FAIL_STAGE') == 'prepare-' + stage: sys.exit(7)\n"
            "pathlib.Path(sys.argv[sys.argv.index('--output-dir') + 1]).mkdir(parents=True)\n"
        )
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        gplay = bin_dir / "gplay"
        gplay.write_text(
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "assert len(args) == 6, args\n"
            "assert args[:1] == ['validate'], args\n"
            "assert args[1] in ('listing', 'screenshots'), args\n"
            "assert args[2] == '--dir' and args[4:] == ['--output', 'table'], args\n"
            "assert os.environ['NO_COLOR'] == '1' and os.environ['TERM'] == 'dumb'\n"
            "assert sys.stdin.read() == ''\n"
            "directory = pathlib.Path(args[3])\n"
            "assert directory.is_dir(), directory\n"
            "stage = args[1] + '-' + directory.name\n"
            "with open(os.environ['CALL_LOG'], 'a') as log: log.write(stage + '\\n')\n"
            "if os.environ.get('FAIL_STAGE') == stage: sys.exit(9)\n"
        )
        gplay.chmod(0o755)
        self.log = self.root / "calls.log"
        self.environment = {
            **os.environ,
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "CALL_LOG": str(self.log),
            "FAIL_STAGE": "",
        }

    def run_validator(self, failure: str = "") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(self.root / "scripts" / SCRIPT.name)],
            cwd=self.root.parent,
            env={**self.environment, "FAIL_STAGE": failure},
            capture_output=True,
            text=True,
            timeout=20,
        )

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_only_listing_tests_run_and_both_metadata_scopes_are_validated(self) -> None:
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [
            "prepare all", "listing-all", "screenshots-all",
            "prepare reviewed", "listing-reviewed", "screenshots-reviewed",
        ])
        self.assertIn("Google Play listing validation passed.", result.stdout)
        self.assertIn(str(self.root / "build/play-metadata/reviewed"), result.stdout)

    def test_every_failure_stops_before_later_steps_or_success(self) -> None:
        stages = [
            "tests", "prepare-all", "listing-all", "screenshots-all",
            "prepare-reviewed", "listing-reviewed", "screenshots-reviewed",
        ]
        expected_calls = [stage.replace("prepare-", "prepare ") for stage in stages[1:]]
        for index, stage in enumerate(stages):
            with self.subTest(stage=stage):
                self.log.unlink(missing_ok=True)
                shutil.rmtree(self.root / "build", ignore_errors=True)
                result = self.run_validator(stage)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Google Play listing validation passed.", result.stdout)
                self.assertEqual(self.calls(), expected_calls[:index])


if __name__ == "__main__":
    unittest.main()
