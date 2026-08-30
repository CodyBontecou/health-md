#!/usr/bin/env python3
"""Verify that generated installers reference the exact final release archives."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ARCHIVES = {
    "healthmd-cli-aarch64-apple-darwin.tar.xz",
    "healthmd-cli-aarch64-unknown-linux-gnu.tar.xz",
    "healthmd-cli-x86_64-apple-darwin.tar.xz",
    "healthmd-cli-x86_64-pc-windows-msvc.zip",
    "healthmd-cli-x86_64-unknown-linux-gnu.tar.xz",
}
FORMULA_ARCHIVES = {name for name in ARCHIVES if "windows" not in name}
WINDOWS_ARCHIVE = "healthmd-cli-x86_64-pc-windows-msvc.zip"
ARCHIVE_NAME = r"healthmd-cli-[0-9A-Za-z_.-]+\.(?:tar\.xz|zip)"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SHELL_CASE = re.compile(
    rf'^\s*"(?P<name>{ARCHIVE_NAME})"\)\s*$'
)
SHELL_CHECKSUM = re.compile(r'^\s*_checksum_value="(?P<digest>[0-9a-f]{64})"\s*$')
FORMULA_PAIR = re.compile(
    rf'^\s*url\s+"[^"]*/(?P<name>{ARCHIVE_NAME})"\s*\n'
    r'^\s*sha256\s+"(?P<digest>[0-9a-f]{64})"\s*$',
    re.MULTILINE,
)
POWERSHELL_ARCHIVE = re.compile(
    rf'^\s*"artifact_name"\s*=\s*"(?P<name>{ARCHIVE_NAME})"\s*$',
    re.MULTILINE,
)


class VerificationError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def final_archive_digests(directory: Path) -> dict[str, str]:
    found = {
        path.name: sha256(path)
        for path in directory.iterdir()
        if path.is_file() and re.fullmatch(ARCHIVE_NAME, path.name)
    }
    if set(found) != ARCHIVES:
        missing = sorted(ARCHIVES - set(found))
        unexpected = sorted(set(found) - ARCHIVES)
        raise VerificationError(
            f"final archive set differs: missing={missing}, unexpected={unexpected}"
        )
    return found


def record(mapping: dict[str, str], name: str, digest: str, source: str) -> None:
    if name in mapping:
        raise VerificationError(f"duplicate {source} metadata for {name}")
    if not SHA256.fullmatch(digest):
        raise VerificationError(f"invalid {source} SHA-256 for {name}: {digest!r}")
    mapping[name] = digest


def shell_digests(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    mapping: dict[str, str] = {}
    for index, line in enumerate(lines):
        match = SHELL_CASE.fullmatch(line)
        if match is None:
            continue
        name = match.group("name")
        digest: str | None = None
        for following in lines[index + 1 :]:
            if following.strip() == ";;":
                break
            checksum = SHELL_CHECKSUM.fullmatch(following)
            if checksum is not None:
                if digest is not None:
                    raise VerificationError(f"multiple shell checksums for {name}")
                digest = checksum.group("digest")
        if digest is None:
            raise VerificationError(f"shell installer omits checksum for {name}")
        record(mapping, name, digest, "shell installer")
    return mapping


def formula_digests(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for match in FORMULA_PAIR.finditer(path.read_text(encoding="utf-8")):
        record(mapping, match.group("name"), match.group("digest"), "Homebrew formula")
    return mapping


def powershell_archives(path: Path) -> set[str]:
    names = {
        match.group("name")
        for match in POWERSHELL_ARCHIVE.finditer(path.read_text(encoding="utf-8"))
    }
    if names != {WINDOWS_ARCHIVE}:
        raise VerificationError(
            f"PowerShell installer archive set differs: {sorted(names)}"
        )
    return names


def manifest_digests(directory: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for name in sorted(ARCHIVES):
        target = name.removeprefix("healthmd-cli-")
        target = target.removesuffix(".tar.xz").removesuffix(".zip")
        matches = list(directory.rglob(f"{target}-dist-manifest.json"))
        if len(matches) != 1:
            raise VerificationError(
                f"expected one dist manifest for {name}, found {len(matches)}"
            )
        try:
            manifest = json.loads(matches[0].read_text(encoding="utf-8"))
            digest = manifest["artifacts"][name]["checksums"]["sha256"]
        except (KeyError, TypeError, json.JSONDecodeError) as error:
            raise VerificationError(
                f"dist manifest lacks SHA-256 for {name}: {matches[0]}"
            ) from error
        record(mapping, name, digest, "dist manifest")
    return mapping


def require_exact(
    label: str,
    actual: dict[str, str],
    expected: dict[str, str],
) -> None:
    if actual != expected:
        details = [
            f"{name}: expected={expected.get(name)}, actual={actual.get(name)}"
            for name in sorted(set(actual) | set(expected))
            if actual.get(name) != expected.get(name)
        ]
        raise VerificationError(f"{label} differs from final archives: " + "; ".join(details))


def verify(
    archives: Path,
    manifests: Path | None = None,
    shell: Path | None = None,
    powershell: Path | None = None,
    formula: Path | None = None,
) -> None:
    expected = final_archive_digests(archives)
    if manifests is not None:
        require_exact("dist manifest checksums", manifest_digests(manifests), expected)
    if shell is not None:
        require_exact("shell installer checksums", shell_digests(shell), expected)
    if formula is not None:
        formula_expected = {name: expected[name] for name in FORMULA_ARCHIVES}
        require_exact("Homebrew formula checksums", formula_digests(formula), formula_expected)
    if powershell is not None:
        powershell_archives(powershell)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archives", required=True, type=Path)
    parser.add_argument("--manifests", type=Path)
    parser.add_argument("--shell", type=Path)
    parser.add_argument("--powershell", type=Path)
    parser.add_argument("--formula", type=Path)
    args = parser.parse_args()
    try:
        verify(
            archives=args.archives,
            manifests=args.manifests,
            shell=args.shell,
            powershell=args.powershell,
            formula=args.formula,
        )
    except (OSError, VerificationError) as error:
        print(f"generated release metadata verification failed: {error}", file=sys.stderr)
        return 1
    print("generated release metadata matches final archive bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
