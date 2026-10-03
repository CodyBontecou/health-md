"""Executable proposal semantics, NOT a production scheduler or HTTP client."""
from dataclasses import dataclass, replace
from datetime import date, datetime, timedelta
import json
import re
from zoneinfo import ZoneInfo

MAX_DAYS = 30
MAX_RESPONSE_BYTES = 64 * 1024


def civil(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise ValueError("invalid civil date")
    return date.fromisoformat(value)


def exact_object(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ValueError("invalid fields")
    return value


def strict_json(text):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate field")
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=pairs)


@dataclass(frozen=True)
class Request:
    request_id: str
    scope_id: str
    calendar_timezone: str
    candidates: tuple[str, ...]
    today: str

    def __post_init__(self):
        for identifier in (self.request_id, self.scope_id):
            if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", identifier):
                raise ValueError("invalid opaque identifier")
        ZoneInfo(self.calendar_timezone)
        civil(self.today)
        if not isinstance(self.candidates, tuple) or not 1 <= len(self.candidates) <= MAX_DAYS:
            raise ValueError("invalid candidate count")
        if tuple(sorted(set(self.candidates))) != self.candidates:
            raise ValueError("candidates must be sorted and unique")
        for item in self.candidates:
            if civil(item) >= civil(self.today):
                raise ValueError("candidate is not a completed day")
        if (civil(self.candidates[-1]) - civil(self.candidates[0])).days >= MAX_DAYS:
            raise ValueError("window exceeds limit")

    @classmethod
    def at(cls, request_id, scope_id, calendar_timezone, candidates, now):
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("now must be timezone-aware")
        today = now.astimezone(ZoneInfo(calendar_timezone)).date().isoformat()
        return cls(request_id, scope_id, calendar_timezone, tuple(candidates), today)

    def wire(self):
        return {
            "schema": "healthmd.receiver_coverage.request",
            "schema_version": 1,
            "request_id": self.request_id,
            "scope_id": self.scope_id,
            "calendar_timezone": self.calendar_timezone,
            "start": self.candidates[0],
            "end_exclusive": (civil(self.candidates[-1]) + timedelta(days=1)).isoformat(),
        }


def completed_dates(request, response):
    """None means unavailable; any invalid response is unsafe for skipping days."""
    if response is None:
        raise ValueError("receiver unavailable")
    if not isinstance(response, str) or len(response.encode("utf-8")) > MAX_RESPONSE_BYTES:
        raise ValueError("invalid response size")
    value = strict_json(response)
    expected = request.wire()
    expected["schema"] = "healthmd.receiver_coverage.response"
    exact_object(value, {*expected, "completed_dates"})
    if type(value["schema_version"]) is not int:
        raise ValueError("invalid version")
    if any(value[key] != item for key, item in expected.items()):
        raise ValueError("receiver context mismatch")
    days = value["completed_dates"]
    if not isinstance(days, list) or len(days) > MAX_DAYS:
        raise ValueError("invalid completed dates")
    for item in days:
        civil(item)
        if not expected["start"] <= item < expected["end_exclusive"] or item >= request.today:
            raise ValueError("completed date outside request")
    if days != sorted(set(days)):
        raise ValueError("completed dates must be sorted and unique")
    return frozenset(days)


def correction_dates(request, count):
    if not count:
        return set()
    cutoff = civil(request.candidates[-1]) - timedelta(days=count - 1)
    return {day for day in request.candidates if civil(day) >= cutoff}


@dataclass(frozen=True)
class Plan:
    destination_binding: str
    request: Request
    policy: str
    refresh_recent_days: int
    today_refresh: bool
    selected: tuple[str, ...]
    residual: tuple[str, ...]
    coverage_status: str

    def __post_init__(self):
        if not isinstance(self.destination_binding, str) or not re.fullmatch(r"[a-f0-9]{64}", self.destination_binding):
            raise ValueError("invalid destination binding")
        if self.policy not in ("full_lookback", "missing_days"):
            raise ValueError("invalid policy")
        if type(self.refresh_recent_days) is not int or not 0 <= self.refresh_recent_days <= MAX_DAYS:
            raise ValueError("invalid correction window")
        if type(self.today_refresh) is not bool:
            raise ValueError("invalid Today Refresh")
        if self.coverage_status not in ("not_requested", "valid", "fallback_full"):
            raise ValueError("invalid coverage status")
        if (self.policy == "full_lookback") != (self.coverage_status == "not_requested"):
            raise ValueError("inconsistent policy status")
        permitted = set(self.request.candidates) | ({self.request.today} if self.today_refresh else set())
        for days in (self.selected, self.residual):
            if not isinstance(days, tuple) or tuple(sorted(set(days))) != days:
                raise ValueError("invalid plan dates")
            if not set(days) <= permitted:
                raise ValueError("plan date outside request")
        if not set(self.residual) <= set(self.selected):
            raise ValueError("residual expands selection")
        required = correction_dates(self.request, self.refresh_recent_days)
        if self.policy == "full_lookback" or self.coverage_status == "fallback_full":
            required = set(self.request.candidates)
        if self.today_refresh:
            required.add(self.request.today)
        if not required <= set(self.selected):
            raise ValueError("plan drops required refresh dates")

    def resume(self, current_binding, acknowledged=()):
        if current_binding != self.destination_binding:
            raise ValueError("destination changed; explicit recovery required")
        if not set(acknowledged) <= set(self.selected):
            raise ValueError("acknowledgement outside original selection")
        return replace(self, residual=tuple(day for day in self.residual if day not in acknowledged))

    def to_json(self):
        return json.dumps({
            "schema": "healthmd.receiver_coverage.plan", "schema_version": 1,
            "destination_binding": self.destination_binding,
            "request": {"request_id": self.request.request_id, "scope_id": self.request.scope_id,
                        "calendar_timezone": self.request.calendar_timezone,
                        "candidates": list(self.request.candidates), "today": self.request.today},
            "policy": self.policy, "refresh_recent_days": self.refresh_recent_days,
            "today_refresh": self.today_refresh, "selected": list(self.selected),
            "residual": list(self.residual), "coverage_status": self.coverage_status,
        }, sort_keys=True, separators=(",", ":"))

    @classmethod
    def from_json(cls, text):
        value = strict_json(text)
        exact_object(value, {"schema", "schema_version", "destination_binding", "request", "policy",
                             "refresh_recent_days", "today_refresh", "selected", "residual", "coverage_status"})
        if value.pop("schema") != "healthmd.receiver_coverage.plan" or type(value["schema_version"]) is not int or value.pop("schema_version") != 1:
            raise ValueError("unsupported plan")
        request = exact_object(value["request"], {"request_id", "scope_id", "calendar_timezone", "candidates", "today"})
        for field in ("selected", "residual"):
            if not isinstance(value[field], list):
                raise ValueError("invalid persisted dates")
            value[field] = tuple(value[field])
        if not isinstance(request["candidates"], list):
            raise ValueError("invalid persisted candidates")
        request["candidates"] = tuple(request["candidates"])
        value["request"] = Request(**request)
        return cls(**value)


def select(request, destination_binding, *, policy="full_lookback", response=None,
           refresh_recent_days=0, today_refresh=False):
    if policy not in ("full_lookback", "missing_days"):
        raise ValueError("invalid policy")
    if type(refresh_recent_days) is not int or not 0 <= refresh_recent_days <= MAX_DAYS:
        raise ValueError("invalid correction window")
    selected = set(request.candidates)
    status = "not_requested"
    if policy == "missing_days":
        try:
            selected -= completed_dates(request, response)
            status = "valid"
        except (ValueError, TypeError, UnicodeError, RecursionError):
            status = "fallback_full"
        if refresh_recent_days:
            selected.update(correction_dates(request, refresh_recent_days))
    if today_refresh:
        selected.add(request.today)
    dates = tuple(sorted(selected))
    return Plan(destination_binding, request, policy, refresh_recent_days, today_refresh, dates, dates, status)
