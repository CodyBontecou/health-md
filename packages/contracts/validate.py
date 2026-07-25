#!/usr/bin/env python3
"""Validate the language-neutral Health.md contract inventory and fixtures."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote

MANIFEST_SCHEMA = "healthmd.contract_manifest"
VALID_STATUSES = {"canonical", "inventory_only", "deferred"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
HEX_RE = re.compile(r"^[0-9a-f]+$")
PATH_LIST_FIELDS = ("authorities", "implementations", "consumers", "documentation")
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


class ContractValidationError(Exception):
    pass


def fail(message: str) -> None:
    raise ContractValidationError(message)


def repository_path(root: Path, raw_path: Any, context: str) -> Path:
    if not isinstance(raw_path, str) or not raw_path:
        fail(f"{context}: path must be a non-empty string")
    logical = PurePosixPath(raw_path)
    if logical.is_absolute() or ".." in logical.parts or logical.as_posix() != raw_path:
        fail(f"{context}: unsafe repository-relative path {raw_path!r}")
    candidate = (root / raw_path).resolve()
    try:
        common = os.path.commonpath((str(root), str(candidate)))
    except ValueError:
        fail(f"{context}: path escapes the repository: {raw_path}")
    if common != str(root):
        fail(f"{context}: path escapes the repository: {raw_path}")
    if not candidate.is_file():
        fail(f"{context}: file does not exist: {raw_path}")
    return candidate


def load_json(path: Path, context: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{context}: invalid UTF-8 JSON: {error}")


def decode_base64(value: Any, context: str) -> bytes:
    if not isinstance(value, str):
        fail(f"{context}: expected a base64 string")
    try:
        return base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        fail(f"{context}: invalid base64: {error}")


def decode_json_base64(value: Any, context: str) -> tuple[bytes, Any]:
    encoded = decode_base64(value, context)
    try:
        return encoded, json.loads(encoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{context}: decoded value is not UTF-8 JSON: {error}")


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def require_exact_keys(payload: Any, expected: set[str], context: str) -> dict[str, Any]:
    if not isinstance(payload, dict):
        fail(f"{context}: fixture must be a JSON object")
    actual = set(payload)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        fail(f"{context}: fixture keys differ; missing={missing}, extra={extra}")
    return payload


def validate_v1_fixture(path: Path) -> None:
    context = "healthmd.direct.ios v1 fixture"
    payload = require_exact_keys(
        load_json(path, context),
        {
            "binary_frame_base64",
            "pairing_packet_json_base64",
            "pairing_verifier_hex",
            "request_fingerprint",
            "request_json_base64",
            "request_message_json_base64",
        },
        context,
    )
    for field in ("pairing_verifier_hex", "request_fingerprint"):
        value = payload[field]
        if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
            fail(f"{context}: {field} must be lowercase SHA-256 hex")

    request_bytes, request = decode_json_base64(payload["request_json_base64"], f"{context}.request")
    if canonical_json(request) != request_bytes:
        fail(f"{context}: request JSON is not canonical sorted compact JSON")
    if hashlib.sha256(request_bytes).hexdigest() != payload["request_fingerprint"]:
        fail(f"{context}: request fingerprint does not match request bytes")

    message_bytes, message = decode_json_base64(
        payload["request_message_json_base64"], f"{context}.request_message"
    )
    if canonical_json(message) != message_bytes:
        fail(f"{context}: request message is not canonical sorted compact JSON")
    decode_json_base64(payload["pairing_packet_json_base64"], f"{context}.pairing_packet")

    frame = decode_base64(payload["binary_frame_base64"], f"{context}.binary_frame")
    if len(frame) < 66 or frame[:8] != b"HMDDIRCT":
        fail(f"{context}: invalid binary frame magic or length")
    if int.from_bytes(frame[8:10], "big") != 1:
        fail(f"{context}: binary frame version must be 1")
    sequence = int.from_bytes(frame[26:30], "big")
    byte_count = int.from_bytes(frame[30:34], "big")
    body = frame[66:]
    if sequence != 1 or byte_count != len(body):
        fail(f"{context}: binary frame sequence or byte count is invalid")
    if hashlib.sha256(body).digest() != frame[34:66]:
        fail(f"{context}: binary frame digest does not match its body")


def validate_v2_fixture(path: Path) -> None:
    context = "healthmd.direct.android v2 fixture"
    expected = {
        "android_pairing_code",
        "android_pairing_server_verifier_hex",
        "android_pairing_verifier_hex",
        "client_nonce_hex",
        "client_private_key_hex",
        "client_public_key_hex",
        "pairing_code",
        "pairing_code_key_hex",
        "pairing_server_verifier_hex",
        "pairing_verifier_hex",
        "reconnect_secret_hex",
        "request_fingerprint",
        "request_json_base64",
        "sealed_ciphertext_hex",
        "sealed_nonce_hex",
        "sealed_tag_hex",
        "server_nonce_hex",
        "server_private_key_hex",
        "server_public_key_hex",
        "session_key_hex",
        "shared_secret_hex",
        "status_request_envelope_json_base64",
        "trusted_client_verifier_hex",
        "trusted_server_verifier_hex",
    }
    payload = require_exact_keys(load_json(path, context), expected, context)

    for key, value in payload.items():
        if key.endswith("_hex"):
            if not isinstance(value, str) or len(value) % 2 != 0 or not HEX_RE.fullmatch(value):
                fail(f"{context}: {key} must be non-empty lowercase even-length hex")
    if not SHA256_RE.fullmatch(payload["request_fingerprint"]):
        fail(f"{context}: request_fingerprint must be lowercase SHA-256 hex")
    if not re.fullmatch(r"[0-9]{6}", payload["pairing_code"]):
        fail(f"{context}: pairing_code must be six digits")
    if not re.fullmatch(r"[0-9]{20}", payload["android_pairing_code"]):
        fail(f"{context}: android_pairing_code must be twenty digits")

    request_bytes, request = decode_json_base64(payload["request_json_base64"], f"{context}.request")
    if canonical_json(request) != request_bytes:
        fail(f"{context}: request JSON is not canonical sorted compact JSON")
    if hashlib.sha256(request_bytes).hexdigest() != payload["request_fingerprint"]:
        fail(f"{context}: request fingerprint does not match request bytes")

    envelope_bytes, envelope = decode_json_base64(
        payload["status_request_envelope_json_base64"], f"{context}.status_envelope"
    )
    if canonical_json(envelope) != envelope_bytes:
        fail(f"{context}: status envelope is not canonical sorted compact JSON")
    if envelope.get("protocol_version") != 2 or envelope.get("type") != "status_request":
        fail(f"{context}: status envelope does not identify protocol v2 status_request")


def validate_markdown_links(root: Path) -> int:
    checked = 0
    contracts_root = root / "packages/contracts"
    for document in sorted(contracts_root.rglob("*.md")):
        text = document.read_text(encoding="utf-8")
        for match in MARKDOWN_LINK_RE.finditer(text):
            target = match.group(1).strip()
            if target.startswith("<") and ">" in target:
                target = target[1 : target.index(">")]
            else:
                target = target.split(maxsplit=1)[0]
            if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                continue
            relative = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not relative:
                continue
            resolved = (document.parent / relative).resolve()
            try:
                common = os.path.commonpath((str(root), str(resolved)))
            except ValueError:
                common = ""
            if common != str(root):
                fail(f"{document.relative_to(root)}: link escapes the repository: {target}")
            if not resolved.exists():
                line = text.count("\n", 0, match.start()) + 1
                fail(
                    f"{document.relative_to(root)}:{line}: missing local link target {target}"
                )
            checked += 1
    return checked


def validate_manifest(root: Path) -> tuple[int, int, int]:
    manifest_path = root / "packages/contracts/manifest.json"
    manifest = load_json(manifest_path, "contract manifest")
    if not isinstance(manifest, dict):
        fail("contract manifest: top-level value must be an object")
    if manifest.get("schema") != MANIFEST_SCHEMA:
        fail(f"contract manifest: schema must be {MANIFEST_SCHEMA}")
    if type(manifest.get("schema_version")) is not int or manifest["schema_version"] != 1:
        fail("contract manifest: schema_version must be integer 1")
    contracts = manifest.get("contracts")
    if not isinstance(contracts, list) or not contracts:
        fail("contract manifest: contracts must be a non-empty array")

    identifiers: set[str] = set()
    fixture_paths: set[str] = set()
    fixture_count = 0
    mirror_count = 0

    for index, contract in enumerate(contracts):
        context = f"contracts[{index}]"
        if not isinstance(contract, dict):
            fail(f"{context}: contract must be an object")
        identifier = contract.get("id")
        if not isinstance(identifier, str) or not identifier:
            fail(f"{context}: id must be a non-empty string")
        if identifier in identifiers:
            fail(f"{context}: duplicate contract id {identifier}")
        identifiers.add(identifier)
        context = identifier

        if type(contract.get("version")) is not int or contract["version"] < 1:
            fail(f"{context}: version must be a positive integer")
        if contract.get("status") not in VALID_STATUSES:
            fail(f"{context}: status must be one of {sorted(VALID_STATUSES)}")
        if not isinstance(contract.get("summary"), str) or not contract["summary"]:
            fail(f"{context}: summary must be a non-empty string")

        specification = contract.get("specification")
        if contract["status"] == "canonical" and specification is None:
            fail(f"{context}: canonical contracts require a specification")
        if specification is not None:
            repository_path(root, specification, f"{context}.specification")

        authorities = contract.get("authorities")
        if not isinstance(authorities, list) or not authorities:
            fail(f"{context}: authorities must be a non-empty array")
        for field in PATH_LIST_FIELDS:
            values = contract.get(field, [])
            if not isinstance(values, list):
                fail(f"{context}.{field}: must be an array")
            for path_index, raw_path in enumerate(values):
                repository_path(root, raw_path, f"{context}.{field}[{path_index}]")

        fixtures = contract.get("fixtures")
        if not isinstance(fixtures, list):
            fail(f"{context}.fixtures: must be an array")
        for fixture_index, fixture in enumerate(fixtures):
            fixture_context = f"{context}.fixtures[{fixture_index}]"
            if not isinstance(fixture, dict):
                fail(f"{fixture_context}: must be an object")
            raw_path = fixture.get("path")
            fixture_path = repository_path(root, raw_path, f"{fixture_context}.path")
            if raw_path in fixture_paths:
                fail(f"{fixture_context}: duplicate canonical fixture path {raw_path}")
            fixture_paths.add(raw_path)
            declared_hash = fixture.get("sha256")
            if not isinstance(declared_hash, str) or not SHA256_RE.fullmatch(declared_hash):
                fail(f"{fixture_context}: sha256 must be lowercase SHA-256 hex")
            fixture_bytes = fixture_path.read_bytes()
            actual_hash = hashlib.sha256(fixture_bytes).hexdigest()
            if actual_hash != declared_hash:
                fail(
                    f"{fixture_context}: SHA-256 mismatch for {raw_path}; "
                    f"declared {declared_hash}, actual {actual_hash}"
                )
            load_json(fixture_path, fixture_context)
            provenance = fixture.get("provenance")
            if not isinstance(provenance, str) or not provenance:
                fail(f"{fixture_context}: provenance must be a non-empty string")
            mirrors = fixture.get("mirrors")
            if not isinstance(mirrors, list):
                fail(f"{fixture_context}.mirrors: must be an array")
            for mirror_index, mirror in enumerate(mirrors):
                mirror_path = repository_path(
                    root, mirror, f"{fixture_context}.mirrors[{mirror_index}]"
                )
                if mirror_path.read_bytes() != fixture_bytes:
                    fail(f"{fixture_context}: packaging mirror differs from {raw_path}: {mirror}")
                mirror_count += 1
            fixture_count += 1

            if identifier == "healthmd.direct.ios":
                validate_v1_fixture(fixture_path)
            elif identifier == "healthmd.direct.android":
                validate_v2_fixture(fixture_path)

    return len(contracts), fixture_count, mirror_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (defaults to the root containing packages/contracts)",
    )
    arguments = parser.parse_args()
    root = arguments.repo_root.resolve()
    try:
        contracts, fixtures, mirrors = validate_manifest(root)
        links = validate_markdown_links(root)
    except ContractValidationError as error:
        print(f"contracts validation failed: {error}", file=sys.stderr)
        return 1
    print(
        f"Validated {contracts} contracts, {fixtures} fixtures, "
        f"{mirrors} packaging mirrors, and {links} local documentation links."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
