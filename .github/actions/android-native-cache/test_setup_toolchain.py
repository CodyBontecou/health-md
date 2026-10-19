#!/usr/bin/env python3
"""Exercise cold/warm native tool setup without downloading a toolchain."""
from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ACTION = Path(__file__).resolve().parent
ROOT = ACTION.parents[2]

FAKE_RUSTUP = r'''#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

arguments = sys.argv[1:]
with open(os.environ["RUSTUP_CALLS"], "a") as log:
    log.write(json.dumps(arguments) + "\n")
if arguments[:5] == ["run", "1.88.0", "cargo", "ndk", "--version"]:
    result = subprocess.run(["cargo-ndk", "--version"])
    raise SystemExit(result.returncode)
if arguments[:5] == ["run", "1.88.0", "cargo", "install", "cargo-ndk"]:
    tool_root = Path(arguments[arguments.index("--root") + 1])
    binary = tool_root / "bin/cargo-ndk"
    binary.parent.mkdir(parents=True, exist_ok=True)
    version = os.environ.get("INSTALLED_NDK_VERSION", "4.1.2")
    binary.write_text("#!/bin/sh\nprintf 'cargo-ndk " + version + "\\n'\n")
    binary.chmod(0o755)
'''


class NativeToolchainSetupTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="healthmd-native-cache-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.home = self.directory / "home"
        self.home.mkdir()
        self.binaries = self.directory / "bin"
        self.binaries.mkdir()
        rustup = self.binaries / "rustup"
        rustup.write_text(FAKE_RUSTUP)
        rustup.chmod(0o755)
        self.calls_file = self.directory / "calls.jsonl"
        self.environment = {
            **os.environ,
            "HEALTHMD_NATIVE_TOOLS_ROOT": str(self.home / ".cache/healthmd-cargo-ndk"),
            "CARGO_HOME": str(self.home / "custom-cargo"),
            "PATH": str(self.binaries) + os.pathsep + os.environ["PATH"],
            "RUSTUP_CALLS": str(self.calls_file),
            "GITHUB_PATH": str(self.directory / "github-path"),
            "GITHUB_ENV": str(self.directory / "github-env"),
            "GITHUB_OUTPUT": str(self.directory / "github-output"),
            "GITHUB_WORKSPACE": str(ROOT),
            "ANDROID_TOOLCHAIN": "true",
            "CACHE_TARGETS": "android",
        }
        self.tool_binary = (
            self.home / ".cache/healthmd-cargo-ndk"
            / "rust-1.88.0-cargo-ndk-4.1.2/bin/cargo-ndk"
        )

    def run_script(self, name: str, **environment: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(ACTION / name)],
            env={**self.environment, **environment},
            capture_output=True,
            text=True,
        )

    def calls(self) -> list[list[str]]:
        if not self.calls_file.exists():
            return []
        return [json.loads(line) for line in self.calls_file.read_text().splitlines()]

    def install_calls(self) -> list[list[str]]:
        return [call for call in self.calls() if "install" in call and "cargo-ndk" in call]

    def seed_binary(self, version: str) -> None:
        self.tool_binary.parent.mkdir(parents=True)
        self.tool_binary.write_text(f"#!/bin/sh\nprintf 'cargo-ndk {version}\\n'\n")
        self.tool_binary.chmod(0o755)

    def test_cold_setup_installs_the_pinned_binary_and_all_android_targets(self) -> None:
        result = self.run_script("setup-toolchain.sh")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(1, len(self.install_calls()))
        install = self.install_calls()[0]
        self.assertIn("--locked", install)
        self.assertEqual("4.1.2", install[install.index("--version") + 1])
        self.assertEqual(str(self.tool_binary.parent.parent), install[install.index("--root") + 1])
        target_call = next(call for call in self.calls() if call[:2] == ["target", "add"])
        self.assertEqual(
            ["target", "add", "--toolchain", "1.88.0", "aarch64-linux-android",
             "armv7-linux-androideabi", "x86_64-linux-android", "i686-linux-android"],
            target_call,
        )
        self.assertEqual(str(self.tool_binary.parent) + "\n", Path(self.environment["GITHUB_PATH"]).read_text())

    def test_warm_setup_verifies_the_binary_without_reinstalling_it(self) -> None:
        self.seed_binary("4.1.2")
        result = self.run_script("setup-toolchain.sh")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([], self.install_calls())
        self.assertEqual(2, self.calls().count(["run", "1.88.0", "cargo", "ndk", "--version"]))

    def test_wrong_cached_version_is_replaced(self) -> None:
        self.seed_binary("4.0.0")
        result = self.run_script("setup-toolchain.sh")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(1, len(self.install_calls()))
        self.assertIn("--force", self.install_calls()[0])

    def test_installing_the_wrong_version_fails(self) -> None:
        result = self.run_script("setup-toolchain.sh", INSTALLED_NDK_VERSION="4.0.0")
        self.assertNotEqual(0, result.returncode)

    def test_host_only_mode_installs_rust_without_android_tools(self) -> None:
        result = self.run_script("setup-toolchain.sh", ANDROID_TOOLCHAIN="false")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([["toolchain", "install", "1.88.0", "--profile", "minimal"]], self.calls())
        self.assertEqual("RUSTUP_TOOLCHAIN=1.88.0\n", Path(self.environment["GITHUB_ENV"]).read_text())
        self.assertFalse(Path(self.environment["GITHUB_PATH"]).exists())

    def test_invalid_toolchain_mode_fails_before_installation(self) -> None:
        result = self.run_script("setup-toolchain.sh", ANDROID_TOOLCHAIN="yes")
        self.assertEqual(64, result.returncode)
        self.assertEqual([], self.calls())

    def configure(self, mode: str, android: str = "true") -> dict[str, str]:
        output_file = Path(self.environment["GITHUB_OUTPUT"])
        output_file.unlink(missing_ok=True)
        result = self.run_script("configure.sh", CACHE_TARGETS=mode, ANDROID_TOOLCHAIN=android)
        self.assertEqual(0, result.returncode, result.stderr)
        outputs: dict[str, str] = {}
        lines = iter(output_file.read_text().splitlines())
        for line in lines:
            if "<<" in line:
                key, delimiter = line.split("<<", 1)
                value = []
                for entry in lines:
                    if entry == delimiter:
                        break
                    value.append(entry)
                outputs[key] = "\n".join(value)
            else:
                key, value = line.split("=", 1)
                outputs[key] = value
        return outputs

    def test_only_selected_component_targets_are_cached(self) -> None:
        expected = {
            "android": ["apps/android/healthmd-core/build/rust-target"],
            "android-cli": ["apps/android/healthmd-core/build/rust-target", "apps/cli/target"],
            "cli": ["apps/cli/target"],
            "none": [],
        }
        for mode, paths in expected.items():
            with self.subTest(mode=mode):
                outputs = self.configure(mode)
                self.assertEqual([str(ROOT / path) for path in paths], outputs["targets"].splitlines())
                self.assertRegex(outputs["source"], r"^[0-9a-f]{40}$")

    def test_clean_source_mode_caches_downloads_and_tools_without_build_outputs_or_credentials(self) -> None:
        outputs = self.configure("none")
        self.assertEqual("", outputs["targets"])
        self.assertEqual(
            [str(self.home / "custom-cargo/registry"), str(self.home / "custom-cargo/git/db"),
             str(self.home / "custom-cargo/git/checkouts"), str(self.tool_binary.parent.parent)],
            outputs["dependencies"].splitlines(),
        )

    def test_host_only_mode_does_not_restore_the_android_tool(self) -> None:
        outputs = self.configure("cli", android="false")
        self.assertNotIn("healthmd-cargo-ndk", outputs["dependencies"])

    def test_invalid_cache_mode_fails_without_outputs(self) -> None:
        result = self.run_script("configure.sh", CACHE_TARGETS="../../arbitrary")
        self.assertEqual(64, result.returncode)
        self.assertFalse(Path(self.environment["GITHUB_OUTPUT"]).exists())

    def test_dependency_keys_separate_host_and_android_tool_path_sets(self) -> None:
        # GitHub caches are immutable. A host-only job must not claim the native
        # dependency key before another job has populated its cargo-ndk binary.
        action = (ACTION / "action.yml").read_text()
        steps = re.split(r"(?m)^    - name: ", action)[1:]
        dependency_steps = [step for step in steps if "path: ${{ steps.paths.outputs.dependencies }}" in step]
        self.assertEqual(2, len(dependency_steps))
        selector = "${{ inputs.android-toolchain }}"
        for step in dependency_steps:
            with self.subTest(step=step.splitlines()[0]):
                key = re.search(r"(?m)^        key: (.+)$", step).group(1)
                prefix = re.search(r"(?m)^        restore-keys: \|\n          (.+)$", step).group(1)
                self.assertIn(selector, key)
                self.assertIn(selector, prefix)
                host_key, native_key = key.replace(selector, "false"), key.replace(selector, "true")
                host_prefix, native_prefix = prefix.replace(selector, "false"), prefix.replace(selector, "true")
                self.assertTrue(host_key.startswith(host_prefix))
                self.assertTrue(native_key.startswith(native_prefix))
                self.assertFalse(host_key.startswith(native_prefix))
                self.assertFalse(native_key.startswith(host_prefix))


if __name__ == "__main__":
    unittest.main()
