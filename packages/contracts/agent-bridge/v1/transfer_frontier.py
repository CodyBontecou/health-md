"""Pure frontier1 reference. Hash agreement is not native permission or durable commit proof."""
import base64
import hashlib
import json
import re
from pathlib import Path

UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
DIGEST = re.compile(r"[0-9a-f]{64}")
SEED_KEYS = {"job_id", "request_sha256", "manifest_sha256", "session_id"}
PARTITION_KEYS = {"partition_index", "transfer_id", "artifact_id", "artifact_offset", "byte_count", "chunk_count", "sha256"}

class Invalid(Exception):
    pass

def require(condition, code="invalid_request"):
    if not condition: raise Invalid(code)

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")

def text(value, pattern):
    require(type(value) is str and pattern.fullmatch(value) is not None)

def integer(value, low, high):
    require(type(value) is int and low <= value <= high)

def seed_document(value):
    require(type(value) is dict and set(value) == SEED_KEYS)
    for key in ("job_id", "session_id"): text(value[key], UUID)
    for key in ("request_sha256", "manifest_sha256"): text(value[key], DIGEST)
    return {"schema": "healthmd.agent_transfer_frontier_seed", "schema_version": 1, **value}

def step_document(previous, count, partition):
    text(previous, DIGEST)
    integer(count, 0, 2_147_483_646)
    require(type(partition) is dict and set(partition) == PARTITION_KEYS)
    integer(partition["partition_index"], 0, 2_147_483_646)
    integer(partition["byte_count"], 0, 67_108_864)
    integer(partition["chunk_count"], 0, 128)
    integer(partition["artifact_offset"], 0, 1_099_511_627_776 - partition["byte_count"])
    for key in ("transfer_id", "artifact_id"): text(partition[key], UUID)
    text(partition["sha256"], DIGEST)
    require(partition["partition_index"] == count, "binding_changed")
    return {"schema": "healthmd.agent_transfer_frontier_step", "schema_version": 1,
            "previous_frontier_sha256": previous, "partition": partition}

def decode_partition(raw):
    require(len(raw) <= 2_097_152)
    def pairs(values):
        result = {}
        for key, value in values:
            require(key not in result)
            result[key] = value
        return result
    def reject_number(_): raise Invalid("invalid_request")
    try: return json.loads(raw.decode("utf-8"), object_pairs_hook=pairs, parse_float=reject_number, parse_constant=reject_number)
    except (ValueError, UnicodeError): raise Invalid("invalid_request") from None

def evaluate(seed, partitions, raw_partitions=None):
    documents = [seed_document(seed)]
    prefixes = [hashlib.sha256(canonical(documents[0])).hexdigest()]
    rows = (decode_partition(base64.b64decode(raw, validate=True)) for raw in raw_partitions) if raw_partitions is not None else iter(partitions)
    for count, partition in enumerate(rows):
        document = step_document(prefixes[-1], count, partition)
        documents.append(document)
        prefixes.append(hashlib.sha256(canonical(document)).hexdigest())
    return prefixes, [base64.b64encode(canonical(d)).decode("ascii") for d in documents]

def validate_fixture(path: Path):
    bundle = json.loads(path.read_text(encoding="utf-8"))
    require(set(bundle) == {"schema", "schema_version", "cases"})
    require(bundle["schema"] == "healthmd.agent_transfer_frontier_vectors" and type(bundle["schema_version"]) is int and bundle["schema_version"] == 1)
    require(type(bundle["cases"]) is list and len(bundle["cases"]) >= 20)
    ids = set()
    for case in bundle["cases"]:
        require(type(case) is dict and type(case.get("id")) is str and case["id"] not in ids)
        ids.add(case["id"])
        required = {"id", "seed", "partitions", "expected"}
        if case["expected"] == "valid": required |= {"prefix_sha256", "canonical_base64"}
        if "raw_partitions_base64" in case:
            require(not case["partitions"] and case["expected"] != "valid")
            required.add("raw_partitions_base64")
        require(set(case) == required)
        try:
            prefixes, canonical_bytes = evaluate(case["seed"], case["partitions"], case.get("raw_partitions_base64"))
            outcome = "valid"
        except Invalid as error:
            outcome = str(error)
        require(outcome == case["expected"])
        if outcome == "valid": require(prefixes == case["prefix_sha256"] and canonical_bytes == case["canonical_base64"])
