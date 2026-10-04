"""Executable synthetic conformance oracle, NOT a native authorizer/query engine.

The existing contract validator is passed in; none of its historical semantics change.
Errors contain fixed codes only, never rejected payloads.
"""
import base64
import copy
import hashlib
import hmac
import json
import math
import re
import struct
from fractions import Fraction
import unicodedata
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

HERE = Path(__file__).resolve().parent
DOMAIN = b"HealthMd.AgentBridge.SourceQueryCursor.v1\x00"

class Invalid(Exception):
    pass

def reject(code): raise Invalid(code)
def canonical(value): return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
def digest(value): return hashlib.sha256(canonical(value)).hexdigest()
def capability_digest(discovery):
    return digest({k: v for k, v in discovery.items() if k not in {"capability_sha256", "request_id", "issued_at", "expires_at"}})

def discovery_checks(discovery):
    if discovery["capability_sha256"] != capability_digest(discovery): reject("binding_changed")
    if not 0 < (instant(discovery["expires_at"]) - instant(discovery["issued_at"])).total_seconds() <= 600: reject("plan_expired")
    try: ZoneInfo(discovery["source_calendar_timezone"])
    except (ZoneInfoNotFoundError, ValueError): reject("invalid_request")
    for key in ("features", "settings_policies", "output_profiles", "query_operations", "control_operations", "projection_products"): sorted_ids(discovery[key])
    if bool(discovery["projection_products"]) != ("source_projection" in discovery["features"]): reject("invalid_request")
    if discovery["projection_products"]:
        catalog = discovery.get("projection_source_catalog")
        if not catalog or catalog["peer"] != discovery["peer"] or catalog["source_id"] != "health_connect" or discovery["projection_catalog_sha256"] != digest(projection_catalog()): reject("invalid_request")
        catalog_checks(catalog)
        if any(catalog["history"][k] for k in ("days_considered", "days_with_values", "missing_count")) or catalog["history"]["missing"]: reject("invalid_request")
    elif discovery["projection_catalog_sha256"] != "0" * 64 or "projection_source_catalog" in discovery: reject("invalid_request")
    for key in ("formats", "write_modes", "compatibility_detail", "native_archive_products", "setting_pointers", "path_tokens"): sorted_ids(discovery["output_support"][key])
    references = discovery["authority_references"]
    if any(r["issuer"] != "native_source" for r in references) or len({r["authority_id"] for r in references}) != len(references): reject("invalid_request")
def instant(value): return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
def date(value): return datetime.strptime(value, "%Y-%m-%d").date()

def preflight(value, depth=0, counter=None):
    if counter is None: counter = [0]
    counter[0] += 1
    if depth > 24 or counter[0] > 262144: reject("invalid_request")
    if isinstance(value, dict):
        if len(value) > 512: reject("invalid_request")
        for key, child in value.items():
            preflight(key, depth + 1, counter); preflight(child, depth + 1, counter)
    elif isinstance(value, list):
        if len(value) > 4096: reject("invalid_request")
        for child in value: preflight(child, depth + 1, counter)
    elif isinstance(value, str):
        if len(value) > 65536 or any(0xD800 <= ord(c) <= 0xDFFF for c in value): reject("invalid_request")
    elif isinstance(value, float): reject("invalid_request")

def parse(raw):
    if len(raw) > 2097152: reject("invalid_request")
    def pairs(rows):
        result = {}
        for key, value in rows:
            if key in result: reject("invalid_request")
            result[key] = value
        return result
    try: value = json.loads(raw, object_pairs_hook=pairs, parse_constant=lambda _: reject("invalid_request"))
    except (ValueError, UnicodeError): reject("invalid_request")
    preflight(value)
    return value

def schema_check(value, family, schema_validator):
    path = HERE / (family + ".schema.json") if family != "wire" else HERE.parents[1] / "direct-protocol/v4/envelope.schema.json"
    try: schema_validator(value, json.loads(path.read_text()), "agent-bridge")
    except Exception: reject("invalid_request")
    preflight(value)

def safe_path(path, filename=False, templates=False):
    if len(path.encode("utf-8")) > 4096 or any(ord(c) < 32 or ord(c) == 127 for c in path): reject("unsafe_path")
    if path.startswith(("/", "~")) or any(c in path for c in "\\:%\x00"): reject("unsafe_path")
    if not path:
        if filename: reject("unsafe_path")
        return
    if filename and "/" in path: reject("unsafe_path")
    parts = path.split("/")
    if len(parts) > 16: reject("unsafe_path")
    for part in parts:
        if not part or part in (".", "..") or part != part.strip() or part.endswith(".") or len(part.encode("utf-8")) > 255: reject("unsafe_path")
        if any(c in part for c in '<>"|?*'): reject("unsafe_path")
        tokens = re.findall(r"\{([^{}]*)\}", part)
        if tokens and (not templates or not set(tokens) <= {"year", "month", "day", "date", "metric", "category", "record_id"}): reject("unsafe_path")
        stripped = re.sub(r"\{[^{}]*\}", "x", part)
        if "{" in stripped or "}" in stripped: reject("unsafe_path")
        if re.fullmatch(r"(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", stripped): reject("unsafe_path")

def collisions(paths):
    keys = set()
    for path in paths:
        safe_path(path)
        if not path: reject("unsafe_path")
        key = unicodedata.normalize("NFC", path).casefold()
        if key in keys: reject("path_collision")
        keys.add(key)

def sorted_ids(value):
    if value != sorted(set(value)): reject("invalid_request")

def dates(selection, zone):
    try: ZoneInfo(zone)
    except (ZoneInfoNotFoundError, ValueError): reject("invalid_request")
    if selection["type"] == "exact":
        r = selection["range"]
        if date(r["start_date"]) > date(r["end_date"]): reject("invalid_request")
    if selection["type"] == "past_complete_days":
        start = date(selection["anchor_date"]) - timedelta(days=selection["days"])
        return {"type": "exact", "range": {"start_date": start.isoformat(), "end_date": (date(selection["anchor_date"]) - timedelta(days=1)).isoformat()}}
    return copy.deepcopy(selection)

