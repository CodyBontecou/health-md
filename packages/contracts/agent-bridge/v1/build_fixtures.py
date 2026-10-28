#!/usr/bin/env python3
"""Generate new synthetic specification candidates, never native conformance claims."""
import base64
import copy
import hashlib
import json
import struct
from fractions import Fraction
from pathlib import Path
import build_schemas as S
import validation as V

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def uid(n): return f"00000000-0000-4000-8000-{n:012x}"
def doc(name, **fields): return {"schema": "healthmd." + name, "schema_version": 1, **fields}
def clone(x): return copy.deepcopy(x)
PEER = {"source_installation_id": uid(1), "host_installation_id": uid(2), "platform": "android"}
DEST = {"binding_id": uid(3), "identity_sha256": "1" * 64, "revision": 1, "host_installation_id": uid(2)}
BUDGETS = {"max_page_items": 1000, "max_page_bytes": 1048576, "max_snapshot_bytes": 67108864, "max_capture_seconds": 120,
           "max_calendar_days": 366000, "cursor_idle_seconds": 600, "cursor_lifetime_seconds": 3600}
DATES = {"type": "exact", "range": {"start_date": "2000-01-01", "end_date": "2000-01-02"}}
NOW = "2000-01-03T00:01:00Z"
ISSUED = "2000-01-03T00:00:00Z"
EXPIRES = "2000-01-03T00:10:00Z"
SETTINGS = {"formats": ["json"], "output_profile": "android-analytical-v5", "subfolder": "", "folder_template": "{year}", "filename_template": "{date}", "write_mode": "overwrite",
    "presentation": {"display_units": "metric", "machine_units": "canonical", "locale": "en-US", "include_metadata": True, "group_by_category": True,
        "frontmatter": {"enabled_field_ids": [], "custom_fields": [], "include_units": True, "include_capture_diagnostics": True}, "markdown": {"style": "tables", "custom_template": "", "placeholder_ids": []}},
    "individual_entries": {"enabled": False, "metric_ids": [], "folder_template": "entries/{year}", "filename_template": "{date}-{record_id}", "category_folders": False},
    "daily_notes": {"enabled": False, "only": False, "folder_template": "notes/{year}", "filename_template": "{date}", "create_if_missing": False, "section_ids": []},
    "packaging": {"type": "loose_files"}, "dictionary": {"type": "none"}}

def selection(ids, source="health_connect"):
    return {"metric_ids": sorted(ids), "category_ids": [], "source_ids": [source], "provider_ids": [], "all_metrics": False}
INTENT = doc("agent_export_intent", intent_id=uid(4), peer=clone(PEER), destination=clone(DEST), dates=clone(DATES), calendar_timezone="Etc/UTC", timestamp_timezone="UTC",
    product={"type": "generated_files"}, capture_scope={"selection": selection(["steps"]), "compatibility_detail": "summary", "native_archive": {"type": "none"}}, settings_policy={"type": "explicit", "settings": clone(SETTINGS)})

OUTPUT_SUPPORT = {"formats": ["csv", "json", "markdown", "obsidian_bases"], "write_modes": ["append", "merge_markdown", "merge_markdown_preserving_preamble", "overwrite"],
    "compatibility_detail": ["selected_time_series", "summary"], "native_archive_products": ["android_provider_native_snapshot_v1", "none"],
    "setting_pointers": sorted(V.leaves(SETTINGS)), "path_tokens": ["category", "date", "day", "metric", "month", "record_id", "year"], "max_artifacts": 4096, "max_path_bytes": 4096}
DELEGATION_BOUNDS = {"products": ["android_source_projection_v1", "generated_files"], "projection_details": ["native_records", "selected_time_series", "summary"],
    "projection_object_ids": ["capture_manifest", "daily_summary", "native_records", "selected_series"], "projection_field_ids": sorted(f["field_id"] for f in S.PROJECTION_CATALOG["fields"]), "metric_ids": ["heart_rate_avg", "steps"], "calendar_timezones": ["Etc/UTC"],
    "date_policy": {"type": "authorized_history", "max_days": 365, "allow_all_available": True},
    "formats": clone(OUTPUT_SUPPORT["formats"]), "output_profiles": ["android-analytical-v5", "android-frozen-v4"], "write_modes": clone(OUTPUT_SUPPORT["write_modes"]),
    "compatibility_detail": clone(OUTPUT_SUPPORT["compatibility_detail"]), "native_archive_products": clone(OUTPUT_SUPPORT["native_archive_products"]),
    "destination_policy": {"type": "authenticated_host_bindings"}}
NATIVE_DELEGATION = doc("agent_export_delegation", authority_id=uid(7), issuer="native_source", grant_revision=1, peer=clone(PEER),
    rights=["discover", "export_execute", "plan"], expires_at="2000-01-03T01:00:00Z", bounds=clone(DELEGATION_BOUNDS))
HOST_DELEGATION = clone(NATIVE_DELEGATION); HOST_DELEGATION.update(authority_id=uid(13), issuer="authorized_host")
HOST_DELEGATION["bounds"]["destination_policy"] = {"type": "registered_host_bindings", "binding_ids": [uid(3), uid(14)]}
AUTHORITY_REFS = {"native": V.authority_reference(NATIVE_DELEGATION), "host": V.authority_reference(HOST_DELEGATION)}
SECOND_DEST = {**DEST, "binding_id": uid(14), "identity_sha256": "f" * 64}
BASE_DISCOVERY = doc("agent_discovery", request_id=uid(100), peer=clone(PEER), capability_revision=1, issued_at=ISSUED, expires_at=EXPIRES,
    source_calendar_timezone="Etc/UTC", features=["bound_execution", "explicit_settings", "profile_dictionary", "zero_health_plan", "zip"], settings_policies=["explicit", "profile", "saved_device_settings"],
    output_profiles=["android-analytical-v5", "android-frozen-v4"], projection_products=[], projection_catalog_sha256="0" * 64, query_catalog_sha256="0" * 64, query_operations=[], budgets=clone(BUDGETS), output_support=clone(OUTPUT_SUPPORT), control_operations=[], authority_references=[clone(AUTHORITY_REFS["native"])],
    lifecycle="android_user_started_service_after_first_unlock", configuration_protection="locked", native_grants="satisfied", entitlement="satisfied", required_actions=[])
BASE_DISCOVERY["capability_sha256"] = V.capability_digest(BASE_DISCOVERY)

def make_plan(intent=INTENT, effective=SETTINGS, capabilities=BASE_DISCOVERY):
    projection = V.is_projection(intent)
    policy = {"type": "explicit"} if projection else intent["settings_policy"]
    if projection: effective = intent["product"]["output"]
    origin = "request" if policy["type"] == "explicit" else policy["type"]
    revision = policy.get("expected_revision", 0)
    output_key = "effective_projection_output" if projection else "effective_settings"
    origins = [{"pointer": p, "origin": origin, "revision": revision} for p in V.leaves(effective, "/" + output_key)]
    origins += [{"pointer": p, "origin": "request", "revision": 0} for p in V.leaves(intent["capture_scope"], "/capture_scope")]
    if projection: origins += [{"pointer": p, "origin": "request", "revision": 0} for p in V.leaves(intent["product"]["request"], "/projection_request")]
    origins += [{"pointer": "/resolved_dates", "origin": "resolved_calendar", "revision": 0}, {"pointer": "/calendar_timezone", "origin": "request", "revision": 0}]
    resolved = V.dates(intent["dates"], intent["calendar_timezone"])
    metrics = V.resolve_selection(intent["capture_scope"]["selection"], intent["peer"]["platform"], V.registry(ROOT))
    revisions = []
    if revision: revisions = [{"domain": "native_profile" if policy["type"] == "profile" else "device_settings", "object_id": policy.get("profile_id", uid(5)), "revision": revision, "sha256": V.digest(effective)}]
    entries = not projection and effective["individual_entries"]["enabled"]
    plan = doc("agent_export_plan", plan_id=uid(6), intent=clone(intent), resolved_dates=resolved, resolved_metric_ids=metrics,
        **{output_key: clone(effective)}, authority_references=clone(AUTHORITY_REFS), origins=sorted(origins, key=lambda x: x["pointer"]),
        revisions=revisions, settings_sha256=V.digest(effective), scope_sha256=V.digest(V.export_scope_payload(intent, resolved, metrics)),
        capability_sha256=capabilities["capability_sha256"], issued_at=ISSUED, expires_at=EXPIRES, predicted_paths=V.projection_paths(intent, effective) if projection else V.predicted_paths(intent, effective),
        path_prediction="template_only_all_available" if resolved["type"] == "all_available" else "deferred_native_entries" if entries else "exact_requested_days", required_actions=[],
        limitations=["history_bounds_unresolved"] if resolved["type"] == "all_available" else ["entry_paths_unresolved"] if entries else [], side_effects={k: 0 for k in S.D["zero_control_effects"]["properties"]})
    plan["plan_sha256"] = V.digest(plan)
    return plan

PLAN = make_plan()
AUTH = doc("agent_authority", authority_id=uid(7), issuer="native_source", peer=clone(PEER), rights=sorted(S.rights), scope_sha256=PLAN["scope_sha256"], destination_binding_ids=[uid(3)], expires_at=EXPIRES,
    configuration_protection="unlocked_native", native_consent="satisfied", entitlement="satisfied", grant_revision=1)
APPROVAL = doc("agent_approval", approval_id=uid(8), authority_id=uid(7), binding=V.binding(PLAN), rights=["export_execute"], approved_at="2000-01-03T00:00:30Z")
EXECUTE = doc("agent_execute_request", request_id=uid(9), job_id=uid(10), idempotency_key=uid(11), plan=clone(PLAN), approval=clone(APPROVAL))
EXPORT_AUTH = V.derived_export_authority(NATIVE_DELEGATION, PLAN, AUTH)
HOST_AUTH = V.derived_export_authority(HOST_DELEGATION, PLAN, AUTH)
CONTEXT = {"now": NOW, "peer": clone(PEER), "destination": clone(DEST), "capability_sha256": PLAN["capability_sha256"], "capabilities": clone(BASE_DISCOVERY), "revisions": [], "authority": clone(EXPORT_AUTH), "host_authority": clone(HOST_AUTH),
    "stored_native_delegations": {uid(7): clone(NATIVE_DELEGATION)}, "stored_host_delegations": {uid(13): clone(HOST_DELEGATION)}, "registered_destinations": {uid(3): clone(DEST), uid(14): clone(SECOND_DEST)},
    "issued_approval_ids": [uid(8)], "issued_approvals": {uid(8): V.digest(APPROVAL)}, "issued_plans": {uid(6): PLAN["plan_sha256"]}, "plan": clone(PLAN), "approved_export_binding_sha256": V.digest(V.binding(PLAN))}
PLAN_REQUEST = doc("agent_plan_request", request_id=uid(101), intent=clone(INTENT), authority_id=uid(7), authority_revision=1, host_authority_reference=clone(AUTHORITY_REFS["host"]), capability_sha256=BASE_DISCOVERY["capability_sha256"])
APPROVAL_REQUEST = doc("agent_approval_request", request_id=uid(103), plan_id=PLAN["plan_id"], binding=V.binding(PLAN))

CASES = []
def case(name, family, value, expected="valid", context=None):
    row = {"id": name, "family": family, "value": clone(value), "expected": expected}
    if context is not None:
        row["context"] = clone(context)
        request = value if isinstance(value, dict) and value.get("schema") == "healthmd.source_query_request" else context.get("request")
        if request and "catalog" in context and "authority" not in context:
            authority = clone(AUTH); authority["scope_sha256"] = V.query_scope_hash(request); authority["peer"] = clone(request["peer"])
            row["context"].update(authority=authority, now=NOW)
    CASES.append(row); return row

def mutation(name, family, base, change, expected="invalid_request", context=None):
    value = clone(base); change(value); return case(name, family, value, expected, context)

def rehash_plan(p):
    p["settings_sha256"] = V.digest(V.effective_output(p))
    p["plan_sha256"] = V.digest({k: v for k, v in p.items() if k != "plan_sha256"})

case("intent-request-owned-summary", "agent", INTENT)
case("zero-health-plan-year-json", "agent", PLAN)
case("approved-execution", "agent", EXECUTE, context=CONTEXT)
for policy in ["saved_device_settings", "profile"]:
    i = clone(INTENT); i["settings_policy"] = {"type": policy, "expected_revision": 2}
    if policy == "profile": i["settings_policy"]["profile_id"] = uid(12)
    p = make_plan(i); case("plan-" + policy, "agent", p)
    mutation("stale-" + policy, "agent", p, lambda x: x["intent"]["settings_policy"].update(expected_revision=3), "binding_changed")
