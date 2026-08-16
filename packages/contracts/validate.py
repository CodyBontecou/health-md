#!/usr/bin/env python3
"""Validate the language-neutral Health.md contract inventory and fixtures."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import math
import os
import re
import struct
import sys
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote

MANIFEST_SCHEMA = "healthmd.contract_manifest"
MANIFEST_SCHEMA_VERSION = 2
PRODUCT_CAPABILITIES_SCHEMA = "healthmd.product_capabilities"
PRODUCT_CAPABILITIES_SCHEMA_VERSION = 1
METRIC_REGISTRY_SCHEMA = "healthmd.metric_registry"
METRIC_REGISTRY_SCHEMA_VERSION = 1
REGISTRY_PROFILE_TO_PUBLIC = {
    "apple_health_data_v7": "apple-v7",
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
    "apple-v7": ("apple", "healthmd.health_data.apple", 7),
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
        or payload["registry_sha256"] != "b988fa9a0fea4cf3a0768ee6ad89251a15386c87eb929ce1e46b136fd33b1f4b"
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
        if profile not in {"apple_health_data_v7", "android_frozen_v4", "android_analytical_v5"} or profile in profiles:
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
    known_capability_ids = require_unique_string_array(
        payload.get("known_capability_ids"),
        f"{context}.known_capability_ids",
        allow_empty=False,
    )
    if known_capability_ids != capability_ids:
        fail(f"{context}: known capabilities must exactly match product-capabilities order")
    available_by_platform = require_exact_keys(
        payload.get("available_capability_ids_by_platform"),
        {"apple", "android"},
        f"{context}.available_capability_ids_by_platform",
    )
    expected_available_by_platform = {
        platform: [
            capability["id"]
            for capability in product_payload["capabilities"]
            if capability["platforms"][platform]["state"] == "available"
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
            elif identifier == "healthmd.direct.ios-query":
                validate_v3_fixture(fixture_path)
            elif identifier == "healthmd.direct.android":
                validate_v2_fixture(fixture_path)
            elif identifier == "healthmd.semantic_input":
                validate_semantic_fixture(root, fixture_path)
            elif identifier == "healthmd.render_input":
                validate_render_fixture(root, fixture_path)

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
