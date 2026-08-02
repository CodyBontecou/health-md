#![allow(clippy::too_many_lines)]

use std::collections::{BTreeMap, BTreeSet};

use chrono::{DateTime, Duration, NaiveDate, TimeZone as _, Timelike as _, Utc};
use chrono_tz::Tz;
use serde_json::{Map, Value};

use super::{HostedConsentDetail, HostedConsentRequest, HostedError};

const MAX_METRICS: usize = 4_096;
const MAX_WORKOUTS: usize = 4_096;
const MAX_SLEEP_SESSIONS: usize = 4_096;
const MAX_EVIDENCE: usize = 20_000;
const MAX_LIMITATIONS: usize = 1_024;
const MAX_NESTED_ARRAY: usize = 20_000;
const MAX_JSON_DEPTH: usize = 32;
const MAX_OBJECT_FIELDS: usize = 512;
const MAX_STRING_BYTES: usize = 16 * 1_024;

pub(super) fn validate_context_day(
    day: &Value,
    consent: &HostedConsentRequest,
    now: DateTime<Utc>,
) -> Result<(), HostedError> {
    validate_json_shape(day, 0)?;
    let object = day.as_object().ok_or_else(invalid_day)?;
    reject_unknown(
        object,
        &[
            "schema",
            "schema_version",
            "owner_date",
            "interval_start",
            "interval_end",
            "calendar_timezone",
            "source",
            "status",
            "metrics",
            "workouts",
            "sleep_sessions",
            "evidence",
            "limitations",
        ],
    )?;
    if string(object, "schema")? != "healthmd.query_context_day"
        || integer(object, "schema_version")? != 1
    {
        return Err(HostedError::new(
            "healthmd_sync_schema_unsupported",
            "The synchronized context-day schema is unsupported.",
        ));
    }

    let owner_date = string(object, "owner_date")?;
    let parsed_owner_date = parse_owner_date(owner_date)?;
    let start = timestamp(object, "interval_start")?;
    let end = timestamp(object, "interval_end")?;
    let timezone_name = string(object, "calendar_timezone")?;
    if timezone_name.len() > 128 || timezone_name.chars().any(char::is_control) {
        return Err(invalid_day());
    }
    let timezone: Tz = timezone_name.parse().map_err(|_| invalid_day())?;
    let local_start = start.with_timezone(&timezone);
    let local_end = end.with_timezone(&timezone);
    if local_start.date_naive() != parsed_owner_date
        || local_end.date_naive() != parsed_owner_date.succ_opt().ok_or_else(invalid_day)?
        || local_start.time().num_seconds_from_midnight() != 0
        || local_start.nanosecond() != 0
        || local_end.time().num_seconds_from_midnight() != 0
        || local_end.nanosecond() != 0
    {
        return Err(invalid_day());
    }
    let interval_seconds = end.signed_duration_since(start).num_seconds();
    if !(23 * 3_600..=25 * 3_600).contains(&interval_seconds) || end > now + Duration::minutes(5) {
        return Err(invalid_day());
    }

    validate_source(object.get("source"), None)?;
    let top_source = object.get("source").ok_or_else(invalid_day)?;
    status(object.get("status"))?;
    validate_limitations(object.get("limitations"), MAX_LIMITATIONS)?;

    let evidence_values = required_array(object, "evidence", MAX_EVIDENCE)?;
    let mut evidence_ids = BTreeSet::new();
    let mut evidence_metric_ids = BTreeMap::new();
    for evidence in evidence_values {
        let evidence = evidence.as_object().ok_or_else(invalid_day)?;
        reject_unknown(evidence, &["reference", "value", "note", "metric_ids"])?;
        let reference = evidence
            .get("reference")
            .and_then(Value::as_object)
            .ok_or_else(invalid_day)?;
        reject_unknown(
            reference,
            &[
                "evidence_id",
                "locator",
                "source",
                "source_id",
                "provider_id",
            ],
        )?;
        let evidence_id = bounded_identifier(string(reference, "evidence_id")?)?;
        if !evidence_ids.insert(evidence_id.to_owned()) {
            return Err(invalid_day());
        }
        validate_locator(reference.get("locator"), owner_date)?;
        validate_source(reference.get("source"), Some(top_source))?;
        let source_id = strict_identifier(string(reference, "source_id")?)?;
        if !consent.allowed_source_ids.contains(source_id) {
            return Err(consent_violation());
        }
        match reference.get("provider_id") {
            None | Some(Value::Null) => {}
            Some(Value::String(provider))
                if strict_identifier(provider).is_ok()
                    && consent.allowed_provider_ids.contains(provider) => {}
            Some(_) => return Err(consent_violation()),
        }
        match evidence.get("value") {
            None | Some(Value::Null) => {}
            Some(value) if consent.maximum_detail == HostedConsentDetail::Lossless => {
                validate_query_value(value, 0)?;
            }
            Some(_) => return Err(consent_violation()),
        }
        match evidence.get("note") {
            None | Some(Value::Null) => {}
            Some(Value::String(note))
                if consent.maximum_detail == HostedConsentDetail::Lossless
                    && note.len() <= MAX_STRING_BYTES => {}
            Some(_) if consent.maximum_detail != HostedConsentDetail::Lossless => {
                return Err(consent_violation());
            }
            Some(_) => return Err(invalid_day()),
        }
        let metric_ids = string_array(evidence, "metric_ids", 512)?;
        if metric_ids.is_empty() {
            return Err(invalid_day());
        }
        let mut validated_metric_ids = BTreeSet::new();
        for metric_id in metric_ids {
            let metric_id = strict_identifier(metric_id)?;
            if !consent.allowed_metric_ids.contains(metric_id) {
                return Err(consent_violation());
            }
            if !validated_metric_ids.insert(metric_id.to_owned()) {
                return Err(invalid_day());
            }
        }
        evidence_metric_ids.insert(evidence_id.to_owned(), validated_metric_ids);
    }

    let mut referenced_evidence_ids = BTreeSet::new();
    let metrics = required_array(object, "metrics", MAX_METRICS)?;
    let mut observation_ids = BTreeSet::new();
    for metric in metrics {
        let metric = metric.as_object().ok_or_else(invalid_day)?;
        reject_unknown(
            metric,
            &[
                "observation_id",
                "metric_id",
                "display_name",
                "value",
                "status",
                "daily_aggregation",
                "evidence_ids",
                "limitations",
            ],
        )?;
        let observation_id = bounded_identifier(string(metric, "observation_id")?)?;
        if !observation_ids.insert(observation_id.to_owned()) {
            return Err(invalid_day());
        }
        let metric_id = strict_identifier(string(metric, "metric_id")?)?;
        if !consent.allowed_metric_ids.contains(metric_id) {
            return Err(consent_violation());
        }
        bounded_text(string(metric, "display_name")?, 512)?;
        match metric.get("value") {
            None | Some(Value::Null) => {}
            Some(value) => validate_query_value(value, 0)?,
        }
        status(metric.get("status"))?;
        match metric.get("daily_aggregation") {
            None | Some(Value::Null) => {}
            Some(Value::String(value)) if valid_daily_aggregation(value) => {}
            Some(_) => return Err(invalid_day()),
        }
        validate_evidence_references(
            metric,
            &evidence_metric_ids,
            metric_id,
            &mut referenced_evidence_ids,
        )?;
        validate_limitations(metric.get("limitations"), MAX_LIMITATIONS)?;
    }

    let workouts = required_array(object, "workouts", MAX_WORKOUTS)?;
    if !workouts.is_empty() && !consent.allowed_metric_ids.contains("workouts") {
        return Err(consent_violation());
    }
    let mut workout_ids = BTreeSet::new();
    for workout in workouts {
        let workout = workout.as_object().ok_or_else(invalid_day)?;
        reject_unknown(
            workout,
            &[
                "workout_id",
                "activity",
                "start",
                "end",
                "details",
                "evidence_ids",
            ],
        )?;
        let workout_id = bounded_identifier(string(workout, "workout_id")?)?;
        if !workout_ids.insert(workout_id.to_owned()) {
            return Err(invalid_day());
        }
        bounded_text(string(workout, "activity")?, 512)?;
        validate_timestamp_pair(workout, "start", "end", start, end)?;
        let details = workout
            .get("details")
            .and_then(Value::as_object)
            .ok_or_else(invalid_day)?;
        if details.len() > MAX_OBJECT_FIELDS {
            return Err(invalid_day());
        }
        if consent.maximum_detail != HostedConsentDetail::Lossless && !details.is_empty() {
            return Err(consent_violation());
        }
        for (key, value) in details {
            strict_identifier(key)?;
            validate_query_value(value, 0)?;
        }
        validate_evidence_references(
            workout,
            &evidence_metric_ids,
            "workouts",
            &mut referenced_evidence_ids,
        )?;
    }

    let sessions = required_array(object, "sleep_sessions", MAX_SLEEP_SESSIONS)?;
    if !sessions.is_empty() && !consent.allowed_metric_ids.contains("sleep_total") {
        return Err(consent_violation());
    }
    // Compact context days use midnight-to-midnight ownership for ordinary metrics,
    // while Apple deliberately attributes sleep using the owner's noon-to-noon
    // journaling window. Derive that adjacent window in the declared timezone so
    // normal overnight sessions remain valid across DST transitions.
    let sleep_window_start = timezone
        .from_local_datetime(
            &parsed_owner_date
                .and_hms_opt(12, 0, 0)
                .ok_or_else(invalid_day)?,
        )
        .single()
        .ok_or_else(invalid_day)?
        .with_timezone(&Utc);
    let sleep_window_end = timezone
        .from_local_datetime(
            &parsed_owner_date
                .succ_opt()
                .ok_or_else(invalid_day)?
                .and_hms_opt(12, 0, 0)
                .ok_or_else(invalid_day)?,
        )
        .single()
        .ok_or_else(invalid_day)?
        .with_timezone(&Utc);
    let mut session_ids = BTreeSet::new();
    for session in sessions {
        let session = session.as_object().ok_or_else(invalid_day)?;
        reject_unknown(
            session,
            &[
                "session_id",
                "start",
                "end",
                "classification",
                "completeness",
                "stage_intervals",
                "aggregate_stage_durations_seconds",
                "evidence_ids",
                "limitations",
            ],
        )?;
        let session_id = bounded_identifier(string(session, "session_id")?)?;
        if !session_ids.insert(session_id.to_owned()) {
            return Err(invalid_day());
        }
        validate_timestamp_pair(
            session,
            "start",
            "end",
            sleep_window_start,
            sleep_window_end,
        )?;
        if !matches!(
            string(session, "classification")?,
            "overnight" | "nap" | "sleep"
        ) || !matches!(
            string(session, "completeness")?,
            "complete"
                | "partial"
                | "truncated_at_start"
                | "truncated_at_end"
                | "truncated_at_both"
                | "aggregated"
                | "outside_session"
        ) {
            return Err(invalid_day());
        }
        let intervals = required_array(session, "stage_intervals", MAX_NESTED_ARRAY)?;
        if consent.maximum_detail != HostedConsentDetail::Lossless && !intervals.is_empty() {
            return Err(consent_violation());
        }
        let session_start = timestamp(session, "start")?;
        let session_end = timestamp(session, "end")?;
        if session_end > now + Duration::minutes(5) {
            return Err(invalid_day());
        }
        for interval in intervals {
            let interval = interval.as_object().ok_or_else(invalid_day)?;
            reject_unknown(interval, &["stage", "start", "end"])?;
            let stage = strict_identifier(string(interval, "stage")?)?;
            let metric_id = sleep_stage_metric_id(stage).ok_or_else(invalid_day)?;
            if !consent.allowed_metric_ids.contains(metric_id) {
                return Err(consent_violation());
            }
            validate_timestamp_pair(interval, "start", "end", session_start, session_end)?;
        }
        let aggregates = session
            .get("aggregate_stage_durations_seconds")
            .and_then(Value::as_object)
            .ok_or_else(invalid_day)?;
        if aggregates.len() > 64 {
            return Err(invalid_day());
        }
        let session_seconds = session_end
            .signed_duration_since(session_start)
            .to_std()
            .map_err(|_| invalid_day())?
            .as_secs_f64();
        for (stage, seconds) in aggregates {
            strict_identifier(stage)?;
            let metric_id = sleep_stage_metric_id(stage).ok_or_else(invalid_day)?;
            if !consent.allowed_metric_ids.contains(metric_id) {
                return Err(consent_violation());
            }
            let seconds = finite_number(seconds)?;
            if !(0.0..=session_seconds + 1.0).contains(&seconds) {
                return Err(invalid_day());
            }
        }
        validate_evidence_references(
            session,
            &evidence_metric_ids,
            "sleep_total",
            &mut referenced_evidence_ids,
        )?;
        validate_limitations(session.get("limitations"), MAX_LIMITATIONS)?;
    }

    if referenced_evidence_ids != evidence_ids {
        return Err(invalid_day());
    }
    Ok(())
}

