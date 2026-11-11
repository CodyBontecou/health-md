#!/usr/bin/env python3
"""Bind an immutable phone release tag to its committed version and build code."""
import re
import sys


def validate(tag: str, version: str, code: str) -> None:
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("versionName must be a release semantic version")
    if not re.fullmatch(r"[1-9][0-9]*", code) or int(code) >= 1_000_000:
        raise ValueError("phone versionCode must be between 1 and 999999")
    if tag not in (f"android/v{version}", f"android/v{version}+{code}"):
        raise ValueError("release tag must match the committed versionName and optional exact versionCode")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 4:
            raise ValueError("usage: validate-phone-release-tag.py TAG VERSION CODE")
        validate(*sys.argv[1:])
    except ValueError as error:
        sys.exit(str(error))
