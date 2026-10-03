//! Independent typed-query history observation checks and presentation.
//! This does not alter protocol models, capture coverage, or metric authority.

use std::collections::BTreeSet;

use chrono::{DateTime, NaiveDate};
use serde_json::Value;
use uuid::Uuid;

/// A recognized receipt was malformed or did not match the authenticated query.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidHistoryReceipt;

const MAX_ROWS: usize = 512;
const MAX_BYTES: usize = 256 * 1024;
const ROOT_KEYS: &[&str] = &[
    "schema",
    "schema_version",
    "assessment_id",
    "capture_id",
    "observed_at",
    "capture_completed_at",
    "evidence_method",
    "producer",
    "platform",
    "calendar_identifier",
    "time_zone_identifier",
    "boundary_semantics",
    "boundary_equality_physically_verified",
    "logical_metrics",
    "resolved_metric_ids",
    "logical_sources",
    "resolved_source_ids",
    "resolved_provider_ids",
    "logical_dates",
    "resolved_owner_dates",
    "types",
    "dataset_digest",
    "trusted_peer_installation_id",
    "source_installation_id",
];

fn receipt(response: &Value) -> Option<&Value> {
    response.pointer("/metadata/history_assessment")
}

fn recognized(value: &Value) -> bool {
    value.get("schema").and_then(Value::as_str) == Some("healthmd.history_assessment")
        && value.get("schema_version").and_then(Value::as_u64) == Some(1)
}

/// Validate recognized evidence against the exact query and authenticated peers.
/// Absent means legacy/unassessed. Unknown semantics remain opaque, never full.
/// The encrypted source authenticates this observation, not a permission epoch.
///
/// # Errors
/// Returns a health-free error for malformed recognized evidence or scope/peer mismatch.
pub fn validate_response(
    response: &Value,
    query: &Value,
    trusted_peer: Uuid,
    source: Uuid,
) -> Result<(), InvalidHistoryReceipt> {
    let Some(value) = receipt(response) else {
        return Ok(());
    };
    if !value.is_object() {
        return Err(InvalidHistoryReceipt);
    }
    if !recognized(value) {
        if value.get("schema").and_then(Value::as_str) == Some("healthmd.history_assessment")
            && value
                .get("schema_version")
                .and_then(Value::as_u64)
                .is_none()
        {
            return Err(InvalidHistoryReceipt);
        }
        return Ok(());
    }
    validate_shape(value)?;
    let default_sources = serde_json::json!({"type": "all_available"});
    let expected_sources = query.get("sources").unwrap_or(&default_sources);
    if normalized_selection(&value["logical_metrics"], false)
        != normalized_selection(&query["metrics"], false)
        || normalized_selection(&value["logical_sources"], true)
            != normalized_selection(expected_sources, true)
        || value["logical_dates"] != query["dates"]
        || uuid(&value["trusted_peer_installation_id"]) != Some(trusted_peer)
        || uuid(&value["source_installation_id"]) != Some(source)
    {
        return Err(InvalidHistoryReceipt);
    }
    Ok(())
}

fn only_keys(value: &Value, keys: &[&str]) -> bool {
    value
        .as_object()
        .is_some_and(|object| object.keys().all(|key| keys.contains(&key.as_str())))
}

fn safe_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_.:-".contains(&byte))
}

fn ids(value: &Value) -> Option<BTreeSet<String>> {
    let values = value.as_array()?;
    if values.len() > MAX_ROWS {
        return None;
    }
    let mut result = BTreeSet::new();
    for value in values {
        let value = value.as_str()?;
        if !safe_id(value) || !result.insert(value.to_owned()) {
            return None;
        }
    }
    Some(result)
}

fn uuid(value: &Value) -> Option<Uuid> {
    let text = value.as_str()?;
    if text.len() != 36 {
        return None;
    }
    Uuid::parse_str(text).ok()
}

fn digest(value: &Value) -> bool {
    value.as_str().is_some_and(|text| {
        text.len() == 64
            && text
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    })
}

fn instant(value: &Value) -> bool {
    value.as_str().is_some_and(|text| {
        text.len() == 30
            && text.ends_with('Z')
            && text.as_bytes()[19] == b'.'
            && text.as_bytes()[20..29].iter().all(u8::is_ascii_digit)
            && DateTime::parse_from_rfc3339(text).is_ok()
    })
}

fn owner_date(value: &Value) -> Option<&str> {
    let text = value.as_str()?;
    (text.len() == 10 && NaiveDate::parse_from_str(text, "%Y-%m-%d").is_ok()).then_some(text)
}

