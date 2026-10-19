#!/usr/bin/env python3
"""Cache-safety regression tests for the exact packaged-source smoke check."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("smoke-crate-packages.py")
SPEC = importlib.util.spec_from_file_location("smoke_crate_packages", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(smoke)


def archive(path: Path, package: str, files: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(path, "w:gz") as output:
        for name, contents in files.items():
            data = contents.encode()
            entry = tarfile.TarInfo(f"{package}-1.0.0/{name}")
            entry.size = len(data)
            output.addfile(entry, io.BytesIO(data))


class TargetTests(unittest.TestCase):
    def test_local_default_stays_inside_the_temporary_directory(self) -> None:
        fallback = Path("/temporary/verified-target")
        with mock.patch.object(smoke.subprocess, "check_output") as command:
            self.assertEqual(smoke.verification_target(fallback, {}, "current", "rustc"), fallback)
        command.assert_not_called()

    def test_opt_in_cache_uses_distinct_compiler_identities(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            environment = {"HEALTHMD_PACKAGED_CACHE_DIR": directory}
            with mock.patch.object(smoke.subprocess, "check_output", return_value="rustc 1.88.0\nhost: fixture\n"):
                current = smoke.verification_target(Path("fallback"), environment, "current", "rustc")
                repeated = smoke.verification_target(Path("other"), environment, "current", "rustc")
            with mock.patch.object(smoke.subprocess, "check_output", return_value="rustc 1.85.0\nhost: fixture\n"):
                msrv = smoke.verification_target(Path("fallback"), environment, "msrv", "msrv-rustc")
            self.assertEqual(current, repeated)
            self.assertNotEqual(current, msrv)
            self.assertEqual(current.parent, Path(directory).resolve())
            self.assertEqual(msrv.parent, Path(directory).resolve())


class SmokeCoverageTests(unittest.TestCase):
    def test_warm_targets_still_package_check_test_build_and_execute_every_smoke(self) -> None:
        commands = []
        outputs = []

        def run(arguments, cwd, env):
            arguments = list(map(str, arguments))
            commands.append((arguments, dict(env)))
            if arguments[1] == "package":
                package = arguments[arguments.index("-p") + 1]
                archive(Path(env["CARGO_TARGET_DIR"]) / "package" / f"{package}-1.0.0.crate", package,
                        {name: "fixture" for name in smoke.REQUIRED[package]})

        def output(arguments, **kwargs):
            arguments = list(map(str, arguments))
            outputs.append(arguments)
            if arguments[:2] == ["rustup", "which"]:
                return "/toolchains/1.85.0/bin/" + arguments[-1] + "\n"
            if arguments[-1] == "-vV":
                return "rustc " + ("1.85.0" if "1.85.0" in arguments[0] else "1.88.0")
            if arguments[-1] == "--version":
                return "healthmd 1.0.0\n"
            return json.dumps({"schema": "healthmd.mcp_tool_schema", "tool": {"name": "healthmd_sleep_sessions"}})

        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.dict(os.environ, {"HEALTHMD_PACKAGED_CACHE_DIR": directory}), \
                mock.patch.object(smoke, "run", side_effect=run), \
                mock.patch.object(smoke.subprocess, "check_output", side_effect=output), \
                mock.patch.object(smoke.subprocess, "run") as executable, \
                mock.patch("sys.argv", [str(SCRIPT), "--version", "1.0.0"]):
            self.assertEqual(smoke.main(), 0)
        self.assertEqual([command[0][command[0].index("-p") + 1] for command in commands if command[0][1] == "package"], list(smoke.REQUIRED))
        checks = [(args, env) for args, env in commands if args[1] == "check"]
        tests = [(args, env) for args, env in commands if args[1] == "test"]
        builds = [(args, env) for args, env in commands if args[1] == "build"]
        self.assertEqual(len(checks), 1)
        self.assertEqual(len(tests), 1)
        self.assertEqual(len(builds), 1)
        for args, _ in checks + tests:
            self.assertIn("--workspace", args)
            self.assertIn("--all-features", args)
        self.assertIn("--locked", tests[0][0])
        self.assertIn("--bins", builds[0][0])
        self.assertNotEqual(checks[0][1]["CARGO_TARGET_DIR"], tests[0][1]["CARGO_TARGET_DIR"])
        self.assertEqual(tests[0][1]["CARGO_TARGET_DIR"], builds[0][1]["CARGO_TARGET_DIR"])
        cleans = [(args, env) for args, env in commands if args[1] == "clean"]
        self.assertEqual(len(cleans), 2)
        for args, _ in cleans:
            self.assertEqual([args[i + 1] for i, arg in enumerate(args) if arg == "-p"], list(smoke.REQUIRED))
        self.assertTrue(any(args[-1] == "--version" and args[0].endswith("healthmd" + (".exe" if os.name == "nt" else "")) for args in outputs))
        self.assertTrue(any(args[-3:] == ["mcp", "schema", "healthmd_sleep_sessions"] for args in outputs))
        self.assertEqual(len(executable.call_args_list), 2)
        self.assertTrue(all(call.args[0][-1] == "--help" for call in executable.call_args_list))


class RealCargoCacheTests(unittest.TestCase):
    """Small offline builds prove cache hits cannot replace packaged tests/binaries."""

    def test_dependency_reused_but_fresh_archive_tests_and_executables_run(self) -> None:
        with tempfile.TemporaryDirectory(prefix="healthmd-package-cache-test-") as directory:
            root = Path(directory)
            target = root / "target"
            dependency = root / "dependency"
            (dependency / "src").mkdir(parents=True)
            (dependency / "Cargo.toml").write_text('[package]\nname="cache-fixture-dependency"\nversion="1.0.0"\nedition="2021"\n')
            (dependency / "src/lib.rs").write_text('pub fn value() -> u32 { 42 }\n')
            marker = root / "executed"
            environment = os.environ.copy()
            environment.update(CARGO_TARGET_DIR=str(target), CARGO_INCREMENTAL="0", CARGO_NET_OFFLINE="true", FIXTURE_MARKER=str(marker), RUSTUP_TOOLCHAIN="1.88.0")
            files = {
                "Cargo.toml": '[package]\nname="cache-fixture-app"\nversion="1.0.0"\nedition="2021"\n[dependencies]\ncache-fixture-dependency={path=' + json.dumps(str(dependency)) + '}\n',
                "src/main.rs": 'mod packaged_logic;\nfn main() { assert_eq!(packaged_logic::value(),42); std::fs::write(std::env::var("FIXTURE_MARKER").unwrap(),"binary").unwrap(); }\n#[test]\nfn actual_test() { assert_eq!(packaged_logic::value(),42); std::fs::write(std::env::var("FIXTURE_MARKER").unwrap(),"test").unwrap(); }\n',
                "src/packaged_logic.rs": 'pub fn value() -> u32 { cache_fixture_dependency::value() }\n',
            }

            def invocation(number: int, source: dict[str, str]):
                package_target = root / f"package-{number}"
                archive(package_target / "package/cache-fixture-app-1.0.0.crate", "cache-fixture-app", source)
                extracted = root / f"extracted-{number}"
                extracted.mkdir()
                paths = smoke.extract_archives(package_target, extracted, "1.0.0", {"cache-fixture-app": {"Cargo.toml", "src/main.rs"}})
                manifest = paths["cache-fixture-app"] / "Cargo.toml"
                subprocess.run(["cargo", "generate-lockfile", "--manifest-path", str(manifest)], cwd=root, env=environment, check=True, capture_output=True)
                smoke.clean_packaged_crates(manifest, paths, root, environment, "cargo")
                command = ["cargo", "test", "--manifest-path", str(manifest), "--all-features", "--message-format=json"]
                completed = subprocess.run(command, cwd=root, env=environment, text=True, capture_output=True)
                if completed.returncode:
                    return completed, []
                self.assertEqual(marker.read_text(), "test")
                marker.unlink()
                subprocess.run(["cargo", "build", "--manifest-path", str(manifest)], cwd=root, env=environment, check=True, capture_output=True)
                executable = target / "debug" / ("cache-fixture-app.exe" if os.name == "nt" else "cache-fixture-app")
                subprocess.run([executable], env=environment, check=True)
                self.assertEqual(marker.read_text(), "binary")
                marker.unlink()
                artifacts = [json.loads(line) for line in completed.stdout.splitlines() if line.startswith('{')]
                return completed, [item for item in artifacts if item.get("reason") == "compiler-artifact"]

            cold, cold_artifacts = invocation(1, files)
            self.assertEqual(cold.returncode, 0, cold.stderr)
            self.assertFalse(next(item for item in cold_artifacts if item["target"]["name"] == "cache_fixture_dependency")["fresh"])
            warm, warm_artifacts = invocation(2, files)
            self.assertEqual(warm.returncode, 0, warm.stderr)
            self.assertTrue(next(item for item in warm_artifacts if item["target"]["name"] == "cache_fixture_dependency")["fresh"])
            self.assertTrue(all(not item["fresh"] for item in warm_artifacts if item["target"]["name"] == "cache-fixture-app"))
            changed = dict(files, **{"src/main.rs": "compile_error!(\"fresh archive source must compile\");"})
            failed, _ = invocation(3, changed)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("fresh archive source must compile", failed.stdout + failed.stderr)
            missing_source = dict(files)
            del missing_source["src/main.rs"]
            with self.assertRaisesRegex(SystemExit, "archive missing"):
                invocation(4, missing_source)
            missing_module = dict(files)
            del missing_module["src/packaged_logic.rs"]
            failed, _ = invocation(5, missing_module)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("packaged_logic", failed.stdout + failed.stderr)
            (dependency / "src/lib.rs").write_text('pub fn value() -> u32 { 43 }\n')
            failed, _ = invocation(6, files)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("actual_test ... FAILED", failed.stdout)
            (dependency / "src/lib.rs").unlink()
            with self.assertRaises(subprocess.CalledProcessError):
                invocation(7, files)


if __name__ == "__main__":
    unittest.main()
