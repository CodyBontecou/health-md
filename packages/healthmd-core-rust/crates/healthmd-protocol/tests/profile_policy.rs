use healthmd_protocol::{
    encoding::SwiftUuid,
    models::{
        DateSelection, DetailLevel, ExactDateSelection, ExportRequest, ProfileReference,
        ResponseMode, SettingsPolicy,
    },
};
use serde::Deserialize;
use uuid::Uuid;

fn base_request_json() -> String {
    // A v1 request exactly as an older peer would have emitted it: no
    // profile fields at all.
    r#"{
        "protocolVersion": 1,
        "jobID": "00000000-0000-4000-8000-00000000000A",
        "createdAt": "2023-11-14T22:13:20Z",
        "dateSelection": { "exact": { "start": "2026-08-01", "end": "2026-08-07" } },
        "settingsPolicy": "requested_dates_only",
        "responseMode": "write_files",
        "destination": { "rootPath": "/tmp/vault" }
    }"#
    .to_owned()
}

fn profile_request() -> ExportRequest {
    ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(Uuid::parse_str("00000000-0000-4000-8000-00000000000B").unwrap()),
        created_at: chrono::TimeZone::timestamp_opt(&chrono::Utc, 1_700_000_000, 0).unwrap(),
        date_selection: DateSelection::Exact(ExactDateSelection {
            start: "2026-08-01".into(),
            end: "2026-08-07".into(),
        }),
        settings_policy: SettingsPolicy::Profile,
        profile_reference: Some(ProfileReference {
            profile_id: "11111111-2222-4333-8444-555555555555".into(),
            name: Some("Weekly Sleep".into()),
        }),
        response_mode: ResponseMode::WriteFiles,
        raw_profile: None,
        canonical_selection: None,
        destination: None,
    }
}

#[test]
fn legacy_request_without_profile_fields_decodes() {
    let request: ExportRequest = serde_json::from_str(&base_request_json()).unwrap();
    assert_eq!(request.settings_policy, SettingsPolicy::RequestedDatesOnly);
    assert_eq!(request.profile_reference, None);
}

#[test]
fn profile_policy_round_trips_with_camel_case_fields() {
    let request = profile_request();
    let json = serde_json::to_value(&request).unwrap();
    assert_eq!(json["settingsPolicy"], "profile");
    assert_eq!(
        json["profileReference"]["profileID"],
        "11111111-2222-4333-8444-555555555555"
    );
    assert_eq!(json["profileReference"]["name"], "Weekly Sleep");

    let decoded: ExportRequest = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, request);
}

#[test]
fn profile_reference_name_is_omitted_when_absent() {
    let mut request = profile_request();
    let reference = request.profile_reference.as_mut().unwrap();
    reference.name = None;

    let json = serde_json::to_value(&request).unwrap();
    assert!(json["profileReference"].get("name").is_none());

    let decoded: ExportRequest = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, request);
}

#[test]
fn old_peer_fails_closed_on_profile_policy() {
    // An older peer's decoder does not know the "profile" variant. Simulate
    // that enum shape and assert it rejects the new payload with a typed
    // error instead of silently defaulting.
    #[derive(Deserialize, PartialEq, Debug)]
    #[serde(rename_all = "snake_case")]
    enum LegacySettingsPolicy {
        RequestedDatesOnly,
        CurrentIphoneSettings,
    }
    #[derive(Deserialize)]
    struct LegacyRequest {
        settings_policy: LegacySettingsPolicy,
    }

    let legacy_request: Result<LegacyRequest, _> =
        serde_json::from_str(&base_request_json().replace(
            "\"requested_dates_only\"",
            "\"profile\"",
        ));
    assert!(legacy_request.is_err());
}

#[test]
fn old_peer_ignores_unknown_profile_reference_field() {
    // Unknown struct fields are ignored by the v1 models (no
    // deny_unknown_fields), so a legacy peer reading a new payload skips the
    // profile reference rather than failing the whole decode.
    #[derive(Deserialize, Debug)]
    struct LegacyRequest {
        #[serde(rename = "responseMode")]
        response_mode: String,
    }

    let mut json: serde_json::Value = serde_json::from_str(&base_request_json()).unwrap();
    json["profileReference"] = serde_json::json!({
        "profileID": "11111111-2222-4333-8444-555555555555"
    });

    let legacy_request: LegacyRequest = serde_json::from_value(json).unwrap();
    assert_eq!(legacy_request.response_mode, "write_files");
}

#[test]
fn canonical_selection_still_round_trips_alongside_profile() {
    let mut request = profile_request();
    request.canonical_selection = Some(healthmd_protocol::models::CanonicalSelection {
        metric_ids: vec!["sleep_total".into()],
        categories: vec!["Sleep".into()],
        source_ids: vec!["apple_health".into()],
        object_paths: vec!["/sleep".into()],
        field_pointers: Vec::new(),
        all_metrics: false,
        detail_level: DetailLevel::Summary,
    });

    let json = serde_json::to_value(&request).unwrap();
    let decoded: ExportRequest = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, request);
}