fn validate_json_shape(value: &Value, depth: usize) -> Result<(), HostedError> {
    if depth > MAX_JSON_DEPTH {
        return Err(invalid_day());
    }
    match value {
        Value::Null | Value::Bool(_) => Ok(()),
        Value::Number(value) if value.as_f64().is_some_and(f64::is_finite) => Ok(()),
        Value::String(value) if value.len() <= MAX_STRING_BYTES => Ok(()),
        Value::Array(values) if values.len() <= MAX_NESTED_ARRAY => {
            for value in values {
                validate_json_shape(value, depth + 1)?;
            }
            Ok(())
        }
        Value::Object(values) if values.len() <= MAX_OBJECT_FIELDS => {
            for (key, value) in values {
                if key.is_empty() || key.len() > 256 || key.chars().any(char::is_control) {
                    return Err(invalid_day());
                }
                validate_json_shape(value, depth + 1)?;
            }
            Ok(())
        }
        _ => Err(invalid_day()),
    }
}

fn validate_source(value: Option<&Value>, expected: Option<&Value>) -> Result<(), HostedError> {
    let value = value.ok_or_else(invalid_day)?;
    let source = value.as_object().ok_or_else(invalid_day)?;
    reject_unknown(source, &["schema", "schema_version", "digest"])?;
    strict_identifier(string(source, "schema")?)?;
    let version = integer(source, "schema_version")?;
    if version == 0 || version > u64::from(u16::MAX) {
        return Err(invalid_day());
    }
    if !is_sha256(string(source, "digest")?) {
        return Err(invalid_day());
    }
    if expected.is_some_and(|expected| expected != value) {
        return Err(invalid_day());
    }
    Ok(())
}

