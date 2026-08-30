#!/usr/bin/env python3
"""Regression tests for generated installer and formula archive metadata."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify-generated-release-metadata.py")
SPEC = importlib.util.spec_from_file_location("verify_generated_release_metadata", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {MODULE_PATH}")
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


class GeneratedReleaseMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.archives = self.root / "archives"
        self.archives.mkdir()
        self.digests: dict[str, str] = {}
        for index, name in enumerate(sorted(metadata.ARCHIVES)):
            path = self.archives / name
            path.write_bytes(f"final signed archive {index}\n".encode())
            self.digests[name] = metadata.sha256(path)

        self.manifests = self.root / "manifests"
        self.manifests.mkdir()
        for name, digest in self.digests.items():
            target = name.removeprefix("healthmd-cli-")
            target = target.removesuffix(".tar.xz").removesuffix(".zip")
            (self.manifests / f"{target}-dist-manifest.json").write_text(
                json.dumps(
                    {
                        "artifacts": {
                            name: {"checksums": {"sha256": digest}},
                        }
                    }
                ),
                encoding="utf-8",
            )

        self.shell = self.root / "installer.sh"
        shell_blocks = []
        for name, digest in self.digests.items():
            shell_blocks.append(
                f'    "{name}")\n'
                f'        _checksum_value="{digest}"\n'
                "        ;;"
            )
        self.shell.write_text("case x in\n" + "\n".join(shell_blocks) + "\nesac\n")

        self.formula = self.root / "healthmd.rb"
        formula_pairs = []
        for name in sorted(metadata.FORMULA_ARCHIVES):
            formula_pairs.append(
                f'  url "https://example.invalid/tag/{name}"\n'
                f'  sha256 "{self.digests[name]}"'
            )
        self.formula.write_text("\n".join(formula_pairs) + "\n", encoding="utf-8")

        self.powershell = self.root / "installer.ps1"
        self.powershell.write_text(
            f'  "artifact_name" = "{metadata.WINDOWS_ARCHIVE}"\n',
            encoding="utf-8",
        )

    def verify(self) -> None:
        metadata.verify(
            archives=self.archives,
            manifests=self.manifests,
            shell=self.shell,
            powershell=self.powershell,
            formula=self.formula,
        )

    def test_exact_metadata_passes(self) -> None:
        self.verify()

    def test_stale_manifest_checksum_fails(self) -> None:
        path = next(self.manifests.glob("aarch64-apple-darwin-dist-manifest.json"))
        value = json.loads(path.read_text(encoding="utf-8"))
        name = "healthmd-cli-aarch64-apple-darwin.tar.xz"
        value["artifacts"][name]["checksums"]["sha256"] = "0" * 64
        path.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(metadata.VerificationError, "dist manifest checksums"):
            self.verify()

    def test_stale_shell_checksum_fails(self) -> None:
        name = "healthmd-cli-aarch64-apple-darwin.tar.xz"
        self.shell.write_text(
            self.shell.read_text(encoding="utf-8").replace(
                self.digests[name], "1" * 64, 1
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(metadata.VerificationError, "shell installer checksums"):
            self.verify()

    def test_stale_formula_checksum_fails(self) -> None:
        name = "healthmd-cli-x86_64-apple-darwin.tar.xz"
        self.formula.write_text(
            self.formula.read_text(encoding="utf-8").replace(
                self.digests[name], "2" * 64, 1
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(metadata.VerificationError, "Homebrew formula checksums"):
            self.verify()

    def test_duplicate_formula_archive_fails(self) -> None:
        first_pair = "\n".join(self.formula.read_text(encoding="utf-8").splitlines()[:2])
        with self.formula.open("a", encoding="utf-8") as handle:
            handle.write(first_pair + "\n")
        with self.assertRaisesRegex(metadata.VerificationError, "duplicate Homebrew"):
            self.verify()

    def test_wrong_powershell_archive_set_fails(self) -> None:
        self.powershell.write_text(
            '  "artifact_name" = "healthmd-cli-x86_64-unknown-linux-gnu.tar.xz"\n',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(metadata.VerificationError, "PowerShell"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
