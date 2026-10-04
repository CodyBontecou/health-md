#!/usr/bin/env python3
"""Generate new synthetic specification candidates, never native conformance claims."""
import base64
import copy
import hashlib
import json
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
    capture_scope={"selection": selection(["steps"]), "compatibility_detail": "summary", "native_archive": {"type": "none"}}, settings_policy={"type": "explicit", "settings": clone(SETTINGS)})

OUTPUT_SUPPORT = {"formats": ["csv", "json", "markdown", "obsidian_bases"], "write_modes": ["append", "merge_markdown", "merge_markdown_preserving_preamble", "overwrite"],
    "compatibility_detail": ["selected_time_series", "summary"], "native_archive_products": ["android_provider_native_snapshot_v1", "none"],
    "setting_pointers": sorted(V.leaves(SETTINGS)), "path_tokens": ["category", "date", "day", "metric", "month", "record_id", "year"], "max_artifacts": 4096, "max_path_bytes": 4096}
BASE_DISCOVERY = doc("agent_discovery", request_id=uid(100), peer=clone(PEER), capability_revision=1, issued_at=ISSUED, expires_at=EXPIRES,
    source_calendar_timezone="Etc/UTC", features=["bound_execution", "explicit_settings", "profile_dictionary", "zero_health_plan", "zip"], settings_policies=["explicit", "profile", "saved_device_settings"],
    output_profiles=["android-analytical-v5", "android-frozen-v4"], query_catalog_sha256="0" * 64, query_operations=[], budgets=clone(BUDGETS), output_support=clone(OUTPUT_SUPPORT), control_operations=[],
    lifecycle="android_user_started_service_after_first_unlock", configuration_protection="locked", native_grants="satisfied", entitlement="satisfied", required_actions=[])
BASE_DISCOVERY["capability_sha256"] = V.capability_digest(BASE_DISCOVERY)

def make_plan(intent=INTENT, effective=SETTINGS):
    policy = intent["settings_policy"]
    origin = "request" if policy["type"] == "explicit" else policy["type"]
    revision = policy.get("expected_revision", 0)
    origins = [{"pointer": p, "origin": origin, "revision": revision} for p in V.leaves(effective, "/effective_settings")]
    origins += [{"pointer": p, "origin": "request", "revision": 0} for p in V.leaves(intent["capture_scope"], "/capture_scope")]
    origins += [{"pointer": "/resolved_dates", "origin": "resolved_calendar", "revision": 0}, {"pointer": "/calendar_timezone", "origin": "request", "revision": 0}]
    resolved = V.dates(intent["dates"], intent["calendar_timezone"])
    metrics = V.resolve_selection(intent["capture_scope"]["selection"], intent["peer"]["platform"], V.registry(ROOT))
    revisions = []
    if revision:
        revisions = [{"domain": "native_profile" if policy["type"] == "profile" else "device_settings", "object_id": policy.get("profile_id", uid(5)), "revision": revision, "sha256": V.digest(effective)}]
    plan = doc("agent_export_plan", plan_id=uid(6), intent=clone(intent), resolved_dates=resolved, resolved_metric_ids=metrics, effective_settings=clone(effective), origins=sorted(origins, key=lambda x: x["pointer"]),
        revisions=revisions, settings_sha256=V.digest(effective), scope_sha256=V.digest({"dates": resolved, "calendar_timezone": intent["calendar_timezone"], "capture_scope": intent["capture_scope"], "metric_ids": metrics}),
        capability_sha256=BASE_DISCOVERY["capability_sha256"], issued_at=ISSUED, expires_at=EXPIRES, predicted_paths=V.predicted_paths(intent, effective),
        path_prediction="template_only_all_available" if resolved["type"] == "all_available" else "deferred_native_entries" if effective["individual_entries"]["enabled"] else "exact_requested_days", required_actions=[],
        limitations=["history_bounds_unresolved"] if resolved["type"] == "all_available" else ["entry_paths_unresolved"] if effective["individual_entries"]["enabled"] else [], side_effects={"health_reads": 0, "output_writes": 0, "quota_consumed": 0, "settings_mutations": 0, "wake_enrollments": 0})
    plan["plan_sha256"] = V.digest(plan)
    return plan

PLAN = make_plan()
AUTH = doc("agent_authority", authority_id=uid(7), peer=clone(PEER), rights=sorted(S.rights), scope_sha256=PLAN["scope_sha256"], destination_binding_ids=[uid(3)], expires_at=EXPIRES,
    configuration_protection="unlocked_native", native_consent="satisfied", entitlement="satisfied", grant_revision=1)
