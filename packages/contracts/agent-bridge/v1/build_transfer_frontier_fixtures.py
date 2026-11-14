"""Deterministic synthetic frontier1 vectors; does not change any historical fixture."""
import copy
import base64
import hashlib
import json
import runpy
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REFERENCE = runpy.run_path(str(HERE / "transfer_frontier.py"))

def build():
    def uid(n): return f"00000000-0000-4000-8000-{n:012x}"
    seed = {"job_id": uid(1), "request_sha256": "1" * 64, "manifest_sha256": "2" * 64, "session_id": uid(2)}
    first = {"partition_index": 0, "transfer_id": uid(3), "artifact_id": uid(4), "artifact_offset": 0,
             "byte_count": 3, "chunk_count": 1, "sha256": hashlib.sha256(b"abc").hexdigest()}
    second = {**first, "partition_index": 1, "transfer_id": uid(5), "artifact_id": uid(6), "sha256": hashlib.sha256(b"def").hexdigest()}
    cases = []
    def add(identifier, rows, context=None, expected="valid"):
        case = {"id": identifier, "seed": copy.deepcopy(context or seed), "partitions": copy.deepcopy(rows), "expected": expected}
        try:
            prefixes, canonical_bytes = REFERENCE["evaluate"](case["seed"], case["partitions"])
            assert expected == "valid"
            case.update(prefix_sha256=prefixes, canonical_base64=canonical_bytes)
        except REFERENCE["Invalid"] as error:
            assert str(error) == expected
        cases.append(case)
    add("empty-prefix", [])
    add("one-partition", [first])
    add("two-artifacts", [first, second])
    add("one-artifact-segments", [first, {**second, "artifact_id": first["artifact_id"], "artifact_offset": 3}])
    add("empty-partition", [{**first, "byte_count": 0, "chunk_count": 0, "sha256": hashlib.sha256(b"").hexdigest()}])
    add("maximum-partition-and-offset", [{**first, "byte_count": 67_108_864, "chunk_count": 128, "artifact_offset": 1_099_511_627_776 - 67_108_864}])
    for field in sorted(seed):
        changed = {**seed, field: uid(10) if field.endswith("_id") else "3" * 64}
        add("changed-" + field, [first], changed)
    for field, value in [("transfer_id", uid(11)), ("artifact_id", uid(12)), ("artifact_offset", 3), ("byte_count", 4), ("chunk_count", 2), ("sha256", "4" * 64)]:
        add("changed-partition-" + field, [{**first, field: value}])
    add("skipped-first-index", [{**first, "partition_index": 1}], expected="binding_changed")
    add("repeated-index", [first, first], expected="binding_changed")
    add("reordered-prefix", [second, first], expected="binding_changed")
    for field, value in [("partition_index", -1), ("partition_index", 2_147_483_647), ("byte_count", -1), ("byte_count", 67_108_865),
                         ("chunk_count", -1), ("chunk_count", 129), ("artifact_offset", -1), ("artifact_offset", 1_099_511_627_776),
                         ("transfer_id", uid(3).upper().replace("000000000003", "ABCDEF000003")), ("artifact_id", "not-an-id"),
                         ("sha256", "F" * 64), ("byte_count", True)]:
        add(f"invalid-{field}-{len(cases)}", [{**first, field: value}], expected="invalid_request")
    for field in ("partition_index", "artifact_offset", "byte_count", "chunk_count"):
        add("quoted-" + field, [{**first, field: str(first[field])}], expected="invalid_request")
    add("unknown-partition-field", [{**first, "unknown": 1}], expected="invalid_request")
    missing = dict(first); del missing["sha256"]
    add("missing-partition-field", [missing], expected="invalid_request")
    add("invalid-seed-uuid", [], {**seed, "job_id": "invalid"}, expected="invalid_request")
    add("invalid-seed-digest", [], {**seed, "manifest_sha256": "A" * 64}, expected="invalid_request")
    raw_float = json.dumps({**first, "partition_index": 0.0}, sort_keys=True, separators=(",", ":")).encode()
    raw_duplicate = REFERENCE["canonical"](first).replace(b'"partition_index":0', b'"partition_index":0,"partition_index":0')
    for identifier, raw in [("raw-float-index", raw_float), ("raw-duplicate-field", raw_duplicate), ("raw-invalid-utf8", b"\xff")]:
        case = {"id": identifier, "seed": seed, "partitions": [], "raw_partitions_base64": [base64.b64encode(raw).decode()], "expected": "invalid_request"}
        try: REFERENCE["evaluate"](seed, [], case["raw_partitions_base64"]); raise AssertionError("Raw negative must reject")
        except REFERENCE["Invalid"] as error: assert str(error) == "invalid_request"
        cases.append(case)
    return {"schema": "healthmd.agent_transfer_frontier_vectors", "schema_version": 1, "cases": cases}

if __name__ == "__main__":
    relative = "packages/contracts/agent-bridge/v1/fixtures/transfer-frontier-v1.json"
    mirror = "packages/healthmd-core-rust/crates/healthmd-protocol/tests/fixtures/agent-transfer-frontier-v1.json"
    data = (json.dumps(build(), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    (ROOT / relative).write_bytes(data); (ROOT / mirror).write_bytes(data)
    path = ROOT / "packages/contracts/manifest.json"
    manifest = json.loads(path.read_text())
    contract = next(c for c in manifest["contracts"] if c["id"] == "healthmd.agent_bridge")
    entry = {"path": relative, "sha256": hashlib.sha256(data).hexdigest(),
             "provenance": "Independent Python frontier1 seed/partition-chain computation vectors. Pure Swift/Kotlin/Rust agreement is not native permission, durable output commit, resume or physical acceptance.", "mirrors": [mirror]}
    contract["fixtures"] = [f for f in contract["fixtures"] if f["path"] != relative] + [entry]
    implementation = "packages/contracts/agent-bridge/v1/transfer_frontier.py"
    if implementation not in contract["implementations"]: contract["implementations"].append(implementation)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
