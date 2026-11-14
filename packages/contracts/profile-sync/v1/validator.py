"""Independent bounded profile-sync v1 reference parser. No service/native writes.
Reuses frozen v2 writer shape, security, path, registry semantics (not bundle identity).
The fixture-only v2 endpoint helper is deliberately not an online validator.
"""
from __future__ import annotations
import copy
import hashlib
import importlib.util
import json
import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
_spec = importlib.util.spec_from_file_location("frozen_contract_validator", ROOT / "packages/contracts/validate.py")
v2 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v2)
CONTENT_MAX = 262_144
WIRE_MAX = 4_194_304
SAFE_MAX = 9_007_199_254_740_991
DOMAIN = b"healthmd.profile_sync.portable/v1\x00"
SCHEMA = json.loads((HERE / "portable-content.schema.json").read_bytes())
TRANSPORT = "healthmd.profile_sync"
ERROR_RESULTS = ("unavailable", "invalid", "requires_upgrade", "conflict", "gone", "not_found",
                 "resync_required", "idempotency_mismatch", "intent_expired", "verification_pending", "quota_exceeded")
# Explicit finite v1 subset, not Python/JS/Foundation/Kotlin trim semantics.
NAME_EDGE_WHITESPACE = frozenset([*range(0x0009, 0x000E), 0x0020, 0x0085, 0x00A0, 0x1680,
                                *range(0x2000, 0x200B), 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF])
NAME_LINE_BREAKS = frozenset([0x0085, 0x2028, 0x2029])


class Invalid(ValueError):
    """Fixed error category; never echo private content."""


def require(condition: bool, category: str = "invalid") -> None:
    if not condition:
        raise Invalid(category)


def strict_json(raw: bytes, maximum: int = WIRE_MAX) -> Any:
    require(len(raw) <= maximum, "size")

    def pairs(rows):
        out, normalized = {}, set()
        for key, value in rows:
            key_nfc = unicodedata.normalize("NFC", key)
            require(key_nfc not in normalized, "duplicate_key")
            normalized.add(key_nfc)
            out[key] = value
        return out

    def integer(text):
        value = int(text)
        require(text != "-0" and abs(value) <= SAFE_MAX, "integer")
        return value

    def not_integer(_):
        raise Invalid("integer")

    try:
        text = raw.decode("utf-8")
        # Bound nesting before a recursive generic decoder is invoked, even on invalid JSON.
        depth, in_string, escaped = 0, False, False
        for character in text:
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character in "[{":
                depth += 1
                require(depth <= 21, "depth")
            elif character in "]}":
                depth -= 1
        value = json.loads(text, object_pairs_hook=pairs, parse_int=integer,
                           parse_float=not_integer, parse_constant=not_integer)
        v2._validate_shared_setup_generic_bounds(value, "sync", max_depth=20,
            max_container_items=512, max_key_scalars=65_536,
            max_string_scalars=65_536 if maximum == CONTENT_MAX else WIRE_MAX,
            max_nodes=16_384)
        return value
    except Invalid:
        raise
    except (UnicodeError, ValueError, RecursionError, v2.ContractValidationError):
        raise Invalid("json") from None


def exact(value, keys):
    require(type(value) is dict and set(value) == set(keys.split()))


def integer(value, minimum=1):
    require(type(value) is int and minimum <= value <= SAFE_MAX, "integer")
    return value


def opaque(value, prefix, length=32):
    require(type(value) is str and re.fullmatch(prefix + "[0-9a-f]{" + str(length) + "}", value) is not None)
    return value


def digest(raw: bytes) -> str:
    return hashlib.sha256(DOMAIN + raw).hexdigest()


def mutation_digest(raw: bytes) -> str:
    return hashlib.sha256(b"healthmd.profile_sync.mutate/v1\x00" + raw).hexdigest()


def witness(content):
    profile = copy.deepcopy(content["profile"])
    profile["bundle_id"] = "profile-001"
    return {"schema": "healthmd.shared_setup", "schema_version": 2,
            "created_by": {"platform": content["origin_platform"], "app_version": "profile-sync-v1-witness"},
            "metric_registry": content["metric_registry"], "metric_aliases": content["metric_aliases"],
            "profiles": [profile], "active_profile": "profile-001"}


