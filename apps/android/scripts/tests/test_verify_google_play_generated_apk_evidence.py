#!/usr/bin/env python3
"""SDK-free synthetic receipt regressions; mocks never attest a real Play artifact."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[2]
SCRIPT = ANDROID / "scripts/verify-google-play-generated-apk-evidence.sh"
SIGNER = "a" * 64


class GeneratedApkReceiptTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.tools = self.root / "tools"
        self.tools.mkdir()
        for command, body in (
            ("aapt", "print(\"package: name='%s' versionCode='%s' versionName='%s'\" % (apk['package'], apk['code'], apk['version']))"),
            ("apksigner", "print('Signer #1 certificate SHA-256 digest: ' + apk['signer'])"),
        ):
            path = self.tools / command
            path.write_text("#!/usr/bin/env python3\nimport json, sys\napk=json.load(open(sys.argv[-1]))\n" + body + "\n")
            path.chmod(0o755)
        for label, code in (("phone", 55), ("wear", 1000054)):
            (self.evidence / f"{label}-generated.apk").write_text(json.dumps({
                "package": "com.healthmd.android", "code": code, "version": "2.3.4", "signer": SIGNER,
            }))
            (self.evidence / f"{label}-generated-apks.json").write_text(json.dumps({"generatedApks": [{
                "certificateSha256Hash": SIGNER,
                "generatedSplitApks": [{"downloadId": f"{label}-id", "moduleName": "base", "splitId": ""}],
            }]}))
        self.receipt = {"schemaVersion": 1, "package": "com.healthmd.android",
                        "expectedPlayAppSigningCertSha256": SIGNER}
        for label, code in (("phone", 55), ("wear", 1000054)):
            self.receipt[label] = {"versionCode": code, "versionName": "2.3.4",
                "apkSha256": self.digest(f"{label}-generated.apk"), "certSha256": SIGNER,
                "downloadId": f"{label}-id"}
        self.env = dict(os.environ, APKSIGNER=str(self.tools / "apksigner"), AAPT=str(self.tools / "aapt"),
                        EXPECTED_PHONE_VERSION_CODE="55", EXPECTED_WEAR_VERSION_CODE="1000054",
                        EXPECTED_VERSION_NAME="2.3.4", EXPECTED_PLAY_APP_SIGNING_CERT_SHA256=SIGNER)
        self.save()

    def digest(self, name: str) -> str:
        return hashlib.sha256((self.evidence / name).read_bytes()).hexdigest()

    def save(self) -> None:
        (self.evidence / "play-app-signing.json").write_text(json.dumps(self.receipt))
        names = ("play-app-signing.json", "phone-generated.apk", "wear-generated.apk",
                 "phone-generated-apks.json", "wear-generated-apks.json")
        (self.evidence / "play-app-signing-SHA256SUMS").write_text(
            "".join(f"{self.digest(name)}  {name}\n" for name in names))

    def run_verifier(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(SCRIPT), str(self.evidence / "play-app-signing.json")],
                              env=self.env, text=True, capture_output=True)

    def assert_rejected(self, message: str) -> None:
        result = self.run_verifier()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)

    def edit_json(self, name: str, transform) -> None:
        path = self.evidence / name
        data = json.loads(path.read_text())
        transform(data)
        path.write_text(json.dumps(data))
        self.save()

    def test_exact_pair_passes(self) -> None:
        result = self.run_verifier()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_receipt_code_mismatch_rejected(self) -> None:
        self.receipt["phone"]["versionCode"] = 56
        self.save()
        self.assert_rejected("phone receipt versionCode differs")

    def test_receipt_name_mismatch_rejected(self) -> None:
        self.receipt["wear"]["versionName"] = "invalid"
        self.save()
        self.assert_rejected("wear receipt versionName differs")

    def test_apk_tampering_rejected(self) -> None:
        path = self.evidence / "phone-generated.apk"
        path.write_bytes(path.read_bytes() + b" ")
        self.save()
        self.assert_rejected("phone APK digest differs from receipt")

    def test_inventory_signer_mismatch_rejected(self) -> None:
        self.edit_json("wear-generated-apks.json", lambda data: data["generatedApks"][0].update(certificateSha256Hash="f" * 64))
        self.assert_rejected("wear raw inventory lacks authorized signing-key group")

    def test_download_id_mismatch_rejected(self) -> None:
        self.receipt["wear"]["downloadId"] = "other"
        self.save()
        self.assert_rejected("wear receipt downloadId absent")

    def test_universal_apk_cannot_replace_base_master_evidence(self) -> None:
        def transform(data):
            group = data["generatedApks"][0]
            del group["generatedSplitApks"]
            group["generatedUniversalApk"] = {"downloadId": "wear-id"}
        self.edit_json("wear-generated-apks.json", transform)
        self.assert_rejected("wear receipt downloadId absent")

    def test_packaged_code_mismatch_rejected_after_receipt_matches_expectation(self) -> None:
        self.receipt["phone"]["versionCode"] = 56
        self.env["EXPECTED_PHONE_VERSION_CODE"] = "56"
        self.save()
        self.assert_rejected("phone package/version differs")

    def test_independent_signer_mismatch_rejected(self) -> None:
        self.env["EXPECTED_PLAY_APP_SIGNING_CERT_SHA256"] = "f" * 64
        self.assert_rejected("receipt signer differs from independently supplied signer")

    def test_mixed_actual_versions_cannot_qualify_even_with_matching_receipt(self) -> None:
        self.edit_json("wear-generated.apk", lambda data: data.update(version="2.3.3"))
        self.receipt["wear"]["apkSha256"] = self.digest("wear-generated.apk")
        self.save()
        self.assert_rejected("wear package/version differs")

    def test_packaged_signer_mismatch_rejected(self) -> None:
        self.edit_json("wear-generated.apk", lambda data: data.update(signer="f" * 64))
        self.receipt["wear"]["apkSha256"] = self.digest("wear-generated.apk")
        self.save()
        self.assert_rejected("wear signer differs from independently authorized identity")

    def test_missing_independent_signer_rejected(self) -> None:
        self.env.pop("EXPECTED_PLAY_APP_SIGNING_CERT_SHA256")
        self.assert_rejected("independently supplied EXPECTED_PLAY_APP_SIGNING_CERT_SHA256 is required")

    def test_checksum_tampering_rejected(self) -> None:
        path = self.evidence / "phone-generated.apk"
        path.write_bytes(path.read_bytes() + b"tamper")
        self.assert_rejected("checksum coverage or content mismatch")

    def test_deferred_real_apk_ci_harness_requires_mixed_pair_rejection(self) -> None:
        # Synthetic APK inspectors exercise the CI harness while leaving the production verifier's
        # single paired version expectation unchanged. They cannot produce Play release evidence.
        android = self.root / "repo/apps/android"
        scripts = android / "scripts"
        (scripts / "tests").mkdir(parents=True)
        for name in ("android-release-scope.sh", "verify-google-play-generated-apk-evidence.sh"):
            shutil.copyfile(ANDROID / "scripts" / name, scripts / name)
            (scripts / name).chmod(0o755)
        harness = scripts / "tests/test_verify_google_play_generated_apk_evidence.sh"
        shutil.copyfile(ANDROID / "scripts/tests" / harness.name, harness)
        phone = android / "app/build/outputs/apk/play/debug/app-play-debug.apk"
        wear = android / "wear/build/outputs/apk/debug/wear-debug.apk"
        phone.parent.mkdir(parents=True)
        wear.parent.mkdir(parents=True)
        shutil.copyfile(self.evidence / "phone-generated.apk", phone)
        data = json.loads((self.evidence / "wear-generated.apk").read_text())
        data["version"] = "2.3.3"
        wear.write_text(json.dumps(data))
        scope = json.loads((ANDROID / "release-scope.json").read_text())
        scope["releaseVersionName"] = "2.3.4"
        scope["googlePlay"]["phone"]["versionCode"] = 55
        (android / "release-scope.json").write_text(json.dumps(scope))
        result = subprocess.run(["bash", str(harness)], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Deferred Wear development APK pair rejected as production evidence", result.stdout)
        scope["googlePlay"]["wear"].update(status="release_candidate", runtimeAdvertisedByPhone=True)
        (android / "release-scope.json").write_text(json.dumps(scope))
        result = subprocess.run(["bash", str(harness)], env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Active paired phone and Wear APK version names differ", result.stderr)


if __name__ == "__main__":
    unittest.main()