fn validate_locator(value: Option<&Value>, owner_date: &str) -> Result<(), HostedError> {
    let locator = value.and_then(Value::as_object).ok_or_else(invalid_day)?;
    let locator_type = string(locator, "type")?;
    let allowed = match locator_type {
        "summary_key" => &["type", "owner_date", "key"][..],
        "canonical_uuid" => &["type", "owner_date", "uuid"][..],
        "external_identity" | "query_manifest" | "partial_failure" => {
            &["type", "owner_date", "identifier"][..]
        }
        "warning" => &["type", "owner_date", "code"][..],
        _ => return Err(invalid_day()),
    };
    reject_unknown(locator, allowed)?;
    if string(locator, "owner_date")? != owner_date {
        return Err(invalid_day());
    }
    let payload_key = allowed[2];
    bounded_identifier(string(locator, payload_key)?)?;
    Ok(())
}

fn validate_limitations(value: Option<&Value>, maximum: usize) -> Result<(), HostedError> {
    let values = value.and_then(Value::as_array).ok_or_else(invalid_day)?;
    if values.len() > maximum {
        return Err(invalid_day());
    }
    for value in values {
        let limitation = value.as_object().ok_or_else(invalid_day)?;
        reject_unknown(limitation, &["code", "message"])?;
        strict_identifier(string(limitation, "code")?)?;
        bounded_text(string(limitation, "message")?, 4_096)?;
    }
    Ok(())
}

