#![allow(
    clippy::assigning_clones,
    clippy::cast_possible_truncation,
    clippy::cast_precision_loss,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]

use std::{
    collections::{BTreeMap, BTreeSet},
    ops::{Deref, DerefMut},
};

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use chacha20poly1305::{
    ChaCha20Poly1305, Key, Nonce,
    aead::{Aead, KeyInit, Payload},
};
use chrono::{DateTime, Duration, NaiveDate, SecondsFormat, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use sha2::{Digest as _, Sha256};

use crate::backend::{CallContext, QueryDetailLevel, QueryPageRequest};

use super::{
    models::{HostedConsentDetail, HostedError},
    store::{HostedDataStore, Manifest, OwnerCorpus},
};

const MAX_PAGE_ITEMS: usize = 1_000;
const MAX_PAGE_BYTES: usize = 1_024 * 1_024;
const MAX_SCAN_DAYS: usize = 3_650;
const MAX_SCAN_BYTES: usize = 128 * 1_024 * 1_024;
const MAX_CANDIDATES: usize = 100_000;
const MAX_CANDIDATE_BYTES: usize = 64 * 1_024 * 1_024;
const MAX_MISSING_INTERVALS: usize = 64;
const MAX_DETAIL_IDS: usize = 128;
const MAX_DETAIL_ID_BYTES: usize = 128;
const MAX_DETAIL_PROBES: usize = 100_000;
const FACTUAL_CODE: &str = "factual_observations_only";
const FACTUAL_MESSAGE: &str = "This response reports synchronized observations only and does not diagnose conditions or recommend treatment.";

type DatedValues = Vec<(String, Value)>;
type PeriodValues = BTreeMap<String, (DatedValues, DatedValues)>;
type TimeInterval = (DateTime<Utc>, DateTime<Utc>);
type StageIntervals = BTreeMap<String, Vec<TimeInterval>>;

#[derive(Clone, Debug)]
struct QuerySpec {
    metrics: BTreeSet<String>,
    sources: SourceSelection,
    dates: DateSelection,
    operation: String,
    operation_value: Value,
    max_items: usize,
    max_bytes: usize,
    cursor: Option<String>,
    detail: QueryDetailLevel,
}

#[derive(Clone, Debug)]
enum DateSelection {
    All,
    Exact { start: String, end: String },
}

#[derive(Clone, Debug)]
enum SourceSelection {
    All,
    Explicit {
        source_ids: BTreeSet<String>,
        provider_ids: BTreeSet<String>,
    },
}

#[derive(Debug, Deserialize, Serialize)]
struct CursorPayload {
    offset: usize,
    request_digest: String,
    operation: String,
    detail: String,
    dataset_revision: u64,
    owner_partition: String,
}

#[derive(Default)]
struct CandidateBuffer {
    values: Vec<Value>,
    bytes: usize,
}

struct AlignmentWorkout {
    owner_date: String,
    value: Value,
    evidence: Vec<Value>,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
}

struct AlignmentSleep {
    value: Value,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
}

impl Deref for CandidateBuffer {
    type Target = Vec<Value>;

    fn deref(&self) -> &Self::Target {
        &self.values
    }
}

impl DerefMut for CandidateBuffer {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.values
    }
}

struct Evaluation {
    candidates: CandidateBuffer,
    packet_kind: Option<String>,
    packet_range: Option<Value>,
    coverage_value_days: BTreeSet<String>,
    coverage_missing_statuses: BTreeMap<String, String>,
    limitations: Vec<Value>,
    metadata: Option<Value>,
}

impl HostedDataStore {
    pub(super) async fn evaluate_query(
        &self,
        context: &CallContext,
        request: QueryPageRequest,
    ) -> Result<Value, HostedError> {
        let mut owner = self.owner(&context.caller)?;
        let guard = self.gate.write().await;
        self.load_existing_data_key(&mut owner)?;
        let mut manifest = self.read_manifest(&owner)?;
        self.enforce_retention_policy(&owner, &mut manifest, Utc::now())?;
        let consent = manifest.consent.as_ref().ok_or_else(|| {
            query_error(
                "healthmd_not_synchronized",
                "Hosted consent and synchronized snapshots are required.",
            )
        })?;
        if consent.expires_at.is_some_and(|value| value <= Utc::now()) {
            return Err(query_error(
                "healthmd_consent_expired",
                "Server-side consent has expired.",
            ));
        }
        let spec = parse_query(&request, consent)?;
        let request_digest = request_digest(&request.query)?;
        let offset = match spec.cursor.as_deref() {
            None => 0,
            Some(cursor) => decode_cursor(
                &owner,
                cursor,
                &request_digest,
                &spec.operation,
                spec.detail,
                manifest.dataset_revision,
            )?,
        };
        // Retention and crash recovery require exclusive access, but immutable object scanning
        // does not. Let independent hosted queries share the read gate after the short mutation
        // phase. A writer that wins the handoff can only make this captured snapshot stale; its
        // checked object reads then either remain valid or fail closed.
        drop(guard);
        let guard = self.gate.read().await;
        let evaluation = self.evaluate_operation(context, &owner, &manifest, &spec)?;
        if offset > evaluation.candidates.len() {
            return Err(query_error(
                "healthmd_cursor_invalid",
                "The query cursor is invalid.",
            ));
        }
        // Formatting a byte-bounded page can require several serialization attempts. The
        // immutable evaluation is already memory-resident, so do not retain even the shared store
        // gate while sizing the response.
        drop(guard);
        build_page(
            context,
            &owner,
            &manifest,
            &spec,
            request_digest,
            offset,
            evaluation,
        )
    }

    fn evaluate_operation(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        match spec.operation.as_str() {
            "metric_series" => self.metric_series(context, owner, manifest, spec),
            "workout_listing" => self.workout_listing(context, owner, manifest, spec),
            "sleep_session_listing" => self.sleep_listing(context, owner, manifest, spec),
            "source_record_listing" => self.source_listing(context, owner, manifest, spec),
            "coverage" => self.coverage_only(context, owner, manifest, spec),
            "period_comparison" => self.period_comparison(context, owner, manifest, spec),
            "workout_sleep_alignment" => self.alignment(context, owner, manifest, spec),
            "derive_packet" => self.derive_packet(context, owner, manifest, spec),
            _ => Err(query_error(
                "healthmd_query_unsupported",
                "The requested query operation is unsupported.",
            )),
        }
    }

