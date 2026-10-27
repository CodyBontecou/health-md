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
                examples = re.findall(
                    r"(?:healthmd ([a-z-]+) )?--arguments '([^'\n]+)'", text
                )
                self.assertTrue(examples, "retain a typed execution example")
                dated_examples = 0
                for command, raw in examples:
                    arguments = json.loads(raw)
                    if command == "cancel-execution":
                        self.assertEqual(arguments, {"job_id": "JOB_UUID"})
                        continue
                    dated_examples += 1
                    dates = arguments["dates"]
                    self.assertEqual(set(dates), {"type", "range"})
                    self.assertEqual(dates["type"], "exact")
                    self.assertEqual(set(dates["range"]), {"start_date", "end_date"})
                    start = date.fromisoformat(dates["range"]["start_date"])
                    end = date.fromisoformat(dates["range"]["end_date"])
                    self.assertGreaterEqual(end, start)
                    self.assertLessEqual((end - start).days + 1, 7)
                self.assertGreater(dated_examples, 0, "retain a bounded typed query example")
                self.assertIn("illustrative", text)


class CanonicalCliDocumentationTests(unittest.TestCase):
    """The root map locates owners; canonical guides retain public boundary checks."""

    ROOT = MODULE_PATH.resolve().parents[3]

    def test_portable_catalog_counts_do_not_promote_the_bundled_or_public_release(self) -> None:
        inventory = (self.ROOT / "docs/features/feature-inventory.md").read_text(encoding="utf-8")
        self.assertIn("../../apps/cli/README.md", inventory)
        self.assertIn("../../apps/cli/docs/architecture.md", inventory)
        readiness = (self.ROOT / "apps/cli/docs/production-readiness.md").read_text(encoding="utf-8")
        catalog = json.loads(
            (self.ROOT / "apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json")
            .read_text(encoding="utf-8")
        )
        self.assertEqual(len(catalog), 26)
        self.assertIn(f"Current development source exposes {len(catalog)}", readiness)
        self.assertIn("Published alpha.6 preview has 19 tools", readiness)
        self.assertIn("Alpha.7 remains an unpublished draft", readiness)
        self.assertIn("the 13-tool read-only catalog", readiness)
        self.assertIn("the 21-tool local stdio MCP catalog", readiness)
        self.assertIn("bundled Mac helper has 21 tools", readiness)
        for name in ("healthmd_export_plan", "healthmd_export_approval",
                     "healthmd_export_execute", "healthmd_export_execution_resume",
                     "healthmd_export_execution_cancel"):
            self.assertIn(name, {tool["name"] for tool in catalog})
            self.assertIn(name, readiness)
        self.assertIn("native extension 4 remains unadvertised", readiness)
        self.assertIn("installed setup", readiness)
        self.assertIn("full feature acceptance remain incomplete", readiness)

    def test_pairing_inventory_distinguishes_universal_and_legacy_selectors(self) -> None:
        compatibility = (self.ROOT / "apps/cli/docs/mobile-compatibility.md").read_text(encoding="utf-8")
        for term in ("selector 3", "20-digit", "Legacy Apple selector 1 (6-digit)",
                     "Android selector 2 (20-digit)"):
            with self.subTest(term=term):
                self.assertIn(term, compatibility)
        self.assertIn("independent from iPhone query v3", compatibility)
        self.assertIn("no permission escalation", compatibility)