all_intent = clone(INTENT); all_intent["dates"] = {"type": "all_available"}
case("all-available-logical-no-date-discovery", "agent", make_plan(all_intent))
relative = clone(INTENT); relative["dates"] = {"type": "past_complete_days", "days": 2, "anchor_date": "2000-01-03"}
case("relative-freezes-before-execution", "agent", make_plan(relative))
apple = clone(INTENT); apple["peer"]["platform"] = "apple"; apple["capture_scope"]["selection"] = selection(["steps"], "apple_health")
apple["settings_policy"]["settings"]["output_profile"] = "apple-v8"
case("apple-same-intent", "agent", make_plan(apple, apple["settings_policy"]["settings"]))
for detail, archive in [("selected_time_series", {"type": "none"}), ("summary", {"type": "apple_healthkit_canonical_v1"}), ("selected_time_series", {"type": "apple_healthkit_canonical_v1"})]:
    i = clone(apple); i["capture_scope"].update(compatibility_detail=detail, native_archive=archive)
    case("apple-two-detail-axes-" + detail + "-" + archive["type"], "agent", i)
i = clone(INTENT); i["capture_scope"]["native_archive"] = {"type": "android_provider_native_snapshot_v1", "provider_id": "health_connect", "record_scope": "selected", "format": "ndjson", "include_exercise_routes": False}
case("android-archive-is-separate-product", "agent", i)
zip_settings = clone(SETTINGS); zip_settings["packaging"] = {"type": "zip", "filename_template": "archive-{date}", "include_loose_files": False, "max_entries": 4096, "max_uncompressed_bytes": 1073741824, "manifest": "healthmd.agent_artifact_manifest/1"}
zip_settings["dictionary"] = {"type": "profile_dictionary_v1", "filename_template": "dictionary", "format": "json"}
i = clone(INTENT); i["settings_policy"]["settings"] = zip_settings
case("explicit-zip-dictionary-opt-in", "agent", i)
case("planned-zip-includes-dictionary-no-loose-files", "agent", make_plan(i, zip_settings))
for field, changed, expected in [("peer", {**PEER, "source_installation_id": uid(99)}, "binding_changed"), ("destination", {**DEST, "revision": 2}, "binding_changed"),
    ("capability_sha256", "3" * 64, "binding_changed"), ("revisions", [{"domain": "device_settings", "object_id": uid(5), "revision": 2, "sha256": "4" * 64}], "revision_conflict")]:
    c = clone(CONTEXT); c[field] = changed; case("execution-changed-" + field, "agent", EXECUTE, expected, c)
c = clone(CONTEXT); c["now"] = EXPIRES; case("expired-plan", "agent", EXECUTE, "plan_expired", c)
c = clone(CONTEXT); c["issued_approval_ids"] = []; case("fabricated-approval-id", "agent", EXECUTE, "approval_required", c)
mutation("issued-approval-cannot-be-reinterpreted", "agent", EXECUTE, lambda x: x["approval"].update(approved_at="2000-01-03T00:00:31Z"), "approval_required", CONTEXT)
c = clone(CONTEXT); c["issued_plans"] = {}; case("unissued-plan-digest-not-authority", "agent", EXECUTE, "binding_changed", c)
c = clone(CONTEXT); c["authority"]["rights"] = ["plan"]; case("read-only-plan-not-write", "agent", EXECUTE, "approval_required", c)
c = clone(CONTEXT); c["authority"]["native_consent"] = "required"; case("pairing-not-native-consent", "agent", EXECUTE, "permission_required", c)
c = clone(CONTEXT); c["authority"]["entitlement"] = "required"; case("export-entitlement-required", "agent", EXECUTE, "entitlement_required", c)
c = clone(CONTEXT); c["existing_request_sha256"] = V.digest(EXECUTE); case("idempotent-execute-retry", "agent", EXECUTE, context=c)
late = clone(c); late["now"] = EXPIRES; case("late-exact-retry-returns-stored-receipt-only", "agent", EXECUTE, context=late)
c = clone(CONTEXT); c["existing_request_sha256"] = "5" * 64; case("idempotency-key-reused-new-request", "agent", EXECUTE, "binding_changed", c)
mutation("execute-widen-scope", "agent", EXECUTE, lambda x: x["plan"]["intent"]["capture_scope"]["selection"]["metric_ids"].append("android.hrv_rmssd"), "invalid_request", CONTEXT)
mutation("zero-health-plan-refuses-health-reads", "agent", PLAN, lambda x: x["side_effects"].update(health_reads=1))
mutation("all-available-cannot-promise-exact-paths", "agent", make_plan(all_intent), lambda x: x.update(predicted_paths=["2000/file.json"]), "binding_changed")
mutation("origin-required-for-every-setting", "agent", PLAN, lambda x: (x["origins"].pop(), rehash_plan(x)))
mutation("no-hidden-format-inheritance", "agent", PLAN, lambda x: (x["effective_settings"].update(formats=["csv", "json"]), rehash_plan(x)), "binding_changed")
mutation("no-healthkit-on-android", "agent", INTENT, lambda x: x["capture_scope"].update(native_archive={"type": "apple_healthkit_canonical_v1"}), "unsupported_capability")
mutation("archive-cannot-widen-selected-scope", "agent", i if i["capture_scope"]["native_archive"]["type"] != "none" else INTENT,
    lambda x: x["capture_scope"].update(native_archive={"type": "android_provider_native_snapshot_v1", "provider_id": "health_connect", "record_scope": "all_authorized_supported", "format": "ndjson", "include_exercise_routes": False}), "binding_changed")
for unsafe in ["/absolute", "../escape", "a//b", "a/./b", "a\\b", "C:drive", "a%2fb", "content://grant", "CON", "a.", "a/../b", "{unknown}", "{date/../../}", "a\u0000b"]:
    case("unsafe-path-" + str(len(CASES)), "path", unsafe, "unsafe_path", {"templates": True})
case("bounded-year-date-template", "path", "{year}/{date}", context={"templates": True})
case("case-alias-collision", "collision", ["folder/A.json", "folder/a.json"], "path_collision")
case("unicode-alias-collision", "collision", ["caf\u00e9.json", "cafe\u0301.json"], "path_collision")
mutation("path-date-collision", "agent", INTENT, lambda x: x["settings_policy"]["settings"].update(filename_template="fixed"), "valid") # intent valid; plan detects collision below
collision_i = clone(INTENT); collision_i["settings_policy"]["settings"].update(filename_template="fixed")
try: make_plan(collision_i, collision_i["settings_policy"]["settings"])
except V.Invalid: case("expanded-day-path-collision", "collision", ["2000/fixed.json", "2000/fixed.json"], "path_collision")
mutation("no-portable-credentials", "agent", INTENT, lambda x: x.update(credentials="synthetic"))
mutation("no-desktop-path-to-phone", "agent", INTENT, lambda x: x["destination"].update(root_path="synthetic"))
mutation("profile-no-name-fallback", "agent", INTENT, lambda x: x.update(settings_policy={"type": "profile", "profile_id": uid(12), "expected_revision": 1, "name": "synthetic"}))
mutation("schema-bool-is-not-version", "agent", INTENT, lambda x: x.update(schema_version=True))

RESUME = doc("agent_resume_request", job_id=uid(10), peer=clone(PEER), destination=clone(DEST), binding=V.binding(PLAN), request_sha256=V.digest(EXECUTE), manifest_sha256="6" * 64, committed_partition_count=1, frontier_sha256="7" * 64)
case("resume-pinned-journal", "resume", RESUME, context={"journal_resume": RESUME})
for field, value in [("destination", {**DEST, "revision": 2}), ("request_sha256", "8" * 64), ("frontier_sha256", "9" * 64)]:
    mutation("resume-change-" + field, "resume", RESUME, lambda x, k=field, v=value: x.update({k: v}), "binding_changed", {"journal_resume": RESUME})
RECEIPT = doc("agent_execution_receipt", job_id=uid(10), binding=V.binding(PLAN), request_sha256=V.digest(EXECUTE), manifest_sha256="6" * 64, status="complete", source_acknowledged=True, artifact_count=1, committed_partition_count=1, frontier_sha256="7" * 64, expires_at="2000-01-10T00:00:00Z")
case("source-confirmed-completion", "agent", RECEIPT)
mutation("local-intent-not-terminal-cancellation", "agent", RECEIPT, lambda x: x.update(status="cancelled", source_acknowledged=False))
COMMIT = doc("agent_commit_receipt", job_id=uid(10), artifact_id=uid(20), peer=clone(PEER), destination=clone(DEST), request_sha256=V.digest(EXECUTE), manifest_sha256="6" * 64,
    relative_path="2000/2000-01-01.json", write_mode="append", input_sha256="a" * 64, before_sha256="b" * 64, after_sha256="c" * 64, status="committed")
COMMIT["commit_key"] = V.digest({k: COMMIT[k] for k in ("job_id", "artifact_id", "destination", "request_sha256", "manifest_sha256", "relative_path", "write_mode", "input_sha256", "before_sha256", "after_sha256")})
case("durable-append-commit", "agent", COMMIT)
mutation("commit-replay-once", "agent", COMMIT, lambda x: x.update(status="already_committed"), "valid", context={"persisted_commit": COMMIT})
mutation("commit-content-changed", "agent", COMMIT, lambda x: x.update(input_sha256="d" * 64), "binding_changed")
MANIFEST = doc("agent_artifact_manifest", job_id=uid(10), request_sha256=V.digest(EXECUTE), binding=V.binding(PLAN), artifacts=[{"artifact_id": uid(20), "relative_path": COMMIT["relative_path"], "media_type": "application/json", "byte_count": 32, "sha256": "a" * 64, "write_mode": "append", "profile": "android-analytical-v5"}], capture_status="complete", branch_statuses=[{"selector_id": "steps", "status": "success", "record_count": 1}])
case("immutable-artifact-manifest", "agent", MANIFEST)
mutation("unsupported-branch-not-complete", "agent", MANIFEST, lambda x: x["branch_statuses"][0].update(status="unsupported"))

# Bootstrap: existing paired/native delegation + existing host-approved roots, no plan-time enrollment.
case("bootstrap-stored-native-delegation-description", "agent", NATIVE_DELEGATION)
case("bootstrap-stored-host-delegation-description", "agent", HOST_DELEGATION)
case("bootstrap-first-plan-request", "agent", PLAN_REQUEST, context=CONTEXT)
case("bootstrap-first-approval-request", "agent", APPROVAL_REQUEST, context=CONTEXT)
for slot in ("native", "host"):
    c = clone(CONTEXT); c["stored_" + slot + "_delegations"] = {}
    case("bootstrap-caller-reference-not-" + slot + "-grant", "agent", PLAN_REQUEST, "approval_required", c)
    c = clone(CONTEXT); next(iter(c["stored_" + slot + "_delegations"].values()))["grant_revision"] = 2
    case("bootstrap-stale-" + slot + "-delegation", "agent", PLAN_REQUEST, "approval_required", c)
    c = clone(CONTEXT); c["stored_" + slot + "_delegations"][uid(7 if slot == "native" else 13)]["expires_at"] = NOW
    case("bootstrap-expired-" + slot + "-delegation", "agent", PLAN_REQUEST, "approval_required", c)
