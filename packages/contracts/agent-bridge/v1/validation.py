"""Executable synthetic conformance oracle, NOT a native authorizer/query engine.

The existing contract validator is passed in; none of its historical semantics change.
Errors contain fixed codes only, never rejected payloads.
"""
import base64
import copy
import hashlib
import hmac
import json
import re
import unicodedata
from datetime import datetime, timedelta
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
    for key in ("features", "settings_policies", "output_profiles", "query_operations", "control_operations"): sorted_ids(discovery[key])
    for key in ("formats", "write_modes", "compatibility_detail", "native_archive_products", "setting_pointers", "path_tokens"): sorted_ids(discovery["output_support"][key])
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
    policy = value["settings_policy"]
    if policy["type"] == "explicit": settings(policy["settings"], value["peer"]["platform"])
    return metrics

def leaves(value, prefix=""):
    if isinstance(value, dict):
        for key, child in value.items(): yield from leaves(child, prefix + "/" + key)
    else: yield prefix

def plan_checks(plan, root):
    metrics = intent_checks(plan["intent"], root)
    effective = plan["effective_settings"]
    settings(effective, plan["intent"]["peer"]["platform"])
    if plan["resolved_metric_ids"] != metrics: reject("binding_changed")
    if effective["individual_entries"]["enabled"]:
        if not effective["individual_entries"]["metric_ids"] or not set(effective["individual_entries"]["metric_ids"]) <= set(metrics): reject("binding_changed")
        if plan["intent"]["capture_scope"]["native_archive"]["type"] == "none": reject("unsupported_capability")
    if plan["resolved_dates"] != dates(plan["intent"]["dates"], plan["intent"]["calendar_timezone"]): reject("binding_changed")
    if plan["settings_sha256"] != digest(effective): reject("binding_changed")
    if plan["scope_sha256"] != digest({"dates": plan["resolved_dates"], "calendar_timezone": plan["intent"]["calendar_timezone"], "capture_scope": plan["intent"]["capture_scope"], "metric_ids": metrics}): reject("binding_changed")
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
    return {"peer": plan["intent"]["peer"], "destination": plan["intent"]["destination"], **{k: plan[k] for k in ("plan_sha256", "settings_sha256", "scope_sha256", "capability_sha256", "revisions", "expires_at")}}

def require_authority(authority, right, peer, scope, destination, now):
    if right not in authority["rights"]: reject("approval_required")
    if authority["peer"] != peer or authority["scope_sha256"] != scope: reject("binding_changed")
    if instant(authority["expires_at"]) <= instant(now): reject("approval_required")
    if destination and destination["binding_id"] not in authority["destination_binding_ids"]: reject("approval_required")
    if right in ("native_configuration_mutate", "native_schedule_mutate"):
        if authority["configuration_protection"] != "unlocked_native": reject("configuration_protected")
    if right in ("export_execute", "native_configuration_mutate", "native_schedule_mutate", "host_schedule_run"):
        if authority["native_consent"] != "satisfied": reject("permission_required")
        if authority["entitlement"] != "satisfied": reject("entitlement_required")

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
    settings = plan["effective_settings"]
    if not {"bound_execution", "zero_health_plan"} <= set(capabilities["features"]): reject("unsupported_capability")
    if not set(settings["formats"]) <= set(support["formats"]) or settings["write_mode"] not in support["write_modes"] or settings["output_profile"] not in capabilities["output_profiles"]: reject("unsupported_capability")
    if plan["intent"]["settings_policy"]["type"] not in capabilities["settings_policies"]: reject("unsupported_capability")
    if plan["intent"]["capture_scope"]["native_archive"]["type"] not in support["native_archive_products"] or plan["intent"]["capture_scope"]["compatibility_detail"] not in support["compatibility_detail"]: reject("unsupported_capability")
    if settings["packaging"]["type"] == "zip" and "zip" not in capabilities["features"] or settings["dictionary"]["type"] != "none" and "profile_dictionary" not in capabilities["features"]: reject("unsupported_capability")
    if approved["approval_id"] not in context["issued_approval_ids"] or context["issued_approvals"].get(approved["approval_id"]) != digest(approved) or approved["authority_id"] != context["authority"]["authority_id"]: reject("approval_required")
    if "export_execute" not in approved["rights"]: reject("approval_required")
    require_authority(context["authority"], "export_execute", plan["intent"]["peer"], plan["scope_sha256"], plan["intent"]["destination"], context["now"])
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
                if value["identity"]["identity_kind"] == "derived_child" and not value["identity"]["parent_record_id"]: reject("invalid_request")
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
            if "identity" in value:
                identity = value["identity"]
                if identity["source_id"] != request["source_id"] or identity["provider_id"] != request["provider_id"]: reject("binding_changed")
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    walk(response)
    if not request["include_evidence_values"] and any(x.get("type") == "evidence" for x in response["items"]): reject("approval_required")