class RootFeatureParityDocumentationTests(unittest.TestCase):
    """Static public claims, not native permission, import or transport qualification."""

    ROOT = MODULE_PATH.resolve().parents[3]

    def row(self, path: Path, capability: str) -> list[str]:
        rows = [
            line for line in path.read_text(encoding="utf-8").splitlines()
            if line.startswith(f"| {capability} |")
        ]
        self.assertEqual(len(rows), 1, f"retain one public row for {capability}")
        cells = [cell.strip() for cell in rows[0].strip("|").split("|")]
        self.assertEqual(len(cells), 5)
        return cells

    def test_shared_setup_parity_preserves_planned_and_deferred_status(self) -> None:
        capabilities = json.loads(
            (self.ROOT / "packages/contracts/product-capabilities.json").read_text(encoding="utf-8")
        )
        capability = next(
            row for row in capabilities["capabilities"]
            if row["id"] == "setup.share-portable-configuration"
        )
        self.assertEqual(capability["classification"], "planned")
        for platform in ("apple", "android"):
            self.assertEqual(capability["platforms"][platform]["state"], "planned")
        manifest = json.loads(
            (self.ROOT / "packages/contracts/manifest.json").read_text(encoding="utf-8")
        )
        contract = next(
            row for row in manifest["contracts"]
            if row["id"] == "healthmd.shared_setup" and row["version"] == 2
        )
        self.assertEqual(contract["status"], "deferred")
        cells = self.row(self.ROOT / "docs/features/feature-parity.md", "Share My Setup")
        self.assertEqual(cells[3], capability["classification"])
        for term in ("deferred", "physical-device", "accessibility", "v2", "v1"):
            with self.subTest(term=term):
                self.assertIn(term, cells[4])
        pages = sorted(
            (self.ROOT / "apps/website/docs-src/src/content/docs")
            .glob("**/guides/platform-features.md")
        )
        self.assertEqual(len(pages), 10)
        for path in pages:
            with self.subTest(page=path.relative_to(self.ROOT)):
                rows = [line for line in path.read_text(encoding="utf-8").splitlines()
                        if line.startswith("| Share My Setup")]
                self.assertEqual(len(rows), 1)
                website_cells = [cell.strip() for cell in rows[0].strip("|").split("|")]
                self.assertEqual(len(website_cells), 5)
                self.assertTrue(all(cell.startswith("△") for cell in website_cells[1:4]))

    def test_raw_ndjson_claims_do_not_conflate_iphone_jsonl_extraction(self) -> None:
        with self.subTest(document="parity"):
            cells = self.row(self.ROOT / "docs/features/feature-parity.md", "NDJSON raw output")
            self.assertEqual(cells[3], "android_only")
            self.assertNotIn("--raw-format", cells[1])
            self.assertIn("export --raw", cells[1])
            self.assertIn("extract --format jsonl", cells[1])
            self.assertIn("provider-native", cells[4])
            self.assertIn("not iPhone", cells[4])
        with self.subTest(document="canonical CLI guide"):
            guide = (self.ROOT / "apps/cli/README.md").read_text(encoding="utf-8")
            self.assertIn("Android provider-native JSON/NDJSON raw export", guide)
            self.assertIn("iPhone `export --raw` emits canonical `healthmd.health_data` JSON", guide)
            self.assertIn("`extract --format jsonl` is a separate canonical projection", guide)
            self.assertIn("not the Android provider-native", guide)
        pages = sorted(
            (self.ROOT / "apps/website/docs-src/src/content/docs")
            .glob("**/guides/platform-features.md")
        )
        self.assertEqual(len(pages), 10)
        for path in pages:
            with self.subTest(page=path.relative_to(self.ROOT)):
                rows = [line for line in path.read_text(encoding="utf-8").splitlines()
                        if line.startswith("| ") and "NDJSON" in line]
                self.assertEqual(len(rows), 1)
                cells = [cell.strip() for cell in rows[0].strip("|").split("|")]
                self.assertEqual(len(cells), 5)
                self.assertEqual(cells[1:3], ["—", "—"])
                self.assertTrue(cells[3].startswith("✓"))


