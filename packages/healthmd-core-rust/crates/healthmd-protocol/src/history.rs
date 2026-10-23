//! Independently versioned export-admission evidence. This is never a permission grant.

use std::collections::BTreeSet;

use serde::{Deserialize, Deserializer, Serialize, de::Error as _};
use uuid::Uuid;

/// Validated, immutable observation. Unknown versions are rejected, never interpreted as v1.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct ExportHistoryObservation(Box<ObservationFields>);

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct ObservationFields {
    schema: String,
    schema_version: i32,
    observation_id: String,
    operation_id: String,
    observed_at: String,
    request_binding_sha256: String,
    source_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_installation_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    destination_installation_id: Option<String>,
    time_zone_identifier: String,
    metric_ids: Vec<String>,
    requested_start: String,
    requested_end: String,
    all_available: bool,
    range_semantics: String,
    evidence_method: String,
    types: Vec<TypeObservation>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct TypeObservation {
    type_id: String,
    direct_metric_ids: Vec<String>,
    dependency_metric_ids: Vec<String>,
    dependency_reasons: Vec<String>,
    outcome: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    sample_end_boundary: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    unassessed_reason: Option<String>,
}

impl<'de> Deserialize<'de> for ExportHistoryObservation {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let fields = ObservationFields::deserialize(deserializer)?;
        if !fields.is_valid() {
            return Err(D::Error::custom("invalid export history observation"));
        }
        Ok(Self(Box::new(fields)))
    }
}

impl ExportHistoryObservation {
    /// Operation that owns the frozen observation.
    #[must_use]
    pub fn operation_id(&self) -> &str {
        &self.0.operation_id
    }

    /// Match authenticated immutable request, peer, selection and calendar authority.
    #[must_use]
    pub fn matches(
        &self,
        request: &crate::models::ExportRequest,
        accepted: &crate::models::ExportAccepted,
        session: &crate::models::TransferSession,
    ) -> bool {
        let fields = &self.0;
        if fields.operation_id != request.job_id.0.to_string()
            || accepted.job_id != request.job_id
            || session.job_id != request.job_id
            || fields.request_binding_sha256 != session.request_fingerprint.sha256
            || fields.source_installation_id.as_deref()
                != Some(
                    session
                        .peer_binding
                        .source_installation_id
                        .0
                        .to_string()
                        .as_str(),
                )
            || fields.destination_installation_id.as_deref()
                != Some(
                    session
                        .peer_binding
                        .destination_installation_id
                        .0
                        .to_string()
                        .as_str(),
                )
            || session.peer_binding != accepted.peer_binding
            || fields.time_zone_identifier != accepted.source_time_zone_identifier
            || fields.range_semantics != "owner_dates"
        {
            return false;
        }
        let Some(selection) = &accepted.resolved_canonical_selection else {
            return false;
        };
        let mut metrics = selection.metric_ids.clone();
        metrics.sort();
        if fields.metric_ids != metrics {
            return false;
        }
        let Ok(time_zone) = fields.time_zone_identifier.parse::<chrono_tz::Tz>() else {
            return false;
        };
        let civil_day = |instant: &str| {
            chrono::DateTime::parse_from_rfc3339(instant)
                .ok()
                .map(|date| {
                    date.with_timezone(&time_zone)
                        .format("%Y-%m-%d")
                        .to_string()
                })
        };
        let (Some(start), Some(end)) = (
            civil_day(&fields.requested_start),
            civil_day(&fields.requested_end),
        ) else {
            return false;
        };
        match &request.date_selection {
            crate::models::DateSelection::Exact(range) => {
                !fields.all_available && start == range.start && end == range.end
            }
            crate::models::DateSelection::AllAvailable(_) => {
                fields.all_available
                    && Some(&start) == accepted.resolved_date_identifiers.first()
                    && Some(&end) == accepted.resolved_date_identifiers.last()
            }
        }
    }

    /// Immutable request/settings authority supplied by the producer.
    #[must_use]
    pub fn request_binding_sha256(&self) -> &str {
        &self.0.request_binding_sha256
    }

    /// Source calendar authority, independent of the receiving host's timezone.
    #[must_use]
    pub fn time_zone_identifier(&self) -> &str {
        &self.0.time_zone_identifier
    }

    /// Remote identity bindings, absent together for local artifacts.
    #[must_use]
    pub fn installation_ids(&self) -> (Option<&str>, Option<&str>) {
        (
            self.0.source_installation_id.as_deref(),
            self.0.destination_installation_id.as_deref(),
        )
    }

    /// Exact resolved metric selection; permission evidence cannot widen it.
    #[must_use]
    pub fn metric_ids(&self) -> &[String] {
        &self.0.metric_ids
    }
}