mutation("bootstrap-caller-native-uuid-not-grant", "agent", PLAN_REQUEST, lambda x: x.update(authority_id=uid(99)), "approval_required", CONTEXT)
mutation("bootstrap-caller-host-uuid-not-grant", "agent", PLAN_REQUEST, lambda x: x["host_authority_reference"].update(authority_id=uid(99)), "approval_required", CONTEXT)
mutation("bootstrap-delegation-does-not-widen-metrics", "agent", PLAN_REQUEST, lambda x: x["intent"]["capture_scope"].update(selection=selection(["blood_oxygen"])), "approval_required", CONTEXT)
mutation("bootstrap-delegation-does-not-widen-days", "agent", PLAN_REQUEST, lambda x: x["intent"]["dates"]["range"].update(end_date="2001-01-01"), "approval_required", CONTEXT)
mutation("bootstrap-unregistered-root-not-authorized", "agent", PLAN_REQUEST, lambda x: x["intent"]["destination"].update(binding_id=uid(99)), "approval_required", CONTEXT)
c = clone(CONTEXT); c["registered_destinations"][uid(3)]["identity_sha256"] = "0" * 64
case("bootstrap-host-root-identity-changed", "agent", PLAN_REQUEST, "binding_changed", c)
c = clone(CONTEXT); c.pop("approved_export_binding_sha256")
case("bootstrap-approval-request-not-human-decision", "agent", APPROVAL_REQUEST, "approval_required", c)
new_intent = clone(INTENT); new_intent["intent_id"] = uid(104); new_intent["destination"] = clone(SECOND_DEST)
new_intent["capture_scope"]["selection"] = selection(["heart_rate_avg", "steps"])
NEW_PLAN = make_plan(new_intent); NEW_PLAN["plan_id"] = uid(105); rehash_plan(NEW_PLAN)
NEW_APPROVAL = clone(APPROVAL); NEW_APPROVAL.update(approval_id=uid(106), binding=V.binding(NEW_PLAN))
NEW_EXECUTE = clone(EXECUTE); NEW_EXECUTE.update(request_id=uid(107), job_id=uid(108), idempotency_key=uid(109), plan=NEW_PLAN, approval=NEW_APPROVAL)
NEW_CONTEXT = clone(CONTEXT); NEW_CONTEXT.update(destination=clone(SECOND_DEST), plan=clone(NEW_PLAN),
    authority=V.derived_export_authority(NATIVE_DELEGATION, NEW_PLAN, AUTH), host_authority=V.derived_export_authority(HOST_DELEGATION, NEW_PLAN, AUTH),
    issued_plans={NEW_PLAN["plan_id"]: NEW_PLAN["plan_sha256"]}, issued_approval_ids=[uid(106)], issued_approvals={uid(106): V.digest(NEW_APPROVAL)}, approved_export_binding_sha256=V.digest(V.binding(NEW_PLAN)))
new_request = clone(PLAN_REQUEST); new_request.update(request_id=uid(110), intent=new_intent)
case("bootstrap-future-scope-host-destination-first-plan", "agent", new_request, context=NEW_CONTEXT)
case("bootstrap-future-scope-host-destination-new-plan", "agent", NEW_PLAN)
case("bootstrap-future-scope-host-destination-new-approval-request", "agent", doc("agent_approval_request", request_id=uid(111), plan_id=NEW_PLAN["plan_id"], binding=V.binding(NEW_PLAN)), context=NEW_CONTEXT)
case("bootstrap-future-scope-host-destination-approved-execute", "agent", NEW_EXECUTE, context=NEW_CONTEXT)
mutation("bootstrap-old-approval-not-new-scope-destination", "agent", NEW_EXECUTE, lambda x: x.update(approval=clone(APPROVAL)), "binding_changed", NEW_CONTEXT)
c = clone(NEW_CONTEXT); c["authority"] = clone(EXPORT_AUTH)
case("bootstrap-old-derived-scope-not-new-authority", "agent", NEW_EXECUTE, "binding_changed", c)

# Every closed control verb plus candidate-bound plan/approval journeys for all domains.
SCHEDULE = {"recipe_or_profile_id": uid(12), "recipe_or_profile_revision": 2, "calendar_timezone": "Etc/UTC", "cadence": {"value": 1, "unit": "days", "anchor_date": "2000-01-01"},
    "local_time": {"hour": 8, "minute": 0}, "iso_weekday": 1, "lookback_days": 1, "dst_gap": "skip", "dst_fold": "first_occurrence", "catch_up": "one_latest_complete_window", "enabled": False, "destination": clone(DEST)}
NATIVE_DEST = {"type": "existing_native_binding", "binding_id": uid(33), "expected_revision": 3}
NATIVE_READ_SCOPE = {"objects": [{"domain": d, "object_id": uid(12)} for d in ("native_destination", "native_profile", "native_schedule")], "list_domains": ["native_profile"], "create_domains": ["native_profile"]}
HOST_READ_SCOPE = {"objects": [{"domain": d, "object_id": uid(12)} for d in ("host_schedule", "local_recipe")], "list_domains": ["host_schedule", "local_recipe"], "create_domains": ["host_schedule", "local_recipe"]}
PLANNING_AUTH = clone(AUTH); PLANNING_AUTH.update(authority_id=uid(34), rights=["native_configuration_read"], control_read_scope=clone(NATIVE_READ_SCOPE), scope_sha256=V.digest(NATIVE_READ_SCOPE), configuration_protection="locked")
CONTROL_DISCOVERY = clone(BASE_DISCOVERY)
CONTROL_DISCOVERY["configuration_protection"] = "unlocked_native"
CONTROL_DISCOVERY["features"] = sorted([*CONTROL_DISCOVERY["features"], "control_plan", "native_destination_control", "native_profile_control", "native_schedule_control"])
CONTROL_DISCOVERY["control_operations"] = sorted(domain + "." + verb for domain, verbs in S.CONTROL_VERBS.items() for verb in [*verbs, "plan"])
CONTROL_DISCOVERY["authority_references"].append({"authority_id": uid(34), "issuer": "native_source", "grant_revision": 1, "grant_sha256": V.digest(PLANNING_AUTH)})
CONTROL_DISCOVERY["capability_sha256"] = V.capability_digest(CONTROL_DISCOVERY)

def proposal(domain, verb):
    p = {"domain": domain, "verb": verb, "object_id": uid(12), "expected_revision": 0 if verb == "create" else 2}
    if verb in ("create", "update"):
        p["value"] = {"name": "Synthetic recipe", "intent": clone(INTENT)} if domain == "local_recipe" else {"name": "Synthetic profile", "capture_scope": clone(INTENT["capture_scope"]), "settings": clone(SETTINGS), "destination": clone(NATIVE_DEST)} if domain == "native_profile" else clone(NATIVE_DEST) if domain == "native_destination" else clone(SCHEDULE)
        if domain == "native_schedule": p["value"]["destination"] = clone(NATIVE_DEST)
    if verb == "discard_pending": p["pending_binding_sha256"] = "a" * 64
    return p

def make_control_plan(p):
    revisions = []
    def pin(domain, object_id, revision):
        revisions.append({"domain": domain, "object_id": object_id, "revision": revision, "sha256": "5" * 64})
    if p["expected_revision"]: pin(p["domain"], p["object_id"], p["expected_revision"])
    value = p.get("value", {})
    if p["domain"] in ("host_schedule", "native_schedule") and value:
        pin("local_recipe" if p["domain"] == "host_schedule" else "native_profile", value["recipe_or_profile_id"], value["recipe_or_profile_revision"])
    destination = value if p["domain"] == "native_destination" else value.get("destination", {})
    if destination.get("type") == "existing_native_binding": pin("native_destination", destination["binding_id"], destination["expected_revision"])
    if destination.get("type") == "endpoint_disclosure": pin("native_credential_reference", destination["credential_reference_id"], 1)
    cp = doc("agent_control_plan", plan_id=uid(38), request_id=uid(30), planning_authority_id=uid(34), peer=clone(PEER), proposal=clone(p), proposal_sha256=V.digest(p),
        scope_sha256=V.digest({"peer": PEER, "proposal": p, "revisions": sorted(revisions, key=lambda r: (r["domain"], r["object_id"]))}), capability_sha256=CONTROL_DISCOVERY["capability_sha256"],
        revisions=sorted(revisions, key=lambda r: (r["domain"], r["object_id"])), required_right=V.control_right(p["domain"], p["verb"]), issued_at=ISSUED, expires_at=EXPIRES,
        required_actions=["native_destination_rebind"] if destination.get("type") == "requires_native_rebind" else [],
        side_effects={k: 0 for k in S.D["zero_control_effects"]["properties"]})
    cp["plan_sha256"] = V.digest(cp); return cp

def control_journey(p):
    cp = make_control_plan(p)
    owner = "native_source" if p["domain"].startswith("native_") else "authorized_host"
    authority = clone(AUTH); authority.update(authority_id=uid(35), issuer=owner, scope_sha256=cp["scope_sha256"], rights=[cp["required_right"]])
    planning_authority = clone(PLANNING_AUTH)
    if owner == "authorized_host": planning_authority.update(issuer=owner, rights=["host_schedule_read", "recipe_read"], control_read_scope=clone(HOST_READ_SCOPE), scope_sha256=V.digest(HOST_READ_SCOPE))
    approved = doc("agent_control_approval", approval_id=uid(39), authority_id=uid(35), authority_reference=V.authority_reference(authority), binding=V.control_binding(cp), right=cp["required_right"], approved_at="2000-01-03T00:00:30Z")
    request = doc("agent_control_request", operation={**clone(p), "request_id": uid(30), "authority_id": uid(35), "peer": clone(PEER), "idempotency_key": uid(31), "plan": clone(cp), "approval": clone(approved)})
    c = {"peer": clone(PEER), "authority": authority, "planning_authority": planning_authority, "stored_planning_authority_ids": [uid(34)], "planning_scope_sha256": PLANNING_AUTH["scope_sha256"],
        "now": NOW, "current_revision": p["expected_revision"], "current_revisions": clone(cp["revisions"]), "capabilities": clone(CONTROL_DISCOVERY), "control_plan": clone(cp),
        "issued_control_plans": {cp["plan_id"]: cp["plan_sha256"]}, "issued_control_approvals": {approved["approval_id"]: V.digest(approved)}, "native_or_host_decision_binding_sha256": V.digest(V.control_binding(cp)), "pending_binding_sha256": "a" * 64}
    plan_request = doc("agent_control_plan_request", request_id=uid(30), authority_id=uid(34), peer=clone(PEER), capability_sha256=cp["capability_sha256"], proposal=clone(p))
    approval_request = doc("agent_control_approval_request", request_id=uid(40), authority_id=uid(35), binding=V.control_binding(cp))
    return plan_request, cp, approval_request, approved, request, c

CONTROL_JOURNEYS = {}
for domain, verbs in S.CONTROL_VERBS.items():
    for verb in [*verbs, "plan"]:
        if verb in S.READ_VERBS:
            op = {"domain": domain, "verb": verb, "request_id": uid(30), "authority_id": uid(34), "peer": clone(PEER)}
            if verb != "list": op.update(object_id=uid(12), expected_revision=2)
            planning_authority = clone(PLANNING_AUTH)
            if not domain.startswith("native_"): planning_authority.update(issuer="authorized_host", rights=["host_schedule_read", "recipe_read"], control_read_scope=clone(HOST_READ_SCOPE), scope_sha256=V.digest(HOST_READ_SCOPE))
            c = {"planning_authority": planning_authority, "stored_planning_authority_ids": [uid(34)], "planning_scope_sha256": PLANNING_AUTH["scope_sha256"], "now": NOW, "current_revision": op.get("expected_revision", 0)}
            request = doc("agent_control_request", operation=op)
        else:
            journey = control_journey(proposal(domain, "update" if verb == "plan" else verb))
            plan_request, cp, approval_request, approved, request, c = journey
            if verb == "plan":
                op = {"domain": domain, "verb": "plan", **{k: clone(plan_request[k]) for k in ("request_id", "authority_id", "peer", "capability_sha256", "proposal")}}
                request = doc("agent_control_request", operation=op)
                CONTROL_JOURNEYS[domain] = journey
                for suffix, value in (("plan-request", plan_request), ("plan-response", cp), ("approval-request", approval_request), ("approval-response", approved)):
                    case("control-journey-" + domain + "-" + suffix, "agent", value, context=c)
        case("control-" + domain + "-" + verb, "control", request, context=c)
        if domain == "native_profile" and verb == "update":
            for name, changed, expected in (("native-configuration-protection", {"configuration_protection": "locked"}, "configuration_protected"),
                ("native-consent-not-configuration-grant", {"native_consent": "required"}, "permission_required"), ("native-configuration-entitlement", {"entitlement": "required"}, "entitlement_required")):
                bad = clone(c); bad["authority"].update(changed); case(name, "control", request, expected, bad)
            bad = clone(c); bad["current_revision"] = 3; case("native-stale-revision", "control", request, "revision_conflict", bad)
            bad = clone(c); bad["import_blocked"] = True; case("imported-profile-rebind-block", "control", request, "native_rebind_required", bad)
        if domain == "native_profile" and verb == "delete":
            bad = clone(c); bad["last_profile"] = True; case("native-last-profile-invariant", "control", request, "invalid_request", bad)