fn normalized_selection(value: &Value, sources: bool) -> Option<Value> {
    let type_name = value.get("type")?.as_str()?;
    if type_name == "all_available" {
        return (value.as_object()?.len() == 1).then(|| value.clone());
    }
    if type_name != "explicit" {
        return None;
    }
    if sources {
        if !only_keys(value, &["type", "source_ids", "provider_ids"]) {
            return None;
        }
        let empty = serde_json::json!([]);
        let source_ids = ids(value.get("source_ids").unwrap_or(&empty))?;
        let provider_ids = ids(value.get("provider_ids").unwrap_or(&empty))?;
        Some(
            serde_json::json!({"type": "explicit", "source_ids": source_ids, "provider_ids": provider_ids}),
        )
    } else {
        if !only_keys(value, &["type", "metric_ids"]) {
            return None;
        }
        Some(serde_json::json!({"type": "explicit", "metric_ids": ids(&value["metric_ids"])?}))
    }
}

fn validate_shape(value: &Value) -> Result<(), InvalidHistoryReceipt> {
    if !only_keys(value, ROOT_KEYS)
        || serde_json::to_vec(value)
            .map_err(|_| InvalidHistoryReceipt)?
            .len()
            > MAX_BYTES
        || uuid(&value["assessment_id"]).is_none()
        || uuid(&value["capture_id"]).is_none()
        || uuid(&value["trusted_peer_installation_id"]).is_none()
        || uuid(&value["source_installation_id"]).is_none()
        || !instant(&value["observed_at"])
        || !instant(&value["capture_completed_at"])
        || value["producer"] != "Health.md"
        || value["platform"] != "apple_healthkit"
        || value["calendar_identifier"] != "gregorian"
        || value["boundary_semantics"] != "sample_end_instant"
        || value["boundary_equality_physically_verified"] != false
        || !digest(&value["dataset_digest"])
        || !matches!(
            value["evidence_method"].as_str(),
            Some(
                "HKHealthStore.earliestAuthorizedSampleDate(for:)"
                    | "synthetic_ui_fixture"
                    | "assessment_not_completed"
            )
        )
        || !value["time_zone_identifier"].as_str().is_some_and(|zone| {
            !zone.is_empty()
                && zone.len() <= 128
                && zone
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || b"_/-+:".contains(&byte))
        })
    {
        return Err(InvalidHistoryReceipt);
    }
    let metrics = ids(&value["resolved_metric_ids"])
        .filter(|ids| !ids.is_empty())
        .ok_or(InvalidHistoryReceipt)?;
    let logical_metrics =
        normalized_selection(&value["logical_metrics"], false).ok_or(InvalidHistoryReceipt)?;
    if logical_metrics["type"] == "explicit"
        && ids(&logical_metrics["metric_ids"]) != Some(metrics.clone())
    {
        return Err(InvalidHistoryReceipt);
    }
    validate_sources(value)?;
    validate_dates(value)?;
    validate_types(value, &metrics)
}

fn validate_sources(value: &Value) -> Result<(), InvalidHistoryReceipt> {
    let sources = ids(&value["resolved_source_ids"])
        .filter(|ids| !ids.is_empty())
        .ok_or(InvalidHistoryReceipt)?;
    let supported = BTreeSet::from(["apple_health".to_owned(), "healthmd_summary".to_owned()]);
    if !sources.is_subset(&supported)
        || ids(&value["resolved_provider_ids"]) != Some(BTreeSet::new())
    {
        return Err(InvalidHistoryReceipt);
    }
    let logical =
        normalized_selection(&value["logical_sources"], true).ok_or(InvalidHistoryReceipt)?;
    if logical["type"] == "all_available" {
        if sources != supported {
            return Err(InvalidHistoryReceipt);
        }
    } else if ids(&logical["source_ids"]) != Some(sources)
        || ids(&logical["provider_ids"]) != Some(BTreeSet::new())
    {
        return Err(InvalidHistoryReceipt);
    }
    Ok(())
}

fn validate_dates(value: &Value) -> Result<(), InvalidHistoryReceipt> {
    let resolved = &value["resolved_owner_dates"];
    let first = owner_date(&resolved["first"]).ok_or(InvalidHistoryReceipt)?;
    let last = owner_date(&resolved["last"]).ok_or(InvalidHistoryReceipt)?;
    if !only_keys(resolved, &["count", "digest", "first", "last"])
        || !resolved["count"]
            .as_u64()
            .is_some_and(|count| (1..=366_000).contains(&count))
        || !digest(&resolved["digest"])
        || first > last
    {
        return Err(InvalidHistoryReceipt);
    }
    let logical = &value["logical_dates"];
    if logical["type"] == "all_available" {
        if logical.as_object().is_none_or(|object| object.len() != 1) {
            return Err(InvalidHistoryReceipt);
        }
    } else {
        let range = &logical["range"];
        let start = owner_date(&range["start_date"]).ok_or(InvalidHistoryReceipt)?;
        let end = owner_date(&range["end_date"]).ok_or(InvalidHistoryReceipt)?;
        if logical["type"] != "exact"
            || !only_keys(logical, &["type", "range"])
            || !only_keys(range, &["start_date", "end_date"])
            || start > end
            || first < start
            || last > end
        {
            return Err(InvalidHistoryReceipt);
        }
    }
    Ok(())
}

