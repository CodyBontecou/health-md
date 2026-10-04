#!/usr/bin/env python3
"""Build only new agent-bridge v1 / direct v4 schemas. No product code generation."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
D = {}
CONTROL_VERBS = {"local_recipe": ["list", "get", "create", "update", "delete", "run"],
    "native_profile": ["list", "get", "create", "update", "activate", "delete"],
    "host_schedule": ["list", "get", "create", "update", "pause", "delete", "run_now"],
    "native_schedule": ["inspect", "update", "enable", "disable", "inspect_pending", "discard_pending"],
    "native_destination": ["inspect", "update"]}
READ_VERBS = {"list", "get", "inspect", "inspect_pending"}
CONTROL_RIGHTS = ["recipe_mutate", "recipe_run", "host_schedule_mutate", "host_schedule_run", "native_configuration_mutate", "native_schedule_mutate"]

def obj(fields, optional=()):
    return {"type": "object", "additionalProperties": False, "properties": fields,
            "required": [k for k in fields if k not in optional]}

def ref(name): return {"$ref": "#/$defs/" + name}
def enum(*values): return {"type": "string", "enum": list(values)}
def text(n=256, minimum=1, pattern=None):
    x = {"type": "string", "minLength": minimum, "maxLength": n}
    if pattern: x["pattern"] = pattern
    return x

def integer(low=0, high=2147483647): return {"type": "integer", "minimum": low, "maximum": high}
def array(item, maximum=256, minimum=0, unique=False):
    x = {"type": "array", "items": item, "minItems": minimum, "maxItems": maximum}
    if unique: x["uniqueItems"] = True
    return x

def tagged(tag, fields, optional=()): return obj({"type": {"const": tag}, **fields}, optional)
def document(name, fields, optional=()):
    return obj({"schema": {"const": "healthmd." + name}, "schema_version": {"type": "integer", "const": 1}, **fields}, optional)

def add(name, shape): D[name] = shape; return ref(name)

add("uuid", text(36, 36, r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"))
add("digest", text(64, 64, r"^[0-9a-f]{64}$"))
add("id", text(128, pattern=r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$"))
add("date", {**text(10, 10, r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"), "format": "date"})
add("utc", {**text(20, 20, r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"), "format": "date-time"})
add("zone", text(128))
add("range", obj({"start_date": ref("date"), "end_date": ref("date")}))
add("dates", {"oneOf": [tagged("exact", {"range": ref("range")}), tagged("all_available", {}),
    tagged("past_complete_days", {"days": integer(1, 3650), "anchor_date": ref("date")})]})
add("peer", obj({"source_installation_id": ref("uuid"), "host_installation_id": ref("uuid"), "platform": enum("apple", "android")}))
add("destination", obj({"binding_id": ref("uuid"), "identity_sha256": ref("digest"), "revision": integer(1), "host_installation_id": ref("uuid")}))
add("path", text(4096, 0))
add("filename", text(255))
add("selection", obj({"metric_ids": array(ref("id"), 256, unique=True), "category_ids": array(ref("id"), 32, unique=True),
    "source_ids": array(ref("id"), 16, 1, True), "provider_ids": array(ref("id"), 16, unique=True), "all_metrics": {"type": "boolean"}}))
add("archive", {"oneOf": [tagged("none", {}), tagged("apple_healthkit_canonical_v1", {}),
    tagged("android_provider_native_snapshot_v1", {"provider_id": ref("id"), "record_scope": enum("selected", "all_authorized_supported"),
          "format": enum("json", "ndjson"), "include_exercise_routes": {"type": "boolean"}})]})
add("capture", obj({"selection": ref("selection"), "compatibility_detail": enum("summary", "selected_time_series"), "native_archive": ref("archive")}))
add("frontmatter", obj({"enabled_field_ids": array(ref("id"), 256, unique=True), "custom_fields": array(obj({"key": ref("id"), "value": text(4096, 0)}), 128),
    "include_units": {"type": "boolean"}, "include_capture_diagnostics": {"type": "boolean"}}))
add("markdown", obj({"style": enum("tables", "lists"), "custom_template": text(65536, 0), "placeholder_ids": array(ref("id"), 128, unique=True)}))
add("presentation", obj({"display_units": enum("metric", "imperial"), "machine_units": {"const": "canonical"}, "locale": text(64),
    "include_metadata": {"type": "boolean"}, "group_by_category": {"type": "boolean"}, "frontmatter": ref("frontmatter"), "markdown": ref("markdown")}))
add("individual_entries", obj({"enabled": {"type": "boolean"}, "metric_ids": array(ref("id"), 256, unique=True),
    "folder_template": ref("path"), "filename_template": ref("filename"), "category_folders": {"type": "boolean"}}))
add("daily_notes", obj({"enabled": {"type": "boolean"}, "only": {"type": "boolean"}, "folder_template": ref("path"),
    "filename_template": ref("filename"), "create_if_missing": {"type": "boolean"}, "section_ids": array(ref("id"), 64, unique=True)}))
add("packaging", {"oneOf": [tagged("loose_files", {}), tagged("zip", {"filename_template": ref("filename"), "include_loose_files": {"type": "boolean"},
    "max_uncompressed_bytes": integer(1, 1073741824), "max_entries": integer(1, 4096), "manifest": {"const": "healthmd.agent_artifact_manifest/1"}})]})
add("dictionary", {"oneOf": [tagged("none", {}), tagged("profile_dictionary_v1", {"format": enum("json", "markdown"), "filename_template": ref("filename")})]})
add("settings", obj({"formats": array(enum("csv", "json", "markdown", "obsidian_bases"), 4, 1, True), "output_profile": enum("apple-v8", "android-frozen-v4", "android-analytical-v5"),
    "subfolder": ref("path"), "folder_template": ref("path"), "filename_template": ref("filename"),
    "write_mode": enum("overwrite", "append", "merge_markdown", "merge_markdown_preserving_preamble"),
    "presentation": ref("presentation"), "individual_entries": ref("individual_entries"), "daily_notes": ref("daily_notes"),
    "packaging": ref("packaging"), "dictionary": ref("dictionary")}))
add("policy", {"oneOf": [tagged("explicit", {"settings": ref("settings")}),
    tagged("saved_device_settings", {"expected_revision": integer(1)}),
    tagged("profile", {"profile_id": ref("uuid"), "expected_revision": integer(1)})]})
add("revision", obj({"domain": enum("device_settings", "native_profile", "local_recipe", "host_schedule", "native_schedule", "native_destination", "native_credential_reference"),
    "object_id": ref("uuid"), "revision": integer(1), "sha256": ref("digest")}))
rights = ["discover", "plan", "query_summary", "query_evidence", "export_execute", "recipe_read", "recipe_mutate", "recipe_run",
          "native_configuration_read", "native_configuration_mutate", "host_schedule_read", "host_schedule_mutate", "host_schedule_run", "native_schedule_mutate"]
add("control_read_scope", obj({"objects": array(obj({"domain": enum(*CONTROL_VERBS), "object_id": ref("uuid")}), 256),
    "list_domains": array(enum(*CONTROL_VERBS), 5, unique=True), "create_domains": array(enum("local_recipe", "native_profile", "host_schedule"), 3, unique=True)}))
add("authority", document("agent_authority", {"authority_id": ref("uuid"), "issuer": enum("native_source", "authorized_host"), "peer": ref("peer"), "rights": array(enum(*rights), 14, 1, True),
    "scope_sha256": ref("digest"), "destination_binding_ids": array(ref("uuid"), 32, unique=True), "expires_at": ref("utc"),
    "configuration_protection": enum("not_applicable", "unlocked_native", "locked"), "native_consent": enum("satisfied", "required"),
    "entitlement": enum("satisfied", "required"), "grant_revision": integer(1), "control_read_scope": ref("control_read_scope")}, ["control_read_scope"]))
add("authority_reference", obj({"authority_id": ref("uuid"), "issuer": enum("native_source", "authorized_host"),
    "grant_revision": integer(1), "grant_sha256": ref("digest")}))
add("authority_references", obj({"native": ref("authority_reference"), "host": ref("authority_reference")}))
# Sanitized description of an already stored, native/host-approved export delegation, never a grant RPC.
add("export_delegation", document("agent_export_delegation", {"authority_id": ref("uuid"), "issuer": enum("native_source", "authorized_host"),
    "grant_revision": integer(1), "peer": ref("peer"), "rights": array(enum("discover", "plan", "export_execute"), 3, 1, True), "expires_at": ref("utc"),
    "bounds": obj({"products": array(enum("generated_files", "android_source_projection_v1"), 2, 1, True),
        "projection_details": array(enum("summary", "selected_time_series", "native_records"), 3, unique=True),
        "projection_object_ids": array(enum("daily_summary", "selected_series", "native_records", "capture_manifest"), 4, unique=True),
        "projection_field_ids": array(ref("id"), 256, unique=True), "metric_ids": array(ref("id"), 256, 1, True), "calendar_timezones": array(ref("zone"), 16, 1, True),
        "date_policy": {"oneOf": [tagged("bounded_exact", {"range": ref("range"), "max_days": integer(1, 366000)}),
            tagged("authorized_history", {"max_days": integer(1, 366000), "allow_all_available": {"type": "boolean"}})]},
        "formats": array(enum("csv", "json", "markdown", "obsidian_bases"), 4, 1, True),
        "output_profiles": array(enum("apple-v8", "android-frozen-v4", "android-analytical-v5"), 3, 1, True),
        "write_modes": array(enum("overwrite", "append", "merge_markdown", "merge_markdown_preserving_preamble"), 4, 1, True),
        "compatibility_detail": array(enum("summary", "selected_time_series"), 2, 1, True),
        "native_archive_products": array(enum("none", "apple_healthkit_canonical_v1", "android_provider_native_snapshot_v1"), 3, 1, True),
        "destination_policy": {"oneOf": [tagged("authenticated_host_bindings", {}),
            tagged("registered_host_bindings", {"binding_ids": array(ref("uuid"), 32, 1, True)})]}})}))
projection_output_fields = {"profile": {"const": "android-source-projection-v1"}, "layout": {"const": "per_day"}, "subfolder": ref("path"), "folder_template": ref("path"), "filename_template": ref("filename")}
add("projection_output", {"oneOf": [obj({**projection_output_fields, "media_type": {"const": "application/json"}, "write_mode": {"const": "overwrite"}}),
    obj({**projection_output_fields, "media_type": {"const": "application/x-ndjson"}, "write_mode": enum("overwrite", "append")})]})
add("projection_product", tagged("source_projection", {"product_id": {"const": "android_source_projection_v1"},
    "request": ref("projection_request"), "output": ref("projection_output")}))
intent_fields = {"intent_id": ref("uuid"), "peer": ref("peer"), "destination": ref("destination"), "dates": ref("dates"),
    "calendar_timezone": ref("zone"), "timestamp_timezone": {"const": "UTC"}, "capture_scope": ref("capture")}
add("generated_intent", document("agent_export_intent", {**intent_fields, "product": tagged("generated_files", {}), "settings_policy": ref("policy")}))
add("projection_intent", document("agent_export_intent", {**intent_fields, "product": ref("projection_product")}))
add("intent", {"oneOf": [ref("generated_intent"), ref("projection_intent")]})
features = ["explicit_settings", "zero_health_plan", "bound_execution", "source_query", "source_projection", "native_profile_control", "native_schedule_control", "native_destination_control", "control_plan", "zip", "profile_dictionary"]
add("budgets", obj({"max_page_items": integer(1, 1000), "max_page_bytes": integer(1024, 1048576), "max_snapshot_bytes": integer(1024, 67108864),
    "max_capture_seconds": integer(1, 120), "max_calendar_days": integer(1, 366000), "cursor_idle_seconds": integer(1, 600), "cursor_lifetime_seconds": integer(1, 3600)}))
add("output_support", obj({"formats": array(enum("csv", "json", "markdown", "obsidian_bases"), 4, unique=True),
    "write_modes": array(enum("overwrite", "append", "merge_markdown", "merge_markdown_preserving_preamble"), 4, unique=True),
    "compatibility_detail": array(enum("summary", "selected_time_series"), 2, unique=True),
    "native_archive_products": array(enum("none", "apple_healthkit_canonical_v1", "android_provider_native_snapshot_v1"), 3, unique=True),
    "setting_pointers": array(text(256, pattern=r"^/[a-z0-9_/]+$"), 512, unique=True),
    "path_tokens": array(enum("year", "month", "day", "date", "metric", "category", "record_id"), 7, unique=True),
    "max_artifacts": integer(1, 4096), "max_path_bytes": integer(1, 4096)}))
add("discovery_request", document("agent_discovery_request", {"request_id": ref("uuid"), "peer": ref("peer")}))
add("discovery", document("agent_discovery", {"request_id": ref("uuid"), "peer": ref("peer"), "capability_revision": integer(1), "capability_sha256": ref("digest"),
    "issued_at": ref("utc"), "expires_at": ref("utc"), "source_calendar_timezone": ref("zone"), "features": array(enum(*features), 11, unique=True), "settings_policies": array(enum("explicit", "saved_device_settings", "profile"), 3, unique=True),
    "output_profiles": array(enum("apple-v8", "android-frozen-v4", "android-analytical-v5"), 3, unique=True),
    "projection_products": array(enum("android_source_projection_v1"), 1, unique=True), "projection_catalog_sha256": ref("digest"), "projection_source_catalog": ref("query_catalog"), "query_catalog_sha256": ref("digest"), "query_operations": array(ref("id"), 9, unique=True),
    "budgets": ref("budgets"), "output_support": ref("output_support"), "control_operations": array(enum(*(domain + "." + verb for domain, verbs in CONTROL_VERBS.items() for verb in [*verbs, "plan"])), 64, unique=True),
    "authority_references": array(ref("authority_reference"), 32), "lifecycle": enum("iphone_foreground_protected_data", "android_user_started_service_after_first_unlock"),
    "configuration_protection": enum("locked", "unlocked_native"), "native_grants": enum("satisfied", "required", "unverified"),
    "entitlement": enum("satisfied", "required"), "required_actions": array(enum("open_mobile_app", "unlock_mobile", "grant_health_access", "grant_history_access", "native_configuration_unlock", "native_destination_rebind", "purchase_required"), 16, unique=True)}, ["projection_source_catalog"]))
add("plan_request", document("agent_plan_request", {"request_id": ref("uuid"), "intent": ref("intent"), "authority_id": ref("uuid"), "authority_revision": integer(1),
    "host_authority_reference": ref("authority_reference"), "capability_sha256": ref("digest")}))
add("origin", obj({"pointer": text(256), "origin": enum("request", "saved_device_settings", "profile", "resolved_calendar", "catalog"), "revision": integer()}))
plan_fields = {"plan_id": ref("uuid"), "resolved_dates": ref("dates"), "resolved_metric_ids": array(ref("id"), 256, 1, True),
    "authority_references": ref("authority_references"), "origins": array(ref("origin"), 512, 1), "revisions": array(ref("revision"), 16),
    "settings_sha256": ref("digest"), "scope_sha256": ref("digest"), "capability_sha256": ref("digest"), "plan_sha256": ref("digest"),
    "issued_at": ref("utc"), "expires_at": ref("utc"), "predicted_paths": array(ref("path"), 4096, unique=True),
    "path_prediction": enum("exact_requested_days", "template_only_all_available", "deferred_native_entries"),
    "required_actions": array(ref("id"), 16, unique=True), "limitations": array(ref("id"), 64, unique=True),
    "side_effects": ref("zero_control_effects")}
add("generated_plan", document("agent_export_plan", {**plan_fields, "intent": ref("generated_intent"), "effective_settings": ref("settings")}))
add("projection_plan", document("agent_export_plan", {**plan_fields, "intent": ref("projection_intent"), "effective_projection_output": ref("projection_output")}))
add("plan", {"oneOf": [ref("generated_plan"), ref("projection_plan")]})
add("binding", obj({"peer": ref("peer"), "destination": ref("destination"), "authority_references": ref("authority_references"), "plan_sha256": ref("digest"), "settings_sha256": ref("digest"),
    "scope_sha256": ref("digest"), "capability_sha256": ref("digest"), "revisions": array(ref("revision"), 16), "expires_at": ref("utc")}))
add("approval", document("agent_approval", {"approval_id": ref("uuid"), "authority_id": ref("uuid"), "binding": ref("binding"),
    "rights": array(enum("export_execute"), 1, 1, True), "approved_at": ref("utc")}))
add("approval_request", document("agent_approval_request", {"request_id": ref("uuid"), "plan_id": ref("uuid"), "binding": ref("binding")}))
add("execute", document("agent_execute_request", {"request_id": ref("uuid"), "job_id": ref("uuid"), "idempotency_key": ref("uuid"), "plan": ref("plan"), "approval": ref("approval")}))
add("cancel", document("agent_cancel_request", {"job_id": ref("uuid"), "peer": ref("peer"), "request_sha256": ref("digest"), "authority_id": ref("uuid"), "approval_id": ref("uuid")}))
add("resume", document("agent_resume_request", {"job_id": ref("uuid"), "peer": ref("peer"), "destination": ref("destination"), "binding": ref("binding"),
    "request_sha256": ref("digest"), "manifest_sha256": ref("digest"), "committed_partition_count": integer(), "frontier_sha256": ref("digest")}))
artifact_fields = {"artifact_id": ref("uuid"), "relative_path": ref("path"), "byte_count": integer(0, 1099511627776), "sha256": ref("digest"),
    "write_mode": enum("overwrite", "append", "merge_markdown", "merge_markdown_preserving_preamble")}
add("artifact", {"oneOf": [obj({**artifact_fields, "media_type": enum("application/json", "application/x-ndjson", "text/csv", "text/markdown", "application/zip"),
    "profile": enum("apple-v8", "android-frozen-v4", "android-analytical-v5", "apple-healthkit-canonical-v1", "android-provider-native-snapshot-v1", "profile-dictionary-v1", "zip-container-v1")}),
    obj({**artifact_fields, "profile": {"const": "android-source-projection-v1"}, "media_type": {"const": "application/json"}, "write_mode": {"const": "overwrite"}}),
    obj({**artifact_fields, "profile": {"const": "android-source-projection-v1"}, "media_type": {"const": "application/x-ndjson"}, "write_mode": enum("overwrite", "append")})]})
add("manifest", document("agent_artifact_manifest", {"job_id": ref("uuid"), "request_sha256": ref("digest"), "binding": ref("binding"), "artifacts": array(ref("artifact"), 4096),
    "capture_status": enum("complete", "complete_empty", "partial", "failed", "cancelled"), "branch_statuses": array(obj({"selector_id": ref("id"), "status": enum("success", "unsupported", "skipped", "failure", "cancelled"), "record_count": integer()}), 256)}))
add("commit", document("agent_commit_receipt", {"job_id": ref("uuid"), "artifact_id": ref("uuid"), "peer": ref("peer"), "destination": ref("destination"), "request_sha256": ref("digest"),
    "manifest_sha256": ref("digest"), "relative_path": ref("path"), "write_mode": enum("overwrite", "append", "merge_markdown", "merge_markdown_preserving_preamble"),
    "input_sha256": ref("digest"), "before_sha256": ref("digest"), "after_sha256": ref("digest"), "commit_key": ref("digest"), "status": enum("committed", "already_committed", "conflict")}))
add("receipt", document("agent_execution_receipt", {"job_id": ref("uuid"), "binding": ref("binding"), "request_sha256": ref("digest"), "manifest_sha256": ref("digest"),
    "status": enum("accepted", "paused", "complete", "complete_empty", "partial", "failed", "cancellation_pending", "cancelled", "expired"), "source_acknowledged": {"type": "boolean"},
    "artifact_count": integer(0, 4096), "committed_partition_count": integer(), "frontier_sha256": ref("digest"), "expires_at": ref("utc")}))
add("schedule", obj({"recipe_or_profile_id": ref("uuid"), "recipe_or_profile_revision": integer(1), "calendar_timezone": ref("zone"),
    "cadence": obj({"value": integer(1, 365), "unit": enum("days", "weeks", "months"), "anchor_date": ref("date")}),
    "local_time": obj({"hour": integer(0, 23), "minute": integer(0, 59)}), "iso_weekday": integer(1, 7), "lookback_days": integer(1, 365),
    "dst_gap": {"const": "skip"}, "dst_fold": {"const": "first_occurrence"}, "catch_up": enum("skip", "one_latest_complete_window"), "enabled": {"type": "boolean"}, "destination": ref("destination")}))
add("native_destination", {"oneOf": [tagged("existing_native_binding", {"binding_id": ref("uuid"), "expected_revision": integer(1)}),
    tagged("endpoint_disclosure", {"scheme": {"const": "https"}, "host": text(253), "port": integer(1, 65535), "path": text(2048),
        "query_omitted": {"const": True}, "credential_reference_id": ref("uuid"), "disclosure_sha256": ref("digest")}), tagged("requires_native_rebind", {"kind": enum("device_folder", "connected_mac", "api_endpoint")})]})
add("recipe_definition", obj({"name": text(128), "intent": ref("intent")}))
add("profile_definition", obj({"name": text(128), "capture_scope": ref("capture"), "settings": ref("settings"), "destination": ref("native_destination")}))
add("native_schedule_definition", obj({**D["schedule"]["properties"], "destination": ref("native_destination")}))
add("control_item", obj({"object_id": ref("uuid"), "revision": integer(1), "value_sha256": ref("digest"), "value": {"oneOf": [ref("recipe_definition"), ref("profile_definition"), ref("schedule"), ref("native_schedule_definition"), ref("native_destination")]}}))
# Closed candidate proposals are shared by planning and mutation; no arbitrary dispatch.
proposal_branches = []
DOMAIN_PROPOSALS = {}
for domain, verbs in CONTROL_VERBS.items():
    branches = []
    for verb in verbs:
        if verb in READ_VERBS: continue
        fields = {"domain": {"const": domain}, "verb": {"const": verb}, "object_id": ref("uuid"),
            "expected_revision": {"type": "integer", "const": 0} if verb == "create" else integer(1)}
        if verb in ("create", "update"):
            fields["value"] = ref("recipe_definition" if domain == "local_recipe" else "profile_definition" if domain == "native_profile" else "native_destination" if domain == "native_destination" else "native_schedule_definition" if domain == "native_schedule" else "schedule")
        if verb == "discard_pending": fields["pending_binding_sha256"] = ref("digest")
        branches.append(obj(fields))
    DOMAIN_PROPOSALS[domain] = add(domain + "_proposal", {"oneOf": branches})
    proposal_branches.extend(branches)
add("control_proposal", {"oneOf": proposal_branches})
add("zero_control_effects", obj({key: {"type": "integer", "const": 0} for key in
    ("health_reads", "earliest_date_reads", "content_preview_reads", "output_writes", "quota_consumed", "settings_mutations", "credential_enrollments", "wake_enrollments")}))
add("control_plan_request", document("agent_control_plan_request", {"request_id": ref("uuid"), "authority_id": ref("uuid"), "peer": ref("peer"),
    "capability_sha256": ref("digest"), "proposal": ref("control_proposal")}))
add("control_plan", document("agent_control_plan", {"plan_id": ref("uuid"), "request_id": ref("uuid"), "planning_authority_id": ref("uuid"),
    "peer": ref("peer"), "proposal": ref("control_proposal"), "proposal_sha256": ref("digest"), "scope_sha256": ref("digest"),
    "capability_sha256": ref("digest"), "revisions": array(ref("revision"), 16), "required_right": enum(*CONTROL_RIGHTS),
    "issued_at": ref("utc"), "expires_at": ref("utc"), "required_actions": array(ref("id"), 16, unique=True), "side_effects": ref("zero_control_effects"), "plan_sha256": ref("digest")}))
add("control_binding", obj({"plan_id": ref("uuid"), "peer": ref("peer"), "plan_sha256": ref("digest"), "proposal_sha256": ref("digest"),
    "scope_sha256": ref("digest"), "capability_sha256": ref("digest"), "revisions": array(ref("revision"), 16), "expires_at": ref("utc")}))
add("control_approval_request", document("agent_control_approval_request", {"request_id": ref("uuid"), "authority_id": ref("uuid"), "binding": ref("control_binding")}, ["authority_id"]))
add("control_approval", document("agent_control_approval", {"approval_id": ref("uuid"), "authority_id": ref("uuid"), "authority_reference": ref("authority_reference"), "binding": ref("control_binding"),
    "right": enum(*CONTROL_RIGHTS), "approved_at": ref("utc")}))
control_branches = []
for domain, verbs in CONTROL_VERBS.items():
    base = {"domain": {"const": domain}, "request_id": ref("uuid"), "authority_id": ref("uuid"), "peer": ref("peer")}
    for verb in verbs:
        if verb in READ_VERBS:
            fields = {**base, "verb": {"const": verb}}
            if verb != "list": fields.update(object_id=ref("uuid"), expected_revision=integer(1))
            control_branches.append(obj(fields))
    control_branches.append(obj({**base, "verb": {"const": "plan"}, "capability_sha256": ref("digest"), "proposal": DOMAIN_PROPOSALS[domain]}))
    for proposal in D[domain + "_proposal"]["oneOf"]:
        control_branches.append(obj({**base, **proposal["properties"], "idempotency_key": ref("uuid"), "plan": ref("control_plan"), "approval": ref("control_approval")}))
add("control", document("agent_control_request", {"operation": {"oneOf": control_branches}}))
add("control_receipt", document("agent_control_receipt", {"request_id": ref("uuid"), "domain": enum("local_recipe", "native_profile", "host_schedule", "native_schedule", "native_destination"),
    "status": enum("success", "conflict", "requires_native_action", "denied", "pending_recovery_retained"), "object_id": ref("uuid"),
    "previous_revision": integer(), "revision": integer(), "value_sha256": ref("digest"), "items": array(ref("control_item"), 100), "required_actions": array(ref("id"), 16, unique=True),
    "mutation_binding": obj({"binding": ref("control_binding"), "approval_id": ref("uuid"), "request_sha256": ref("digest")})}, ["mutation_binding"]))
add("error", document("agent_error", {"request_id": ref("uuid"), "code": enum("invalid_request", "unsupported_capability", "unsupported_metric", "permission_required", "history_unverified", "configuration_protected", "entitlement_required", "native_rebind_required", "revision_conflict", "approval_required", "binding_changed", "plan_expired", "unsafe_path", "path_collision", "query_budget_exceeded", "cursor_invalid", "snapshot_expired", "busy", "cancelled", "spool_missing_restart_required", "job_expired"), "retryable": {"type": "boolean"}}))

add("dictionary_document", document("profile_dictionary", {"profile": enum("apple-v8", "android-frozen-v4", "android-analytical-v5"), "source_schema": {"const": "healthmd.health_data"},
    "source_schema_version": {"type": "integer", "enum": [8, 4, 5]}, "platform": enum("apple", "android"), "registry_sha256": ref("digest"), "dictionary_rules_version": {"type": "integer", "const": 1},
    "entries": array(obj({"field_id": ref("id"), "semantic_id": ref("id"), "native_selection_id": ref("id"), "native_type": text(256, pattern=r"^[A-Za-z_][A-Za-z0-9_.:$-]{0,255}$"), "unit": text(32, 0),
        "statistic": text(128), "registry_equivalence": enum("platform_exact_or_unavailable", "mapped_alias", "platform_distinct"),
        "mapping_state": enum("profile_mapped", "planned", "unavailable"), "alias_notes": array(ref("id"), 16, unique=True)}), 512), "contains_health_values": {"const": False}}))
BRIDGE_ROOTS = ["intent", "authority", "export_delegation", "discovery_request", "discovery", "plan_request", "plan", "approval_request", "approval", "execute", "cancel", "resume", "manifest", "commit", "receipt",
    "control", "control_plan_request", "control_plan", "control_approval_request", "control_approval", "control_receipt", "dictionary_document", "error"]

def reachable(defs, roots):
    selected = set(roots)
    def references(value):
        if isinstance(value, dict):
            if "$ref" in value: yield value["$ref"][8:]
            for child in value.values(): yield from references(child)
        elif isinstance(value, list):
            for child in value: yield from references(child)
    while True:
        expanded = selected | {target for name in selected for target in references(defs[name])}
        if expanded == selected: return {name: defs[name] for name in sorted(selected)}
        selected = expanded

def schema(defs, roots, identity):
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://healthmd.app/contracts/" + identity,
            "oneOf": [ref(x) for x in roots], "$defs": reachable(defs, roots)}

def emit(path, payload):
    encoded = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(encoded, encoding="utf-8")

# Separate source-aware query view; Apple query_request/1 is not rewritten.
Q = dict(D)
add("query_page", obj({"max_items": integer(1, 1000), "max_bytes": integer(1024, 1048576), "cursor": text(4096)}, ["cursor"]))
operations = [tagged("metric_catalog", {}), tagged("metric_series", {}), tagged("coverage", {}), tagged("workout_listing", {}), tagged("source_record_listing", {}),
    tagged("sleep_session_listing", {"include_naps": {"type": "boolean"}, "window": obj({"start_offset_seconds": integer(-86400, 86400), "duration_seconds": integer(1, 86400)})}),
    tagged("workout_sleep_alignment", {"include_naps": {"type": "boolean"}, "workout_activity": ref("id"), "window": obj({"start_offset_seconds": integer(-86400, 86400), "duration_seconds": integer(1, 86400)})}),
    tagged("period_comparison", {"first": ref("range"), "second": ref("range"), "aggregations": array(obj({"metric_id": ref("id"), "kind": enum("sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"), "expected_unit": text(32)}), 256, 1)}),
    tagged("derive_packet", {"kind": enum("daily_wellness", "training", "doctor_visit"), "detail_ids": array(ref("id"), 64, unique=True)})]
add("query_operation", {"oneOf": operations})
add("query_request", document("source_query_request", {"request_id": ref("uuid"), "peer": ref("peer"), "source_id": enum("apple_health", "health_connect", "provider_native"),
    "provider_id": ref("id"), "catalog_sha256": ref("digest"), "authority_id": ref("uuid"), "authority_revision": integer(1), "dates": ref("dates"), "calendar_timezone": ref("zone"), "selection": ref("selection"),
    "detail": enum("summary", "native_evidence"), "include_evidence_values": {"type": "boolean"}, "operation": ref("query_operation"), "page": ref("query_page"), "budgets": ref("budgets")}))
add("native_type_identifier", text(256, pattern=r"^[A-Za-z_][A-Za-z0-9_.:$-]{0,255}$"))
time_fields = {"epoch_second": integer(-62135596800, 253402300799), "nanosecond": integer(0, 999999999),
    "source_offset_seconds": {"oneOf": [integer(-64800, 64800), {"type": "null"}]}}
add("exact_time", {"oneOf": [obj({**time_fields, "precision": enum("source_nanoseconds", "source_milliseconds", "source_seconds")}),
    obj({**time_fields, "precision": {"const": "source_binary64_seconds"}, "source_binary64_bits": text(16, 16, r"^[0-9a-f]{16}$")})]})
metadata_status = obj({"last_modified": enum("available", "not_captured", "not_exposed_by_source"),
    "client_record_id": enum("available", "absent", "not_captured", "not_exposed_by_source"),
    "client_record_version": enum("available", "not_captured", "not_exposed_by_source")})
identity_fields = {"record_type": ref("native_type_identifier"), "record_id": text(256), "identity_kind": enum("native", "derived_child", "external"),
    "parent_record_id": text(256), "parent_record_type": ref("native_type_identifier"), "origin": text(256)}
identity_optional = ["parent_record_id", "parent_record_type", "origin"]
add("native_identity", {"oneOf": [obj({**identity_fields, "source_id": {"const": "apple_health"}, "provider_id": {"const": "apple_health"},
    "metadata_status": obj({key: {"const": "not_exposed_by_source"} for key in metadata_status["properties"]})}, identity_optional),
    *[obj({**identity_fields, "source_id": {"const": source}, "provider_id": {"const": "health_connect"} if source == "health_connect" else ref("id"),
        "metadata_status": metadata_status, "client_record_id": text(256), "client_record_version": integer(0, 9223372036854775807),
        "last_modified": ref("exact_time")}, identity_optional + ["client_record_id", "client_record_version", "last_modified"]) for source in ("health_connect", "provider_native")]]})
add("value", {"oneOf": [tagged("integer", {"value": integer(-9007199254740991, 9007199254740991)}),
    tagged("decimal", {"value": text(80, pattern=r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$")}), tagged("text", {"value": text(1024, 0)})]})
add("metric_item", tagged("metric", {"metric_id": ref("id"), "owner_date": ref("date"), "unit": text(32), "statistic": enum("sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"),
    "availability": enum("available", "missing", "unsupported", "permission_required", "history_limited", "failed", "skipped"), "value": ref("value"), "evidence_ids": array(ref("digest"), 64, unique=True)}))
# Value is absent, not null/zero, for missing or unsupported facts.
D["metric_item"]["required"].remove("value")
add("session_item", tagged("session", {"kind": enum("sleep", "workout"), "owner_date": ref("date"), "identity": ref("native_identity"), "start": ref("exact_time"), "end": ref("exact_time"),
    "activity_or_stage": ref("id"), "duration_nanoseconds": text(32, pattern=r"^[0-9]+$"), "classification": enum("principal", "nap", "unclassified", "completed_workout"),
    "stages": array(obj({"raw_type": integer(-2147483648), "symbol": ref("id"), "start": ref("exact_time"), "end": ref("exact_time")}), 1000), "evidence_ids": array(ref("digest"), 64, unique=True)}))
add("comparison_item", tagged("comparison", {"metric_id": ref("id"), "unit": text(32), "statistic": enum("sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"),
    "first": ref("metric_item"), "second": ref("metric_item"), "delta": ref("value")}))
D["comparison_item"]["required"].remove("delta")
add("alignment_item", tagged("alignment", {"workout": ref("session_item"), "sleep": ref("session_item"), "relation": {"const": "first_following_sleep_start"},
    "gap_nanoseconds": text(32, pattern=r"^[0-9]+$"), "status": enum("complete", "partial", "unavailable"), "physiology": array(ref("metric_item"), 256)}))
D["alignment_item"]["required"].remove("sleep")
add("evidence_item", tagged("evidence", {"evidence_id": ref("digest"), "identity": ref("native_identity"), "start": ref("exact_time"), "end": ref("exact_time"),
    "metric_ids": array(ref("id"), 256, 1, True), "values": array(ref("metric_item"), 256)}))
add("catalog_item", tagged("catalog_metric", {"metric_id": ref("id"), "registry_equivalence": enum("platform_exact_or_unavailable", "mapped_alias", "platform_distinct"), "unit": text(32),
    "statistics": array(enum("sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"), 7, 1, True), "native_record_type": ref("native_type_identifier"),
    "source_statistic": text(128), "owner_rule": enum("civil_day_aggregate", "source_start_civil_day", "noon_to_noon_additive_native", "source_start_noon_journal"),
    "availability": enum("planned", "unavailable", "supported", "permission_required", "feature_unavailable", "history_unverified"), "target_or_reason": text(256),
    "feature_gate": text(128, 0), "evidence_value_support": {"type": "boolean"}}, ["native_record_type"]))
add("coverage", obj({"status": enum("complete", "complete_empty", "partial", "unavailable", "failed", "cancelled"), "days_considered": integer(0, 366000), "days_with_values": integer(0, 366000),
    "missing_count": integer(), "missing_truncated": {"type": "boolean"}, "missing": array(obj({"range": ref("range"), "metric_id": ref("id"), "reason": enum("no_records", "unsupported", "permission_required", "history_limited", "history_unverified", "failure", "skipped", "cancelled")}), 64),
    "history": obj({"state": enum("full_granted", "bounded", "unverified", "not_applicable"), "boundary": ref("date"), "feature_status": enum("available", "unavailable", "error", "not_applicable")}, ["boundary"])}))
add("packet", obj({"kind": enum("daily_wellness", "training", "doctor_visit"), "facts": array(ref("metric_item"), 1000), "medical_interpretation": {"const": False}}))
item_types = {"metric_catalog": "catalog_item", "metric_series": "metric_item", "coverage": None, "workout_listing": "session_item", "sleep_session_listing": "session_item", "period_comparison": "comparison_item", "workout_sleep_alignment": "alignment_item", "source_record_listing": "evidence_item", "derive_packet": None}
response_branches = []
for op, item in item_types.items():
    fields = {"request_id": ref("uuid"), "operation": {"const": op}, "peer": ref("peer"), "source_id": enum("apple_health", "health_connect", "provider_native"),
        "provider_id": ref("id"), "query_sha256": ref("digest"), "dataset_sha256": ref("digest"), "catalog_sha256": ref("digest"), "calendar_timezone": ref("zone"),
        "items": array(ref(item) if item else {}, 1000 if item else 0), "coverage": ref("coverage"), "limitations": array(ref("id"), 64, unique=True),
        "limitation_count": integer(), "limitations_truncated": {"type": "boolean"},
        "source_descriptors": array(obj({"source_id": ref("id"), "provider_id": ref("id"), "origin": text(256), "sha256": ref("digest")}), 64),
        "source_descriptor_count": integer(), "source_descriptors_truncated": {"type": "boolean"}, "next_cursor": text(4096), "expires_at": ref("utc")}
    if op == "derive_packet": fields["packet"] = ref("packet")
    if op == "metric_catalog": fields["catalog"] = ref("query_catalog")
    response_branches.append(document("source_query_response", fields, ["next_cursor"]))
add("query_response", {"oneOf": response_branches})
add("cursor_claims", document("source_query_cursor_claims", {"peer": ref("peer"), "query_sha256": ref("digest"), "dataset_sha256": ref("digest"), "catalog_sha256": ref("digest"),
    "authority_revision": integer(1), "position": integer(), "issued_at": ref("utc"), "expires_at": ref("utc"), "nonce": ref("uuid")}))
add("query_cancel", document("source_query_cancel", {"request_id": ref("uuid"), "peer": ref("peer"), "query_sha256": ref("digest"), "dataset_sha256": ref("digest")}))
add("projection_request", document("source_projection_request", {"request_id": ref("uuid"), "peer": ref("peer"), "source_id": enum("health_connect", "provider_native"), "provider_id": ref("id"),
    "catalog_sha256": ref("digest"), "projection_catalog_sha256": ref("digest"), "dates": ref("dates"), "calendar_timezone": ref("zone"), "selection": ref("selection"), "detail": enum("summary", "selected_time_series", "native_records"),
    "object_ids": array(enum("daily_summary", "selected_series", "native_records", "capture_manifest"), 4, 1, True), "field_ids": array(ref("id"), 256, 1, True), "allow_partial": {"type": "boolean"}}))
add("source_observation", tagged("source_observation", {"observation_id": ref("digest"), "field_id": ref("id"), "selection_metric_id": ref("id"),
    "owner_date": ref("date"), "identity": ref("native_identity"), "start": ref("exact_time"), "end": ref("exact_time"),
    "native_value_key": ref("native_type_identifier"), "observation_kind": enum("point", "interval_total"), "unit": text(32), "value": tagged("integer", {"value": integer(0, 9223372036854775807)})}, ["end"]))
add("projection_catalog", document("source_projection_catalog", {"product_id": {"const": "android_source_projection_v1"},
    "artifact_profile": {"const": "android-source-projection-v1"}, "source_id": {"const": "health_connect"}, "provider_id": {"const": "health_connect"},
    "sdk_version": {"const": "1.2.0-alpha02"}, "implementation_state": {"const": "planned"}, "contains_health_values": {"const": False},
    "fields": array(obj({"field_id": ref("id"), "object_id": enum("daily_summary", "selected_series", "native_records"), "selection_metric_id": ref("id"),
        "native_record_type": ref("native_type_identifier"), "parent_record_type": ref("native_type_identifier"), "native_value_key": ref("native_type_identifier"),
        "unit": text(32), "value_role": enum("daily_aggregate", "point", "interval_total", "native_record")}, ["parent_record_type"]), 256, 1)}))
add("projection", document("source_data_projection", {"request_id": ref("uuid"), "peer": ref("peer"), "source_id": enum("health_connect", "provider_native"), "provider_id": ref("id"),
    "scope_sha256": ref("digest"), "catalog_sha256": ref("digest"), "projection_catalog_sha256": ref("digest"), "owner_date": ref("date"), "calendar_timezone": ref("zone"), "detail": enum("summary", "selected_time_series", "native_records"),
    "is_complete_daily_document": {"const": False}, "summary": array(ref("metric_item"), 256), "selected_series": array(ref("source_observation"), 1000), "native_records": array(ref("evidence_item"), 1000), "coverage": ref("coverage")}))
add("query_catalog", document("source_query_catalog", {"peer": ref("peer"), "source_id": enum("apple_health", "health_connect", "provider_native"), "provider_id": ref("id"),
    "sdk_version": text(64), "provider_version": text(128), "provider_availability": enum("available", "unavailable", "update_required", "unverified"),
    "feature_statuses": array(obj({"feature": ref("id"), "status": enum("available", "unavailable", "error", "unverified")}), 32),
    "metrics": array(ref("catalog_item"), 256), "operations": array(ref("id"), 9, unique=True), "budgets": ref("budgets"), "history": ref("coverage")}))
add("projection_job", document("agent_projection_job", {"job_id": ref("uuid"), "execute": ref("execute"), "request_sha256": ref("digest"),
    "accepted_at": ref("utc"), "expires_at": ref("utc"), "resolved_dates": ref("dates"), "source_catalog": ref("query_catalog"), "projection_catalog": ref("projection_catalog"),
    "state": enum("accepted", "capturing", "spooled", "transferring", "complete", "failed", "cancelled"), "capture_started": {"type": "boolean"},
    "manifest_sha256": ref("digest"), "spool_sha256": ref("digest")}, ["manifest_sha256", "spool_sha256"]))
BRIDGE_ROOTS.append("projection_job")
add("query_cancelled", document("source_query_cancelled", {"request_id": ref("uuid"), "peer": ref("peer"), "query_sha256": ref("digest"), "dataset_sha256": ref("digest"), "source_acknowledged": {"const": True}}))
QUERY_ROOTS = ["query_request", "query_response", "query_catalog", "cursor_claims", "query_cancel", "query_cancelled", "projection_catalog", "projection_request", "projection"]
Q = dict(D)
# Wire payloads are explicit closed boxes, never Swift associated-value encodings.
wire_types = {"discovery_request": "discovery_request", "discovery_response": "discovery", "plan_request": "plan_request", "plan_response": "plan",
    "approval_request": "approval_request", "approval_response": "approval", "execute_request": "execute", "cancel_request": "cancel", "execution_receipt": "receipt", "resume_request": "resume", "artifact_manifest": "manifest", "commit_receipt": "commit",
    "control_plan_request": "control_plan_request", "control_plan_response": "control_plan", "control_approval_request": "control_approval_request", "control_approval_response": "control_approval",
    "control_request": "control", "control_receipt": "control_receipt", "query_request": "query_request", "query_response": "query_response", "query_cancel": "query_cancel", "query_cancelled": "query_cancelled",
    "rejected": "error"}
WIRE = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://healthmd.app/contracts/direct/v4/envelope", "$defs": reachable(Q, list(wire_types.values())),
        "oneOf": [obj({"protocol_version": {"type": "integer", "const": 4}, "type": {"const": kind}, "payload": ref(target)}) for kind, target in wire_types.items()]}

HC = "androidx.health.connect.client.records."
PROJECTION_CATALOG = {"schema": "healthmd.source_projection_catalog", "schema_version": 1, "product_id": "android_source_projection_v1",
    "artifact_profile": "android-source-projection-v1", "source_id": "health_connect", "provider_id": "health_connect", "sdk_version": "1.2.0-alpha02",
    "implementation_state": "planned", "contains_health_values": False, "fields": [
        {"field_id": "heart_rate.samples.bpm", "object_id": "selected_series", "selection_metric_id": "heart_rate_avg", "native_record_type": HC + "HeartRateRecord$Sample", "parent_record_type": HC + "HeartRateRecord", "native_value_key": "beatsPerMinute", "unit": "bpm", "value_role": "point"},
        {"field_id": "heart_rate_avg", "object_id": "daily_summary", "selection_metric_id": "heart_rate_avg", "native_record_type": HC + "HeartRateRecord", "native_value_key": "BPM_AVG", "unit": "bpm", "value_role": "daily_aggregate"},
        {"field_id": "steps", "object_id": "daily_summary", "selection_metric_id": "steps", "native_record_type": HC + "StepsRecord", "native_value_key": "COUNT_TOTAL", "unit": "steps", "value_role": "daily_aggregate"},
        {"field_id": "steps.count", "object_id": "selected_series", "selection_metric_id": "steps", "native_record_type": HC + "StepsRecord", "native_value_key": "count", "unit": "steps", "value_role": "interval_total"},
        {"field_id": "steps.record", "object_id": "native_records", "selection_metric_id": "steps", "native_record_type": HC + "StepsRecord", "native_value_key": "count", "unit": "steps", "value_role": "native_record"}]}

if __name__ == "__main__":
    # Reproducible copies of common definitions keep references local/offline.
    emit(HERE / "agent.schema.json", schema(D, BRIDGE_ROOTS, "agent-bridge/v1/agent"))
    emit(HERE / "query.schema.json", schema(Q, QUERY_ROOTS, "agent-bridge/v1/source-query"))
    emit(HERE / "reviewed-projection-catalog.json", PROJECTION_CATALOG)
    emit(HERE.parents[1] / "direct-protocol/v4/envelope.schema.json", WIRE)
