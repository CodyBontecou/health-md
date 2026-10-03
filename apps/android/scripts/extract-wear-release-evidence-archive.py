#!/usr/bin/env python3
"""Safely extract a bounded, regular-file-only Wear release evidence tar archive."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import tarfile
from pathlib import Path, PurePosixPath

MAX_ARCHIVE_BYTES = 2 * 1024 * 1024 * 1024
MAX_EXTRACTED_BYTES = 4 * 1024 * 1024 * 1024
MAX_FILE_BYTES = 1024 * 1024 * 1024
MAX_ENTRIES = 2500
SAFE_NAME = re.compile(r"^[A-Za-z0-9._/-]+$")
PROTECTED_MEMBERS = {
    "SHA256SUMS",
    "SHA256SUMS.hmac-sha256",
    "protected-ingest.json",
}
PROTECTED_DIRECTORIES = {"qa-upload", "source-review", "wear-play-screenshot-upload"}
PROTECTED_PREFIXES = ("qa-upload/", "source-review/", "wear-play-screenshot-upload/")
PROTECTED_MEMBERS_FOLDED = {value.casefold() for value in PROTECTED_MEMBERS}
PROTECTED_DIRECTORIES_FOLDED = {value.casefold() for value in PROTECTED_DIRECTORIES}
PROTECTED_PREFIXES_FOLDED = tuple(value.casefold() for value in PROTECTED_PREFIXES)


def fail(message: str) -> None:
    raise SystemExit(f"Wear evidence archive: {message}")


def normalized_name(name: str) -> PurePosixPath:
    if not name or "\x00" in name or "\\" in name or not SAFE_NAME.fullmatch(name):
        fail(f"unsafe member name: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        fail(f"unsafe member path: {name!r}")
    return path


class BoundedTarInfo(tarfile.TarInfo):
    """Reject extension headers before tarfile can recurse into or materialize their bodies."""

    physical_headers = 0

    @classmethod
    def fromtarfile(cls, bundle: tarfile.TarFile) -> tarfile.TarInfo:
        cls.physical_headers += 1
        if cls.physical_headers > MAX_ENTRIES:
            fail(f"archive physical header count exceeds {MAX_ENTRIES}")
        header = bundle.fileobj.read(tarfile.BLOCKSIZE)
        member = cls.frombuf(header, bundle.encoding, bundle.errors)
        member.offset = bundle.fileobj.tell() - tarfile.BLOCKSIZE
        if member.type in (
            tarfile.GNUTYPE_LONGNAME,
            tarfile.GNUTYPE_LONGLINK,
            tarfile.XHDTYPE,
            tarfile.XGLTYPE,
            tarfile.SOLARIS_XHDTYPE,
            tarfile.GNUTYPE_SPARSE,
        ):
            fail(f"GNU/PAX archive extensions are forbidden: {member.name!r}")
        return member._proc_builtin(bundle)


def extract(archive: Path, output: Path) -> None:
    if not archive.is_file():
        fail(f"archive missing: {archive}")
    archive_size = archive.stat().st_size
    if archive_size <= 0 or archive_size > MAX_ARCHIVE_BYTES:
        fail(f"archive size {archive_size} is outside the allowed range")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        fail(f"output must be absent or empty: {output}")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    root = output.resolve()
    seen: set[str] = set()
    seen_casefolded: set[str] = set()
    total = 0
    regular_files = 0

    try:
        # Reject GNU/PAX transport extensions. Besides being unnecessary for the bounded ASCII
        # evidence names, CPython's tarfile recursively follows extension-header chains before it
        # yields a logical member, so counting ordinary iteration cannot bound them defensibly.
        # USTAR is the only accepted input dialect; each physical header then maps one-to-one to a
        # yielded member and is bounded before any member body is materialized.
        BoundedTarInfo.physical_headers = 0
        with tarfile.open(archive, mode="r|*", tarinfo=BoundedTarInfo) as bundle:
            logical_entries = 0
            for member in bundle:
                logical_entries += 1
                if logical_entries > MAX_ENTRIES:
                    fail(f"archive entry count exceeds {MAX_ENTRIES}")
                if member.pax_headers:
                    fail(f"PAX archive extensions are forbidden: {member.name!r}")
                path = normalized_name(member.name)
                name = path.as_posix()
                folded = name.casefold()
                if name in seen or folded in seen_casefolded:
                    fail(f"duplicate or case-colliding member: {name}")
                seen.add(name)
                seen_casefolded.add(folded)
                if folded in PROTECTED_MEMBERS_FOLDED or folded in PROTECTED_DIRECTORIES_FOLDED or folded.startswith(PROTECTED_PREFIXES_FOLDED):
                    fail(f"submitted archive must not contain protected workflow-owned member: {name}")
                if not (member.isdir() or member.isreg()):
                    fail(f"links and special members are forbidden: {name}")
                # Creator ownership, modes, and timestamps are never restored; they are transport
                # metadata rather than evidence identity. Extracted paths receive fixed permissions.
                if member.isreg():
                    regular_files += 1
                    if member.size <= 0 or member.size > MAX_FILE_BYTES:
                        fail(f"member size {member.size} is invalid: {name}")
                    total += member.size
                    if total > MAX_EXTRACTED_BYTES:
                        fail("archive exceeds total uncompressed evidence limit")
                destination = (root / Path(*path.parts)).resolve()
                try:
                    destination.relative_to(root)
                except ValueError:
                    fail(f"member escapes output root: {name}")
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
                    os.chmod(destination, 0o700)
                    continue
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                source = bundle.extractfile(member)
                if source is None:
                    fail(f"unable to read regular member: {name}")
                written = 0
                with destination.open("xb") as target:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        written += len(chunk)
                        if written > member.size:
                            fail(f"member exceeded declared size: {name}")
                        target.write(chunk)
                if written != member.size:
                    fail(f"member size mismatch: {name}")
                os.chmod(destination, 0o600)
    except (tarfile.TarError, OSError, RecursionError) as error:
        shutil.rmtree(output, ignore_errors=True)
        fail(f"unable to extract archive: {error}")
    if logical_entries == 0 or regular_files == 0 or "release-attestation.json" not in seen:
        shutil.rmtree(output, ignore_errors=True)
        fail("archive lacks release-attestation.json or regular evidence files")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    extract(args.archive, args.output)
    print(f"Safely extracted bounded Wear evidence to {args.output}")


if __name__ == "__main__":
    main()
