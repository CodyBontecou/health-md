#!/usr/bin/env python3
"""Focused adversarial tests for Homebrew release helper scripts."""

from __future__ import annotations

import hashlib
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent
VERIFY = SCRIPTS / "verify-sealed-homebrew-formula.sh"
FRESHNESS = SCRIPTS / "check-homebrew-formula-freshness.py"
TAG = "healthmd-cli/v0.1.0"
IDENTITY = (
    "https://github.com/CodyBontecou/health-md/.github/workflows/"
    "cli-release.yml@refs/tags/healthmd-cli/v0.1.0"
)


class HomebrewReleaseScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "output" / "healthmd.rb"
        self.formula = self.artifacts / "healthmd.rb"
        self.write_formula(self.formula, "0.1.0")
        self.write_manifest()
        (self.artifacts / "sha256.sum.sigstore.json").write_text("{}\n")
        cosign = self.bin / "cosign"
        cosign.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "args = sys.argv[1:]\n"
            "assert args[0] == 'verify-blob', args\n"
            f"assert args[args.index('--certificate-identity') + 1] == {IDENTITY!r}, args\n"
            "assert args[args.index('--certificate-oidc-issuer') + 1] == "
            "'https://token.actions.githubusercontent.com', args\n"
            "raise SystemExit(1 if os.environ.get('FAKE_COSIGN_FAIL') else 0)\n"
        )
        cosign.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            {
                "PATH": f"{self.bin}{os.pathsep}{self.env['PATH']}",
                "GITHUB_SERVER_URL": "https://github.com",
                "GITHUB_REPOSITORY": "CodyBontecou/health-md",
                "GITHUB_REF": "refs/tags/healthmd-cli/v0.1.0",
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def write_formula(
        path: pathlib.Path, version: str, *, latest: bool = False, marker: str = ""
    ) -> None:
        if latest:
            url = (
                "https://github.com/CodyBontecou/health-md/releases/latest/download/"
                "healthmd-cli-aarch64-apple-darwin.tar.xz"
            )
        else:
            url = (
                "https://github.com/CodyBontecou/health-md/releases/download/"
                f"healthmd-cli/v{version}/healthmd-cli-aarch64-apple-darwin.tar.xz"
            )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "class Healthmd < Formula\n"
            f"  version \"{version}\"\n"
            f"  url \"{url}\"\n"
            f"  # {marker}\n"
            "end\n",
            encoding="utf-8",
        )

    def write_manifest(self, *, digest: str | None = None) -> None:
        if digest is None:
            digest = hashlib.sha256(self.formula.read_bytes()).hexdigest()
        (self.artifacts / "sha256.sum").write_text(
            f"{digest}  healthmd.rb\n", encoding="utf-8"
        )

    def run_verify(
        self, *, tag: str = TAG, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(VERIFY), str(self.artifacts), tag, str(self.output)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env or self.env,
            check=False,
        )

    def run_freshness(
        self, candidate_version: str, current: pathlib.Path, candidate: pathlib.Path
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                str(FRESHNESS),
                candidate_version,
                str(current),
                str(candidate),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_sealed_formula_verification_copies_exact_bytes(self) -> None:
        result = self.run_verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), self.formula.read_bytes())

    def test_sealed_formula_rejects_duplicate_artifact(self) -> None:
        self.write_formula(self.artifacts / "nested" / "healthmd.rb", "0.1.0")
        result = self.run_verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one healthmd.rb", result.stderr)

    def test_sealed_formula_rejects_digest_mismatch(self) -> None:
        self.write_manifest(digest="0" * 64)
        result = self.run_verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("digest differs", result.stderr)

    def test_sealed_formula_rejects_latest_url_and_malformed_tag(self) -> None:
        self.write_formula(self.formula, "0.1.0", latest=True)
        self.write_manifest()
        latest = self.run_verify()
        self.assertNotEqual(latest.returncode, 0)
        self.assertIn("must not use", latest.stderr)
        malformed = self.run_verify(tag="v0.1.0")
        self.assertNotEqual(malformed.returncode, 0)
        self.assertIn("invalid", malformed.stderr)

    def test_sealed_formula_rejects_symlink_output_and_cosign_failure(self) -> None:
        self.output.parent.mkdir(parents=True)
        target = self.root / "outside.rb"
        target.write_text("unchanged\n")
        self.output.symlink_to(target)
        symlinked = self.run_verify()
        self.assertNotEqual(symlinked.returncode, 0)
        self.assertEqual(target.read_text(), "unchanged\n")
        self.output.unlink()
        failing_env = self.env.copy()
        failing_env["FAKE_COSIGN_FAIL"] = "1"
        failed_cosign = self.run_verify(env=failing_env)
        self.assertNotEqual(failed_cosign.returncode, 0)
        wrong_identity_env = self.env.copy()
        wrong_identity_env["GITHUB_REPOSITORY"] = "CodyBontecou/not-health-md"
        wrong_identity = self.run_verify(env=wrong_identity_env)
        self.assertNotEqual(wrong_identity.returncode, 0)

    def test_freshness_allows_first_newer_and_identical_release(self) -> None:
        current = self.root / "tap" / "healthmd.rb"
        candidate = self.root / "candidate.rb"
        self.write_formula(candidate, "0.1.0")
        first = self.run_freshness("0.1.0", current, candidate)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.write_formula(current, "0.0.9")
        newer = self.run_freshness("0.1.0", current, candidate)
        self.assertEqual(newer.returncode, 0, newer.stderr)
        current.write_bytes(candidate.read_bytes())
        identical = self.run_freshness("0.1.0", current, candidate)
        self.assertEqual(identical.returncode, 0, identical.stderr)

    def test_freshness_rejects_rollback_and_same_version_rewrite(self) -> None:
        current = self.root / "tap" / "healthmd.rb"
        candidate = self.root / "candidate.rb"
        self.write_formula(current, "0.2.0")
        self.write_formula(candidate, "0.1.0")
        rollback = self.run_freshness("0.1.0", current, candidate)
        self.assertNotEqual(rollback.returncode, 0)
        self.assertIn("rollback", rollback.stderr)
        self.write_formula(current, "0.1.0", marker="published")
        rewrite = self.run_freshness("0.1.0", current, candidate)
        self.assertNotEqual(rewrite.returncode, 0)
        self.assertIn("immutable", rewrite.stderr)

    def test_freshness_rejects_prerelease_until_policy_supports_it(self) -> None:
        candidate = self.root / "candidate.rb"
        self.write_formula(candidate, "0.1.0-alpha.1")
        result = self.run_freshness(
            "0.1.0-alpha.1", self.root / "missing.rb", candidate
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a stable SemVer", result.stderr)


if __name__ == "__main__":
    unittest.main()
