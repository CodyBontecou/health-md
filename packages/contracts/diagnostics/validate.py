"""Diagnostics-only conformance; no health export or network dependency."""
import hashlib
import json
from datetime import datetime
from pathlib import Path

from diagnostics.generate import generate


def validate_event(root, event, validate_schema):
    schema = json.loads((root / "packages/contracts/diagnostics/v1/event.schema.json").read_text())
    validate_schema(event, schema, "diagnostic event")
    datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00"))
    if set(event["fields"]) & set(event["omitted_fields"]):
        raise ValueError("fields and omitted_fields must be disjoint")
    for key, value in event["fields"].items():
        maximum = schema["properties"]["fields"]["properties"][key].get("x-max-utf8-bytes")
        if maximum is not None and len(value.encode("utf-8")) > maximum:
            raise ValueError("private diagnostic field exceeds UTF-8 budget")


def validate_manifest(root, manifest, validate_schema):
    schema = json.loads((root / "packages/contracts/diagnostics/v1/bundle.schema.json").read_text())
    validate_schema(manifest, schema, "diagnostic bundle")
    datetime.fromisoformat(manifest["generated_at"].replace("Z", "+00:00"))
    files = manifest["files"]
    paths = [entry["path"] for entry in files]
    if len(paths) != len(set(paths)) or not {"README.txt", "events.jsonl", "events.txt"}.issubset(paths):
        raise ValueError("bundle inventory paths must be unique with all required content")
    contains_private = False
    attachment_bytes = 0
    for entry in files:
        attachment = entry["path"].startswith("attachments/")
        if attachment != (entry["privacy"] == "user_attachment"):
            raise ValueError("attachment paths must retain user_attachment classification")
        if attachment:
            attachment_bytes += entry["byte_count"]
            if "original_name" not in entry:
                raise ValueError("attachment provenance requires the source name")
        elif "original_name" in entry:
            raise ValueError("operational files cannot carry source filenames")
        if entry["privacy"] == "private_context" and not manifest["include_private_context"]:
            raise ValueError("recorded private context requires explicit sharing selection")
        contains_private |= entry["privacy"] != "operational"
    if attachment_bytes > 100 * 1024 * 1024:
        raise ValueError("attachment budget exceeded")
    if manifest["contains_private_context"] != contains_private or manifest["health_content"] != ("possible" if contains_private else "not_included"):
        raise ValueError("manifest sensitivity must account for free-form context and all attachments")


def validate_fixture(root: Path, path: Path, validate_schema, schema_error):
    for generated, expected in generate(root).items():
        if generated.read_text() != expected:
            raise ValueError(f"generated diagnostic contract drift: {generated.relative_to(root)}")
    fixture = json.loads(path.read_text())
    if not isinstance(fixture.get("provenance"), str) or not fixture["provenance"]:
        raise ValueError("diagnostics fixtures require synthetic provenance")
    if path.name == "privacy.json":
        catalog = json.loads((root / "packages/contracts/diagnostics/v1/catalog.json").read_text())
        schema = json.loads((root / "packages/contracts/diagnostics/v1/event.schema.json").read_text())
        raw = fixture["input"]
        for private, key in [(False, "expected_operational"), (True, "expected_private")]:
            expected = fixture[key]
            validate_event(root, expected, validate_schema)
            projected = {key: value for key, value in raw.items() if key in schema["properties"] and key not in ("fields", "omitted_fields")}
            accepted, omitted = {}, {}
            for field, value in raw["fields"].items():
                if field not in catalog["fields"]:
                    continue
                try:
                    validate_schema(value, schema["properties"]["fields"]["properties"][field], "diagnostic field")
                except schema_error:
                    omitted[field] = "invalid"
                    continue
                if catalog["fields"][field]["privacy"] != "operational" and not private:
                    omitted[field] = "redacted"
                else:
                    accepted[field] = value
            projected |= {"fields": accepted, "omitted_fields": omitted}
            if projected != expected:
                raise ValueError("synthetic privacy projection differs from catalog")
            encoded = json.dumps(expected)
            if "SYNTHETIC_SECRET_SENTINEL" in encoded or "SYNTHETIC_HEALTH_SENTINEL" in encoded:
                raise ValueError("restricted synthetic values escaped fixture projection")
    elif path.name == "bundle.json":
        manifest = fixture["manifest"]
        validate_manifest(root, manifest, validate_schema)
        contents = fixture["file_contents"]
        if set(contents) != {entry["path"] for entry in manifest["files"]}:
            raise ValueError("synthetic bundle content/inventory mismatch")
        for entry in manifest["files"]:
            data = contents[entry["path"]].encode("utf-8")
            if entry["byte_count"] != len(data) or entry["sha256"] != hashlib.sha256(data).hexdigest():
                raise ValueError("synthetic bundle byte/digest mismatch")
    else:
        raise ValueError("unknown diagnostics fixture")
