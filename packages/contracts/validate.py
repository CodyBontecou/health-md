#!/usr/bin/env python3
"""Validate the language-neutral Health.md contract inventory and fixtures."""

from __future__ import annotations

import argparse
import base64
import binascii
import csv
import hashlib
import json
import math
import os
import re
import struct
import sys
from datetime import datetime
from pathlib import Path, PurePosixPath
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from typing import Any
from urllib.parse import unquote

MANIFEST_SCHEMA = "healthmd.contract_manifest"
MANIFEST_SCHEMA_VERSION = 2
PRODUCT_CAPABILITIES_SCHEMA = "healthmd.product_capabilities"
PRODUCT_CAPABILITIES_SCHEMA_VERSION = 1
METRIC_REGISTRY_SCHEMA = "healthmd.metric_registry"
METRIC_REGISTRY_SCHEMA_VERSION = 1
SHARED_SETUP_SCHEMA = "healthmd.shared_setup"
SHARED_SETUP_SCHEMA_VERSION = 1
SHARED_SETUP_MAX_BYTES = 262_144
REGISTRY_PROFILE_TO_PUBLIC = {
    "apple_health_data_v8": "apple-v8",
    "android_frozen_v4": "android-frozen-v4",
    "android_analytical_v5": "android-analytical-v5",
}
VALID_STATUSES = {"canonical", "inventory_only", "deferred"}
VALID_PRODUCTS = {"apple", "android"}
VALID_CAPABILITY_STATES = {"available", "unavailable", "planned"}
VALID_CAPABILITY_CLASSIFICATIONS = {
    "shared",
    "apple_only",
    "android_only",
    "unavailable",
    "planned",
}
VALID_PROFILE_COMPATIBILITY = {"shipped", "frozen", "additive"}
REQUIRED_OUTPUT_PROFILES = {
    "apple-v8": ("apple", "healthmd.health_data.apple", 8),
    "android-frozen-v4": ("android", "healthmd.health_data.android", 4),
    "android-analytical-v5": (
        "android",
        "healthmd.health_data.android_analytical",
        5,
    ),
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
HEX_RE = re.compile(r"^[0-9a-f]+$")
IDENTIFIER_RE = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
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
        fail(f"{context}: value must be a JSON object")
    actual = set(payload)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        fail(f"{context}: object keys differ; missing={missing}, extra={extra}")
    return payload


def require_unique_string_array(
    value: Any,
    context: str,
    *,
    allow_empty: bool = True,
) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        fail(f"{context}: must be an array of strings")
    if not allow_empty and not value:
        fail(f"{context}: must not be empty")
    if len(value) != len(set(value)):
        fail(f"{context}: must not contain duplicates")
    return value


def validate_json_schema_subset(instance: Any, schema: dict[str, Any], context: str) -> None:
    """Validate the draft-2020-12 keywords used by local typed-provider fixtures."""

    root = schema

    def resolve(reference: str, schema_context: str) -> dict[str, Any]:
        if not reference.startswith("#/"):
            fail(f"{schema_context}: only local JSON Schema references are supported")
        value: Any = root
        for raw_part in reference[2:].split("/"):
            part = raw_part.replace("~1", "/").replace("~0", "~")
            if not isinstance(value, dict) or part not in value:
                fail(f"{schema_context}: unresolved JSON Schema reference {reference}")
            value = value[part]
        if not isinstance(value, dict):
            fail(f"{schema_context}: JSON Schema reference {reference} is not an object")
        return value

    def matches(value: Any, candidate: dict[str, Any], value_context: str) -> bool:
        try:
            validate(value, candidate, value_context)
            return True
        except ContractValidationError:
            return False

    def has_type(value: Any, expected: str) -> bool:
        if expected == "object":
            return isinstance(value, dict)
        if expected == "array":
            return isinstance(value, list)
        if expected == "string":
            return isinstance(value, str)
        if expected == "integer":
            return isinstance(value, int) and not isinstance(value, bool)
        if expected == "number":
            return isinstance(value, (int, float)) and not isinstance(value, bool)
        if expected == "boolean":
            return isinstance(value, bool)
        if expected == "null":
            return value is None
        fail(f"{context}: unsupported JSON Schema type {expected!r}")

    def validate(value: Any, candidate: dict[str, Any], value_context: str) -> None:
        reference = candidate.get("$ref")
        if reference is not None:
            if not isinstance(reference, str):
                fail(f"{value_context}: JSON Schema $ref must be a string")
            validate(value, resolve(reference, value_context), value_context)

        for index, branch in enumerate(candidate.get("allOf", [])):
            validate(value, branch, f"{value_context}.allOf[{index}]")
        if "oneOf" in candidate:
            branches = candidate["oneOf"]
            match_count = sum(
                matches(value, branch, f"{value_context}.oneOf[{index}]")
                for index, branch in enumerate(branches)
            )
            if match_count != 1:
                fail(f"{value_context}: expected exactly one matching oneOf branch, got {match_count}")
        if "not" in candidate and matches(value, candidate["not"], f"{value_context}.not"):
            fail(f"{value_context}: value matches forbidden JSON Schema branch")
        if "if" in candidate and matches(value, candidate["if"], f"{value_context}.if"):
            if "then" in candidate:
                validate(value, candidate["then"], f"{value_context}.then")
        elif "else" in candidate:
            validate(value, candidate["else"], f"{value_context}.else")

        def json_equal(left: Any, right: Any) -> bool:
            if isinstance(left, bool) or isinstance(right, bool):
                return isinstance(left, bool) and isinstance(right, bool) and left == right
            if isinstance(left, (int, float)) and isinstance(right, (int, float)):
                return not isinstance(left, bool) and not isinstance(right, bool) and left == right
            return type(left) is type(right) and left == right

        if "const" in candidate and not json_equal(value, candidate["const"]):
            fail(f"{value_context}: value does not match JSON Schema const")
        if "enum" in candidate and not any(json_equal(value, item) for item in candidate["enum"]):
            fail(f"{value_context}: value is not in the JSON Schema enum")

        expected_types = candidate.get("type")
        if isinstance(expected_types, str):
            expected_types = [expected_types]
        if expected_types is not None:
            if not isinstance(expected_types, list) or not all(
                isinstance(item, str) for item in expected_types
            ):
                fail(f"{value_context}: JSON Schema type must be a string or string array")
            if not any(has_type(value, expected) for expected in expected_types):
                fail(f"{value_context}: value has the wrong JSON type")

        if isinstance(value, dict):
            minimum = candidate.get("minProperties")
            maximum = candidate.get("maxProperties")
            if minimum is not None and len(value) < minimum:
                fail(f"{value_context}: object has fewer than {minimum} properties")
            if maximum is not None and len(value) > maximum:
                fail(f"{value_context}: object has more than {maximum} properties")
            required = candidate.get("required", [])
            missing = [key for key in required if key not in value]
            if missing:
                fail(f"{value_context}: missing required properties {missing}")
            property_schema = candidate.get("propertyNames")
            if property_schema is not None:
                for key in value:
                    validate(key, property_schema, f"{value_context}.propertyNames[{key!r}]")
            properties = candidate.get("properties", {})
            for key, child in value.items():
                if key in properties:
                    validate(child, properties[key], f"{value_context}.{key}")
                    continue
                additional = candidate.get("additionalProperties", True)
                if additional is False:
                    fail(f"{value_context}: additional property {key!r} is forbidden")
                if isinstance(additional, dict):
                    validate(child, additional, f"{value_context}.{key}")

        if isinstance(value, list):
            minimum = candidate.get("minItems")
            maximum = candidate.get("maxItems")
            if minimum is not None and len(value) < minimum:
                fail(f"{value_context}: array has fewer than {minimum} items")
            if maximum is not None and len(value) > maximum:
                fail(f"{value_context}: array has more than {maximum} items")
            if candidate.get("uniqueItems") is True:
                encoded = [canonical_json(item) for item in value]
                if len(encoded) != len(set(encoded)):
                    fail(f"{value_context}: array items must be unique")
            item_schema = candidate.get("items")
            if isinstance(item_schema, dict):
                for index, child in enumerate(value):
                    validate(child, item_schema, f"{value_context}[{index}]")
            contains = candidate.get("contains")
            if isinstance(contains, dict):
                count = sum(
                    matches(child, contains, f"{value_context}.contains[{index}]")
                    for index, child in enumerate(value)
                )
                if count < candidate.get("minContains", 1):
                    fail(f"{value_context}: array does not satisfy minContains")
                if "maxContains" in candidate and count > candidate["maxContains"]:
                    fail(f"{value_context}: array exceeds maxContains")

        if isinstance(value, str):
            minimum = candidate.get("minLength")
            maximum = candidate.get("maxLength")
            if minimum is not None and len(value) < minimum:
                fail(f"{value_context}: string is shorter than {minimum} characters")
            if maximum is not None and len(value) > maximum:
                fail(f"{value_context}: string is longer than {maximum} characters")
            pattern = candidate.get("pattern")
            if pattern is not None and re.search(pattern, value) is None:
                fail(f"{value_context}: string does not match JSON Schema pattern")
            if candidate.get("format") == "date":
                try:
                    datetime.strptime(value, "%Y-%m-%d")
                except ValueError as error:
                    fail(f"{value_context}: invalid calendar date: {error}")
            if candidate.get("format") == "date-time":
                try:
                    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
                except ValueError as error:
                    fail(f"{value_context}: invalid RFC 3339 date-time: {error}")
                if parsed.tzinfo is None:
                    fail(f"{value_context}: date-time must include an offset")

        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if not math.isfinite(value):
                fail(f"{value_context}: JSON number must be finite")
            if "minimum" in candidate and value < candidate["minimum"]:
                fail(f"{value_context}: number is below minimum")
            if "maximum" in candidate and value > candidate["maximum"]:
                fail(f"{value_context}: number is above maximum")
            if "exclusiveMinimum" in candidate and value <= candidate["exclusiveMinimum"]:
                fail(f"{value_context}: number is not above exclusiveMinimum")
            if "exclusiveMaximum" in candidate and value >= candidate["exclusiveMaximum"]:
                fail(f"{value_context}: number is not below exclusiveMaximum")

    validate(instance, schema, context)


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


def validate_profile_policy_fixture(path: Path) -> None:
    context = "healthmd.direct.ios profile policy fixture"
    payload = require_exact_keys(
        load_json(path, context),
        {
            "schema",
            "schema_version",
            "profile_request_json_base64",
            "profile_request_message_json_base64",
            "profile_request_fingerprint",
            "profile_request_unnamed_reference_json_base64",
        },
        context,
    )
    if (
        payload["schema"] != "healthmd.direct_profile_policy_swift_reference"
        or payload["schema_version"] != 1
    ):
        fail(f"{context}: schema metadata is invalid")

    fingerprint = payload["profile_request_fingerprint"]
    if not isinstance(fingerprint, str) or not SHA256_RE.fullmatch(fingerprint):
        fail(f"{context}: profile_request_fingerprint must be lowercase SHA-256 hex")

    request_bytes, request = decode_json_base64(
        payload["profile_request_json_base64"], f"{context}.profile_request"
    )
    if canonical_json(request) != request_bytes:
        fail(f"{context}: profile request JSON is not canonical sorted compact JSON")
    if hashlib.sha256(request_bytes).hexdigest() != fingerprint:
        fail(f"{context}: fingerprint does not match profile request bytes")
    reference = request.get("profileReference")
    if request.get("settingsPolicy") != "profile" or not isinstance(reference, dict):
        fail(f"{context}: profile request must pin settings_policy=profile with a reference")
    if not isinstance(reference.get("profileID"), str) or not reference["profileID"]:
        fail(f"{context}: profileReference.profileID must be a non-empty string")
    if not isinstance(reference.get("name"), str):
        fail(f"{context}: named-reference vector must carry a name")

    message_bytes, message = decode_json_base64(
        payload["profile_request_message_json_base64"], f"{context}.profile_request_message"
    )
    if canonical_json(message) != message_bytes:
        fail(f"{context}: profile request message is not canonical sorted compact JSON")
    if message.get("exportRequest", {}).get("_0") != request:
        fail(f"{context}: message envelope must wrap the profile request unchanged")

    unnamed_bytes, unnamed = decode_json_base64(
        payload["profile_request_unnamed_reference_json_base64"],
        f"{context}.profile_request_unnamed_reference",
    )
    if canonical_json(unnamed) != unnamed_bytes:
        fail(f"{context}: unnamed-reference JSON is not canonical sorted compact JSON")
    unnamed_reference = unnamed.get("profileReference")
    if unnamed.get("settingsPolicy") != "profile":
        fail(f"{context}: unnamed-reference vector must pin settings_policy=profile")
    if not isinstance(unnamed_reference, dict) or "name" in unnamed_reference:
        fail(f"{context}: unnamed-reference vector must omit the name field")


def validate_semantic_fixture(root: Path, path: Path) -> None:
    context = "healthmd.semantic_input v1 fixture"
    payload = require_exact_keys(
        load_json(path, context),
        {
            "schema",
            "fixture_version",
            "semantic_input_version",
            "canonical_model_version",
            "registry_sha256",
            "cases",
            "rejection_cases",
        },
        context,
    )
    if path.read_bytes() != canonical_json(payload) + b"\n":
        fail(f"{context}: fixture must be canonical sorted compact JSON with one newline")
    if (
        payload["schema"] != "healthmd.semantic_differential_fixture"
        or payload["fixture_version"] != 1
        or payload["semantic_input_version"] != 1
        or payload["canonical_model_version"] != 1
        or not isinstance(payload["registry_sha256"], str)
        or not SHA256_RE.fullmatch(payload["registry_sha256"])
    ):
        fail(f"{context}: fixture metadata is invalid")

    registry_path = repository_path(
        root,
        "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json",
        f"{context}.registry",
    )
    if hashlib.sha256(registry_path.read_bytes()).hexdigest() != payload["registry_sha256"]:
        fail(f"{context}: registry hash does not match the canonical metric registry")

    for schema_name in ("semantic-input.schema.json", "semantic-result.schema.json"):
        schema_path = repository_path(
            root,
            f"packages/contracts/semantic-input/v1/{schema_name}",
            f"{context}.{schema_name}",
        )
        schema = load_json(schema_path, f"{context}.{schema_name}")
        if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            fail(f"{context}: {schema_name} must use JSON Schema draft 2020-12")

    cases = payload["cases"]
    if not isinstance(cases, list) or len(cases) != 3:
        fail(f"{context}.cases: expected three reviewed cross-language cases")
    case_ids: set[str] = set()
    covered: set[str] = set()
    for index, case in enumerate(cases):
        case_context = f"{context}.cases[{index}]"
        case = require_exact_keys(
            case,
            {"id", "features", "config", "batches", "expected_result_sha256"},
            case_context,
        )
        case_id = case["id"]
        if not isinstance(case_id, str) or not IDENTIFIER_RE.fullmatch(case_id) or case_id in case_ids:
            fail(f"{case_context}.id: must be a unique stable identifier")
        case_ids.add(case_id)
        features = require_unique_string_array(case["features"], f"{case_context}.features", allow_empty=False)
        covered.update(features)
        expected_hash = case["expected_result_sha256"]
        if not isinstance(expected_hash, str) or not SHA256_RE.fullmatch(expected_hash):
            fail(f"{case_context}.expected_result_sha256: invalid SHA-256")
        config = require_exact_keys(
            case["config"],
            {
                "schema", "semantic_input_version", "canonical_model_version",
                "registry_version", "registry_sha256", "profile_revision", "session_id", "profile",
                "calendar_time_zone", "selected_selection_ids", "disabled_output_keys",
                "retain_platform_extensions", "rollup_periods",
            },
            f"{case_context}.config",
        )
        if (
            config["schema"] != "healthmd.semantic_session_config"
            or config["semantic_input_version"] != 1
            or config["canonical_model_version"] != 1
            or config["registry_version"] != 1
            or config["registry_sha256"] != payload["registry_sha256"]
            or config["profile_revision"] != 1
            or config["profile"] not in REGISTRY_PROFILE_TO_PUBLIC
            or not isinstance(config["calendar_time_zone"], str)
            or not config["calendar_time_zone"]
            or type(config["retain_platform_extensions"]) is not bool
        ):
            fail(f"{case_context}.config: invalid version/profile/timezone metadata")
        require_unique_string_array(
            config["selected_selection_ids"],
            f"{case_context}.config.selected_selection_ids",
            allow_empty=True,
        )
        require_unique_string_array(
            config["disabled_output_keys"],
            f"{case_context}.config.disabled_output_keys",
            allow_empty=True,
        )
        require_unique_string_array(config["rollup_periods"], f"{case_context}.config.rollup_periods")
        batches = case["batches"]
        if not isinstance(batches, list) or not batches:
            fail(f"{case_context}.batches: must not be empty")
        previous_ordinal = -1
        previous_date = ""
        for batch_index, batch in enumerate(batches):
            batch_context = f"{case_context}.batches[{batch_index}]"
            batch = require_exact_keys(
                batch,
                {"schema", "semantic_input_version", "session_id", "batch_index", "final_batch", "owner_dates", "records"},
                batch_context,
            )
            if (
                batch["schema"] != "healthmd.semantic_input"
                or batch["semantic_input_version"] != 1
                or batch["session_id"] != config["session_id"]
                or batch["batch_index"] != batch_index
                or batch["final_batch"] != (batch_index == len(batches) - 1)
                or not isinstance(batch["owner_dates"], list)
                or len(batch["owner_dates"]) > 400
                or batch["owner_dates"] != sorted(set(batch["owner_dates"]))
                or not isinstance(batch["records"], list)
                or len(batch["records"]) > 4096
            ):
                fail(f"{batch_context}: invalid batch sequence or bounds")
            for record_index, record in enumerate(batch["records"]):
                record_context = f"{batch_context}.records[{record_index}]"
                record = require_exact_keys(
                    record,
                    {
                        "record_id", "source_ordinal", "owner_date", "semantic_id",
                        "selection_ids", "attribution", "kind", "output_key", "aggregation",
                        "start", "end", "value", "weight", "attributes", "extensions",
                    },
                    record_context,
                )
                if (
                    not isinstance(record["record_id"], str)
                    or not isinstance(record["semantic_id"], str)
                    or record["attribution"] not in {"direct", "dependency"}
                    or record["kind"] not in {
                        "observation", "sdk_aggregate", "workout", "state_of_mind",
                        "category", "extension_ref",
                    }
                    or not isinstance(record["attributes"], dict)
                    or not isinstance(record["extensions"], list)
                ):
                    fail(f"{record_context}: record does not satisfy the semantic-input schema")
                require_unique_string_array(record["selection_ids"], f"{record_context}.selection_ids", allow_empty=False)
                ordinal = record.get("source_ordinal")
                owner_date = record.get("owner_date")
                if not isinstance(ordinal, str) or not re.fullmatch(r"0|[1-9][0-9]*", ordinal):
                    fail(f"{record_context}.source_ordinal: invalid canonical integer")
                if int(ordinal) <= previous_ordinal:
                    fail(f"{record_context}.source_ordinal: sequence must be strictly ascending")
                if not isinstance(owner_date, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", owner_date):
                    fail(f"{record_context}.owner_date: invalid date")
                if owner_date not in batch["owner_dates"]:
                    fail(f"{record_context}.owner_date: date was not declared by its batch")
                if owner_date < previous_date:
                    fail(f"{record_context}.owner_date: dates must be nondecreasing")
                previous_ordinal = int(ordinal)
                previous_date = owner_date
                for extension_index, extension in enumerate(record["extensions"]):
                    extension_context = f"{record_context}.extensions[{extension_index}]"
                    extension = require_exact_keys(
                        extension,
                        {"namespace", "version", "retention_token", "selection_ids"},
                        extension_context,
                    )
                    if (
                        not isinstance(extension["namespace"], str)
                        or type(extension["version"]) is not int
                        or extension["version"] < 1
                        or not isinstance(extension["retention_token"], str)
                    ):
                        fail(f"{extension_context}: extension does not satisfy the schema")
                    require_unique_string_array(
                        extension["selection_ids"],
                        f"{extension_context}.selection_ids",
                        allow_empty=False,
                    )

                def walk(value: Any, walk_context: str) -> None:
                    if isinstance(value, dict):
                        if value.get("representation") == "binary64":
                            bits = value.get("bits")
                            if not isinstance(bits, str) or not re.fullmatch(r"[0-9a-f]{16}", bits):
                                fail(f"{walk_context}: invalid binary64 bits")
                            number = struct.unpack(">d", bytes.fromhex(bits))[0]
                            if not math.isfinite(number):
                                fail(f"{walk_context}: non-finite binary64 is forbidden")
                        if "nanoseconds" in value:
                            nanos = value.get("nanoseconds")
                            if type(nanos) is not int or not 0 <= nanos <= 999_999_999:
                                fail(f"{walk_context}: nanoseconds out of range")
                        for key, child in value.items():
                            walk(child, f"{walk_context}.{key}")
                    elif isinstance(value, list):
                        for child_index, child in enumerate(value):
                            walk(child, f"{walk_context}[{child_index}]")

                walk(record, record_context)

    rejection_cases = payload["rejection_cases"]
    if not isinstance(rejection_cases, list) or len(rejection_cases) != 3:
        fail(f"{context}.rejection_cases: expected three reviewed rejection cases")
    for index, case in enumerate(rejection_cases):
        case = require_exact_keys(
            case,
            {"id", "expected_error", "feature"},
            f"{context}.rejection_cases[{index}]",
        )
        if not all(isinstance(case[field], str) and case[field] for field in case):
            fail(f"{context}.rejection_cases[{index}]: values must be non-empty strings")
        covered.add(case["feature"])

    required_features = {
        "missing-versus-zero", "nanoseconds", "nullable-source-offset", "non-hour-offset", "dst-offset-transition",
        "iso-week-year-boundary", "blood-pressure-dependency", "state-of-mind-independent-views",
        "sleep-stage-platform-differences", "android-percentage-fraction", "vo2-latest-lower-value", "workout-duration-weighting",
        "unknown-extension-retention", "batch-boundary-invariance", "reject-nan-and-infinity",
        "batch-order-and-bounds", "cancellation-and-terminal-state",
    }
    if not required_features.issubset(covered):
        fail(f"{context}: missing required differential features {sorted(required_features - covered)}")


def validate_render_fixture(root: Path, path: Path) -> None:
    for schema_name in ("render-input.schema.json", "artifact-plan.schema.json"):
        schema_path = repository_path(
            root,
            f"packages/contracts/render-input/v1/{schema_name}",
            f"healthmd.render_input {schema_name}",
        )
        schema = load_json(schema_path, f"healthmd.render_input {schema_name}")
        if not isinstance(schema, dict) or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            fail(f"healthmd.render_input: invalid {schema_name}")

    payload = load_json(path, "healthmd.render_input v1 fixture")
    if isinstance(payload, dict) and payload.get("schema") == "healthmd.native_renderer_goldens":
        validate_native_renderer_golden(path)
        return
    if isinstance(payload, dict) and payload.get("schema") == "healthmd.native_render_requests":
        validate_native_render_requests(path)
        return
    if isinstance(payload, dict) and payload.get("schema") == "healthmd.markdown_merge_vectors":
        validate_markdown_merge_vectors(payload)
        return
    payload = require_exact_keys(
        payload,
        {"schema", "schema_version", "render_input_version", "artifact_plan_version", "registry_sha256", "cases"},
        "healthmd.render differential",
    )
    if (
        payload["schema"] != "healthmd.render_differential"
        or payload["schema_version"] != 1
        or payload["render_input_version"] != 1
        or payload["artifact_plan_version"] != 1
        or payload["registry_sha256"]
        != "3f21e560d2d27a4ec1055327b97bc194b847d64ca5ff250d1216e94a71a2586f"
    ):
        fail("healthmd.render differential: version or registry pin is invalid")
    cases = payload.get("cases")
    if not isinstance(cases, list) or len(cases) != 3:
        fail("healthmd.render differential: exactly three profile cases are required")
    profiles: set[str] = set()
    for index, case in enumerate(cases):
        context = f"healthmd.render differential cases[{index}]"
        case = require_exact_keys(
            case,
            {"id", "profile", "configuration", "semantic_result", "batches", "expected_plan"},
            context,
        )
        profile = case.get("profile")
        if profile not in {"apple_health_data_v8", "android_frozen_v4", "android_analytical_v5"} or profile in profiles:
            fail(f"{context}: profile is invalid or duplicated")
        profiles.add(profile)
        configuration = case.get("configuration")
        if not isinstance(configuration, dict):
            fail(f"{context}.configuration: must be an object")
        if (
            configuration.get("schema") != "healthmd.render_session_config"
            or configuration.get("render_input_version") != 1
            or configuration.get("artifact_plan_version") != 1
            or configuration.get("profile") != profile
            or configuration.get("registry_sha256") != payload["registry_sha256"]
            or configuration.get("locale") != "en-US"
        ):
            fail(f"{context}.configuration: version/profile pins are invalid")
        semantic = case.get("semantic_result")
        if not isinstance(semantic, dict) or semantic.get("schema") != "healthmd.semantic_result" or semantic.get("state") != "completed":
            fail(f"{context}.semantic_result: completed semantic result is required")
        if semantic.get("profile") != profile or semantic.get("session_id") != configuration.get("session_id"):
            fail(f"{context}: semantic/configuration identity mismatch")
        batches = case.get("batches")
        if not isinstance(batches, list) or not batches:
            fail(f"{context}.batches: non-empty array required")
        for batch_index, batch in enumerate(batches):
            if not isinstance(batch, dict) or batch.get("schema") != "healthmd.render_input" or batch.get("render_input_version") != 1:
                fail(f"{context}.batches[{batch_index}]: invalid batch")
            if batch.get("batch_index") != batch_index or batch.get("session_id") != configuration.get("session_id"):
                fail(f"{context}.batches[{batch_index}]: sequence/identity mismatch")
            if batch.get("final_batch") is not (batch_index == len(batches) - 1):
                fail(f"{context}.batches[{batch_index}]: final_batch mismatch")
        plan = case.get("expected_plan")
        plan = require_exact_keys(
            plan,
            {"schema", "artifact_plan_version", "request_id", "session_id", "profile", "total_byte_count", "items"},
            f"{context}.expected_plan",
        )
        if plan["schema"] != "healthmd.artifact_plan" or plan["artifact_plan_version"] != 1 or plan["profile"] != profile:
            fail(f"{context}.expected_plan: profile/version mismatch")
        if plan["request_id"] != configuration.get("request_id") or plan["session_id"] != configuration.get("session_id"):
            fail(f"{context}.expected_plan: identity mismatch")
        items = plan.get("items")
        if not isinstance(items, list) or not items:
            fail(f"{context}.expected_plan.items: non-empty array required")
        paths: set[str] = set()
        total = 0
        for item_index, item in enumerate(items):
            item_context = f"{context}.expected_plan.items[{item_index}]"
            item = require_exact_keys(
                item,
                {"artifact_id", "relative_path", "media_type", "write_mode", "byte_count", "sha256", "content_base64"},
                item_context,
            )
            for digest_key in ("artifact_id", "sha256"):
                if not isinstance(item[digest_key], str) or not SHA256_RE.fullmatch(item[digest_key]):
                    fail(f"{item_context}.{digest_key}: invalid SHA-256")
            logical = PurePosixPath(item["relative_path"])
            if logical.is_absolute() or not logical.parts or any(part in {"", ".", ".."} for part in logical.parts):
                fail(f"{item_context}: unsafe relative path")
            collision = item["relative_path"].casefold()
            if collision in paths:
                fail(f"{item_context}: duplicate/case-colliding path")
            paths.add(collision)
            content = decode_base64(item["content_base64"], f"{item_context}.content_base64")
            if item["byte_count"] != len(content) or item["sha256"] != hashlib.sha256(content).hexdigest():
                fail(f"{item_context}: content descriptor mismatch")
            total += len(content)
        if plan["total_byte_count"] != total:
            fail(f"{context}.expected_plan: total_byte_count mismatch")


def validate_markdown_merge_vectors(payload: object) -> None:
    payload = require_exact_keys(
        payload,
        {"schema", "schema_version", "render_profile_revision", "vectors"},
        "managed Markdown merge vectors",
    )
    if (
        payload["schema"] != "healthmd.markdown_merge_vectors"
        or payload["schema_version"] != 1
        or payload["render_profile_revision"] != 2
    ):
        fail("managed Markdown merge vectors: version pins are invalid")
    vectors = payload.get("vectors")
    if not isinstance(vectors, list) or not vectors:
        fail("managed Markdown merge vectors: non-empty vectors are required")
    identifiers: set[str] = set()
    for index, vector in enumerate(vectors):
        context = f"managed Markdown merge vectors[{index}]"
        vector = require_exact_keys(
            vector,
            {"id", "existing", "generated", "preserve_preamble", "outcome", "expected"},
            context,
        )
        identifier = vector.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER_RE.fullmatch(identifier) or identifier in identifiers:
            fail(f"{context}.id: invalid or duplicated")
        identifiers.add(identifier)
        if not isinstance(vector.get("existing"), str) or not isinstance(vector.get("generated"), str):
            fail(f"{context}: existing/generated must be strings")
        if type(vector.get("preserve_preamble")) is not bool:
            fail(f"{context}.preserve_preamble: must be Boolean")
        outcome = vector.get("outcome")
        expected = vector.get("expected")
        if outcome == "merged":
            if not isinstance(expected, str):
                fail(f"{context}.expected: merged vectors require exact bytes")
        elif outcome == "rejected":
            if expected is not None:
                fail(f"{context}.expected: rejected vectors must use null")
        else:
            fail(f"{context}.outcome: unsupported value")


def validate_native_render_requests(path: Path) -> None:
    payload = load_json(path, "native render requests")
    payload = require_exact_keys(
        payload,
        {"schema", "schema_version", "render_input_version", "artifact_plan_version", "cases"},
        "native render requests",
    )
    if (
        payload["schema"] != "healthmd.native_render_requests"
        or payload["schema_version"] != 1
        or payload["render_input_version"] != 1
        or payload["artifact_plan_version"] != 1
    ):
        fail("native render requests: version pins are invalid")
    cases = payload.get("cases")
    if not isinstance(cases, list) or not cases:
        fail("native render requests: non-empty cases are required")
    identifiers: set[str] = set()
    for case_index, case in enumerate(cases):
        context = f"native render requests cases[{case_index}]"
        if not isinstance(case, dict):
            fail(f"{context}: must be an object")
        full_outputs = "expected_outputs" in case
        expected_keys = (
            {"id", "profile", "semantic_result", "configuration", "batches", "expected_outputs"}
            if full_outputs
            else {
                "id", "profile", "semantic_result", "configuration", "batches",
                "expected_relative_path", "expected_media_type", "expected_bytes_base64",
                "expected_byte_count", "expected_sha256",
            }
        )
        case = require_exact_keys(case, expected_keys, context)
        identifier = case.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER_RE.fullmatch(identifier) or identifier in identifiers:
            fail(f"{context}: id is invalid or duplicated")
        identifiers.add(identifier)
        profile = case.get("profile")
        if profile not in {"android_frozen_v4", "android_analytical_v5"}:
            fail(f"{context}: profile is invalid")
        configuration = case.get("configuration")
        if not isinstance(configuration, dict) or configuration.get("schema") != "healthmd.render_session_config":
            fail(f"{context}: configuration is invalid")
        if configuration.get("profile") != profile or configuration.get("render_input_version") != 1:
            fail(f"{context}: configuration profile/version mismatch")
        semantic = case.get("semantic_result")
        if not isinstance(semantic, dict) or semantic.get("schema") != "healthmd.semantic_result":
            fail(f"{context}: semantic result is invalid")
        if semantic.get("profile") != profile or semantic.get("state") != "completed":
            fail(f"{context}: semantic profile/state mismatch")
        batches = case.get("batches")
        if not isinstance(batches, list) or not batches:
            fail(f"{context}: batches are required")
        for batch_index, batch in enumerate(batches):
            if not isinstance(batch, dict) or batch.get("schema") != "healthmd.render_input":
                fail(f"{context}.batches[{batch_index}]: invalid batch")
            if batch.get("batch_index") != batch_index or batch.get("final_batch") is not (batch_index == len(batches) - 1):
                fail(f"{context}.batches[{batch_index}]: invalid sequence")
        if full_outputs:
            outputs = case.get("expected_outputs")
            if not isinstance(outputs, list) or len(outputs) != 4:
                fail(f"{context}: exactly four expected outputs are required")
        else:
            outputs = [{
                "format": "obsidian_bases",
                "relative_path": case["expected_relative_path"],
                "media_type": case["expected_media_type"],
                "bytes_base64": case["expected_bytes_base64"],
                "byte_count": case["expected_byte_count"],
                "sha256": case["expected_sha256"],
            }]
        formats: set[str] = set()
        for output_index, output in enumerate(outputs):
            output_context = f"{context}.expected_outputs[{output_index}]"
            output = require_exact_keys(
                output,
                {"format", "relative_path", "media_type", "bytes_base64", "byte_count", "sha256"},
                output_context,
            )
            output_format = output.get("format")
            if output_format not in {"markdown", "obsidian_bases", "json", "csv"} or output_format in formats:
                fail(f"{output_context}: format is invalid or duplicated")
            formats.add(output_format)
            if not isinstance(output.get("relative_path"), str) or not isinstance(output.get("media_type"), str):
                fail(f"{output_context}: path/media type is invalid")
            raw = decode_base64(output.get("bytes_base64"), f"{output_context}.bytes_base64")
            if output.get("byte_count") != len(raw) or hashlib.sha256(raw).hexdigest() != output.get("sha256"):
                fail(f"{output_context}: byte evidence mismatch")


def validate_native_renderer_golden(path: Path) -> None:
    payload = load_json(path, "native renderer golden")
    if not isinstance(payload, dict) or payload.get("schema") != "healthmd.native_renderer_goldens":
        fail(f"native renderer golden: invalid schema in {path}")
    if payload.get("schema_version") != 1:
        fail(f"native renderer golden: unsupported version in {path}")

    is_apple = payload.get("profile") == "apple-v7"
    if is_apple:
        require_exact_keys(
            payload,
            {"schema", "schema_version", "profile", "public_schema", "public_schema_version", "cases"},
            "native Apple renderer golden",
        )
        if payload["public_schema"] != "healthmd.health_data" or payload["public_schema_version"] != 7:
            fail("native Apple renderer golden: public schema pin is invalid")
    else:
        require_exact_keys(
            payload,
            {"schema", "schema_version", "profiles", "public_schema", "cases"},
            "native Android renderer golden",
        )
        if payload["profiles"] != ["android-frozen-v4", "android-analytical-v5"]:
            fail("native Android renderer golden: profile pins are invalid")
        if payload["public_schema"] != "healthmd.health_data":
            fail("native Android renderer golden: public schema pin is invalid")

    cases = payload.get("cases")
    if not isinstance(cases, list) or not cases:
        fail("native renderer golden: cases must be a non-empty array")
    case_ids: set[str] = set()
    for case_index, case in enumerate(cases):
        context = f"native renderer golden cases[{case_index}]"
        if not isinstance(case, dict):
            fail(f"{context}: must be an object")
        required = {"id", "outputs"} if is_apple else {"id", "profile", "granular", "outputs"}
        case = require_exact_keys(case, required, context)
        case_id = case.get("id")
        if not isinstance(case_id, str) or not IDENTIFIER_RE.fullmatch(case_id):
            fail(f"{context}: id is invalid")
        if case_id in case_ids:
            fail(f"{context}: duplicate id")
        case_ids.add(case_id)
        profile = "apple-v7" if is_apple else case.get("profile")
        if profile not in {"apple-v7", "android-frozen-v4", "android-analytical-v5"}:
            fail(f"{context}: profile is invalid")
        if not is_apple and type(case.get("granular")) is not bool:
            fail(f"{context}: granular must be Boolean")

        outputs = case.get("outputs")
        if not isinstance(outputs, list) or len(outputs) != 4:
            fail(f"{context}: exactly four format outputs are required")
        formats: set[str] = set()
        for output_index, output in enumerate(outputs):
            output_context = f"{context}.outputs[{output_index}]"
            output = require_exact_keys(
                output,
                {"format", "media_type", "byte_count", "sha256", "bytes_base64"},
                output_context,
            )
            output_format = output.get("format")
            if output_format not in {"markdown", "obsidian_bases", "json", "csv"}:
                fail(f"{output_context}: format is invalid")
            if output_format in formats:
                fail(f"{output_context}: duplicate format")
            formats.add(output_format)
            media_type = output.get("media_type")
            if not isinstance(media_type, str) or not media_type:
                fail(f"{output_context}: media_type is invalid")
            raw = decode_base64(output.get("bytes_base64"), f"{output_context}.bytes_base64")
            byte_count = output.get("byte_count")
            if type(byte_count) is not int or byte_count != len(raw):
                fail(f"{output_context}: byte_count mismatch")
            digest = output.get("sha256")
            if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
                fail(f"{output_context}: sha256 is invalid")
            if hashlib.sha256(raw).hexdigest() != digest:
                fail(f"{output_context}: sha256 mismatch")
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                fail(f"{output_context}: output is not UTF-8")
            if output_format == "json":
                try:
                    public_json = json.loads(text)
                except json.JSONDecodeError:
                    fail(f"{output_context}: JSON output is invalid")
                if profile == "apple-v7":
                    if public_json.get("schema") != "healthmd.health_data" or public_json.get("schema_version") != 7:
                        fail(f"{output_context}: Apple v7 discriminator mismatch")
                elif profile == "android-frozen-v4":
                    if "schemaProfile" in public_json or "schemaVersion" in public_json:
                        fail(f"{output_context}: frozen v4 gained analytical discriminators")
                elif public_json.get("schemaProfile") != "android-analytical-v5" or public_json.get("schemaVersion") != 5:
                    fail(f"{output_context}: Android analytical-v5 discriminator mismatch")
            elif output_format == "csv" and not text.startswith("Date,Category,Metric,Value,Unit,Timestamp\n"):
                fail(f"{output_context}: CSV header mismatch")

        if formats != {"markdown", "obsidian_bases", "json", "csv"}:
            fail(f"{context}: format coverage is incomplete")


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


def validate_v2_profile_policy_fixture(path: Path) -> None:
    context = "healthmd.direct.android v2 profile-policy fixture"
    payload = require_exact_keys(
        load_json(path, context),
        {
            "envelope_json_base64",
            "request_fingerprint",
            "request_json_base64",
            "request_unnamed_reference_json_base64",
            "schema",
            "schema_version",
        },
        context,
    )
    if payload["schema"] != "healthmd.direct_v2_profile_policy_reference":
        fail(f"{context}: schema discriminator mismatch")
    if payload["schema_version"] != 1:
        fail(f"{context}: schema version must be 1")
    if not isinstance(payload["request_fingerprint"], str) or not SHA256_RE.fullmatch(
        payload["request_fingerprint"]
    ):
        fail(f"{context}: request_fingerprint must be lowercase SHA-256 hex")

    request_bytes, request = decode_json_base64(
        payload["request_json_base64"], f"{context}.request"
    )
    if canonical_json(request) != request_bytes:
        fail(f"{context}: request JSON is not canonical sorted compact JSON")
    if hashlib.sha256(request_bytes).hexdigest() != payload["request_fingerprint"]:
        fail(f"{context}: request fingerprint does not match request bytes")

    product = request.get("product")
    if not isinstance(product, dict):
        fail(f"{context}.request.product: must be an object")
    if product.get("product_id") != "generated_files_v1" or product.get("settings_policy") != "profile":
        fail(f"{context}.request.product: profile policy discriminator mismatch")
    reference = require_exact_keys(
        product.get("profile_reference"), {"name", "profile_id"},
        f"{context}.request.product.profile_reference",
    )
    if not isinstance(reference["profile_id"], str) or not reference["profile_id"].strip():
        fail(f"{context}: profile_id must be non-empty")
    if not isinstance(reference["name"], str) or not reference["name"].strip():
        fail(f"{context}: profile name must be non-empty when present")

    unnamed_bytes, unnamed = decode_json_base64(
        payload["request_unnamed_reference_json_base64"], f"{context}.unnamed_request"
    )
    if canonical_json(unnamed) != unnamed_bytes:
        fail(f"{context}: unnamed request JSON is not canonical sorted compact JSON")
    unnamed_product = unnamed.get("product")
    if not isinstance(unnamed_product, dict):
        fail(f"{context}.unnamed_request.product: must be an object")
    unnamed_reference = require_exact_keys(
        unnamed_product.get("profile_reference"), {"profile_id"},
        f"{context}.unnamed_request.product.profile_reference",
    )
    if unnamed_reference["profile_id"] != reference["profile_id"]:
        fail(f"{context}: unnamed reference changed profile_id")
    expected_unnamed = json.loads(json.dumps(request))
    del expected_unnamed["product"]["profile_reference"]["name"]
    if unnamed != expected_unnamed:
        fail(f"{context}: unnamed request differs by more than omitted profile name")

    envelope_bytes, envelope = decode_json_base64(
        payload["envelope_json_base64"], f"{context}.envelope"
    )
    if canonical_json(envelope) != envelope_bytes:
        fail(f"{context}: envelope JSON is not canonical sorted compact JSON")
    if envelope.get("protocol_version") != 2 or envelope.get("type") != "export_request":
        fail(f"{context}: envelope discriminator mismatch")
    if envelope.get("payload") != request:
        fail(f"{context}: envelope payload differs from request")


def validate_v3_fixture(path: Path) -> None:
    context = "healthmd.direct.ios-query v3 fixture"
    payload = require_exact_keys(
        load_json(path, context),
        {
            "hello",
            "query_rejected",
            "query_request",
            "query_response",
            "schema",
            "schema_version",
        },
        context,
    )
    if payload["schema"] != "healthmd.direct_query_swift_reference" or payload["schema_version"] != 1:
        fail(f"{context}: schema discriminator mismatch")

    def swift_payload(field: str, discriminator: str) -> dict[str, Any]:
        wrapper = require_exact_keys(payload[field], {discriminator}, f"{context}.{field}")
        associated = require_exact_keys(
            wrapper[discriminator], {"_0"}, f"{context}.{field}.{discriminator}"
        )
        value = associated["_0"]
        if not isinstance(value, dict):
            fail(f"{context}.{field}: Swift associated value must be an object")
        return value

    hello = require_exact_keys(
        swift_payload("hello", "hello"),
        {
            "installationID",
            "platform",
            "protocolVersions",
            "query",
            "supportedRawProfiles",
            "supportsCanonicalExtraction",
            "supportsDurableJobs",
            "transfer",
        },
        f"{context}.hello",
    )
    if hello["platform"] != "ios" or hello["protocolVersions"] != [1, 3]:
        fail(f"{context}.hello: iOS query hello must advertise [1, 3]")
    uuid_re = re.compile(
        r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-"
        r"[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$"
    )
    if not isinstance(hello["installationID"], str) or not uuid_re.fullmatch(hello["installationID"]):
        fail(f"{context}.hello.installationID: invalid UUID")
    query_capabilities = require_exact_keys(
        hello["query"],
        {
            "detailLevels",
            "maximumPageBytes",
            "maximumPageItems",
            "operations",
            "schemaVersions",
            "supportsEvidenceValues",
        },
        f"{context}.hello.query",
    )
    expected_operations = {
        "coverage",
        "derive_packet",
        "metric_series",
        "period_comparison",
        "sleep_session_listing",
        "source_record_listing",
        "workout_listing",
        "workout_sleep_alignment",
    }
    if set(require_unique_string_array(query_capabilities["operations"], f"{context}.hello.query.operations")) != expected_operations:
        fail(f"{context}.hello.query: operation catalog mismatch")
    if query_capabilities["schemaVersions"] != [1]:
        fail(f"{context}.hello.query: schema version must be [1]")
    if set(require_unique_string_array(query_capabilities["detailLevels"], f"{context}.hello.query.detailLevels")) != {"summary", "lossless"}:
        fail(f"{context}.hello.query: detail level catalog mismatch")
    for field, maximum in (("maximumPageItems", 1_000), ("maximumPageBytes", 1_048_576)):
        value = query_capabilities[field]
        if type(value) is not int or value <= 0 or value > maximum:
            fail(f"{context}.hello.query.{field}: invalid bound")
    if query_capabilities["supportsEvidenceValues"] is not True:
        fail(f"{context}.hello.query: evidence values must be supported")

    request = require_exact_keys(
        swift_payload("query_request", "queryRequest"),
        {"createdAt", "detailLevel", "protocolVersion", "query", "requestID"},
        f"{context}.query_request",
    )
    if request["protocolVersion"] != 3 or request["detailLevel"] not in {"summary", "lossless"}:
        fail(f"{context}.query_request: protocol or detail discriminator mismatch")
    if not isinstance(request["requestID"], str) or not uuid_re.fullmatch(request["requestID"]):
        fail(f"{context}.query_request.requestID: invalid UUID")
    if not isinstance(request["createdAt"], str) or not re.fullmatch(
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
        request["createdAt"],
    ):
        fail(f"{context}.query_request.createdAt: expected whole-second UTC timestamp")
    query = require_exact_keys(
        request["query"],
        {"dates", "metrics", "operation", "page", "schema", "schema_version", "sources"},
        f"{context}.query_request.query",
    )
    if query["schema"] != "healthmd.query_request" or query["schema_version"] != 1:
        fail(f"{context}.query_request.query: schema discriminator mismatch")
    for selector_name in ("dates", "metrics", "sources"):
        selector = require_exact_keys(
            query[selector_name], {"type"}, f"{context}.query_request.query.{selector_name}"
        )
        if selector["type"] != "all_available":
            fail(f"{context}.query_request.query.{selector_name}: reference selector mismatch")
    page = require_exact_keys(
        query["page"], {"cursor", "max_bytes", "max_items"}, f"{context}.query_request.query.page"
    )
    if (
        page["cursor"] is not None
        or type(page["max_items"]) is not int
        or type(page["max_bytes"]) is not int
        or not (0 < page["max_items"] <= query_capabilities["maximumPageItems"])
        or not (0 < page["max_bytes"] <= query_capabilities["maximumPageBytes"])
    ):
        fail(f"{context}.query_request.query.page: page bounds or cursor mismatch")
    operation = require_exact_keys(query["operation"], {"type"}, f"{context}.query_request.query.operation")
    if operation["type"] not in expected_operations:
        fail(f"{context}.query_request.query: unsupported operation")

    response = require_exact_keys(
        swift_payload("query_response", "queryResponse"),
        {"requestID", "response"},
        f"{context}.query_response",
    )
    rejection = require_exact_keys(
        swift_payload("query_rejected", "queryRejected"),
        {"code", "message", "requestID", "retryable"},
        f"{context}.query_rejected",
    )
    if response["requestID"] != request["requestID"] or rejection["requestID"] != request["requestID"]:
        fail(f"{context}: request IDs must match across request, response, and rejection")
    response_body = require_exact_keys(
        response["response"],
        {
            "coverage",
            "evidence",
            "items",
            "limitations",
            "metadata",
            "next_cursor",
            "packet",
            "schema",
            "schema_version",
            "sources",
        },
        f"{context}.query_response.response",
    )
    if response_body["schema"] != "healthmd.query_response" or response_body["schema_version"] != 1:
        fail(f"{context}.query_response.response: schema discriminator mismatch")
    for field in ("evidence", "items", "limitations", "sources"):
        if not isinstance(response_body[field], list):
            fail(f"{context}.query_response.response.{field}: must be an array")
    if len(response_body["items"]) > query_capabilities["maximumPageItems"]:
        fail(f"{context}.query_response.response.items: exceeds advertised page limit")
    if not isinstance(response_body["metadata"], dict):
        fail(f"{context}.query_response.response.metadata: must be an object")
    if not isinstance(response_body["coverage"], dict):
        fail(f"{context}.query_response.response.coverage: must be an object")
    if response_body["packet"] is not None and not isinstance(response_body["packet"], dict):
        fail(f"{context}.query_response.response.packet: must be null or an object")
    if response_body["next_cursor"] is not None and not isinstance(response_body["next_cursor"], str):
        fail(f"{context}.query_response.response.next_cursor: must be null or a string")
    if not isinstance(rejection["code"], str) or not IDENTIFIER_RE.fullmatch(rejection["code"]):
        fail(f"{context}.query_rejected.code: invalid stable code")
    message = rejection["message"]
    if not isinstance(message, str) or not message or len(message.encode("utf-8")) > 512 or any(ord(character) < 32 for character in message):
        fail(f"{context}.query_rejected.message: unsafe diagnostic")
    if not isinstance(rejection["retryable"], bool):
        fail(f"{context}.query_rejected.retryable: must be boolean")


def validate_unified_health_data_fixture(root: Path, path: Path) -> None:
    context = "healthmd.health_data unified v9 fixture"
    payload = load_json(path, context)
    schema_path = repository_path(
        root,
        "packages/contracts/proposals/unified-health-data-v9/unified-health-data-v9.schema.json",
        f"{context}.schema",
    )
    schema = load_json(schema_path, f"{context}.schema")
    if (
        not isinstance(schema, dict)
        or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema"
        or schema.get("properties", {}).get("schema_version", {}).get("const") != 9
    ):
        fail(f"{context}: schema metadata is invalid")
    validate_json_schema_subset(payload, schema, context)

    if (
        payload.get("schema") != "healthmd.health_data"
        or payload.get("schema_version") != 9
        or payload.get("profile") != "unified-cross-platform-v1"
    ):
        fail(f"{context}: public discriminator mismatch")

    source = payload["source"]
    platform = source["platform"]
    expected_source = "apple_health" if platform == "apple" else "health_connect"
    if set(payload["platform"]) != {platform}:
        fail(f"{context}: source and platform section disagree")
    platform_payload = payload["platform"][platform]
    if platform == "android":
        source_profiles = {
            "android_frozen_v4": ("android-frozen-v4", 4),
            "android_analytical_v5": ("android-analytical-v5", 5),
        }
        expected_profile, expected_version = source_profiles[source["source_profile"]]
        if (
            platform_payload["source_profile"] != expected_profile
            or platform_payload["source_schema_version"] != expected_version
        ):
            fail(f"{context}: Android envelope and platform source profiles disagree")

    calendar = payload["calendar"]
    try:
        time_zone = ZoneInfo(calendar["time_zone"])
    except ZoneInfoNotFoundError:
        fail(f"{context}.calendar.time_zone: unknown IANA time zone")
    start = datetime.fromisoformat(calendar["interval_start"].replace("Z", "+00:00"))
    end = datetime.fromisoformat(calendar["interval_end"].replace("Z", "+00:00"))
    if end <= start:
        fail(f"{context}: owner-day interval must be non-empty and ordered")
    owner_date = datetime.strptime(payload["owner_date"], "%Y-%m-%d").date()
    if start.astimezone(time_zone).date() != owner_date:
        fail(f"{context}: interval start does not match owner_date in the frozen time zone")
    if end.astimezone(time_zone).date().toordinal() != owner_date.toordinal() + 1:
        fail(f"{context}: interval end is not the next local owner-date boundary")
    if any(
        instant.astimezone(time_zone).time().replace(tzinfo=None) != datetime.min.time()
        for instant in (start, end)
    ):
        fail(f"{context}: interval boundaries must be local midnights")

    resources = payload["capture"]["resources"]
    resource_keys: set[tuple[str, str]] = set()
    for index, resource in enumerate(resources):
        key = (resource["source"], resource["resource"])
        if resource["source"] != expected_source:
            fail(f"{context}.capture.resources[{index}]: wrong primary source")
        if key in resource_keys:
            fail(f"{context}.capture.resources[{index}]: duplicate resource")
        resource_keys.add(key)

    status = payload["capture"]["status"]
    expected_status = (
        "not_requested"
        if not resources
        else "complete"
        if all(resource["status"] == "complete" for resource in resources)
        else "partial"
    )
    if status != expected_status:
        fail(f"{context}.capture.status: does not match resource states")

    resource_statuses = {resource["resource"]: resource["status"] for resource in resources}
    statistic_order = {
        name: index for index, name in enumerate(
            ("sum", "average", "minimum", "maximum", "latest", "count", "duration_sum", "first_time", "last_time")
        )
    }
    metric_order = [
        (metric["semantic_id"], statistic_order[metric["statistic"]])
        for metric in payload["metrics"]
    ]
    if metric_order != sorted(metric_order):
        fail(f"{context}.metrics: metrics are not in canonical semantic/statistic order")
    metric_keys: set[tuple[str, str]] = set()
    for index, metric in enumerate(payload["metrics"]):
        key = (metric["semantic_id"], metric["statistic"])
        if key in metric_keys:
            fail(f"{context}.metrics[{index}]: duplicate semantic/statistic pair")
        metric_keys.add(key)
        if metric["semantic_id"] not in resource_statuses:
            fail(f"{context}.metrics[{index}]: no matching capture resource")
        if resource_statuses[metric["semantic_id"]] != "complete":
            fail(f"{context}.metrics[{index}]: matching capture resource did not complete")
        for provenance_index, provenance in enumerate(metric["provenance"]):
            if provenance["source"] != expected_source:
                fail(
                    f"{context}.metrics[{index}].provenance[{provenance_index}]: "
                    "provider or wrong-platform provenance is forbidden in v9 profile revision 1"
                )
        value = metric["value"]
        if value["value_type"] == "number":
            number = value["number"]
            if number["representation"] == "binary64":
                decoded = struct.unpack(">d", bytes.fromhex(number["bits"]))[0]
                if not math.isfinite(decoded):
                    fail(f"{context}.metrics[{index}]: non-finite binary64 value")

    if "providers" in payload:
        if payload["capture"]["status"] == "not_requested":
            fail(f"{context}: provider-only days are forbidden")
        provider_schema_path = repository_path(
            root,
            "packages/contracts/proposals/provider-sections-v1/provider-sections-v1.schema.json",
            f"{context}.providers.schema",
        )
        provider_schema = load_json(provider_schema_path, f"{context}.providers.schema")
        validate_json_schema_subset(payload["providers"], provider_schema, f"{context}.providers")

    fixture_metric_rules = {
        "steps": {("sum", "count")},
        "heart_rate_variability_sdnn": {("average", "millisecond")},
        "heart_rate_variability_rmssd": {("latest", "millisecond")},
    }
    for index, metric in enumerate(payload["metrics"]):
        value = metric["value"]
        if metric["semantic_id"] not in fixture_metric_rules:
            fail(f"{context}.metrics[{index}]: semantic mapping is not fixture-approved")
        if value["value_type"] != "number" or (
            metric["statistic"], value["unit"]
        ) not in fixture_metric_rules[metric["semantic_id"]]:
            fail(f"{context}.metrics[{index}]: statistic or canonical unit is not fixture-approved")

    semantic_ids = {metric["semantic_id"] for metric in payload["metrics"]}
    if "hrv" in semantic_ids:
        fail(f"{context}: ambiguous hrv semantic id is forbidden")
    if platform == "apple" and "heart_rate_variability_rmssd" in semantic_ids:
        fail(f"{context}: Apple primary data must not be relabeled as RMSSD")
    if platform == "android" and "heart_rate_variability_sdnn" in semantic_ids:
        fail(f"{context}: Android primary data must not be relabeled as SDNN")


def validate_shared_setup_fixture(root: Path, path: Path) -> None:
    context = "healthmd.shared_setup v1 fixture"
    fixture_bytes = path.read_bytes()
    if len(fixture_bytes) > SHARED_SETUP_MAX_BYTES:
        fail(f"{context}: fixture exceeds {SHARED_SETUP_MAX_BYTES} encoded bytes")
    payload = load_json(path, context)
    if fixture_bytes != canonical_json(payload) + b"\n":
        fail(f"{context}: fixture must be canonical sorted compact JSON with one newline")

    node_count = 0

    def validate_generic_bounds(value: Any, value_context: str, depth: int = 0) -> None:
        nonlocal node_count
        node_count += 1
        if node_count > 16_384:
            fail(f"{context}: JSON node count exceeds 16384")
        if depth > 16:
            fail(f"{value_context}: JSON nesting exceeds 16 levels")
        if isinstance(value, dict):
            if len(value) > 256:
                fail(f"{value_context}: object exceeds 256 members")
            for key, child in value.items():
                if len(key) > 256:
                    fail(f"{value_context}: object key exceeds 256 characters")
                validate_generic_bounds(child, f"{value_context}.{key}", depth + 1)
        elif isinstance(value, list):
            if len(value) > 256:
                fail(f"{value_context}: array exceeds 256 items")
            for index, child in enumerate(value):
                validate_generic_bounds(child, f"{value_context}[{index}]", depth + 1)
        elif isinstance(value, str) and len(value) > 65_536:
            fail(f"{value_context}: string exceeds 65536 characters")

    validate_generic_bounds(payload, context)

    schema_path = repository_path(
        root,
        "packages/contracts/shared-setup/v1/shared-setup.schema.json",
        f"{context}.schema",
    )
    schema = load_json(schema_path, f"{context}.schema")
    if (
        not isinstance(schema, dict)
        or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema"
        or schema.get("properties", {}).get("schema_version", {}).get("const")
        != SHARED_SETUP_SCHEMA_VERSION
    ):
        fail(f"{context}: schema metadata is invalid")
    validate_json_schema_subset(payload, schema, context)

    # V1 readers tolerate unknown optional fields only after the same recursive
    # security scan. The schema still requires every core profile section.
    if payload.get("schema") != SHARED_SETUP_SCHEMA or payload.get("schema_version") != 1:
        fail(f"{context}: exact schema/version discriminator is required")

    profile = payload["profile"]
    forbidden_exact = {
        "authorization", "authorization_header", "authorization_header_value",
        "credential", "credentials", "token", "access_token", "refresh_token",
        "password", "secret", "cookie", "headers", "request_headers",
        "bookmark", "security_scoped_bookmark", "saf_uri", "content_uri",
        "folder_uri", "folder_grant", "device_id", "installation_id", "user_id",
        "account_id", "permissions", "health_permissions", "purchase", "purchases",
        "entitlement", "onboarding", "history", "export_history", "enabled_at",
        "last_run", "last_export_date", "last_success", "last_today_refresh_date",
        "retry", "retries", "pending_work", "pending_requests", "operation_id",
        "destination_fingerprint", "fingerprint", "engine_pin", "worker_id",
        "alarm_id", "schedule_enabled", "is_enabled", "health_records",
        "health_data", "source_data", "analytics", "email", "api_key",
        "raw_persistence_snapshot", "raw_snapshot", "session_id", "first_name",
        "last_name", "full_name",
    }
    forbidden_fragments = (
        "credential", "password", "token", "secret", "authorization", "header",
        "bookmark", "saf_uri", "content_uri", "folder_grant", "permission",
        "purchase", "entitlement", "history", "device_id", "installation_id",
        "account_id", "health_record", "health_data", "source_data", "analytics",
        "email", "api_key", "raw_persistence", "raw_snapshot", "session_id",
        "pending_retry", "operation_id", "destination_fingerprint", "engine_pin",
    )

    def reject_sensitive(value: Any, value_context: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                normalized = re.sub(r"[^a-z0-9]+", "_", key.lower()).strip("_")
                safe_disclosure_fields = {"credentials_required", "header_level"}
                if normalized not in safe_disclosure_fields and (
                    normalized in forbidden_exact
                    or any(fragment in normalized for fragment in forbidden_fragments)
                ):
                    fail(f"{value_context}: forbidden sensitive/runtime field {key!r}")
                reject_sensitive(child, f"{value_context}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                reject_sensitive(child, f"{value_context}[{index}]")
        elif isinstance(value, str):
            lowered = value.lower()
            if lowered.startswith(("content://", "file://")):
                fail(f"{value_context}: device-bound URI is forbidden")
            if "authorization:" in lowered or re.search(r"\b(?:bearer|basic)\s+[a-z0-9]", lowered):
                fail(f"{value_context}: authorization material is forbidden")

    reject_sensitive(payload, context)

    if "categories" in profile["metrics"] or "enabled_categories" in profile["metrics"]:
        fail(f"{context}: metric categories must not be selection authority")

    registry_path = repository_path(
        root,
        "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json",
        f"{context}.registry",
    )
    registry = load_json(registry_path, f"{context}.registry")
    registry_identity = payload["metric_registry"]
    if registry_identity["schema"] != METRIC_REGISTRY_SCHEMA:
        fail(f"{context}: metric registry schema discriminator is invalid")
    local_registry_sha256 = hashlib.sha256(registry_path.read_bytes()).hexdigest()
    source_registry_matches = (
        registry_identity["registry_version"] == registry["registry_version"]
        and registry_identity["registry_sha256"] == local_registry_sha256
    )
    registry_metrics = {metric["semantic_id"]: metric for metric in registry["metrics"]}
    enabled_ids = profile["metrics"]["enabled_ids"]
    if enabled_ids != sorted(enabled_ids):
        fail(f"{context}: enabled semantic metric IDs must be sorted")
    unknown_ids = sorted(set(enabled_ids) - set(registry_metrics))
    if unknown_ids and source_registry_matches:
        fail(f"{context}: unknown canonical semantic metric IDs {unknown_ids}")

    individual_ids = set(profile["individual_entries"]["metrics"])
    unknown_individual_ids = sorted(individual_ids - set(registry_metrics))
    if unknown_individual_ids and source_registry_matches:
        fail(f"{context}: unknown individual-entry semantic IDs {unknown_individual_ids}")

    aliases = payload["metric_aliases"]
    alias_ids = [alias["semantic_id"] for alias in aliases]
    if alias_ids != sorted(alias_ids) or len(alias_ids) != len(set(alias_ids)):
        fail(f"{context}: metric alias ledger must be unique and semantic-ID sorted")
    if set(alias_ids) != set(enabled_ids):
        fail(f"{context}: metric alias ledger must cover enabled IDs exactly")
    for index, alias in enumerate(aliases):
        alias_context = f"{context}.metric_aliases[{index}]"
        registry_metric = registry_metrics.get(alias["semantic_id"])
        if registry_metric is None:
            if source_registry_matches:
                fail(f"{alias_context}: semantic ID is missing from the pinned registry")
            continue
        if source_registry_matches:
            if alias["equivalence"] != registry_metric["equivalence"]:
                fail(f"{alias_context}: equivalence differs from registry evidence")
            for platform in ("apple", "android"):
                binding = registry_metric[platform]
                expected = binding["selection_id"] if binding["status"] == "backed" else None
                if alias[f"{platform}_selection_id"] != expected:
                    fail(f"{alias_context}: {platform} selection ID differs from registry evidence")

    path_fields = [
        (profile["export"]["folder_template"], "profile.export.folder_template", True),
        (profile["export"]["filename_template"], "profile.export.filename_template", False),
        (profile["individual_entries"]["entries_folder"], "profile.individual_entries.entries_folder", True),
        (profile["individual_entries"]["filename_template"], "profile.individual_entries.filename_template", False),
        (profile["daily_notes"]["folder"], "profile.daily_notes.folder", True),
        (profile["daily_notes"]["filename_template"], "profile.daily_notes.filename_template", False),
    ]
    android_extension = payload["platform_extensions"]["android"]
    if android_extension is not None:
        path_fields.append((android_extension["export"]["subfolder"], "platform_extensions.android.export.subfolder", True))
    for metric_id, metric_config in profile["individual_entries"]["metrics"].items():
        custom_folder = metric_config["custom_folder"]
        if custom_folder is not None:
            path_fields.append((custom_folder, f"profile.individual_entries.metrics.{metric_id}.custom_folder", True))

    def validate_relative(value: str, field: str, allow_segments: bool) -> None:
        decoded = value
        for _ in range(3):
            next_value = unquote(decoded)
            if next_value == decoded:
                break
            decoded = next_value
        if any(ord(character) < 32 for character in decoded):
            fail(f"{context}.{field}: control characters are forbidden")
        if (
            decoded.startswith(("/", "\\"))
            or "\\" in decoded
            or "%" in value
            or "//" in decoded
            or "://" in decoded
            or re.match(r"^[A-Za-z]:", decoded)
        ):
            fail(f"{context}.{field}: path/template must be relative")
        parts = decoded.split("/")
        if any(part in {".", ".."} for part in parts) or (
            decoded and any(not part for part in parts)
        ):
            fail(f"{context}.{field}: empty or traversal components are forbidden")
        if not allow_segments and len(parts) != 1:
            fail(f"{context}.{field}: filename template must be one segment")

    for value, field, allow_segments in path_fields:
        validate_relative(value, field, allow_segments)

    schedule = profile["schedule"]
    if "enabled" in schedule:
        fail(f"{context}: imported schedule must never contain an operative enabled state")

    endpoint = profile["api_endpoint"]
    if endpoint is not None:
        if endpoint["scheme"] != "https" or endpoint["credentials_required"] is not True:
            fail(f"{context}: endpoint must be non-operative HTTPS requiring credentials")
        combined = f"{endpoint['host']}{endpoint['path']}"
        for _ in range(3):
            next_value = unquote(combined)
            if next_value == combined:
                break
            combined = next_value
        if any(character in combined for character in ("@", "%", "?", "#")):
            fail(f"{context}: endpoint userinfo/escape/query/fragment is forbidden")
        if endpoint["path"].startswith("//"):
            fail(f"{context}: endpoint network-path form is forbidden")
        if endpoint["host"].lower() != "setup.invalid":
            fail(f"{context}: canonical fixture endpoint must use synthetic reserved .invalid host")

    extensions = payload["platform_extensions"]
    origin = payload["created_by"]["platform"]
    if extensions[origin] is None:
        fail(f"{context}: writer must include its own platform extension")
    for platform in ("apple", "android"):
        extension = extensions[platform]
        if extension is not None and extension["extension_version"] != 1:
            fail(f"{context}: present platform extensions must be explicitly versioned")
    if origin == "apple":
        apple_schedule = extensions["apple"]["schedule"]
        cadence = schedule["cadence"]
        frequency = apple_schedule["frequency"]
        cadence_matches = (
            (frequency == "daily" and cadence == {"value": 1, "unit": "days"})
            or (frequency == "weekly" and cadence == {"value": 1, "unit": "weeks"})
            or (frequency == "custom" and cadence["unit"] == apple_schedule["custom_unit"])
        )
        portable_target = "api_endpoint" if apple_schedule["desired_target"] == "api_endpoint" else "device_folder"
        if not cadence_matches or schedule["desired_target"] != portable_target:
            fail(f"{context}: portable and Apple schedule representations contradict each other")


def validate_provider_sections_fixture(root: Path, path: Path) -> None:
    context = "healthmd.provider_sections v1 fixture"
    payload = require_exact_keys(load_json(path, context), {"whoop"}, context)
    whoop = require_exact_keys(
        payload["whoop"],
        {
            "schema",
            "schema_version",
            "capture_status",
            "fetched_at",
            "resources",
            "cycles",
            "recoveries",
            "sleep",
            "workouts",
            "body",
            "warnings",
        },
        f"{context}.whoop",
    )
    if (
        whoop["schema"] != "healthmd.provider.whoop_daily"
        or whoop["schema_version"] != 1
        or whoop["capture_status"] != "complete"
    ):
        fail(f"{context}.whoop: schema or complete-capture discriminator mismatch")

    schema_path = repository_path(
        root,
        "packages/contracts/proposals/provider-sections-v1/provider-sections-v1.schema.json",
        f"{context}.schema",
    )
    schema = load_json(schema_path, f"{context}.schema")
    if (
        not isinstance(schema, dict)
        or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema"
        or schema.get("properties", {}).get("whoop", {}).get("$ref") != "#/$defs/whoopDaily"
        or "whoopDaily" not in schema.get("$defs", {})
    ):
        fail(f"{context}: schema metadata or WHOOP definition is invalid")
    validate_json_schema_subset(payload, schema, context)

    timestamp_re = re.compile(
        r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z$"
    )
    if not isinstance(whoop["fetched_at"], str) or not timestamp_re.fullmatch(
        whoop["fetched_at"]
    ):
        fail(f"{context}.whoop.fetched_at: expected an RFC 3339 UTC timestamp")

    expected_resources = {"cycles", "recovery", "sleep", "workouts", "body"}
    resources = whoop["resources"]
    if not isinstance(resources, list) or len(resources) != len(expected_resources):
        fail(f"{context}.whoop.resources: expected one result for every WHOOP resource")
    resource_names: set[str] = set()
    for index, value in enumerate(resources):
        result = require_exact_keys(
            value,
            {"resource", "status", "record_count"},
            f"{context}.whoop.resources[{index}]",
        )
        resource = result["resource"]
        if resource not in expected_resources or resource in resource_names:
            fail(f"{context}.whoop.resources[{index}]: unknown or duplicate resource")
        resource_names.add(resource)
        if result["status"] != "success" or result["record_count"] != 1:
            fail(f"{context}.whoop.resources[{index}]: complete fixture must retain one record")
    if resource_names != expected_resources:
        fail(f"{context}.whoop.resources: resource coverage mismatch")

    for field in ("cycles", "recoveries", "sleep", "workouts"):
        values = whoop[field]
        if not isinstance(values, list) or len(values) != 1 or not isinstance(values[0], dict):
            fail(f"{context}.whoop.{field}: expected one synthetic typed record")

    id_paths = (
        ("cycles", "id"),
        ("recoveries", "cycle_id"),
        ("recoveries", "sleep_id"),
        ("sleep", "id"),
        ("sleep", "cycle_id"),
        ("workouts", "id"),
    )
    for collection, field in id_paths:
        value = whoop[collection][0].get(field)
        if not isinstance(value, str) or not value or len(value.encode("utf-8")) > 256:
            fail(f"{context}.whoop.{collection}[0].{field}: provider IDs must be bounded strings")

    sleep = whoop["sleep"][0]
    stage_total = sum(
        sleep.get(field, 0)
        for field in (
            "light_sleep_milliseconds",
            "slow_wave_sleep_milliseconds",
            "rem_sleep_milliseconds",
        )
    )
    if sleep.get("total_sleep_milliseconds") != stage_total:
        fail(f"{context}.whoop.sleep[0]: total sleep does not match retained stage durations")

    body = whoop["body"]
    if not isinstance(body, dict) or body.get("source_kind") != "current_profile_snapshot":
        fail(f"{context}.whoop.body: body data must be labeled as a current profile snapshot")
    if not isinstance(body.get("observed_at"), str) or not timestamp_re.fullmatch(
        body["observed_at"]
    ):
        fail(f"{context}.whoop.body.observed_at: expected an RFC 3339 UTC timestamp")
    if whoop["warnings"] != []:
        fail(f"{context}.whoop.warnings: complete synthetic fixture should have no warning")

    fetched_at = datetime.fromisoformat(whoop["fetched_at"].replace("Z", "+00:00"))
    cycle_end = whoop["cycles"][0].get("end_time")
    if cycle_end is not None and datetime.fromisoformat(
        cycle_end.replace("Z", "+00:00")
    ) > fetched_at:
        fail(f"{context}.whoop.cycles[0]: cycle end cannot be after provider fetch time")
    if datetime.fromisoformat(body["observed_at"].replace("Z", "+00:00")) > fetched_at:
        fail(f"{context}.whoop.body: observation cannot be after provider fetch time")

    sensitive_names = {
        "accesstoken",
        "refreshtoken",
        "clientsecret",
        "authorization",
        "oauthcode",
        "nexttoken",
        "cursor",
        "endpoint",
        "url",
        "cookie",
        "password",
        "email",
        "userid",
        "profileid",
        "accountid",
        "firstname",
        "lastname",
        "headers",
    }

    def reject_sensitive(value: Any, value_context: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                normalized = "".join(character for character in key.lower() if character.isalnum())
                if normalized in sensitive_names:
                    fail(f"{value_context}: sensitive or provider-native field {key!r} is forbidden")
                reject_sensitive(child, f"{value_context}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                reject_sensitive(child, f"{value_context}[{index}]")
        elif isinstance(value, str):
            normalized = value.lower()
            if "http://" in normalized or "https://" in normalized:
                fail(f"{value_context}: provider URLs are forbidden in the typed fixture")
            if re.search(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
                fail(f"{value_context}: email addresses are forbidden in the typed fixture")

    reject_sensitive(payload, context)


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


def validate_product_capabilities(
    root: Path,
    inventory_path: Path,
    contract_versions: dict[str, int],
) -> tuple[int, int]:
    context = PRODUCT_CAPABILITIES_SCHEMA
    payload = require_exact_keys(
        load_json(inventory_path, context),
        {"schema", "schema_version", "products", "output_profiles", "capabilities"},
        context,
    )
    if payload.get("schema") != PRODUCT_CAPABILITIES_SCHEMA:
        fail(f"{context}: schema must be {PRODUCT_CAPABILITIES_SCHEMA}")
    if (
        type(payload.get("schema_version")) is not int
        or payload["schema_version"] != PRODUCT_CAPABILITIES_SCHEMA_VERSION
    ):
        fail(
            f"{context}: schema_version must be integer "
            f"{PRODUCT_CAPABILITIES_SCHEMA_VERSION}"
        )

    products = require_unique_string_array(
        payload.get("products"),
        f"{context}.products",
        allow_empty=False,
    )
    if set(products) != VALID_PRODUCTS:
        fail(f"{context}: products must contain apple and android exactly once")

    output_profiles = payload.get("output_profiles")
    if not isinstance(output_profiles, list) or not output_profiles:
        fail(f"{context}: output_profiles must be a non-empty array")
    profile_platforms: dict[str, str] = {}
    for index, profile in enumerate(output_profiles):
        profile_context = f"{context}.output_profiles[{index}]"
        profile = require_exact_keys(
            profile,
            {
                "id",
                "name",
                "platform",
                "contract_id",
                "public_schema",
                "public_schema_version",
                "compatibility",
                "comparison",
            },
            profile_context,
        )
        identifier = profile.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER_RE.fullmatch(identifier):
            fail(f"{profile_context}: id must be a stable lowercase identifier")
        if identifier in profile_platforms:
            fail(f"{profile_context}: duplicate output profile id {identifier}")
        platform = profile.get("platform")
        if not isinstance(platform, str) or platform not in VALID_PRODUCTS:
            fail(f"{profile_context}: platform must be one of {sorted(VALID_PRODUCTS)}")
        profile_platforms[identifier] = platform

        if not isinstance(profile.get("name"), str) or not profile["name"]:
            fail(f"{profile_context}: name must be a non-empty string")
        contract_id = profile.get("contract_id")
        if not isinstance(contract_id, str) or contract_id not in contract_versions:
            fail(f"{profile_context}: unknown contract_id {contract_id!r}")
        public_schema = profile.get("public_schema")
        if not isinstance(public_schema, str) or not public_schema:
            fail(f"{profile_context}: public_schema must be a non-empty string")
        public_version = profile.get("public_schema_version")
        if type(public_version) is not int or public_version < 1:
            fail(f"{profile_context}: public_schema_version must be a positive integer")
        if public_version != contract_versions[contract_id]:
            fail(
                f"{profile_context}: public_schema_version {public_version} does not "
                f"match {contract_id} version {contract_versions[contract_id]}"
            )
        compatibility = profile.get("compatibility")
        if (
            not isinstance(compatibility, str)
            or compatibility not in VALID_PROFILE_COMPATIBILITY
        ):
            fail(
                f"{profile_context}: compatibility must be one of "
                f"{sorted(VALID_PROFILE_COMPATIBILITY)}"
            )
        if profile.get("comparison") != "byte_for_byte":
            fail(f"{profile_context}: comparison must be byte_for_byte")

    missing_profiles = sorted(set(REQUIRED_OUTPUT_PROFILES) - set(profile_platforms))
    if missing_profiles:
        fail(f"{context}: missing required output profiles {missing_profiles}")
    profiles_by_id = {profile["id"]: profile for profile in output_profiles}
    for identifier, (platform, contract_id, version) in REQUIRED_OUTPUT_PROFILES.items():
        profile = profiles_by_id[identifier]
        actual = (
            profile["platform"],
            profile["contract_id"],
            profile["public_schema_version"],
        )
        expected = (platform, contract_id, version)
        if actual != expected:
            fail(f"{context}: {identifier} identity must be {expected}, found {actual}")

    capabilities = payload.get("capabilities")
    if not isinstance(capabilities, list) or not capabilities:
        fail(f"{context}: capabilities must be a non-empty array")
    capability_ids: set[str] = set()
    classifications: set[str] = set()
    for index, capability in enumerate(capabilities):
        capability_context = f"{context}.capabilities[{index}]"
        capability = require_exact_keys(
            capability,
            {
                "id",
                "name",
                "classification",
                "summary",
                "profiles",
                "platforms",
                "evidence",
            },
            capability_context,
        )
        identifier = capability.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER_RE.fullmatch(identifier):
            fail(f"{capability_context}: id must be a stable lowercase identifier")
        if identifier in capability_ids:
            fail(f"{capability_context}: duplicate capability id {identifier}")
        capability_ids.add(identifier)
        capability_context = identifier

        for field in ("name", "summary"):
            if not isinstance(capability.get(field), str) or not capability[field]:
                fail(f"{capability_context}: {field} must be a non-empty string")
        classification = capability.get("classification")
        if (
            not isinstance(classification, str)
            or classification not in VALID_CAPABILITY_CLASSIFICATIONS
        ):
            fail(
                f"{capability_context}: classification must be one of "
                f"{sorted(VALID_CAPABILITY_CLASSIFICATIONS)}"
            )
        classifications.add(classification)

        profiles = require_unique_string_array(
            capability.get("profiles"),
            f"{capability_context}.profiles",
        )
        for profile_id in profiles:
            if profile_id not in profile_platforms:
                fail(f"{capability_context}: unknown output profile {profile_id!r}")

        platforms = capability.get("platforms")
        if not isinstance(platforms, dict) or set(platforms) != VALID_PRODUCTS:
            fail(f"{capability_context}: platforms must contain apple and android")
        states: dict[str, str] = {}
        for product in sorted(VALID_PRODUCTS):
            product_context = f"{capability_context}.platforms.{product}"
            availability = platforms[product]
            if not isinstance(availability, dict):
                fail(f"{product_context}: availability must be an object")
            state = availability.get("state")
            if not isinstance(state, str) or state not in VALID_CAPABILITY_STATES:
                fail(
                    f"{product_context}: state must be one of "
                    f"{sorted(VALID_CAPABILITY_STATES)}"
                )
            states[product] = state
            expected_keys = {"state"}
            detail_field: str | None = None
            if state == "unavailable":
                expected_keys.add("reason")
                detail_field = "reason"
            elif state == "planned":
                expected_keys.add("target")
                detail_field = "target"
            if set(availability) != expected_keys:
                fail(
                    f"{product_context}: {state} entry keys must be "
                    f"{sorted(expected_keys)}"
                )
            if detail_field is not None and (
                not isinstance(availability.get(detail_field), str)
                or not availability[detail_field]
            ):
                fail(f"{product_context}: {detail_field} must be a non-empty string")

        expected_states: dict[str, tuple[str, str]] = {
            "shared": ("available", "available"),
            "apple_only": ("available", "unavailable"),
            "android_only": ("unavailable", "available"),
            "unavailable": ("unavailable", "unavailable"),
        }
        actual_states = (states["apple"], states["android"])
        if classification in expected_states and actual_states != expected_states[classification]:
            fail(
                f"{capability_context}: {classification} requires Apple/Android states "
                f"{expected_states[classification]}, found {actual_states}"
            )
        if classification == "planned" and "planned" not in actual_states:
            fail(f"{capability_context}: planned classification requires a planned platform")
        if classification != "planned" and "planned" in actual_states:
            fail(f"{capability_context}: planned platform requires planned classification")
        if classification == "unavailable" and profiles:
            fail(f"{capability_context}: unavailable capability cannot name output profiles")

        for profile_id in profiles:
            product = profile_platforms[profile_id]
            if states[product] == "unavailable":
                fail(
                    f"{capability_context}: profile {profile_id} belongs to unavailable "
                    f"platform {product}"
                )

        evidence = require_unique_string_array(
            capability.get("evidence"),
            f"{capability_context}.evidence",
            allow_empty=False,
        )
        for evidence_index, raw_path in enumerate(evidence):
            repository_path(
                root,
                raw_path,
                f"{capability_context}.evidence[{evidence_index}]",
            )

    missing_classifications = sorted(
        VALID_CAPABILITY_CLASSIFICATIONS - classifications
    )
    if missing_classifications:
        fail(
            f"{context}: inventory does not account for classifications "
            f"{missing_classifications}"
        )
    return len(output_profiles), len(capabilities)


def validate_metric_registry(
    root: Path,
    registry_path: Path,
    contract_versions: dict[str, int],
) -> None:
    context = METRIC_REGISTRY_SCHEMA
    payload = require_exact_keys(
        load_json(registry_path, context),
        {
            "schema",
            "schema_version",
            "registry_version",
            "known_capability_ids",
            "available_capability_ids_by_platform",
            "categories",
            "metrics",
            "profiles",
            "legacy_unavailable",
        },
        context,
    )
    canonical = (
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode()
    if canonical != registry_path.read_bytes():
        fail(f"{context}: registry bytes must be canonical sorted-key JSON")
    if payload.get("registry_version") != 1:
        fail(f"{context}: registry_version must be 1")

    product_payload = load_json(
        root / "packages/contracts/product-capabilities.json",
        "product capability cross-check",
    )
    product_profiles = {
        profile["id"]: profile for profile in product_payload["output_profiles"]
    }
    capability_ids = [capability["id"] for capability in product_payload["capabilities"]]
    capability_by_id = {
        capability["id"]: capability for capability in product_payload["capabilities"]
    }
    known_capability_ids = require_unique_string_array(
        payload.get("known_capability_ids"),
        f"{context}.known_capability_ids",
        allow_empty=False,
    )
    unknown_registry_capabilities = sorted(set(known_capability_ids) - set(capability_ids))
    if unknown_registry_capabilities:
        fail(
            f"{context}: registry references unknown product capabilities "
            f"{unknown_registry_capabilities}"
        )
    expected_known_order = [
        capability_id
        for capability_id in capability_ids
        if capability_id in set(known_capability_ids)
    ]
    if known_capability_ids != expected_known_order:
        fail(f"{context}: known capabilities must preserve product-capabilities order")
    metric_capability_ids = {
        metric.get("capability_id")
        for metric in payload.get("metrics", [])
        if isinstance(metric, dict)
    }
    missing_metric_capabilities = sorted(metric_capability_ids - set(known_capability_ids))
    if missing_metric_capabilities:
        fail(
            f"{context}: metric capabilities missing from registry inventory "
            f"{missing_metric_capabilities}"
        )
    available_by_platform = require_exact_keys(
        payload.get("available_capability_ids_by_platform"),
        {"apple", "android"},
        f"{context}.available_capability_ids_by_platform",
    )
    expected_available_by_platform = {
        platform: [
            capability_id
            for capability_id in known_capability_ids
            if capability_by_id[capability_id]["platforms"][platform]["state"]
            == "available"
        ]
        for platform in ("apple", "android")
    }
    for platform in ("apple", "android"):
        available = require_unique_string_array(
            available_by_platform.get(platform),
            f"{context}.available_capability_ids_by_platform.{platform}",
            allow_empty=False,
        )
        if available != expected_available_by_platform[platform]:
            fail(f"{context}: available {platform} capabilities differ from product inventory")

    categories = payload.get("categories")
    if not isinstance(categories, list) or len(categories) != 33:
        fail(f"{context}: expected 21 Apple and 12 Android ordered categories")
    category_keys: set[tuple[str, str]] = set()
    category_counts = {"apple": 0, "android": 0}
    for index, category in enumerate(categories):
        category_context = f"{context}.categories[{index}]"
        category = require_exact_keys(
            category,
            {"platform", "category_id", "label_key", "ordinal"},
            category_context,
        )
        platform = category.get("platform")
        if platform not in category_counts:
            fail(f"{category_context}: invalid platform")
        category_id = category.get("category_id")
        label_key = category.get("label_key")
        if not isinstance(category_id, str) or not category_id or not isinstance(label_key, str) or not label_key:
            fail(f"{category_context}: category_id and label_key are required")
        key = (platform, category_id)
        if key in category_keys or category.get("ordinal") != category_counts[platform]:
            fail(f"{category_context}: duplicate or non-contiguous category order")
        category_keys.add(key)
        category_counts[platform] += 1
    if category_counts != {"apple": 21, "android": 12}:
        fail(f"{context}: wrong platform category counts {category_counts}")

    metrics = payload.get("metrics")
    if not isinstance(metrics, list) or len(metrics) != 248:
        fail(f"{context}: expected 248 explicit semantic rows")
    semantic_ids: set[str] = set()
    backed_ids: dict[str, list[tuple[int, str]]] = {"apple": [], "android": []}
    for index, metric in enumerate(metrics):
        metric_context = f"{context}.metrics[{index}]"
        if not isinstance(metric, dict):
            fail(f"{metric_context}: metric must be an object")
        semantic_id = metric.get("semantic_id")
        if not isinstance(semantic_id, str) or not semantic_id or semantic_id in semantic_ids:
            fail(f"{metric_context}: duplicate or invalid semantic_id")
        semantic_ids.add(semantic_id)
        if metric.get("capability_id") not in capability_ids:
            fail(f"{metric_context}: unknown capability_id")
        if metric.get("equivalence") not in {
            "platform_exact_or_unavailable",
            "mapped_alias",
            "platform_distinct",
        }:
            fail(f"{metric_context}: invalid equivalence classification")
        for platform in ("apple", "android"):
            binding = metric.get(platform)
            if not isinstance(binding, dict) or binding.get("status") not in {"backed", "unavailable"}:
                fail(f"{metric_context}.{platform}: explicit backed/unavailable status required")
            if binding["status"] == "backed":
                if metric.get("capability_id") not in expected_available_by_platform[platform]:
                    fail(f"{metric_context}.{platform}: backed metric uses unavailable capability")
                valid_aggregations = (
                    {"cumulative", "discreteAvg", "discreteMin", "discreteMax", "mostRecent", "duration", "count"}
                    if platform == "apple"
                    else {"sum", "average", "minimum", "maximum", "latest", "record_projection"}
                )
                if binding.get("source_aggregation") not in valid_aggregations:
                    fail(f"{metric_context}.{platform}: invalid source aggregation")
                selection_id = binding.get("selection_id")
                ordinal = binding.get("ordinal")
                if not isinstance(selection_id, str) or not selection_id or type(ordinal) is not int:
                    fail(f"{metric_context}.{platform}: backed binding lacks id/order")
                backed_ids[platform].append((ordinal, selection_id))
            elif binding.get("reason_key") is None or binding.get("picker_visibility") not in {"hidden", "listed"}:
                fail(f"{metric_context}.{platform}: unavailable binding lacks reason/visibility")
    for platform, expected_count in (("apple", 230), ("android", 106)):
        ordered = sorted(backed_ids[platform])
        if len(ordered) != expected_count or [ordinal for ordinal, _ in ordered] != list(range(expected_count)):
            fail(f"{context}: {platform} backed metrics have duplicate/non-contiguous order")
        if len({selection_id for _, selection_id in ordered}) != expected_count:
            fail(f"{context}: {platform} backed selection ids must be unique")

    profiles = payload.get("profiles")
    if not isinstance(profiles, list) or len(profiles) != 3:
        fail(f"{context}: exactly three profiles are required")
    seen_profile_ids: set[str] = set()
    for index, profile in enumerate(profiles):
        profile_context = f"{context}.profiles[{index}]"
        if not isinstance(profile, dict):
            fail(f"{profile_context}: profile must be an object")
        profile_id = profile.get("id")
        public_profile_id = profile.get("public_profile_id")
        if REGISTRY_PROFILE_TO_PUBLIC.get(profile_id) != public_profile_id or profile_id in seen_profile_ids:
            fail(f"{profile_context}: invalid or duplicate internal/public profile mapping")
        seen_profile_ids.add(profile_id)
        product_profile = product_profiles[public_profile_id]
        if profile.get("platform") != product_profile["platform"]:
            fail(f"{profile_context}: profile platform differs from product capabilities")
        if profile.get("public_schema") != product_profile["public_schema"] or profile.get("public_schema_version") != product_profile["public_schema_version"]:
            fail(f"{profile_context}: public schema differs from product capabilities")
        if contract_versions.get(product_profile["contract_id"]) != profile["public_schema_version"]:
            fail(f"{profile_context}: public schema differs from contract manifest")
        expected_ids = [selection_id for _, selection_id in sorted(backed_ids[profile["platform"]])]
        if profile.get("ordered_selection_ids") != expected_ids:
            fail(f"{profile_context}: ordered selections differ from platform bindings")
        outputs = profile.get("outputs")
        if not isinstance(outputs, list) or not outputs:
            fail(f"{profile_context}: outputs must be non-empty")
        paths: set[tuple[str, str]] = set()
        for output_index, output in enumerate(outputs):
            if not isinstance(output, dict):
                fail(f"{profile_context}.outputs[{output_index}]: output must be an object")
            path = (output.get("surface"), output.get("key"))
            if not all(isinstance(value, str) and value for value in path) or path in paths:
                fail(f"{profile_context}.outputs[{output_index}]: duplicate/invalid output path")
            paths.add(path)
        unavailable = profile.get("unavailable_selection_ids")
        expected_unavailable = 0 if profile["platform"] == "apple" else 102
        if not isinstance(unavailable, list) or len(unavailable) != expected_unavailable or len(set(unavailable)) != expected_unavailable:
            fail(f"{profile_context}: unavailable inventory count/uniqueness mismatch")
    if seen_profile_ids != set(REGISTRY_PROFILE_TO_PUBLIC):
        fail(f"{context}: missing required registry profiles")


def validate_semantic_range_capability_fixture(path: Path) -> None:
    context = f"semantic range capability fixture {path}"
    payload = load_json(path, context)
    payload = require_exact_keys(
        payload,
        {
            "schema", "schema_version", "calendar_v1", "range_v2",
            "revision_one_range_rejected", "range_limit_cases",
        },
        context,
    )
    if payload["schema"] != "healthmd.semantic_profile_capability_fixture" or payload["schema_version"] != 1:
        fail(f"{context}: invalid fixture identity")
    calendar = payload["calendar_v1"]
    range_v2 = payload["range_v2"]
    if calendar.get("profile_revision") != 1 or calendar.get("rollup_periods") != ["iso_week"] or calendar.get("rollup_range") is not None:
        fail(f"{context}.calendar_v1: calendar grammar must remain revision 1")
    if range_v2.get("profile_revision") != 2 or range_v2.get("rollup_periods") != ["range"] or not isinstance(range_v2.get("rollup_range"), dict):
        fail(f"{context}.range_v2: range grammar must require revision 2 and explicit bounds")
    if payload["revision_one_range_rejected"] is not True:
        fail(f"{context}: revision-one range rejection must be explicit")
    limit_cases = payload["range_limit_cases"]
    expected_cases = {
        "exact-10000-accepted": (10_000, True),
        "10001-rejected": (10_001, False),
        "reversed-rejected": (-9_998, False),
    }
    if not isinstance(limit_cases, list) or len(limit_cases) != len(expected_cases):
        fail(f"{context}.range_limit_cases: exact boundary cases are required")
    for index, case in enumerate(limit_cases):
        case_context = f"{context}.range_limit_cases[{index}]"
        case = require_exact_keys(
            case,
            {"id", "start_date", "end_date", "expected_days", "accepted"},
            case_context,
        )
        try:
            start = datetime.strptime(case["start_date"], "%Y-%m-%d").date()
            end = datetime.strptime(case["end_date"], "%Y-%m-%d").date()
        except (TypeError, ValueError):
            fail(f"{case_context}: bounds must be canonical civil dates")
        actual_days = (end - start).days + 1
        expected = expected_cases.get(case["id"])
        if expected is None or case["expected_days"] != actual_days or (actual_days, case["accepted"]) != expected:
            fail(f"{case_context}: range boundary acceptance does not match the 10,000-day limit")

    result_schema = load_json(path.parent.parent / "semantic-result.schema.json", f"{context} result schema")
    synthetic_result = {
        "schema": "healthmd.semantic_result",
        "semantic_input_version": 1,
        "canonical_model_version": 1,
        "core_api_version": 3,
        "registry_sha256": "0" * 64,
        "profile_revision": 2,
        "session_id": "range-schema-proof",
        "profile": "apple_health_data_v8",
        "state": "completed",
        "next_batch_index": 1,
        "records_accepted": 0,
        "records_filtered": 0,
        "days": [],
        "rollups": [{
            "period": "range",
            "start_date": range_v2["rollup_range"]["start_date"],
            "end_date": range_v2["rollup_range"]["end_date"],
            "calendar_time_zone": "UTC",
            "source_dates": [range_v2["rollup_range"]["start_date"]],
            "values": [{
                "output_key": "steps",
                "rule": "sum",
                "primary_value": {
                    "value_type": "number",
                    "number": {"representation": "unsigned_integer", "decimal": "1"},
                    "unit": {"id": "steps"},
                },
                "days_counted": 1,
                "statistics": {},
            }],
        }],
        "retained_extensions": [],
    }
    validate_json_schema_subset(synthetic_result, result_schema, f"{context}.range_result_v2")
    synthetic_result["profile_revision"] = 1
    try:
        validate_json_schema_subset(synthetic_result, result_schema, f"{context}.range_result_v1")
    except ContractValidationError:
        pass
    else:
        fail(f"{context}: semantic-result schema must reject range at profile revision 1")

    synthetic_result["profile_revision"] = 2
    synthetic_result["rollups"][0]["period"] = "iso_week"
    try:
        validate_json_schema_subset(synthetic_result, result_schema, f"{context}.calendar_result_v2")
    except ContractValidationError:
        pass
    else:
        fail(f"{context}: semantic-result schema must reject calendar roll-ups at profile revision 2")


def validate_rollup_summary_fixture(root: Path, path: Path) -> None:
    context = f"rollup fixture {path}"
    payload = load_json(path, context)
    if not isinstance(payload, dict):
        fail(f"{context}: root must be an object")
    schema_path = path.parent.parent / "rollup-summary.schema.json"
    schema = load_json(schema_path, f"{context} schema")
    if not isinstance(schema, dict) or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        fail(f"{context}: invalid rollup summary schema")
    validate_json_schema_subset(payload, schema, context)
    start_text = payload.get("start_date")
    end_text = payload.get("end_date")
    source_dates = payload.get("source_dates")
    try:
        ZoneInfo(payload.get("calendar_timezone"))
    except (TypeError, ZoneInfoNotFoundError):
        fail(f"{context}.calendar_timezone: must be a valid IANA timezone identifier")
    try:
        start = datetime.strptime(start_text, "%Y-%m-%d").date()
        end = datetime.strptime(end_text, "%Y-%m-%d").date()
    except (TypeError, ValueError):
        fail(f"{context}: start_date and end_date must be canonical civil dates")
    days_expected = (end - start).days + 1
    if start > end or days_expected > 10_000:
        fail(f"{context}: invalid or unbounded requested range")
    if payload.get("period_id") != f"{start_text}_to_{end_text}":
        fail(f"{context}.period_id: must equal the immutable requested bounds")
    if payload.get("days_expected") != days_expected:
        fail(f"{context}.days_expected: must equal the inclusive requested bounds")
    if not isinstance(source_dates, list) or source_dates != sorted(set(source_dates)):
        fail(f"{context}.source_dates: must be unique and sorted")
    if any(not isinstance(value, str) or value < start_text or value > end_text for value in source_dates):
        fail(f"{context}.source_dates: every date must be within requested bounds")
    days_counted = payload.get("days_counted")
    if days_counted != len(source_dates) or days_counted > days_expected:
        fail(f"{context}.days_counted: must equal unique source_dates and not exceed days_expected")
    coverage = payload.get("coverage_percent")
    expected_coverage = days_counted * 100.0 / days_expected
    if not isinstance(coverage, (int, float)) or not math.isclose(coverage, expected_coverage, abs_tol=1e-9):
        fail(f"{context}.coverage_percent: must equal days_counted / days_expected * 100")
    metrics = payload.get("metrics")
    if not isinstance(metrics, list) or not metrics:
        fail(f"{context}.metrics: must be a non-empty array")
    for index, metric in enumerate(metrics):
        counted = metric.get("days_counted") if isinstance(metric, dict) else None
        if type(counted) is not int or counted < 1 or counted > days_counted:
            fail(f"{context}.metrics[{index}].days_counted: must be within artifact coverage")
    units = payload.get("units")
    expected_units = {
        metric["key"]: metric["unit"]
        for metric in metrics
        if isinstance(metric, dict) and metric.get("unit")
    }
    if units != expected_units:
        fail(f"{context}.units: must match the production non-empty metric unit projection")
    categories = payload.get("categories")
    expected_categories: dict[str, list[Any]] = {}
    for metric in metrics:
        if isinstance(metric, dict):
            expected_categories.setdefault(metric.get("category"), []).append(metric)
    if categories != expected_categories:
        fail(f"{context}.categories: must match the production metric category projection")


def validate_rollup_production_fixture(root: Path, path: Path) -> None:
    context = f"rollup production fixture {path}"
    production_names = {
        "range-v9.json": "range.json",
        "range-v9.csv": "range.csv",
        "range-v9.md": "range.md",
        "range-v9-bases.md": "range-bases.md",
    }
    production_name = production_names.get(path.name)
    if production_name is None:
        fail(f"{context}: unknown canonical range-v9 fixture")
    generated = root / "apps/apple/docs/reference/generated/rollups" / production_name
    if generated.read_bytes() != path.read_bytes():
        fail(f"{context}: fixture must be copied byte-for-byte from the production Swift renderer")

    content = path.read_text()
    if path.suffix == ".csv":
        rows = list(csv.reader(content.splitlines()))
        if not rows or rows[0][:6] != [
            "Schema", "Schema Version", "Source Schema", "Source Schema Version",
            "Rollup Rules Version", "Calendar Timezone",
        ]:
            fail(f"{context}: range-v9 CSV leading contract columns are incomplete")
        if len(rows) < 2 or any(len(row) != len(rows[0]) or row[5] != "UTC" for row in rows[1:]):
            fail(f"{context}: every production CSV row must carry the frozen calendar timezone")
    elif path.suffix == ".md":
        if "\ncalendar_timezone: UTC\n" not in content:
            fail(f"{context}: Markdown/Bases frontmatter must carry calendar_timezone")
        if path.name == "range-v9.md" and "## Roll-up notes" not in content:
            fail(f"{context}: canonical Markdown fixture must include the production body")
        if path.name == "range-v9-bases.md" and "rollup_metrics:" not in content:
            fail(f"{context}: canonical Bases fixture must include all metric projections")


def validate_manifest(root: Path) -> tuple[int, int, int, int, int, int]:
    manifest_path = root / "packages/contracts/manifest.json"
    manifest = require_exact_keys(
        load_json(manifest_path, "contract manifest"),
        {"schema", "schema_version", "inventories", "contracts"},
        "contract manifest",
    )
    if manifest.get("schema") != MANIFEST_SCHEMA:
        fail(f"contract manifest: schema must be {MANIFEST_SCHEMA}")
    if (
        type(manifest.get("schema_version")) is not int
        or manifest["schema_version"] != MANIFEST_SCHEMA_VERSION
    ):
        fail(
            f"contract manifest: schema_version must be integer "
            f"{MANIFEST_SCHEMA_VERSION}"
        )
    contracts = manifest.get("contracts")
    if not isinstance(contracts, list) or not contracts:
        fail("contract manifest: contracts must be a non-empty array")

    identifiers: set[str] = set()
    contract_versions: dict[str, int] = {}
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
        contract_versions[identifier] = contract["version"]
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
            if fixture_path.suffix == ".json":
                load_json(fixture_path, fixture_context)
            else:
                try:
                    fixture_bytes.decode("utf-8")
                except UnicodeDecodeError as error:
                    fail(f"{fixture_context}: fixture is not UTF-8: {error}")
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
                if fixture_path.name == "swift-reference.json":
                    validate_v1_fixture(fixture_path)
                elif fixture_path.name == "profile-policy-swift-reference.json":
                    validate_profile_policy_fixture(fixture_path)
                else:
                    fail(f"{fixture_context}: unknown healthmd.direct.ios fixture file")
            elif identifier == "healthmd.direct.ios-query":
                validate_v3_fixture(fixture_path)
            elif identifier == "healthmd.direct.android":
                if fixture_path.name == "interop.json":
                    validate_v2_fixture(fixture_path)
                elif fixture_path.name == "profile-policy-reference.json":
                    validate_v2_profile_policy_fixture(fixture_path)
                else:
                    fail(f"{fixture_context}: unknown healthmd.direct.android fixture file")
            elif identifier == "healthmd.semantic_input":
                if fixture_path.name == "range-profile-revision-v2.json":
                    validate_semantic_range_capability_fixture(fixture_path)
                else:
                    validate_semantic_fixture(root, fixture_path)
            elif identifier == "healthmd.render_input":
                validate_render_fixture(root, fixture_path)
            elif identifier == "healthmd.provider_sections":
                validate_provider_sections_fixture(root, fixture_path)
            elif identifier == SHARED_SETUP_SCHEMA:
                validate_shared_setup_fixture(root, fixture_path)
            elif identifier == "healthmd.health_data.unified":
                validate_unified_health_data_fixture(root, fixture_path)
            elif identifier == "healthmd.rollup_summary":
                validate_rollup_production_fixture(root, fixture_path)
                if fixture_path.suffix == ".json":
                    validate_rollup_summary_fixture(root, fixture_path)

    inventories = manifest.get("inventories")
    if not isinstance(inventories, list) or not inventories:
        fail("contract manifest: inventories must be a non-empty array")
    inventory_ids: set[str] = set()
    inventory_paths: set[str] = set()
    inventory_count = 0
    profile_count = 0
    capability_count = 0
    found_product_inventory = False
    found_metric_inventory = False
    for index, inventory in enumerate(inventories):
        inventory_context = f"inventories[{index}]"
        inventory = require_exact_keys(
            inventory,
            {"id", "version", "path", "sha256", "implementations"},
            inventory_context,
        )
        identifier = inventory.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER_RE.fullmatch(identifier):
            fail(f"{inventory_context}: id must be a stable lowercase identifier")
        if identifier in inventory_ids:
            fail(f"{inventory_context}: duplicate inventory id {identifier}")
        inventory_ids.add(identifier)
        inventory_context = identifier

        version = inventory.get("version")
        if type(version) is not int or version < 1:
            fail(f"{inventory_context}: version must be a positive integer")
        raw_path = inventory.get("path")
        inventory_path = repository_path(root, raw_path, f"{inventory_context}.path")
        if raw_path in inventory_paths:
            fail(f"{inventory_context}: duplicate inventory path {raw_path}")
        inventory_paths.add(raw_path)
        implementations = require_unique_string_array(
            inventory.get("implementations"),
            f"{inventory_context}.implementations",
            allow_empty=False,
        )
        for implementation_index, implementation in enumerate(implementations):
            repository_path(
                root,
                implementation,
                f"{inventory_context}.implementations[{implementation_index}]",
            )
        declared_hash = inventory.get("sha256")
        if not isinstance(declared_hash, str) or not SHA256_RE.fullmatch(declared_hash):
            fail(f"{inventory_context}: sha256 must be lowercase SHA-256 hex")
        actual_hash = hashlib.sha256(inventory_path.read_bytes()).hexdigest()
        if actual_hash != declared_hash:
            fail(
                f"{inventory_context}: SHA-256 mismatch for {raw_path}; "
                f"declared {declared_hash}, actual {actual_hash}"
            )
        inventory_payload = load_json(inventory_path, inventory_context)
        if not isinstance(inventory_payload, dict):
            fail(f"{inventory_context}: inventory must be a JSON object")
        if inventory_payload.get("schema") != identifier:
            fail(
                f"{inventory_context}: inventory schema must match its manifest id"
            )
        if inventory_payload.get("schema_version") != version:
            fail(
                f"{inventory_context}: inventory schema_version must match manifest version"
            )
        if identifier == PRODUCT_CAPABILITIES_SCHEMA:
            if found_product_inventory:
                fail(f"{inventory_context}: product capability inventory declared twice")
            found_product_inventory = True
            profile_count, capability_count = validate_product_capabilities(
                root,
                inventory_path,
                contract_versions,
            )
        elif identifier == METRIC_REGISTRY_SCHEMA:
            if found_metric_inventory:
                fail(f"{inventory_context}: metric registry inventory declared twice")
            found_metric_inventory = True
            validate_metric_registry(root, inventory_path, contract_versions)
        inventory_count += 1

    if not found_product_inventory:
        fail(
            f"contract manifest: required inventory {PRODUCT_CAPABILITIES_SCHEMA} is missing"
        )
    if not found_metric_inventory:
        fail(
            f"contract manifest: required inventory {METRIC_REGISTRY_SCHEMA} is missing"
        )

    return (
        len(contracts),
        fixture_count,
        mirror_count,
        inventory_count,
        profile_count,
        capability_count,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (defaults to the root containing packages/contracts)",
    )
    parser.add_argument(
        "--product-parity-only",
        action="store_true",
        help="validate the manifest and product capability/profile inventory without link checks",
    )
    arguments = parser.parse_args()
    root = arguments.repo_root.resolve()
    try:
        (
            contracts,
            fixtures,
            mirrors,
            inventories,
            profiles,
            capabilities,
        ) = validate_manifest(root)
        links = 0 if arguments.product_parity_only else validate_markdown_links(root)
    except ContractValidationError as error:
        print(f"contracts validation failed: {error}", file=sys.stderr)
        return 1
    if arguments.product_parity_only:
        print(
            f"Validated {inventories} inventories, {profiles} output profiles, "
            f"and {capabilities} product capabilities."
        )
    else:
        print(
            f"Validated {contracts} contracts, {fixtures} fixtures, "
            f"{mirrors} packaging mirrors, {inventories} inventories, "
            f"{profiles} output profiles, {capabilities} product capabilities, "
            f"and {links} local documentation links."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