impl ObservationFields {
    fn is_valid(&self) -> bool {
        let metrics: BTreeSet<_> = self.metric_ids.iter().collect();
        let mut attributed = BTreeSet::new();
        let identities = match (
            &self.source_installation_id,
            &self.destination_installation_id,
        ) {
            (None, None) => true,
            (Some(source), Some(destination)) => valid_uuid(source) && valid_uuid(destination),
            _ => false,
        };
        if self.schema != "healthmd.export_history_observation"
            || self.schema_version != 1
            || !valid_uuid(&self.observation_id)
            || !valid_uuid(&self.operation_id)
            || !identities
            || !valid_instant(&self.observed_at)
            || !valid_instant(&self.requested_start)
            || !valid_instant(&self.requested_end)
            || self.requested_start > self.requested_end
            || self.request_binding_sha256.len() != 64
            || !self
                .request_binding_sha256
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            || self.source_id != "apple.healthkit"
            || self.time_zone_identifier.parse::<chrono_tz::Tz>().is_err()
            || self.metric_ids.is_empty()
            || !identifiers(&self.metric_ids)
            || !identifier(&self.evidence_method)
            || !matches!(
                self.range_semantics.as_str(),
                "owner_dates" | "exact_interval"
            )
            || self.types.len() > 512
            || !identifiers(
                &self
                    .types
                    .iter()
                    .map(|r| r.type_id.clone())
                    .collect::<Vec<_>>(),
            )
        {
            return false;
        }
        for row in &self.types {
            if (row.direct_metric_ids.is_empty() && row.dependency_metric_ids.is_empty())
                || (!row.dependency_reasons.is_empty() && row.dependency_metric_ids.is_empty())
                || !identifiers(&row.direct_metric_ids)
                || !identifiers(&row.dependency_metric_ids)
                || !identifiers(&row.dependency_reasons)
                || !row
                    .direct_metric_ids
                    .iter()
                    .chain(&row.dependency_metric_ids)
                    .all(|id| metrics.contains(id))
            {
                return false;
            }
            attributed.extend(row.direct_metric_ids.iter());
            let valid = match row.outcome.as_str() {
                "limited" => {
                    row.sample_end_boundary
                        .as_deref()
                        .is_some_and(valid_instant)
                        && row.unassessed_reason.is_none()
                }
                "unknown" | "api_unavailable" | "assessment_failed" => {
                    row.sample_end_boundary.is_none() && row.unassessed_reason.is_none()
                }
                "unassessed" => {
                    row.sample_end_boundary.is_none()
                        && row.unassessed_reason.as_deref().is_some_and(identifier)
                }
                _ => false,
            };
            if !valid {
                return false;
            }
        }
        attributed == metrics
            && serde_json::to_vec(self).is_ok_and(|bytes| bytes.len() <= 256 * 1_024)
    }
}

fn valid_uuid(value: &str) -> bool {
    Uuid::parse_str(value).is_ok_and(|uuid| uuid.to_string() == value)
}

fn identifier(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._:-".contains(&b))
}

fn identifiers(values: &[String]) -> bool {
    values.len() <= 512
        && values.iter().all(|s| identifier(s))
        && values.windows(2).all(|w| w[0] < w[1])
}

fn valid_instant(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 30 {
        return false;
    }
    for (index, byte) in bytes.iter().copied().enumerate() {
        let separator = match index {
            4 | 7 => Some(b'-'),
            10 => Some(b'T'),
            13 | 16 => Some(b':'),
            19 => Some(b'.'),
            29 => Some(b'Z'),
            _ => None,
        };
        if separator.map_or(!byte.is_ascii_digit(), |expected| byte != expected) {
            return false;
        }
    }
    // Reject normalized/leap-second inputs and preserve nanosecond ordering as text.
    chrono::DateTime::parse_from_rfc3339(value).is_ok()
        && &value[0..4] != "0000"
        && &value[17..19] < "60"
}

/// Independently versioned sidecar binding frozen admission evidence to generated
/// contributions and complete post-merge artifacts. It certifies no current permission.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct ExportHistoryFileReceipt(Box<FileReceiptFields>);

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct FileReceiptFields {
    schema: String,
    schema_version: i32,
    history_observation: ExportHistoryObservation,
    artifacts: Vec<ExportHistoryFileArtifact>,
}

/// A generated contribution and the complete file resulting from its commit.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExportHistoryFileArtifact {
    pub relative_path: String,
    pub write_mode: crate::models::FileWriteMode,
    pub generated_byte_count: i64,
    pub generated_sha256: String,
    pub committed_sha256: String,
}