    fn metric_series(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let mut output = empty_evaluation();
        let mut seen = BTreeSet::new();
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if !spec.dates.contains(owner_date) {
                return Ok(());
            }
            let evidence = evidence_index(day);
            let mut day_has_value = false;
            let mut day_missing_status = None;
            for metric in day_array(day, "metrics")? {
                let metric_id = metric.get("metric_id").and_then(Value::as_str).ok_or_else(invalid_snapshot)?;
                if !spec.metrics.contains(metric_id)
                    || !record_passes_sources(metric, &evidence, &spec.sources)
                {
                    continue;
                }
                let observation = metric
                    .get("observation_id")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if !seen.insert(format!("{owner_date}\0{observation}")) {
                    continue;
                }
                let value = metric.get("value").cloned().unwrap_or(Value::Null);
                let mut status = metric
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("partial")
                    .to_owned();
                if value.is_null() && status == "available" {
                    status = "complete_empty".to_owned();
                }
                day_has_value |= !value.is_null() && status == "available";
                if value.is_null() || status != "available" {
                    merge_missing_status(&mut day_missing_status, &status);
                }
                let references = references_for(metric, &evidence, &spec.sources);
                push_candidate(
                    &mut output.candidates,
                    json!({
                        "type": "metric",
                        "metric": {
                            "metric_id": metric_id,
                            "display_name": metric.get("display_name").and_then(Value::as_str).unwrap_or(metric_id),
                            "owner_date": owner_date,
                            "value": value,
                            "status": status,
                            "evidence": references,
                            "limitations": metric.get("limitations").cloned().unwrap_or_else(|| json!([]))
                        }
                    }),
                )?;
            }
            if day_has_value {
                output.coverage_value_days.insert(owner_date.to_owned());
            } else if let Some(status) = day_missing_status {
                output
                    .coverage_missing_statuses
                    .insert(owner_date.to_owned(), status);
            }
            collect_day_limitations(day, &mut output.limitations);
            Ok(())
        })?;
        Ok(output)
    }

    fn workout_listing(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let mut output = empty_evaluation();
        let mut seen = BTreeSet::new();
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if !spec.dates.contains(owner_date) {
                return Ok(());
            }
            let evidence = evidence_index(day);
            let mut has = false;
            for workout in day_array(day, "workouts")? {
                if !record_passes_sources(workout, &evidence, &spec.sources) {
                    continue;
                }
                let id = workout
                    .get("workout_id")
                    .and_then(Value::as_str)
                    .ok_or_else(invalid_snapshot)?;
                if seen.insert(id.to_owned()) {
                    let mut projected = workout.clone();
                    if spec.detail == QueryDetailLevel::Summary {
                        projected["details"] = json!({});
                    }
                    push_candidate(
                        &mut output.candidates,
                        json!({"type":"workout", "workout": projected}),
                    )?;
                    has = true;
                }
            }
            if has {
                output.coverage_value_days.insert(owner_date.to_owned());
            }
            collect_day_limitations(day, &mut output.limitations);
            Ok(())
        })?;
        output.candidates.sort_by(|left, right| {
            item_string(left, "/workout/start")
                .cmp(item_string(right, "/workout/start"))
                .then_with(|| {
                    item_string(left, "/workout/workout_id")
                        .cmp(item_string(right, "/workout/workout_id"))
                })
        });
        Ok(output)
    }

    fn source_listing(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let mut output = empty_evaluation();
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if !spec.dates.contains(owner_date) {
                return Ok(());
            }
            let mut has = false;
            for evidence in day_array(day, "evidence")? {
                if !evidence_allowed(evidence, &spec.sources)
                    || !evidence_matches_metrics(evidence, &spec.metrics)
                {
                    continue;
                }
                push_candidate(
                    &mut output.candidates,
                    json!({"type":"evidence", "evidence": evidence}),
                )?;
                has = true;
            }
            if has {
                output.coverage_value_days.insert(owner_date.to_owned());
            }
            Ok(())
        })?;
        output.candidates.sort_by(|left, right| {
            item_string(left, "/evidence/reference/locator/owner_date")
                .cmp(item_string(right, "/evidence/reference/locator/owner_date"))
                .then_with(|| {
                    item_string(left, "/evidence/reference/evidence_id")
                        .cmp(item_string(right, "/evidence/reference/evidence_id"))
                })
        });
        Ok(output)
    }

    fn sleep_listing(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let operation = operation_object(&spec.operation_value)?;
        let include_naps = operation
            .get("include_naps")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let window = parse_window(operation.get("window"))?;
        let mut output = empty_evaluation();
        let mut excluded_naps = 0_u64;
        let mut outside = 0_u64;
        let mut source_excluded = 0_u64;
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if !spec.dates.contains(owner_date) {
                return Ok(());
            }
            let evidence = evidence_index(day);
            for session in day_array(day, "sleep_sessions")? {
                if session.get("classification").and_then(Value::as_str) == Some("nap")
                    && !include_naps
                {
                    excluded_naps += 1;
                    continue;
                }
                if !record_passes_sources(session, &evidence, &spec.sources) {
                    source_excluded = source_excluded
                        .checked_add(1)
                        .ok_or_else(scan_limit_error)?;
                    continue;
                }
                match sleep_result(
                    session,
                    owner_date,
                    day,
                    window,
                    &evidence,
                    &spec.metrics,
                    &spec.sources,
                )? {
                    Some(result) => {
                        output.coverage_value_days.insert(owner_date.to_owned());
                        push_candidate(
                            &mut output.candidates,
                            json!({"type":"sleep_session", "sleep_session": result}),
                        )?;
                    }
                    None => outside += 1,
                }
            }
            collect_day_limitations(day, &mut output.limitations);
            Ok(())
        })?;
        output.candidates.sort_by(|left, right| {
            item_string(left, "/sleep_session/start")
                .cmp(item_string(right, "/sleep_session/start"))
                .then_with(|| {
                    item_string(left, "/sleep_session/session_id")
                        .cmp(item_string(right, "/sleep_session/session_id"))
                })
        });
        output.metadata = Some(json!({
            "excluded_session_count": excluded_naps
                .checked_add(outside)
                .and_then(|value| value.checked_add(source_excluded))
                .ok_or_else(scan_limit_error)?,
            "excluded_nap_count": excluded_naps,
            "window_outside_session_count": outside,
            "source_excluded_session_count": source_excluded,
            "adjacent_owner_dates_considered": []
        }));
        Ok(output)
    }

    fn coverage_only(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let mut output = empty_evaluation();
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if spec.dates.contains(owner_date) {
                if day_has_selected_value(day, &spec.metrics, &spec.sources)? {
                    output.coverage_value_days.insert(owner_date.to_owned());
                } else if let Some(status) =
                    selected_metric_missing_status(day, &spec.metrics, &spec.sources)?
                {
                    output
                        .coverage_missing_statuses
                        .insert(owner_date.to_owned(), status);
                }
                collect_day_limitations(day, &mut output.limitations);
            }
            Ok(())
        })?;
        Ok(output)
    }

    fn period_comparison(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let operation = operation_object(&spec.operation_value)?;
        let first = parse_range(operation.get("first"))?;
        let second = parse_range(operation.get("second"))?;
        if !spec.dates.contains_range(&first) || !spec.dates.contains_range(&second) {
            return Err(invalid_query());
        }
        let descriptors = operation
            .get("aggregations")
            .and_then(Value::as_array)
            .ok_or_else(invalid_query)?;
        if descriptors.is_empty() || descriptors.len() > 512 {
            return Err(invalid_query());
        }
        let mut descriptor_ids = BTreeSet::new();
        for descriptor in descriptors {
            let descriptor = descriptor.as_object().ok_or_else(invalid_query)?;
            let id = descriptor
                .get("metric_id")
                .and_then(Value::as_str)
                .ok_or_else(invalid_query)?;
            if !spec.metrics.contains(id) || !descriptor_ids.insert(id) {
                return Err(invalid_query());
            }
        }
        let mut values: PeriodValues = BTreeMap::new();
        let mut output = empty_evaluation();
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if !first.contains(owner_date) && !second.contains(owner_date) {
                return Ok(());
            }
            let evidence = evidence_index(day);
            for metric in day_array(day, "metrics")? {
                let id = metric
                    .get("metric_id")
                    .and_then(Value::as_str)
                    .ok_or_else(invalid_snapshot)?;
                if !spec.metrics.contains(id)
                    || metric.get("status").and_then(Value::as_str) != Some("available")
                    || !record_passes_sources(metric, &evidence, &spec.sources)
                {
                    continue;
                }
                let Some(value) = metric.get("value").filter(|value| !value.is_null()) else {
                    continue;
                };
                let entry = values.entry(id.to_owned()).or_default();
                if first.contains(owner_date) {
                    entry.0.push((owner_date.to_owned(), value.clone()));
                }
                if second.contains(owner_date) {
                    entry.1.push((owner_date.to_owned(), value.clone()));
                }
            }
            Ok(())
        })?;
        for descriptor in descriptors {
            if context.cancellation.is_cancelled() {
                return Err(query_error(
                    "healthmd_request_cancelled",
                    "The hosted query was cancelled.",
                ));
            }
            let descriptor_object = descriptor.as_object().ok_or_else(invalid_query)?;
            let id = descriptor_object
                .get("metric_id")
                .and_then(Value::as_str)
                .ok_or_else(invalid_query)?;
            let kind = descriptor_object
                .get("kind")
                .and_then(Value::as_str)
                .ok_or_else(invalid_query)?;
            let (first_values, second_values) = values.get(id).cloned().unwrap_or_default();
            let first_value =
                aggregate(&first_values, kind, descriptor_object.get("expected_unit"))?;
            let second_value =
                aggregate(&second_values, kind, descriptor_object.get("expected_unit"))?;
            let (absolute, percent, direction) = comparison_delta(&first_value, &second_value)?;
            let value_days: BTreeSet<String> = first_values
                .iter()
                .chain(&second_values)
                .map(|value| value.0.clone())
                .collect();
            output
                .coverage_value_days
                .extend(value_days.iter().cloned());
            let coverage = coverage_for_ranges(manifest, &first, &second, &value_days)?;
            push_candidate(
                &mut output.candidates,
                json!({
                    "type": "comparison",
                    "comparison": {
                        "metric_id": id,
                        "aggregation": descriptor,
                        "first_range": first.to_json(),
                        "second_range": second.to_json(),
                        "first_value": first_value,
                        "second_value": second_value,
                        "absolute_change": absolute,
                        "percent_change": percent,
                        "direction": direction,
                        "coverage": coverage,
                        "evidence": [],
                        "limitations": []
                    }
                }),
            )?;
        }
        Ok(output)
    }

    fn derive_packet(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let operation = operation_object(&spec.operation_value)?;
        let kind = operation
            .get("kind")
            .and_then(Value::as_str)
            .ok_or_else(invalid_query)?;
        if !matches!(kind, "daily_wellness" | "training" | "doctor_visit") {
            return Err(invalid_query());
        }
        let detail_values = operation
            .get("detail_ids")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or_default();
        if detail_values.len() > MAX_DETAIL_IDS {
            return Err(invalid_query());
        }
        let mut details = BTreeSet::new();
        for value in detail_values {
            let detail = value.as_str().ok_or_else(invalid_query)?;
            if detail.is_empty()
                || detail.len() > MAX_DETAIL_ID_BYTES
                || !detail
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
                || !details.insert(detail.to_owned())
            {
                return Err(invalid_query());
            }
        }
        let mut output = empty_evaluation();
        let mut seen = BTreeSet::new();
        let mut detail_probes = 0_usize;
        self.scan_days(context, owner, manifest, |owner_date, day| {
            if !spec.dates.contains(owner_date) {
                return Ok(());
            }
            let evidence = evidence_index(day);
            for metric in day_array(day, "metrics")? {
                let id = metric.get("metric_id").and_then(Value::as_str).ok_or_else(invalid_snapshot)?;
                if !spec.metrics.contains(id)
                    || metric.get("status").and_then(Value::as_str) != Some("available")
                    || !record_passes_sources(metric, &evidence, &spec.sources)
                {
                    continue;
                }
                let Some(value) = metric.get("value").filter(|value| !value.is_null()) else { continue };
                let observation = metric.get("observation_id").and_then(Value::as_str).unwrap_or("");
                let fact_id = format!("metric:{owner_date}:{id}:{observation}");
                if seen.insert(fact_id.clone()) {
                    output.coverage_value_days.insert(owner_date.to_owned());
                    push_candidate(&mut output.candidates, json!({
                        "fact_id": fact_id,
                        "label": metric.get("display_name").and_then(Value::as_str).unwrap_or(id),
                        "owner_date": owner_date,
                        "value": value,
                        "evidence": references_for(metric, &evidence, &spec.sources)
                    }))?;
                }
            }
            if kind == "training" {
                for workout in day_array(day, "workouts")? {
                    if !record_passes_sources(workout, &evidence, &spec.sources) {
                        continue;
                    }
                    let workout_id = workout.get("workout_id").and_then(Value::as_str).ok_or_else(invalid_snapshot)?;
                    let workout_details = workout.get("details").and_then(Value::as_object);
                    for detail in &details {
                        detail_probes = detail_probes.checked_add(1).ok_or_else(scan_limit_error)?;
                        if detail_probes > MAX_DETAIL_PROBES {
                            return Err(scan_limit_error());
                        }
                        if detail_probes % 64 == 0 && context.cancellation.is_cancelled() {
                            return Err(query_error(
                                "healthmd_request_cancelled",
                                "The hosted query was cancelled.",
                            ));
                        }
                        let Some(value) = workout_details
                            .and_then(|values| values.get(detail))
                            .filter(|value| !value.is_null())
                        else { continue };
                        let fact_id = format!("workout:{workout_id}:{detail}");
                        if seen.insert(fact_id.clone()) {
                            output.coverage_value_days.insert(owner_date.to_owned());
                            push_candidate(&mut output.candidates, json!({
                                "fact_id": fact_id,
                                "label": detail,
                                "owner_date": owner_date,
                                "value": value,
                                "evidence": references_for(workout, &evidence, &spec.sources)
                            }))?;
                        }
                    }
                }
            }
            collect_day_limitations(day, &mut output.limitations);
            Ok(())
        })?;
        output.candidates.sort_by(|left, right| {
            item_string(left, "/fact_id").cmp(item_string(right, "/fact_id"))
        });
        output.packet_kind = Some(kind.to_owned());
        output.packet_range = selected_range_json(&spec.dates, manifest);
        Ok(output)
    }

    fn alignment(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        spec: &QuerySpec,
    ) -> Result<Evaluation, HostedError> {
        let operation = operation_object(&spec.operation_value)?;
        let include_naps = operation
            .get("include_naps")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let activity = operation
            .get("workout_activity")
            .and_then(Value::as_str)
            .map(str::to_lowercase);
        let window = parse_window(operation.get("window"))?;
        let mut workouts: Vec<AlignmentWorkout> = Vec::new();
        let mut sleeps: Vec<AlignmentSleep> = Vec::new();
        let mut intermediate_items = 0_usize;
        let mut intermediate_bytes = 0_usize;
        let mut output = empty_evaluation();
        self.scan_days(context, owner, manifest, |owner_date, day| {
            let adjacent = spec.dates.contains_or_adjacent(owner_date, 2)?;
            if !adjacent {
                return Ok(());
            }
            let evidence = evidence_index(day);
            if spec.dates.contains(owner_date) {
                for workout in day_array(day, "workouts")? {
                    if !record_passes_sources(workout, &evidence, &spec.sources) {
                        continue;
                    }
                    if activity.as_ref().is_some_and(|activity| {
                        workout
                            .get("activity")
                            .and_then(Value::as_str)
                            .map(str::to_lowercase)
                            .as_ref()
                            != Some(activity)
                    }) {
                        continue;
                    }
                    let references = references_for(workout, &evidence, &spec.sources);
                    let reference_bytes = references.iter().try_fold(0_usize, |total, value| {
                        total
                            .checked_add(estimated_json_size(value))
                            .ok_or_else(scan_limit_error)
                    })?;
                    let size = estimated_json_size(workout)
                        .checked_add(reference_bytes)
                        .ok_or_else(scan_limit_error)?;
                    reserve_intermediate(&mut intermediate_items, &mut intermediate_bytes, size)?;
                    workouts.push(AlignmentWorkout {
                        owner_date: owner_date.to_owned(),
                        value: workout.clone(),
                        evidence: references,
                        start: parse_json_timestamp(workout.get("start"))?,
                        end: parse_json_timestamp(workout.get("end"))?,
                    });
                }
            }
            for session in day_array(day, "sleep_sessions")? {
                if session.get("classification").and_then(Value::as_str) == Some("nap")
                    && !include_naps
                {
                    continue;
                }
                if record_passes_sources(session, &evidence, &spec.sources) {
                    if let Some(result) = sleep_result(
                        session,
                        owner_date,
                        day,
                        window,
                        &evidence,
                        &spec.metrics,
                        &spec.sources,
                    )? {
                        reserve_intermediate(
                            &mut intermediate_items,
                            &mut intermediate_bytes,
                            estimated_json_size(&result),
                        )?;
                        sleeps.push(AlignmentSleep {
                            start: parse_json_timestamp(result.get("start"))?,
                            end: parse_json_timestamp(result.get("end"))?,
                            value: result,
                        });
                    }
                }
            }
            Ok(())
        })?;
        let mut sleeps_by_end: Vec<usize> = (0..sleeps.len()).collect();
        sleeps_by_end.sort_unstable_by(|left, right| {
            sleeps[*left]
                .end
                .cmp(&sleeps[*right].end)
                .then_with(|| {
                    item_string(&sleeps[*left].value, "/owner_date")
                        .cmp(item_string(&sleeps[*right].value, "/owner_date"))
                })
                .then_with(|| {
                    item_string(&sleeps[*left].value, "/session_id")
                        .cmp(item_string(&sleeps[*right].value, "/session_id"))
                })
        });
        let mut sleeps_by_start: Vec<usize> = (0..sleeps.len()).collect();
        sleeps_by_start.sort_unstable_by(|left, right| {
            sleeps[*left]
                .start
                .cmp(&sleeps[*right].start)
                .then_with(|| {
                    item_string(&sleeps[*left].value, "/owner_date")
                        .cmp(item_string(&sleeps[*right].value, "/owner_date"))
                })
                .then_with(|| {
                    item_string(&sleeps[*left].value, "/session_id")
                        .cmp(item_string(&sleeps[*right].value, "/session_id"))
                })
        });
        for workout in workouts {
            let preceding_position =
                sleeps_by_end.partition_point(|index| sleeps[*index].end <= workout.start);
            let preceding = preceding_position
                .checked_sub(1)
                .map(|position| &sleeps[sleeps_by_end[position]])
                .and_then(|sleep| {
                    let distance = workout.start.signed_duration_since(sleep.end).num_seconds();
                    (distance <= 36 * 3_600).then_some((distance, &sleep.value))
                });
            let following_position =
                sleeps_by_start.partition_point(|index| sleeps[*index].start < workout.end);
            let following = sleeps_by_start
                .get(following_position)
                .map(|index| &sleeps[*index])
                .and_then(|sleep| {
                    let distance = sleep.start.signed_duration_since(workout.end).num_seconds();
                    (distance <= 36 * 3_600).then_some((distance, &sleep.value))
                });
            let status = match (preceding, following) {
                (Some(_), Some(_)) => "complete",
                (Some(_), None) | (None, Some(_)) => "partial",
                (None, None) => "unavailable",
            };
            let workout_id = workout
                .value
                .get("workout_id")
                .and_then(Value::as_str)
                .ok_or_else(invalid_snapshot)?;
            let identity = format!(
                "{workout_id}\0{}\0{}",
                preceding
                    .and_then(|value| value.1.get("session_id"))
                    .and_then(Value::as_str)
                    .unwrap_or(""),
                following
                    .and_then(|value| value.1.get("session_id"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
            );
            let alignment_id = format!("alignment:{}", hex(&Sha256::digest(identity.as_bytes())));
            let mut projected_workout = workout.value;
            if spec.detail == QueryDetailLevel::Summary {
                projected_workout["details"] = json!({});
            }
            push_candidate(
                &mut output.candidates,
                json!({
                    "type": "workout_sleep_alignment",
                    "workout_sleep_alignment": {
                        "alignment_id": alignment_id,
                        "workout": projected_workout,
                        "preceding_sleep": preceding.map(|value| value.1),
                        "following_sleep": following.map(|value| value.1),
                        "seconds_from_preceding_sleep": preceding.map(|value| value.0),
                        "seconds_until_following_sleep": following.map(|value| value.0),
                        "physiology_sample_count": 0,
                        "status": status,
                        "evidence": workout.evidence,
                        "limitations": [{
                            "code":"temporal_alignment_only",
                            "message":"Workout and sleep times are aligned deterministically; this is not evidence that either caused a change in the other."
                        }]
                    }
                }),
            )?;
            output.coverage_value_days.insert(workout.owner_date);
        }
        output.candidates.sort_by(|left, right| {
            item_string(left, "/workout_sleep_alignment/workout/start")
                .cmp(item_string(right, "/workout_sleep_alignment/workout/start"))
        });
        output.metadata = Some(json!({
            "aligned_workout_count": output.candidates.len(),
            "physiology_sample_count": 0
        }));
        Ok(output)
    }

    fn scan_days(
        &self,
        context: &CallContext,
        owner: &OwnerCorpus,
        manifest: &Manifest,
        mut visit: impl FnMut(&str, &Value) -> Result<(), HostedError>,
    ) -> Result<(), HostedError> {
        if manifest.days.len() > MAX_SCAN_DAYS {
            return Err(scan_limit_error());
        }
        let mut scanned_bytes = 0_usize;
        for (owner_date, metadata) in &manifest.days {
            if context.cancellation.is_cancelled() {
                return Err(query_error(
                    "healthmd_request_cancelled",
                    "The hosted query was cancelled.",
                ));
            }
            scanned_bytes = scanned_bytes
                .checked_add(metadata.size_bytes as usize)
                .ok_or_else(scan_limit_error)?;
            if scanned_bytes > MAX_SCAN_BYTES {
                return Err(scan_limit_error());
            }
            let consent = manifest.consent.as_ref().ok_or_else(invalid_snapshot)?;
            let mut day = self.read_day(owner, owner_date, metadata, consent)?;
            if !context.caller.has_scope("health.detail.read") {
                project_summary_day(&mut day)?;
            }
            visit(owner_date, &day)?;
        }
        Ok(())
    }
}

pub(super) fn project_summary_day(day: &mut Value) -> Result<(), HostedError> {
    let day = day.as_object_mut().ok_or_else(invalid_snapshot)?;
    for evidence in day
        .get_mut("evidence")
        .and_then(Value::as_array_mut)
        .ok_or_else(invalid_snapshot)?
    {
        let evidence = evidence.as_object_mut().ok_or_else(invalid_snapshot)?;
        evidence.remove("value");
        evidence.remove("note");
    }
    for workout in day
        .get_mut("workouts")
        .and_then(Value::as_array_mut)
        .ok_or_else(invalid_snapshot)?
    {
        let workout = workout.as_object_mut().ok_or_else(invalid_snapshot)?;
        workout.insert("details".to_owned(), Value::Object(Map::new()));
    }
    for session in day
        .get_mut("sleep_sessions")
        .and_then(Value::as_array_mut)
        .ok_or_else(invalid_snapshot)?
    {
        let session = session.as_object_mut().ok_or_else(invalid_snapshot)?;
        session.insert("stage_intervals".to_owned(), Value::Array(Vec::new()));
    }
    Ok(())
}

fn parse_query(
    request: &QueryPageRequest,
    consent: &super::models::HostedConsentRequest,
) -> Result<QuerySpec, HostedError> {
    let query = request.query.as_object().ok_or_else(invalid_query)?;
    if query.get("schema").and_then(Value::as_str) != Some("healthmd.query_request")
        || query.get("schema_version").and_then(Value::as_u64) != Some(1)
    {
        return Err(query_error(
            "healthmd_query_schema_unsupported",
            "The query request schema is unsupported.",
        ));
    }
    if request.detail_level == QueryDetailLevel::Lossless
        && consent.maximum_detail != HostedConsentDetail::Lossless
    {
        return Err(query_error(
            "healthmd_consent_violation",
            "The query detail exceeds the active consent policy.",
        ));
    }
    let metrics_object = query
        .get("metrics")
        .and_then(Value::as_object)
        .ok_or_else(invalid_query)?;
    let metrics = match metrics_object.get("type").and_then(Value::as_str) {
        Some("all_available") => consent.allowed_metric_ids.clone(),
        Some("explicit") => {
            let values = metrics_object
                .get("metric_ids")
                .and_then(Value::as_array)
                .ok_or_else(invalid_query)?;
            if values.is_empty() || values.len() > 512 {
                return Err(invalid_query());
            }
            values
                .iter()
                .map(|value| value.as_str().map(str::to_owned).ok_or_else(invalid_query))
                .collect::<Result<BTreeSet<_>, _>>()?
        }
        _ => return Err(invalid_query()),
    };
    if !metrics.is_subset(&consent.allowed_metric_ids) {
        return Err(query_error(
            "healthmd_consent_violation",
            "The query exceeds the active metric consent.",
        ));
    }
    let sources = parse_sources(query.get("sources"), consent)?;
    let dates = parse_dates(query.get("dates"))?;
    let operation_value = query.get("operation").cloned().ok_or_else(invalid_query)?;
    let operation = operation_value
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(invalid_query)?
        .to_owned();
    if matches!(
        operation.as_str(),
        "workout_listing" | "workout_sleep_alignment"
    ) && !consent.allowed_metric_ids.contains("workouts")
    {
        return Err(query_error(
            "healthmd_consent_violation",
            "Workout access is not authorized by active consent.",
        ));
    }
    if matches!(
        operation.as_str(),
        "sleep_session_listing" | "workout_sleep_alignment"
    ) && (!consent.allowed_metric_ids.contains("sleep_total")
        || !metrics.contains("sleep_total"))
    {
        return Err(query_error(
            "healthmd_consent_violation",
            "Sleep-session access requires sleep_total consent and selection.",
        ));
    }
    if operation == "source_record_listing" && request.detail_level != QueryDetailLevel::Lossless {
        return Err(query_error(
            "healthmd_detail_scope_required",
            "Source-record listing requires lossless detail authorization.",
        ));
    }
    if operation == "derive_packet"
        && operation_value
            .get("detail_ids")
            .and_then(Value::as_array)
            .is_some_and(|values| !values.is_empty())
        && request.detail_level != QueryDetailLevel::Lossless
    {
        return Err(query_error(
            "healthmd_detail_scope_required",
            "Packet detail fields require lossless detail authorization.",
        ));
    }
    let page = query
        .get("page")
        .and_then(Value::as_object)
        .ok_or_else(invalid_query)?;
    let max_items = page
        .get("max_items")
        .and_then(Value::as_u64)
        .ok_or_else(invalid_query)? as usize;
    let max_bytes = page
        .get("max_bytes")
        .and_then(Value::as_u64)
        .ok_or_else(invalid_query)? as usize;
    if max_items == 0 || max_items > MAX_PAGE_ITEMS || max_bytes == 0 || max_bytes > MAX_PAGE_BYTES
    {
        return Err(invalid_query());
    }
    let cursor = match page.get("cursor") {
        None | Some(Value::Null) => None,
        Some(Value::String(value)) if value.len() <= 2_048 => Some(value.clone()),
        Some(_) => return Err(invalid_query()),
    };
    Ok(QuerySpec {
        metrics,
        sources,
        dates,
        operation,
        operation_value,
        max_items,
        max_bytes,
        cursor,
        detail: request.detail_level,
    })
}

fn parse_sources(
    value: Option<&Value>,
    consent: &super::models::HostedConsentRequest,
) -> Result<SourceSelection, HostedError> {
    let Some(object) = value.and_then(Value::as_object) else {
        return Ok(SourceSelection::All);
    };
    match object.get("type").and_then(Value::as_str) {
        Some("all_available") => Ok(SourceSelection::All),
        Some("explicit") => {
            let source_ids = string_set(object.get("source_ids"), 512)?;
            let provider_ids = string_set(object.get("provider_ids"), 512)?;
            if !source_ids.is_subset(&consent.allowed_source_ids)
                || !provider_ids.is_subset(&consent.allowed_provider_ids)
            {
                return Err(query_error(
                    "healthmd_consent_violation",
                    "The query exceeds active source consent.",
                ));
            }
            Ok(SourceSelection::Explicit {
                source_ids,
                provider_ids,
            })
        }
        _ => Err(invalid_query()),
    }
}

fn parse_dates(value: Option<&Value>) -> Result<DateSelection, HostedError> {
    let object = value.and_then(Value::as_object).ok_or_else(invalid_query)?;
    match object.get("type").and_then(Value::as_str) {
        Some("all_available") => Ok(DateSelection::All),
        Some("exact") => {
            let range = parse_range(object.get("range"))?;
            Ok(DateSelection::Exact {
                start: range.start,
                end: range.end,
            })
        }
        _ => Err(invalid_query()),
    }
}

#[derive(Clone)]
struct DateRange {
    start: String,
    end: String,
}

impl DateRange {
    fn contains(&self, date: &str) -> bool {
        date >= self.start.as_str() && date <= self.end.as_str()
    }

    fn to_json(&self) -> Value {
        json!({"start_date":self.start,"end_date":self.end})
    }
}

impl DateSelection {
    fn contains(&self, date: &str) -> bool {
        match self {
            Self::All => true,
            Self::Exact { start, end } => date >= start.as_str() && date <= end.as_str(),
        }
    }

    fn contains_range(&self, range: &DateRange) -> bool {
        match self {
            Self::All => true,
            Self::Exact { start, end } => {
                range.start.as_str() >= start.as_str() && range.end.as_str() <= end.as_str()
            }
        }
    }

    fn contains_or_adjacent(&self, date: &str, radius: i64) -> Result<bool, HostedError> {
        match self {
            Self::All => Ok(true),
            Self::Exact { start, end } => {
                let start = parse_date(start)? - Duration::days(radius);
                let end = parse_date(end)? + Duration::days(radius);
                let date = parse_date(date)?;
                Ok(date >= start && date <= end)
            }
        }
    }
}

fn parse_range(value: Option<&Value>) -> Result<DateRange, HostedError> {
    let object = value.and_then(Value::as_object).ok_or_else(invalid_query)?;
    let start = object
        .get("start_date")
        .and_then(Value::as_str)
        .ok_or_else(invalid_query)?;
    let end = object
        .get("end_date")
        .and_then(Value::as_str)
        .ok_or_else(invalid_query)?;
    parse_date(start)?;
    parse_date(end)?;
    if start > end {
        return Err(invalid_query());
    }
    Ok(DateRange {
        start: start.to_owned(),
        end: end.to_owned(),
    })
}

fn parse_date(value: &str) -> Result<NaiveDate, HostedError> {
    if value.len() != 10 {
        return Err(invalid_query());
    }
    let result = NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| invalid_query())?;
    if result.format("%Y-%m-%d").to_string() != value {
        return Err(invalid_query());
    }
    Ok(result)
}