@dataclass(frozen=True, init=False)
class ValidatedContent:
    raw: bytes
    sha256: str
    requires_action: tuple[str, ...]

    @classmethod
    def parse(cls, raw: bytes, expected_hash: str | None = None):
        content = strict_json(raw, CONTENT_MAX)
        try:
            v2.validate_json_schema_subset(content, SCHEMA, "sync")
            v2._validate_shared_setup_writer_allowlist(content, SCHEMA, "sync")
            w = witness(content)
            v2._reject_sensitive_shared_setup_v2(w, "sync")
            p = content["profile"]
            name = p["name"]
            require(bool(name) and ord(name[0]) not in NAME_EDGE_WHITESPACE and ord(name[-1]) not in NAME_EDGE_WHITESPACE)
            require(not any(ord(c) < 32 or ord(c) == 127 or ord(c) in NAME_LINE_BREAKS for c in name))
            require(p["export"]["formats"] == sorted(set(p["export"]["formats"])))
            ids = p["metrics"]["enabled_ids"]
            require(ids == sorted(set(ids)))
            for path, filename in [(p["export"]["folder_template"], False), (p["export"]["filename_template"], True),
                (p["individual_entries"]["entries_folder"], False), (p["individual_entries"]["filename_template"], True),
                (p["daily_notes"]["folder"], False), (p["daily_notes"]["filename_template"], True)]:
                v2._validate_shared_setup_v2_relative(path, "path", "sync", allow_segments=not filename)
            ext = p["platform_extensions"]
            require(ext[content["origin_platform"]] is not None)
            if ext["android"] is not None:
                v2._validate_shared_setup_v2_relative(ext["android"]["export"]["subfolder"], "subfolder", "sync", allow_segments=True)
            for row in p["individual_entries"]["metrics"].values():
                if row["custom_folder"] is not None:
                    v2._validate_shared_setup_v2_relative(row["custom_folder"], "folder", "sync", allow_segments=True)
            d = p["destination"]
            require(d["kind"] == "api_endpoint" or d["api_endpoint"] is None)
            if d["api_endpoint"] is not None:
                endpoint = d["api_endpoint"]
                require(not any(c in endpoint["path"] for c in "@%?#\\") and not endpoint["path"].startswith("//"))
            schedule = p["schedule"]
            if schedule is not None:
                anchor = schedule["cadence"]["anchor_date"]
                require(date.fromisoformat(anchor).isoformat() == anchor)
            if ext["apple"] is not None:
                apple_schedule = ext["apple"]["schedule"]
                require((schedule is None) == (apple_schedule is None))
                if schedule is not None:
                    cadence = schedule["cadence"]
                    frequency = apple_schedule["frequency"]
                    require((frequency == "daily" and cadence["value"] == 1 and cadence["unit"] == "days") or
                            (frequency == "weekly" and cadence["value"] == 1 and cadence["unit"] == "weeks") or
                            (frequency == "custom" and cadence["unit"] == apple_schedule["custom_unit"]))
            v2._validate_shared_setup_v2_registry(ROOT, w, set(ids) | set(p["individual_entries"]["metrics"]), "sync")
            # Stricter, portable security parity: reject native identity/path material in prose.
            scan_strings(content)
        except Invalid:
            raise
        except (v2.ContractValidationError, ValueError, TypeError, KeyError):
            raise Invalid("content") from None
        hash_value = digest(raw)
        require(expected_hash is None or expected_hash == hash_value, "hash")
        flags = ["unbound_destination", "local_review_required"]
        if content["metric_registry"]["registry_sha256"] != json.loads((HERE / "source-pins.json").read_bytes())["metric_registry_sha256"]:
            flags.append("registry_review")
        if any(ext[platform] is not None for platform in ("apple", "android")):
            flags.append("platform_review")
        if schedule is not None:
            flags.append("schedule_disabled")
        if p["presentation"]["markdown"]["style"] == "custom":
            flags.append("template_review")
        result = object.__new__(cls)
        object.__setattr__(result, "raw", raw)
        object.__setattr__(result, "sha256", hash_value)
        object.__setattr__(result, "requires_action", tuple(sorted(flags)))
        return result


def scan_strings(value, endpoint=False, path=()):
    if isinstance(value, dict):
        endpoint_parent = path[-2:] == ("destination", "api_endpoint")
        markdown_parent = path[-2:] == ("presentation", "markdown")
        for key, child in value.items():
            snake = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", key)
            normalized = re.sub(r"[^a-z0-9]+", "_", snake.lower()).strip("_")
            if normalized == "credentials_required": require(endpoint_parent, "prohibited")
            if normalized == "header_level": require(markdown_parent, "prohibited")
            scan_strings(child, endpoint_parent and key in {"host", "path"} and value.get("scheme") == "https", path + (normalized,))
    elif isinstance(value, list):
        for child in value:
            scan_strings(child, path=path + ("[]",))
    elif isinstance(value, str):
        lower = value.lower()
        require(not re.search(r"(?i)(content|file|saf)://|authorization:|\b(?:bearer|basic)\s+[a-z0-9+/=_-]|-----begin private key|https?://[^\s/@]+(?::[^\s/@]*)?@|[?&](?:access_?token|api_?key|password|secret|authorization)=", value), "prohibited")
        if not endpoint:
            require(not re.search(r"(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(?![0-9a-f])|(?:^|[\s\"'])(?:[a-z]:[\\/])", value), "prohibited")
            require(not any(path in lower for path in ("/users/", "/home/", "/private/", "/var/mobile/", "/data/user/", "/storage/emulated/", "/sdcard/", "/mnt/")) and not lower.startswith("~/"), "prohibited")