APPROVAL = doc("agent_approval", approval_id=uid(8), authority_id=uid(7), binding=V.binding(PLAN), rights=["export_execute"], approved_at="2000-01-03T00:00:30Z")
EXECUTE = doc("agent_execute_request", request_id=uid(9), job_id=uid(10), idempotency_key=uid(11), plan=clone(PLAN), approval=clone(APPROVAL))
CONTEXT = {"now": NOW, "peer": clone(PEER), "destination": clone(DEST), "capability_sha256": PLAN["capability_sha256"], "capabilities": clone(BASE_DISCOVERY), "revisions": [], "authority": clone(AUTH), "issued_approval_ids": [uid(8)], "issued_approvals": {uid(8): V.digest(APPROVAL)}, "issued_plans": {uid(6): PLAN["plan_sha256"]}}

CASES = []
def case(name, family, value, expected="valid", context=None):
    row = {"id": name, "family": family, "value": clone(value), "expected": expected}
    if context is not None:
        row["context"] = clone(context)
        if family == "control": row["context"]["approved_operation_sha256"] = V.digest(value)
        request = value if isinstance(value, dict) and value.get("schema") == "healthmd.source_query_request" else context.get("request")
        if request and "catalog" in context and "authority" not in context:
            authority = clone(AUTH); authority["scope_sha256"] = V.query_scope_hash(request)
            row["context"].update(authority=authority, now=NOW)
    CASES.append(row); return row

def mutation(name, family, base, change, expected="invalid_request", context=None):
    value = clone(base); change(value); return case(name, family, value, expected, context)

def rehash_plan(p):
    p["settings_sha256"] = V.digest(p["effective_settings"])
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
mutation("issued-approval-cannot-be-reinterpreted", "agent", EXECUTE, lambda x: x["approval"]["rights"].append("native_configuration_mutate"), "approval_required", CONTEXT)
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

# Future typed control grammar: all verbs have positive shape/authority/CAS cases.
SCHEDULE = {"recipe_or_profile_id": uid(12), "recipe_or_profile_revision": 2, "calendar_timezone": "Etc/UTC", "cadence": {"value": 1, "unit": "days", "anchor_date": "2000-01-01"},
    "local_time": {"hour": 8, "minute": 0}, "iso_weekday": 1, "lookback_days": 1, "dst_gap": "skip", "dst_fold": "first_occurrence", "catch_up": "one_latest_complete_window", "enabled": False, "destination": clone(DEST)}
NATIVE_DEST = {"type": "requires_native_rebind", "kind": "device_folder"}
for branch in S.control_branches:
    props = branch["properties"]; domain = props["domain"]["const"]; verb = props["verb"]["const"]
    op = {"domain": domain, "verb": verb, "request_id": uid(30), "authority_id": uid(7), "peer": clone(PEER)}
    for key in ("object_id", "idempotency_key", "approval_id"):
        if key in props: op[key] = uid(12 if key == "object_id" else 8 if key == "approval_id" else 31)
    if "expected_revision" in props: op["expected_revision"] = 2
    if "pending_binding_sha256" in props: op["pending_binding_sha256"] = "a" * 64
    if "value" in props:
        op["value"] = {"name": "Synthetic recipe", "intent": clone(INTENT)} if domain == "local_recipe" else {"name": "Synthetic profile", "capture_scope": clone(INTENT["capture_scope"]), "settings": clone(SETTINGS), "destination": clone(NATIVE_DEST)} if domain == "native_profile" else clone(NATIVE_DEST) if domain == "native_destination" else clone(SCHEDULE)
        if domain == "native_schedule": op["value"]["destination"] = clone(NATIVE_DEST)
    read = verb in ("list", "get", "inspect", "plan", "inspect_pending")
    right = "recipe_read" if domain == "local_recipe" and read else "recipe_run" if domain == "local_recipe" and verb == "run" else "recipe_mutate" if domain == "local_recipe" else "host_schedule_read" if domain == "host_schedule" and read else "host_schedule_run" if domain == "host_schedule" and verb == "run_now" else "host_schedule_mutate" if domain == "host_schedule" else "native_configuration_read" if read else "native_schedule_mutate" if domain == "native_schedule" else "native_configuration_mutate"
    c = {"right": right, "authority": clone(AUTH), "scope_sha256": AUTH["scope_sha256"], "now": NOW, "current_revision": op.get("expected_revision", 0), "issued_approval_ids": [uid(8)]}
    case("control-" + domain + "-" + verb, "control", doc("agent_control_request", operation=op), context=c)
    if domain == "native_profile" and verb == "update":
        bad = clone(c); bad["authority"]["configuration_protection"] = "locked"
        case("native-configuration-protection", "control", doc("agent_control_request", operation=op), "configuration_protected", bad)
        bad = clone(c); bad["current_revision"] = 3
        case("native-stale-revision", "control", doc("agent_control_request", operation=op), "revision_conflict", bad)
        bad = clone(c); bad["import_blocked"] = True
        case("imported-profile-rebind-block", "control", doc("agent_control_request", operation=op), "native_rebind_required", bad)
    if domain == "native_profile" and verb == "delete":
        bad = clone(c); bad["last_profile"] = True
        case("native-last-profile-invariant", "control", doc("agent_control_request", operation=op), "invalid_request", bad)

