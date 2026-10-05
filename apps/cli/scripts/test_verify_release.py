#!/usr/bin/env python3
"""Regression tests for CLI release-channel and mobile-qualification policy."""

from __future__ import annotations

import importlib.util
import json
import re
import tempfile
import unittest
from datetime import date
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
                    "iOS 3.3.0 (build 202609032317)",
                    "iPhone / iOS 18",
                ),
                (
                    verify_release.MOBILE_QUALIFICATION_LABELS[1],
                    "iOS 3.3.0 (build 202609032317)",
                    "iPhone / iOS 18",
                ),
                (
                    verify_release.MOBILE_QUALIFICATION_LABELS[2],
                    "Android 1.8.2 (versionCode 31)",
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


class HistoryReadinessDocumentationTests(unittest.TestCase):
    """Static consumer-copy checks, not native permission or runtime qualification."""

    DOCS = MODULE_PATH.parents[1] / "docs"

    def test_readiness_does_not_promote_os_hint_to_history_support(self) -> None:
        text = (self.DOCS / "production-readiness.md").read_text(encoding="utf-8")
        self.assertNotIn("history-authorization evidence on OS 27+", text)
        self.assertNotIn("OS 27 limited history", text)
        self.assertIn("peer-supplied history-authorization metadata", text)
        self.assertIn("current-source-history-limitations", text)

    def test_history_guidance_distinguishes_build_support_and_android(self) -> None:
        text = (self.DOCS / "mobile-compatibility.md").read_text(encoding="utf-8")
        self.assertIn("## Current source history limitations", text)
        for term in (
            "pinned SDK", "api_unavailable", "unknown", "explicit date ranges",
            "Health Connect", "historical-read", "An OS upgrade alone",
        ):
            with self.subTest(term=term):
                self.assertIn(term, text)
        self.assertIn("not proof of denial or no data", text)
        native_link = "../../apple/docs/features/healthkit-permissions.md"
        self.assertIn(native_link, text)
        self.assertTrue((self.DOCS / native_link).is_file())

    def test_execution_examples_use_bounded_exact_dates_not_full_history(self) -> None:
        for filename in ("qa.md", "command-guidance.md"):
            with self.subTest(document=filename):
                text = (self.DOCS / filename).read_text(encoding="utf-8")
                examples = re.findall(r"--arguments '([^'\n]+)'", text)
                self.assertTrue(examples, "retain a typed execution example")
                for raw in examples:
                    arguments = json.loads(raw)
                    dates = arguments["dates"]
                    self.assertEqual(set(dates), {"type", "range"})
                    self.assertEqual(dates["type"], "exact")
                    self.assertEqual(set(dates["range"]), {"start_date", "end_date"})
                    start = date.fromisoformat(dates["range"]["start_date"])
                    end = date.fromisoformat(dates["range"]["end_date"])
                    self.assertGreaterEqual(end, start)
                    self.assertLessEqual((end - start).days + 1, 7)
                self.assertIn("illustrative", text)


class RootFeatureInventoryDocumentationTests(unittest.TestCase):
    """Static public inventory accounting, not installed capability qualification."""

    ROOT = MODULE_PATH.resolve().parents[3]

    def test_portable_catalog_counts_do_not_promote_the_bundled_or_public_release(self) -> None:
        inventory = (self.ROOT / "docs/features/feature-inventory.md").read_text(encoding="utf-8")
        catalog = json.loads(
            (self.ROOT / "apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json")
            .read_text(encoding="utf-8")
        )
        self.assertEqual(len(catalog), 23)
        serve = next(line for line in inventory.splitlines() if line.startswith("| `healthmd mcp serve` /"))
        self.assertIn(f"current development source has {len(catalog)}", serve)
        self.assertIn("preview has 19 tools", serve)
        self.assertIn("13 tools", serve)
        self.assertIn("frozen CLI 1.0 scope remains 21", serve)
        row = next(line for line in inventory.splitlines() if line.startswith("| MCP tool catalog"))
        self.assertIn("portable development: 23; bundled Mac: 21", row)
        for name in ("healthmd_export_plan", "healthmd_export_approval"):
            self.assertIn(name, {tool["name"] for tool in catalog})
            self.assertIn(name, row)
        self.assertIn("unwired/unadvertised", row)
        self.assertIn("no bound execution", row)

    def test_pairing_inventory_distinguishes_universal_and_legacy_selectors(self) -> None:
        inventory = (self.ROOT / "docs/features/feature-inventory.md").read_text(encoding="utf-8")
        row = next(line for line in inventory.splitlines() if line.startswith("| `healthmd direct pair` |"))
        for term in ("selector 3", "20-digit", "legacy Apple selector 1", "Android selector 2"):
            with self.subTest(term=term):
                self.assertIn(term, row)
        self.assertIn("not query v3", row)
        self.assertIn("no permission", row)


if __name__ == "__main__":
    unittest.main()