for domain, journey in CONTROL_JOURNEYS.items():
    plan_request, cp, approval_request, approved, request, c = journey
    mutation("control-no-candidate-" + domain, "agent", plan_request, lambda x: x.pop("proposal"), context=c)
    mutation("control-changed-candidate-" + domain, "control", request, lambda x: x["operation"].update(value={}), context=c)
    mutation("control-changed-value-bound-" + domain, "control", request, lambda x: x["operation"].update(value=clone(cp["proposal"]["value"]) | {"synthetic_unknown": True}), context=c)
    bad = clone(c); bad["issued_control_plans"] = {}; case("control-unissued-plan-" + domain, "control", request, "binding_changed", bad)
    bad = clone(c); bad["issued_control_approvals"] = {}; case("control-unissued-approval-" + domain, "control", request, "approval_required", bad)
    bad = clone(c); bad.pop("native_or_host_decision_binding_sha256"); case("control-request-not-native-decision-" + domain, "agent", approval_request, "approval_required", bad)
    bad = clone(c); bad["now"] = EXPIRES; case("control-expired-plan-" + domain, "control", request, "plan_expired", bad)
    bad = clone(c); bad["existing_control_request_sha256"] = V.digest(request); bad["now"] = EXPIRES; bad["current_revision"] = 3
    case("control-exact-retry-stored-receipt-only-" + domain, "control", request, context=bad)
    mutation("control-idempotency-new-request-" + domain, "control", request, lambda x: x["operation"].update(request_id=uid(99)), "binding_changed", bad)
    mutation("control-approval-id-alone-not-authority-" + domain, "control", request, lambda x: (x["operation"].pop("plan"), x["operation"].pop("approval"), x["operation"].update(approval_id=uid(39))), context=c)

CONTROL_PLAN_REQUEST, CONTROL_PLAN, CONTROL_APPROVAL_REQUEST, CONTROL_APPROVAL, CONTROL_REQUEST, CONTROL_CONTEXT = CONTROL_JOURNEYS["native_profile"]
locked_plan_request = clone(CONTROL_PLAN_REQUEST); locked_context = clone(CONTROL_CONTEXT)
locked_context["capabilities"]["configuration_protection"] = "locked"
locked_context["capabilities"]["capability_sha256"] = V.capability_digest(locked_context["capabilities"])
locked_plan_request["capability_sha256"] = locked_context["capabilities"]["capability_sha256"]
case("control-planning-while-native-protection-locked", "agent", locked_plan_request, context=locked_context)
lookup_approval_request = clone(CONTROL_APPROVAL_REQUEST); lookup_approval_request.pop("authority_id")
case("control-approval-reference-from-existing-native-decision", "agent", lookup_approval_request, context=CONTROL_CONTEXT)
bad = clone(CONTROL_CONTEXT); bad.pop("native_or_host_decision_binding_sha256")
case("control-approval-no-id-never-mints-native-decision", "agent", lookup_approval_request, "approval_required", bad)
bad = clone(CONTROL_CONTEXT); bad["authority"]["grant_revision"] += 1
case("control-native-grant-revision-requires-fresh-approval", "control", CONTROL_REQUEST, "approval_required", bad)
for field in CONTROL_PLAN["side_effects"]:
    mutation("control-plan-zero-" + field, "agent", CONTROL_PLAN, lambda x, f=field: x["side_effects"].update({f: 1}))
mutation("control-plan-caller-object-id-not-inspection-authority", "agent", CONTROL_PLAN_REQUEST, lambda x: x["proposal"].update(object_id=uid(99)), "approval_required", CONTROL_CONTEXT)
mutation("control-proposal-value-changed-after-plan", "control", CONTROL_REQUEST, lambda x: x["operation"]["value"].update(name="Changed synthetic profile"), "binding_changed", CONTROL_CONTEXT)
mutation("control-approval-binding-changed", "control", CONTROL_REQUEST, lambda x: x["operation"]["approval"]["binding"].update(proposal_sha256="f" * 64), "binding_changed", CONTROL_CONTEXT)
mutation("control-approval-right-cannot-be-reinterpreted", "control", CONTROL_REQUEST, lambda x: x["operation"]["approval"].update(right="native_schedule_mutate"), "binding_changed", CONTROL_CONTEXT)
for changed_domain in ("native_destination", "native_profile"):
    bad = clone(CONTROL_CONTEXT); bad["current_revisions"] = clone(CONTROL_PLAN["revisions"])
    next(r for r in bad["current_revisions"] if r["domain"] == changed_domain)["revision"] += 1
    case("control-current-dependency-changed-" + changed_domain, "control", CONTROL_REQUEST, "revision_conflict", bad)
bad = clone(CONTROL_CONTEXT); bad["authority"] = clone(EXPORT_AUTH)
case("bootstrap-export-delegation-not-configuration-authority", "control", CONTROL_REQUEST, "approval_required", bad)
CONTROL_RECEIPT = doc("agent_control_receipt", request_id=uid(30), domain="native_profile", status="success", object_id=uid(12), previous_revision=2, revision=3,
    value_sha256=V.digest(CONTROL_PLAN["proposal"]["value"]), items=[], required_actions=[], mutation_binding={"binding": V.control_binding(CONTROL_PLAN), "approval_id": uid(39), "request_sha256": V.digest(CONTROL_REQUEST)})
case("control-bound-mutation-receipt", "agent", CONTROL_RECEIPT, context={"control_request": CONTROL_REQUEST})
mutation("control-receipt-not-another-request", "agent", CONTROL_RECEIPT, lambda x: x["mutation_binding"].update(request_sha256="f" * 64), "binding_changed", {"control_request": CONTROL_REQUEST})
endpoint = {"type": "endpoint_disclosure", "scheme": "https", "host": "synthetic.example", "port": 443, "path": "/export", "query_omitted": True, "credential_reference_id": uid(41)}
endpoint["disclosure_sha256"] = V.digest(endpoint)
p = proposal("native_destination", "update"); p["value"] = endpoint
endpoint_journey = control_journey(p)
case("control-exact-endpoint-credential-reference", "control", endpoint_journey[4], context=endpoint_journey[5])
mutation("control-endpoint-digest-not-caller-claim", "agent", endpoint_journey[0], lambda x: x["proposal"]["value"].update(disclosure_sha256="f" * 64), "binding_changed", endpoint_journey[5])
bad = clone(endpoint_journey[5]); next(r for r in bad["current_revisions"] if r["domain"] == "native_credential_reference")["revision"] += 1
case("control-credential-rotation-requires-new-plan", "control", endpoint_journey[4], "revision_conflict", bad)
p = proposal("native_profile", "update"); p["value"]["destination"] = {"type": "requires_native_rebind", "kind": "device_folder"}
rebind_journey = control_journey(p)
case("control-unbound-candidate-zero-health-plan", "agent", rebind_journey[1])
case("control-unbound-candidate-cannot-mutate", "control", rebind_journey[4], "native_rebind_required", rebind_journey[5])
plan_request, cp, approval_request, approved, request, c = CONTROL_JOURNEYS["native_schedule"]
mutation("control-schedule-cadence-changed-after-plan", "control", request, lambda x: x["operation"]["value"]["cadence"].update(value=2), "binding_changed", c)
mutation("control-schedule-profile-changed-after-plan", "control", request, lambda x: x["operation"]["value"].update(recipe_or_profile_revision=3), "binding_changed", c)
plan_request, cp, approval_request, approved, request, c = CONTROL_JOURNEYS["native_destination"]
mutation("control-destination-binding-changed-after-plan", "control", request, lambda x: x["operation"]["value"].update(binding_id=uid(99)), "binding_changed", c)
mutation("control-plan-branch-wrong-domain", "control", next(row["value"] for row in CASES if row["id"] == "control-native_profile-plan"), lambda x: x["operation"].update(proposal=clone(cp["proposal"])), context=CONTROL_CONTEXT)
# Rehashing all client-supplied boxes never creates a source-issued plan or approval.
forged = clone(CONTROL_REQUEST); op = forged["operation"]; op["value"]["name"] = "Unissued synthetic candidate"; op["plan"]["proposal"]["value"] = clone(op["value"])
op["plan"]["proposal_sha256"] = V.digest(op["plan"]["proposal"])
op["plan"]["scope_sha256"] = V.digest({k: op["plan"][k] for k in ("peer", "proposal", "revisions")})
op["plan"]["plan_sha256"] = V.digest({k: v for k, v in op["plan"].items() if k != "plan_sha256"})
op["approval"]["binding"] = V.control_binding(op["plan"])
case("control-rehashed-client-boxes-not-issued-authority", "control", forged, "approval_required", CONTROL_CONTEXT)

# Reviewed query meanings use existing registry IDs; no new metric-registry rows.
rows = V.registry(ROOT)
HC_PREFIX = "androidx.health.connect.client.records."
NATIVE_TYPES = {"steps": HC_PREFIX + "StepsRecord", "heart_rate": HC_PREFIX + "HeartRateRecord", "heart_rate_variability_rmssd": HC_PREFIX + "HeartRateVariabilityRmssdRecord",
    "skin_temperature": HC_PREFIX + "SkinTemperatureRecord", "sleep_session": HC_PREFIX + "SleepSessionRecord", "exercise_session": HC_PREFIX + "ExerciseSessionRecord",
    "oxygen_saturation": HC_PREFIX + "OxygenSaturationRecord", "medical_resource": HC_PREFIX + "MedicalResource",
    "healthkit_sdnn": None, "healthkit_wrist_temperature": None, "healthkit_clinical_record": None}
def metric_row(mid, unit, stats, native, reducer, owner="civil_day_aggregate", availability="planned", feature="", evidence=True):
    return {"type": "catalog_metric", "metric_id": mid, "registry_equivalence": rows[mid]["equivalence"], "unit": unit, "statistics": sorted(stats), **({"native_record_type": NATIVE_TYPES[native]} if NATIVE_TYPES[native] else {}),
        "source_statistic": reducer, "owner_rule": owner, "availability": availability, "target_or_reason": "B06 native capture; B07 source-aware dispatch" if availability == "planned" else "No reviewed Health Connect equivalent or alias approval",
        "feature_gate": feature, "evidence_value_support": evidence}
METRICS = [metric_row("steps", "steps", ["sum", "count"], "steps", "StepsRecord.COUNT_TOTAL"),
    metric_row("heart_rate_avg", "bpm", ["average"], "heart_rate", "HeartRateRecord.BPM_AVG"),
    metric_row("android.hrv_rmssd", "ms", ["latest", "average", "minimum", "maximum"], "heart_rate_variability_rmssd", "latest_same_day_exact_record", "source_start_civil_day"),
    metric_row("hrv", "ms", ["average"], "healthkit_sdnn", "HKStatistics.discreteAverage", availability="unavailable"),
    metric_row("wrist_temperature", "degC", ["latest"], "healthkit_wrist_temperature", "HealthKit_most_recent", availability="unavailable"),
    metric_row("android.skin_temperature", "degC_delta", ["average", "minimum", "maximum"], "skin_temperature", "SkinTemperatureRecord.TEMPERATURE_DELTA_AVG_MIN_MAX", feature="FEATURE_SKIN_TEMPERATURE"),
    metric_row("sleep_total", "hours", ["duration_sum"], "sleep_session", "native_noon_journal_additive_clipped_intervals", "noon_to_noon_additive_native"),
    metric_row("sleep_core", "hours", ["duration_sum"], "sleep_session", "historical_light_core_alias_not_query_authority", availability="unavailable"),
    metric_row("workouts", "count", ["count"], "exercise_session", "native_identity_listing", "source_start_civil_day"),
    metric_row("blood_oxygen", "ratio", ["latest", "average", "minimum", "maximum"], "oxygen_saturation", "Percentage.value_divided_by_100", "source_start_civil_day"),
    metric_row("android.medical_resources", "unitless", ["count"], "medical_resource", "PHR_not_medication_dose_event", availability="unavailable", feature="FEATURE_PERSONAL_HEALTH_RECORD"),
    metric_row("clinical_medication_records", "unitless", ["count"], "healthkit_clinical_record", "current_App_Store_clinical_capture_disabled", availability="unavailable")]