fn validate_types(value: &Value, metrics: &BTreeSet<String>) -> Result<(), InvalidHistoryReceipt> {
    let rows = value["types"]
        .as_array()
        .filter(|rows| !rows.is_empty() && rows.len() <= MAX_ROWS)
        .ok_or(InvalidHistoryReceipt)?;
    let mut types = BTreeSet::new();
    let mut directly_attributed = BTreeSet::new();
    for row in rows {
        let type_id = row["type_id"]
            .as_str()
            .filter(|id| safe_id(id))
            .ok_or(InvalidHistoryReceipt)?;
        let direct = ids(&row["direct_metric_ids"]).ok_or(InvalidHistoryReceipt)?;
        let dependencies = ids(&row["dependency_metric_ids"]).ok_or(InvalidHistoryReceipt)?;
        if !only_keys(
            row,
            &[
                "type_id",
                "direct_metric_ids",
                "dependency_metric_ids",
                "dependency_reasons",
                "outcome",
                "intersection",
                "sample_end_boundary",
                "unassessed_reason",
            ],
        ) || !types.insert(type_id)
            || !direct.is_subset(metrics)
            || !dependencies.is_subset(metrics)
            || ids(&row["dependency_reasons"]).is_none()
        {
            return Err(InvalidHistoryReceipt);
        }
        directly_attributed.extend(direct);
        match row["outcome"].as_str() {
            Some("limited") => {
                if !instant(&row["sample_end_boundary"])
                    || row.get("unassessed_reason").is_some()
                    || !matches!(
                        row["intersection"].as_str(),
                        Some("potential" | "no_known_intersection")
                    )
                    || (value["logical_dates"]["type"] == "all_available"
                        && row["intersection"] != "potential")
                {
                    return Err(InvalidHistoryReceipt);
                }
            }
            Some("unknown" | "api_unavailable" | "assessment_failed" | "unassessed") => {
                if row.get("sample_end_boundary").is_some()
                    || row["intersection"] != "unknown"
                    || (row["outcome"] == "unassessed"
                        && !row["unassessed_reason"].as_str().is_some_and(safe_id))
                    || (row["outcome"] != "unassessed" && row.get("unassessed_reason").is_some())
                {
                    return Err(InvalidHistoryReceipt);
                }
            }
            _ => return Err(InvalidHistoryReceipt),
        }
    }
    if &directly_attributed != metrics {
        return Err(InvalidHistoryReceipt);
    }
    Ok(())
}

/// Human disclosure independent of capture/traversal coverage. JSON is unchanged.
#[must_use]
pub fn disclosure_message(response: &Value) -> String {
    let Some(value) = receipt(response) else {
        return "History: legacy/unassessed; completed capture and empty results do not prove full history.".into();
    };
    if !recognized(value) {
        return "History: unsupported assessment semantics; retained opaquely, full history unverified.".into();
    }
    if validate_shape(value).is_err() {
        return "History: invalid assessment evidence; full history unverified.".into();
    }
    let outcomes = [
        "limited",
        "unknown",
        "api_unavailable",
        "assessment_failed",
        "unassessed",
    ];
    let counts: Vec<_> = outcomes
        .iter()
        .map(|outcome| {
            value["types"].as_array().map_or(0, |rows| {
                rows.iter()
                    .filter(|row| row["outcome"].as_str() == Some(*outcome))
                    .count()
            })
        })
        .collect();
    let fixture = if value["evidence_method"] == "synthetic_ui_fixture" {
        "Synthetic fixture. "
    } else {
        ""
    };
    let Some(rows) = value["types"].as_array() else {
        return "History: invalid assessment evidence; full history unverified.".into();
    };
    let cutoffs: Vec<_> = rows
        .iter()
        .filter(|row| row["outcome"] == "limited")
        .collect();
    let displayed: Vec<_> = cutoffs
        .iter()
        .take(8)
        .map(|row| {
            format!(
                "{}: {} (sample END, UTC)",
                row["type_id"].as_str().unwrap_or(""),
                row["sample_end_boundary"].as_str().unwrap_or("")
            )
        })
        .collect();
    let overflow = if cutoffs.len() > 8 {
        format!(
            " {} additional type cutoffs: see complete JSON metadata.",
            cutoffs.len() - 8
        )
    } else {
        String::new()
    };
    format!(
        "History: {fixture}capture-time observation at {}, frozen timezone {}; not current permission. Types: limited {}, unknown {}, API unavailable {}, failed {}, unassessed {}. {}{} Earlier starts/owner dates preserved. No full-history certification.",
        value["observed_at"].as_str().unwrap_or(""),
        value["time_zone_identifier"].as_str().unwrap_or(""),
        counts[0],
        counts[1],
        counts[2],
        counts[3],
        counts[4],
        displayed.join("; "),
        overflow
    )
}
