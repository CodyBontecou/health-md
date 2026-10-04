"""Synthetic AS05 vectors. Does not touch frozen v2 fixtures or any service/store."""
import copy
import json
from pathlib import Path
from validator import HERE, digest, mutation_digest
from build_source_artifacts import compact, write_json


def raw(value):
    return compact(value) + "\n"


def main():
    manifest = json.loads((HERE / "fixtures/content-vectors.json").read_bytes())
    base = json.loads((HERE / "fixtures/apple-1.json").read_bytes())
    evidence = json.loads((HERE / "registry-evidence.json").read_bytes())
    current = copy.deepcopy(base)
    current["metric_registry"]["registry_sha256"] = evidence["sha256"]
    for row in current["metric_aliases"]:
        e, a, b = evidence["aliases"][row["semantic_id"]]
        row.update(equivalence=e, apple_selection_id=a, android_selection_id=b)
    variants = {"registry-current": current}
    foreign = copy.deepcopy(base)
    foreign["profile"]["platform_extensions"]["android"] = json.loads((HERE / "fixtures/android-1.json").read_bytes())["profile"]["platform_extensions"]["android"]
    variants["foreign-unchanged"] = foreign
    changed = copy.deepcopy(foreign)
    changed["profile"]["name"] = "Synthetic local edit 🧪 e\u0301"
    changed["profile"]["export"]["folder_template"] = "Reviewed/{YYYY}"
    variants["foreign-local-edit"] = changed
    unicode_value = copy.deepcopy(current)
    unicode_value["profile"]["presentation"]["frontmatter"]["custom_values"] = {"é": "Synthetic composed", "astral_🧪": "line\n🧪 e\u0301"}
    variants["unicode-exact"] = unicode_value
    for name, value in variants.items():
        encoded = raw(value)
        (HERE / "fixtures" / (name + ".json")).write_text(encoded)
        manifest["positive"][name] = {"file": name + ".json", "sha256": digest(encoded.encode())}
    from validator import ValidatedContent
    for name, row in manifest["positive"].items():
        row["requires_action"] = list(ValidatedContent.parse((HERE / "fixtures" / row["file"]).read_bytes()).requires_action)
    write_json("fixtures/content-vectors.json", manifest)

    cases = []
    def add(name, value, entry="content", valid=False):
        encoded = raw(value) if not isinstance(value, str) else value
        row = {"id": name, "entry": entry, "raw": encoded, "valid": valid}
        if entry == "mutation" and valid: row["request_hash"] = mutation_digest(encoded.encode())
        cases.append(row)
    def patch(name, path, value, original=base):
        c = copy.deepcopy(original); node = c
        for part in path[:-1]: node = node[part]
        if value is REMOVE: del node[path[-1]]
        else: node[path[-1]] = value
        add(name, c)
    REMOVE = object()
    patch("future-content", ["schema_version"], 2)
    patch("removed-version", ["schema_version"], 0)
    patch("boolean-version", ["schema_version"], True)
    patch("fractional-version", ["schema_version"], 1.0)
    patch("missing-null", ["profile", "schedule"], REMOVE)
    patch("future-extension", ["profile", "platform_extensions", "apple", "extension_version"], 3)
    patch("unknown-optional", ["profile", "future_preference"], False)
    patch("native-snapshot", ["profile", "export", "raw_persistence_snapshot"], {})
    prohibited = ["account_id", "native_profile_id", "active_profile", "authorization", "headers", "folder_uri", "bookmark", "timezone", "schedule_enabled", "engine_pin", "pending_work", "history", "purchases", "health_data", "records", "source_data", "permission", "device_id", "timestamp", "include_granular_data"]
    for key in prohibited: patch("prohibited-" + key, ["profile", key], "synthetic")
    for key in ("authorization", "nativeProfileId", "endpoint_url", "last_success", "rollups", "raw_snapshot", "credentials_required", "header_level"):
        patch("prohibited-dynamic-" + key, ["profile", "presentation", "frontmatter", "custom_values"], {key: "synthetic"})
    patch("prohibited-endpoint-impostor", ["profile", "presentation", "frontmatter", "custom_values"], {"scheme": "https", "host": "config.synthetic.example", "path": "/Users/synthetic/Vault"})
    for i, value in enumerate(["Bearer synthetic", "authorization: synthetic", "content://synthetic", "file://synthetic", "saf://synthetic", "/Users/synthetic/Vault", "C:\\synthetic", "https://name:password@setup.invalid/", "https://setup.invalid/?token=redacted&secret=synthetic", "00000000-0000-4000-8000-000000000001", "-----BEGIN PRIVATE KEY-----"]):
        patch("prohibited-text-" + str(i), ["profile", "presentation", "markdown", "custom_text"], value)
    for i, value in enumerate(["/absolute", "../outside", "a/../outside", "a//b", "a/", "a\\b", "a%2Fb", "file://synthetic", "C:/synthetic"]):
        patch("path-" + str(i), ["profile", "export", "folder_template"], value)
    patch("filename-segments", ["profile", "export", "filename_template"], "a/b")
    patch("unsorted-formats", ["profile", "export", "formats"], ["json", "csv"])
    patch("duplicate-formats", ["profile", "export", "formats"], ["json", "json"])
    patch("unsorted-metrics", ["profile", "metrics", "enabled_ids"], ["steps", "active_energy"])
    patch("metric-native-category", ["profile", "metrics", "categories"], ["Heart"])
    patch("alias-missing", ["metric_aliases"], [])
    patch("alias-changed-current", ["metric_aliases", 0, "apple_selection_id"], "not_the_registry", current)
    patch("alias-unknown-current", ["metric_aliases", 0, "semantic_id"], "future_metric", current)
    patch("alias-duplicate", ["metric_aliases"], base["metric_aliases"] + [base["metric_aliases"][0]])
    patch("name-trim", ["profile", "name"], " Synthetic ")
    patch("name-empty", ["profile", "name"], "")
    patch("name-control", ["profile", "name"], "Synthetic\u007f")
    patch("short-field-control", ["profile", "presentation", "frontmatter", "date_key"], "date\nkey")
    patch("short-field-trailing-control", ["profile", "presentation", "frontmatter", "date_key"], "date\n")
    trailing_metric = copy.deepcopy(base)
    trailing_metric["profile"]["metrics"]["enabled_ids"] = ["future_metric\n"]
    trailing_metric["profile"]["individual_entries"]["metrics"] = {}
    trailing_metric["metric_aliases"] = [{"semantic_id": "future_metric\n", "equivalence": "platform_distinct", "apple_selection_id": None, "android_selection_id": None}]
    add("semantic-id-trailing-control", trailing_metric)
    patch("huge-markdown", ["profile", "presentation", "markdown", "custom_text"], "x" * 65_537)
    patch("huge-frontmatter-map", ["profile", "presentation", "frontmatter", "custom_values"], {"k" + str(i): "synthetic" for i in range(129)})
    patch("placeholder-duplicate", ["profile", "presentation", "frontmatter", "placeholders"], ["steps", "steps"])
    schedule_source = json.loads((HERE / "fixtures/apple-2.json").read_bytes())
    patch("bad-date", ["profile", "schedule", "cadence", "anchor_date"], "2026-02-30", schedule_source)
    patch("year-zero", ["profile", "schedule", "cadence", "anchor_date"], "0000-01-01", schedule_source)
    patch("fractional-cadence", ["profile", "schedule", "cadence", "value"], 1.0, schedule_source)
    patch("schedule-enabled", ["profile", "schedule", "enabled"], True, schedule_source)
    patch("schedule-contradiction", ["profile", "schedule", "cadence", "unit"], "months", schedule_source)
    foreign_schedule = copy.deepcopy(schedule_source); foreign_schedule["origin_platform"] = "android"
    foreign_schedule["profile"]["platform_extensions"]["android"] = foreign["profile"]["platform_extensions"]["android"]
    patch("foreign-schedule-contradiction", ["profile", "schedule", "cadence", "unit"], "months", foreign_schedule)
    patch("missing-origin-extension", ["profile", "platform_extensions", "apple"], None)
    endpoint_source = copy.deepcopy(base)
    endpoint_source["profile"]["destination"] = {"kind": "api_endpoint", "api_endpoint": {"scheme": "https", "host": "config.synthetic.example", "port": None, "path": "/config", "query_omitted": True, "credentials_required": True}}
    add("valid-inert-endpoint", endpoint_source, valid=True)
    for i, value in enumerate(["//network", "/has?query", "/has%escape", "/has#fragment", "/has\\slash", "/has@identity", "/has space", "/unicode/🧪", "/has[bracket]"]):
        patch("endpoint-path-" + str(i), ["profile", "destination", "api_endpoint", "path"], value, endpoint_source)
    patch("endpoint-host-userinfo", ["profile", "destination", "api_endpoint", "host"], "name@setup.invalid", endpoint_source)
    patch("endpoint-host-trailing-control", ["profile", "destination", "api_endpoint", "host"], "config.synthetic.example\n", endpoint_source)
    patch("endpoint-path-trailing-control", ["profile", "destination", "api_endpoint", "path"], "/config\n", endpoint_source)
    patch("endpoint-credentials-false", ["profile", "destination", "api_endpoint", "credentials_required"], False, endpoint_source)
    patch("endpoint-kind-mismatch", ["profile", "destination", "kind"], "device_folder", endpoint_source)
    patch("raw-page-out-of-bound", ["profile", "platform_extensions", "android", "export", "raw_snapshot", "page_size"], 5001, foreign)
    # Lexical vectors; never parsed/re-serialized before the real codec sees them.
    add("duplicate-key", raw(base).replace('"schema_version":1', '"schema_version":1,"schema_version":1'))
    add("escaped-key-duplicate", raw(base).replace('"schema_version":1', '"schema_version":1,"schema_versi\\u006fn":1'))
    patch("nfc-equivalent-keys", ["profile", "presentation", "frontmatter", "custom_values"], {"é": "one", "e\u0301": "two"})
    add("surrogate", raw(base).replace('"name":', '"name":', 1).replace(base["profile"]["name"], r"\ud800"))
    add("trailing-data", raw(base) + "{}")
    # Hex bypasses Foundation's trusted fixture JSON string decoder, which drops
    # a literal leading BOM from a string value on this host.
    cases.append({"id": "bom", "entry": "content", "hex": (b"\xef\xbb\xbf" + raw(base).encode()).hex(), "valid": False})
    add("negative-zero", raw(base).replace('"schema_version":1', '"schema_version":-0'))
    add("nan", raw(base).replace('"schema_version":1', '"schema_version":NaN'))
    add("exponent", raw(base).replace('"schema_version":1', '"schema_version":1e0'))
    add("over-depth", "[" * 22 + "null" + "]" * 22)
    cases.append({"id": "over-bytes", "entry": "content", "repeat": 262145, "valid": False})
    cases.append({"id": "bad-utf8", "entry": "content", "hex": "ff", "valid": False})
    add("generic-valid-json", {"emoji": "🧪", "é": "e\u0301", "numbers": [0, 1, 9007199254740991, True]}, "json", True)
    add("generic-container-overflow", {"safe": [0] * 513}, "json")
    add("generic-node-overflow", [[0] * 512 for _ in range(32)], "json")
    add("generic-key-overflow", {"k" * 65537: None}, "json")

    content_json = raw(current); content_hash = digest(content_json.encode())
    record = {"schema": "healthmd.profile_sync", "schema_version": 1, "profile_id": "psp_" + "1" * 32, "object_revision": 1, "event_sequence": 1, "order_key": 0, "deleted": False, "content_revision": 1, "content_hash": content_hash, "content_json": content_json}
    tombstone = dict(record, object_revision=3, event_sequence=4, order_key=None, deleted=True, content_revision=None, content_hash=None, content_json=None)
    add("valid-record", record, "record", True); add("valid-tombstone", tombstone, "record", True)
    for i, value in enumerate([True, 1.0, "1", None, 0, -1, 9007199254740992]):
        add("revision-" + str(i), dict(record, object_revision=value), "record")
    add("v2-bundle-id", dict(record, profile_id="profile-001"), "record")
    add("profile-id-trailing-control", dict(record, profile_id=record["profile_id"] + "\n"), "record")
    add("native-id", dict(record, native_profile_id="synthetic"), "record")
    add("caller-account", dict(record, account_id="synthetic"), "record")
    add("future-record", dict(record, schema_version=2), "record")
    add("hash-mismatch", dict(record, content_hash="0" * 64), "record")
    add("nested-content-bom-not-lossy", dict(record, content_json="\ufeff" + content_json), "record")
    add("content-revision-ahead", dict(record, content_revision=2), "record")
    add("tombstone-has-content", dict(tombstone, content_json=content_json), "record")
    create = {"schema": "healthmd.profile_sync", "schema_version": 1, "operation": "create", "mutation_id": "psm_" + "a" * 32, "base_revision": 0, "content_hash": content_hash, "content_json": content_json}
    add("valid-publish", create, "mutation", True)
    for op in ("update", "reorder", "delete"):
        m = {"schema": "healthmd.profile_sync", "schema_version": 1, "operation": op, "mutation_id": "psm_" + "b" * 32, "base_revision": 1, "profile_id": record["profile_id"]}
        if op == "update": m.update(content_hash=content_hash, content_json=content_json)
        if op == "reorder": m["order_key"] = 2
        add("valid-" + op, m, "mutation", True)
    add("create-base-nonzero", dict(create, base_revision=1), "mutation")
    add("mutation-id-trailing-control", dict(create, mutation_id=create["mutation_id"] + "\n"), "mutation")
    add("create-caller-id", dict(create, profile_id=record["profile_id"]), "mutation")
    add("mutation-caller-account", dict(create, account_id="synthetic"), "mutation")
    add("mutation-secret", dict(create, access_token="synthetic"), "mutation")
    add("mutation-unknown", dict(create, future=True), "mutation")
    read = {"schema": "healthmd.profile_sync", "schema_version": 1, "mode": "changes", "cursor": None, "limit": 8}
    add("valid-read", read, "read", True); add("read-account", dict(read, account_id="synthetic"), "read")
    add("read-limit", dict(read, limit=9), "read"); add("read-cursor", dict(read, cursor="caller-account|1"), "read")
    page = {"schema": "healthmd.profile_sync", "schema_version": 1, "mode": "snapshot", "snapshot_id": "pss_" + "c" * 32, "high_watermark": 1, "items": [record], "next_cursor": None, "complete": True}
    add("valid-page", page, "page", True)
    add("duplicate-snapshot-id", dict(page, items=[record, record]), "page")
    add("high-watermark-underflow", dict(page, high_watermark=0), "page")
    add("page-cursor-contradiction", dict(page, complete=False), "page")
    add("page-tombstone-in-snapshot", dict(page, items=[tombstone], high_watermark=4), "page")
    add("page-limit", dict(page, items=[record] * 9), "page")
    write_json("fixtures/parser-cases.json", {"schema_version": 1, "cases": cases})

    scenarios = []
    def scenario(name, event, remote=record, **args):
        scenarios.append(dict(id=name, event=event, remote=remote, **args))
    scenario("selected-publish", "publish", mutation=create, native_id="local-synthetic-1", expected="mapped_only_after_receipt")
    scenario("publish-lost-ack-replay", "replay", original=create, retry=copy.deepcopy(create), expected="same_receipt")
    scenario("idempotency-key-changed-body", "replay", original=create, retry=dict(create, content_json=raw(changed), content_hash=digest(raw(changed).encode())), expected="idempotency_mismatch")
    scenario("edit-edit", "observe", remote=dict(record, object_revision=2, event_sequence=2), base_revision=1, pending=True, expected="edit_edit_conflict")
    scenario("edit-delete", "observe", remote=tombstone, base_revision=1, pending=True, expected="edit_delete_conflict")
    scenario("delete-edit", "observe", remote=dict(record, object_revision=2, event_sequence=2), base_revision=1, pending=True, pending_kind="delete", expected="edit_edit_conflict")
    scenario("remote-stage-not-apply", "observe", remote=dict(record, object_revision=2, event_sequence=2), base_revision=1, pending=False, expected="pending_local_review")
    scenario("repeat-event", "observe", base_revision=1, pending=False, expected="unchanged")
    scenario("older-event-ignored", "observe", base_revision=2, pending=False, expected="unchanged")
    scenario("delete-keep-local", "observe", remote=tombstone, base_revision=1, pending=False, expected="keep_local_unlink_review")
    scenario("account-switch-outbox", "fence", owner=["synthetic-issuer", "synthetic", "account-A", 1], current=["synthetic-issuer", "synthetic", "account-B", 2], expected="quarantine")
    scenario("environment-switch-outbox", "fence", owner=["synthetic-issuer", "synthetic", "account-A", 1], current=["synthetic-issuer", "staging", "account-A", 2], expected="quarantine")
    scenario("late-response-signout", "fence", owner=["synthetic-issuer", "synthetic", "account-A", 1], current=["synthetic-issuer", "synthetic", "account-A", 2], expected="quarantine")
    scenario("same-generation", "fence", owner=["synthetic-issuer", "synthetic", "account-A", 1], current=["synthetic-issuer", "synthetic", "account-A", 1], expected="eligible_metadata_only")
    scenario("adopt-same-name", "adopt", native_id="local-synthetic-2", already_mapped=False, expected="fresh_blocked_native_id")
    scenario("adopt-repeated", "adopt", native_id="local-synthetic-2", already_mapped=True, expected="existing_mapping_no_duplicate")
    scenario("keep-both", "keep_both", new_profile_id="psp_" + "2" * 32, new_native_id="local-synthetic-3", expected="independent_identity")
    scenario("same-name-not-identity", "names", names=["Café", "CAFÉ", "Cafe\u0301", "Café"], ids=["psp_" + digit * 32 for digit in "1234"], expected="four_identities_no_fold")
    for state in ("missing", "corrupt", "verified"):
        scenario("foreign-provenance-" + state, "preserve", provenance=state, expected="publish_exact_overlay" if state == "verified" else "quarantine")
    scenario("protected-during-commit", "protect", initial=False, commit=True, expected="blocked_commit")
    scenario("accepted-content-immutable", "acceptance", accepted_hash=content_hash, fetched_hash=manifest["positive"]["foreign-local-edit"]["sha256"], expected="accepted_unchanged_candidate_staged")
    scenario("tombstone-expired-resync", "reset", complete_snapshot=True, missing_id=record["profile_id"], pending=True, expected="quarantine_old_base_no_resurrection")
    scenario("incomplete-snapshot-no-removal", "reset", complete_snapshot=False, pending=False, expected="retain_until_complete")
    scenario("snapshot-high-watermark-fence", "snapshot_fence", first_snapshot_id=page["snapshot_id"], next_snapshot_id="pss_" + "d" * 32, first_high=1, next_high=2, expected="discard_restart_snapshot")
    scenario("reorder-keeps-content", "reorder", remote=dict(record, object_revision=2, event_sequence=2, order_key=2), previous_hash=content_hash, expected="same_immutable_content")
    scenario("cas-after-delete", "cas", remote=tombstone, base_revision=3, expected="gone_never_restore_id")
    scenario("cas-stale-base", "cas", remote=dict(record, object_revision=2, event_sequence=2), base_revision=1, expected="conflict")
    scenario("cas-current", "cas", base_revision=1, expected="eligible_metadata_only")
    write_json("fixtures/scenarios.json", {"schema_version": 1, "scenarios": scenarios})
    print(f"Built {len(manifest['positive'])} content fixtures, {len(cases)} parser cases, {len(scenarios)} source scenarios")


if __name__ == "__main__": main()