COVERAGE = {"status": "complete", "days_considered": 2, "days_with_values": 1, "missing_count": 0, "missing_truncated": False, "missing": [], "history": {"state": "full_granted", "feature_status": "available"}}
CATALOG = doc("source_query_catalog", peer=clone(PEER), source_id="health_connect", provider_id="health_connect", sdk_version="1.2.0-alpha02", provider_version="synthetic-not-qualified", provider_availability="unverified",
    feature_statuses=[{"feature": "skin_temperature", "status": "unverified"}], metrics=sorted(METRICS, key=lambda x: x["metric_id"]), operations=sorted(S.item_types), budgets=clone(BUDGETS), history=clone(COVERAGE))
REVIEWED_CATALOG = clone(CATALOG) # Planning targets only, not an installed capability advertisement.
REVIEWED_CATALOG["history"].update(status="unavailable", days_considered=0, days_with_values=0, history={"state": "unverified", "feature_status": "error"})
for row in CATALOG["metrics"]:
    if row["availability"] == "planned": row["availability"] = "supported" # hypothetical fake-peer response only
CATALOG["provider_availability"] = "available" # synthetic; never a device observation
CATALOG["feature_statuses"][0]["status"] = "available" # fake installed provider only
case("source-aware-catalog", "query", REVIEWED_CATALOG)
EXACT = {"epoch_second": 946684800, "nanosecond": 123456789, "source_offset_seconds": None, "precision": "source_nanoseconds"}
IDENTITY = {"source_id": "health_connect", "provider_id": "health_connect", "record_type": NATIVE_TYPES["steps"], "record_id": "synthetic-native-id", "identity_kind": "native", "origin": "synthetic.origin", "client_record_id": "synthetic-client-id", "client_record_version": 0, "last_modified": clone(EXACT),
    "metadata_status": {"last_modified": "available", "client_record_id": "available", "client_record_version": "available"}}

def fact(mid="steps", stat="sum", unit="steps", n=1):
    return {"type": "metric", "metric_id": mid, "owner_date": "2000-01-01", "unit": unit, "statistic": stat, "availability": "available", "value": {"type": "integer", "value": n}, "evidence_ids": []}
def session(kind):
    identity = clone(IDENTITY); identity["record_type"] = NATIVE_TYPES["sleep_session" if kind == "sleep" else "exercise_session"]
    return {"type": "session", "kind": kind, "owner_date": "2000-01-01", "identity": identity, "start": clone(EXACT), "end": {**EXACT, "epoch_second": EXACT["epoch_second"] + 60},
        "activity_or_stage": "light" if kind == "sleep" else "walking", "duration_nanoseconds": "60000000000", "classification": "unclassified" if kind == "sleep" else "completed_workout", "stages": [], "evidence_ids": []}
QUERIES = {}
for op in S.operations:
    name = op["properties"]["type"]["const"]
    operation = {"type": name}
    if name in ("sleep_session_listing", "workout_sleep_alignment"):
        operation.update(include_naps=True, window={"start_offset_seconds": 0, "duration_seconds": 60})
    if name == "workout_sleep_alignment": operation["workout_activity"] = "walking"
    if name == "period_comparison": operation.update(first={"start_date": "2000-01-01", "end_date": "2000-01-01"}, second={"start_date": "2000-01-02", "end_date": "2000-01-02"}, aggregations=[{"metric_id": "steps", "kind": "sum", "expected_unit": "steps"}])
    if name == "derive_packet": operation.update(kind="daily_wellness", detail_ids=[])
    ids = ["steps"]
    if name == "sleep_session_listing": ids = ["sleep_total"]
    if name == "workout_listing": ids = ["workouts"]
    if name == "workout_sleep_alignment": ids = ["sleep_total", "workouts"]
    request = doc("source_query_request", request_id=uid(40 + len(QUERIES)), peer=clone(PEER), source_id="health_connect", provider_id="health_connect", catalog_sha256=V.digest(CATALOG), authority_id=uid(7), authority_revision=1, dates=clone(DATES),
        calendar_timezone="Etc/UTC", selection=selection(ids), detail="native_evidence" if name == "source_record_listing" else "summary", include_evidence_values=name == "source_record_listing", operation=operation, page={"max_items": 1000, "max_bytes": 1048576}, budgets=clone(BUDGETS))
    QUERIES[name] = request
    case("query-request-" + name, "query", request, context={"catalog": CATALOG})
    mutation("query-unknown-member-" + name, "query", request, lambda x: x["operation"].update(arbitrary_sql="synthetic"), context={"catalog": CATALOG})
    response = doc("source_query_response", request_id=request["request_id"], operation=name, peer=clone(PEER), source_id="health_connect", provider_id="health_connect", query_sha256=V.query_scope_hash(request), dataset_sha256="e" * 64,
        catalog_sha256=V.digest(CATALOG), calendar_timezone="Etc/UTC", items=[], coverage=clone(COVERAGE), limitations=["factual_not_medical_advice"], limitation_count=1, limitations_truncated=False, source_descriptors=[], source_descriptor_count=0, source_descriptors_truncated=False, expires_at=EXPIRES)
    if name == "metric_catalog":
        response["items"] = [clone(CATALOG["metrics"][0])]; response["catalog"] = clone(CATALOG)
    if name == "metric_series": response["items"] = [fact()]
    if name == "workout_listing": response["items"] = [session("workout")]
    if name == "sleep_session_listing": response["items"] = [session("sleep")]
    if name == "period_comparison": response["items"] = [{"type": "comparison", "metric_id": "steps", "unit": "steps", "statistic": "sum", "first": fact(), "second": fact(n=2), "delta": {"type": "integer", "value": 1}}]
    if name == "workout_sleep_alignment":
        sleep = session("sleep"); sleep["start"]["epoch_second"] += 60; sleep["end"]["epoch_second"] += 60
        response["items"] = [{"type": "alignment", "workout": session("workout"), "sleep": sleep, "relation": "first_following_sleep_start", "gap_nanoseconds": "0", "status": "complete", "physiology": []}]
    if name == "source_record_listing": response["items"] = [{"type": "evidence", "evidence_id": "f" * 64, "identity": clone(IDENTITY), "start": clone(EXACT), "end": clone(EXACT), "metric_ids": ["steps"], "values": [fact()]}]
    if name == "derive_packet": response["packet"] = {"kind": "daily_wellness", "facts": [fact()], "medical_interpretation": False}
    ctx = {"catalog": CATALOG, "request": request}
    case("query-response-" + name, "query", response, context=ctx)
    mutation("query-response-wrong-peer-" + name, "query", response, lambda x: x["peer"].update(source_installation_id=uid(99)), "binding_changed", ctx)
    if name not in ("metric_catalog",):
        empty = clone(response); empty["items"] = []; empty["coverage"].update(status="complete_empty", days_with_values=0)
        if name == "derive_packet": empty["packet"]["facts"] = []
        case("query-complete-empty-" + name, "query", empty, context=ctx)
for mid in ["hrv", "wrist_temperature", "sleep_core", "android.medical_resources", "clinical_medication_records", "unknown"]:
    mutation("distinct-or-unavailable-" + mid, "query", QUERIES["metric_series"], lambda x, m=mid: x.update(selection=selection([m])), "unsupported_metric", {"catalog": CATALOG})
for mid in ["android.hrv_rmssd", "android.skin_temperature", "blood_oxygen"]:
    mutation("native-metric-" + mid, "query", QUERIES["metric_series"], lambda x, m=mid: x.update(selection=selection([m])), "valid", context={"catalog": CATALOG})
mutation("summary-no-native-evidence", "query", QUERIES["source_record_listing"], lambda x: x.update(detail="summary"), "approval_required", {"catalog": CATALOG})
mutation("comparison-no-disjoint-metric", "query", QUERIES["period_comparison"], lambda x: x["operation"]["aggregations"][0].update(metric_id="android.hrv_rmssd"), "unsupported_metric", {"catalog": CATALOG})
mutation("comparison-no-unit-substitution", "query", QUERIES["period_comparison"], lambda x: x["operation"]["aggregations"][0].update(expected_unit="ms"), "unsupported_metric", {"catalog": CATALOG})
mutation("comparison-no-date-expansion", "query", QUERIES["period_comparison"], lambda x: x["operation"]["first"].update(start_date="1999-12-31"), "invalid_request", {"catalog": CATALOG})
mutation("capture-time-budget", "query", QUERIES["metric_series"], lambda x: x["budgets"].update(max_capture_seconds=121), context={"catalog": CATALOG})
series_response = next(c["value"] for c in CASES if c["id"] == "query-response-metric_series")
series_ctx = {"request": QUERIES["metric_series"], "catalog": CATALOG}
mutation("missing-never-zero", "query", series_response, lambda x: x["items"][0].update(availability="missing"), context=series_ctx)
mutation("unverified-history-not-complete", "query", series_response, lambda x: x["coverage"]["history"].update(state="unverified"), context=series_ctx)
mutation("wrong-unit-not-charted", "query", series_response, lambda x: x["items"][0].update(unit="ms"), "unsupported_metric", series_ctx)
partial = clone(series_response); partial["coverage"].update(status="partial", missing_count=1, missing=[{"range": clone(DATES["range"]), "metric_id": "steps", "reason": "history_unverified"}]); partial["coverage"]["history"].update(state="unverified")
case("partial-history-facts-not-zero", "query", partial, context=series_ctx)

# Source-specific metadata/type/precision vectors; no HK last-modified or invented client version.
record_response = next(c["value"] for c in CASES if c["id"] == "query-response-source_record_listing")
record_ctx = {"request": QUERIES["source_record_listing"], "catalog": CATALOG}
for field in ("last_modified", "client_record_version", "client_record_id"):
    missing = clone(record_response); identity = missing["items"][0]["identity"]; identity.pop(field); identity["metadata_status"][field] = "not_captured"
    missing["coverage"]["status"] = "partial"; missing["limitations"].append("native_metadata_not_captured"); missing["limitation_count"] += 1
    case("hc-identity-missing-" + field + "-not-zero", "query", missing, context=record_ctx)
    mutation("hc-identity-available-" + field + "-needs-value", "query", record_response, lambda x, f=field: x["items"][0]["identity"].pop(f), context=record_ctx)
    mutation("hc-identity-uncaptured-" + field + "-cannot-have-value", "query", record_response, lambda x, f=field: x["items"][0]["identity"]["metadata_status"].update({f: "not_captured"}), context=record_ctx)
incomplete_metadata = clone(missing); incomplete_metadata["coverage"]["status"] = "complete"
case("hc-missing-metadata-cannot-promise-complete", "query", incomplete_metadata, "invalid_request", record_ctx)
missing = clone(record_response); missing["items"][0]["identity"].pop("client_record_id"); missing["items"][0]["identity"]["metadata_status"]["client_record_id"] = "absent"
case("hc-null-client-id-omitted-native-version-zero-retained", "query", missing, context=record_ctx)
LARGE_VERSION_RESPONSE = clone(record_response); LARGE_VERSION_RESPONSE["items"][0]["identity"]["client_record_version"] = 9223372036854775807
case("hc-client-version-exact-int64-not-js-rounded", "query", LARGE_VERSION_RESPONSE, context=record_ctx)
mutation("hc-client-version-int64-overflow-rejected", "query", record_response, lambda x: x["items"][0]["identity"].update(client_record_version=9223372036854775808), context=record_ctx)
mutation("hc-record-type-not-semantic-id", "query", record_response, lambda x: x["items"][0]["identity"].update(record_type="steps"), "unsupported_metric", record_ctx)
mutation("hc-native-metadata-not-unexposed-api", "query", record_response, lambda x: (x["items"][0]["identity"].pop("last_modified"), x["items"][0]["identity"]["metadata_status"].update(last_modified="not_exposed_by_source")), context=record_ctx)
mutation("catalog-native-type-not-semantic-id", "query", REVIEWED_CATALOG, lambda x: next(r for r in x["metrics"] if r["metric_id"] == "steps").update(native_record_type="steps"))
mutation("catalog-supported-row-needs-exact-native-type", "query", REVIEWED_CATALOG, lambda x: next(r for r in x["metrics"] if r["metric_id"] == "steps").pop("native_record_type"))
child_request = clone(QUERIES["source_record_listing"]); child_request["selection"] = selection(["heart_rate_avg"])
child_ctx = {"request": child_request, "catalog": CATALOG}
child_response = clone(record_response); child_response["query_sha256"] = V.query_scope_hash(child_request)
child_response["items"][0].update(metric_ids=["heart_rate_avg"], values=[fact(mid="heart_rate_avg", stat="average", unit="bpm")])
identity = child_response["items"][0]["identity"]
identity.update(identity_kind="derived_child", record_type=HC_PREFIX + "HeartRateRecord$Sample", record_id="synthetic-child-digest", parent_record_id="synthetic-parent-id", parent_record_type=NATIVE_TYPES["heart_rate"])
for field in ("last_modified", "client_record_version", "client_record_id"): identity.pop(field)
identity["metadata_status"] = {k: "not_exposed_by_source" for k in identity["metadata_status"]}
case("hc-derived-child-no-fabricated-system-metadata", "query", child_response, context=child_ctx)
mutation("hc-derived-child-needs-parent-id", "query", child_response, lambda x: x["items"][0]["identity"].pop("parent_record_id"), context=child_ctx)
mutation("hc-derived-child-not-parent-modified-time", "query", child_response, lambda x: (x["items"][0]["identity"].update(last_modified=clone(EXACT)), x["items"][0]["identity"]["metadata_status"].update(last_modified="available")), context=child_ctx)

