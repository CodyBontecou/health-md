#!/usr/bin/env python3
"""Exercise the actual release-tag validator and promotion shell with local Git."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[4]
VALIDATOR = ROOT / "apps/android/scripts/validate-phone-release-tag.py"


class PhoneReleaseTagTest(unittest.TestCase):
    def check_tag(self, tag, version="3.5.0", code="44"):
        return subprocess.run(["python3", str(VALIDATOR), tag, version, code], capture_output=True).returncode

    def test_exact_version_and_optional_exact_build(self):
        for tag in ("android/v3.5.0", "android/v3.5.0+44"):
            self.assertEqual(0, self.check_tag(tag))
        for tag in ("android/v3.5.0+43", "android/v3.5.0+044", "android/v3.5.1+44",
                    "android/v3.5.0+44/other", "android/v3.5.0^{}", "v3.5.0", "android/recovery/x"):
            self.assertNotEqual(0, self.check_tag(tag), tag)
        for version, code in (("03.5.0", "44"), ("3.5.0-rc1", "44"), ("3.5.0", "0"),
                              ("3.5.0", "044"), ("3.5.0", "1000000")):
            self.assertNotEqual(0, self.check_tag(f"android/v{version}+{code}", version, code))

    def test_promotion_checks_actual_tag_source_and_recovery(self):
        doc = yaml.safe_load((ROOT / ".github/workflows/android-promote-production.yml").read_text())
        step = next(s for s in doc["jobs"]["promote-production"]["steps"]
                    if s.get("name") == "Validate immutable phone promotion request")
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp) / "repo"
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=repo, stderr=subprocess.DEVNULL, text=True).strip()
            git("init", "-b", "main")
            git("config", "user.name", "QA")
            git("config", "user.email", "qa@example.invalid")
            android = repo / "apps/android"
            (android / "scripts").mkdir(parents=True)
            shutil.copy(VALIDATOR, android / "scripts" / VALIDATOR.name)
            (android / "app").mkdir()
            (android / "app/build.gradle.kts").write_text('versionName = "3.5.0"\nversionCode = 44\n')
            scope = (ROOT / "apps/android/release-scope.json").read_text()
            (android / "release-scope.json").write_text(scope)
            git("add", ".")
            git("commit", "-m", "source")
            sha = git("rev-parse", "HEAD")
            for tag in ("android/v3.5.0", "android/v3.5.0+44", "android/v3.5.0+43", "android/recovery/workflow"):
                git("tag", "-a", tag, "-m", tag)
            git("tag", "android/v3.5.0+45")  # a lightweight tag cannot authorize promotion
            origin = str(Path(temp) / "origin.git")
            subprocess.run(["git", "clone", "--bare", str(repo), origin], check=True, capture_output=True)
            git("remote", "add", "origin", origin)
            for ref, release_tag, code, success in (
                ("android/v3.5.0", "", "44", True),
                ("android/v3.5.0+44", "", "44", True),
                ("android/recovery/workflow", "android/v3.5.0+44", "44", True),
                ("android/v3.5.0+43", "", "44", False),
                ("android/v3.5.0+45", "", "45", False),
                ("android/v3.5.0", "android/v3.5.0+44", "44", False),
                ("android/recovery/workflow", "android/v3.5.0+43", "44", False),
            ):
                env = {**os.environ, "VERSION": "3.5.0", "VERSION_CODE": code,
                       "RELEASE_TAG": release_tag, "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": ref,
                       "GITHUB_SHA": sha, "RUNNER_TEMP": temp, "GITHUB_REF": f"refs/tags/{ref}", "GITHUB_OUTPUT": str(Path(temp) / "output")}
                result = subprocess.run(["bash", "-c", step["run"]], cwd=android, env=env, capture_output=True)
                self.assertEqual(success, result.returncode == 0, (ref, release_tag, result.stderr.decode()))

            release = yaml.safe_load((ROOT / ".github/workflows/android-release.yml").read_text())
            release_step = next(s for s in release["jobs"]["build-signed-phone"]["steps"]
                                if s.get("name") == "Validate tag, phone-only scope, and committed version")
            for tag, expected_sha, success in (
                ("android/v3.5.0", sha, True),
                ("android/v3.5.0+44", sha, True),
                ("android/v3.5.0+43", sha, False),
                ("android/v3.5.0+45", sha, False),
                ("android/v3.5.0+44", "0" * 40, False),
            ):
                env = {**os.environ, "RELEASE_TAG": tag, "RELEASE_SHA": expected_sha, "GITHUB_SHA": sha, "RUNNER_TEMP": temp,
                       "GITHUB_OUTPUT": str(Path(temp) / "output")}
                result = subprocess.run(["bash", "-c", release_step["run"]], cwd=android, env=env, capture_output=True)
                self.assertEqual(success, result.returncode == 0, (tag, result.stderr.decode()))

            # Older recovery product checkouts predate the helper. The workflow's
            # Git revision, rather than that checkout's files, must supply it.
            (android / "scripts" / VALIDATOR.name).unlink()
            env = {**os.environ, "VERSION": "3.5.0", "VERSION_CODE": "44",
                   "RELEASE_TAG": "android/v3.5.0+44", "RELEASE_SHA": sha,
                   "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "android/recovery/workflow",
                   "GITHUB_SHA": sha, "GITHUB_REF": "refs/tags/android/recovery/workflow",
                   "RUNNER_TEMP": temp, "GITHUB_OUTPUT": str(Path(temp) / "output")}
            for run in (step["run"], release_step["run"]):
                result = subprocess.run(["bash", "-c", run], cwd=android, env=env, capture_output=True)
                self.assertEqual(0, result.returncode, result.stderr.decode())

    def test_all_active_phone_tag_consumers_use_validator(self):
        for name in ("android-release.yml", "android-promote-production.yml", "android-announce.yml"):
            self.assertIn("validate-phone-release-tag.py", (ROOT / ".github/workflows" / name).read_text())


if __name__ == "__main__":
    unittest.main()