fn validate_query_value(value: &Value, depth: usize) -> Result<(), HostedError> {
    if depth > 16 {
        return Err(invalid_day());
    }
    let object = value.as_object().ok_or_else(invalid_day)?;
    let value_type = strict_identifier(string(object, "type")?)?;
    match value_type {
        "quantity" => {
            reject_unknown(object, &["type", "value", "unit"])?;
            finite_number(object.get("value").ok_or_else(invalid_day)?)?;
            bounded_identifier(string(object, "unit")?)?;
        }
        "duration" => {
            reject_unknown(object, &["type", "seconds"])?;
            finite_number(object.get("seconds").ok_or_else(invalid_day)?)?;
        }
        "count" => {
            reject_unknown(object, &["type", "value"])?;
            object
                .get("value")
                .and_then(Value::as_i64)
                .ok_or_else(invalid_day)?;
        }
        "string" => {
            reject_unknown(object, &["type", "value"])?;
            bounded_text(string(object, "value")?, MAX_STRING_BYTES)?;
        }
        "category" => {
            reject_unknown(object, &["type", "identifier", "display", "raw_value"])?;
            bounded_identifier(string(object, "identifier")?)?;
            if let Some(display) = object.get("display") {
                bounded_text(display.as_str().ok_or_else(invalid_day)?, 1_024)?;
            }
            if object
                .get("raw_value")
                .is_some_and(|value| value.as_i64().is_none())
            {
                return Err(invalid_day());
            }
        }
        "boolean" => {
            reject_unknown(object, &["type", "value"])?;
            object
                .get("value")
                .and_then(Value::as_bool)
                .ok_or_else(invalid_day)?;
        }
        "timestamp" => {
            reject_unknown(object, &["type", "value"])?;
            parse_timestamp(string(object, "value")?)?;
        }
        "date" => {
            reject_unknown(object, &["type", "value"])?;
            parse_owner_date(string(object, "value")?)?;
        }
        "array" => {
            reject_unknown(object, &["type", "value"])?;
            let values = object
                .get("value")
                .and_then(Value::as_array)
                .ok_or_else(invalid_day)?;
            if values.len() > 1_024 {
                return Err(invalid_day());
            }
            for value in values {
                validate_query_value(value, depth + 1)?;
            }
        }
        _ => {
            reject_unknown(object, &["type", "value"])?;
            if let Some(value) = object.get("value") {
                validate_json_shape(value, depth + 1)?;
            }
        }
    }
    Ok(())
}