APPLE_CATALOG = clone(CATALOG); APPLE_CATALOG.update(peer={**PEER, "platform": "apple"}, source_id="apple_health", provider_id="apple_health", sdk_version="iOS-SDK-26.5-header-review", metrics=[clone(next(r for r in CATALOG["metrics"] if r["metric_id"] == "steps"))])
APPLE_CATALOG["metrics"][0]["native_record_type"] = "HKQuantityTypeIdentifierStepCount"
APPLE_CATALOG["metrics"][0]["source_statistic"] = "HKStatistics.cumulativeSum"
APPLE_CATALOG["history"]["history"] = {"state": "not_applicable", "feature_status": "not_applicable"}
APPLE_REQUEST = clone(QUERIES["source_record_listing"]); APPLE_REQUEST.update(peer=clone(APPLE_CATALOG["peer"]), source_id="apple_health", provider_id="apple_health", catalog_sha256=V.digest(APPLE_CATALOG), selection=selection(["steps"], "apple_health"))
case("apple-source-identity-query-request", "query", APPLE_REQUEST, context={"catalog": APPLE_CATALOG})

def binary64_time(seconds):
    epoch, nanos = divmod(round(Fraction.from_float(seconds) * 1000000000), 1000000000)
    return {"epoch_second": epoch, "nanosecond": nanos, "source_offset_seconds": None, "precision": "source_binary64_seconds", "source_binary64_bits": struct.pack(">d", seconds).hex()}
APPLE_RESPONSE = clone(record_response); APPLE_RESPONSE.update(peer=clone(APPLE_REQUEST["peer"]), source_id="apple_health", provider_id="apple_health", query_sha256=V.query_scope_hash(APPLE_REQUEST), catalog_sha256=APPLE_REQUEST["catalog_sha256"])
APPLE_RESPONSE["coverage"]["history"] = clone(APPLE_CATALOG["history"]["history"])
APPLE_RESPONSE["limitations"].append("healthkit_read_permission_indistinguishable_empty"); APPLE_RESPONSE["limitation_count"] += 1
APPLE_IDENTITY = {"source_id": "apple_health", "provider_id": "apple_health", "record_type": "HKQuantityTypeIdentifierStepCount", "record_id": uid(120), "identity_kind": "native", "origin": "synthetic.apple.source", "metadata_status": {k: "not_exposed_by_source" for k in IDENTITY["metadata_status"]}}
APPLE_RESPONSE["items"][0].update(identity=clone(APPLE_IDENTITY), start=binary64_time(946684800.125), end=binary64_time(946684800.125))
apple_ctx = {"request": APPLE_REQUEST, "catalog": APPLE_CATALOG}
case("apple-native-identity-without-android-metadata", "query", APPLE_RESPONSE, context=apple_ctx)
for field, value in (("last_modified", clone(EXACT)), ("client_record_version", 0), ("client_record_id", "synthetic-id")):
    mutation("apple-must-not-invent-" + field, "query", APPLE_RESPONSE, lambda x, f=field, v=value: x["items"][0]["identity"].update({f: v}), context=apple_ctx)
mutation("apple-native-type-identifier-not-lowercased", "query", APPLE_RESPONSE, lambda x: x["items"][0]["identity"].update(record_type="hkquantitytypeidentifierstepcount"), "unsupported_metric", apple_ctx)
mutation("apple-source-version-not-client-version", "query", APPLE_RESPONSE, lambda x: x["items"][0]["identity"].update(source_revision_version="synthetic-version"), context=apple_ctx)
mutation("apple-date-not-fake-instant-nanosecond-precision", "query", APPLE_RESPONSE, lambda x: x["items"][0].update(start=clone(EXACT), end=clone(EXACT)), context=apple_ctx)
mutation("apple-date-binary64-round-trip-check", "query", APPLE_RESPONSE, lambda x: x["items"][0]["start"].update(nanosecond=1), context=apple_ctx)
mutation("apple-date-binary64-nonfinite-rejected", "query", APPLE_RESPONSE, lambda x: x["items"][0]["start"].update(source_binary64_bits="7ff0000000000000"), context=apple_ctx)
mutation("native-type-identifiers-bounded", "query", APPLE_RESPONSE, lambda x: x["items"][0]["identity"].update(record_type="H" * 257), context=apple_ctx)
mutation("native-type-identifiers-never-executable-url", "query", APPLE_RESPONSE, lambda x: x["items"][0]["identity"].update(record_type="https://synthetic.example/type"), context=apple_ctx)

CLAIMS = doc("source_query_cursor_claims", peer=clone(PEER), query_sha256=V.query_scope_hash(QUERIES["metric_series"]), dataset_sha256="e" * 64, catalog_sha256=V.digest(CATALOG), authority_revision=1, position=1, issued_at=ISSUED, expires_at=EXPIRES, nonce=uid(80))
KEY = bytes(range(32)) # Deliberately public test-only key, never usable as a runtime key.
TOKEN = V.cursor_issue(CLAIMS, KEY)
CURSOR_CONTEXT = {"synthetic_key_hex": KEY.hex(), "now": NOW, "expected": {k: clone(CLAIMS[k]) for k in ("peer", "query_sha256", "dataset_sha256", "catalog_sha256", "authority_revision")}}
case("authenticated-dataset-cursor", "cursor", TOKEN, context=CURSOR_CONTEXT)
case("cursor-tampered", "cursor", "A" + TOKEN[1:], "cursor_invalid", CURSOR_CONTEXT)
for key, val in [("peer", {**PEER, "host_installation_id": uid(99)}), ("dataset_sha256", "a" * 64), ("query_sha256", "b" * 64), ("catalog_sha256", "c" * 64), ("authority_revision", 2), ("snapshot_alive", False), ("cancelled", True), ("revoked", True)]:
    c = clone(CURSOR_CONTEXT); c["expected"][key] = val
    case("cursor-bound-" + key, "cursor", TOKEN, "snapshot_expired" if key == "snapshot_alive" else "cursor_invalid", c)
c = clone(CURSOR_CONTEXT); c["now"] = EXPIRES; case("cursor-expired-no-recapture", "cursor", TOKEN, "snapshot_expired", c)
case("cursor-noncanonical-padding", "cursor", TOKEN + "=", "cursor_invalid", CURSOR_CONTEXT)

PROJECTION_REQUEST = doc("source_projection_request", request_id=uid(90), peer=clone(PEER), source_id="health_connect", provider_id="health_connect", catalog_sha256=V.digest(CATALOG), projection_catalog_sha256=V.digest(S.PROJECTION_CATALOG), dates=clone(DATES),
    calendar_timezone="Etc/UTC", selection=selection(["steps"]), detail="summary", object_ids=["capture_manifest", "daily_summary"], field_ids=["steps"], allow_partial=False)
case("android-projection-summary-not-healthkit", "query", PROJECTION_REQUEST, context={"allowed_field_ids": ["steps"]})
mutation("projection-no-hidden-native-records", "query", PROJECTION_REQUEST, lambda x: x["object_ids"].append("native_records"), "approval_required", {"allowed_field_ids": ["steps"]})
mutation("projection-no-arbitrary-json-pointer", "query", PROJECTION_REQUEST, lambda x: x.update(field_ids=["private.identity"]), "unsupported_metric", {"allowed_field_ids": ["steps"]})
PROJECTION = doc("source_data_projection", request_id=uid(90), peer=clone(PEER), source_id="health_connect", provider_id="health_connect", scope_sha256=V.projection_scope_hash(PROJECTION_REQUEST), catalog_sha256=V.digest(CATALOG), projection_catalog_sha256=V.digest(S.PROJECTION_CATALOG),
    owner_date="2000-01-01", calendar_timezone="Etc/UTC", detail="summary", is_complete_daily_document=False, summary=[fact()], selected_series=[], native_records=[], coverage=clone(COVERAGE))
case("new-projection-independent-daily-profile", "query", PROJECTION)
mutation("projection-not-complete-daily-document", "query", PROJECTION, lambda x: x.update(is_complete_daily_document=True))