def validate_case(case, root, schema_validator):
    family = case["family"]; value = case["value"]; context = case.get("context", {})
    if family in ("agent", "query", "wire"): schema_check(value, family, schema_validator)
    if family == "wire":
        if 4 not in context["host_versions"] or 4 not in context["source_versions"]: reject("unsupported_capability")
        value = value["payload"]
    schema = value.get("schema") if isinstance(value, dict) else None
    if family == "path": safe_path(value, templates=context.get("templates", False), filename=context.get("filename", False)); return
    if family == "collision": collisions(value); return
    if family == "cursor": cursor_verify(value, bytes.fromhex(context["synthetic_key_hex"]), context["expected"], context["now"]); return
    if family == "authority": require_authority(value, context["right"], context["peer"], context["scope_sha256"], context.get("destination"), context["now"]); return
    if family == "resume":
        schema_check(value, "agent", schema_validator)
        if value != context["journal_resume"]: reject("binding_changed")
        return
    if family == "control":
        schema_check(value, "agent", schema_validator)
        op = value["operation"]
        domain, verb = op["domain"], op["verb"]
        read = verb in ("list", "get", "inspect", "plan", "inspect_pending")
        right = "recipe_read" if domain == "local_recipe" and read else "recipe_run" if domain == "local_recipe" and verb == "run" else "recipe_mutate" if domain == "local_recipe" else "host_schedule_read" if domain == "host_schedule" and read else "host_schedule_run" if domain == "host_schedule" and verb == "run_now" else "host_schedule_mutate" if domain == "host_schedule" else "native_configuration_read" if read else "native_schedule_mutate" if domain == "native_schedule" else "native_configuration_mutate"
        require_authority(context["authority"], right, op["peer"], context["scope_sha256"], None, context["now"])
        if op.get("authority_id") != context["authority"]["authority_id"]: reject("approval_required")
        if not read and (op.get("approval_id") not in context["issued_approval_ids"] or context["approved_operation_sha256"] != digest(value)): reject("approval_required")
        if op.get("expected_revision", 0) != context["current_revision"]: reject("revision_conflict")
        if "value" in op:
            value = op["value"]
            if domain == "local_recipe": intent_checks(value["intent"], root)
            if domain == "native_profile": settings(value["settings"], op["peer"]["platform"])
            if domain in ("host_schedule", "native_schedule"):
                try: ZoneInfo(value["calendar_timezone"])
                except (ZoneInfoNotFoundError, ValueError): reject("invalid_request")
            target = value if domain == "native_destination" else value.get("destination", {})
            if target.get("type") == "endpoint_disclosure":
                if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?", target["host"]): reject("invalid_request")
                if not target["path"].startswith("/") or target["path"].startswith("//") or any(c in target["path"] for c in "%?#@\\\\") or any(ord(c) < 33 for c in target["path"]): reject("invalid_request")
                if any(p in (".", "..") for p in target["path"].split("/")): reject("invalid_request")
        if context.get("import_blocked"): reject("native_rebind_required")
        if context.get("last_profile") and op["verb"] == "delete": reject("invalid_request")
        return
    if schema == "healthmd.agent_discovery": discovery_checks(value)
    elif schema == "healthmd.agent_export_intent": intent_checks(value, root)
    elif schema == "healthmd.agent_export_plan": plan_checks(value, root)
    elif schema == "healthmd.agent_execute_request": execute_checks(value, context, root)
    elif schema == "healthmd.agent_artifact_manifest":
        collisions([a["relative_path"] for a in value["artifacts"]])
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
    elif schema == "healthmd.source_query_request": query_checks(value, context["catalog"], context["authority"], context["now"])
    elif schema == "healthmd.source_query_response": response_checks(value, context["request"], context["catalog"])
    elif schema == "healthmd.source_projection_request":
        if value["detail"] == "summary" and any(x in value["object_ids"] for x in ("selected_series", "native_records")): reject("approval_required")
        if "native_records" in value["object_ids"] and value["detail"] != "native_records": reject("approval_required")
        if any(x not in context["allowed_field_ids"] for x in value["field_ids"]): reject("unsupported_metric")
    elif schema == "healthmd.source_data_projection":
        if value["detail"] == "summary" and (value["selected_series"] or value["native_records"]): reject("approval_required")

def validate_asset(root, path, schema_validator, fail):
    if path.name == "conformance.json":
        return validate_fixture(root, path, schema_validator, fail)
    value = json.loads(path.read_text(encoding="utf-8"))
    if path.name == "reviewed-query-catalog.json":
        try: schema_check(value, "query", schema_validator)
        except Invalid: fail("agent bridge: invalid reviewed catalog grammar")
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
