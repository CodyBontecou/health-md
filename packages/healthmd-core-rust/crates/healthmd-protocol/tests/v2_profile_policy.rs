//! Export-profiles decision 10 (v2 mirror): the additive
//! `settings_policy = profile` request shape for Android direct v2, its
//! optional `profile_reference`, capability advertisement, and the fail-closed
//! behavior of older peers that do not know the new variant or field.

use chrono::{TimeZone as _, Utc};
use healthmd_protocol::v2::{
    self, ArtifactSchema, ArtifactFormat, DateSelection, DestinationBinding, ExportProduct,
    ExportRequest, ProductCapability, ProfileReference, ProtocolLimits, SettingsPolicy,
    SourceIdentity, SourcePlatform,
};
use serde::Deserialize;
use uuid::Uuid;

fn base_request() -> ExportRequest {
    ExportRequest {
        job_id: Uuid::parse_str("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee").unwrap(),
        created_at: Utc.timestamp_opt(1_753_343_472, 0).unwrap(),
        expires_at: "2026-07-31T10:11:12Z".parse().unwrap(),
        source_installation_id: Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap(),
        date_selection: DateSelection::Exact {
            start_date: "2026-07-01".into(),
            end_date: "2026-07-02".into(),
        },
        product: ExportProduct::GeneratedFilesV1 {
            settings_policy: SettingsPolicy::SavedDeviceSettings,
            profile_reference: None,
        },
        destination: Some(DestinationBinding {
            binding_sha256: "a".repeat(64),
            display_name: "Health Exports".into(),
        }),
    }
}

fn profile_request() -> ExportRequest {
    let mut request = base_request();
    request.product = ExportProduct::GeneratedFilesV1 {
        settings_policy: SettingsPolicy::Profile,
        profile_reference: Some(ProfileReference {
            profile_id: "99999999-8888-4777-8666-555555555555".into(),
            name: Some("Weekly Sleep".into()),
        }),
    };
    request
}

#[test]
fn legacy_request_without_profile_fields_decodes() {
    let request = base_request();
    let json = serde_json::to_value(&request).unwrap();
    let decoded: ExportRequest = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, request);
    assert!(decoded.product.profile_reference().is_none());
}

#[test]
fn profile_policy_round_trips_with_snake_case_fields() {
    let request = profile_request();
    let json = serde_json::to_value(&request).unwrap();

    let product = &json["product"];
    assert_eq!(product["product_id"], "generated_files_v1");
    assert_eq!(product["settings_policy"], "profile");
    assert_eq!(
        product["profile_reference"]["profile_id"],
        "99999999-8888-4777-8666-555555555555"
    );
    assert_eq!(product["profile_reference"]["name"], "Weekly Sleep");

    let decoded: ExportRequest = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, request);
    assert_eq!(
        decoded.product.profile_reference(),
        Some(&ProfileReference {
            profile_id: "99999999-8888-4777-8666-555555555555".into(),
            name: Some("Weekly Sleep".into()),
        })
    );
}

#[test]
fn profile_reference_name_is_omitted_when_absent() {
    let mut request = profile_request();
    request.product = ExportProduct::GeneratedFilesV1 {
        settings_policy: SettingsPolicy::Profile,
        profile_reference: Some(ProfileReference {
            profile_id: "99999999-8888-4777-8666-555555555555".into(),
            name: None,
        }),
    };

    let json = serde_json::to_value(&request).unwrap();
    assert!(json["product"]["profile_reference"].get("name").is_none());

    let decoded: ExportRequest = serde_json::from_value(json).unwrap();
    assert_eq!(decoded, request);
}

#[test]
fn request_fingerprint_is_deterministic_for_profile_requests() {
    let request = profile_request();
    let first = v2::request_fingerprint(&request).unwrap();
    let canonical = healthmd_protocol::encoding::canonical_json(&request).unwrap();
    let round_trip: ExportRequest = serde_json::from_slice(&canonical).unwrap();
    let second = v2::request_fingerprint(&round_trip).unwrap();
    assert_eq!(first, second);
    assert_eq!(first.len(), 64);
}

#[test]
fn old_peer_fails_closed_on_unknown_profile_policy() {
    // An older v2 peer's decoder does not know the "profile" variant. Simulate
    // that enum shape and assert it rejects the new payload instead of
    // silently defaulting.
    #[derive(Deserialize, PartialEq, Debug)]
    #[serde(rename_all = "snake_case")]
    enum LegacySettingsPolicy {
        RequestedScope,
        SavedDeviceSettings,
    }
    #[derive(Deserialize)]
    #[allow(dead_code)] // wire-shape mirror: only decode success/failure is asserted
    struct LegacyProduct {
        settings_policy: LegacySettingsPolicy,
    }

    let json = serde_json::to_value(&profile_request()).unwrap();
    let legacy: Result<LegacyProduct, _> = serde_json::from_value(json["product"].clone());
    assert!(legacy.is_err());
}

#[test]
fn old_peer_fails_closed_on_unknown_profile_reference_field() {
    // v2 models deny unknown fields, so an older peer also rejects the new
    // optional field — fail closed rather than misreading the policy.
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    #[allow(dead_code)] // wire-shape mirror: only decode success/failure is asserted
    struct LegacyProduct {
        settings_policy: String,
    }

    let json = serde_json::to_value(&profile_request()).unwrap();
    let legacy: Result<LegacyProduct, _> = serde_json::from_value(json["product"].clone());
    assert!(legacy.is_err());
}

#[test]
fn capability_advertisement_serializes_the_profile_policy() {
    let capability = ProductCapability {
        product_id: healthmd_protocol::v2::ProductId::GeneratedFilesV1,
        artifact_schema: ArtifactSchema {
            id: "healthmd.generated-files".into(),
            major: 1,
        },
        formats: vec![ArtifactFormat::Markdown],
        providers: Vec::new(),
        settings_policies: vec![
            SettingsPolicy::SavedDeviceSettings,
            SettingsPolicy::Profile,
        ],
        supports_resume: true,
    };
    let hello = healthmd_protocol::v2::SourceHello {
        source: SourceIdentity {
            installation_id: Uuid::parse_str("11111111-2222-4333-8444-555555555555").unwrap(),
            platform: SourcePlatform::Android,
            display_name: "Pixel 7".into(),
            app_version: "2.0".into(),
        },
        products: vec![capability],
        limits: ProtocolLimits {
            maximum_control_bytes: 262_144,
            maximum_chunk_bytes: 524_288,
            preferred_partition_bytes: 8 * 1024 * 1024,
        },
    };

    let json = serde_json::to_value(&hello).unwrap();
    assert_eq!(
        json["products"][0]["settings_policies"],
        serde_json::json!(["saved_device_settings", "profile"])
    );

    let decoded: healthmd_protocol::v2::SourceHello = serde_json::from_value(json).unwrap();
    assert_eq!(
        decoded.products[0].settings_policies,
        vec![
            SettingsPolicy::SavedDeviceSettings,
            SettingsPolicy::Profile,
        ]
    );
}
