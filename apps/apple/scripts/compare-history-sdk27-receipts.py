#!/usr/bin/env python3
"""Compare qualified SDK27 receipts without modifying their retained evidence."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

IMAGE = re.compile(r"^(ImageOS=\S+) ImageVersion=\S+$", re.MULTILINE)


def build_identity(receipt: str) -> str:
    if len(IMAGE.findall(receipt)) != 1:
        raise ValueError("receipt must contain exactly one runner image diagnostic line")
    # Hosted image rollouts can overlap jobs using the same pinned compiler,
    # SDKs and OS. Keep full receipts; exclude only this runner diagnostic from
    # their comparison. Every other byte, including ImageOS, remains binding.
    return IMAGE.sub(r"\1 ImageVersion=<runner-image-diagnostic>", receipt)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("consumer", type=Path)
    parser.add_argument("producer", type=Path)
    args = parser.parse_args()
    try:
        consumer = build_identity(args.consumer.read_bytes().decode("utf-8"))
        producer = build_identity(args.producer.read_bytes().decode("utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"::error::SDK27 provenance comparison failed: {error}", file=sys.stderr)
        return 1
    if consumer != producer:
        print("::error::SDK27 source/toolchain receipts differ", file=sys.stderr)
        return 1
    print("PASS SDK27 source/toolchain receipts match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