fn validate_evidence_references(
    object: &Map<String, Value>,
    known: &BTreeMap<String, BTreeSet<String>>,
    required_metric_id: &str,
    referenced: &mut BTreeSet<String>,
) -> Result<(), HostedError> {
    let mut seen = BTreeSet::new();
    for evidence_id in string_array(object, "evidence_ids", MAX_NESTED_ARRAY)? {
        let evidence_id = bounded_identifier(evidence_id)?;
        let Some(metric_ids) = known.get(evidence_id) else {
            return Err(invalid_day());
        };
        if !seen.insert(evidence_id) || !metric_ids.contains(required_metric_id) {
            return Err(invalid_day());
        }
        referenced.insert(evidence_id.to_owned());
    }
    Ok(())
}

fn validate_timestamp_pair(
    object: &Map<String, Value>,
    start_key: &str,
    end_key: &str,
    containing_start: DateTime<Utc>,
    containing_end: DateTime<Utc>,
) -> Result<(), HostedError> {
    let start = timestamp(object, start_key)?;
    let end = timestamp(object, end_key)?;
    if end <= start || start < containing_start || end > containing_end {
        return Err(invalid_day());
    }
    Ok(())
}

fn reject_unknown(object: &Map<String, Value>, allowed: &[&str]) -> Result<(), HostedError> {
    if object.keys().any(|key| !allowed.contains(&key.as_str())) {
        return Err(invalid_day());
    }
    Ok(())
}

fn required_array<'a>(
    object: &'a Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<&'a [Value], HostedError> {
    let values = object
        .get(key)
        .and_then(Value::as_array)
        .ok_or_else(invalid_day)?;
    if values.len() > maximum {
        return Err(invalid_day());
    }
    Ok(values)
}

