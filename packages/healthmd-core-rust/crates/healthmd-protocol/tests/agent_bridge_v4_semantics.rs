//! DTO round trips, intrinsic checks and synthetic private-store checks are separate.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use healthmd_protocol::v4::*;
use serde::{Serialize, de::DeserializeOwned};
use serde_json::{Value, json};

fn fixture() -> Value {
    serde_json::from_str(include_str!(
        "../../../../contracts/agent-bridge/v1/fixtures/conformance.json"
    ))
    .unwrap()
}
fn typed<T: DeserializeOwned + ValidateShape>(value: &Value) -> T {
    decode_typed(&serde_json::to_vec(value).unwrap()).unwrap()
}
fn case(fixture: &Value, id: &str) -> Value {
    fixture["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == id)
        .unwrap()
        .clone()
}
fn zones() -> Vec<CalendarZone> {
    vec![CalendarZone("Etc/UTC".to_owned())]
}
fn metrics() -> Vec<MetricSupport> {
    let registry: Value = serde_json::from_str(include_str!(
        "../../healthmd-core/registry/metric-registry-v1.json"
    ))
    .unwrap();
    let mut result = Vec::new();
    for row in registry["metrics"].as_array().unwrap() {
        for (key, platform) in [
            ("apple", PeerPlatform::Apple),
            ("android", PeerPlatform::Android),
        ] {
            if row[key]["status"] == "backed" {
                result.push(MetricSupport {
                    metric_id: SemanticId(row["semantic_id"].as_str().unwrap().to_owned()),
                    category_id: SemanticId(
                        row[key]["category_id"].as_str().unwrap().to_lowercase(),
                    ),
                    platform,
                });
            }
        }
    }
    result
}
fn projection_digest() -> Digest {
    let value: Value = serde_json::from_str(include_str!(
        "../../../../contracts/agent-bridge/v1/reviewed-projection-catalog.json"
    ))
    .unwrap();
    document_digest(&value).unwrap()
}
fn configuration<'a>(
    zones: &'a [CalendarZone],
    metrics: &'a [MetricSupport],
    projection: &'a Digest,
) -> ConfigurationContext<'a> {
    ConfigurationContext {
        calendar_zones: zones,
        metrics,
        projection_catalog_sha256: Some(projection),
    }
}
fn supported(value: &Value) -> bool {
    let Some(schema) = value["schema"].as_str() else {
        return false;
    };
    match schema {
        "healthmd.agent_export_intent" => value["product"]["type"] == "generated_files",
        "healthmd.agent_export_plan" | "healthmd.agent_plan_request" => {
            value["intent"]["product"]["type"] == "generated_files"
        }
        "healthmd.agent_execute_request" => {
            value["plan"]["intent"]["product"]["type"] == "generated_files"
        }
        "healthmd.agent_artifact_manifest" => !value["artifacts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["profile"] == "android-source-projection-v1"),
        "healthmd.agent_resume_request"
        | "healthmd.agent_approval_request"
        | "healthmd.agent_approval"
        | "healthmd.agent_execution_receipt"
        | "healthmd.agent_export_delegation"
        | "healthmd.agent_discovery"
        | "healthmd.agent_discovery_request"
        | "healthmd.agent_commit_receipt"
        | "healthmd.agent_cancel_request"
        | "healthmd.source_query_catalog"
        | "healthmd.agent_error" => true,
        _ => false,
    }
}

fn typed_vectors(fixture: &Value) -> Vec<usize> {
    let negotiation = Negotiation {
        base: 2,
        iphone_query_v3: false,
        agent_v4: true,
    };
    let mut indices = Vec::new();
    for (i, vector) in fixture["canonical_vectors"]
        .as_array()
        .unwrap()
        .iter()
        .enumerate()
    {
        let value = &vector["value"];
        let raw = serde_json::to_vec(value).unwrap();
        let bytes = if value.get("protocol_version").is_some() && supported(&value["payload"]) {
            canonical_json(&decode_envelope(&raw, negotiation).unwrap()).unwrap()
        } else if supported(value) {
            canonical_json(&decode_document(&raw).unwrap()).unwrap()
        } else {
            continue;
        };
        assert_eq!(
            STANDARD.encode(&bytes),
            vector["canonical_base64"],
            "typed vector {i}"
        );
        assert_eq!(sha256_hex(&bytes), vector["sha256"], "typed vector {i}");
        indices.push(i);
    }
    indices
}
#[test]
fn supported_python_candidates_roundtrip_through_closed_dtos() {
    let indices = typed_vectors(&fixture());
    assert!(indices.len() >= 20);
}

fn entries<T: DeserializeOwned + ValidateShape>(value: &Value) -> Vec<T> {
    value
        .as_object()
        .map(|map| map.values().map(typed).collect())
        .unwrap_or_default()
}
fn issued(value: &Value) -> Vec<(ControlUuid, Digest)> {
    value
        .as_object()
        .map(|map| {
            map.iter()
                .map(|(id, sha)| {
                    (
                        ControlUuid(id.clone()),
                        Digest(sha.as_str().unwrap().to_owned()),
                    )
                })
                .collect()
        })
        .unwrap_or_default()
}
fn with_store<T>(
    context: &Value,
    request: Option<&ExecuteRequest>,
    run: impl FnOnce(&ExportStoreContext<'_>) -> Result<T, Error>,
) -> Result<T, Error> {
    let zones = zones();
    let metrics = metrics();
    let projection = projection_digest();
    let now = typed(&context["now"]);
    let capabilities = typed(&context["capabilities"]);
    let native = entries(&context["stored_native_delegations"]);
    let host = entries(&context["stored_host_delegations"]);
    let destinations = entries(&context["registered_destinations"]);
    let plans = issued(&context["issued_plans"]);
    let approvals = issued(&context["issued_approvals"]);
    let approval_ids: Vec<ControlUuid> = context["issued_approval_ids"]
        .as_array()
        .unwrap()
        .iter()
        .map(typed)
        .collect();
    let native_authority = typed(&context["authority"]);
    let host_authority = typed(&context["host_authority"]);
    let peer = typed(&context["peer"]);
    let destination = typed(&context["destination"]);
    let current_capability = typed(&context["capability_sha256"]);
    let revisions: Vec<Revision> = context["revisions"]
        .as_array()
        .unwrap()
        .iter()
        .map(typed)
        .collect();
    let decision = context
        .get("approved_export_binding_sha256")
        .map(typed::<Digest>);
    let accepted = context.get("existing_request_sha256").map(|sha| {
        let request = request.unwrap();
        AcceptedExecution {
            peer: request.plan.intent.peer.clone(),
            destination: request.plan.intent.destination.clone(),
            job_id: request.job_id.clone(),
            idempotency_key: request.idempotency_key.clone(),
            request_sha256: typed(sha),
        }
    });
    run(&ExportStoreContext {
        configuration: configuration(&zones, &metrics, &projection),
        now: &now,
        capabilities: &capabilities,
        native_delegations: &native,
        host_delegations: &host,
        registered_destinations: &destinations,
        issued_plans: &plans,
        issued_approvals: &approvals,
        issued_approval_ids: &approval_ids,
        native_authority: &native_authority,
        host_authority: &host_authority,
        current_peer: &peer,
        current_destination: &destination,
        current_capability_sha256: &current_capability,
        current_revisions: &revisions,
        approved_binding_sha256: decision.as_ref(),
        accepted: accepted.as_ref(),
    })
}

fn check_document(value: &Value, context: &Value) -> Result<(), Error> {
    let document = decode_document(&serde_json::to_vec(value).unwrap())?;
    let zones = zones();
    let metrics = metrics();
    let projection = projection_digest();
    let config = configuration(&zones, &metrics, &projection);
    match document {
        Document::Intent(v) => validate_export_intent(&v, &config).map(|_| ()),
        Document::Plan(v) => validate_export_plan(&v, &config),
        Document::Discovery(v) => validate_discovery(&v, &config),
        Document::Delegation(v) => validate_export_delegation(&v, &config),
        Document::Execute(v) => with_store(context, Some(&v), |store| {
            validate_execute(&v, store).map(|_| ())
        }),
        Document::PlanRequest(v) => with_store(context, None, |store| {
            let effective: OutputSettings = typed(&context["plan"]["effective_settings"]);
            validate_plan_request(&v, &effective, store)
        }),
        Document::ApprovalRequest(v) => with_store(context, None, |store| {
            validate_approval_request(&v, &typed(&context["plan"]), store)
        }),
        Document::Commit(v) => validate_commit_receipt(
            &v,
            context
                .get("persisted_commit")
                .map(typed::<CommitReceipt>)
                .as_ref(),
        ),
        Document::Manifest(v) => validate_artifact_manifest(&v),
        Document::Receipt(v) => validate_execution_receipt(&v),
        Document::Resume(v) if context.get("journal_resume").is_some() => {
            validate_resume(&v, &typed(&context["journal_resume"]))
        }
        Document::QueryCatalog(v) => validate_query_catalog(&v),
        _ => Err(Error::UnsupportedCapability),
    }
}
fn semantic_case_supported(case: &Value) -> bool {
    let family = case["family"].as_str().unwrap();
    if family == "path" {
        return case["value"].as_str().unwrap().is_ascii();
    }
    if family == "collision" {
        return case["value"]
            .as_array()
            .unwrap()
            .iter()
            .all(|s| s.as_str().unwrap().is_ascii());
    }
    if !["agent", "resume"].contains(&family) || !supported(&case["value"]) {
        return false;
    }
    // These source/projection bindings require preserved-byte/catalog validators, not export DTOs.
    if case["id"].as_str().unwrap().starts_with("projection-") {
        return false;
    }
    ![
        "healthmd.agent_approval",
        "healthmd.agent_cancel_request",
        "healthmd.agent_error",
        "healthmd.agent_discovery_request",
    ]
    .contains(&case["value"]["schema"].as_str().unwrap())
}
fn check_case(case: &Value) -> Result<(), Error> {
    let value = &case["value"];
    let context = &case["context"];
    match case["family"].as_str().unwrap() {
        "path" => validate_relative_path(
            value.as_str().unwrap(),
            context["filename"].as_bool().unwrap_or(false),
            if context["templates"].as_bool().unwrap_or(false) {
                &[
                    "year",
                    "month",
                    "day",
                    "date",
                    "metric",
                    "category",
                    "record_id",
                ]
            } else {
                &[]
            },
        ),
        "collision" => validate_path_collisions(
            &value
                .as_array()
                .unwrap()
                .iter()
                .map(|s| RelativePath(s.as_str().unwrap().to_owned()))
                .collect::<Vec<_>>(),
        ),
        _ => check_document(value, context),
    }
}
fn semantic_ids(fixture: &Value) -> Vec<String> {
    let mut ids = Vec::new();
    let mut mismatches = Vec::new();
    for case in fixture["cases"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|c| semantic_case_supported(c))
    {
        let actual = check_case(case).map_or_else(|e| e.to_string(), |()| "valid".to_owned());
        if actual != case["expected"].as_str().unwrap() {
            mismatches.push(format!(
                "{}: {} != {}",
                case["id"].as_str().unwrap(),
                actual,
                case["expected"].as_str().unwrap()
            ));
        }
        ids.push(case["id"].as_str().unwrap().to_owned());
    }
    assert!(mismatches.is_empty(), "{}", mismatches.join("; "));
    ids
}
#[test]
fn bounded_export_intrinsic_and_synthetic_store_conformance() {
    assert!(semantic_ids(&fixture()).len() >= 75);
}

fn id(n: u32) -> ControlUuid {
    ControlUuid(format!("00000000-0000-4000-8000-{n:012x}"))
}
fn zero() -> Digest {
    Digest("0".repeat(64))
}
fn peer() -> Peer {
    Peer {
        source_installation_id: id(1),
        host_installation_id: id(2),
        platform: PeerPlatform::Android,
    }
}
fn settings() -> OutputSettings {
    OutputSettings {
        formats: vec![OutputSettingsFormatsItem::Json],
        output_profile: OutputSettingsOutputProfile::AndroidAnalyticalV5,
        subfolder: RelativePath(String::new()),
        folder_template: RelativePath("{year}".to_owned()),
        filename_template: FilenameTemplate("{date}".to_owned()),
        write_mode: OutputSettingsWriteMode::Overwrite,
        presentation: Presentation {
            display_units: PresentationDisplayUnits::Metric,
            machine_units: PresentationMachineUnits::Canonical,
            locale: "en-US".to_owned(),
            include_metadata: true,
            group_by_category: false,
            frontmatter: Frontmatter {
                enabled_field_ids: vec![],
                custom_fields: vec![],
                include_units: true,
                include_capture_diagnostics: true,
            },
            markdown: Markdown {
                style: MarkdownStyle::Tables,
                custom_template: String::new(),
                placeholder_ids: vec![],
            },
        },
        individual_entries: IndividualEntries {
            enabled: false,
            metric_ids: vec![],
            category_folders: false,
            folder_template: RelativePath("entries".to_owned()),
            filename_template: FilenameTemplate("{record_id}".to_owned()),
        },
        daily_notes: DailyNotes {
            enabled: false,
            only: false,
            folder_template: RelativePath("notes".to_owned()),
            filename_template: FilenameTemplate("{date}".to_owned()),
            create_if_missing: false,
            section_ids: vec![],
        },
        packaging: Packaging::LooseFiles {},
        dictionary: Dictionary::None {},
    }
}
fn intent() -> ExportIntent {
    ExportIntent {
        schema: ExportIntentSchema::HealthmdAgentExportIntent,
        schema_version: 1,
        intent_id: id(100),
        peer: peer(),
        destination: Destination {
            binding_id: id(3),
            host_installation_id: id(2),
            identity_sha256: Digest("d".repeat(64)),
            revision: 1,
        },
        dates: Dates::Exact {
            range: Range {
                start_date: CivilDate("2026-01-01".to_owned()),
                end_date: CivilDate("2026-01-01".to_owned()),
            },
        },
        calendar_timezone: CalendarZone("Etc/UTC".to_owned()),
        timestamp_timezone: ExportIntentTimestampTimezone::Utc,
        capture_scope: Capture {
            selection: Selection {
                metric_ids: vec![SemanticId("steps".to_owned())],
                category_ids: vec![],
                source_ids: vec![SemanticId("health_connect".to_owned())],
                provider_ids: vec![],
                all_metrics: false,
            },
            compatibility_detail: CaptureCompatibilityDetail::Summary,
            native_archive: Archive::None {},
        },
        product: ExportIntentProduct {
            kind: ExportIntentProductType::GeneratedFiles,
        },
        settings_policy: Policy::Explicit {
            settings: Box::new(settings()),
        },
    }
}
fn plan() -> ExportPlan {
    let intent = intent();
    let settings = settings();
    let mut plan = ExportPlan {
        schema: ExportPlanSchema::HealthmdAgentExportPlan,
        schema_version: 1,
        plan_id: id(101),
        resolved_dates: intent.dates.clone(),
        resolved_metric_ids: vec![SemanticId("steps".to_owned())],
        authority_references: AuthorityReferences {
            native: AuthorityReference {
                authority_id: id(10),
                issuer: AuthorityReferenceIssuer::NativeSource,
                grant_revision: 1,
                grant_sha256: zero(),
            },
            host: AuthorityReference {
                authority_id: id(11),
                issuer: AuthorityReferenceIssuer::AuthorizedHost,
                grant_revision: 1,
                grant_sha256: zero(),
            },
        },
        origins: setting_origins(&intent, &settings).unwrap(),
        revisions: vec![],
        settings_sha256: document_digest(&settings).unwrap(),
        scope_sha256: export_scope_digest(
            &intent,
            &intent.dates,
            &[SemanticId("steps".to_owned())],
        )
        .unwrap(),
        capability_sha256: zero(),
        plan_sha256: zero(),
        issued_at: UtcTimestamp("2026-01-01T00:00:00Z".to_owned()),
        expires_at: UtcTimestamp("2026-01-01T00:10:00Z".to_owned()),
        predicted_paths: predicted_paths(&intent, &settings).unwrap(),
        path_prediction: ExportPlanPathPrediction::ExactRequestedDays,
        required_actions: vec![],
        limitations: vec![],
        side_effects: ZeroSideEffects {
            health_reads: 0,
            earliest_date_reads: 0,
            content_preview_reads: 0,
            output_writes: 0,
            quota_consumed: 0,
            settings_mutations: 0,
            credential_enrollments: 0,
            wake_enrollments: 0,
        },
        intent,
        effective_settings: settings,
    };
    plan.plan_sha256 = plan_digest(&plan).unwrap();
    plan
}
fn execute() -> ExecuteRequest {
    let plan = plan();
    ExecuteRequest {
        schema: ExecuteRequestSchema::HealthmdAgentExecuteRequest,
        schema_version: 1,
        request_id: id(102),
        job_id: id(103),
        idempotency_key: id(104),
        approval: Approval {
            schema: ApprovalSchema::HealthmdAgentApproval,
            schema_version: 1,
            approval_id: id(105),
            authority_id: id(10),
            binding: approval_binding(&plan),
            rights: vec![ApprovalRightsItem::ExportExecute],
            approved_at: UtcTimestamp("2026-01-01T00:01:00Z".to_owned()),
        },
        plan,
    }
}
fn discovery() -> Discovery {
    let mut discovery = Discovery {
        schema: DiscoverySchema::HealthmdAgentDiscovery,
        schema_version: 1,
        request_id: id(106),
        peer: peer(),
        capability_revision: 1,
        capability_sha256: zero(),
        issued_at: UtcTimestamp("2026-01-01T00:00:00Z".to_owned()),
        expires_at: UtcTimestamp("2026-01-01T00:10:00Z".to_owned()),
        source_calendar_timezone: CalendarZone("Etc/UTC".to_owned()),
        features: vec![
            DiscoveryFeaturesItem::BoundExecution,
            DiscoveryFeaturesItem::ExplicitSettings,
            DiscoveryFeaturesItem::ZeroHealthPlan,
        ],
        settings_policies: vec![DiscoverySettingsPoliciesItem::Explicit],
        output_profiles: vec![OutputSettingsOutputProfile::AndroidAnalyticalV5],
        projection_products: vec![],
        projection_catalog_sha256: zero(),
        projection_source_catalog: None,
        query_catalog_sha256: zero(),
        query_operations: vec![],
        budgets: Budgets {
            max_page_items: 1000,
            max_page_bytes: 1_048_576,
            max_snapshot_bytes: 67_108_864,
            max_capture_seconds: 120,
            max_calendar_days: 366_000,
            cursor_idle_seconds: 600,
            cursor_lifetime_seconds: 3600,
        },
        output_support: OutputSupport {
            formats: vec![OutputSettingsFormatsItem::Json],
            write_modes: vec![OutputSettingsWriteMode::Overwrite],
            compatibility_detail: vec![CaptureCompatibilityDetail::Summary],
            native_archive_products: vec![OutputSupportNativeArchiveProductsItem::None],
            setting_pointers: vec![],
            path_tokens: vec![],
            max_artifacts: 4096,
            max_path_bytes: 4096,
        },
        control_operations: vec![],
        authority_references: vec![],
        lifecycle: DiscoveryLifecycle::AndroidUserStartedServiceAfterFirstUnlock,
        configuration_protection: DiscoveryConfigurationProtection::Locked,
        native_grants: DiscoveryNativeGrants::Required,
        entitlement: DiscoveryEntitlement::Required,
        required_actions: vec![],
    };
    discovery.capability_sha256 = capability_digest(&discovery).unwrap();
    discovery
}
fn receipt() -> ExecutionReceipt {
    let request = execute();
    ExecutionReceipt {
        schema: ExecutionReceiptSchema::HealthmdAgentExecutionReceipt,
        schema_version: 1,
        job_id: request.job_id.clone(),
        binding: approval_binding(&request.plan),
        request_sha256: document_digest(&request).unwrap(),
        manifest_sha256: zero(),
        status: ExecutionReceiptStatus::Accepted,
        source_acknowledged: false,
        artifact_count: 0,
        committed_partition_count: 0,
        frontier_sha256: zero(),
        expires_at: UtcTimestamp("2026-01-08T00:01:00Z".to_owned()),
    }
}
fn native_constructors() -> Vec<(&'static str, Value)> {
    vec![
        ("rust-discovery", json!(discovery())),
        ("rust-intent", json!(intent())),
        ("rust-plan", json!(plan())),
        ("rust-execute", json!(execute())),
        ("rust-receipt", json!(receipt())),
    ]
}
#[test]
fn independent_native_constructors_are_typed_not_tree_reencodes() {
    let zones = zones();
    let metrics = metrics();
    let projection = projection_digest();
    let config = configuration(&zones, &metrics, &projection);
    validate_discovery(&discovery(), &config).unwrap();
    validate_export_intent(&intent(), &config).unwrap();
    validate_export_plan(&plan(), &config).unwrap();
    validate_execution_receipt(&receipt()).unwrap();
    for (_, value) in native_constructors() {
        let bytes = canonical_json(&value).unwrap();
        assert_eq!(
            canonical_json(&decode_document(&bytes).unwrap()).unwrap(),
            bytes
        );
    }
    // A syntactically valid approval/request remains unissued until checked against stores.
    let f = fixture();
    let c = case(&f, "approved-execution");
    let request = execute();
    assert_eq!(
        with_store(&c["context"], Some(&request), |store| validate_execute(
            &request, store
        ))
        .unwrap_err(),
        Error::BindingChanged
    );
}

#[test]
fn missing_private_grants_and_decisions_fail_closed() {
    let fixture = fixture();
    let mut c = case(&fixture, "approved-execution");
    let request: ExecuteRequest = typed(&c["value"]);
    c["context"]["stored_native_delegations"] = json!({});
    assert_eq!(
        with_store(&c["context"], Some(&request), |store| validate_execute(
            &request, store
        ))
        .unwrap_err(),
        Error::ApprovalRequired
    );
    let mut c = case(&fixture, "bootstrap-first-approval-request");
    c["context"]
        .as_object_mut()
        .unwrap()
        .remove("approved_export_binding_sha256");
    assert_eq!(
        check_document(&c["value"], &c["context"]).unwrap_err(),
        Error::ApprovalRequired
    );
}

fn candidate<T: Serialize>(value: &T, provenance: &str) -> Value {
    let bytes = canonical_json(value).unwrap();
    json!({"provenance":provenance,"value":value,"canonical_base64":STANDARD.encode(&bytes),"sha256":sha256_hex(&bytes)})
}
#[test]
fn explicit_scratch_candidate_generation_and_coverage() {
    if std::env::var("HEALTHMD_GENERATE_AGENT_BRIDGE_V4").as_deref() != Ok("1") {
        return;
    }
    let output = std::env::var_os("HEALTHMD_AGENT_BRIDGE_CANDIDATES")
        .expect("explicit scratch candidate output is required");
    let output = std::path::PathBuf::from(output);
    assert!(output.is_absolute());
    if let Ok(metadata) = output.symlink_metadata() {
        assert!(
            !metadata.file_type().is_symlink(),
            "candidate output cannot be a symlink"
        );
    }
    let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../..")
        .canonicalize()
        .unwrap();
    let parent = output.parent().unwrap().canonicalize().unwrap();
    assert!(
        !parent.starts_with(repo),
        "candidate output must be outside repository sources"
    );
    let fixture = fixture();
    let typed_indices = typed_vectors(&fixture);
    let ids = semantic_ids(&fixture);
    let mut vectors: Vec<_> = fixture["canonical_vectors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| candidate(&v["value"], "generic-codec-python-candidate-input"))
        .collect();
    vectors.extend(
        native_constructors()
            .into_iter()
            .map(|(name, value)| candidate(&value, name)),
    );
    let cases: Vec<_> = fixture["cases"].as_array().unwrap().iter().map(|case| json!({"family":case["family"],"id":case["id"],
        "coverage":if ids.contains(&case["id"].as_str().unwrap().to_owned()) { "typed-semantic-synthetic-context" } else { "unsupported-or-pending" }})).collect();
    let payload = json!({"language":"rust","coverage":{"generic_codec_vectors":58,"typed_dto_vector_indices":typed_indices,
        "independent_typed_constructors":["discovery","intent","plan","execute","receipt"],"semantic_fixture_case_ids":ids,"cases":cases,
        "limitations":["synthetic immutable store snapshots, not native persistence/CAS","no query/projection/control envelope support","ASCII-only path collision subset; Unicode paths fail closed","no capture/transfer/artifact bytes/filesystem/device proof"]},"vectors":vectors});
    std::fs::write(output, serde_json::to_vec_pretty(&payload).unwrap()).unwrap();
}
