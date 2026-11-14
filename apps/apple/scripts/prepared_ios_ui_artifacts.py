#!/usr/bin/env python3
"""Transfer qualified UI products between jobs without rebuilding or rewriting them."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import tarfile

from validate_ios_ui_xctestrun import BUILD_MARKER, qualify


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def pack(derived: Path, source: str, archive: Path) -> str:
    _, receipt = qualify(derived, source)
    derived = derived.resolve()
    files = [derived / BUILD_MARKER, derived / "compile.log"] + sorted((derived / "Build/Products").rglob("*"))
    inventory = []
    for path in files:
        if path.is_symlink():
            raise ValueError("prepared products must not contain symlinks")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError("prepared products must be regular files")
        stat = path.stat()
        inventory.append({"path": path.relative_to(derived).as_posix(),
                          "sha256": digest(path), "size": stat.st_size,
                          "mode": stat.st_mode & 0o777, "mtime_ns": stat.st_mtime_ns})
    metadata = json.dumps({"version": 1, "receipt": receipt, "files": inventory}).encode()
    if len(metadata) > 4 * 1024 * 1024:
        raise ValueError("prepared artifact inventory is too large")
    with tarfile.open(archive, "w:gz", compresslevel=1) as bundle:
        info = tarfile.TarInfo("qualification.json")
        info.size = len(metadata)
        bundle.addfile(info, io.BytesIO(metadata))
        for item in inventory:
            bundle.add(derived / item["path"], arcname="products/" + item["path"], recursive=False)
    return digest(archive)


def restore(archive: Path, derived: Path, source: str, expected_digest: str) -> tuple[Path, dict]:
    if not re.fullmatch(r"[0-9a-f]{64}", expected_digest) or digest(archive) != expected_digest:
        raise ValueError("prepared artifact digest differs from the producer job output")
    if not derived.is_dir() or derived.is_symlink() or any(derived.iterdir()):
        raise ValueError("restore requires a newly created empty derived-data directory")
    with tarfile.open(archive, "r:gz") as bundle:
        members = bundle.getmembers()
        names = [item.name for item in members]
        if len(names) != len(set(names)) or not names or names[0] != "qualification.json":
            raise ValueError("duplicate or missing prepared artifact metadata")
        metadata_member = members[0]
        if not metadata_member.isfile() or metadata_member.size > 4 * 1024 * 1024:
            raise ValueError("invalid prepared artifact metadata")
        metadata = json.load(bundle.extractfile(metadata_member))
        if metadata.get("version") != 1 or metadata["receipt"]["source_sha"] != source:
            raise ValueError("prepared products do not belong to this checked-out commit")
        inventory = metadata["files"]
        if not isinstance(inventory, list) or not all(isinstance(item, dict) for item in inventory):
            raise ValueError("invalid prepared artifact inventory")
        expected = {}
        for item in inventory:
            relative = PurePosixPath(item["path"])
            if relative.is_absolute() or ".." in relative.parts or str(relative) != item["path"]:
                raise ValueError("invalid prepared product path")
            if item["path"] not in (BUILD_MARKER, "compile.log") and not item["path"].startswith("Build/Products/"):
                raise ValueError("unexpected prepared product path")
            name = "products/" + item["path"]
            if name in expected:
                raise ValueError("duplicate inventory path")
            expected[name] = item
        if not {"products/" + BUILD_MARKER, "products/compile.log"}.issubset(expected):
            raise ValueError("prepared artifact requires build marker and compile evidence")
        if set(names[1:]) != set(expected) or sum(item["size"] for item in inventory) > 4 * 1024**3:
            raise ValueError("prepared artifact inventory differs from its files")
        for member in members[1:]:
            item = expected[member.name]
            if not member.isfile() or member.size != item["size"] or member.mode & 0o777 != item["mode"]:
                raise ValueError("prepared product type/size/mode differs from inventory")
            path = derived / item["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as incoming, path.open("xb") as outgoing:
                while True:
                    chunk = incoming.read(1024 * 1024)
                    if not chunk:
                        break
                    outgoing.write(chunk)
            if digest(path) != item["sha256"]:
                raise ValueError("prepared product bytes differ from inventory")
            path.chmod(item["mode"])
            os.utime(path, ns=(item["mtime_ns"], item["mtime_ns"]))
    manifest, receipt = qualify(derived, source)
    producer = metadata["receipt"]
    for key in ("source_sha", "scheme", "configuration", "format_version", "xctestrun_sha256"):
        if receipt[key] != producer[key]:
            raise ValueError("restored qualification differs from producer")
    if [item["sha256"] for item in receipt["products"]] != [item["sha256"] for item in producer["products"]]:
        raise ValueError("restored native product digests differ from producer")
    receipt["prepared_archive_sha256"] = expected_digest
    return manifest, receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("pack", "restore"))
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--sha256")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    try:
        if args.operation == "pack":
            print(pack(args.derived_data, args.source_sha, args.archive))
        else:
            if not args.sha256 or not args.receipt:
                raise ValueError("restore requires producer digest and output receipt")
            manifest, receipt = restore(args.archive, args.derived_data, args.source_sha, args.sha256)
            args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
            print(manifest)
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
