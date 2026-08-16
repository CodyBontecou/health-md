#!/usr/bin/env python3
"""Fully parse and verify required manually captured Wear Play PNGs."""
import argparse
from pathlib import Path
import struct
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"

def validate(path: Path) -> None:
    data = path.read_bytes()
    if not data.startswith(SIGNATURE):
        raise SystemExit(f"not a PNG: {path}")
    offset = len(SIGNATURE)
    chunks = []
    idat = bytearray()
    width = height = None
    while offset < len(data):
        if offset + 12 > len(data):
            raise SystemExit(f"truncated PNG chunk: {path}")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise SystemExit(f"truncated PNG data: {path}")
        payload = data[offset + 8:offset + 8 + length]
        expected = struct.unpack(">I", data[offset + 8 + length:end])[0]
        actual = zlib.crc32(kind + payload) & 0xffffffff
        if actual != expected:
            raise SystemExit(f"PNG CRC mismatch: {path}")
        chunks.append(kind)
        if kind == b"IHDR":
            if length != 13:
                raise SystemExit(f"invalid PNG IHDR: {path}")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if depth not in (8, 16) or color not in (0, 2, 3, 4, 6) or compression or filtering or interlace not in (0, 1):
                raise SystemExit(f"unsupported PNG encoding: {path}")
        elif kind == b"IDAT":
            idat.extend(payload)
        offset = end
        if kind == b"IEND":
            break
    if chunks[:1] != [b"IHDR"] or not idat or chunks[-1:] != [b"IEND"] or offset != len(data):
        raise SystemExit(f"invalid PNG chunk sequence: {path}")
    try:
        zlib.decompress(idat)
    except zlib.error as error:
        raise SystemExit(f"invalid compressed PNG pixels: {path}: {error}")
    if width != height or width is None or width < 400:
        raise SystemExit(f"invalid Wear screenshot geometry: {path} {width}x{height}")

parser = argparse.ArgumentParser()
parser.add_argument("--root", type=Path, default=Path("play-store/wear/screenshots"))
args = parser.parse_args()
for name in ("wear-app.png", "wear-tile.png"):
    path = args.root / name
    if not path.is_file():
        raise SystemExit(f"missing manual Wear Play screenshot: {path}")
    validate(path)
print("Wear Play screenshots valid")