# Cross-schema durable artifact bytes: JSON one projection; NDJSON ordered projection lines, not daily/raw.
PROJECTION_MANIFESTS = {}
for media in ("application/json", "application/x-ndjson"):
    documents = [clone(PROJECTION)]
    if media == "application/x-ndjson":
        other = clone(PROJECTION); other["owner_date"] = "2000-01-02"; other["summary"][0]["owner_date"] = "2000-01-02"; documents.append(other)
    raw = b"".join(V.canonical(d) + b"\n" for d in documents)
    manifest = clone(MANIFEST); artifact = manifest["artifacts"][0]
    artifact.update(profile="android-source-projection-v1", media_type=media, write_mode="overwrite", relative_path="projection.json" if media == "application/json" else "projection.jsonl", byte_count=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    c = {"projection_request": PROJECTION_REQUEST, "catalog": CATALOG, "artifact_documents": {artifact["artifact_id"]: documents}}
    suffix = "json" if media == "application/json" else "ndjson"
    PROJECTION_MANIFESTS[suffix] = (manifest, c)
    case("durable-source-projection-profile-" + suffix, "agent", manifest, context=c)
    mutation("projection-artifact-not-frozen-daily-" + suffix, "agent", manifest, lambda x: x["artifacts"][0].update(profile="android-analytical-v5"), context=c)
    mutation("projection-artifact-bytes-pinned-" + suffix, "agent", manifest, lambda x: x["artifacts"][0].update(sha256="0" * 64), "binding_changed", c)
    mutation("projection-artifact-count-pinned-" + suffix, "agent", manifest, lambda x: x["artifacts"][0].update(byte_count=1), "binding_changed", c)
    mutation("projection-artifact-no-csv-" + suffix, "agent", manifest, lambda x: x["artifacts"][0].update(media_type="text/csv"), context=c)
    mutation("projection-artifact-no-markdown-merge-" + suffix, "agent", manifest, lambda x: x["artifacts"][0].update(write_mode="merge_markdown"), context=c)
    for field, changed, expected in (("schema", "healthmd.health_data", "invalid_request"), ("schema_version", 5, "invalid_request"),
        ("is_complete_daily_document", True, "invalid_request"), ("scope_sha256", "f" * 64, "binding_changed"), ("source_id", "provider_native", "binding_changed"),
        ("owner_date", "1999-12-31", "binding_changed")):
        bad = clone(c); bad["artifact_documents"][artifact["artifact_id"]][0][field] = changed
        case("projection-artifact-cross-schema-" + field + "-" + suffix, "agent", manifest, expected, bad)
    bad = clone(c); bad["artifact_documents"][artifact["artifact_id"]][0]["detail"] = "native_records"
    case("projection-artifact-detail-not-expanded-" + suffix, "agent", manifest, "binding_changed", bad)
manifest, c = PROJECTION_MANIFESTS["ndjson"]
mutation("projection-json-never-multiple-documents", "agent", manifest, lambda x: x["artifacts"][0].update(media_type="application/json"), context=c)
bad = clone(c); bad["artifact_documents"][uid(20)].reverse()
case("projection-ndjson-owner-order-pinned", "agent", manifest, "invalid_request", bad)
for detail in ("selected_time_series", "native_records"):
    request = clone(PROJECTION_REQUEST); request.update(detail=detail, object_ids=sorted(["capture_manifest", "daily_summary", "selected_series"] + (["native_records"] if detail == "native_records" else [])), field_ids=sorted(["steps", "steps.count"] + (["steps.record"] if detail == "native_records" else [])))
    observation = {"type": "source_observation", "field_id": "steps.count", "selection_metric_id": "steps", "owner_date": "2000-01-01", "identity": clone(IDENTITY),
        "start": clone(EXACT), "end": {**EXACT, "epoch_second": EXACT["epoch_second"] + 60}, "native_value_key": "count", "observation_kind": "interval_total", "unit": "steps", "value": {"type": "integer", "value": 1}}
    observation["observation_id"] = V.digest(observation)
    document = clone(PROJECTION); document.update(detail=detail, scope_sha256=V.projection_scope_hash(request), selected_series=[observation])
    if detail == "native_records": document["native_records"] = [{"type": "evidence", "evidence_id": "f" * 64, "identity": clone(IDENTITY), "start": clone(EXACT), "end": clone(EXACT), "metric_ids": ["steps"], "values": [fact()]}]
    raw = V.canonical(document) + b"\n"; manifest = clone(PROJECTION_MANIFESTS["json"][0]); manifest["artifacts"][0].update(byte_count=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    c = {"projection_request": request, "catalog": CATALOG, "artifact_documents": {uid(20): [document]}}
    case("projection-artifact-detail-" + detail, "agent", manifest, context=c)
    bad = clone(c); bad["artifact_documents"][uid(20)][0]["summary"][0]["unit"] = "ms"
    case("projection-artifact-unit-not-substituted-" + detail, "agent", manifest, "unsupported_metric", bad)
    bad = clone(c); bad["artifact_documents"][uid(20)][0]["coverage"]["history"]["state"] = "unverified"
    case("projection-artifact-history-not-complete-" + detail, "agent", manifest, "invalid_request", bad)

# Projection is its own accepted/journaled v4 product, never a transient selector RPC or v2 daily job.
case("reviewed-projection-field-catalog-planned", "query", S.PROJECTION_CATALOG)
PROJECTED_CATALOG = clone(CATALOG); PROJECTED_CATALOG["history"].update(days_considered=0, days_with_values=0, missing_count=0, missing=[])
PROJECTED_REQUEST = clone(request); PROJECTED_REQUEST["catalog_sha256"] = V.digest(PROJECTED_CATALOG); PROJECTED_REQUEST["dates"] = {"type": "exact", "range": {"start_date": "2000-01-01", "end_date": "2000-01-01"}}
PROJECTED_DOCUMENT = clone(document); PROJECTED_DOCUMENT["catalog_sha256"] = V.digest(PROJECTED_CATALOG); PROJECTED_DOCUMENT["scope_sha256"] = V.projection_scope_hash(PROJECTED_REQUEST); PROJECTED_DOCUMENT["coverage"]["days_considered"] = 1
PROJECTION_OUTPUT = {"profile": "android-source-projection-v1", "layout": "per_day", "media_type": "application/x-ndjson", "write_mode": "append", "subfolder": "", "folder_template": "{year}", "filename_template": "{date}"}
PROJECTED_INTENT = clone(INTENT); PROJECTED_INTENT.pop("settings_policy"); PROJECTED_INTENT.update(intent_id=uid(120), dates=clone(PROJECTED_REQUEST["dates"]),
    product={"type": "source_projection", "product_id": "android_source_projection_v1", "request": clone(PROJECTED_REQUEST), "output": clone(PROJECTION_OUTPUT)})
PROJECTED_INTENT["capture_scope"].update(selection=clone(PROJECTED_REQUEST["selection"]), compatibility_detail="selected_time_series")
PROJECTED_CAPS = clone(BASE_DISCOVERY); PROJECTED_CAPS.update(features=sorted(BASE_DISCOVERY["features"] + ["source_projection"]), projection_products=["android_source_projection_v1"], projection_catalog_sha256=V.digest(S.PROJECTION_CATALOG), projection_source_catalog=clone(PROJECTED_CATALOG))
PROJECTED_CAPS["capability_sha256"] = V.capability_digest(PROJECTED_CAPS)
PROJECTED_PLAN = make_plan(PROJECTED_INTENT, capabilities=PROJECTED_CAPS); PROJECTED_PLAN["plan_id"] = uid(121); rehash_plan(PROJECTED_PLAN)
PROJECTED_APPROVAL = clone(APPROVAL); PROJECTED_APPROVAL.update(approval_id=uid(122), binding=V.binding(PROJECTED_PLAN))
PROJECTED_EXECUTE = clone(EXECUTE); PROJECTED_EXECUTE.update(request_id=uid(123), job_id=uid(124), idempotency_key=uid(125), plan=clone(PROJECTED_PLAN), approval=clone(PROJECTED_APPROVAL))
PROJECTED_CONTEXT = clone(CONTEXT); PROJECTED_CONTEXT.update(catalog=clone(PROJECTED_CATALOG), capabilities=clone(PROJECTED_CAPS), capability_sha256=PROJECTED_PLAN["capability_sha256"],
    plan=clone(PROJECTED_PLAN), authority=V.derived_export_authority(NATIVE_DELEGATION, PROJECTED_PLAN, AUTH), host_authority=V.derived_export_authority(HOST_DELEGATION, PROJECTED_PLAN, AUTH),
    issued_plans={uid(121): PROJECTED_PLAN["plan_sha256"]}, issued_approval_ids=[uid(122)], issued_approvals={uid(122): V.digest(PROJECTED_APPROVAL)}, approved_export_binding_sha256=V.digest(V.binding(PROJECTED_PLAN)))
PROJECTED_PLAN_REQUEST = clone(PLAN_REQUEST); PROJECTED_PLAN_REQUEST.update(intent=clone(PROJECTED_INTENT), capability_sha256=PROJECTED_PLAN["capability_sha256"])
case("projection-product-discovery", "agent", PROJECTED_CAPS)
mutation("projection-discovery-no-missing-source-catalog", "agent", PROJECTED_CAPS, lambda x: (x.pop("projection_source_catalog"), x.update(capability_sha256=V.capability_digest(x))))
mutation("projection-discovery-no-health-value-counts", "agent", PROJECTED_CAPS, lambda x: (x["projection_source_catalog"]["history"].update(days_with_values=1), x.update(capability_sha256=V.capability_digest(x))))
case("projection-product-explicit-intent", "agent", PROJECTED_INTENT)
case("projection-product-zero-health-first-plan", "agent", PROJECTED_PLAN_REQUEST, context=PROJECTED_CONTEXT)
case("projection-product-frozen-selector-plan", "agent", PROJECTED_PLAN)
projected_all = clone(PROJECTED_INTENT); projected_all["dates"] = {"type": "all_available"}; projected_all["product"]["request"]["dates"] = {"type": "all_available"}
case("projection-all-available-no-earliest-date-or-path-read", "agent", make_plan(projected_all, capabilities=PROJECTED_CAPS))
case("projection-product-separate-approval-relay", "agent", doc("agent_approval_request", request_id=uid(126), plan_id=uid(121), binding=V.binding(PROJECTED_PLAN)), context=PROJECTED_CONTEXT)
case("projection-product-approved-execute", "agent", PROJECTED_EXECUTE, context=PROJECTED_CONTEXT)
for key, value in (("product_id", "android_daily_records_v1"), ("product_id", "generated_files_v1")):
    mutation("projection-never-reserved-v2-" + value, "agent", PROJECTED_INTENT, lambda x, k=key, v=value: x["product"].update({k: v}))
mutation("projection-not-daily-settings-policy", "agent", PROJECTED_INTENT, lambda x: x.update(settings_policy=clone(INTENT["settings_policy"])))
mutation("projection-output-json-not-append", "agent", PROJECTED_INTENT, lambda x: x["product"]["output"].update(media_type="application/json"))
for key, value, error in (("detail", "selected_time_series", "approval_required"), ("field_ids", ["steps", "steps.count"], "unsupported_metric"), ("object_ids", ["daily_summary", "native_records", "selected_series"], "binding_changed")):
    mutation("projection-execute-selector-not-reinterpreted-" + key, "agent", PROJECTED_EXECUTE, lambda x, k=key, v=value: x["plan"]["intent"]["product"]["request"].update({k: v}), error, PROJECTED_CONTEXT)
for slot in ("native", "host"):
    bad = clone(PROJECTED_CONTEXT); next(iter(bad["stored_" + slot + "_delegations"].values()))["bounds"]["products"] = ["generated_files"]
    case("projection-no-implicit-" + slot + "-product-grant", "agent", PROJECTED_PLAN_REQUEST, "approval_required", bad)
    bad = clone(PROJECTED_CONTEXT); next(iter(bad["stored_" + slot + "_delegations"].values()))["bounds"]["projection_field_ids"].remove("steps.count")
    case("projection-no-implicit-" + slot + "-field-grant", "agent", PROJECTED_PLAN_REQUEST, "approval_required", bad)
PROJECTED_JOB = doc("agent_projection_job", job_id=uid(124), execute=clone(PROJECTED_EXECUTE), request_sha256=V.digest(PROJECTED_EXECUTE), accepted_at=NOW, expires_at="2000-01-10T00:01:00Z",
    resolved_dates=clone(PROJECTED_PLAN["resolved_dates"]), source_catalog=clone(PROJECTED_CATALOG), projection_catalog=clone(S.PROJECTION_CATALOG), state="accepted", capture_started=False)
case("projection-journal-before-first-health-read", "agent", PROJECTED_JOB)
mutation("projection-journal-never-new-fingerprint", "agent", PROJECTED_JOB, lambda x: x.update(request_sha256="0" * 64), "binding_changed")
mutation("projection-acceptance-before-capture", "agent", PROJECTED_JOB, lambda x: x.update(capture_started=True))
raw = V.canonical(PROJECTED_DOCUMENT) + b"\n"
PROJECTED_MANIFEST = clone(MANIFEST); PROJECTED_MANIFEST.update(job_id=uid(124), request_sha256=V.digest(PROJECTED_EXECUTE), binding=V.binding(PROJECTED_PLAN),
    branch_statuses=[{"selector_id": key, "status": "success", "record_count": 1} for key in sorted(["object." + x for x in PROJECTED_REQUEST["object_ids"]] + ["field." + x for x in PROJECTED_REQUEST["field_ids"]])])
PROJECTED_MANIFEST["artifacts"][0].update(profile="android-source-projection-v1", media_type="application/x-ndjson", write_mode="append", relative_path=PROJECTED_PLAN["predicted_paths"][0], byte_count=len(raw), sha256=hashlib.sha256(raw).hexdigest())
PROJECTED_SPOOL = clone(PROJECTED_JOB); PROJECTED_SPOOL.update(state="spooled", capture_started=True, manifest_sha256=V.digest(PROJECTED_MANIFEST), spool_sha256=V.digest([{k: a[k] for k in ("artifact_id", "sha256", "byte_count")} for a in PROJECTED_MANIFEST["artifacts"]]))
PROJECTED_RESUME = clone(RESUME); PROJECTED_RESUME.update(job_id=uid(124), request_sha256=V.digest(PROJECTED_EXECUTE), manifest_sha256=V.digest(PROJECTED_MANIFEST), binding=V.binding(PROJECTED_PLAN))
PROJECTED_ARTIFACT_CONTEXT = {"projection_job": clone(PROJECTED_SPOOL), "projection_request": clone(PROJECTED_REQUEST), "catalog": clone(PROJECTED_CATALOG), "journal_projection_catalog": clone(S.PROJECTION_CATALOG),
    "artifact_documents": {uid(20): [PROJECTED_DOCUMENT]}, "journal_resume": clone(PROJECTED_RESUME), "spool_present": True}
case("projection-journal-capture-spooled-once", "agent", PROJECTED_SPOOL)
case("projection-manifest-under-execute-fingerprint", "agent", PROJECTED_MANIFEST, context=PROJECTED_ARTIFACT_CONTEXT)
case("projection-resume-same-journal-not-query-cache", "resume", PROJECTED_RESUME, context={"journal_resume": PROJECTED_RESUME})
BASE_SESSION = {"session_id": uid(127), "job_id": uid(124), "request_fingerprint": V.digest(PROJECTED_EXECUTE), "peer_binding": {k: PEER[k] for k in ("source_installation_id", "host_installation_id")}, "partition_target_bytes": 1048576, "created_at": NOW}
BASE_PROJECTED_ARTIFACT = {"job_id": uid(124), "artifact_id": uid(20), "kind": "generated_file", "schema": {"id": "healthmd.source_data_projection", "major": 1},
    **{k: PROJECTED_MANIFEST["artifacts"][0][k] for k in ("media_type", "byte_count", "sha256", "relative_path", "write_mode")}, "provider_id": "health_connect"}
PROJECTED_TRANSFER = {"manifest": clone(PROJECTED_MANIFEST), "transfer_session": BASE_SESSION, "base_artifact_manifest": BASE_PROJECTED_ARTIFACT, "resume": clone(PROJECTED_RESUME)}
case("projection-v2-generic-carriage-v4-authority", "projection_transfer", PROJECTED_TRANSFER, context=PROJECTED_ARTIFACT_CONTEXT)
late = clone(PROJECTED_ARTIFACT_CONTEXT); late.update(now="2000-01-04T00:00:00Z", current_settings_sha256="f" * 64, current_capability_sha256="f" * 64, query_snapshot_alive=False)
case("projection-resume-no-replan-recapture-or-preference-lookup", "projection_transfer", PROJECTED_TRANSFER, context=late)
expired = clone(late); expired["now"] = PROJECTED_JOB["expires_at"]
case("projection-resume-job-expired-no-renewal", "projection_transfer", PROJECTED_TRANSFER, "job_expired", expired)
revoked = clone(late); revoked["native_grants_revoked"] = True
case("projection-resume-native-revocation-stops-without-migration", "projection_transfer", PROJECTED_TRANSFER, "permission_required", revoked)
for name, mutate in [("daily-kind", lambda x: x["base_artifact_manifest"].update(kind="daily_records")), ("raw-kind", lambda x: x["base_artifact_manifest"].update(kind="raw_snapshot")),
    ("daily-schema", lambda x: x["base_artifact_manifest"].update(schema={"id": "healthmd.health_data", "major": 5})), ("fingerprint", lambda x: x["transfer_session"].update(request_fingerprint="f" * 64)),
    ("profile", lambda x: x["manifest"]["artifacts"][0].update(profile="android-analytical-v5")), ("resume", lambda x: x["resume"].update(request_sha256="f" * 64))]:
    mutation("projection-transfer-rejects-" + name, "projection_transfer", PROJECTED_TRANSFER, mutate, "binding_changed", PROJECTED_ARTIFACT_CONTEXT)
bad = clone(PROJECTED_ARTIFACT_CONTEXT); bad["spool_present"] = False
case("projection-resume-missing-spool-never-recaptures", "projection_transfer", PROJECTED_TRANSFER, "spool_missing_restart_required", bad)
for key in ("start", "identity"):
    mutation("projection-series-never-drops-" + key, "query", PROJECTED_DOCUMENT, lambda x, k=key: x["selected_series"][0].pop(k))
mutation("projection-series-not-daily-aggregate", "query", PROJECTED_DOCUMENT, lambda x: x.update(selected_series=[fact()]))
point_request = clone(PROJECTED_REQUEST); point_request.update(detail="selected_time_series", selection=selection(["heart_rate_avg"]), object_ids=["capture_manifest", "selected_series"], field_ids=["heart_rate.samples.bpm"])
point = clone(PROJECTED_DOCUMENT["selected_series"][0]); point.pop("end"); point.update(field_id="heart_rate.samples.bpm", selection_metric_id="heart_rate_avg", native_value_key="beatsPerMinute", observation_kind="point", unit="bpm", identity=clone(child_response["items"][0]["identity"]))
point["observation_id"] = V.digest({k: v for k, v in point.items() if k != "observation_id"})
point_document = clone(PROJECTED_DOCUMENT); point_document.update(detail="selected_time_series", scope_sha256=V.projection_scope_hash(point_request), summary=[], native_records=[], selected_series=[point])
case("projection-intraday-child-point-not-average", "query", point_document, context={"projection_request": point_request, "catalog": PROJECTED_CATALOG})
PROJECTED_COMMIT = clone(COMMIT); PROJECTED_COMMIT.update(job_id=uid(124), request_sha256=V.digest(PROJECTED_EXECUTE), manifest_sha256=V.digest(PROJECTED_MANIFEST), relative_path=PROJECTED_PLAN["predicted_paths"][0], input_sha256=hashlib.sha256(raw).hexdigest())
PROJECTED_COMMIT["commit_key"] = V.digest({k: PROJECTED_COMMIT[k] for k in ("job_id", "artifact_id", "destination", "request_sha256", "manifest_sha256", "relative_path", "write_mode", "input_sha256", "before_sha256", "after_sha256")})
case("projection-ndjson-commit-journal-exact-input", "agent", PROJECTED_COMMIT)
mutation("projection-ndjson-resume-no-second-append", "agent", PROJECTED_COMMIT, lambda x: x.update(status="already_committed"), "valid", {"persisted_commit": PROJECTED_COMMIT})

DICTIONARY = doc("profile_dictionary", profile="android-analytical-v5", source_schema="healthmd.health_data", source_schema_version=5, platform="android",
    registry_sha256=hashlib.sha256((ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json").read_bytes()).hexdigest(), dictionary_rules_version=1,
    entries=[{"field_id": "heart.hrv_samples", "semantic_id": "android.hrv_rmssd", "native_selection_id": "hrv", "native_type": NATIVE_TYPES["heart_rate_variability_rmssd"], "unit": "ms", "statistic": "latest", "registry_equivalence": "platform_distinct", "mapping_state": "planned", "alias_notes": ["not_sdnn"]}], contains_health_values=False)
case("android-profile-specific-dictionary", "agent", DICTIONARY)
mutation("dictionary-not-apple-profile", "agent", DICTIONARY, lambda x: x.update(source_schema_version=8))
mutation("dictionary-no-health-values", "agent", DICTIONARY, lambda x: x.update(contains_health_values=True))
mutation("dictionary-rmssd-not-sdnn", "agent", DICTIONARY, lambda x: x["entries"][0].update(semantic_id="hrv"), "unsupported_metric")

DISCOVERY = doc("agent_discovery", request_id=uid(100), peer=clone(PEER), capability_revision=1, capability_sha256="2" * 64, issued_at=ISSUED, expires_at=EXPIRES,
    source_calendar_timezone="Etc/UTC", features=["bound_execution", "explicit_settings", "source_query", "zero_health_plan"], settings_policies=["explicit", "profile", "saved_device_settings"],
    output_profiles=["android-analytical-v5", "android-frozen-v4"], projection_products=[], projection_catalog_sha256="0" * 64, query_catalog_sha256=V.digest(CATALOG), query_operations=sorted(S.item_types), budgets=clone(BUDGETS), output_support=clone(OUTPUT_SUPPORT), control_operations=[], authority_references=[clone(AUTHORITY_REFS["native"])], lifecycle="android_user_started_service_after_first_unlock", configuration_protection="locked", native_grants="unverified", entitlement="required", required_actions=["grant_health_access"])
DISCOVERY["capability_sha256"] = V.capability_digest(DISCOVERY)
case("read-only-runtime-discovery", "agent", DISCOVERY)
case("export-discovery-before-plan", "agent", BASE_DISCOVERY)
mutation("discovery-content-change-requires-new-hash", "agent", BASE_DISCOVERY, lambda x: x["output_support"].update(formats=["csv"]), "binding_changed")
WIRE_CASES = []
for kind, target in S.wire_types.items():
    value = {"discovery_request": doc("agent_discovery_request", request_id=uid(100), peer=clone(PEER)), "discovery": DISCOVERY,
        "plan_request": PLAN_REQUEST, "plan": PLAN, "approval_request": APPROVAL_REQUEST, "approval": APPROVAL,
        "execute": EXECUTE, "cancel": doc("agent_cancel_request", job_id=uid(10), peer=clone(PEER), request_sha256=V.digest(EXECUTE), authority_id=uid(7), approval_id=uid(8)), "receipt": RECEIPT, "resume": RESUME, "manifest": MANIFEST, "commit": COMMIT, "control": CONTROL_REQUEST,
        "control_plan_request": CONTROL_PLAN_REQUEST, "control_plan": CONTROL_PLAN, "control_approval_request": CONTROL_APPROVAL_REQUEST, "control_approval": CONTROL_APPROVAL,
        "control_receipt": CONTROL_RECEIPT,
        "query_request": QUERIES["metric_series"], "query_response": series_response, "query_cancel": doc("source_query_cancel", request_id=uid(40), peer=clone(PEER), query_sha256="a" * 64, dataset_sha256="e" * 64),
        "query_cancelled": doc("source_query_cancelled", request_id=uid(40), peer=clone(PEER), query_sha256="a" * 64, dataset_sha256="e" * 64, source_acknowledged=True),
        "projection_request": PROJECTION_REQUEST, "projection": PROJECTION, "error": doc("agent_error", request_id=uid(102), code="unsupported_capability", retryable=False)}[target]
    envelope = {"protocol_version": 4, "type": kind, "payload": clone(value)}
    context = {**CONTEXT, "host_versions": [1, 2, 3, 4], "source_versions": [2, 4]}
    if kind.startswith("query"):
        authority = clone(AUTH); authority["scope_sha256"] = V.query_scope_hash(QUERIES["metric_series"])
        context.update(catalog=CATALOG, request=QUERIES["metric_series"], authority=authority)
    if kind == "projection_request": context["allowed_field_ids"] = ["steps"]
    if kind.startswith("control"):
        context.update(clone(CONTROL_CONTEXT), control_request=clone(CONTROL_REQUEST))
    case("v4-envelope-" + kind, "wire", envelope, context=context)
    old = clone(context); old["source_versions"] = [2]
    case("old-peer-never-new-case-" + kind, "wire", envelope, "unsupported_capability", old)
    WIRE_CASES.append(envelope)
for kind, payload in (("projection_request", PROJECTED_REQUEST), ("projection_response", PROJECTED_DOCUMENT)):
    case("projection-selector-no-standalone-wire-" + kind, "wire", {"protocol_version": 4, "type": kind, "payload": payload}, "invalid_request", {"host_versions": [1, 2, 3, 4], "source_versions": [2, 4]})
case("projection-execute-v4-wire-job-not-transient", "wire", {"protocol_version": 4, "type": "execute_request", "payload": PROJECTED_EXECUTE}, context={**PROJECTED_CONTEXT, "host_versions": [1, 2, 3, 4], "source_versions": [2, 4]})
for domain in ("local_recipe", "host_schedule"):
    journey = CONTROL_JOURNEYS[domain]
    context = {**clone(journey[5]), "host_versions": [1, 2, 3, 4], "source_versions": [2, 4]}
    envelope = {"protocol_version": 4, "type": "control_plan_request", "payload": clone(journey[0])}
    case("v4-no-mobile-rpc-for-host-store-" + domain, "wire", envelope, "unsupported_capability", context)

if __name__ == "__main__":
    vectors = []
    for value in [PLAN, EXECUTE, COMMIT, PLAN_REQUEST, APPROVAL_REQUEST, NATIVE_DELEGATION, HOST_DELEGATION,
            NEW_PLAN, NEW_EXECUTE, CONTROL_PLAN_REQUEST, CONTROL_PLAN, CONTROL_APPROVAL_REQUEST, CONTROL_APPROVAL, CONTROL_REQUEST, CONTROL_RECEIPT,
            PROJECTION, *(v[0] for v in PROJECTION_MANIFESTS.values()), QUERIES["metric_series"], APPLE_REQUEST, APPLE_RESPONSE, LARGE_VERSION_RESPONSE, S.PROJECTION_CATALOG, PROJECTED_PLAN_REQUEST, PROJECTED_PLAN, PROJECTED_APPROVAL, PROJECTED_EXECUTE, PROJECTED_JOB, PROJECTED_SPOOL, PROJECTED_MANIFEST, PROJECTED_DOCUMENT, PROJECTED_RESUME, PROJECTED_COMMIT, PROJECTED_TRANSFER, CLAIMS, *WIRE_CASES]:
        raw = V.canonical(value)
        vectors.append({"value": value, "canonical_base64": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest()})
    payload = doc("agent_bridge_test_vectors", provenance="Python-generated synthetic specification candidates; Rust/Swift/Kotlin generation and independent verification NOT RUN", cases=CASES, canonical_vectors=vectors)
    S.emit(HERE / "fixtures/conformance.json", payload)
    S.emit(HERE / "reviewed-query-catalog.json", REVIEWED_CATALOG)
    print("Generated", len(CASES), "synthetic cases and", len(vectors), "canonical vectors")