class NativeDirectDocumentationTests(unittest.TestCase):
    """Static native-page guidance, not provider, permission or lifecycle execution."""

    ROOT = MODULE_PATH.resolve().parents[3]
    APPLE = ROOT / "apps/apple/docs/features/cli-direct-iphone.md"
    ANDROID = ROOT / "apps/android/docs/features/direct-cli.md"

    def test_iphone_history_example_matches_current_build_limits(self) -> None:
        text = self.APPLE.read_text(encoding="utf-8")
        self.assertIn("## Current build and history scope", text)
        for term in ("pinned SDK", "api_unavailable", "unknown", "denied-versus-empty",
                     "explicit date ranges", "type scope, not date scope", "OS upgrade alone"):
            with self.subTest(term=term):
                self.assertIn(term, text)
        commands = [line for line in text.splitlines()
                    if line.startswith("healthmd export ") and "--full-corpus" in line]
        self.assertEqual(len(commands), 1)
        command = commands[0]
        self.assertNotIn("--all", command.split())
        start = re.search(r"--from (\d{4}-\d{2}-\d{2})\b", command)
        end = re.search(r"--to (\d{4}-\d{2}-\d{2})\b", command)
        self.assertIsNotNone(start)
        self.assertIsNotNone(end)
        days = (date.fromisoformat(end.group(1)) - date.fromisoformat(start.group(1))).days + 1
        self.assertGreaterEqual(days, 1)
        self.assertLessEqual(days, 7)
        self.assertIn("Source dates in these examples are illustrative", text)
        self.assertIn("healthkit-permissions.md", text)

    def test_android_lifecycle_and_native_admission_are_not_pairing_authority(self) -> None:
        text = self.ANDROID.read_text(encoding="utf-8")
        self.assertIn("## Session lifecycle and native admission", text)
        for term in ("user-started foreground service", "ordinary screen locking",
                     "first unlock after reboot", "first permission grant", "boundary day",
                     "historical-read permission", "app-level export entitlement/quota",
                     "pairing does not reset", "Play and F-Droid", "wait-only", "force-stop"):
            with self.subTest(term=term):
                self.assertIn(term, text)
        locked = [line for line in text.splitlines() if line.startswith("| Device locked error |")]
        quota = [line for line in text.splitlines() if line.startswith("| Quota exhausted |")]
        self.assertEqual(len(locked), 1)
        self.assertEqual(len(quota), 1)
        self.assertIn("first unlock", locked[0])
        self.assertNotIn("Phone locked mid-session", locked[0])
        self.assertIn("app-level", quota[0])
        self.assertNotIn("re-pair", quota[0])
        self.assertNotIn("Transfer quota for the pairing", quota[0])

    def test_native_pages_do_not_promote_development_bridge_to_installed_support(self) -> None:
        for path in (self.APPLE, self.ANDROID):
            with self.subTest(document=path.relative_to(self.ROOT).as_posix()):
                text = path.read_text(encoding="utf-8")
                self.assertIn("## Source and qualification", text)
                for term in ("not installed/release qualification", "alpha.7 preview has 19",
                             "development catalog declares 23", "read-only profile 13",
                             "frozen CLI 1.0 scope 21", "healthmd_export_plan",
                             "healthmd_export_approval", "independently negotiated extension 4",
                             "unwired/unadvertised", "native consent", "bound execution",
                             "host-owned recipes", "exact-build matrix",
                             "production-readiness.md", "mobile-compatibility.md"):
                    self.assertIn(term, text)
        self.assertNotIn("Swift direct client complete", self.APPLE.read_text(encoding="utf-8"))
        self.assertIn("Android typed direct queries and extraction remain planned",
                      self.ANDROID.read_text(encoding="utf-8"))


