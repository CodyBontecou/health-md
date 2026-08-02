#!/usr/bin/env python3
"""Extract a cargo-dist release archive without trusting archive paths or metadata."""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import tarfile
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Callable

MAXIMUM_ENTRIES = 128
MAXIMUM_FILE_BYTES = 512 * 1024 * 1024
MAXIMUM_TOTAL_BYTES = 1024 * 1024 * 1024
MAXIMUM_PATH_BYTES = 1024
COPY_CHUNK_BYTES = 1024 * 1024


class UnsafeArchive(ValueError):
    """The archive is not a bounded regular-file tree."""


@dataclass(frozen=True)
class Entry:
    relative: PurePosixPath
    size: int
    is_directory: bool
    executable: bool
    open_source: Callable[[], BinaryIO] | None


def _portable_key(path: PurePosixPath) -> str:
    return unicodedata.normalize("NFC", path.as_posix()).casefold()


def _windows_reserved(component: str) -> bool:
    stem = component.split(".", 1)[0].casefold()
    if stem in {"con", "prn", "aux", "nul", "clock$", "conin$", "conout$"}:
        return True
    for prefix in ("com", "lpt"):
        if stem.startswith(prefix) and stem[len(prefix) :] in {
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"
        }:
            return True
    return False


def _invalid_component(component: str) -> bool:
    return (
        component in {"", ".", ".."}
        or component.endswith((".", " "))
        or any(character in '<>:"|?*' for character in component)
        or any(unicodedata.category(character) == "Cc" for character in component)
        or _windows_reserved(component)
    )


def _validate_name(name: str) -> PurePosixPath:
    if not name or "\x00" in name or "\\" in name:
        raise UnsafeArchive("archive path is invalid")
    if len(name.encode("utf-8")) > MAXIMUM_PATH_BYTES:
        raise UnsafeArchive("archive path is too long")
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(_invalid_component(part) for part in path.parts):
        raise UnsafeArchive("archive path is not portable or escapes its destination")
    return path


def _validate_entries(entries: list[Entry]) -> None:
    if not entries or len(entries) > MAXIMUM_ENTRIES:
        raise UnsafeArchive("archive entry count is invalid")
    total = 0
    kinds: dict[str, bool] = {}
    namespace: dict[str, str] = {}
    for entry in entries:
        if entry.size < 0 or entry.size > MAXIMUM_FILE_BYTES:
            raise UnsafeArchive("archive member is too large")
        total += entry.size
        if total > MAXIMUM_TOTAL_BYTES:
            raise UnsafeArchive("archive expands beyond its total bound")
        key = _portable_key(entry.relative)
        if key in kinds:
            raise UnsafeArchive("archive contains duplicate portable paths")
        kinds[key] = entry.is_directory
        for end in range(1, len(entry.relative.parts) + 1):
            prefix = PurePosixPath(*entry.relative.parts[:end])
            prefix_key = _portable_key(prefix)
            spelling = unicodedata.normalize("NFC", prefix.as_posix())
            previous = namespace.setdefault(prefix_key, spelling)
            if previous != spelling:
                raise UnsafeArchive("archive contains a portable namespace alias")

    for entry in entries:
        parts = entry.relative.parts
        for end in range(1, len(parts)):
            ancestor = _portable_key(PurePosixPath(*parts[:end]))
            if ancestor in kinds and not kinds[ancestor]:
                raise UnsafeArchive("archive places a child beneath a regular file")


def _tar_entries(archive: Path) -> tuple[tarfile.TarFile, list[Entry]]:
    handle = tarfile.open(archive, mode="r:xz")
    entries: list[Entry] = []
    try:
        for member in handle.getmembers():
            relative = _validate_name(member.name.rstrip("/") if member.isdir() else member.name)
            if not (member.isdir() or member.isfile()):
                raise UnsafeArchive("archive contains a link or special file")
            source = None
            if member.isfile():
                source = lambda member=member: _required_tar_source(handle, member)
            entries.append(
                Entry(
                    relative=relative,
                    size=0 if member.isdir() else member.size,
                    is_directory=member.isdir(),
                    executable=bool(member.mode & 0o111),
                    open_source=source,
                )
            )
        _validate_entries(entries)
        return handle, entries
    except Exception:
        handle.close()
        raise