fn string_array<'a>(
    object: &'a Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<Vec<&'a str>, HostedError> {
    let values = required_array(object, key, maximum)?;
    values
        .iter()
        .map(|value| value.as_str().ok_or_else(invalid_day))
        .collect()
}

fn string<'a>(object: &'a Map<String, Value>, key: &str) -> Result<&'a str, HostedError> {
    object
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(invalid_day)
}

fn integer(object: &Map<String, Value>, key: &str) -> Result<u64, HostedError> {
    object
        .get(key)
        .and_then(Value::as_u64)
        .ok_or_else(invalid_day)
}

fn timestamp(object: &Map<String, Value>, key: &str) -> Result<DateTime<Utc>, HostedError> {
    parse_timestamp(string(object, key)?)
}

fn parse_timestamp(value: &str) -> Result<DateTime<Utc>, HostedError> {
    DateTime::parse_from_rfc3339(value)
        .map(|value| value.with_timezone(&Utc))
        .map_err(|_| invalid_day())
}

fn parse_owner_date(value: &str) -> Result<NaiveDate, HostedError> {
    if value.len() != 10 {
        return Err(invalid_day());
    }
    let parsed = NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| invalid_day())?;
    if parsed.format("%Y-%m-%d").to_string() != value
        || parsed < NaiveDate::from_ymd_opt(1900, 1, 1).ok_or_else(invalid_day)?
    {
        return Err(invalid_day());
    }
    Ok(parsed)
}

fn status(value: Option<&Value>) -> Result<(), HostedError> {
    if value.and_then(Value::as_str).is_some_and(|value| {
        matches!(
            value,
            "available"
                | "complete_empty"
                | "partial"
                | "failed"
                | "unsupported"
                | "skipped"
                | "cancelled"
                | "not_requested"
                | "legacy_unavailable"
                | "redacted"
                | "not_synchronized"
        )
    }) {
        Ok(())
    } else {
        Err(invalid_day())
    }
}

fn sleep_stage_metric_id(stage: &str) -> Option<&'static str> {
    match stage {
        "deep" => Some("sleep_deep"),
        "rem" => Some("sleep_rem"),
        "core" => Some("sleep_core"),
        "awake" => Some("sleep_awake"),
        "in_bed" => Some("sleep_in_bed"),
        "unspecified" | "asleep_total" => Some("sleep_total"),
        _ => None,
    }
}

fn valid_daily_aggregation(value: &str) -> bool {
    matches!(
        value,
        "sum"
            | "average"
            | "minimum"
            | "maximum"
            | "latest"
            | "count"
            | "list"
            | "duration_sum"
            | "first_time"
            | "last_time"
            | "category_latest"
            | "weighted_average"
    )
}

fn finite_number(value: &Value) -> Result<f64, HostedError> {
    value
        .as_f64()
        .filter(|value| value.is_finite())
        .ok_or_else(invalid_day)
}

fn strict_identifier(value: &str) -> Result<&str, HostedError> {
    if !value.is_empty()
        && value.len() <= 128
        && value.bytes().enumerate().all(|(index, byte)| {
            byte.is_ascii_lowercase()
                || byte.is_ascii_digit()
                || (index > 0 && matches!(byte, b'.' | b'_' | b'-'))
        })
    {
        Ok(value)
    } else {
        Err(invalid_day())
    }
}

fn bounded_identifier(value: &str) -> Result<&str, HostedError> {
    if !value.is_empty() && value.len() <= 256 && !value.chars().any(char::is_control) {
        Ok(value)
    } else {
        Err(invalid_day())
    }
}

fn bounded_text(value: &str, maximum: usize) -> Result<(), HostedError> {
    if !value.is_empty() && value.len() <= maximum {
        Ok(())
    } else {
        Err(invalid_day())
    }
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn invalid_day() -> HostedError {
    HostedError::new(
        "healthmd_sync_invalid",
        "The synchronized context day is invalid.",
    )
}

fn consent_violation() -> HostedError {
    HostedError::new(
        "healthmd_consent_violation",
        "The synchronized context day exceeds the active consent.",
    )
}