def discriminant(value):
    require(type(value) is dict and value.get("schema") == TRANSPORT)
    require(type(value.get("schema_version")) is int and value["schema_version"] == 1, "version")


def parse_record(raw: bytes):
    value = strict_json(raw)
    discriminant(value)
    exact(value, "schema schema_version profile_id object_revision event_sequence order_key deleted content_revision content_hash content_json")
    opaque(value["profile_id"], "psp_")
    rev = integer(value["object_revision"])
    integer(value["event_sequence"])
    require(type(value["deleted"]) is bool)
    if value["deleted"]:
        require(all(value[key] is None for key in ("order_key", "content_revision", "content_hash", "content_json")))
        return value, None
    integer(value["order_key"], 0)
    require(integer(value["content_revision"]) <= rev)
    opaque(value["content_hash"], "", 64)
    require(type(value["content_json"]) is str)
    return value, ValidatedContent.parse(value["content_json"].encode("utf-8"), value["content_hash"])


def parse_mutation(raw: bytes):
    value = strict_json(raw)
    discriminant(value)
    op = value.get("operation")
    require(op in {"create", "update", "reorder", "delete"})
    keys = "schema schema_version operation mutation_id base_revision"
    if op != "create":
        keys += " profile_id"
    if op in {"create", "update"}:
        keys += " content_json content_hash"
    if op == "reorder":
        keys += " order_key"
    exact(value, keys)
    opaque(value["mutation_id"], "psm_")
    integer(value["base_revision"], 0 if op == "create" else 1)
    if op == "create":
        require(value["base_revision"] == 0)
    else:
        opaque(value["profile_id"], "psp_")
    content = None
    if op in {"create", "update"}:
        opaque(value["content_hash"], "", 64)
        require(type(value["content_json"]) is str)
        content = ValidatedContent.parse(value["content_json"].encode(), value["content_hash"])
    if op == "reorder":
        integer(value["order_key"], 0)
    return value, content


def parse_read(raw: bytes):
    value = strict_json(raw, 8192)
    discriminant(value)
    mode = value.get("mode")
    require(mode in {"changes", "snapshot", "revision"})
    if mode == "revision":
        exact(value, "schema schema_version mode profile_id content_revision content_hash")
        opaque(value["profile_id"], "psp_")
        integer(value["content_revision"])
        opaque(value["content_hash"], "", 64)
    else:
        exact(value, "schema schema_version mode cursor limit")
        require(type(value["limit"]) is int and 1 <= value["limit"] <= 8)
        if value["cursor"] is not None:
            opaque(value["cursor"], "psc_", 64)
    return value


def parse_error(raw: bytes):
    value = strict_json(raw, 8192)
    discriminant(value)
    exact(value, "schema schema_version result")
    require(type(value["result"]) is str and value["result"] in ERROR_RESULTS)
    return value


def parse_page(raw: bytes):
    value = strict_json(raw)
    discriminant(value)
    exact(value, "schema schema_version mode snapshot_id high_watermark items next_cursor complete")
    require(value["mode"] in {"snapshot", "changes"})
    opaque(value["snapshot_id"], "pss_")
    high = integer(value["high_watermark"], 0)
    require(type(value["complete"]) is bool and value["complete"] == (value["next_cursor"] is None))
    if value["next_cursor"] is not None:
        opaque(value["next_cursor"], "psc_", 64)
    rows = value["items"]
    require(type(rows) is list and len(rows) <= 8 and (value["complete"] or len(rows) > 0))
    parsed = [parse_record(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode())[0] for row in rows]
    require(all(row["event_sequence"] <= high for row in parsed))
    if value["mode"] == "changes":
        order = [row["event_sequence"] for row in parsed]
    else:
        require(not any(row["deleted"] for row in parsed))
        require(len({row["profile_id"] for row in parsed}) == len(parsed))
        order = [(row["order_key"], row["profile_id"]) for row in parsed]
    require(order == sorted(set(order)))
    return value