fn string_set(value: Option<&Value>, maximum: usize) -> Result<BTreeSet<String>, HostedError> {
    let Some(values) = value else {
        return Ok(BTreeSet::new());
    };
    let values = values.as_array().ok_or_else(invalid_query)?;
    if values.len() > maximum {
        return Err(invalid_query());
    }
    values
        .iter()
        .map(|value| value.as_str().map(str::to_owned).ok_or_else(invalid_query))
        .collect()
}

fn build_page(
    context: &CallContext,
    owner: &OwnerCorpus,
    manifest: &Manifest,
    spec: &QuerySpec,
    request_digest: String,
    offset: usize,
    mut evaluation: Evaluation,
) -> Result<Value, HostedError> {
    let maximum = offset
        .checked_add(spec.max_items)
        .ok_or_else(invalid_query)?
        .min(evaluation.candidates.len());
    let coverage = coverage(
        manifest,
        &spec.dates,
        &evaluation.coverage_value_days,
        &evaluation.coverage_missing_statuses,
    )?;
    let sources = source_descriptors(manifest);
    let limitations = normalize_limitations(&mut evaluation.limitations);
    fit_bounded_response(context, offset, maximum, spec.max_bytes, |end| {
        let next_cursor = if end < evaluation.candidates.len() {
            Some(encode_cursor(
                owner,
                CursorPayload {
                    offset: end,
                    request_digest: request_digest.clone(),
                    operation: spec.operation.clone(),
                    detail: detail_name(spec.detail).to_owned(),
                    dataset_revision: manifest.dataset_revision,
                    owner_partition: owner.partition.clone(),
                },
            )?)
        } else {
            None
        };
        let selected = &evaluation.candidates[offset..end];
        let packet = evaluation.packet_kind.as_ref().map(|kind| {
            let packet_id = packet_id(kind, evaluation.packet_range.as_ref(), selected, &coverage);
            json!({
                "schema":"healthmd.evidence_packet",
                "schema_version":1,
                "packet_id":packet_id,
                "kind":kind,
                "range":evaluation.packet_range,
                "facts":selected,
                "coverage":coverage,
                "sources":sources,
                "limitations":limitations,
                "metadata":{"generated_at":Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),"producer":"Health.md"}
            })
        });
        Ok(json!({
            "schema":"healthmd.query_response",
            "schema_version":1,
            "items": if packet.is_some() { json!([]) } else { json!(selected) },
            "packet":packet,
            "coverage":coverage,
            "sources":sources,
            "evidence":response_evidence(selected),
            "next_cursor":next_cursor,
            "limitations":limitations,
            "metadata":evaluation.metadata
        }))
    })
}