impl ExportHistoryFileReceipt {
    /// Build a sidecar in deterministic UTF-8 path order.
    ///
    /// # Errors
    /// Returns a health-free validation error for invalid paths, digests, duplicate
    /// artifacts or metadata exceeding the 64 MiB durable bound.
    pub fn new(
        history_observation: ExportHistoryObservation,
        mut artifacts: Vec<ExportHistoryFileArtifact>,
    ) -> Result<Self, &'static str> {
        artifacts.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
        let value = Self(Box::new(FileReceiptFields {
            schema: "healthmd.export_history_file_receipt".into(),
            schema_version: 1,
            history_observation,
            artifacts,
        }));
        if value.is_valid() {
            Ok(value)
        } else {
            Err("invalid history file receipt")
        }
    }

    #[must_use]
    pub fn history_observation(&self) -> &ExportHistoryObservation {
        &self.0.history_observation
    }

    #[must_use]
    pub fn artifacts(&self) -> &[ExportHistoryFileArtifact] {
        &self.0.artifacts
    }

    fn is_valid(&self) -> bool {
        self.0.schema == "healthmd.export_history_file_receipt"
            && self.0.schema_version == 1
            && self.0.artifacts.len() <= 100_000
            && self
                .0
                .artifacts
                .windows(2)
                .all(|w| w[0].relative_path < w[1].relative_path)
            && self.0.artifacts.iter().all(|a| {
                let path = &a.relative_path;
                !path.is_empty()
                    && path.len() <= 4_096
                    && !path.starts_with('/')
                    && !path.contains(['\\', ':'])
                    && !path
                        .chars()
                        .any(|c| u32::from(c) < 0x20 || (0x7f..=0x9f).contains(&u32::from(c)))
                    && path
                        .split('/')
                        .all(|s| !s.is_empty() && s != "." && s != "..")
                    && a.generated_byte_count >= 0
                    && crate::transfer::is_sha256(&a.generated_sha256)
                    && crate::transfer::is_sha256(&a.committed_sha256)
                    && (a.write_mode != crate::models::FileWriteMode::Overwrite
                        || a.generated_sha256 == a.committed_sha256)
            })
            && serde_json::to_vec(self).is_ok_and(|bytes| bytes.len() <= 64 * 1_024 * 1_024)
    }
}

