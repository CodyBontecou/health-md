#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[2]


class AndroidDeferredWearScopeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.android = self.repo / "apps/android"
        for relative in (
            "scripts/android-release-scope.sh",
            "scripts/verify-wear-audit-evidence.sh",
            "scripts/validate-wear-artifact.sh",
            "scripts/report-wear-release-blockers.sh",
            "scripts/verify-wear-release-evidence-bundle.sh",
            "scripts/extract-wear-release-evidence-archive.py",
            "app/build.gradle.kts",
            "wear/build.gradle.kts",
            "wear/src/main/AndroidManifest.xml",
            "docs/features/wear-os-completion-audit.md",
            "release-scope.json",
        ):
            target = self.android / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ANDROID / relative, target)
        workflow = ".github/workflows/android-wear-evidence.yml"
        target = self.repo / workflow
        target.parent.mkdir(parents=True)
        shutil.copyfile(ANDROID.parents[1] / workflow, target)
        for module in ("app", "wear"):
            for source in (ANDROID / module / "src/main/res").glob("values*"):
                if not source.is_dir():
                    continue
                destination = self.android / module / "src/main/res" / source.name
                destination.mkdir(parents=True, exist_ok=True)
                if module == "wear" and (source / "strings.xml").exists():
                    shutil.copyfile(source / "strings.xml", destination / "strings.xml")
        self.set_version("app", "2.3.4", 55)
        self.set_version("wear", "2.3.3", 1000054)
        self.scope = json.loads((self.android / "release-scope.json").read_text())
        self.scope["releaseVersionName"] = "2.3.4"
        self.scope["googlePlay"]["phone"]["versionCode"] = 55
        self.write_scope()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        git = self.bin / "git"
        git.write_text('#!/bin/sh\nprintf "%s\\n" "$REVIEW_TEST_REPO"\n')
        git.chmod(0o755)
        self.sdk = Path(self.temp.name) / "sdk"
        self.aapt = self.sdk / "build-tools/35.0.0/aapt"
        self.aapt.parent.mkdir(parents=True)
        self.aapt.write_text('''#!/usr/bin/env python3
import json, sys
apk=json.load(open(sys.argv[-1]))
print("package: name='com.healthmd.android' versionCode='%s' versionName='%s'" % (apk['code'], apk['version']))
print("uses-feature: name='android.hardware.type.watch'")
''')
        self.aapt.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        REVIEW_TEST_REPO=str(self.repo), ANDROID_HOME=str(self.sdk),
                        WEAR_REQUIRE_SIGNING_ATTESTATION="false")
        self.apk = self.android / "wear-test.apk"
        self.apk.write_text(json.dumps({"code": 1000054, "version": "2.3.3"}))

    def set_version(self, module: str, name: str, code: int) -> None:
        path = self.android / module / "build.gradle.kts"
        text = re.sub(r'versionName = "[^"]*"', f'versionName = "{name}"', path.read_text(), count=1)
        text = re.sub(r'versionCode = [0-9_]+', f'versionCode = {code}', text, count=1)
        path.write_text(text)

    def write_scope(self) -> None:
        (self.android / "release-scope.json").write_text(json.dumps(self.scope))

    def activate_wear(self, align_versions: bool = False) -> None:
        self.scope["googlePlay"]["wear"].update(status="release_candidate", runtimeAdvertisedByPhone=True)
        self.write_scope()
        if align_versions:
            self.set_version("wear", "2.3.4", 1000054)
            self.apk.write_text(json.dumps({"code": 1000054, "version": "2.3.4"}))

    def run_script(self, name: str, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(self.android / "scripts" / name), *args],
                              cwd=self.android, env=self.env, text=True, capture_output=True)

    def assert_result(self, result: subprocess.CompletedProcess[str], success: bool, message: str) -> None:
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, output)
        self.assertIn(message, output)

    def mode(self, version: str = "2.3.4", code: str = "55") -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", "-c", 'source "$1"; android_release_wear_mode "$2" "$3" "$4"',
                               "scope-test", str(self.android / "scripts/android-release-scope.sh"),
                               str(self.android / "release-scope.json"), version, code],
                              text=True, capture_output=True)

    def test_helper_accepts_valid_deferred_and_active_scope(self) -> None:
        self.assert_result(self.mode(), True, "deferred")
        self.activate_wear()
        self.assert_result(self.mode(), True, "paired")

    def test_helper_rejects_malformed_scope_and_phone_identity_mismatch(self) -> None:
        for version, code in (("2.3.5", "55"), ("2.3.4", "56")):
            with self.subTest(version=version, code=code):
                self.assertNotEqual(self.mode(version, code).returncode, 0)
        (self.android / "release-scope.json").write_text("{malformed")
        self.assertNotEqual(self.mode().returncode, 0)

    def test_helper_rejects_deferral_flags_and_incomplete_scope(self) -> None:
        cases = (("published", True), ("runtimeAdvertisedByPhone", True),
                 ("reason", " "), ("targetVersionName", "invalid"), ("status", "unknown"))
        for key, value in cases:
            with self.subTest(key=key):
                original = self.scope["googlePlay"]["wear"][key]
                self.scope["googlePlay"]["wear"][key] = value
                self.write_scope()
                self.assertNotEqual(self.mode().returncode, 0)
                self.scope["googlePlay"]["wear"][key] = original
        del self.scope["googlePlay"]["phone"]["module"]
        self.write_scope()
        self.assertNotEqual(self.mode().returncode, 0)

    def test_deferred_audit_checks_links_without_qualifying_phone_aab(self) -> None:
        phone = self.android / "app/build/outputs/bundle/playRelease/app-play-release.aab"
        phone.parent.mkdir(parents=True)
        phone.write_bytes(b"phone-only release artifact outside Wear audit")
        self.assert_result(self.run_script("verify-wear-audit-evidence.sh"), True, "completion remains blocked")

    def test_deferred_audit_still_requires_wear_artifact_evidence(self) -> None:
        wear = self.android / "wear/build/outputs/bundle/release/wear-release.aab"
        wear.parent.mkdir(parents=True)
        wear.write_bytes(b"unreviewed Wear artifact")
        self.assert_result(self.run_script("verify-wear-audit-evidence.sh"), False, "Wear current release AAB hash is absent")

    def test_audit_rejects_active_mixed_version_pair(self) -> None:
        self.activate_wear()
        self.assert_result(self.run_script("verify-wear-audit-evidence.sh"), False, "active paired release version names differ")

    def test_active_audit_retains_phone_artifact_proof(self) -> None:
        self.activate_wear(align_versions=True)
        self.assert_result(self.run_script("verify-wear-audit-evidence.sh"), True, "completion remains blocked")
        phone = self.android / "app/build/outputs/bundle/playRelease/app-play-release.aab"
        phone.parent.mkdir(parents=True)
        phone.write_bytes(b"unreviewed paired phone artifact")
        self.assert_result(self.run_script("verify-wear-audit-evidence.sh"), False, "phone current release AAB hash is absent")

    def test_deferred_audit_preserves_not_complete_guard(self) -> None:
        audit = self.android / "docs/features/wear-os-completion-audit.md"
        text = audit.read_text()
        self.assertIn("**NOT COMPLETE.**", text)
        audit.write_text(text.replace("**NOT COMPLETE.**", "**COMPLETE.**"))
        self.assert_result(self.run_script("verify-wear-audit-evidence.sh"), False, "blocked rows exist without NOT COMPLETE decision")

    def test_deferred_apk_keeps_its_packaged_identity_validation(self) -> None:
        self.assert_result(self.run_script("validate-wear-artifact.sh", str(self.apk)), True, "Wear artifact contract valid")
        self.apk.write_text(json.dumps({"code": 1000055, "version": "2.3.3"}))
        self.assert_result(self.run_script("validate-wear-artifact.sh", str(self.apk)), False, "packaged identity")
        for version in ("2.3.2", "2x3x3"):
            with self.subTest(version=version):
                self.apk.write_text(json.dumps({"code": 1000054, "version": version}))
                self.assert_result(self.run_script("validate-wear-artifact.sh", str(self.apk)), False, "packaged identity")

    def test_active_apk_requires_matching_source_versions(self) -> None:
        self.activate_wear()
        self.assert_result(self.run_script("validate-wear-artifact.sh", str(self.apk)), False, "version names differ")
        self.activate_wear(align_versions=True)
        self.assert_result(self.run_script("validate-wear-artifact.sh", str(self.apk)), True, "Wear artifact contract valid")

    def test_deferred_aab_still_requires_a_paired_release(self) -> None:
        phone = self.android / "phone.aab"
        wear = self.android / "wear.aab"
        phone.touch()
        wear.touch()
        self.assert_result(self.run_script("validate-wear-artifact.sh", str(wear), str(phone)), False, "version names differ")

    def test_invalid_deferral_cannot_bypass_audit_or_apk_validation(self) -> None:
        self.scope["googlePlay"]["wear"]["published"] = True
        self.write_scope()
        for script, args in (("verify-wear-audit-evidence.sh", ()),
                             ("validate-wear-artifact.sh", (str(self.apk),))):
            with self.subTest(script=script):
                self.assert_result(self.run_script(script, *args), False, "release-scope.json is invalid")


if __name__ == "__main__":
    unittest.main()