fn fit_bounded_response(
    context: &CallContext,
    offset: usize,
    maximum: usize,
    max_bytes: usize,
    mut response_for_end: impl FnMut(usize) -> Result<Value, HostedError>,
) -> Result<Value, HostedError> {
    let response_too_large = || {
        query_error(
            "healthmd_response_item_too_large",
            "One query result cannot fit within the requested page byte limit.",
        )
    };
    let mut build = |end| {
        if context.cancellation.is_cancelled() {
            return Err(query_error(
                "healthmd_request_cancelled",
                "The hosted query was cancelled.",
            ));
        }
        let response = response_for_end(end)?;
        let size = serde_json::to_vec(&response)
            .map_err(|_| internal_error())?
            .len();
        Ok((response, size))
    };

    // Try the full item-limited page first. If it is too large, response size is monotonic on
    // the remaining range and a binary search takes at most eleven total attempts for the
    // protocol's 1,000-item maximum instead of repeatedly cloning and serializing every prefix.
    let (full, full_size) = build(maximum)?;
    if full_size <= max_bytes {
        return Ok(full);
    }
    if maximum == offset {
        return Err(response_too_large());
    }

    let mut low = offset + 1;
    let mut high = maximum - 1;
    let mut best = None;
    while low <= high {
        let middle = low + (high - low) / 2;
        let (response, size) = build(middle)?;
        if size <= max_bytes {
            best = Some(response);
            low = middle + 1;
        } else {
            high = middle - 1;
        }
    }
    best.ok_or_else(response_too_large)
}

