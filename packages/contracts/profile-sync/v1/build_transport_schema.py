"""Source-only independent transport schema. No manifest, CI or frozen contract edits."""
from build_source_artifacts import write_json

SAFE = 9007199254740991


def obj(properties):
    return {"type": "object", "required": list(properties), "properties": properties, "additionalProperties": False}


def ref(name): return {"$ref": "#/$defs/" + name}
def num(minimum=1): return {"type": "integer", "minimum": minimum, "maximum": SAFE}
def identifier(prefix, length=32): return {"type": "string", "pattern": "^" + prefix + "[0-9a-f]{" + str(length) + r"}$(?![\s\S])"}
def nullable(schema): return {"oneOf": [{"type": "null"}, schema]}
def envelope(): return {"schema": {"const": "healthmd.profile_sync"}, "schema_version": {"type": "integer", "const": 1}}


def build():
    defs = {"profileID": identifier("psp_"), "mutationID": identifier("psm_"), "snapshotID": identifier("pss_"), "cursor": identifier("psc_", 64), "hash": identifier("", 64)}
    content = {"content_json": {"type": "string", "maxLength": 262144}, "content_hash": ref("hash")}
    metadata = dict(envelope(), profile_id=ref("profileID"), object_revision=num(), event_sequence=num())
    defs["liveRecord"] = obj(dict(metadata, order_key=num(0), deleted={"const": False}, content_revision=num(), **content))
    defs["tombstone"] = obj(dict(metadata, order_key={"type": "null"}, deleted={"const": True}, content_revision={"type": "null"}, content_hash={"type": "null"}, content_json={"type": "null"}))
    defs["record"] = {"oneOf": [ref("liveRecord"), ref("tombstone")]}
    for operation in ("create", "update", "reorder", "delete"):
        props = dict(envelope(), operation={"const": operation}, mutation_id=ref("mutationID"), base_revision={"type": "integer", "const": 0} if operation == "create" else num())
        if operation != "create": props["profile_id"] = ref("profileID")
        if operation in {"create", "update"}: props.update(content)
        if operation == "reorder": props["order_key"] = num(0)
        defs[operation] = obj(props)
    defs["mutation"] = {"oneOf": [ref(op) for op in ("create", "update", "reorder", "delete")]}
    defs["pageRead"] = obj(dict(envelope(), mode={"enum": ["changes", "snapshot"]}, cursor=nullable(ref("cursor")), limit={"type": "integer", "minimum": 1, "maximum": 8}))
    defs["revisionRead"] = obj(dict(envelope(), mode={"const": "revision"}, profile_id=ref("profileID"), content_revision=num(), content_hash=ref("hash")))
    defs["read"] = {"oneOf": [ref("pageRead"), ref("revisionRead")]}
    defs["page"] = obj(dict(envelope(), mode={"enum": ["changes", "snapshot"]}, snapshot_id=ref("snapshotID"), high_watermark=num(0), items={"type": "array", "maxItems": 8, "items": ref("record")}, next_cursor=nullable(ref("cursor")), complete={"type": "boolean"}))
    defs["error"] = obj(dict(envelope(), result={"enum": ["unavailable", "invalid", "requires_upgrade", "conflict", "gone", "not_found", "resync_required", "idempotency_mismatch", "intent_expired", "verification_pending", "quota_exceeded"]}))
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://health.md/contracts/profile-sync/v1/profile-sync.schema.json", "title": "Proposed Health.md profile-sync v1 transport", "oneOf": [ref(name) for name in ("record", "mutation", "read", "page", "error")], "$defs": defs}


if __name__ == "__main__": write_json("profile-sync.schema.json", build())
