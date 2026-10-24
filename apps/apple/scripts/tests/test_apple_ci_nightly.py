"""Execute nightly shell policy with fake tools; Apple CI discovers this file."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[4]
NIGHTLY = REPO / ".github/workflows/apple-nightly.yml"
CI = REPO / ".github/workflows/apple-ci.yml"


def job(text, identifier):
    match = re.search(rf"^  {re.escape(identifier)}:\n(.*?)(?=^  [\w-]+:\n|\Z)",
                      text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"missing job {identifier}")
    return match.group(1)


def steps(block):
    return re.split(r"^      - ", block, flags=re.MULTILINE)[1:]


def step(block, name):
    matches = [entry for entry in steps(block) if entry.startswith(f"name: {name}\n")]
    if len(matches) != 1:
        raise AssertionError(f"expected one step named {name}, found {len(matches)}")
    return matches[0]


def command(entry):
    body = entry.split("        run: |\n", 1)[1]
    return "\n".join(line[10:] for line in body.splitlines() if line.startswith("          "))


class NightlyWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = NIGHTLY.read_text()
        self.ios = job(self.text, "extended-ios")
        self.mac = job(self.text, "extended-macos")
        self.prepare = job(self.text, "prepare-ui")
        self.core = job(self.text, "prepare-shared-core")

    def test_both_nightly_jobs_use_the_same_hosted_toolchain_as_apple_ci(self):
        ci_mac = job(CI.read_text(), "test-macos")
        hosted = re.search(r"runs-on: (\S+)", ci_mac).group(1)
        self.assertEqual(hosted, "xcode-27")
        for block in [self.ios, self.mac, self.prepare]:
            self.assertIn(f"runs-on: {hosted}", block)
            self.assertNotIn("self-hosted", block)
            self.assertIn("xcode-version: '27.0'", block)
            self.assertIn("bash scripts/qualify-history-authorization-sdk27.sh", block)

    def test_mac_runs_one_full_coverage_suite_and_keeps_all_diagnostics(self):
        self.assertNotIn("make test-macos", self.mac)
        self.assertEqual(self.mac.count("make coverage"), 1)
        suite = step(self.mac, "Run macOS unit tests with coverage")
        self.assertIn("timeout-minutes: 45", suite)
        self.assertNotIn("continue-on-error", suite)
        makefile = (REPO / "apps/apple/Makefile").read_text()
        coverage = makefile.split("\ncoverage:", 1)[1].split("\ncoverage-report:", 1)[0]
        self.assertIn("-scheme HealthMd-Tests-macOS", coverage)
        self.assertIn("-enableCodeCoverage YES", coverage)
        self.assertNotIn("-only-testing", coverage)
        self.assertNotIn("-skip-testing", coverage)
        for name in ["Coverage summary", "Check coverage threshold", "Check warnings (macOS — strict)",
                     "Upload macOS nightly artifacts"]:
            self.assertIn("if: ${{ !cancelled() }}", step(self.mac, name))
        self.assertIn("scripts/check-coverage.sh build/coverage/HealthMd.xcresult", self.mac)
        self.assertIn("scripts/check-warnings.sh build/logs/build-macos.log", self.mac)
        self.assertIn("apps/apple/build/coverage/HealthMd.xcresult", self.mac)
        self.assertIn("apps/apple/build/logs/build-macos.log", self.mac)
        self.assertIn("retention-days: 30", self.mac)

    def test_shared_core_is_validated_once_and_consumers_require_same_run_source(self):
        self.assertEqual(self.text.count("run: make prepare-healthmd-core-rust"), 1)
        self.assertIn("run: make prepare-healthmd-core-rust", self.core)
        share = step(self.core, "Share validated native core from this run")
        self.assertIn("include-hidden-files: true", share)
        self.assertIn("if-no-files-found: error", share)
        self.assertIn(".nightly-source-sha", share)
        for block in [self.ios, self.mac, self.prepare]:
            self.assertIn("prepare-shared-core", re.search(r"^    needs: (.+)$", block, re.MULTILINE).group(1))
            self.assertNotIn("make prepare-healthmd-core-rust", block)
            download = step(block, "Download validated native core from this run")
            self.assertIn("name: nightly-shared-core", download)
            self.assertNotIn("run-id:", download)
            validate = step(block, "Validate native core source and slices")
            self.assertIn("github.sha", validate)
            self.assertIn(".nightly-source-sha", validate)
            self.assertIn(".healthmd-core-source.sha256", validate)
            self.assertIn("validate-apple-xcframework.sh", validate)
            self.assertLess(block.index(download), block.index(validate))
        self.assertIn("make test-ios CORE_RUST_PREPARE=:", self.ios)
        self.assertIn("make coverage CORE_RUST_PREPARE=:", self.mac)

    def test_unit_simulator_startup_overlaps_build_after_native_validation(self):
        boot = step(self.ios, "Select newest compatible iOS Simulator")
        self.assertIn("apple_nightly_ui.py start-simulator", boot)
        self.assertLess(self.ios.index("Validate native core source and slices"), self.ios.index(boot))
        self.assertLess(self.ios.index(boot), self.ios.index("Run iOS unit tests"))
        self.assertNotIn("bootstatus", boot)

    def test_actual_consumer_rejects_missing_or_wrong_source_before_validation(self):
        sha = "a" * 40
        shell = command(step(self.ios, "Validate native core source and slices"))
        shell = shell.replace("${{ github.sha }}", sha)
        for receipt in (sha, "b" * 40, None):
            with self.subTest(receipt=receipt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                apple = root / "apps/apple"
                artifacts = apple / "Packages/HealthMdCoreRust/Artifacts"
                artifacts.mkdir(parents=True)
                (artifacts / ".healthmd-core-source.sha256").write_text("validated digest")
                if receipt is not None:
                    (artifacts / ".nightly-source-sha").write_text(receipt + "\n")
                validator = root / "packages/healthmd-core-rust/scripts/validate-apple-xcframework.sh"
                validator.parent.mkdir(parents=True)
                validator.write_text("#!/bin/sh\ntouch validated-slices\n")
                validator.chmod(0o755)
                result = subprocess.run(["bash", "-c", shell], cwd=apple, capture_output=True)
                self.assertEqual(result.returncode == 0, receipt == sha)
                self.assertEqual((apple / "validated-slices").exists(), receipt == sha)

    def test_native_cache_reuses_apple_ci_key_but_preparation_still_validates_hits(self):
        prepare = job(CI.read_text(), "prepare-shared-core")
        shared_key = prepare.split("          key: >-\n", 1)[1].split("\n\n", 1)[0]
        for block in [self.core]:
            cached = step(block, "Restore exact-source shared Rust core from Apple CI")
            self.assertIn("uses: actions/cache/restore@v4", cached)
            self.assertNotIn("restore-keys", cached)
            key = cached.split("          key: >-\n", 1)[1].split("\n\n", 1)[0]
            self.assertEqual(" ".join(key.split()), " ".join(shared_key.split()))
            self.assertIn("apps/apple/Packages/HealthMdCoreRust/Artifacts/HealthmdCore.xcframework", cached)
            self.assertIn("apps/apple/Packages/HealthMdCoreRust/Artifacts/.healthmd-core-source.sha256", cached)
            validated = step(block, "Prepare and validate shared Rust core for Apple")
            self.assertNotIn("if:", validated)
            self.assertLess(block.index("uses: actions/cache/restore@v4"),
                            block.index("make prepare-healthmd-core-rust"))

    def test_binding_dependency_cache_never_bypasses_generation_or_validation(self):
        for block in [self.core]:
            compiler = step(block, "Set up pinned Rust compiler for binding verification")
            self.assertIn("uses: dtolnay/rust-toolchain@1.88.0", compiler)
            cache = step(block, "Cache binding compiler dependencies")
            self.assertIn("uses: Swatinem/rust-cache@v2", cache)
            self.assertIn("workspaces: packages/healthmd-core-rust -> target", cache)
            self.assertNotIn("cache-workspace-crates: true", cache)
            self.assertLess(block.index(compiler), block.index(cache))
            validated = step(block, "Prepare and validate shared Rust core for Apple")
            self.assertLess(block.index(cache), block.index(validated))
            self.assertNotIn("if:", validated)
            self.assertIn("run: make prepare-healthmd-core-rust", validated)

    def test_full_ios_unit_and_ui_coverage_and_cancellation_policy_remain(self):
        self.assertIn("make test-ios", self.ios)
        self.assertNotIn("-only-testing", self.ios)
        self.assertNotIn("-skip-testing", self.ios)
        ui = job(self.text, "ui-shards")
        suite = step(ui, "Run and audit assigned UI shard")
        self.assertIn("if: ${{ success() }}", suite)
        self.assertNotIn("continue-on-error", suite)
        self.assertIn("python3 scripts/apple_nightly_ui.py run", suite)
        self.assertIn("cancel-in-progress: true", self.text)
        self.assertIn("cron: '0 4 * * *'", self.text)
        self.assertIn("workflow_dispatch:", self.text)
        self.assertIn("scripts/check-warnings.sh build/logs/build-ios.log", self.ios)

    def test_ui_workers_preserve_failure_and_raw_log_policy(self):
        ui = job(self.text, "ui-shards")
        self.assertIn("fail-fast: false", ui)
        self.assertNotIn("continue-on-error", ui)
        for name in ("Check UI runtime warnings (strict)", "Upload UI shard diagnostics",
                     "Upload UI shard inventory"):
            self.assertIn("if: ${{ !cancelled() }}", step(ui, name))
        self.assertIn(".xcresult", ui)
        self.assertIn("retention-days: 30", ui)
        self.assertIn("if-no-files-found: error", ui)

    def test_ios_native_arch_flags_keep_unfiltered_suite_and_raw_failure_output(self):
        self.assertIn('IOS_TEST_BUILD_FLAGS="ARCHS=$(uname -m) ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"', self.ios)
        for status in (0, 65):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary = root / "bin"
                binary.mkdir()
                xcode = binary / "xcodebuild"
                xcode.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
Path('arguments.json').write_text(json.dumps(sys.argv[1:]))
print('Test Case native suite output')
print('raw compiler diagnostic', file=sys.stderr)
sys.exit(int(os.environ['FAKE_STATUS']))
''')
                xcode.chmod(0o755)
                pretty = binary / "xcpretty"
                pretty.write_text("#!/bin/sh\ncat\n")
                pretty.chmod(0o755)
                result = subprocess.run(["make", "-f", str(REPO / "apps/apple/Makefile"),
                    "test-ios", "CORE_RUST_PREPARE=:", "IOS_SIM=platform=iOS Simulator,id=fake",
                    "IOS_TEST_BUILD_FLAGS=ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"],
                    cwd=root, text=True, capture_output=True, env=dict(os.environ,
                    PATH=f"{binary}:{os.environ['PATH']}", FAKE_STATUS=str(status)))
                self.assertEqual(result.returncode == 0, status == 0)
                args = json.loads((root / "arguments.json").read_text())
                self.assertEqual(args[:1], ["test"])
                self.assertIn("ARCHS=arm64", args)
                self.assertIn("ONLY_ACTIVE_ARCH=YES", args)
                self.assertIn("COMPILER_INDEX_STORE_ENABLE=NO", args)
                self.assertEqual(args[args.index("-scheme") + 1], "HealthMd-Tests-iOS")
                self.assertFalse(any(a.startswith(("-only-testing", "-skip-testing")) for a in args))
                raw = (root / "build/logs/xcodebuild-ios-raw.log").read_text()
                self.assertIn("native suite output", raw)
                self.assertIn("raw compiler diagnostic", raw)

    def test_actual_mac_command_runs_once_and_preserves_failure_and_raw_log(self):
        shell = command(step(self.mac, "Run macOS unit tests with coverage"))
        for status in (0, 65):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary = root / "bin"
                binary.mkdir()
                fake = binary / "make"
                fake.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
with Path('calls.jsonl').open('a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
print('suite output')
print('raw compiler diagnostic', file=sys.stderr)
sys.exit(int(os.environ['FAKE_STATUS']))
''')
                fake.chmod(0o755)
                result = subprocess.run(["bash", "-c", shell], cwd=root, text=True,
                                        capture_output=True, env=dict(os.environ,
                                        PATH=f"{binary}:{os.environ['PATH']}", FAKE_STATUS=str(status)))
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual([json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()],
                                 [["coverage", "CORE_RUST_PREPARE=:"]])
                log = (root / "build/logs/build-macos.log").read_text()
                self.assertIn("suite output", log)
                self.assertIn("raw compiler diagnostic", log)


if __name__ == "__main__":
    unittest.main()