fn request_digest(query: &Value) -> Result<String, HostedError> {
    let mut request = query.clone();
    if let Some(page) = request.get_mut("page").and_then(Value::as_object_mut) {
        page.remove("cursor");
    }
    let bytes = canonical_bytes(&request)?;
    Ok(hex(&Sha256::digest(bytes)))
}

fn canonical_bytes(value: &Value) -> Result<Vec<u8>, HostedError> {
    fn sorted(value: &Value) -> Value {
        match value {
            Value::Array(values) => Value::Array(values.iter().map(sorted).collect()),
            Value::Object(values) => {
                let mut keys: Vec<_> = values.keys().collect();
                keys.sort_unstable();
                let mut result = Map::new();
                for key in keys {
                    result.insert(key.clone(), sorted(&values[key]));
                }
                Value::Object(result)
            }
            value => value.clone(),
        }
    }
    serde_json::to_vec(&sorted(value)).map_err(|_| invalid_query())
}

fn encode_cursor(owner: &OwnerCorpus, payload: CursorPayload) -> Result<String, HostedError> {
    let nonce: [u8; 12] = rand::random();
    let plaintext = serde_json::to_vec(&payload).map_err(|_| internal_error())?;
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&owner.key));
    let aad = format!("healthmd.hosted.cursor/1/{}", owner.partition);
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &plaintext,
                aad: aad.as_bytes(),
            },
        )
        .map_err(|_| internal_error())?;
    let mut bytes = Vec::with_capacity(12 + ciphertext.len());
    bytes.extend_from_slice(&nonce);
    bytes.extend_from_slice(&ciphertext);
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

fn decode_cursor(
    owner: &OwnerCorpus,
    encoded: &str,
    request_digest: &str,
    operation: &str,
    detail: QueryDetailLevel,
    revision: u64,
) -> Result<usize, HostedError> {
    let bytes = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|_| invalid_cursor())?;
    if bytes.len() < 12 + 16 || bytes.len() > 2_048 {
        return Err(invalid_cursor());
    }
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&owner.key));
    let aad = format!("healthmd.hosted.cursor/1/{}", owner.partition);
    let plaintext = cipher
        .decrypt(
            Nonce::from_slice(&bytes[..12]),
            Payload {
                msg: &bytes[12..],
                aad: aad.as_bytes(),
            },
        )
        .map_err(|_| invalid_cursor())?;
    let payload: CursorPayload =
        serde_json::from_slice(&plaintext).map_err(|_| invalid_cursor())?;
    if payload.owner_partition != owner.partition
        || payload.request_digest != request_digest
        || payload.operation != operation
        || payload.detail != detail_name(detail)
    {
        return Err(query_error(
            "healthmd_cursor_mismatch",
            "The query cursor does not match this request or caller.",
        ));
    }
    if payload.dataset_revision != revision {
        return Err(query_error(
            "healthmd_cursor_stale",
            "The synchronized dataset changed after this cursor was issued.",
        ));
    }
    Ok(payload.offset)
}

fn detail_name(detail: QueryDetailLevel) -> &'static str {
    match detail {
        QueryDetailLevel::Summary => "summary",
        QueryDetailLevel::Lossless => "lossless",
    }
}

fn evidence_index(day: &Value) -> BTreeMap<String, Value> {
    day.get("evidence")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|value| {
            value
                .pointer("/reference/evidence_id")
                .and_then(Value::as_str)
                .map(|id| (id.to_owned(), value.clone()))
        })
        .collect()
}

fn references_for(
    record: &Value,
    evidence: &BTreeMap<String, Value>,
    sources: &SourceSelection,
) -> Vec<Value> {
    record
        .get("evidence_ids")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter_map(|id| evidence.get(id))
        .filter(|value| evidence_allowed(value, sources))
        .filter_map(|value| value.get("reference"))
        .cloned()
        .collect()
}

fn record_passes_sources(
    record: &Value,
    evidence: &BTreeMap<String, Value>,
    selection: &SourceSelection,
) -> bool {
    match selection {
        SourceSelection::All => true,
        SourceSelection::Explicit { .. } => record
            .get("evidence_ids")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .filter_map(|id| evidence.get(id))
            .any(|item| evidence_allowed(item, selection)),
    }
}

fn evidence_allowed(evidence: &Value, selection: &SourceSelection) -> bool {
    match selection {
        SourceSelection::All => true,
        SourceSelection::Explicit {
            source_ids,
            provider_ids,
        } => {
            let source = evidence
                .pointer("/reference/source_id")
                .and_then(Value::as_str);
            let provider = evidence
                .pointer("/reference/provider_id")
                .and_then(Value::as_str);
            source.is_some_and(|value| source_ids.contains(value))
                || provider.is_some_and(|value| provider_ids.contains(value))
        }
    }
}

fn evidence_matches_metrics(evidence: &Value, metrics: &BTreeSet<String>) -> bool {
    evidence
        .get("metric_ids")
        .and_then(Value::as_array)
        .is_none_or(|values| {
            values.is_empty()
                || values
                    .iter()
                    .filter_map(Value::as_str)
                    .any(|value| metrics.contains(value))
        })
}

fn day_array<'a>(day: &'a Value, key: &str) -> Result<&'a [Value], HostedError> {
    match day.get(key) {
        None => Ok(&[]),
        Some(Value::Array(values)) => Ok(values),
        Some(_) => Err(invalid_snapshot()),
    }
}

fn day_has_selected_value(
    day: &Value,
    metrics: &BTreeSet<String>,
    sources: &SourceSelection,
) -> Result<bool, HostedError> {
    let evidence = evidence_index(day);
    if day_array(day, "metrics")?.iter().any(|metric| {
        metric
            .get("metric_id")
            .and_then(Value::as_str)
            .is_some_and(|id| metrics.contains(id))
            && metric.get("value").is_some_and(|value| !value.is_null())
            && metric.get("status").and_then(Value::as_str) == Some("available")
            && record_passes_sources(metric, &evidence, sources)
    }) {
        return Ok(true);
    }
    Ok((metrics.contains("workouts")
        && day_array(day, "workouts")?
            .iter()
            .any(|record| record_passes_sources(record, &evidence, sources)))
        || (metrics.contains("sleep_total")
            && day_array(day, "sleep_sessions")?
                .iter()
                .any(|record| record_passes_sources(record, &evidence, sources))))
}

fn selected_metric_missing_status(
    day: &Value,
    metrics: &BTreeSet<String>,
    sources: &SourceSelection,
) -> Result<Option<String>, HostedError> {
    let evidence = evidence_index(day);
    let mut result = None;
    for metric in day_array(day, "metrics")? {
        let id = metric
            .get("metric_id")
            .and_then(Value::as_str)
            .ok_or_else(invalid_snapshot)?;
        if !metrics.contains(id) || !record_passes_sources(metric, &evidence, sources) {
            continue;
        }
        let value = metric.get("value").unwrap_or(&Value::Null);
        let mut status = metric
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("partial");
        if status == "available" && value.is_null() {
            status = "complete_empty";
        }
        if status != "available" || value.is_null() {
            merge_missing_status(&mut result, status);
        }
    }
    Ok(result)
}

fn merge_missing_status(current: &mut Option<String>, candidate: &str) {
    fn rank(status: &str) -> u8 {
        match status {
            "failed" | "cancelled" => 7,
            "partial" => 6,
            "denied" => 5,
            "not_supported" => 4,
            "unavailable" => 3,
            "not_requested" => 2,
            "complete_empty" => 1,
            _ => 0,
        }
    }
    if current
        .as_deref()
        .is_none_or(|status| rank(candidate) > rank(status))
    {
        *current = Some(candidate.to_owned());
    }
}