# Reviewed query meanings use existing registry IDs; no new metric-registry rows.
rows = V.registry(ROOT)
def metric_row(mid, unit, stats, native, reducer, owner="civil_day_aggregate", availability="planned", feature="", evidence=True):
    return {"type": "catalog_metric", "metric_id": mid, "registry_equivalence": rows[mid]["equivalence"], "unit": unit, "statistics": sorted(stats), "native_record_type": native,
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
EXACT = {"epoch_second": 946684800, "nanosecond": 123456789, "source_offset_seconds": None}
IDENTITY = {"source_id": "health_connect", "provider_id": "health_connect", "record_type": "steps", "record_id": "synthetic-native-id", "identity_kind": "native", "parent_record_id": "", "origin": "synthetic.origin", "client_record_id": "synthetic-client-id", "client_record_version": 0, "last_modified": clone(EXACT)}

def fact(mid="steps", stat="sum", unit="steps", n=1):
    return {"type": "metric", "metric_id": mid, "owner_date": "2000-01-01", "unit": unit, "statistic": stat, "availability": "available", "value": {"type": "integer", "value": n}, "evidence_ids": []}
def session(kind):
    identity = clone(IDENTITY); identity["record_type"] = "sleep_session" if kind == "sleep" else "exercise_session"
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

PROJECTION_REQUEST = doc("source_projection_request", request_id=uid(90), peer=clone(PEER), source_id="health_connect", provider_id="health_connect", catalog_sha256=V.digest(CATALOG), dates=clone(DATES),
    calendar_timezone="Etc/UTC", selection=selection(["steps"]), detail="summary", object_ids=["capture_manifest", "daily_summary"], field_ids=["steps"], allow_partial=False)
case("android-projection-summary-not-healthkit", "query", PROJECTION_REQUEST, context={"allowed_field_ids": ["steps"]})
mutation("projection-no-hidden-native-records", "query", PROJECTION_REQUEST, lambda x: x["object_ids"].append("native_records"), "approval_required", {"allowed_field_ids": ["steps"]})
mutation("projection-no-arbitrary-json-pointer", "query", PROJECTION_REQUEST, lambda x: x.update(field_ids=["private.identity"]), "unsupported_metric", {"allowed_field_ids": ["steps"]})
PROJECTION = doc("source_data_projection", request_id=uid(90), peer=clone(PEER), source_id="health_connect", provider_id="health_connect", scope_sha256="a" * 64, catalog_sha256=V.digest(CATALOG),
    owner_date="2000-01-01", calendar_timezone="Etc/UTC", detail="summary", is_complete_daily_document=False, summary=[fact()], selected_series=[], native_records=[], coverage=clone(COVERAGE))
case("new-projection-independent-daily-profile", "query", PROJECTION)
mutation("projection-not-complete-daily-document", "query", PROJECTION, lambda x: x.update(is_complete_daily_document=True))

DICTIONARY = doc("profile_dictionary", profile="android-analytical-v5", source_schema="healthmd.health_data", source_schema_version=5, platform="android",
    registry_sha256=hashlib.sha256((ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json").read_bytes()).hexdigest(), dictionary_rules_version=1,
    entries=[{"field_id": "heart.hrv_samples", "semantic_id": "android.hrv_rmssd", "native_selection_id": "hrv", "native_type": "heart_rate_variability_rmssd", "unit": "ms", "statistic": "latest", "registry_equivalence": "platform_distinct", "mapping_state": "planned", "alias_notes": ["not_sdnn"]}], contains_health_values=False)
case("android-profile-specific-dictionary", "agent", DICTIONARY)
mutation("dictionary-not-apple-profile", "agent", DICTIONARY, lambda x: x.update(source_schema_version=8))
mutation("dictionary-no-health-values", "agent", DICTIONARY, lambda x: x.update(contains_health_values=True))
mutation("dictionary-rmssd-not-sdnn", "agent", DICTIONARY, lambda x: x["entries"][0].update(semantic_id="hrv"), "unsupported_metric")

DISCOVERY = doc("agent_discovery", request_id=uid(100), peer=clone(PEER), capability_revision=1, capability_sha256="2" * 64, issued_at=ISSUED, expires_at=EXPIRES,
    source_calendar_timezone="Etc/UTC", features=["bound_execution", "explicit_settings", "source_query", "zero_health_plan"], settings_policies=["explicit", "profile", "saved_device_settings"],
    output_profiles=["android-analytical-v5", "android-frozen-v4"], query_catalog_sha256=V.digest(CATALOG), query_operations=sorted(S.item_types), budgets=clone(BUDGETS), output_support=clone(OUTPUT_SUPPORT), control_operations=[], lifecycle="android_user_started_service_after_first_unlock", configuration_protection="locked", native_grants="unverified", entitlement="required", required_actions=["grant_health_access"])
DISCOVERY["capability_sha256"] = V.capability_digest(DISCOVERY)
case("read-only-runtime-discovery", "agent", DISCOVERY)
case("export-discovery-before-plan", "agent", BASE_DISCOVERY)
mutation("discovery-content-change-requires-new-hash", "agent", BASE_DISCOVERY, lambda x: x["output_support"].update(formats=["csv"]), "binding_changed")
WIRE_CASES = []
for kind, target in S.wire_types.items():
    value = {"discovery_request": doc("agent_discovery_request", request_id=uid(100), peer=clone(PEER)), "discovery": DISCOVERY,
        "plan_request": doc("agent_plan_request", request_id=uid(101), intent=clone(INTENT), authority_id=uid(7), capability_sha256=BASE_DISCOVERY["capability_sha256"]), "plan": PLAN,
        "execute": EXECUTE, "cancel": doc("agent_cancel_request", job_id=uid(10), peer=clone(PEER), request_sha256=V.digest(EXECUTE), authority_id=uid(7), approval_id=uid(8)), "receipt": RECEIPT, "resume": RESUME, "manifest": MANIFEST, "commit": COMMIT, "control": next(c["value"] for c in CASES if c["id"] == "control-local_recipe-get"),
        "control_receipt": doc("agent_control_receipt", request_id=uid(30), domain="local_recipe", status="success", object_id=uid(12), previous_revision=1, revision=2, value_sha256="a" * 64, items=[], required_actions=[]),
        "query_request": QUERIES["metric_series"], "query_response": series_response, "query_cancel": doc("source_query_cancel", request_id=uid(40), peer=clone(PEER), query_sha256="a" * 64, dataset_sha256="e" * 64),
        "query_cancelled": doc("source_query_cancelled", request_id=uid(40), peer=clone(PEER), query_sha256="a" * 64, dataset_sha256="e" * 64, source_acknowledged=True),
        "projection_request": PROJECTION_REQUEST, "projection": PROJECTION, "error": doc("agent_error", request_id=uid(102), code="unsupported_capability", retryable=False)}[target]
    envelope = {"protocol_version": 4, "type": kind, "payload": clone(value)}
    context = {**CONTEXT, "host_versions": [1, 2, 3, 4], "source_versions": [2, 4]}
    if kind.startswith("query"):
        authority = clone(AUTH); authority["scope_sha256"] = V.query_scope_hash(QUERIES["metric_series"])
        context.update(catalog=CATALOG, request=QUERIES["metric_series"], authority=authority)
    if kind == "projection_request": context["allowed_field_ids"] = ["steps"]
    case("v4-envelope-" + kind, "wire", envelope, context=context)
    old = clone(context); old["source_versions"] = [2]
    case("old-peer-never-new-case-" + kind, "wire", envelope, "unsupported_capability", old)
    WIRE_CASES.append(envelope)

if __name__ == "__main__":
    vectors = []
    for value in [PLAN, EXECUTE, COMMIT, QUERIES["metric_series"], CLAIMS, *WIRE_CASES]:
        raw = V.canonical(value)
        vectors.append({"value": value, "canonical_base64": base64.b64encode(raw).decode(), "sha256": hashlib.sha256(raw).hexdigest()})
    payload = doc("agent_bridge_test_vectors", provenance="Python-generated synthetic specification candidates; Rust/Swift/Kotlin generation and independent verification NOT RUN", cases=CASES, canonical_vectors=vectors)
    S.emit(HERE / "fixtures/conformance.json", payload)
    S.emit(HERE / "reviewed-query-catalog.json", REVIEWED_CATALOG)
    print("Generated", len(CASES), "synthetic cases and", len(vectors), "canonical vectors")
