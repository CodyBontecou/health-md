#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import os
import stat
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("safe-extract-release.py")
SPEC = importlib.util.spec_from_file_location("safe_extract_release", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class SafeExtractReleaseTests(unittest.TestCase):
    def test_extracts_bounded_regular_tar_tree_read_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "candidate.tar.xz"
            with tarfile.open(archive, "w:xz") as output:
                directory = tarfile.TarInfo("candidate")
                directory.type = tarfile.DIRTYPE
                directory.mode = 0o755
                output.addfile(directory)
                executable = tarfile.TarInfo("candidate/healthmd")
                executable.size = 7
                executable.mode = 0o755
                output.addfile(executable, io.BytesIO(b"fixture"))
            destination = root / "unpacked"
            MODULE.extract(archive, destination)
            binary = destination / "candidate" / "healthmd"
            self.assertEqual(binary.read_bytes(), b"fixture")
            if os.name != "nt":
                self.assertEqual(stat.S_IMODE(binary.stat().st_mode), 0o555)

    def test_extracts_exact_zip_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "candidate.zip"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
                output.writestr("candidate/healthmd.exe", b"fixture")
                output.writestr("candidate/healthmd-mcp.exe", b"fixture")
            destination = root / "unpacked"
            MODULE.extract(archive, destination)
            self.assertEqual(
                (destination / "candidate" / "healthmd.exe").read_bytes(), b"fixture"
            )

    def test_rejects_traversal_and_removes_partial_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "candidate.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("../escape", b"fixture")
            destination = root / "unpacked"
            with self.assertRaises(MODULE.UnsafeArchive):
                MODULE.extract(archive, destination)
            self.assertFalse(destination.exists())
            self.assertFalse((root / "escape").exists())

    def test_rejects_symlinks_and_portable_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            symlink_archive = root / "link.zip"
            with zipfile.ZipFile(symlink_archive, "w") as output:
                member = zipfile.ZipInfo("candidate/healthmd")
                member.create_system = 3
                member.external_attr = (stat.S_IFLNK | 0o777) << 16
                output.writestr(member, "elsewhere")
            with self.assertRaises(MODULE.UnsafeArchive):
                MODULE.extract(symlink_archive, root / "link-output")

            alias_archive = root / "alias.zip"
            with zipfile.ZipFile(alias_archive, "w") as output:
                output.writestr("candidate/HealthMd.exe", b"one")
                output.writestr("candidate/healthmd.exe", b"two")
            with self.assertRaises(MODULE.UnsafeArchive):
                MODULE.extract(alias_archive, root / "alias-output")

            namespace_archive = root / "namespace-alias.zip"
            with zipfile.ZipFile(namespace_archive, "w") as output:
                output.writestr("Candidate/healthmd.exe", b"one")
                output.writestr("candidate/healthmd-mcp.exe", b"two")
            with self.assertRaises(MODULE.UnsafeArchive):
                MODULE.extract(namespace_archive, root / "namespace-output")

    def test_rejects_windows_names_ads_and_trailing_aliases(self) -> None:
        for index, name in enumerate(
            (
                "candidate/healthmd.exe:payload",
                "candidate/CON",
                "candidate/com1.txt",
                "candidate/LPT³.log",
                "candidate/trailing.",
                "candidate/trailing ",
                "candidate/bad<name>",
                "candidate/control\x01name",
            )
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / f"invalid-{index}.zip"
                with zipfile.ZipFile(archive, "w") as output:
                    output.writestr(name, b"fixture")
                with self.assertRaises(MODULE.UnsafeArchive):
                    MODULE.extract(archive, root / "output")

    def test_rejects_declared_aggregate_over_bound(self) -> None:
        entries = [
            MODULE.Entry(
                relative=MODULE.PurePosixPath("candidate", f"file-{index}"),
                size=MODULE.MAXIMUM_FILE_BYTES,
                is_directory=False,
                executable=False,
                open_source=lambda: io.BytesIO(),
            )
            for index in range(3)
        ]
        with self.assertRaises(MODULE.UnsafeArchive):
            MODULE._validate_entries(entries)


if __name__ == "__main__":
    unittest.main()