fn sleep_result(
    session: &Value,
    owner_date: &str,
    day: &Value,
    window: Option<(f64, f64)>,
    evidence: &BTreeMap<String, Value>,
    metrics: &BTreeSet<String>,
    sources: &SourceSelection,
) -> Result<Option<Value>, HostedError> {
    let start = parse_json_timestamp(session.get("start"))?;
    let end = parse_json_timestamp(session.get("end"))?;
    let timezone_name = day
        .get("calendar_timezone")
        .and_then(Value::as_str)
        .ok_or_else(invalid_snapshot)?;
    let timezone: Tz = timezone_name.parse().map_err(|_| invalid_snapshot())?;
    let (calendar_dates, local_start, local_end) = sleep_local_metadata(start, end, timezone)?;
    let requested_start =
        start + Duration::milliseconds((window.map_or(0.0, |value| value.0) * 1_000.0) as i64);
    let requested_end = window.map_or(end, |value| {
        requested_start + Duration::milliseconds((value.1 * 1_000.0) as i64)
    });
    let analysis_start = start.max(requested_start);
    let analysis_end = end.min(requested_end);
    if analysis_end <= analysis_start {
        return Ok(None);
    }
    let source_stage_intervals = session
        .get("stage_intervals")
        .and_then(Value::as_array)
        .ok_or_else(invalid_snapshot)?;
    let has_source_intervals = !source_stage_intervals.is_empty();
    let mut stage_intervals: StageIntervals = BTreeMap::new();
    let mut structural_intervals = Vec::new();
    let mut structural_asleep_intervals = Vec::new();
    for interval in source_stage_intervals {
        let stage = interval
            .get("stage")
            .and_then(Value::as_str)
            .ok_or_else(invalid_snapshot)?;
        let normalized = normalized_stage(stage);
        let interval_start = parse_json_timestamp(interval.get("start"))?.max(analysis_start);
        let interval_end = parse_json_timestamp(interval.get("end"))?.min(analysis_end);
        if interval_end <= interval_start {
            continue;
        }
        if metrics.contains("sleep_total") {
            structural_intervals.push((interval_start, interval_end));
            if matches!(
                normalized,
                "deep" | "rem" | "core" | "unspecified" | "asleep_total"
            ) {
                structural_asleep_intervals.push((interval_start, interval_end));
            }
        }
        if stage_is_selected(stage, metrics) {
            stage_intervals
                .entry(normalized.to_owned())
                .or_default()
                .push((interval_start, interval_end));
        }
    }
    let mut stage_totals: BTreeMap<String, f64> = stage_intervals
        .iter()
        .map(|(stage, values)| (stage.clone(), union_seconds(values)))
        .collect();
    if !has_source_intervals && window.is_none() {
        for (stage, value) in session
            .get("aggregate_stage_durations_seconds")
            .and_then(Value::as_object)
            .into_iter()
            .flat_map(Map::iter)
        {
            if stage_is_selected(stage, metrics) {
                if let Some(value) = value
                    .as_f64()
                    .filter(|value| value.is_finite() && *value >= 0.0)
                {
                    stage_totals.insert(normalized_stage(stage).to_owned(), value);
                }
            }
        }
    }
    let elapsed = analysis_end
        .signed_duration_since(analysis_start)
        .to_std()
        .map_err(|_| invalid_snapshot())?
        .as_secs_f64();
    let awake = stage_totals.get("awake").copied().unwrap_or(0.0);
    let (observed, asleep) = if has_source_intervals {
        (
            union_seconds(&structural_intervals).min(elapsed),
            union_seconds(&structural_asleep_intervals).min(elapsed),
        )
    } else if window.is_none() {
        let asleep = stage_totals
            .get("asleep_total")
            .copied()
            .unwrap_or_else(|| {
                ["deep", "rem", "core", "unspecified"]
                    .iter()
                    .filter_map(|stage| stage_totals.get(*stage))
                    .sum()
            });
        // Aggregate totals establish values and the session boundary but do not identify which
        // intervals were observed. Match the native evaluator by preserving asleep/awake totals
        // without claiming interval-level coverage.
        (0.0, asleep.min(elapsed))
    } else {
        (0.0, 0.0)
    };
    let timestamp =
        |value: DateTime<Utc>| value.to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    let mut limitations = session
        .get("limitations")
        .cloned()
        .unwrap_or_else(|| json!([]));
    if window.is_some()
        && session
            .get("stage_intervals")
            .and_then(Value::as_array)
            .is_none_or(Vec::is_empty)
    {
        let Some(values) = limitations.as_array_mut() else {
            return Err(invalid_snapshot());
        };
        values.push(json!({
            "code":"sleep_window_stage_breakdown_unavailable",
            "message":"A fixed session-relative window requires interval-level sleep stages; aggregate totals were not apportioned."
        }));
    }
    Ok(Some(json!({
        "session_id": session.get("session_id"),
        "owner_date": owner_date,
        "calendar_dates": calendar_dates,
        "classification": session.get("classification"),
        "completeness": session.get("completeness"),
        "start": session.get("start"),
        "end": session.get("end"),
        "local_start": local_start,
        "local_end": local_end,
        "calendar_timezone": timezone_name,
        "analysis_start": timestamp(analysis_start),
        "analysis_end": timestamp(analysis_end),
        "requested_window": window.map(|value| json!({"start_offset_seconds":value.0,"duration_seconds":value.1})),
        "elapsed_duration_seconds": elapsed,
        "observed_duration_seconds": observed.min(elapsed),
        "untracked_duration_seconds": (elapsed-observed).max(0.0),
        "asleep_duration_seconds": asleep,
        "awake_duration_seconds": awake,
        "stage_durations_seconds": stage_totals,
        "physiology": [],
        "evidence": references_for(session, evidence, sources),
        "limitations": limitations
    })))
}

fn sleep_local_metadata(
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    timezone: Tz,
) -> Result<(Vec<String>, String, String), HostedError> {
    if end <= start {
        return Err(invalid_snapshot());
    }
    let local_start = start.with_timezone(&timezone);
    let local_end = end.with_timezone(&timezone);
    let mut date = local_start.date_naive();
    let final_date = end
        .checked_sub_signed(Duration::milliseconds(1))
        .ok_or_else(invalid_snapshot)?
        .with_timezone(&timezone)
        .date_naive();
    let mut dates = Vec::with_capacity(2);
    loop {
        if dates.len() >= 8 || date > final_date {
            return Err(invalid_snapshot());
        }
        dates.push(date.format("%Y-%m-%d").to_string());
        if date == final_date {
            break;
        }
        date = date.succ_opt().ok_or_else(invalid_snapshot)?;
    }
    Ok((
        dates,
        local_start.to_rfc3339_opts(SecondsFormat::Secs, true),
        local_end.to_rfc3339_opts(SecondsFormat::Secs, true),
    ))
}

fn parse_window(value: Option<&Value>) -> Result<Option<(f64, f64)>, HostedError> {
    let Some(value) = value else { return Ok(None) };
    let object = value.as_object().ok_or_else(invalid_query)?;
    let start = object
        .get("start_offset_seconds")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let duration = object
        .get("duration_seconds")
        .and_then(Value::as_f64)
        .ok_or_else(invalid_query)?;
    if !start.is_finite()
        || !duration.is_finite()
        || !(0.0..=86_400.0).contains(&start)
        || duration <= 0.0
        || duration > 86_400.0
    {
        return Err(invalid_query());
    }
    Ok(Some((start, duration)))
}

fn stage_is_selected(stage: &str, metrics: &BTreeSet<String>) -> bool {
    let metric = match normalized_stage(stage) {
        "deep" => "sleep_deep",
        "rem" => "sleep_rem",
        "core" => "sleep_core",
        "awake" => "sleep_awake",
        "in_bed" => "sleep_in_bed",
        _ => "sleep_total",
    };
    metrics.contains(metric)
}

fn normalized_stage(stage: &str) -> &str {
    match stage {
        "inBed" | "inbed" => "in_bed",
        "asleepUnspecified" | "asleep_unspecified" => "unspecified",
        value => value,
    }
}

fn union_seconds(intervals: &[(DateTime<Utc>, DateTime<Utc>)]) -> f64 {
    let mut intervals: Vec<_> = intervals
        .iter()
        .copied()
        .filter(|value| value.1 > value.0)
        .collect();
    intervals.sort_by_key(|value| (value.0, value.1));
    let Some(mut current) = intervals.first().copied() else {
        return 0.0;
    };
    let mut total = 0_i64;
    for interval in intervals.into_iter().skip(1) {
        if interval.0 <= current.1 {
            current.1 = current.1.max(interval.1);
        } else {
            total += current
                .1
                .signed_duration_since(current.0)
                .num_milliseconds();
            current = interval;
        }
    }
    total += current
        .1
        .signed_duration_since(current.0)
        .num_milliseconds();
    total as f64 / 1_000.0
}

fn parse_json_timestamp(value: Option<&Value>) -> Result<DateTime<Utc>, HostedError> {
    DateTime::parse_from_rfc3339(value.and_then(Value::as_str).ok_or_else(invalid_snapshot)?)
        .map(|value| value.with_timezone(&Utc))
        .map_err(|_| invalid_snapshot())
}