impl<'de> Deserialize<'de> for ExportHistoryFileReceipt {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = Self(Box::new(FileReceiptFields::deserialize(deserializer)?));
        if value.is_valid() {
            Ok(value)
        } else {
            Err(D::Error::custom("invalid history file receipt"))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    const FIXTURE: &str = include_str!("../tests/fixtures/export-history-v1.json");

    #[test]
    fn slash_heavy_file_receipt_uses_unescaped_metadata_bound() {
        let observation: ExportHistoryObservation = serde_json::from_str(FIXTURE).unwrap();
        let prefix = "a/".repeat(1_900);
        let artifacts: Vec<_> = (0..18_000)
            .map(|n| ExportHistoryFileArtifact {
                relative_path: format!("{prefix}{n:06}.md"),
                write_mode: crate::models::FileWriteMode::Overwrite,
                generated_byte_count: 0,
                generated_sha256: "a".repeat(64),
                committed_sha256: "a".repeat(64),
            })
            .collect();
        assert!(
            ExportHistoryFileReceipt::new(observation.clone(), artifacts[..16_000].to_vec())
                .is_ok()
        );
        assert!(ExportHistoryFileReceipt::new(observation, artifacts).is_err());
    }

    #[test]
    fn swift_file_receipt_preserves_generated_and_post_merge_hashes() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../tests/fixtures/export-history-file-receipt-v1.json"
        ))
        .unwrap();
        let receipt: ExportHistoryFileReceipt = serde_json::from_value(fixture.clone()).unwrap();
        assert_eq!(serde_json::to_value(&receipt).unwrap(), fixture);
        assert_ne!(
            receipt.artifacts()[0].generated_sha256,
            receipt.artifacts()[0].committed_sha256
        );
        let rebuilt = ExportHistoryFileReceipt::new(
            receipt.history_observation().clone(),
            receipt.artifacts().to_vec(),
        )
        .unwrap();
        assert_eq!(rebuilt, receipt);
        assert!(
            ExportHistoryFileReceipt::new(
                receipt.history_observation().clone(),
                vec![receipt.artifacts()[0].clone(); 2]
            )
            .is_err()
        );
        for (key, value) in [
            ("relative_path", json!("../other.md")),
            ("relative_path", json!("C:/other.md")),
            ("generated_sha256", json!("B".repeat(64))),
            ("committed_sha256", json!("invalid")),
            ("generated_byte_count", json!(-1)),
            ("write_mode", json!("unknown")),
            ("write_mode", json!("overwrite")),
            ("unexpected", json!(true)),
        ] {
            let mut changed = fixture.clone();
            changed["artifacts"][0][key] = value;
            assert!(serde_json::from_value::<ExportHistoryFileReceipt>(changed).is_err());
        }
        for (key, value) in [("schema_version", json!(2)), ("full_history", json!(true))] {
            let mut changed = fixture.clone();
            changed[key] = value;
            assert!(serde_json::from_value::<ExportHistoryFileReceipt>(changed).is_err());
        }
        let mut changed = fixture.clone();
        changed["artifacts"] = json!([fixture["artifacts"][0], fixture["artifacts"][0]]);
        assert!(serde_json::from_value::<ExportHistoryFileReceipt>(changed).is_err());
    }

    #[test]
    fn swift_observation_round_trips_without_relabeling() {
        let observation: ExportHistoryObservation = serde_json::from_str(FIXTURE).unwrap();
        let source: Value = serde_json::from_str(FIXTURE).unwrap();
        assert_eq!(serde_json::to_value(&observation).unwrap(), source);
        assert_eq!(
            observation.operation_id(),
            "22222222-2222-4222-8222-222222222222"
        );
    }

    #[test]
    fn swift_direct_job_binding_rejects_changed_authority() {
        #[derive(Deserialize)]
        struct JobFixture {
            request: crate::models::ExportRequest,
            accepted: crate::models::ExportAccepted,
            session: crate::models::TransferSession,
        }
        let fixture: JobFixture = serde_json::from_str(include_str!(
            "../tests/fixtures/export-history-direct-job-v1.json"
        ))
        .unwrap();
        assert_eq!(
            crate::transfer::request_fingerprint(&fixture.request).unwrap(),
            fixture.session.request_fingerprint
        );
        let observation = fixture.accepted.history_observation.as_ref().unwrap();
        assert!(observation.matches(&fixture.request, &fixture.accepted, &fixture.session));
        let mut missing_scope = fixture.accepted.clone();
        missing_scope.resolved_canonical_selection = None;
        assert!(!observation.matches(&fixture.request, &missing_scope, &fixture.session));
        let mut changed_scope = fixture.accepted.clone();
        changed_scope
            .resolved_canonical_selection
            .as_mut()
            .unwrap()
            .metric_ids = vec!["other_metric".into()];
        assert!(!observation.matches(&fixture.request, &changed_scope, &fixture.session));
        for (key, value) in [
            ("operation_id", "66666666-6666-4666-8666-666666666666"),
            (
                "source_installation_id",
                "66666666-6666-4666-8666-666666666666",
            ),
            (
                "request_binding_sha256",
                "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            ),
            ("requested_start", "2026-01-02T04:00:00.000000000Z"),
            ("time_zone_identifier", "UTC"),
        ] {
            let mut changed = serde_json::to_value(observation).unwrap();
            changed[key] = json!(value);
            let changed: ExportHistoryObservation = serde_json::from_value(changed).unwrap();
            assert!(!changed.matches(&fixture.request, &fixture.accepted, &fixture.session));
        }
    }

    #[test]
    fn invalid_and_full_claims_fail_closed() {
        let original: Value = serde_json::from_str(FIXTURE).unwrap();
        for (key, value) in [
            ("schema_version", json!(2)),
            ("metric_ids", json!(["steps", "activeEnergy"])),
            (
                "metric_ids",
                json!(["activeEnergy", "steps", "unattributed"]),
            ),
            ("destination_installation_id", Value::Null),
            ("time_zone_identifier", json!("Unknown/Timezone")),
            ("observed_at", json!("2026-02-30T12:00:00.000000000Z")),
            ("requested_start", json!("2026-10-23T04:00:00.000000001Z")),
        ] {
            let mut changed = original.clone();
            changed[key] = value;
            assert!(serde_json::from_value::<ExportHistoryObservation>(changed).is_err());
        }
        let mut unknown = original.clone();
        unknown["full_history"] = json!(true);
        assert!(serde_json::from_value::<ExportHistoryObservation>(unknown).is_err());
        let mut unrelated = original.clone();
        unrelated["types"].as_array_mut().unwrap().push(json!({
            "type_id": "unrelated", "direct_metric_ids": [], "dependency_metric_ids": [],
            "dependency_reasons": [], "outcome": "limited", "sample_end_boundary": "2026-09-23T12:00:00.000000000Z"
        }));
        assert!(serde_json::from_value::<ExportHistoryObservation>(unrelated).is_err());
        let mut reason = original.clone();
        reason["types"][0]["dependency_reasons"] = json!(["unrelated_reason"]);
        assert!(serde_json::from_value::<ExportHistoryObservation>(reason).is_err());
        for outcome in ["full", "denied", "complete"] {
            let mut changed = original.clone();
            changed["types"][0]["outcome"] = json!(outcome);
            assert!(serde_json::from_value::<ExportHistoryObservation>(changed).is_err());
        }
    }
}
