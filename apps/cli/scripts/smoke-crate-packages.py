#!/usr/bin/env python3
"""Build, inspect, and execute the exact crates.io source archives offline."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tarfile
import tempfile
from pathlib import Path

REQUIRED = {
    "healthmd-core": {
        "Cargo.toml", "LICENSE", "README.md", "src/lib.rs", "src/render/markdown_merge/scoped_note.rs",
        "registry/metric-registry-v1.json", "registry/metric-registry-v2.json", "registry/metric-registry-v3.json",
        "fixtures/m1-self-test.json", "tests/fixtures/contracts/render-input/v2/fixtures/native-android-v6-handoff.json",
    },
    "healthmd-protocol": {
        "Cargo.toml",
        "LICENSE",
        "README.md",
        "src/lib.rs",
        "tests/fixtures/swift-direct-v1.json",
        "tests/fixtures/swift-direct-v3.json",
        "tests/fixtures/kotlin-direct-v2.json",
    },
    "healthmd-operations": {
        "Cargo.toml",
        "LICENSE",
        "README.md",
        "src/lib.rs",
        "src/backend.rs",
        "src/limits.rs",
        "src/normalize.rs",
        "src/receipt.rs",
        "src/registry.rs",
        "src/service.rs",
        "examples/generate_mcp_catalog.rs",
        "tests/fixtures/agent-data-v1/grant-explicit.json",
        "tests/fixtures/agent-data-v1/query-records.json",
    },
    "healthmd-client": {
        "Cargo.toml",
        "LICENSE",
        "README.md",
        "src/lib.rs",
        "src/generated_path.rs",
        "src/limits.rs",
    },
    "healthmd-mcp": {
        "Cargo.toml",
        "LICENSE",
        "README.md",
        "src/lib.rs",
        "assets/mcp-tools-v1.json",
        "assets/metric-registry-v1.json",
        "assets/query-visualization-v1.html",
    },
    "healthmd-cli": {
        "Cargo.toml",
        "LICENSE",
        "README.md",
        "src/main.rs",
        "src/bin/healthmd-mcp/main.rs",
        "tests/fixtures/apple-api-export-v2-provider-sidecar.json",
        "tests/fixtures/android-raw-v1-minimal-snapshot.json",
    },
}


def run(arguments: list[str], cwd: Path, env: dict[str, str]) -> None:
    subprocess.run(arguments, cwd=cwd, env=env, check=True)


def verification_target(
    fallback: Path, env: dict[str, str], label: str, rustc: str | Path
) -> Path:
    """Opt in to dependency caching without mixing compiler/host identities."""
    cache = env.get("HEALTHMD_PACKAGED_CACHE_DIR")
    if not cache:
        return fallback
    identity = subprocess.check_output([str(rustc), "-vV"], text=True, env=env)
    digest = hashlib.sha256(identity.encode()).hexdigest()[:16]
    return Path(cache).expanduser().resolve() / f"{label}-{digest}"


def extract_archives(
    package_target: Path,
    extracted: Path,
    version: str,
    required_files: dict[str, set[str]] = REQUIRED,
) -> dict[str, Path]:
    member_paths: dict[str, Path] = {}
    for package, required in required_files.items():
        archive = package_target / "package" / f"{package}-{version}.crate"
        if not archive.is_file():
            raise SystemExit(f"missing package archive: {archive}")
        with tarfile.open(archive, "r:gz") as crate:
            names = {
                name.removeprefix(f"{package}-{version}/")
                for name in crate.getnames()
                if name.startswith(f"{package}-{version}/")
            }
            missing = required - names
            if missing:
                raise SystemExit(f"{package} archive missing: {sorted(missing)}")
            crate.extractall(extracted, filter="data")
        member_paths[package] = extracted / f"{package}-{version}"
    return member_paths


def clean_packaged_crates(
    manifest: Path,
    packages: dict[str, Path],
    root: Path,
    env: dict[str, str],
    cargo: str | Path,
) -> None:
    # Restored targets may contain same-version local artifacts. Recompile every
    # archived crate, including tests/build scripts, while retaining dependencies.
    run(
        [str(cargo), "clean", "--manifest-path", str(manifest), "--locked"]
        + [argument for package in packages for argument in ("-p", package)],
        root,
        env,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    arguments = parser.parse_args()
    version = arguments.version
    root = Path(__file__).resolve().parents[3]

    with tempfile.TemporaryDirectory(prefix="healthmd-crates-") as raw_temporary:
        temporary = Path(raw_temporary)
        package_target = temporary / "package-target"
        env = os.environ.copy()
        # Archive generation and extraction are always fresh. CI may retain only
        # compiler-separated verification targets; local runs remain ephemeral.
        # Suppress debug/incremental data on the smaller Windows runner disks.
        env.setdefault("CARGO_INCREMENTAL", "0")
        env.setdefault("CARGO_PROFILE_DEV_DEBUG", "0")
        env.setdefault("CARGO_PROFILE_TEST_DEBUG", "0")
        env["CARGO_TARGET_DIR"] = str(package_target)
        for package in ("healthmd-core", "healthmd-protocol"):
            run(
                [
                    "cargo", "package", "--manifest-path",
                    str(root / "packages/healthmd-core-rust/Cargo.toml"),
                    "--locked", "--allow-dirty", "--no-verify", "-p", package,
                ],
                root,
                env,
            )
        local_patches = [
            "--config",
            f'patch.crates-io.healthmd-core.path={json.dumps(str(root / "packages/healthmd-core-rust/crates/healthmd-core"))}',
            "--config",
            f'patch.crates-io.healthmd-protocol.path={json.dumps(str(root / "packages/healthmd-core-rust/crates/healthmd-protocol"))}',
        ]
        for package in (
            "healthmd-operations",
            "healthmd-client",
            "healthmd-mcp",
            "healthmd-cli",
        ):
            package_patches = list(local_patches)
            if package in {"healthmd-mcp", "healthmd-cli"}:
                package_patches.extend(
                    [
                        "--config",
                        f'patch.crates-io.healthmd-operations.path={json.dumps(str(root / "apps/cli/crates/healthmd-operations"))}',
                    ]
                )
            if package == "healthmd-cli":
                package_patches.extend(
                    [
                        "--config",
                        f'patch.crates-io.healthmd-client.path={json.dumps(str(root / "apps/cli/crates/healthmd-client"))}',
                        "--config",
                        f'patch.crates-io.healthmd-mcp.path={json.dumps(str(root / "apps/cli/crates/healthmd-mcp"))}',
                    ]
                )
            run(
                [
                    "cargo",
                    "package",
                    "--manifest-path",
                    str(root / "apps/cli/Cargo.toml"),
                    "--locked",
                    "--allow-dirty",
                    "--no-verify",
                    "-p",
                    package,
                    *package_patches,
                ],
                root,
                env,
            )

        extracted = temporary / "extracted"
        extracted.mkdir()
        member_paths = extract_archives(package_target, extracted, version)

        workspace = temporary / "workspace.toml"
        workspace.write_text(
            "[workspace]\n"
            + "resolver = \"3\"\n"
            + "members = [\n"
            + "".join(
                f"  {json.dumps(str(path))},\n" for path in member_paths.values()
            )
            + "]\n\n[patch.crates-io]\n"
            + f"healthmd-core = {{ path = {json.dumps(str(member_paths['healthmd-core']))} }}\n"
            + f"healthmd-protocol = {{ path = {json.dumps(str(member_paths['healthmd-protocol']))} }}\n"
            + f"healthmd-operations = {{ path = {json.dumps(str(member_paths['healthmd-operations']))} }}\n"
            + f"healthmd-client = {{ path = {json.dumps(str(member_paths['healthmd-client']))} }}\n"
            + f"healthmd-mcp = {{ path = {json.dumps(str(member_paths['healthmd-mcp']))} }}\n",
            encoding="utf-8",
        )
        # Cargo requires the virtual manifest to be named Cargo.toml.
        manifest = temporary / "Cargo.toml"
        workspace.replace(manifest)
        verified_target = verification_target(
            temporary / "verified-target", env, "current", env.get("RUSTC", "rustc")
        )
        env["CARGO_TARGET_DIR"] = str(verified_target)
        toolchain_cargo = Path(
            subprocess.check_output(
                ["rustup", "which", "--toolchain", "1.85.0", "cargo"], text=True
            ).strip()
        )
        toolchain_rustc = Path(
            subprocess.check_output(
                ["rustup", "which", "--toolchain", "1.85.0", "rustc"], text=True
            ).strip()
        )
        msrv_env = env.copy()
        msrv_env["PATH"] = os.pathsep.join(
            [str(toolchain_cargo.parent), msrv_env.get("PATH", "")]
        )
        msrv_env["RUSTC"] = str(toolchain_rustc)
        msrv_env["CARGO_TARGET_DIR"] = str(
            verification_target(temporary / "msrv-target", env, "msrv", toolchain_rustc)
        )
        run([str(toolchain_rustc), "--version"], root, msrv_env)
        # A fresh lockfile resolution can select crates that no longer compile on the
        # package MSRV. Resolve with the MSRV toolchain so rust-version bounds apply.
        # yoke-derive 0.8.4 declares Rust 1.82 and compiles on 1.85; the former
        # derive-only downgrade conflicts with its current consumers.
        run(
            [str(toolchain_cargo), "generate-lockfile", "--manifest-path", str(manifest)],
            root,
            msrv_env,
        )
        clean_packaged_crates(manifest, member_paths, root, msrv_env, toolchain_cargo)
        run(
            [
                str(toolchain_cargo),
                "check",
                "--manifest-path",
                str(manifest),
                "--workspace",
                "--all-features",
            ],
            root,
            msrv_env,
        )
        clean_packaged_crates(manifest, member_paths, root, env, "cargo")
        run(
            [
                "cargo",
                "test",
                "--manifest-path",
                str(manifest),
                "--workspace",
                "--all-features",
                "--locked",
            ],
            root,
            env,
        )
        run(
            [
                "cargo",
                "build",
                "--manifest-path",
                str(manifest),
                "-p",
                "healthmd-cli",
                "--bins",
            ],
            root,
            env,
        )
        suffix = ".exe" if os.name == "nt" else ""
        healthmd = verified_target / "debug" / f"healthmd{suffix}"
        compatibility = verified_target / "debug" / f"healthmd-mcp{suffix}"
        version_output = subprocess.check_output([healthmd, "--version"], text=True).strip()
        if version not in version_output:
            raise SystemExit(f"packaged CLI version mismatch: {version_output}")
        subprocess.run([healthmd, "--help"], check=True, stdout=subprocess.DEVNULL)
        schema = json.loads(
            subprocess.check_output(
                [healthmd, "mcp", "schema", "healthmd_sleep_sessions"], text=True
            )
        )
        if (
            schema.get("schema") != "healthmd.mcp_tool_schema"
            or schema.get("tool", {}).get("name") != "healthmd_sleep_sessions"
        ):
            raise SystemExit("packaged MCP schema smoke test failed")
        subprocess.run([compatibility, "--help"], check=True, stdout=subprocess.DEVNULL)

    print(f"verified packaged crates for {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