fn aggregate(
    values: &[(String, Value)],
    kind: &str,
    expected_unit: Option<&Value>,
) -> Result<Value, HostedError> {
    if values.is_empty() {
        return Ok(Value::Null);
    }
    if kind == "latest" {
        return Ok(values
            .iter()
            .max_by_key(|value| &value.0)
            .map_or(Value::Null, |value| value.1.clone()));
    }
    if kind == "count" {
        return Ok(json!({"type":"count","value":values.len()}));
    }
    if values
        .iter()
        .all(|(_, value)| value.get("type").and_then(Value::as_str) == Some("count"))
    {
        if expected_unit
            .and_then(Value::as_str)
            .is_some_and(|expected| expected != "count")
        {
            return Err(invalid_aggregation());
        }
        let counts: Vec<i64> = values
            .iter()
            .map(|(_, value)| {
                value
                    .get("value")
                    .and_then(Value::as_i64)
                    .ok_or_else(invalid_aggregation)
            })
            .collect::<Result<_, _>>()?;
        return match kind {
            "sum" | "duration_sum" => {
                let total = counts.iter().try_fold(0_i128, |total, value| {
                    total
                        .checked_add(i128::from(*value))
                        .ok_or_else(invalid_aggregation)
                })?;
                let total = i64::try_from(total).map_err(|_| invalid_aggregation())?;
                Ok(json!({"type":"count","value":total}))
            }
            "average" => {
                let total = counts.iter().try_fold(0_i128, |total, value| {
                    total
                        .checked_add(i128::from(*value))
                        .ok_or_else(invalid_aggregation)
                })?;
                let divisor = i128::try_from(counts.len()).map_err(|_| invalid_aggregation())?;
                if total % divisor == 0 {
                    let average =
                        i64::try_from(total / divisor).map_err(|_| invalid_aggregation())?;
                    Ok(json!({"type":"count","value":average}))
                } else {
                    let average = total as f64 / divisor as f64;
                    if !average.is_finite() {
                        return Err(invalid_aggregation());
                    }
                    Ok(json!({"type":"quantity","value":average,"unit":"count"}))
                }
            }
            "minimum" => counts
                .iter()
                .min()
                .map(|value| json!({"type":"count","value":value}))
                .ok_or_else(invalid_aggregation),
            "maximum" => counts
                .iter()
                .max()
                .map(|value| json!({"type":"count","value":value}))
                .ok_or_else(invalid_aggregation),
            _ => Err(invalid_aggregation()),
        };
    }
    let mut numbers = Vec::new();
    let mut value_type = None;
    let mut unit = None;
    for (_, value) in values {
        let object = value.as_object().ok_or_else(invalid_aggregation)?;
        let current_type = object
            .get("type")
            .and_then(Value::as_str)
            .ok_or_else(invalid_aggregation)?;
        let number = match current_type {
            "quantity" | "count" => object.get("value").and_then(Value::as_f64),
            "duration" => object.get("seconds").and_then(Value::as_f64),
            _ => None,
        }
        .filter(|value| value.is_finite())
        .ok_or_else(invalid_aggregation)?;
        let current_unit = match current_type {
            "quantity" => object.get("unit").and_then(Value::as_str).unwrap_or(""),
            "duration" => "s",
            "count" => "count",
            _ => unreachable!(),
        };
        if value_type.is_some_and(|value| value != current_type)
            || unit.is_some_and(|value| value != current_unit)
        {
            return Err(invalid_aggregation());
        }
        value_type = Some(current_type);
        unit = Some(current_unit);
        numbers.push(number);
    }
    if expected_unit
        .and_then(Value::as_str)
        .is_some_and(|expected| Some(expected) != unit)
    {
        return Err(invalid_aggregation());
    }
    let result = match kind {
        "sum" | "duration_sum" => numbers.iter().sum(),
        "average" => numbers.iter().sum::<f64>() / numbers.len() as f64,
        "minimum" => numbers
            .iter()
            .copied()
            .reduce(f64::min)
            .ok_or_else(invalid_aggregation)?,
        "maximum" => numbers
            .iter()
            .copied()
            .reduce(f64::max)
            .ok_or_else(invalid_aggregation)?,
        _ => return Err(invalid_aggregation()),
    };
    if !result.is_finite() {
        return Err(invalid_aggregation());
    }
    Ok(match value_type.ok_or_else(invalid_aggregation)? {
        "duration" => json!({"type":"duration","seconds":result}),
        "count"
            if result.fract() == 0.0 && result >= i64::MIN as f64 && result <= i64::MAX as f64 =>
        {
            json!({"type":"count","value":result as i64})
        }
        "count" => json!({"type":"quantity","value":result,"unit":"count"}),
        _ => json!({"type":"quantity","value":result,"unit":unit.unwrap_or("")}),
    })
}

fn comparison_delta(
    first: &Value,
    second: &Value,
) -> Result<(Value, Value, &'static str), HostedError> {
    fn numeric(value: &Value) -> Option<(f64, &'static str, &str)> {
        let value_type = value.get("type").and_then(Value::as_str)?;
        match value_type {
            "duration" => Some((
                value.get("seconds").and_then(Value::as_f64)?,
                "duration",
                "s",
            )),
            "count" => Some((
                value.get("value").and_then(Value::as_f64)?,
                "numeric",
                "count",
            )),
            "quantity" => Some((
                value.get("value").and_then(Value::as_f64)?,
                "numeric",
                value.get("unit").and_then(Value::as_str)?,
            )),
            _ => None,
        }
    }
    let (
        Some((first_number, first_kind, first_unit)),
        Some((second_number, second_kind, second_unit)),
    ) = (numeric(first), numeric(second))
    else {
        return Ok((Value::Null, Value::Null, "not_comparable"));
    };
    if first_kind != second_kind || first_unit != second_unit {
        return Err(invalid_aggregation());
    }
    if !first_number.is_finite() || !second_number.is_finite() {
        return Err(invalid_aggregation());
    }
    let exact_count_delta = if first.get("type").and_then(Value::as_str) == Some("count")
        && second.get("type").and_then(Value::as_str) == Some("count")
    {
        let first = first
            .get("value")
            .and_then(Value::as_i64)
            .ok_or_else(invalid_aggregation)?;
        let second = second
            .get("value")
            .and_then(Value::as_i64)
            .ok_or_else(invalid_aggregation)?;
        Some(second.checked_sub(first).ok_or_else(invalid_aggregation)?)
    } else {
        None
    };
    let delta = exact_count_delta.map_or(second_number - first_number, |value| value as f64);
    if !delta.is_finite() {
        return Err(invalid_aggregation());
    }
    let absolute = match second.get("type").and_then(Value::as_str) {
        Some("duration") => json!({"type":"duration","seconds":delta}),
        Some("count") => {
            json!({"type":"count","value":exact_count_delta.ok_or_else(invalid_aggregation)?})
        }
        _ => {
            json!({"type":"quantity","value":delta,"unit":second.get("unit").and_then(Value::as_str).unwrap_or("")})
        }
    };
    let percent = if first_number == 0.0 {
        Value::Null
    } else {
        let percent = (delta / first_number.abs()) * 100.0;
        if !percent.is_finite() {
            return Err(invalid_aggregation());
        }
        json!(percent)
    };
    let direction = if delta == 0.0 {
        "unchanged"
    } else if delta > 0.0 {
        "increased"
    } else {
        "decreased"
    };
    Ok((absolute, percent, direction))
}

fn coverage(
    manifest: &Manifest,
    dates: &DateSelection,
    value_days: &BTreeSet<String>,
    missing_statuses: &BTreeMap<String, String>,
) -> Result<Value, HostedError> {
    let requested_dates: Vec<String> = match dates {
        DateSelection::All => manifest.days.keys().cloned().collect(),
        DateSelection::Exact { start, end } => {
            let mut date = parse_date(start)?;
            let end = parse_date(end)?;
            let mut values = Vec::new();
            while date <= end {
                if values.len() >= MAX_SCAN_DAYS {
                    return Err(scan_limit_error());
                }
                values.push(date.format("%Y-%m-%d").to_string());
                date = date.succ_opt().ok_or_else(invalid_query)?;
            }
            values
        }
    };

    let mut synchronized_dates = Vec::new();
    let mut missing_ranges: Vec<(String, String, String, Option<&'static str>)> = Vec::new();
    let mut all_missing_complete_empty = true;
    for date in &requested_dates {
        let metadata = manifest.days.get(date);
        if metadata.is_some() {
            synchronized_dates.push(date.clone());
        }
        if value_days.contains(date) {
            continue;
        }
        let (status, reason) = match metadata {
            None => (
                "not_synchronized".to_owned(),
                Some("No synchronized snapshot is retained for this owner date."),
            ),
            Some(_) if missing_statuses.contains_key(date) => {
                (missing_statuses[date].clone(), None)
            }
            Some(metadata) if metadata.status == "available" => ("complete_empty".to_owned(), None),
            Some(metadata) => (metadata.status.clone(), None),
        };
        all_missing_complete_empty &= status == "complete_empty";
        if let Some((_, previous_end, previous_status, previous_reason)) = missing_ranges.last_mut()
        {
            let adjacent = parse_date(previous_end)?
                .succ_opt()
                .is_some_and(|value| value.format("%Y-%m-%d").to_string() == *date);
            if adjacent && *previous_status == status && *previous_reason == reason {
                *previous_end = date.clone();
                continue;
            }
        }
        missing_ranges.push((date.clone(), date.clone(), status, reason));
    }
    let missing_count = missing_ranges.len();
    let missing: Vec<Value> = missing_ranges
        .iter()
        .take(MAX_MISSING_INTERVALS)
        .map(|(start, end, status, reason)| {
            json!({
                "range":{"start_date":start,"end_date":end},
                "status":status,
                "reason":reason
            })
        })
        .collect();
    let selected_value_days = value_days
        .iter()
        .filter(|date| dates.contains(date))
        .count();
    let status = if requested_dates.is_empty() || synchronized_dates.is_empty() {
        "not_synchronized"
    } else if missing_count == 0 {
        "available"
    } else if selected_value_days == 0
        && synchronized_dates.len() == requested_dates.len()
        && all_missing_complete_empty
    {
        "complete_empty"
    } else {
        "partial"
    };
    let available_range = synchronized_dates
        .first()
        .zip(synchronized_dates.last())
        .map(|(start, end)| json!({"start_date":start,"end_date":end}));
    Ok(json!({
        "requested_range": selected_range_json(dates, manifest),
        "available_range": available_range,
        "status": status,
        "days_considered": requested_dates.len(),
        "days_with_values": selected_value_days,
        "missing": missing,
        "missing_interval_count": if missing_count > MAX_MISSING_INTERVALS { Some(missing_count) } else { None },
        "missing_truncated": if missing_count > MAX_MISSING_INTERVALS { Some(true) } else { None }
    }))
}

fn coverage_for_ranges(
    manifest: &Manifest,
    first: &DateRange,
    second: &DateRange,
    value_days: &BTreeSet<String>,
) -> Result<Value, HostedError> {
    let dates = DateSelection::Exact {
        start: first.start.clone().min(second.start.clone()),
        end: first.end.clone().max(second.end.clone()),
    };
    coverage(manifest, &dates, value_days, &BTreeMap::new())
}

fn selected_range_json(dates: &DateSelection, manifest: &Manifest) -> Option<Value> {
    match dates {
        DateSelection::Exact { start, end } => Some(json!({"start_date":start,"end_date":end})),
        DateSelection::All => manifest
            .days
            .keys()
            .next()
            .zip(manifest.days.keys().next_back())
            .map(|(start, end)| json!({"start_date":start,"end_date":end})),
    }
}

fn source_descriptors(_manifest: &Manifest) -> Vec<Value> {
    // Sources are also present on every item/evidence reference. Avoid loading every day a second
    // time solely to duplicate descriptors in the bounded envelope.
    Vec::new()
}

fn response_evidence(items: &[Value]) -> Vec<Value> {
    let mut by_id = BTreeMap::new();
    for item in items {
        collect_references(item, &mut by_id);
    }
    by_id.into_values().take(2_048).collect()
}

fn collect_references(value: &Value, output: &mut BTreeMap<String, Value>) {
    match value {
        Value::Array(values) => {
            for value in values {
                collect_references(value, output);
            }
        }
        Value::Object(object) => {
            if let Some(id) = object.get("evidence_id").and_then(Value::as_str) {
                if object.contains_key("locator") && object.contains_key("source") {
                    output
                        .entry(id.to_owned())
                        .or_insert_with(|| Value::Object(object.clone()));
                }
            }
            for value in object.values() {
                collect_references(value, output);
            }
        }
        _ => {}
    }
}

fn packet_id(kind: &str, range: Option<&Value>, facts: &[Value], coverage: &Value) -> String {
    let semantic = json!({
        "schema":"healthmd.evidence_packet",
        "schema_version":1,
        "kind":kind,
        "range":range,
        "facts":facts,
        "coverage":coverage,
        "limitations":[{"code":FACTUAL_CODE,"message":FACTUAL_MESSAGE}]
    });
    let bytes = canonical_bytes(&semantic).unwrap_or_default();
    hex(&Sha256::digest(bytes))
}

fn empty_evaluation() -> Evaluation {
    Evaluation {
        candidates: CandidateBuffer::default(),
        packet_kind: None,
        packet_range: None,
        coverage_value_days: BTreeSet::new(),
        coverage_missing_statuses: BTreeMap::new(),
        limitations: vec![
            json!({"code":FACTUAL_CODE,"message":FACTUAL_MESSAGE}),
            json!({
                "code":"hosted_source_descriptors_item_scoped",
                "message":"Source descriptors are retained on item evidence references rather than repeated in this bounded hosted envelope."
            }),
        ],
        metadata: None,
    }
}

fn reserve_intermediate(
    items: &mut usize,
    bytes: &mut usize,
    additional_bytes: usize,
) -> Result<(), HostedError> {
    *items = items.checked_add(1).ok_or_else(scan_limit_error)?;
    *bytes = bytes
        .checked_add(additional_bytes)
        .ok_or_else(scan_limit_error)?;
    if *items > MAX_CANDIDATES || *bytes > MAX_CANDIDATE_BYTES {
        return Err(scan_limit_error());
    }
    Ok(())
}

fn push_candidate(candidates: &mut CandidateBuffer, candidate: Value) -> Result<(), HostedError> {
    if candidates.len() >= MAX_CANDIDATES {
        return Err(scan_limit_error());
    }
    let size = estimated_json_size(&candidate);
    let new_size = candidates
        .bytes
        .checked_add(size)
        .ok_or_else(scan_limit_error)?;
    if new_size > MAX_CANDIDATE_BYTES {
        return Err(scan_limit_error());
    }
    candidates.values.push(candidate);
    candidates.bytes = new_size;
    Ok(())
}

fn estimated_json_size(value: &Value) -> usize {
    serde_json::to_vec(value).map_or(MAX_PAGE_BYTES + 1, |value| value.len())
}

fn collect_day_limitations(day: &Value, output: &mut Vec<Value>) {
    if let Some(values) = day.get("limitations").and_then(Value::as_array) {
        output.extend(values.iter().take(64).cloned());
    }
}

fn normalize_limitations(values: &mut Vec<Value>) -> Vec<Value> {
    let mut by_key = BTreeMap::new();
    for value in values.drain(..) {
        let key = format!(
            "{}\0{}",
            value.get("code").and_then(Value::as_str).unwrap_or(""),
            value.get("message").and_then(Value::as_str).unwrap_or("")
        );
        by_key.insert(key, value);
    }
    by_key.into_values().take(64).collect()
}

fn item_string<'a>(value: &'a Value, pointer: &str) -> &'a str {
    value.pointer(pointer).and_then(Value::as_str).unwrap_or("")
}

