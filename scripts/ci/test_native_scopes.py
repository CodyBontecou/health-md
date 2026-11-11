"""Ensure reduced CI native artifacts cannot be mistaken for release artifacts."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "packages/healthmd-core-rust/scripts"


class NativeScopeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        binary = self.root / "bin"
        binary.mkdir()
        xcrun = binary / "xcrun"
        xcrun.write_text("""#!/usr/bin/env python3
import os
import sys
from pathlib import Path
command = sys.argv[1]
if command == 'lipo':
    identifier = Path(sys.argv[-1]).parent.name
    print(os.environ.get('FAKE_ARCHITECTURES', 'arm64 x86_64' if 'arm64_x86_64' in identifier else 'arm64'))
elif command == 'nm':
    if os.environ.get('FAKE_MISSING_SYMBOL') != '1':
        print('uniffi_healthmd_core_uniffi_fn_func_get_build_info')
    print('uniffi_healthmd_core_uniffi_fn_func_run_self_test')
    print('uniffi_healthmd_core_uniffi_fn_func_validate_fixture')
    print('ffi_healthmd_core_uniffi_uniffi_contract_version')
elif command != 'otool':
    raise SystemExit(1)
""")
        xcrun.chmod(0o755)
        self.environment = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"]}
        self.environment.pop("HEALTHMD_CORE_APPLE_SCOPE", None)
        self.environment.pop("HEALTHMD_CORE_ANDROID_ABIS", None)

    def framework(self, identifiers):
        framework = self.root / "HealthmdCore.xcframework"
        framework.mkdir()
        (framework / "Info.plist").write_text("fixture")
        for identifier in identifiers:
            library = framework / identifier
            (library / "Headers").mkdir(parents=True)
            (library / "libHealthmdCoreFFI.a").write_bytes(b"fixture-static-archive")
            (library / "Headers/HealthmdCoreFFI.h").write_text("fixture")
            (library / "Headers/module.modulemap").write_text("module HealthmdCoreFFI { }\n")
        return framework

    def validate(self, framework, scope=None, **environment):
        env = {**self.environment, **environment}
        if scope is not None:
            env["HEALTHMD_CORE_APPLE_SCOPE"] = scope
        return subprocess.run(["/bin/sh", str(SCRIPTS / "validate-apple-xcframework.sh"), str(framework)], env=env, capture_output=True, text=True)

    def test_ci_framework_is_valid_for_ci_and_rejected_by_default_release_validation(self):
        framework = self.framework(["ios-arm64-simulator", "macos-arm64"])
        self.assertEqual(self.validate(framework, "ci-arm64").returncode, 0)
        result = self.validate(framework)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing static library", result.stderr)

    def test_complete_framework_remains_valid_by_default(self):
        framework = self.framework(["ios-arm64", "ios-arm64_x86_64-simulator", "macos-arm64_x86_64"])
        self.assertEqual(self.validate(framework).returncode, 0)
        self.assertNotEqual(self.validate(framework, "ci-arm64").returncode, 0)

    def test_reduced_framework_still_requires_architecture_and_symbols(self):
        framework = self.framework(["ios-arm64-simulator", "macos-arm64"])
        self.assertNotEqual(self.validate(framework, "ci-arm64", FAKE_ARCHITECTURES="x86_64").returncode, 0)
        result = self.validate(framework, "ci-arm64", FAKE_MISSING_SYMBOL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not export required symbol", result.stderr)

    def test_reduced_framework_rejects_unexpected_slices(self):
        framework = self.framework(["ios-arm64-simulator", "macos-arm64", "extra"])
        result = self.validate(framework, "ci-arm64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 2 static libraries", result.stderr)

    def test_android_rejects_single_abi_release_before_starting_a_build(self):
        result = subprocess.run(["/bin/sh", str(SCRIPTS / "build-android-cdylibs.sh"), "release", str(self.root / "jni")], env={**self.environment, "HEALTHMD_CORE_ANDROID_ABIS": "arm64-v8a"}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("single-ABI mode is debug-only", result.stderr)
        self.assertFalse((self.root / "jni").exists())

    def test_android_rejects_unknown_or_multiple_custom_abis(self):
        for selection in ("invalid", "arm64-v8a x86_64"):
            result = subprocess.run(["/bin/sh", str(SCRIPTS / "build-android-cdylibs.sh"), "debug", str(self.root / "jni")], env={**self.environment, "HEALTHMD_CORE_ANDROID_ABIS": selection}, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsupported ABI selection", result.stderr)


if __name__ == "__main__":
    unittest.main()
