#!/usr/bin/env python3
"""Normalize UniFFI Kotlin checksum calls for Android/JNA ABI behavior.

UniFFI checksum exports return a Rust ``u16``. Some Android ABIs leave the
upper return-register bits sign-extended, while JNA direct mapping reads the
symbol as a Kotlin ``Int``. Masking to 16 bits preserves the generated expected
checksum and avoids false initialization failures when bit 15 is set.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

CHECKSUM_CALL = re.compile(
    r"if \(lib\.(uniffi_[A-Za-z0-9_]+_checksum_[A-Za-z0-9_]+)\(\) != ([0-9]+)\) \{"
)


def normalize(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    normalized, count = CHECKSUM_CALL.subn(
        r"if ((lib.\1() and 0xffff) != \2) {",
        text,
    )
    if count == 0:
        raise SystemExit(f"no UniFFI checksum calls found in {path}")
    path.write_text(normalized, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: normalize-kotlin-bindings.py <generated-kotlin-root>")
    root = Path(sys.argv[1])
    bindings = sorted(root.rglob("*uniffi.kt"))
    if not bindings:
        raise SystemExit(f"no generated UniFFI Kotlin binding found under {root}")
    for binding in bindings:
        normalize(binding)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
