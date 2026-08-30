#!/usr/bin/env python3
"""Regression tests for CLI release-channel and mobile-qualification policy."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify-release.py")
SPEC = importlib.util.spec_from_file_location("verify_release", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {MODULE_PATH}")
verify_release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify_release)


class ReleaseTagTests(unittest.TestCase):
    def test_semver_prerelease_is_distinct_from_stable_and_build_metadata(self) -> None:
        preview = verify_release.TAG_RE.fullmatch("healthmd-cli/v0.1.0-alpha.2")
        stable = verify_release.TAG_RE.fullmatch("healthmd-cli/v0.1.0")
        stable_build = verify_release.TAG_RE.fullmatch("healthmd-cli/v0.1.0+build-1")

        self.assertIsNotNone(preview)
        self.assertEqual(preview.group("prerelease"), "-alpha.2")
        self.assertIsNotNone(stable)
        self.assertIsNone(stable.group("prerelease"))
        self.assertIsNotNone(stable_build)
        self.assertIsNone(stable_build.group("prerelease"))

    def test_non_semver_tags_are_rejected(self) -> None:
        for tag in (
            "healthmd-cli/v01.2.3",
            "healthmd-cli/v1.2.3-01",
            "healthmd-cli/v1.2.3-alpha.01",
            "healthmd-cli/v1.2.3-",
        ):
            with self.subTest(tag=tag):
                self.assertIsNone(verify_release.TAG_RE.fullmatch(tag))


class MobileQualificationTests(unittest.TestCase):
    def write_ledger(self, results: str | dict[str, str]) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "mobile-compatibility.md"
        rows = "\n".join(
            f"| {label} | protocol | floor | "
            f"{results[label] if isinstance(results, dict) else results} |"
            for label in verify_release.MOBILE_QUALIFICATION_LABELS
        )
        path.write_text(rows, encoding="utf-8")
        return path

    def test_pending_rows_are_allowed_only_for_preview_policy(self) -> None:
        path = self.write_ledger(verify_release.PENDING_MOBILE_QUALIFICATION)
        verify_release.validate_mobile_qualification(path, require_qualified=False)
        with self.assertRaisesRegex(SystemExit, "mobile compatibility remains pending"):
            verify_release.validate_mobile_qualification(
                path,
                require_qualified=True,
                expected_source_commit="a" * 40,
            )

    def test_qualified_rows_are_bound_to_the_release_candidate(self) -> None:
        source_commit = "a" * 40
        results = {
            label: (
                f"**Qualified:** mobile_build={platform}; "
                f"source_commit={source_commit}; device_os={device}; "
                f"lan=pass; tailscale=pass; evidence_sha256={'b' * 64}"
            )
            for label, platform, device in (
                (
                    verify_release.MOBILE_QUALIFICATION_LABELS[0],
                    "iOS 3.2.1 (build 202608300209)",
                    "iPhone / iOS 18",
                ),
                (
                    verify_release.MOBILE_QUALIFICATION_LABELS[1],
                    "iOS 3.2.1 (build 202608300209)",
                    "iPhone / iOS 18",
                ),
                (
                    verify_release.MOBILE_QUALIFICATION_LABELS[2],
                    "Android 1.8.1 (versionCode 30)",
                    "Pixel / Android 16",
                ),
            )
        }
        path = self.write_ledger(results)
        verify_release.validate_mobile_qualification(
            path,
            require_qualified=True,
            expected_source_commit=source_commit,
        )
        with self.assertRaisesRegex(SystemExit, "does not match release candidate"):
            verify_release.validate_mobile_qualification(
                path,
                require_qualified=True,
                expected_source_commit="c" * 40,
            )

    def test_malformed_rows_fail_for_preview_and_stable_policy(self) -> None:
        path = self.write_ledger("**Pending someday**")
        for require_qualified in (False, True):
            with self.assertRaisesRegex(SystemExit, "invalid qualified record"):
                verify_release.validate_mobile_qualification(
                    path,
                    require_qualified=require_qualified,
                    expected_source_commit="a" * 40 if require_qualified else None,
                )

    def test_structurally_malformed_duplicate_required_row_fails(self) -> None:
        path = self.write_ledger(verify_release.PENDING_MOBILE_QUALIFICATION)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(
                "\n| "
                f"{verify_release.MOBILE_QUALIFICATION_LABELS[0]}"
                " | malformed |\n"
            )
        with self.assertRaisesRegex(SystemExit, "malformed mobile compatibility row"):
            verify_release.validate_mobile_qualification(path, require_qualified=False)


if __name__ == "__main__":
    unittest.main()