class ConsumerSkillDocumentationTests(unittest.TestCase):
    """Static agent-facing instructions, not installed commands or permission evidence."""

    ROOT = MODULE_PATH.resolve().parents[3]
    CLI = ROOT / ".agents/skills/healthmd-cli/SKILL.md"
    OPERATOR = ROOT / ".agents/skills/healthmd-cli-operator/SKILL.md"

    def test_consumer_history_requires_build_evidence_and_bounded_corpus_example(self) -> None:
        for path in (self.CLI, self.OPERATOR):
            with self.subTest(skill=path.parent.name):
                text = path.read_text(encoding="utf-8")
                for term in ("api_unavailable", "unknown", "denied-versus-empty",
                             "exact app/build/SDK", "explicit date ranges", "type scope, not date scope"):
                    self.assertIn(term, text)
                self.assertNotIn("Use `--all` only when explicitly requested", text)
                commands = [line for line in text.splitlines()
                            if line.startswith("healthmd export ") and "--full-corpus" in line]
                for command in commands:
                    self.assertNotIn("--all", command.split())
                    start = re.search(r"--from (\d{4}-\d{2}-\d{2})\b", command)
                    end = re.search(r"--to (\d{4}-\d{2}-\d{2})\b", command)
                    self.assertIsNotNone(start)
                    self.assertIsNotNone(end)
                    days = (date.fromisoformat(end.group(1)) - date.fromisoformat(start.group(1))).days + 1
                    self.assertGreaterEqual(days, 1)
                    self.assertLessEqual(days, 7)
        self.assertEqual(len([line for line in self.CLI.read_text().splitlines()
                              if line.startswith("healthmd export ") and "--full-corpus" in line]), 1)

    def test_consumer_gates_development_tools_and_platform_lifecycle(self) -> None:
        text = self.CLI.read_text(encoding="utf-8")
        for term in ("alpha.7 exposes 19", "development catalog has 23", "development-only",
                     "healthmd_export_raw", "healthmd_raw_artifact_read", "healthmd_export_plan",
                     "healthmd_export_approval", "unwired/unadvertised", "host-owned recipes",
                     "first-mobile", "alpha.7's iPhone-only", "user-started foreground service",
                     "ordinary screen locking", "first unlock after reboot", "force-stop",
                     "production-readiness.md"):
            self.assertIn(term, text)
        self.assertNotIn("Android pairing remains an explicit", text)
        self.assertNotIn("foreground Health.md mobile app", text)
        self.assertIn("when the installed catalog includes", text)

    def test_iphone_operator_uses_source_readiness_and_portable_existing_destination(self) -> None:
        text = self.OPERATOR.read_text(encoding="utf-8")
        for term in ("source.platform == ios", "source.connected == true",
                     "source.app_active == true", "source.protected_data_available == true",
                     "source.can_trigger_raw_exports == true", "source.can_trigger_exports == true",
                     "iOS-only compatibility alias", "null for Android", "iPhone-only skill",
                     "macOS, Linux, and Windows", "PRIVATE_HEALTH_DIR", "qualification remains pending"):
            self.assertIn(term, text)
        self.assertNotIn("Windows supports raw and extract.", text)
        self.assertNotIn("`iphone.connected == true`", text)
        self.assertNotIn('mkdir -p "$HOME/Documents/HealthVault"', text)
        self.assertIn("existing user-approved absolute non-symlink destination", text)


class PackagedTestSupportTests(unittest.TestCase):
    def test_cli_adapter_support_is_self_contained_and_matches_client_tracer(self) -> None:
        crates = MODULE_PATH.resolve().parents[1] / "crates"
        client_support = crates / "healthmd-client/tests/support/agent.rs"
        cli_support = crates / "healthmd-cli/src/agent_direct_test_support.rs"
        self.assertEqual(cli_support.read_bytes(), client_support.read_bytes())
        adapter_tests = (crates / "healthmd-cli/src/agent_direct_tests.rs").read_text()
        self.assertIn('#[path = "agent_direct_test_support.rs"]', adapter_tests)
        self.assertNotIn('../../healthmd-client/tests/support/agent.rs', adapter_tests)