fn operation_object(value: &Value) -> Result<&Map<String, Value>, HostedError> {
    value.as_object().ok_or_else(invalid_query)
}

fn hex(bytes: &[u8]) -> String {
    const TABLE: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(TABLE[(byte >> 4) as usize] as char);
        output.push(TABLE[(byte & 15) as usize] as char);
    }
    output
}

fn query_error(code: &'static str, message: &'static str) -> HostedError {
    HostedError::new(code, message)
}

fn invalid_query() -> HostedError {
    query_error(
        "healthmd_query_invalid",
        "The hosted query request is invalid.",
    )
}

fn invalid_cursor() -> HostedError {
    query_error("healthmd_cursor_invalid", "The query cursor is invalid.")
}

fn invalid_snapshot() -> HostedError {
    query_error(
        "healthmd_hosted_store_corrupt",
        "The encrypted hosted corpus could not be authenticated.",
    )
}

fn invalid_aggregation() -> HostedError {
    query_error(
        "healthmd_aggregation_invalid",
        "The requested aggregation is incompatible with synchronized values.",
    )
}

fn scan_limit_error() -> HostedError {
    query_error(
        "healthmd_query_scan_limit",
        "The hosted query exceeded a bounded scan limit.",
    )
}

fn internal_error() -> HostedError {
    query_error(
        "healthmd_hosted_internal",
        "The hosted data operation could not be completed.",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aggregation_and_comparison_reject_nonfinite_results() {
        let maximum = json!({"type":"quantity","value":f64::MAX,"unit":"count"});
        let values = vec![
            ("2026-01-01".to_owned(), maximum.clone()),
            ("2026-01-02".to_owned(), maximum.clone()),
        ];
        assert_eq!(
            aggregate(&values, "sum", Some(&json!("count")))
                .unwrap_err()
                .code,
            "healthmd_aggregation_invalid"
        );
        let negative = json!({"type":"quantity","value":-f64::MAX,"unit":"count"});
        assert_eq!(
            comparison_delta(&maximum, &negative).unwrap_err().code,
            "healthmd_aggregation_invalid"
        );
        let kilograms = json!({"type":"quantity","value":1.0,"unit":"kg"});
        let pounds = json!({"type":"quantity","value":2.0,"unit":"lb"});
        assert_eq!(
            comparison_delta(&kilograms, &pounds).unwrap_err().code,
            "healthmd_aggregation_invalid"
        );

        let first_count = json!({"type":"count","value":9_007_199_254_740_992_i64});
        let second_count = json!({"type":"count","value":9_007_199_254_740_993_i64});
        assert_eq!(
            comparison_delta(&first_count, &second_count).unwrap().0,
            json!({"type":"count","value":1})
        );
        let minimum_count = json!({"type":"count","value":i64::MIN});
        let maximum_count = json!({"type":"count","value":i64::MAX});
        assert_eq!(
            comparison_delta(&minimum_count, &maximum_count)
                .unwrap_err()
                .code,
            "healthmd_aggregation_invalid"
        );
        let large_average_values = vec![
            ("2026-01-01".to_owned(), maximum_count.clone()),
            ("2026-01-02".to_owned(), maximum_count.clone()),
        ];
        assert_eq!(
            aggregate(&large_average_values, "average", Some(&json!("count"))).unwrap(),
            maximum_count
        );
        let count_values = vec![
            ("2026-01-01".to_owned(), maximum_count),
            ("2026-01-02".to_owned(), json!({"type":"count","value":1})),
        ];
        assert_eq!(
            aggregate(&count_values, "sum", Some(&json!("count")))
                .unwrap_err()
                .code,
            "healthmd_aggregation_invalid"
        );
    }

    #[test]
    fn response_page_search_is_logarithmic_and_cancellable() {
        let context = CallContext {
            caller: crate::backend::CallerIdentity {
                subject: "owner".to_owned(),
                tenant: None,
                issuer: Some("https://issuer.example".to_owned()),
                scopes: BTreeSet::new(),
                mode: crate::backend::CallerMode::OAuth,
            },
            cancellation: tokio_util::sync::CancellationToken::new(),
            session_id: None,
        };
        let mut attempts = 0_usize;
        let response = fit_bounded_response(&context, 0, 1_000, 128, |end| {
            attempts += 1;
            Ok(json!({"items":"x".repeat(end)}))
        })
        .unwrap();
        assert!(serde_json::to_vec(&response).unwrap().len() <= 128);
        assert!(attempts <= 12, "page sizing used {attempts} attempts");
        assert_eq!(
            fit_bounded_response(&context, 0, 1, 16, |end| {
                Ok(json!({"items":"x".repeat(end * 32)}))
            })
            .unwrap_err()
            .code,
            "healthmd_response_item_too_large"
        );

        context.cancellation.cancel();
        assert_eq!(
            fit_bounded_response(&context, 0, 1, 128, |_| Ok(json!({})))
                .unwrap_err()
                .code,
            "healthmd_request_cancelled"
        );
    }

    #[test]
    fn period_ranges_must_be_inside_the_top_level_selection() {
        let selection = DateSelection::Exact {
            start: "2026-01-02".to_owned(),
            end: "2026-01-30".to_owned(),
        };
        assert!(selection.contains_range(&DateRange {
            start: "2026-01-02".to_owned(),
            end: "2026-01-30".to_owned(),
        }));
        assert!(!selection.contains_range(&DateRange {
            start: "2026-01-01".to_owned(),
            end: "2026-01-30".to_owned(),
        }));
    }

    #[test]
    fn alignment_intermediate_accounting_is_bounded() {
        let mut items = MAX_CANDIDATES;
        let mut bytes = 0;
        assert_eq!(
            reserve_intermediate(&mut items, &mut bytes, 1)
                .unwrap_err()
                .code,
            "healthmd_query_scan_limit"
        );
        let mut items = 0;
        let mut bytes = MAX_CANDIDATE_BYTES;
        assert_eq!(
            reserve_intermediate(&mut items, &mut bytes, 1)
                .unwrap_err()
                .code,
            "healthmd_query_scan_limit"
        );
    }
}
