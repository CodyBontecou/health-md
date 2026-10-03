#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import tarfile
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "extract-wear-release-evidence-archive.py"
spec = importlib.util.spec_from_file_location("wear_evidence_archive", SCRIPT)
assert spec and spec.loader
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class WearEvidenceArchiveTest(unittest.TestCase):
    def _archive(self, root: Path, entries: list[tuple[str, str, bytes]]) -> Path:
        path = root / "evidence.tar.gz"
        with tarfile.open(path, "w:gz") as bundle:
            for name, kind, content in entries:
                info = tarfile.TarInfo(name)
                if kind == "file":
                    info.size = len(content)
                    bundle.addfile(info, io.BytesIO(content))
                elif kind == "dir":
                    info.type = tarfile.DIRTYPE
                    bundle.addfile(info)
                elif kind == "symlink":
                    info.type = tarfile.SYMTYPE
                    info.linkname = content.decode()
                    bundle.addfile(info)
                elif kind == "fifo":
                    info.type = tarfile.FIFOTYPE
                    bundle.addfile(info)
        return path

    def test_extracts_regular_bounded_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle = self._archive(root, [
                ("release-attestation.json", "file", b"{}\n"),
                ("wear-play", "dir", b""),
                ("wear-play/receipt.json", "file", b"{}\n"),
            ])
            output = root / "out"
            archive.extract(bundle, output)
            self.assertEqual((output / "release-attestation.json").read_bytes(), b"{}\n")
            self.assertEqual((output / "wear-play/receipt.json").read_bytes(), b"{}\n")

    def test_rejects_traversal_absolute_links_special_and_duplicate_paths(self) -> None:
        cases = (
            [("release-attestation.json", "file", b"{}"), ("../escape", "file", b"x")],
            [("release-attestation.json", "file", b"{}"), ("/absolute", "file", b"x")],
            [("release-attestation.json", "file", b"{}"), ("link", "symlink", b"../escape")],
            [("release-attestation.json", "file", b"{}"), ("pipe", "fifo", b"")],
            [("release-attestation.json", "file", b"{}"), ("A/file", "file", b"x"), ("a/file", "file", b"y")],
        )
        for entries in cases:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                bundle = self._archive(root, entries)
                with self.assertRaises(SystemExit):
                    archive.extract(bundle, root / "out")

    def test_entry_limit_is_enforced_during_streaming_iteration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            entries = [("release-attestation.json", "file", b"{}")]
            entries += [(f"files/{index}", "file", b"x") for index in range(archive.MAX_ENTRIES)]
            bundle = self._archive(root, entries)
            with self.assertRaises(SystemExit):
                archive.extract(bundle, root / "out")

    def test_rejects_extension_headers_before_tarfile_recursion_or_body_read(self) -> None:
        for extension_type in (
            tarfile.XHDTYPE,
            tarfile.GNUTYPE_LONGNAME,
            tarfile.GNUTYPE_LONGLINK,
            tarfile.GNUTYPE_SPARSE,
        ):
            with self.subTest(extension_type=extension_type), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                path = root / "extension-chain.tar"
                with path.open("wb") as handle:
                    for index in range(1200):
                        info = tarfile.TarInfo(f"extension-{index}")
                        info.type = extension_type
                        payload = b"9 path=x\n" if extension_type == tarfile.XHDTYPE else b"x\0"
                        info.size = len(payload)
                        handle.write(info.tobuf(format=tarfile.USTAR_FORMAT))
                        handle.write(payload)
                        padding = (-len(payload)) % tarfile.BLOCKSIZE
                        handle.write(b"\0" * padding)
                    handle.write(b"\0" * (tarfile.BLOCKSIZE * 2))
                with self.assertRaises(SystemExit) as caught:
                    archive.extract(path, root / "out")
                self.assertNotIsInstance(caught.exception.__context__, RecursionError)

    def test_rejects_submitted_seal_empty_files_and_nonempty_output(self) -> None:
        cases = (
            [("release-attestation.json", "file", b"{}"), ("SHA256SUMS", "file", b"x")],
            [("release-attestation.json", "file", b"{}"), ("protected-ingest.json", "file", b"{}")],
            [("release-attestation.json", "file", b"{}"), ("qa-upload/receipt.json", "file", b"{}")],
            [("release-attestation.json", "file", b"{}"), ("source-review", "dir", b"")],
            [("release-attestation.json", "file", b"{}"), ("source-review/review.json", "file", b"{}")],
            [("release-attestation.json", "file", b"{}"), ("Source-Review/review.json", "file", b"{}")],
            [("release-attestation.json", "file", b"{}"), ("wear-play-screenshot-upload", "dir", b"")],
            [("release-attestation.json", "file", b"{}"), ("wear-play-screenshot-upload/receipt.json", "file", b"{}")],
            [("release-attestation.json", "file", b"{}"), ("Wear-Play-Screenshot-Upload/receipt.json", "file", b"{}")],
            [("release-attestation.json", "file", b"")],
        )
        for entries in cases:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                bundle = self._archive(root, entries)
                with self.assertRaises(SystemExit):
                    archive.extract(bundle, root / "out")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle = self._archive(root, [("release-attestation.json", "file", b"{}")])
            output = root / "out"
            output.mkdir()
            (output / "existing").write_text("x")
            with self.assertRaises(SystemExit):
                archive.extract(bundle, output)


if __name__ == "__main__":
    unittest.main()
