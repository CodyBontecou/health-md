#!/usr/bin/env python3
"""Generate strict native diagnostic catalogs. --check detects native drift."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CATALOG = Path(__file__).parent / "v1/catalog.json"


def camel(value):
    parts = value.split("_")
    return parts[0] + "".join(part.title() for part in parts[1:])


def schemas(catalog):
    maximum = 9_007_199_254_740_991
    uuid = {"type": "string", "pattern": "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"}
    count = {"type": "integer", "minimum": 0, "maximum": maximum}
    timestamp = {"type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"}
    fields = {}
    for key, spec in catalog["fields"].items():
        kind = spec["type"]
        if kind == "enum": definition = {"type": "string", "enum": spec["values"]}
        elif kind == "integer": definition = {"type": "integer", "minimum": -maximum, "maximum": maximum}
        elif kind == "count": definition = count.copy()
        elif kind == "boolean": definition = {"type": "boolean"}
        elif kind == "uuid": definition = uuid.copy()
        elif kind == "alias": definition = {"type": "string", "pattern": "^peer_[0-9]{1,3}$"}
        elif kind == "text" and spec["privacy"] == "private_context": definition = {"type": "string", "maxLength": 512, "x-max-utf8-bytes": 512}
        else: raise ValueError("Unreviewed diagnostic field kind/privacy")
        fields[key] = definition | {"x-privacy": spec["privacy"]}
    event_properties = {
        "schema": {"const": "healthmd.diagnostic_event"}, "schema_version": {"const": 1},
        "timestamp": timestamp, "session_id": uuid, "sequence": count, "monotonic_ms": count,
        "platform": {"enum": ["ios", "macos", "android"]},
        "event_id": {"enum": [value[0] for value in catalog["events"].values()]},
        "subsystem": {"enum": sorted({value[1] for value in catalog["events"].values()})},
        "severity": {"enum": ["info", "debug", "trace", "warning", "error"]},
        "source": {"type": "string", "pattern": "^[A-Za-z0-9_]+/[A-Za-z0-9_+.-]+\\.(swift|kt):[0-9]+$"},
        "fields": {"type": "object", "properties": fields, "additionalProperties": False},
        "omitted_fields": {"type": "object", "properties": {key: {"enum": ["not_recorded", "redacted", "unavailable", "truncated", "invalid"]} for key in fields}, "additionalProperties": False},
    }
    event = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "urn:healthmd:diagnostic-event:v1", "title": "Health.md diagnostic event v1", "type": "object", "required": list(event_properties), "properties": event_properties, "additionalProperties": False,
             "oneOf": [{"properties": {"event_id": {"const": value[0]}, "subsystem": {"const": value[1]}, "severity": {"const": value[2]}}} for value in catalog["events"].values()]}
    bundle_properties = {
        "schema": {"const": "healthmd.diagnostic_bundle"}, "schema_version": {"const": 1}, "generated_at": timestamp,
        "platform": {"enum": ["ios", "macos", "android"]},
        "app_version": {"type": "string", "maxLength": 128}, "app_build": {"type": "string", "maxLength": 128}, "os_version": {"type": "string", "maxLength": 256},
        "include_private_context": {"type": "boolean"}, "contains_private_context": {"type": "boolean"}, "health_content": {"enum": ["not_included", "possible"]},
        "event_count": count, "session_dropped_event_count": count, "invalid_event_count": count, "truncated": {"type": "boolean"},
        "selection_since": timestamp, "selection_subsystem": {"enum": sorted({value[1] for value in catalog["events"].values()})}, "selection_operation_id": uuid,
        "files": {"type": "array", "minItems": 3, "maxItems": 53, "items": {"type": "object", "required": ["path", "byte_count", "sha256", "privacy"], "additionalProperties": False, "properties": {
            "path": {"type": "string", "pattern": "^(README\\.txt|events\\.(jsonl|txt)|attachments/attachment-[1-9][0-9]?\\.[a-z0-9]{1,10})$"},
            "byte_count": count, "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "privacy": {"enum": ["operational", "private_context", "user_attachment"]},
            "original_name": {"type": "string", "maxLength": 512}, "original_name_truncated": {"type": "boolean"},
        }}},
    }
    bundle = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "urn:healthmd:diagnostic-bundle:v1", "title": "Health.md diagnostic bundle manifest v1", "type": "object", "required": [key for key in bundle_properties if not key.startswith("selection_")], "properties": bundle_properties, "additionalProperties": False}
    return event, bundle


def generate(root=ROOT):
    catalog = json.loads((root / "packages/contracts/diagnostics/v1/catalog.json").read_text())
    events, fields = catalog["events"], catalog["fields"]
    assert len({value[0] for value in events.values()}) == len(events), "Duplicate event IDs"
    event_schema, bundle_schema = schemas(catalog)
    swift = ["// Generated by packages/contracts/diagnostics/generate.py; do not edit.",
             "import Foundation", "", "nonisolated enum DiagnosticEventID: String, Codable, CaseIterable, Sendable {"]
    swift += [f'    case {camel(key)} = "{value[0]}"' for key, value in events.items()]
    swift += ["", "    var subsystem: String {", "        switch self {"]
    swift += [f'        case .{camel(key)}: return "{value[1]}"' for key, value in events.items()]
    swift += ["        }", "    }", "", "    var severity: String {", "        switch self {"]
    swift += [f'        case .{camel(key)}: return "{value[2]}"' for key, value in events.items()]
    swift += ["        }", "    }", "}", "", "nonisolated enum DiagnosticField: String, Codable, CaseIterable, Sendable {"]
    swift += [f'    case {camel(key)} = "{key}"' for key in fields]
    swift += ["", "    var isPrivate: Bool {", "        switch self {"]
    swift += [f'        case .{camel(key)}: return {str(value["privacy"] != "operational").lower()}' for key, value in fields.items()]
    swift += ["        }", "    }", "", "    func accepts(_ value: DiagnosticValue) -> Bool {", "        switch (self, value) {"]
    for key, spec in fields.items():
        prefix = f"        case (.{camel(key)}, "
        kind = spec["type"]
        if kind == "enum":
            vals = ", ".join(json.dumps(v) for v in spec["values"])
            swift += [prefix + f".text(let text)): return [{vals}].contains(text)"]
        elif kind == "integer":
            swift += [prefix + ".integer(let number)): return number >= -9_007_199_254_740_991 && number <= 9_007_199_254_740_991"]
        elif kind == "count":
            swift += [prefix + ".integer(let number)): return number >= 0 && number <= 9_007_199_254_740_991"]
        elif kind == "boolean":
            swift += [prefix + ".boolean): return true"]
        elif kind == "uuid":
            swift += [prefix + '.text(let text)): return UUID(uuidString: text) != nil && text.count == 36']
        elif kind == "alias":
            swift += [prefix + '.text(let text)): return text.range(of: "^peer_[0-9]{1,3}$", options: .regularExpression) != nil']
        else:
            swift += [prefix + '.text(let text)): return text.utf8.count <= 512']
    swift += ["        default: return false", "        }", "    }", "}", ""]

    kotlin = ["// Generated by packages/contracts/diagnostics/generate.py; do not edit.",
              "package com.healthmd.diagnostics", "", "import java.util.UUID", "",
              "enum class DiagnosticEventID(val wire: String, val subsystem: String, val severity: String) {"]
    kotlin += [f'    {key.upper()}({", ".join(json.dumps(v) for v in value)}),' for key, value in events.items()]
    kotlin += ["}", "", "enum class DiagnosticField(val wire: String, val isPrivate: Boolean) {"]
    kotlin += [f'    {key.upper()}("{key}", {str(value["privacy"] != "operational").lower()}),' for key, value in fields.items()]
    kotlin += ["    ;", "", "    fun accepts(value: DiagnosticValue): Boolean = when (this) {"]
    for key, spec in fields.items():
        prefix = f"        {key.upper()} -> "
        kind = spec["type"]
        if kind == "enum":
            vals = ", ".join(json.dumps(v) for v in spec["values"])
            kotlin += [prefix + f"value is DiagnosticValue.Text && value.value in setOf({vals})"]
        elif kind == "integer":
            kotlin += [prefix + "value is DiagnosticValue.Integer && value.value in -9_007_199_254_740_991L..9_007_199_254_740_991L"]
        elif kind == "count":
            kotlin += [prefix + "value is DiagnosticValue.Integer && value.value in 0..9_007_199_254_740_991L"]
        elif kind == "boolean":
            kotlin += [prefix + "value is DiagnosticValue.Boolean"]
        elif kind == "uuid":
            kotlin += [prefix + "value is DiagnosticValue.Text && value.value.length == 36 && runCatching { UUID.fromString(value.value) }.isSuccess"]
        elif kind == "alias":
            kotlin += [prefix + 'value is DiagnosticValue.Text && Regex("^peer_[0-9]{1,3}$").matches(value.value)']
        else:
            kotlin += [prefix + "value is DiagnosticValue.Text && value.value.toByteArray(Charsets.UTF_8).size <= 512"]
    kotlin += ["    }", "}", ""]
    return {
        root / "apps/apple/HealthMd/Shared/Diagnostics/DiagnosticCatalog.swift": "\n".join(swift),
        root / "apps/android/app/src/main/java/com/healthmd/diagnostics/DiagnosticCatalog.kt": "\n".join(kotlin),
        root / "packages/contracts/diagnostics/v1/event.schema.json": json.dumps(event_schema, indent=2) + "\n",
        root / "packages/contracts/diagnostics/v1/bundle.schema.json": json.dumps(bundle_schema, indent=2) + "\n",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, content in generate().items():
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f"Diagnostic catalog drift: {path.relative_to(ROOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print("Diagnostic native catalogs match" if args.check else "Generated diagnostic native catalogs")