def _required_tar_source(handle: tarfile.TarFile, member: tarfile.TarInfo) -> BinaryIO:
    source = handle.extractfile(member)
    if source is None:
        raise UnsafeArchive("archive member has no readable body")
    return source


def _zip_entries(archive: Path) -> tuple[zipfile.ZipFile, list[Entry]]:
    handle = zipfile.ZipFile(archive, mode="r")
    entries: list[Entry] = []
    try:
        for member in handle.infolist():
            name = member.filename.rstrip("/") if member.is_dir() else member.filename
            relative = _validate_name(name)
            mode = (member.external_attr >> 16) & 0xFFFF
            file_type = stat.S_IFMT(mode)
            if (
                member.flag_bits & 0x1
                or stat.S_ISLNK(mode)
                or (not member.is_dir() and file_type not in {0, stat.S_IFREG})
            ):
                raise UnsafeArchive("archive contains an encrypted member, link, or special file")
            source = None
            if not member.is_dir():
                source = lambda member=member: handle.open(member, mode="r")
            entries.append(
                Entry(
                    relative=relative,
                    size=0 if member.is_dir() else member.file_size,
                    is_directory=member.is_dir(),
                    executable=bool(mode & 0o111) or member.filename.lower().endswith(".exe"),
                    open_source=source,
                )
            )
        _validate_entries(entries)
        return handle, entries
    except Exception:
        handle.close()
        raise


def _copy_exact(source: BinaryIO, destination: BinaryIO, expected: int) -> None:
    remaining = expected
    while remaining:
        chunk = source.read(min(COPY_CHUNK_BYTES, remaining))
        if not chunk:
            raise UnsafeArchive("archive member ended before its declared size")
        destination.write(chunk)
        remaining -= len(chunk)
    if source.read(1):
        raise UnsafeArchive("archive member exceeds its declared size")


def extract(archive: Path, destination: Path) -> None:
    if destination.exists():
        raise UnsafeArchive("destination must not already exist")
    if archive.name.endswith(".tar.xz"):
        handle, entries = _tar_entries(archive)
    elif archive.name.endswith(".zip"):
        handle, entries = _zip_entries(archive)
    else:
        raise UnsafeArchive("unsupported archive format")

    destination.mkdir(mode=0o700, parents=False)
    try:
        directories = sorted(
            (entry for entry in entries if entry.is_directory),
            key=lambda entry: len(entry.relative.parts),
        )
        for entry in directories:
            target = destination.joinpath(*entry.relative.parts)
            target.mkdir(mode=0o700, parents=True, exist_ok=False)

        for entry in (entry for entry in entries if not entry.is_directory):
            target = destination.joinpath(*entry.relative.parts)
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            if entry.open_source is None:
                raise UnsafeArchive("regular archive member has no body")
            with entry.open_source() as source, target.open("xb") as output:
                _copy_exact(source, output, entry.size)
            target.chmod(0o555 if entry.executable else 0o444)

        for directory in destination.rglob("*"):
            if directory.is_dir():
                directory.chmod(0o755)
        destination.chmod(0o700)
    except Exception:
        # Restore write permission so a partial tree can be removed reliably.
        for path in destination.rglob("*"):
            if path.is_dir():
                path.chmod(0o700)
            else:
                path.chmod(0o600)
        destination.chmod(0o700)
        shutil.rmtree(destination, ignore_errors=True)
        raise
    finally:
        handle.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    try:
        extract(arguments.archive, arguments.destination)
    except (OSError, tarfile.TarError, zipfile.BadZipFile, UnsafeArchive) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
