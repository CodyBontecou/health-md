"""Reproduce NEW AS05 schema/fixture/embedded-shape artifacts only; no shared registration.
Run from repository root. Runtime codecs never trust a caller-supplied schema.
"""
import ast
import base64
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "packages/contracts/shared-setup/v2/shared-setup.schema.json"


def compact(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_json(name, value):
    (HERE / name).parent.mkdir(parents=True, exist_ok=True)
    (HERE / name).write_text(compact(value) + "\n", encoding="utf-8")


def build_schema():
    source = json.loads(SOURCE.read_bytes())
    definitions = copy.deepcopy(source["$defs"])
    # No v2 artifact identity or creator fields become sync content.
    for name in ("bundleId", "createdBy"):
        del definitions[name]
    definitions["profile"]["required"].remove("bundle_id")
    del definitions["profile"]["properties"]["bundle_id"]

    def close(node):
        if isinstance(node, dict):
            if node.get("type") == "object" and not isinstance(node.get("additionalProperties"), dict):
                node["additionalProperties"] = False
            for child in node.values():
                close(child)
        elif isinstance(node, list):
            for child in node:
                close(child)

    close(definitions)
    # Independently versioned safety tightening, never a v2 schema rewrite.
    definitions["nonEmptyShortString"]["pattern"] = r"^[^\u0000-\u001f\u007f]+$"
    # Literal RFC3986 path characters only: frozen Apple v2's percentEncodedPath
    # setter can trap on a raw space/backslash/Unicode component. Reject before reuse.
    definitions["apiEndpoint"]["properties"]["path"]["pattern"] = r"^/(?!/)[A-Za-z0-9/._~!$&'()*+,;=:-]*$"
    # Python/JS/ICU '$' can match before a final newline; JSON field grammars
    # require the entire scalar sequence. Use a portable absolute-end assertion.
    def absolute_end(node):
        if isinstance(node, dict):
            if isinstance(node.get("pattern"), str) and node["pattern"].endswith("$"):
                node["pattern"] += r"(?![\s\S])"
            for child in node.values(): absolute_end(child)
        elif isinstance(node, list):
            for child in node: absolute_end(child)
    absolute_end(definitions)
    properties = {
        "schema": {"const": "healthmd.profile_sync.portable"},
        "schema_version": {"type": "integer", "const": 1},
        "origin_platform": {"enum": ["apple", "android"]},
        "metric_registry": {"$ref": "#/$defs/metricRegistry"},
        "metric_aliases": {"type": "array", "maxItems": 512, "uniqueItems": True, "items": {"$ref": "#/$defs/metricAlias"}},
        "profile": {"$ref": "#/$defs/profile"},
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://health.md/contracts/profile-sync/v1/portable-content.schema.json",
        "title": "Proposed Health.md profile-sync v1 portable content (closed v2 field projection)",
        "type": "object", "required": list(properties), "properties": properties,
        "additionalProperties": False, "$defs": definitions,
    }


def main():
    schema = build_schema()
    write_json("portable-content.schema.json", schema)
    # Small, deterministic source-only data block. An explicit replacement command is
    # emitted rather than touching codecs outside this script's owned directory.
    write_json("embedded-shape.json", schema)
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    write_json("source-pins.json", {
        "status": "proposed_synthetic_only", "shared_setup_schema_sha256": source_hash,
        "metric_registry_sha256": hashlib.sha256((ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json").read_bytes()).hexdigest(),
        "projection": "closed_v2_profile_minus_bundle_id_plus_independent_registry_origin_metadata",
    })
    fixtures = {}
    for platform in ("apple", "android"):
        bundle = json.loads((ROOT / f"packages/contracts/shared-setup/v2/fixtures/{platform}-shared-setup-v2.json").read_bytes())
        for index, profile in enumerate(bundle["profiles"]):
            profile = copy.deepcopy(profile)
            del profile["bundle_id"]
            ids = set(profile["metrics"]["enabled_ids"]) | set(profile["individual_entries"]["metrics"])
            content = {"schema": "healthmd.profile_sync.portable", "schema_version": 1,
                       "origin_platform": platform, "metric_registry": bundle["metric_registry"],
                       "metric_aliases": [row for row in bundle["metric_aliases"] if row["semantic_id"] in ids],
                       "profile": profile}
            name = f"{platform}-{index + 1}"
            raw = compact(content) + "\n"
            (HERE / "fixtures").mkdir(exist_ok=True)
            (HERE / "fixtures" / f"{name}.json").write_text(raw, encoding="utf-8")
            fixtures[name] = {"file": f"{name}.json", "sha256": hashlib.sha256(b"healthmd.profile_sync.portable/v1\x00" + raw.encode()).hexdigest()}
    write_json("fixtures/content-vectors.json", {"schema_version": 1, "positive": fixtures})
    registry_path = ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"
    registry = json.loads(registry_path.read_bytes())
    evidence = {"sha256": hashlib.sha256(registry_path.read_bytes()).hexdigest(), "aliases": {
        row["semantic_id"]: [row["equivalence"],
            row["apple"]["selection_id"] if row["apple"]["status"] == "backed" else None,
            row["android"]["selection_id"] if row["android"]["status"] == "backed" else None]
        for row in registry["metrics"]}}
    write_json("registry-evidence.json", evidence)
    tree = ast.parse((ROOT / "packages/contracts/validate.py").read_text())
    security = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "_reject_sensitive_shared_setup_v2")
    literals = {node.targets[0].id: ast.literal_eval(node.value) for node in security.body if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) and node.targets[0].id in {"forbidden_exact", "forbidden_fragments"}}
    data = {"shape": schema, "registry": evidence, "forbidden_exact": sorted(literals["forbidden_exact"]), "forbidden_fragments": list(literals["forbidden_fragments"])}
    write_json("codec-data.json", data)
    if "--embed" in sys.argv:
        encoded = base64.b64encode(compact(data).encode()).decode()
        paths = {
            ROOT / "apps/cloud/src/profile-sync-v1-contract.ts": 'const DATA_BASE64 = "' + encoded + '";',
            ROOT / "apps/apple/HealthMd/Shared/AccountSync/ProfileSyncV1.swift": '    private static let dataBase64 = "' + encoded + '"',
            ROOT / "apps/android/app/src/main/java/com/healthmd/accountsync/ProfileSyncV1.kt": '        private val DATA_BASE64 = listOf(\n' + ',\n'.join('            "' + encoded[i:i + 12000] + '"' for i in range(0, len(encoded), 12000)) + '\n        ).joinToString("")',
        }
        for path, declaration in paths.items():
            old = path.read_text()
            pattern = r"(?<=// BEGIN GENERATED PINNED DATA)[^\n]*\n.*?(?=\s*// END GENERATED PINNED DATA)"
            new, count = re.subn(pattern, " (build_source_artifacts.py --embed)\n" + declaration + "\n", old, flags=re.DOTALL)
            assert count == 1, path
            path.write_text(new)


if __name__ == "__main__":
    main()