def registry(root):
    raw = (root / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json").read_bytes()
    return {m["semantic_id"]: m for m in json.loads(raw)["metrics"]}

def resolve_selection(selection, platform, rows):
    for key in ("metric_ids", "category_ids", "source_ids", "provider_ids"): sorted_ids(selection[key])
    allowed_source = "apple_health" if platform == "apple" else "health_connect"
    if selection["source_ids"] != [allowed_source] or selection["provider_ids"]: reject("unsupported_capability")
    available = {key for key, row in rows.items() if row[platform].get("status") == "backed"}
    category_map = {}
    for key in available:
        category = rows[key][platform].get("category_id", "").lower()
        category_map.setdefault(category, set()).add(key)
    result = set(selection["metric_ids"])
    if not result <= available: reject("unsupported_metric")
    for category in selection["category_ids"]:
        if category not in category_map: reject("unsupported_metric")
        result.update(category_map[category])
    if selection["all_metrics"]: result.update(available)
    if not result or len(result) > 256: reject("unsupported_metric")
    return sorted(result)

def settings(value, platform):
    if value["formats"] != sorted(value["formats"]): reject("invalid_request")
    if (value["output_profile"].startswith("apple")) != (platform == "apple"): reject("unsupported_capability")
    for key in ("subfolder", "folder_template", "filename_template"):
        safe_path(value[key], filename=key == "filename_template", templates=True)
    # Daily filenames cannot depend on health records or mutable labels.
    for key in ("subfolder", "folder_template", "filename_template"):
        if set(re.findall(r"\{([^{}]*)\}", value[key])) - {"year", "month", "day", "date"}: reject("unsafe_path")
    for key in ("individual_entries", "daily_notes"):
        section = value[key]
        safe_path(section["folder_template"], templates=True)
        safe_path(section["filename_template"], filename=True, templates=True)
    for key in ("packaging", "dictionary"):
        if "filename_template" in value[key]:
            safe_path(value[key]["filename_template"], filename=True, templates=True)
            if set(re.findall(r"\{([^{}]*)\}", value[key]["filename_template"])) - {"year", "month", "day", "date"}: reject("unsafe_path")
    for key in ("folder_template", "filename_template"):
        if set(re.findall(r"\{([^{}]*)\}", value["daily_notes"][key])) - {"year", "month", "day", "date"}: reject("unsafe_path")
    if value["write_mode"].startswith("merge_markdown") and value["formats"] != ["markdown"]: reject("unsupported_capability")
    if value["daily_notes"]["only"] and not value["daily_notes"]["enabled"]: reject("invalid_request")
    for ids in (value["individual_entries"]["metric_ids"], value["daily_notes"]["section_ids"]): sorted_ids(ids)
    fields = value["presentation"]["frontmatter"]["custom_fields"]
    if len({f["key"] for f in fields}) != len(fields): reject("invalid_request")
    # No shadowing reserved machine meaning; dialect is data, never executable.
    if any(f["key"] in {"schema", "schema_version", "units", "raw_capture_status", "time_context"} for f in fields): reject("invalid_request")

def predicted_paths(intent, effective):
    selection = dates(intent["dates"], intent["calendar_timezone"])
    if selection["type"] == "all_available": return []
    r = selection["range"]
    days = (date(r["end_date"]) - date(r["start_date"])).days + 1
    if days * len(effective["formats"]) > 4096: reject("query_budget_exceeded")
    paths = []
    def expand(template, day):
        return template.format(year=f"{day.year:04}", month=f"{day.month:02}", day=f"{day.day:02}", date=day.isoformat())
    def join(parent, name): return (parent + "/" if parent else "") + name
    for n in range(days):
        day = date(r["start_date"]) + timedelta(days=n)
        parent = "/".join(expand(effective[k], day) for k in ("subfolder", "folder_template") if effective[k])
        base = expand(effective["filename_template"], day)
        if not effective["daily_notes"]["only"]:
            for fmt in effective["formats"]:
                ext = {"json": "json", "csv": "csv", "markdown": "md", "obsidian_bases": "md"}[fmt]
                suffix = "-bases" if fmt == "obsidian_bases" and "markdown" in effective["formats"] else ""
                paths.append(join(parent, base + suffix + "." + ext))
        notes = effective["daily_notes"]
        if notes["enabled"]:
            paths.append(join(expand(notes["folder_template"], day), expand(notes["filename_template"], day) + ".md"))
    # Run-level companions use the explicit final requested date, never latest health data.
    anchor = date(r["end_date"])
    root = expand(effective["subfolder"], anchor)
    if effective["dictionary"]["type"] != "none":
        d = effective["dictionary"]
        paths.append(join(root, expand(d["filename_template"], anchor) + (".json" if d["format"] == "json" else ".md")))
    collisions(paths)
    if effective["packaging"]["type"] == "zip":
        z = effective["packaging"]
        archive = join(root, expand(z["filename_template"], anchor) + ".zip")
        if len(paths) > z["max_entries"]: reject("query_budget_exceeded")
        collisions(paths + [archive])
        paths = paths + [archive] if z["include_loose_files"] else [archive]
    return sorted(paths)

def intent_checks(value, root):
    if value["destination"]["host_installation_id"] != value["peer"]["host_installation_id"]: reject("binding_changed")
    dates(value["dates"], value["calendar_timezone"])
    metrics = resolve_selection(value["capture_scope"]["selection"], value["peer"]["platform"], registry(root))
    archive = value["capture_scope"]["native_archive"]
    if archive["type"].startswith("apple") and value["peer"]["platform"] != "apple": reject("unsupported_capability")
    if archive["type"].startswith("android"):
        if value["peer"]["platform"] != "android": reject("unsupported_capability")
        if archive["record_scope"] == "all_authorized_supported" and not value["capture_scope"]["selection"]["all_metrics"]: reject("binding_changed")
        if archive["provider_id"] != "health_connect": reject("unsupported_capability")
    if is_projection(value):
        projection_intent_checks(value)
    else:
        policy = value["settings_policy"]
        if policy["type"] == "explicit": settings(policy["settings"], value["peer"]["platform"])
    return metrics

def leaves(value, prefix=""):
    if isinstance(value, dict):
        for key, child in value.items(): yield from leaves(child, prefix + "/" + key)
    else: yield prefix

def is_projection(intent): return intent["product"]["type"] == "source_projection"
def effective_output(plan): return plan["effective_projection_output"] if is_projection(plan["intent"]) else plan["effective_settings"]
def export_scope_payload(intent, resolved, metrics):
    return {"dates": resolved, "calendar_timezone": intent["calendar_timezone"], "capture_scope": intent["capture_scope"], "metric_ids": metrics, "product": intent["product"]}

def projection_catalog(): return json.loads((HERE / "reviewed-projection-catalog.json").read_text())
def projection_output_checks(output):
    for key in ("subfolder", "folder_template", "filename_template"):
        safe_path(output[key], filename=key == "filename_template", templates=True)
        if set(re.findall(r"\{([^{}]*)\}", output[key])) - {"year", "month", "day", "date"}: reject("unsafe_path")

def projection_request_checks(request, catalog=None):
    catalog = catalog or projection_catalog()
    if request["projection_catalog_sha256"] != digest(catalog): reject("binding_changed")
    if request["peer"]["platform"] != "android" or request["source_id"] != catalog["source_id"] or request["provider_id"] != catalog["provider_id"]: reject("unsupported_capability")
    dates(request["dates"], request["calendar_timezone"])
    for key in ("object_ids", "field_ids"): sorted_ids(request[key])
    sel = request["selection"]
    for key in ("metric_ids", "category_ids", "source_ids", "provider_ids"): sorted_ids(sel[key])
    if sel["category_ids"] or sel["all_metrics"]: reject("unsupported_metric")
    if sel["source_ids"] != [request["source_id"]] or sel["provider_ids"]: reject("unsupported_capability")
    if request["detail"] == "summary" and any(x in request["object_ids"] for x in ("selected_series", "native_records")): reject("approval_required")
    if "native_records" in request["object_ids"] and request["detail"] != "native_records": reject("approval_required")
    fields = {row["field_id"]: row for row in catalog["fields"]}
    if any(field not in fields or fields[field]["object_id"] not in request["object_ids"] for field in request["field_ids"]): reject("unsupported_metric")
    if sorted({fields[f]["selection_metric_id"] for f in request["field_ids"]}) != sel["metric_ids"]: reject("binding_changed")
    if any(obj != "capture_manifest" and not any(fields[f]["object_id"] == obj for f in request["field_ids"]) for obj in request["object_ids"]): reject("unsupported_metric")

def projection_capability_checks(intent, capabilities, catalog):
    product = intent["product"]; request = product["request"]
    if "source_projection" not in capabilities["features"] or product["product_id"] not in capabilities["projection_products"]: reject("unsupported_capability")
    if request["projection_catalog_sha256"] != capabilities["projection_catalog_sha256"] or request["catalog_sha256"] != digest(catalog): reject("binding_changed")
    if capabilities.get("projection_source_catalog") != catalog or catalog["peer"] != intent["peer"] or catalog["source_id"] != request["source_id"] or catalog["provider_id"] != request["provider_id"]: reject("binding_changed")
    catalog_checks(catalog)
    if catalog["provider_availability"] != "available": reject("unsupported_capability")
    metrics = {row["metric_id"]: row for row in catalog["metrics"]}
    if any(metrics.get(mid, {}).get("availability") != "supported" for mid in request["selection"]["metric_ids"]): reject("unsupported_metric")
    if product["output"]["write_mode"] not in capabilities["output_support"]["write_modes"] or "json" not in capabilities["output_support"]["formats"]: reject("unsupported_capability")

def projection_intent_checks(intent):
    product = intent["product"]; request = product["request"]; projection_request_checks(request)
    for key in ("peer", "dates", "calendar_timezone"):
        if intent[key] != request[key]: reject("binding_changed")
    capture = intent["capture_scope"]
    if capture["selection"] != request["selection"] or capture["native_archive"]["type"] != "none": reject("binding_changed")
    detail = "summary" if request["detail"] == "summary" else "selected_time_series"
    if capture["compatibility_detail"] != detail: reject("binding_changed")
    projection_output_checks(product["output"])

def projection_paths(intent, output):
    resolved = dates(intent["dates"], intent["calendar_timezone"])
    if resolved["type"] == "all_available": return []
    r = resolved["range"]; count = (date(r["end_date"]) - date(r["start_date"])).days + 1
    if count > 4096: reject("query_budget_exceeded")
    paths = []
    for offset in range(count):
        day = date(r["start_date"]) + timedelta(days=offset)
        values = {"year": f"{day.year:04}", "month": f"{day.month:02}", "day": f"{day.day:02}", "date": day.isoformat()}
        parent = "/".join(output[k].format(**values) for k in ("subfolder", "folder_template") if output[k])
        name = output["filename_template"].format(**values) + (".json" if output["media_type"] == "application/json" else ".jsonl")
        paths.append((parent + "/" if parent else "") + name)
    collisions(paths); return sorted(paths)

def projection_plan_checks(plan, metrics):
    intent = plan["intent"]; output = plan["effective_projection_output"]; projection_output_checks(output)
    resolved = dates(intent["dates"], intent["calendar_timezone"])
    if output != intent["product"]["output"] or plan["resolved_dates"] != resolved or plan["resolved_metric_ids"] != metrics: reject("binding_changed")
    if plan["revisions"]: reject("revision_conflict") # No saved/profile/native settings are consulted.
    if plan["settings_sha256"] != digest(output) or plan["scope_sha256"] != digest(export_scope_payload(intent, resolved, metrics)): reject("binding_changed")
    if plan["plan_sha256"] != digest({k: v for k, v in plan.items() if k != "plan_sha256"}): reject("binding_changed")
    if not 0 < (instant(plan["expires_at"]) - instant(plan["issued_at"])).total_seconds() <= 600: reject("plan_expired")
    if plan["predicted_paths"] != projection_paths(intent, output): reject("binding_changed")
    if resolved["type"] == "all_available" and (plan["path_prediction"] != "template_only_all_available" or "history_bounds_unresolved" not in plan["limitations"]): reject("binding_changed")
    if resolved["type"] != "all_available" and plan["path_prediction"] != "exact_requested_days": reject("binding_changed")
    expected = set(leaves(output, "/effective_projection_output")) | set(leaves(intent["capture_scope"], "/capture_scope")) | set(leaves(intent["product"]["request"], "/projection_request")) | {"/resolved_dates", "/calendar_timezone"}
    if len({x["pointer"] for x in plan["origins"]}) != len(plan["origins"]) or {x["pointer"] for x in plan["origins"]} != expected: reject("invalid_request")
    if any(x["origin"] != ("resolved_calendar" if x["pointer"] == "/resolved_dates" else "request") or x["revision"] != 0 for x in plan["origins"]): reject("binding_changed")

def plan_checks(plan, root):
    metrics = intent_checks(plan["intent"], root)
    if is_projection(plan["intent"]): projection_plan_checks(plan, metrics); return
    effective = plan["effective_settings"]
    settings(effective, plan["intent"]["peer"]["platform"])
    if plan["resolved_metric_ids"] != metrics: reject("binding_changed")
    if effective["individual_entries"]["enabled"]:
        if not effective["individual_entries"]["metric_ids"] or not set(effective["individual_entries"]["metric_ids"]) <= set(metrics): reject("binding_changed")
        if plan["intent"]["capture_scope"]["native_archive"]["type"] == "none": reject("unsupported_capability")
    if plan["resolved_dates"] != dates(plan["intent"]["dates"], plan["intent"]["calendar_timezone"]): reject("binding_changed")
    if plan["settings_sha256"] != digest(effective): reject("binding_changed")
    if plan["scope_sha256"] != digest(export_scope_payload(plan["intent"], plan["resolved_dates"], metrics)): reject("binding_changed")
    plain = {k: v for k, v in plan.items() if k != "plan_sha256"}
    if plan["plan_sha256"] != digest(plain): reject("binding_changed")
    if not 0 < (instant(plan["expires_at"]) - instant(plan["issued_at"])).total_seconds() <= 600: reject("plan_expired")
    paths = predicted_paths(plan["intent"], effective)
    if plan["predicted_paths"] != paths: reject("binding_changed")
    if plan["resolved_dates"]["type"] == "all_available":
        if plan["path_prediction"] != "template_only_all_available" or "history_bounds_unresolved" not in plan["limitations"]: reject("binding_changed")
    elif effective["individual_entries"]["enabled"]:
        if plan["path_prediction"] != "deferred_native_entries" or "entry_paths_unresolved" not in plan["limitations"]: reject("binding_changed")
    policy = plan["intent"]["settings_policy"]
    expected_origin = "request" if policy["type"] == "explicit" else policy["type"]
    if policy["type"] == "explicit" and effective != policy["settings"]: reject("binding_changed")
    if policy["type"] != "explicit":
        domain = "native_profile" if policy["type"] == "profile" else "device_settings"
        pins = [r for r in plan["revisions"] if r["domain"] == domain]
        if len(pins) != 1 or pins[0]["revision"] != policy["expected_revision"]: reject("revision_conflict")
        if policy["type"] == "profile" and pins[0]["object_id"] != policy["profile_id"]: reject("revision_conflict")
    origins = plan["origins"]
    expected = set(leaves(effective, "/effective_settings")) | set(leaves(plan["intent"]["capture_scope"], "/capture_scope")) | {"/resolved_dates", "/calendar_timezone"}
    if len({x["pointer"] for x in origins}) != len(origins) or {x["pointer"] for x in origins} != expected: reject("invalid_request")
    for origin in origins:
        want = expected_origin if origin["pointer"].startswith("/effective_settings/") else "resolved_calendar" if origin["pointer"] == "/resolved_dates" else "request"
        if origin["origin"] != want: reject("binding_changed")
        if want in ("saved_device_settings", "profile") and origin["revision"] != policy["expected_revision"]: reject("revision_conflict")

def binding(plan):
    return {"peer": plan["intent"]["peer"], "destination": plan["intent"]["destination"], **{k: plan[k] for k in ("authority_references", "plan_sha256", "settings_sha256", "scope_sha256", "capability_sha256", "revisions", "expires_at")}}

def require_authority(authority, right, peer, scope, destination, now):
    host_rights = {"recipe_read", "recipe_mutate", "recipe_run", "host_schedule_read", "host_schedule_mutate", "host_schedule_run"}
    native_rights = {"native_configuration_read", "native_configuration_mutate", "native_schedule_mutate", "query_summary", "query_evidence"}
    if right in host_rights and authority["issuer"] != "authorized_host" or right in native_rights and authority["issuer"] != "native_source": reject("approval_required")
    if right not in authority["rights"]: reject("approval_required")
    if authority["peer"] != peer or authority["scope_sha256"] != scope: reject("binding_changed")
    if instant(authority["expires_at"]) <= instant(now): reject("approval_required")
    if destination and destination["binding_id"] not in authority["destination_binding_ids"]: reject("approval_required")
    if right in ("native_configuration_mutate", "native_schedule_mutate"):
        if authority["configuration_protection"] != "unlocked_native": reject("configuration_protected")
    if right in ("export_execute", "native_configuration_mutate", "native_schedule_mutate", "host_schedule_run"):
        if authority["native_consent"] != "satisfied": reject("permission_required")
        if authority["entitlement"] != "satisfied": reject("entitlement_required")

def authority_reference(delegation):
    return {k: delegation[k] for k in ("authority_id", "issuer", "grant_revision")} | {"grant_sha256": digest(delegation)}

def delegation_checks(delegation):
    if not set(delegation["rights"]) <= {"discover", "plan", "export_execute"}: reject("invalid_request")
    sorted_ids(delegation["rights"])
    bounds = delegation["bounds"]
    for key in ("products", "projection_details", "projection_object_ids", "projection_field_ids", "metric_ids", "calendar_timezones", "formats", "output_profiles", "write_modes", "compatibility_detail", "native_archive_products"): sorted_ids(bounds[key])
    for zone in bounds["calendar_timezones"]:
        try: ZoneInfo(zone)
        except (ZoneInfoNotFoundError, ValueError): reject("invalid_request")
    policy = bounds["destination_policy"]
    want = "authenticated_host_bindings" if delegation["issuer"] == "native_source" else "registered_host_bindings"
    if policy["type"] != want: reject("invalid_request")
    if "binding_ids" in policy: sorted_ids(policy["binding_ids"])
    policy = bounds["date_policy"]
    if policy["type"] == "bounded_exact" and date(policy["range"]["start_date"]) > date(policy["range"]["end_date"]): reject("invalid_request")

def delegated_scope(delegation, intent, effective, metrics, now, right):
    delegation_checks(delegation)
    if delegation["peer"] != intent["peer"]: reject("binding_changed")
    if right not in delegation["rights"] or instant(delegation["expires_at"]) <= instant(now): reject("approval_required")
    bounds = delegation["bounds"]
    if not set(metrics) <= set(bounds["metric_ids"]) or intent["calendar_timezone"] not in bounds["calendar_timezones"]: reject("approval_required")
    if is_projection(intent):
        product = intent["product"]; request = product["request"]
        if product["product_id"] not in bounds["products"] or "json" not in bounds["formats"] or effective["write_mode"] not in bounds["write_modes"]: reject("approval_required")
        if request["detail"] not in bounds["projection_details"] or not set(request["object_ids"]) <= set(bounds["projection_object_ids"]) or not set(request["field_ids"]) <= set(bounds["projection_field_ids"]): reject("approval_required")
    elif "generated_files" not in bounds["products"] or not set(effective["formats"]) <= set(bounds["formats"]) or effective["output_profile"] not in bounds["output_profiles"] or effective["write_mode"] not in bounds["write_modes"]: reject("approval_required")
    if intent["capture_scope"]["compatibility_detail"] not in bounds["compatibility_detail"] or intent["capture_scope"]["native_archive"]["type"] not in bounds["native_archive_products"]: reject("approval_required")
    selected = dates(intent["dates"], intent["calendar_timezone"]); policy = bounds["date_policy"]
    if selected["type"] == "all_available":
        if policy["type"] != "authorized_history" or not policy["allow_all_available"]: reject("approval_required")
        # Logical history remains unresolved; execution must enforce max_days, never clip silently.
    else:
        r = selected["range"]
        if (date(r["end_date"]) - date(r["start_date"])).days + 1 > policy["max_days"]: reject("approval_required")
        if policy["type"] == "bounded_exact" and not date(policy["range"]["start_date"]) <= date(r["start_date"]) <= date(r["end_date"]) <= date(policy["range"]["end_date"]): reject("approval_required")
    dest_policy = bounds["destination_policy"]
    if dest_policy["type"] == "registered_host_bindings" and intent["destination"]["binding_id"] not in dest_policy["binding_ids"]: reject("approval_required")

def stored_export_delegations(references, intent, effective, metrics, context, right):
    found = []
    for slot, issuer in (("native", "native_source"), ("host", "authorized_host")):
        reference = references[slot]
        stored = context.get("stored_" + slot + "_delegations", {}).get(reference["authority_id"])
        if not stored or reference["issuer"] != issuer or authority_reference(stored) != reference: reject("approval_required")
        delegated_scope(stored, intent, effective, metrics, context["now"], right)
        found.append(stored)
    if context.get("registered_destinations", {}).get(intent["destination"]["binding_id"]) != intent["destination"]: reject("binding_changed")
    return found

def derived_export_authority(delegation, plan, readiness):
    # Pure, scoped description; reuse the stored parent ID/revision. No issuance, credentials or writes.
    return {"schema": "healthmd.agent_authority", "schema_version": 1, "authority_id": delegation["authority_id"], "issuer": delegation["issuer"], "peer": copy.deepcopy(delegation["peer"]),
        "rights": copy.deepcopy(delegation["rights"]), "scope_sha256": plan["scope_sha256"], "destination_binding_ids": [plan["intent"]["destination"]["binding_id"]],
        "expires_at": min(delegation["expires_at"], plan["expires_at"]), "grant_revision": delegation["grant_revision"],
        "configuration_protection": "not_applicable", "native_consent": readiness["native_consent"], "entitlement": readiness["entitlement"]}

def export_plan_request_checks(request, context, root):
    capabilities = context["capabilities"]; discovery_checks(capabilities)
    if request["capability_sha256"] != capabilities["capability_sha256"] or request["intent"]["peer"] != capabilities["peer"]: reject("binding_changed")
    if instant(capabilities["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    if "zero_health_plan" not in capabilities["features"]: reject("unsupported_capability")
    refs = [r for r in capabilities["authority_references"] if r["authority_id"] == request["authority_id"] and r["grant_revision"] == request["authority_revision"]]
    if len(refs) != 1: reject("approval_required")
    intent = request["intent"]; metrics = intent_checks(intent, root)
    effective = intent["product"]["output"] if is_projection(intent) else intent["settings_policy"].get("settings", context.get("effective_settings"))
    if effective is None: reject("revision_conflict")
    if is_projection(intent): projection_capability_checks(intent, capabilities, context["catalog"])
    else: settings(effective, intent["peer"]["platform"])
    stored_export_delegations({"native": refs[0], "host": request["host_authority_reference"]}, intent, effective, metrics, context, "plan")

def export_approval_request_checks(request, context, root):
    plan = context["plan"]; plan_checks(plan, root)
    if request["plan_id"] != plan["plan_id"] or request["binding"] != binding(plan): reject("binding_changed")
    if context["issued_plans"].get(plan["plan_id"]) != plan["plan_sha256"]: reject("binding_changed")
    if instant(plan["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    delegations = stored_export_delegations(plan["authority_references"], plan["intent"], effective_output(plan), plan["resolved_metric_ids"], context, "export_execute")
    if instant(plan["expires_at"]) > min(instant(d["expires_at"]) for d in delegations): reject("plan_expired")
    if context.get("approved_export_binding_sha256") != digest(binding(plan)): reject("approval_required")
    for authority, delegation in zip((context["authority"], context["host_authority"]), delegations):
        if authority != derived_export_authority(delegation, plan, authority): reject("approval_required")
    for field in ("peer", "destination", "capability_sha256", "revisions"):
        if context[field] != binding(plan)[field]: reject("revision_conflict" if field == "revisions" else "binding_changed")
    require_authority(context["authority"], "export_execute", plan["intent"]["peer"], plan["scope_sha256"], plan["intent"]["destination"], context["now"])
    require_authority(context["host_authority"], "export_execute", plan["intent"]["peer"], plan["scope_sha256"], plan["intent"]["destination"], context["now"])

def execute_checks(request, context, root):
    plan = request["plan"]; plan_checks(plan, root)
    approved = request["approval"]
    if context["issued_plans"].get(plan["plan_id"]) != plan["plan_sha256"]: reject("binding_changed")
    if approved["binding"] != binding(plan): reject("binding_changed")
    previous = context.get("existing_request_sha256")
    if previous:
        if previous != digest(request): reject("binding_changed")
        for field in ("peer", "destination"):
            if context[field] != binding(plan)[field]: reject("binding_changed")
        # Exact accepted retry returns only its stored job/receipt; it never captures again.
        # Resume has its separate immutable journal, native-grant and seven-day expiry gates.
        return (request["job_id"], request["idempotency_key"])
    if instant(plan["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    if instant(approved["approved_at"]) < instant(plan["issued_at"]) or instant(approved["approved_at"]) > instant(context["now"]): reject("approval_required")
    if plan["required_actions"]: reject("native_rebind_required")
    for field in ("peer", "destination", "capability_sha256", "revisions"):
        if context[field] != binding(plan)[field]: reject("revision_conflict" if field == "revisions" else "binding_changed")
    capabilities = context["capabilities"]
    discovery_checks(capabilities)
    if capabilities["capability_sha256"] != plan["capability_sha256"] or capabilities["peer"] != plan["intent"]["peer"]: reject("binding_changed")
    if instant(capabilities["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    support = capabilities["output_support"]
    settings = effective_output(plan)
    if not {"bound_execution", "zero_health_plan"} <= set(capabilities["features"]): reject("unsupported_capability")
    if is_projection(plan["intent"]): projection_capability_checks(plan["intent"], capabilities, context["catalog"])
    else:
        if not set(settings["formats"]) <= set(support["formats"]) or settings["write_mode"] not in support["write_modes"] or settings["output_profile"] not in capabilities["output_profiles"]: reject("unsupported_capability")
        if plan["intent"]["settings_policy"]["type"] not in capabilities["settings_policies"]: reject("unsupported_capability")
        if plan["intent"]["capture_scope"]["native_archive"]["type"] not in support["native_archive_products"] or plan["intent"]["capture_scope"]["compatibility_detail"] not in support["compatibility_detail"]: reject("unsupported_capability")
        if settings["packaging"]["type"] == "zip" and "zip" not in capabilities["features"] or settings["dictionary"]["type"] != "none" and "profile_dictionary" not in capabilities["features"]: reject("unsupported_capability")
    if approved["approval_id"] not in context["issued_approval_ids"] or context["issued_approvals"].get(approved["approval_id"]) != digest(approved) or approved["authority_id"] != context["authority"]["authority_id"]: reject("approval_required")
    if "export_execute" not in approved["rights"]: reject("approval_required")
    require_authority(context["authority"], "export_execute", plan["intent"]["peer"], plan["scope_sha256"], plan["intent"]["destination"], context["now"])
    native, host = stored_export_delegations(plan["authority_references"], plan["intent"], effective_output(plan), plan["resolved_metric_ids"], context, "export_execute")
    if plan["authority_references"]["native"] not in capabilities["authority_references"]: reject("approval_required")
    if instant(plan["expires_at"]) > min(instant(d["expires_at"]) for d in (native, host)): reject("plan_expired")
    for authority, delegation in ((context["authority"], native), (context["host_authority"], host)):
        expected = derived_export_authority(delegation, plan, authority)
        if authority != expected: reject("approval_required")
        require_authority(authority, "export_execute", plan["intent"]["peer"], plan["scope_sha256"], plan["intent"]["destination"], context["now"])
    identity = (request["job_id"], request["idempotency_key"])
    return identity

def cursor_issue(claims, key):
    payload = canonical(claims)
    mac = hmac.new(key, DOMAIN + payload, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(payload).rstrip(b"=").decode() + "." + base64.urlsafe_b64encode(mac).rstrip(b"=").decode()

def cursor_verify(token, key, expected, now):
    try:
        if len(token) > 4096 or token.count(".") != 1: reject("cursor_invalid")
        left, right = token.split(".")
        if not re.fullmatch(r"[A-Za-z0-9_-]+", left) or not re.fullmatch(r"[A-Za-z0-9_-]+", right): reject("cursor_invalid")
        payload = base64.urlsafe_b64decode(left + "=" * (-len(left) % 4)); mac = base64.urlsafe_b64decode(right + "=" * (-len(right) % 4))
        if not hmac.compare_digest(mac, hmac.new(key, DOMAIN + payload, hashlib.sha256).digest()): reject("cursor_invalid")
        claims = parse(payload)
        required = {"schema", "schema_version", "peer", "query_sha256", "dataset_sha256", "catalog_sha256", "authority_revision", "position", "issued_at", "expires_at", "nonce"}
        if set(claims) != required or claims["schema"] != "healthmd.source_query_cursor_claims" or type(claims["schema_version"]) is not int or claims["schema_version"] != 1: reject("cursor_invalid")
        if type(claims["position"]) is not int or not 0 <= claims["position"] <= 2147483647 or type(claims["authority_revision"]) is not int or claims["authority_revision"] < 1: reject("cursor_invalid")
        if canonical(claims) != payload or cursor_issue(claims, key) != token: reject("cursor_invalid")
        for name in ("peer", "query_sha256", "dataset_sha256", "catalog_sha256", "authority_revision"):
            if claims[name] != expected[name]: reject("cursor_invalid")
        if instant(claims["expires_at"]) <= instant(now): reject("snapshot_expired")
        if instant(claims["issued_at"]) > instant(now) or (instant(claims["expires_at"]) - instant(claims["issued_at"])).total_seconds() > 3600: reject("cursor_invalid")
        if expected.get("snapshot_alive") is False: reject("snapshot_expired")
        if expected.get("cancelled") or expected.get("revoked"): reject("cursor_invalid")
        return claims
    except (KeyError, ValueError, UnicodeError, TypeError): reject("cursor_invalid")

def query_scope_hash(request):
    scope = copy.deepcopy(request)
    del scope["request_id"]
    scope["page"].pop("cursor", None)
    return digest(scope)

def query_checks(request, catalog, authority, now):
    dates(request["dates"], request["calendar_timezone"])
    if request["catalog_sha256"] != digest(catalog): reject("binding_changed")
    if request["source_id"] != catalog["source_id"] or request["provider_id"] != catalog["provider_id"] or request["peer"] != catalog["peer"]: reject("binding_changed")
    if catalog["provider_availability"] != "available": reject("unsupported_capability")
    history = catalog["history"]["history"]
    if request["dates"]["type"] == "all_available" and history["state"] not in ("full_granted", "not_applicable"): reject("history_unverified")
    selection = request["selection"]
    for key in ("metric_ids", "category_ids", "source_ids", "provider_ids"): sorted_ids(selection[key])
    if selection["category_ids"] or selection["all_metrics"]: reject("unsupported_metric") # resolved IDs required for this bounded query edition
    if selection["source_ids"] != [request["source_id"]] or selection["provider_ids"]: reject("unsupported_capability")
    ids = selection["metric_ids"]
    rows = {x["metric_id"]: x for x in catalog["metrics"]}
    if not ids or any(x not in rows or rows[x]["availability"] != "supported" for x in ids): reject("unsupported_metric")
    features = {x["feature"]: x["status"] for x in catalog["feature_statuses"]}
    if any(rows[x]["feature_gate"] and features.get(rows[x]["feature_gate"].removeprefix("FEATURE_").lower()) != "available" for x in ids): reject("unsupported_capability")
    op = request["operation"]["type"]
    if op not in catalog["operations"]: reject("unsupported_capability")
    if request["include_evidence_values"] or op == "source_record_listing":
        if request["detail"] != "native_evidence" or not request["include_evidence_values"]: reject("approval_required")
    if any(not rows[x]["evidence_value_support"] for x in ids) and request["include_evidence_values"]: reject("unsupported_capability")
    if op in ("sleep_session_listing", "workout_sleep_alignment") and "sleep_total" not in ids: reject("unsupported_metric")
    if op in ("workout_listing", "workout_sleep_alignment") and "workouts" not in ids: reject("unsupported_metric")
    if op == "period_comparison":
        seen = set()
        for agg in request["operation"]["aggregations"]:
            metric = agg["metric_id"]
            if metric in seen or metric not in ids: reject("unsupported_metric")
            seen.add(metric)
            if agg["kind"] not in rows[metric]["statistics"] or agg["expected_unit"] != rows[metric]["unit"]: reject("unsupported_metric")
        if request["dates"]["type"] != "exact": reject("invalid_request")
        outer = request["dates"]["range"]
        for key in ("first", "second"):
            r = request["operation"][key]
            if not date(outer["start_date"]) <= date(r["start_date"]) <= date(r["end_date"]) <= date(outer["end_date"]): reject("invalid_request")
    for key, value in request["budgets"].items():
        if value > catalog["budgets"][key]: reject("query_budget_exceeded")
    if request["page"]["max_items"] > request["budgets"]["max_page_items"] or request["page"]["max_bytes"] > request["budgets"]["max_page_bytes"]: reject("query_budget_exceeded")
    right = "discover" if op == "metric_catalog" else "query_evidence" if request["include_evidence_values"] else "query_summary"
    if authority["authority_id"] != request["authority_id"] or authority["grant_revision"] != request["authority_revision"]: reject("approval_required")
    require_authority(authority, right, request["peer"], query_scope_hash(request), None, now)
    if op != "metric_catalog" and authority["native_consent"] != "satisfied": reject("permission_required")

def exact_ns(value): return value["epoch_second"] * 1000000000 + value["nanosecond"]

def time_checks(value):
    precision = value["precision"]
    if precision == "source_binary64_seconds":
        seconds = struct.unpack(">d", bytes.fromhex(value["source_binary64_bits"]))[0]
        if not math.isfinite(seconds) or exact_ns(value) != round(Fraction.from_float(seconds) * 1000000000): reject("invalid_request")
    elif precision == "source_milliseconds" and value["nanosecond"] % 1000000: reject("invalid_request")
    elif precision == "source_seconds" and value["nanosecond"]: reject("invalid_request")

def native_identity_checks(identity):
    for key, state in identity["metadata_status"].items():
        if (state == "available") != (key in identity): reject("invalid_request")
    child = identity["identity_kind"] == "derived_child"
    if child:
        if not identity.get("parent_record_id") or not identity.get("parent_record_type"): reject("invalid_request")
        if any(state != "not_exposed_by_source" for state in identity["metadata_status"].values()): reject("invalid_request")
    elif "parent_record_id" in identity or "parent_record_type" in identity: reject("invalid_request")
    if identity["source_id"] == "apple_health" and identity["identity_kind"] == "native":
        if not re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", identity["record_id"]): reject("invalid_request")
    if identity["source_id"] == "health_connect" and identity["identity_kind"] == "native":
        if identity["metadata_status"]["last_modified"] == "not_exposed_by_source" or identity["metadata_status"]["client_record_version"] == "not_exposed_by_source": reject("invalid_request")
        if "last_modified" in identity and identity["last_modified"]["precision"] != "source_nanoseconds": reject("invalid_request")
    if "last_modified" in identity: time_checks(identity["last_modified"])

def catalog_checks(catalog):
    for row in catalog["metrics"]:
        native_type = row.get("native_record_type")
        if row["availability"] != "unavailable" and not native_type: reject("invalid_request")
        if native_type and catalog["source_id"] == "health_connect" and not native_type.startswith("androidx.health.connect.client.records."): reject("invalid_request")

def value_checks(item, rows):
    if item["metric_id"] not in rows: reject("unsupported_metric")
    row = rows[item["metric_id"]]
    if item["unit"] != row["unit"] or item["statistic"] not in row["statistics"]: reject("unsupported_metric")
    if (item["availability"] == "available") != ("value" in item): reject("invalid_request")

def response_checks(response, request, catalog):
    if response["query_sha256"] != query_scope_hash(request): reject("binding_changed")
    for key in ("peer", "source_id", "provider_id", "request_id", "calendar_timezone", "catalog_sha256"):
        if response[key] != request[key]: reject("binding_changed")
    if response["operation"] != request["operation"]["type"]: reject("binding_changed")
    if response["operation"] == "metric_catalog" and response["catalog"] != catalog: reject("binding_changed")
    if len(response["items"]) > request["page"]["max_items"] or len(canonical(response)) > request["page"]["max_bytes"]: reject("query_budget_exceeded")
    coverage = response["coverage"]
    if response["limitation_count"] < len(response["limitations"]) or response["limitations_truncated"] != (response["limitation_count"] > len(response["limitations"])): reject("invalid_request")
    if coverage["days_with_values"] > coverage["days_considered"]: reject("invalid_request")
    if coverage["missing_count"] < len(coverage["missing"]) or coverage["missing_truncated"] != (coverage["missing_count"] > len(coverage["missing"])): reject("invalid_request")
    if coverage["status"] in ("complete", "complete_empty") and (coverage["history"]["state"] == "unverified" or any(x["reason"] != "no_records" for x in coverage["missing"])): reject("invalid_request")
    if coverage["status"] == "complete_empty" and (response["items"] or coverage["days_with_values"] or response.get("packet", {}).get("facts")): reject("invalid_request")
    if response["source_descriptor_count"] < len(response["source_descriptors"]) or response["source_descriptors_truncated"] != (response["source_descriptor_count"] > len(response["source_descriptors"])): reject("invalid_request")
    rows = {x["metric_id"]: x for x in catalog["metrics"]}
    def walk(value):
        if isinstance(value, dict):
            if value.get("type") == "metric":
                value_checks(value, rows)
                if value["metric_id"] not in request["selection"]["metric_ids"]: reject("binding_changed")
            if value.get("type") == "session":
                op = response["operation"]
                if op == "workout_listing" and value["kind"] != "workout" or op == "sleep_session_listing" and value["kind"] != "sleep": reject("invalid_request")
                duration = exact_ns(value["end"]) - exact_ns(value["start"])
                if duration < 0 or duration != int(value["duration_nanoseconds"]): reject("invalid_request")
                if value["identity"]["identity_kind"] == "derived_child" and not value["identity"].get("parent_record_id"): reject("invalid_request")
                for stage in value["stages"]:
                    if not exact_ns(value["start"]) <= exact_ns(stage["start"]) <= exact_ns(stage["end"]) <= exact_ns(value["end"]): reject("invalid_request")
            if value.get("type") == "alignment":
                if value["workout"]["kind"] != "workout" or "sleep" in value and value["sleep"]["kind"] != "sleep": reject("invalid_request")
                if "sleep" in value:
                    gap = exact_ns(value["sleep"]["start"]) - exact_ns(value["workout"]["end"])
                    if gap < 0 or gap != int(value["gap_nanoseconds"]): reject("invalid_request")
            if value.get("type") == "comparison":
                for key in ("first", "second"):
                    if value[key]["metric_id"] != value["metric_id"] or value[key]["unit"] != value["unit"] or value[key]["statistic"] != value["statistic"]: reject("invalid_request")
                available = all(value[k]["availability"] == "available" for k in ("first", "second"))
                if available != ("delta" in value): reject("invalid_request")
                if available and all(value[k]["value"]["type"] == "integer" for k in ("first", "second")):
                    delta = value["second"]["value"]["value"] - value["first"]["value"]["value"]
                    if value["delta"] != {"type": "integer", "value": delta}: reject("invalid_request")
            if "epoch_second" in value and "nanosecond" in value:
                time_checks(value)
                expected_precision = {"apple_health": "source_binary64_seconds", "health_connect": "source_nanoseconds"}.get(request["source_id"])
                if expected_precision and value["precision"] != expected_precision: reject("invalid_request")
            if "identity" in value:
                identity = value["identity"]; native_identity_checks(identity)
                if "not_captured" in identity["metadata_status"].values() and response["coverage"]["status"] in ("complete", "complete_empty"): reject("invalid_request")
                if identity["source_id"] != request["source_id"] or identity["provider_id"] != request["provider_id"]: reject("binding_changed")
                native_type = identity.get("parent_record_type") if identity["identity_kind"] == "derived_child" else identity["record_type"]
                expected_types = {rows[mid].get("native_record_type") for mid in request["selection"]["metric_ids"]}
                if native_type not in expected_types: reject("unsupported_metric")
                if identity["source_id"] == "apple_health" and any(value[t]["precision"] != "source_binary64_seconds" for t in ("start", "end") if t in value): reject("invalid_request")
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    walk(response)
    if not request["include_evidence_values"] and any(x.get("type") == "evidence" for x in response["items"]): reject("approval_required")

READ_CONTROL_VERBS = {"list", "get", "inspect", "inspect_pending"}

def control_right(domain, verb):
    read = verb in READ_CONTROL_VERBS or verb == "plan"
    if domain == "local_recipe": return "recipe_read" if read else "recipe_run" if verb == "run" else "recipe_mutate"
    if domain == "host_schedule": return "host_schedule_read" if read else "host_schedule_run" if verb == "run_now" else "host_schedule_mutate"
    return "native_configuration_read" if read else "native_schedule_mutate" if domain == "native_schedule" else "native_configuration_mutate"

def control_proposal(operation):
    return {k: copy.deepcopy(operation[k]) for k in ("domain", "verb", "object_id", "expected_revision", "value", "pending_binding_sha256") if k in operation}

def control_binding(plan):
    return {k: copy.deepcopy(plan[k]) for k in ("plan_id", "peer", "plan_sha256", "proposal_sha256", "scope_sha256", "capability_sha256", "revisions", "expires_at")}

def endpoint_checks(target):
    if target.get("type") != "endpoint_disclosure": return
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?", target["host"]): reject("invalid_request")
    if not target["path"].startswith("/") or target["path"].startswith("//") or any(c in target["path"] for c in "%?#@\\\\") or any(ord(c) < 33 for c in target["path"]): reject("invalid_request")
    if any(p in (".", "..") for p in target["path"].split("/")): reject("invalid_request")
    if target["disclosure_sha256"] != digest({k: v for k, v in target.items() if k != "disclosure_sha256"}): reject("binding_changed")

def control_value_checks(proposal, peer, root):
    domain = proposal["domain"]; value = proposal.get("value")
    if value is None: return
    if domain == "local_recipe":
        intent_checks(value["intent"], root)
        if value["intent"]["peer"] != peer: reject("binding_changed")
    if domain == "native_profile":
        settings(value["settings"], peer["platform"])
        resolve_selection(value["capture_scope"]["selection"], peer["platform"], registry(root))
        archive = value["capture_scope"]["native_archive"]
        if archive["type"].startswith("apple") and peer["platform"] != "apple" or archive["type"].startswith("android") and peer["platform"] != "android": reject("unsupported_capability")
    if domain in ("host_schedule", "native_schedule"):
        try: ZoneInfo(value["calendar_timezone"])
        except (ZoneInfoNotFoundError, ValueError): reject("invalid_request")
        if domain == "host_schedule" and value["destination"]["host_installation_id"] != peer["host_installation_id"]: reject("binding_changed")
    endpoint_checks(value if domain == "native_destination" else value.get("destination", {}))

def control_plan_checks(plan, root):
    proposal = plan["proposal"]; control_value_checks(proposal, plan["peer"], root)
    if plan["required_right"] != control_right(proposal["domain"], proposal["verb"]): reject("binding_changed")
    if plan["proposal_sha256"] != digest(proposal): reject("binding_changed")
    scope = {k: plan[k] for k in ("peer", "proposal", "revisions")}
    if plan["scope_sha256"] != digest(scope) or plan["plan_sha256"] != digest({k: v for k, v in plan.items() if k != "plan_sha256"}): reject("binding_changed")
    if not 0 < (instant(plan["expires_at"]) - instant(plan["issued_at"])).total_seconds() <= 600: reject("plan_expired")
    revisions = plan["revisions"]
    if len({(r["domain"], r["object_id"]) for r in revisions}) != len(revisions): reject("invalid_request")
    if revisions != sorted(revisions, key=lambda r: (r["domain"], r["object_id"])): reject("invalid_request")
    target = [r for r in revisions if r["domain"] == proposal["domain"] and r["object_id"] == proposal["object_id"]]
    if proposal["expected_revision"]:
        if len(target) != 1 or target[0]["revision"] != proposal["expected_revision"]: reject("revision_conflict")
    elif target: reject("revision_conflict")
    value = proposal.get("value", {})
    dependencies = []
    if proposal["domain"] in ("host_schedule", "native_schedule") and value:
        dependencies.append(("local_recipe" if proposal["domain"] == "host_schedule" else "native_profile", value["recipe_or_profile_id"], value["recipe_or_profile_revision"]))
    destination = value if proposal["domain"] == "native_destination" else value.get("destination", {})
    if destination.get("type") == "existing_native_binding": dependencies.append(("native_destination", destination["binding_id"], destination["expected_revision"]))
    if destination.get("type") == "endpoint_disclosure": dependencies.append(("native_credential_reference", destination["credential_reference_id"], None))
    for domain, object_id, revision in dependencies:
        pins = [r for r in revisions if r["domain"] == domain and r["object_id"] == object_id]
        if len(pins) != 1 or revision is not None and pins[0]["revision"] != revision: reject("revision_conflict")
    if destination.get("type") == "requires_native_rebind" and "native_destination_rebind" not in plan["required_actions"]: reject("native_rebind_required")

def control_capability_checks(peer, capability_sha256, proposal, context):
    capabilities = context["capabilities"]; discovery_checks(capabilities)
    if peer != capabilities["peer"] or capability_sha256 != capabilities["capability_sha256"]: reject("binding_changed")
    if instant(capabilities["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    if "control_plan" not in capabilities["features"] or proposal["domain"] + "." + proposal["verb"] not in capabilities["control_operations"]: reject("unsupported_capability")
    feature = {"native_profile": "native_profile_control", "native_schedule": "native_schedule_control", "native_destination": "native_destination_control"}.get(proposal["domain"])
    if feature and feature not in capabilities["features"]: reject("unsupported_capability")

def control_inspection_scope(authority, operation):
    scope = authority.get("control_read_scope")
    if scope is None: reject("approval_required")
    pairs = [(r["domain"], r["object_id"]) for r in scope["objects"]]
    if pairs != sorted(set(pairs)): reject("invalid_request")
    for key in ("list_domains", "create_domains"): sorted_ids(scope[key])
    if authority["scope_sha256"] != digest(scope): reject("binding_changed")
    domain, verb = operation["domain"], operation["verb"]
    if verb == "list": allowed = domain in scope["list_domains"]
    elif verb == "create": allowed = domain in scope["create_domains"]
    else: allowed = (domain, operation["object_id"]) in pairs
    if not allowed: reject("approval_required")
    return digest(scope)

def control_plan_request_checks(request, context, root):
    proposal = request["proposal"]; control_value_checks(proposal, request["peer"], root)
    control_capability_checks(request["peer"], request["capability_sha256"], proposal, context)
    authority = context["planning_authority"]
    if request["authority_id"] != authority["authority_id"] or request["authority_id"] not in context["stored_planning_authority_ids"]: reject("approval_required")
    if proposal["domain"].startswith("native_"):
        references = context["capabilities"]["authority_references"]
        if not any(r["authority_id"] == authority["authority_id"] and r["grant_revision"] == authority["grant_revision"] and r["grant_sha256"] == digest(authority) for r in references): reject("approval_required")
    # Inspection scope is a pre-existing stored grant; it is NOT the candidate mutation scope.
    require_authority(authority, control_right(proposal["domain"], "plan"), request["peer"], control_inspection_scope(authority, proposal), None, context["now"])
    if proposal["expected_revision"] != context["current_revision"]: reject("revision_conflict")

def control_approval_checks(approved, plan, context):
    if approved["binding"] != control_binding(plan) or approved["right"] != plan["required_right"]: reject("binding_changed")
    if approved["authority_id"] != context["authority"]["authority_id"]: reject("approval_required")
    if context.get("issued_control_approvals", {}).get(approved["approval_id"]) != digest(approved): reject("approval_required")
    if not instant(plan["issued_at"]) <= instant(approved["approved_at"]) <= instant(context["now"]): reject("approval_required")
    require_authority(context["authority"], plan["required_right"], plan["peer"], plan["scope_sha256"], None, context["now"])
    if approved["authority_reference"] != authority_reference(context["authority"]): reject("approval_required")

def control_current_checks(plan, context):
    if context.get("issued_control_plans", {}).get(plan["plan_id"]) != plan["plan_sha256"]: reject("binding_changed")
    if instant(plan["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    if plan["proposal"]["expected_revision"] != context["current_revision"] or plan["revisions"] != context["current_revisions"]: reject("revision_conflict")
    control_capability_checks(plan["peer"], plan["capability_sha256"], plan["proposal"], context)
    if plan["required_actions"] or context.get("import_blocked"): reject("native_rebind_required")
    if context.get("last_profile") and plan["proposal"]["domain"] == "native_profile" and plan["proposal"]["verb"] == "delete": reject("invalid_request")
    if plan["proposal"]["verb"] == "discard_pending" and plan["proposal"]["pending_binding_sha256"] != context.get("pending_binding_sha256"): reject("binding_changed")

def control_request_checks(request, context, root):
    op = request["operation"]; domain, verb = op["domain"], op["verb"]
    if verb == "plan":
        if op["proposal"]["domain"] != domain: reject("binding_changed")
        normalized = {k: op[k] for k in ("request_id", "authority_id", "peer", "capability_sha256", "proposal")}
        control_plan_request_checks(normalized, context, root); return
    if verb in READ_CONTROL_VERBS:
        authority = context["planning_authority"]
        if op["authority_id"] != authority["authority_id"] or op["authority_id"] not in context["stored_planning_authority_ids"]: reject("approval_required")
        require_authority(authority, control_right(domain, verb), op["peer"], control_inspection_scope(authority, op), None, context["now"])
        if op.get("expected_revision", 0) != context["current_revision"]: reject("revision_conflict")
        return
    plan = op["plan"]; approved = op["approval"]; control_plan_checks(plan, root)
    if control_proposal(op) != plan["proposal"] or op["peer"] != plan["peer"] or op["authority_id"] != approved["authority_id"]: reject("binding_changed")
    if approved["binding"] != control_binding(plan) or context["peer"] != op["peer"]: reject("binding_changed")
    previous = context.get("existing_control_request_sha256")
    if previous:
        if previous != digest(request): reject("binding_changed")
        return # Stored receipt only; no mutation, even after expiry/revision advance.
    if instant(plan["expires_at"]) <= instant(context["now"]): reject("plan_expired")
    control_approval_checks(approved, plan, context)
    control_current_checks(plan, context)

def projection_scope_hash(request): return digest({k: v for k, v in request.items() if k != "request_id"})

def observation_checks(item, request, fields, coverage):
    row = fields.get(item["field_id"])
    if not row or row["object_id"] != "selected_series" or item["field_id"] not in request["field_ids"]: reject("binding_changed")
    for key in ("selection_metric_id", "native_value_key", "unit"):
        if item[key] != row[key]: reject("binding_changed")
    if item["observation_kind"] != row["value_role"] or item["identity"]["record_type"] != row["native_record_type"]: reject("binding_changed")
    identity = item["identity"]; native_identity_checks(identity)
    if identity["source_id"] != request["source_id"] or identity["provider_id"] != request["provider_id"]: reject("binding_changed")
    if identity.get("parent_record_type") != row.get("parent_record_type"): reject("binding_changed")
    if "not_captured" in identity["metadata_status"].values() and coverage["status"] in ("complete", "complete_empty"): reject("invalid_request")
    time_checks(item["start"])
    if item["start"]["precision"] != "source_nanoseconds": reject("invalid_request")
    if item["observation_kind"] == "point":
        if "end" in item: reject("invalid_request") # SDK point time is not a fabricated zero-length interval.
    else:
        if "end" not in item: reject("invalid_request")
        time_checks(item["end"])
        if item["end"]["precision"] != "source_nanoseconds" or exact_ns(item["end"]) <= exact_ns(item["start"]): reject("invalid_request")
    if item["owner_date"] != datetime.fromtimestamp(item["start"]["epoch_second"], timezone.utc).astimezone(ZoneInfo(request["calendar_timezone"])).date().isoformat(): reject("binding_changed")
    if item["observation_id"] != digest({k: v for k, v in item.items() if k != "observation_id"}): reject("binding_changed")

def projection_checks(value, request=None, catalog=None, field_catalog=None):
    fields = {row["field_id"]: row for row in (field_catalog or projection_catalog())["fields"]}
    if value["peer"]["platform"] != "android": reject("invalid_request")
    if value["detail"] == "summary" and (value["selected_series"] or value["native_records"]): reject("approval_required")
    if value["detail"] != "native_records" and value["native_records"]: reject("approval_required")
    if request:
        projection_request_checks(request, field_catalog)
        for key in ("peer", "source_id", "provider_id", "request_id", "calendar_timezone", "catalog_sha256", "projection_catalog_sha256", "detail"):
            if value[key] != request[key]: reject("binding_changed")
        if value["scope_sha256"] != projection_scope_hash(request): reject("binding_changed")
        selected = dates(request["dates"], request["calendar_timezone"])
        if selected["type"] == "exact" and not selected["range"]["start_date"] <= value["owner_date"] <= selected["range"]["end_date"]: reject("binding_changed")
        if value["coverage"]["status"] not in ("complete", "complete_empty") and not request["allow_partial"]: reject("approval_required")
        for key, object_id in (("summary", "daily_summary"), ("selected_series", "selected_series"), ("native_records", "native_records")):
            if value[key] and object_id not in request["object_ids"]: reject("binding_changed")
        for item in value["summary"]:
            if item["metric_id"] not in request["field_ids"] or fields[item["metric_id"]]["object_id"] != "daily_summary" or item["owner_date"] != value["owner_date"]: reject("binding_changed")
            if catalog: value_checks(item, {r["metric_id"]: r for r in catalog["metrics"]})
        if len({x["observation_id"] for x in value["selected_series"]}) != len(value["selected_series"]): reject("invalid_request")
        for item in value["selected_series"]:
            if item["owner_date"] != value["owner_date"]: reject("binding_changed")
            observation_checks(item, request, fields, value["coverage"])
        for evidence in value["native_records"]:
            allowed = {fields[f]["selection_metric_id"] for f in request["field_ids"] if fields[f]["object_id"] == "native_records" and fields[f]["native_record_type"] == evidence["identity"]["record_type"]}
            if not set(evidence["metric_ids"]) <= allowed: reject("binding_changed")
            for item in evidence["values"]:
                if item["metric_id"] not in allowed or item["owner_date"] != value["owner_date"]: reject("binding_changed")
                if catalog: value_checks(item, {r["metric_id"]: r for r in catalog["metrics"]})
        for evidence in value["native_records"]:
            native_identity_checks(evidence["identity"])
            if "not_captured" in evidence["identity"]["metadata_status"].values() and value["coverage"]["status"] in ("complete", "complete_empty"): reject("invalid_request")
            if catalog:
                identity = evidence["identity"]
                native_type = identity.get("parent_record_type") if identity["identity_kind"] == "derived_child" else identity["record_type"]
                expected_types = {r.get("native_record_type") for r in catalog["metrics"] if r["metric_id"] in request["selection"]["metric_ids"]}
                if native_type not in expected_types: reject("unsupported_metric")
            for key in ("start", "end"):
                time_checks(evidence[key])
                if value["source_id"] == "health_connect" and evidence[key]["precision"] != "source_nanoseconds": reject("invalid_request")
            if evidence["identity"]["source_id"] != value["source_id"] or evidence["identity"]["provider_id"] != value["provider_id"] or not set(evidence["metric_ids"]) <= set(request["selection"]["metric_ids"]): reject("binding_changed")
    coverage = value["coverage"]
    if coverage["status"] in ("complete", "complete_empty") and coverage["history"]["state"] == "unverified": reject("invalid_request")
    if coverage["status"] == "complete_empty" and (value["summary"] or value["selected_series"] or value["native_records"] or coverage["days_with_values"]): reject("invalid_request")

def projection_job_checks(job):
    execute = job["execute"]; plan = execute["plan"]
    if not is_projection(plan["intent"]) or job["job_id"] != execute["job_id"] or job["request_sha256"] != digest(execute): reject("binding_changed")
    if instant(job["expires_at"]) - instant(job["accepted_at"]) != timedelta(days=7): reject("invalid_request")
    request = plan["intent"]["product"]["request"]
    projection_request_checks(request, job["projection_catalog"])
    if digest(job["source_catalog"]) != request["catalog_sha256"]: reject("binding_changed")
    if job["source_catalog"]["peer"] != plan["intent"]["peer"]: reject("binding_changed")
    if job["state"] == "accepted" and (job["capture_started"] or "spool_sha256" in job or "manifest_sha256" in job): reject("invalid_request")
    if job["state"] in ("spooled", "transferring", "complete") and (not job["capture_started"] or "spool_sha256" not in job or "manifest_sha256" not in job): reject("invalid_request")
    if plan["resolved_dates"]["type"] != "all_available" and job["resolved_dates"] != plan["resolved_dates"]: reject("binding_changed")

def projection_manifest_binding(manifest, context):
    job = context.get("projection_job")
    if not job: return
    projection_job_checks(job); execute = job["execute"]; plan = execute["plan"]; output = plan["effective_projection_output"]
    if manifest["job_id"] != job["job_id"] or manifest["request_sha256"] != job["request_sha256"] or manifest["binding"] != binding(plan): reject("binding_changed")
    request = plan["intent"]["product"]["request"]
    expected_branches = sorted(["object." + x for x in request["object_ids"]] + ["field." + x for x in request["field_ids"]])
    if sorted(x["selector_id"] for x in manifest["branch_statuses"]) != expected_branches: reject("binding_changed")
    if "spool_sha256" in job and job["spool_sha256"] != digest(sorted([{k: a[k] for k in ("artifact_id", "sha256", "byte_count")} for a in manifest["artifacts"]], key=lambda a: a["artifact_id"])): reject("binding_changed")
    if context["projection_request"] != plan["intent"]["product"]["request"] or context["catalog"] != job["source_catalog"] or context.get("journal_projection_catalog") != job["projection_catalog"]: reject("binding_changed")
    resolved_intent = copy.deepcopy(plan["intent"]); resolved_intent["dates"] = job["resolved_dates"]
    paths = projection_paths(resolved_intent, output)
    for artifact in manifest["artifacts"]:
        if any(artifact[key] != output[key] for key in ("profile", "media_type", "write_mode")) or artifact["relative_path"] not in paths: reject("binding_changed")
        for document in context.get("artifact_documents", {}).get(artifact["artifact_id"], []):
            one_day = copy.deepcopy(resolved_intent); one_day["dates"] = {"type": "exact", "range": {"start_date": document["owner_date"], "end_date": document["owner_date"]}}
            if artifact["relative_path"] not in projection_paths(one_day, output): reject("binding_changed")

def projection_transfer_checks(value, context, schema_validator):
    job = context["projection_job"]; projection_job_checks(job)
    if instant(context.get("now", job["accepted_at"])) >= instant(job["expires_at"]): reject("job_expired")
    if context.get("trust_revoked") or context.get("native_grants_revoked"): reject("permission_required")
    if "spool_sha256" not in job or context.get("spool_present") is False: reject("spool_missing_restart_required")
    manifest = value["manifest"]; projection_manifest_binding(manifest, context)
    if digest(manifest) != job["manifest_sha256"]: reject("binding_changed")
    session = value["transfer_session"]; artifact = manifest["artifacts"][0]; base = value["base_artifact_manifest"]
    if set(session) != {"session_id", "job_id", "request_fingerprint", "peer_binding", "partition_target_bytes", "created_at"}: reject("invalid_request")
    expected_peer = {key: job["execute"]["plan"]["intent"]["peer"][key] for key in ("source_installation_id", "host_installation_id")}
    if session["job_id"] != job["job_id"] or session["request_fingerprint"] != job["request_sha256"] or session["peer_binding"] != expected_peer: reject("binding_changed")
    expected = {"job_id": job["job_id"], "artifact_id": artifact["artifact_id"], "kind": "generated_file", "schema": {"id": "healthmd.source_data_projection", "major": 1},
        **{k: artifact[k] for k in ("media_type", "byte_count", "sha256", "relative_path", "write_mode")}, "provider_id": "health_connect"}
    if base != expected: reject("binding_changed")
    resume = value["resume"]; schema_check(resume, "agent", schema_validator)
    if resume != context["journal_resume"] or resume["job_id"] != job["job_id"] or resume["request_sha256"] != job["request_sha256"] or resume["manifest_sha256"] != job["manifest_sha256"] or resume["binding"] != binding(job["execute"]["plan"]): reject("binding_changed")
    for artifact in manifest["artifacts"]: projection_artifact_checks(artifact, context["artifact_documents"][artifact["artifact_id"]], context, schema_validator)

def projection_artifact_checks(artifact, documents, context, schema_validator):
    if artifact["profile"] != "android-source-projection-v1": reject("invalid_request")
    if not documents or artifact["media_type"] == "application/json" and len(documents) != 1: reject("invalid_request")
    for document in documents:
        schema_check(document, "query", schema_validator)
        if document.get("schema") != "healthmd.source_data_projection": reject("invalid_request")
        projection_checks(document, context["projection_request"], context["catalog"], context.get("journal_projection_catalog"))
    if [d["owner_date"] for d in documents] != sorted({d["owner_date"] for d in documents}): reject("invalid_request")
    encoded = b"".join(canonical(d) + b"\n" for d in documents)
    if artifact["byte_count"] != len(encoded) or artifact["sha256"] != hashlib.sha256(encoded).hexdigest(): reject("binding_changed")

def validate_case(case, root, schema_validator):
    family = case["family"]; value = case["value"]; context = case.get("context", {})
    if family in ("agent", "query", "wire"): schema_check(value, family, schema_validator)
    if family == "wire":
        if 4 not in context["host_versions"] or 4 not in context["source_versions"]: reject("unsupported_capability")
        value = value["payload"]
        # Host recipe/schedule stores consume the same DTOs locally, not as mobile RPC.
        if value.get("schema") in ("healthmd.agent_control_request", "healthmd.agent_control_plan_request"):
            operation = value.get("operation", value.get("proposal", {}))
            if operation.get("domain") in ("local_recipe", "host_schedule"): reject("unsupported_capability")
    schema = value.get("schema") if isinstance(value, dict) else None
    if family == "path": safe_path(value, templates=context.get("templates", False), filename=context.get("filename", False)); return
    if family == "collision": collisions(value); return
    if family == "cursor": cursor_verify(value, bytes.fromhex(context["synthetic_key_hex"]), context["expected"], context["now"]); return
    if family == "authority": require_authority(value, context["right"], context["peer"], context["scope_sha256"], context.get("destination"), context["now"]); return
    if family == "resume":
        schema_check(value, "agent", schema_validator)
        if value != context["journal_resume"]: reject("binding_changed")
        return
    if family == "projection_transfer":
        preflight(value); projection_transfer_checks(value, context, schema_validator); return
    if family == "control": schema_check(value, "agent", schema_validator)
    if schema == "healthmd.agent_discovery": discovery_checks(value)
    elif schema == "healthmd.agent_export_delegation": delegation_checks(value)
    elif schema == "healthmd.agent_plan_request": export_plan_request_checks(value, context, root)
    elif schema == "healthmd.agent_approval_request": export_approval_request_checks(value, context, root)
    elif schema == "healthmd.agent_control_request": control_request_checks(value, context, root)
    elif schema == "healthmd.agent_control_plan_request": control_plan_request_checks(value, context, root)
    elif schema == "healthmd.agent_control_plan": control_plan_checks(value, root)
    elif schema in ("healthmd.agent_control_approval_request", "healthmd.agent_control_approval"):
        plan = context["control_plan"]; control_plan_checks(plan, root)
        if value["binding"] != control_binding(plan) or value.get("authority_id", context["authority"]["authority_id"]) != context["authority"]["authority_id"]: reject("binding_changed")
        require_authority(context["authority"], plan["required_right"], plan["peer"], plan["scope_sha256"], None, context["now"])
        control_current_checks(plan, context)
        if schema == "healthmd.agent_control_approval_request":
            if context.get("native_or_host_decision_binding_sha256") != digest(control_binding(plan)): reject("approval_required")
        else: control_approval_checks(value, plan, context)
    elif schema == "healthmd.agent_control_receipt":
        request = context.get("control_request")
        if request and request["operation"]["verb"] not in READ_CONTROL_VERBS | {"plan"} and "mutation_binding" not in value: reject("invalid_request")
        if "mutation_binding" in value:
            if not request: reject("invalid_request")
            op = request["operation"]; receipt_binding = value["mutation_binding"]
            if receipt_binding != {"binding": control_binding(op["plan"]), "approval_id": op["approval"]["approval_id"], "request_sha256": digest(request)}: reject("binding_changed")
            if any(value[k] != op[k] for k in ("request_id", "domain", "object_id")): reject("binding_changed")
            if value["status"] == "success":
                if value["previous_revision"] != op["expected_revision"] or value["revision"] != op["expected_revision"] + 1: reject("revision_conflict")
                if "value" in op and value["value_sha256"] != digest(op["value"]): reject("binding_changed")
    elif schema == "healthmd.agent_export_intent": intent_checks(value, root)
    elif schema == "healthmd.agent_export_plan": plan_checks(value, root)
    elif schema == "healthmd.agent_execute_request": execute_checks(value, context, root)
    elif schema == "healthmd.agent_projection_job": projection_job_checks(value)
    elif schema == "healthmd.agent_artifact_manifest":
        projection_manifest_binding(value, context)
        collisions([a["relative_path"] for a in value["artifacts"]])
        for artifact in value["artifacts"]:
            documents = context.get("artifact_documents", {}).get(artifact["artifact_id"])
            if artifact["profile"] == "android-source-projection-v1" and value["binding"]["peer"]["platform"] != "android": reject("invalid_request")
            if documents is not None: projection_artifact_checks(artifact, documents, context, schema_validator)
        if value["capture_status"] in ("complete", "complete_empty") and any(x["status"] != "success" for x in value["branch_statuses"]): reject("invalid_request")
        if value["capture_status"] == "complete_empty" and value["artifacts"]: reject("invalid_request")
    elif schema == "healthmd.agent_commit_receipt":
        safe_path(value["relative_path"])
        fields = {k: value[k] for k in ("job_id", "artifact_id", "destination", "request_sha256", "manifest_sha256", "relative_path", "write_mode", "input_sha256", "before_sha256", "after_sha256")}
        if value["commit_key"] != digest(fields): reject("binding_changed")
        if "persisted_commit" in context and fields != {k: context["persisted_commit"][k] for k in fields}: reject("binding_changed")
    elif schema == "healthmd.profile_dictionary":
        versions = {"apple-v8": ("apple", 8), "android-frozen-v4": ("android", 4), "android-analytical-v5": ("android", 5)}
        if versions[value["profile"]] != (value["platform"], value["source_schema_version"]): reject("invalid_request")
        rows = registry(root)
        if len({x["field_id"] for x in value["entries"]}) != len(value["entries"]): reject("invalid_request")
        for item in value["entries"]:
            if item["semantic_id"] not in rows or item["registry_equivalence"] != rows[item["semantic_id"]]["equivalence"]: reject("unsupported_metric")
            mapping = rows[item["semantic_id"]][value["platform"]]
            if mapping.get("selection_id") != item["native_selection_id"]: reject("unsupported_metric")
    elif schema == "healthmd.agent_execution_receipt":
        if value["status"] in ("complete", "complete_empty", "cancelled") and not value["source_acknowledged"]: reject("invalid_request")
    elif schema == "healthmd.source_query_catalog": catalog_checks(value)
    elif schema == "healthmd.source_query_request":
        catalog_checks(context["catalog"])
        query_checks(value, context["catalog"], context["authority"], context["now"])
    elif schema == "healthmd.source_query_response": response_checks(value, context["request"], context["catalog"])
    elif schema == "healthmd.source_projection_request": projection_request_checks(value)
    elif schema == "healthmd.source_projection_catalog":
        if value != projection_catalog(): reject("invalid_request")
    elif schema == "healthmd.source_data_projection": projection_checks(value, context.get("projection_request"), context.get("catalog"))

def validate_asset(root, path, schema_validator, fail):
    if path.name == "conformance.json":
        return validate_fixture(root, path, schema_validator, fail)
    value = json.loads(path.read_text(encoding="utf-8"))
    if path.name == "reviewed-projection-catalog.json":
        try: schema_check(value, "query", schema_validator)
        except Invalid: fail("agent bridge: invalid projection catalog grammar")
        if value["implementation_state"] != "planned" or value["contains_health_values"] is not False: fail("agent bridge: projection catalog promotes availability")
        if len({f["field_id"] for f in value["fields"]}) != len(value["fields"]): fail("agent bridge: duplicate projection field")
        rows = registry(root)
        if any(f["selection_metric_id"] not in rows or not f["native_record_type"].startswith("androidx.health.connect.client.records.") for f in value["fields"]): fail("agent bridge: invalid projection field mapping")
        return
    if path.name == "reviewed-query-catalog.json":
        try: schema_check(value, "query", schema_validator)
        except Invalid: fail("agent bridge: invalid reviewed catalog grammar")
        try: catalog_checks(value)
        except Invalid: fail("agent bridge: invalid reviewed native type identifiers")
        rows = registry(root)
        for row in value["metrics"]:
            if row["availability"] not in ("planned", "unavailable") or row["metric_id"] not in rows or row["registry_equivalence"] != rows[row["metric_id"]]["equivalence"]:
                fail("agent bridge: reviewed catalog claims unreviewed support")
        if value["sdk_version"] != "1.2.0-alpha02" or value["provider_availability"] != "unverified": fail("agent bridge: invalid SDK/provider evidence")
        return
    if not path.name.endswith(".schema.json") or value.get("$schema") != "https://json-schema.org/draft/2020-12/schema": fail("agent bridge: unknown schema asset")
    keywords = {"$schema", "$id", "$defs", "$ref", "oneOf", "type", "properties", "required", "additionalProperties", "const", "enum", "minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems", "uniqueItems", "pattern", "format"}
    def walk(node):
        if not isinstance(node, dict) or not set(node) <= keywords: fail("agent bridge: unsupported schema keyword")
        if "$ref" in node:
            reference = node["$ref"]
            if not reference.startswith("#/$defs/") or reference[8:] not in value["$defs"]: fail("agent bridge: unresolved schema reference")
        if node.get("type") == "object" and node.get("additionalProperties") is not False: fail("agent bridge: object grammar must be closed")
        if node.get("type") == "array" and "maxItems" not in node: fail("agent bridge: array grammar must be bounded")
        for child in node.get("properties", {}).values(): walk(child)
        for child in node.get("$defs", {}).values(): walk(child)
        for child in node.get("oneOf", []): walk(child)
        if "items" in node: walk(node["items"])
    keywords.add("items")
    walk(value)

def validate_fixture(root, path, schema_validator, fail):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload["schema"] != "healthmd.agent_bridge_test_vectors" or type(payload["schema_version"]) is not int or payload["schema_version"] != 1:
        fail("agent bridge: invalid fixture identity")
    ids = set()
    for case in payload["cases"]:
        if case["id"] in ids: fail("agent bridge: duplicate case id")
        ids.add(case["id"])
        try:
            validate_case(case, root, schema_validator)
            outcome = "valid"
        except Invalid as error:
            outcome = str(error)
        if outcome != case["expected"]: fail("agent bridge: fixture outcome mismatch: " + case["id"] + " / " + outcome)
    # Exact canonical bytes/digests are independently consumable by future native tests.
    for vector in payload.get("canonical_vectors", []):
        encoded = canonical(vector["value"])
        if base64.b64encode(encoded).decode() != vector["canonical_base64"] or hashlib.sha256(encoded).hexdigest() != vector["sha256"]:
            fail("agent bridge: canonical vector mismatch")