class DevelopmentQASkillDocumentationTests(unittest.TestCase):
    """Static skill gate/scope instructions, not compiled or physical qualification."""

    ROOT = MODULE_PATH.resolve().parents[3]
    SKILLS = (ROOT / ".agents/skills/healthmd-cli-development/SKILL.md",
              ROOT / ".agents/skills/healthmd-cli-qa/SKILL.md")

    def test_skill_core_msrv_gate_excludes_tooling_and_keeps_cli_workspace(self) -> None:
        core = self.ROOT / "packages/healthmd-core-rust"
        self.assertIn('channel = "1.88.0"', (core / "rust-toolchain.toml").read_text())
        self.assertIn('rust-version = "1.88"', (core / "xtask/Cargo.toml").read_text())
        runtime = ("rustup run 1.85.0 cargo check -p healthmd-core -p healthmd-protocol "
                   "-p healthmd-core-uniffi --all-features --locked")
        self.assertIn(runtime, (core / "AGENTS.md").read_text())
        for path in self.SKILLS:
            with self.subTest(skill=path.parent.name):
                text = path.read_text(encoding="utf-8")
                blocks = re.findall(r"```bash\n(.*?)\n```", text, re.DOTALL)
                core_block = next(block for block in blocks if "cd packages/healthmd-core-rust" in block)
                cli_block = next(block for block in blocks if "cd apps/cli" in block)
                self.assertIn(runtime, core_block)
                self.assertNotIn("rustup run 1.85.0 cargo check --workspace", core_block)
                self.assertIn("rustup run 1.85.0 cargo check --workspace --all-features --locked", cli_block)
                self.assertIn("whole-core workspace/tooling uses Rust 1.88", text)
                self.assertIn("runtime-only Rust 1.85", text)
                self.assertIn("independent lockfiles", text)

    def test_qa_extraction_expectation_preserves_current_and_historical_profiles(self) -> None:
        native = (self.ROOT / "apps/apple/HealthMd/Shared/Export/HealthMetricsDictionary.swift").read_text()
        declaration = re.search(r"enum HealthMdExportSchema\s*\{(.*?)\n\}", native, re.DOTALL)
        self.assertIsNotNone(declaration)
        version = re.search(r"static let version = (\d+)\b", declaration.group(1))
        self.assertIsNotNone(version)
        self.assertEqual(version.group(1), "10")
        text = self.SKILLS[1].read_text(encoding="utf-8")
        extraction = text.split("## Extraction contract\n", 1)[1].split("\n## Live prerequisites", 1)[0]
        self.assertNotIn("Summary returns schema-v7 documents", extraction)
        self.assertIn(f"Apple v{version.group(1)}", extraction)
        for term in ("historical v5/v6/v7", "v8 grammar", "Daily v9 remains reserved",
                     "raw_capture_status: not_requested", "no hidden archive",
                     "Android source-shaped extraction remains planned", "android_source_projection_v1",
                     "android_daily_records_v1", "reserved", "frozen-v4/analytical-v5"):
            self.assertIn(term, extraction)
        self.assertIn("apple/docs/features/export-schema.md", extraction)

    def test_skill_qa_matrix_is_source_specific_and_authorization_gated(self) -> None:
        for path in self.SKILLS:
            with self.subTest(skill=path.parent.name):
                text = path.read_text(encoding="utf-8")
                self.assertIn("## Current source and qualification", text)
                for term in ("Apple application 1", "Android application 2", "iPhone query 3",
                             "independent agent extension 4", "unwired/unadvertised",
                             "user-started foreground service", "ordinary screen locking",
                             "first unlock after reboot", "force-stop", "native consent",
                             "bound execution", "not installed/release qualification",
                             "mobile-compatibility.md", "production-readiness.md"):
                    self.assertIn(term, text)
        with self.subTest(surface="QA authorization and report"):
            text = self.SKILLS[1].read_text(encoding="utf-8")
            self.assertIn("separately authorized", text)
            self.assertIn("No health payloads, owner dates, private paths", text)
            self.assertNotIn("Record only counts, dates, statuses, diagnostics, and digests.", text)
            self.assertNotIn("counts, paths, receipts, artifact digests only", text)
            self.assertIn("not run", text)
            self.assertIn("Android before first unlock / absent or force-stopped service", text)
            self.assertIn("Android later screen lock with active service", text)


if __name__ == "__main__":
    unittest.main()
