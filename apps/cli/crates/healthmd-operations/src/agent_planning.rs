//! Fixed local planning DTO. It is not grant/root enrollment, approval consent, or export.
use healthmd_protocol::v4::{
    self, ApprovalRequest, AuthorityReference, AuthorityReferenceIssuer, CalendarZone, ControlUuid,
    DailyNotes, Dates, Dictionary, Error, FilenameTemplate, Frontmatter, IndividualEntries,
    Markdown, MarkdownStyle, OutputSettings, OutputSettingsFormatsItem,
    OutputSettingsOutputProfile, OutputSettingsWriteMode, Packaging, PeerPlatform, Presentation,
    PresentationDisplayUnits, PresentationMachineUnits, RelativePath, SemanticId, ValidateShape,
    resolve_dates, validate_output_settings,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AgentPlanInput {
    pub dates: Dates,
    pub calendar_timezone: CalendarZone,
    pub metric_ids: Vec<SemanticId>,
    pub output_profile: OutputSettingsOutputProfile,
    pub subfolder: String,
    pub folder_template: String,
    pub filename_template: String,
    pub destination_binding_id: ControlUuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub native_authority_reference: Option<AuthorityReference>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host_authority_reference: Option<AuthorityReference>,
}
impl ValidateShape for AgentPlanInput {
    fn validate_shape(&self) -> Result<(), Error> {
        self.dates.validate_shape()?;
        resolve_dates(&self.dates)?;
        self.calendar_timezone.validate_shape()?;
        self.destination_binding_id.validate_shape()?;
        if self.metric_ids.is_empty()
            || self.metric_ids.len() > 256
            || !self.metric_ids.windows(2).all(|p| p[0] < p[1])
        {
            return Err(Error::InvalidRequest);
        }
        for id in &self.metric_ids {
            id.validate_shape()?;
        }
        for (reference, issuer) in [
            (
                &self.native_authority_reference,
                AuthorityReferenceIssuer::NativeSource,
            ),
            (
                &self.host_authority_reference,
                AuthorityReferenceIssuer::AuthorizedHost,
            ),
        ] {
            if let Some(reference) = reference {
                reference.validate_shape()?;
                if reference.issuer != issuer {
                    return Err(Error::ApprovalRequired);
                }
            }
        }
        self.settings()?;
        Ok(())
    }
}
impl AgentPlanInput {
    /// Complete explicit preset, matching the reviewed native bounded resolver subset.
    /// # Errors
    /// Unsupported profile/layout rejects locally; no mobile defaults are inherited.
    pub fn settings(&self) -> Result<OutputSettings, Error> {
        summary_json_settings(
            &self.output_profile,
            self.subfolder.clone(),
            self.folder_template.clone(),
            self.filename_template.clone(),
        )
    }
}

fn summary_json_settings(
    profile: &OutputSettingsOutputProfile,
    subfolder: String,
    folder_template: String,
    filename_template: String,
) -> Result<OutputSettings, Error> {
    if *profile == OutputSettingsOutputProfile::AndroidAnalyticalV5
        || ![&subfolder, &folder_template, &filename_template]
            .iter()
            .all(|s| s.is_ascii())
        || subfolder.contains(['{', '}'])
    {
        return Err(Error::UnsupportedCapability);
    }
    let settings = OutputSettings {
        formats: vec![OutputSettingsFormatsItem::Json],
        output_profile: profile.clone(),
        subfolder: RelativePath(subfolder),
        folder_template: RelativePath(folder_template),
        filename_template: FilenameTemplate(filename_template),
        write_mode: OutputSettingsWriteMode::Overwrite,
        presentation: Presentation {
            display_units: PresentationDisplayUnits::Metric,
            machine_units: PresentationMachineUnits::Canonical,
            locale: "en-US".into(),
            include_metadata: true,
            group_by_category: true,
            frontmatter: Frontmatter {
                enabled_field_ids: vec![],
                custom_fields: vec![],
                include_units: true,
                include_capture_diagnostics: false,
            },
            markdown: Markdown {
                style: MarkdownStyle::Lists,
                custom_template: String::new(),
                placeholder_ids: vec![],
            },
        },
        individual_entries: IndividualEntries {
            enabled: false,
            metric_ids: vec![],
            folder_template: RelativePath(String::new()),
            filename_template: FilenameTemplate("{metric}-{date}".into()),
            category_folders: false,
        },
        daily_notes: DailyNotes {
            enabled: false,
            only: false,
            folder_template: RelativePath(String::new()),
            filename_template: FilenameTemplate("{date}".into()),
            create_if_missing: false,
            section_ids: vec![],
        },
        packaging: Packaging::LooseFiles {},
        dictionary: Dictionary::None {},
    };
    validate_output_settings(
        &settings,
        &if *profile == OutputSettingsOutputProfile::AppleV8 {
            PeerPlatform::Apple
        } else {
            PeerPlatform::Android
        },
    )?;
    Ok(settings)
}

/// Decode complete planning arguments using the strict integrated v4 grammar.
/// # Errors
/// Invalid bounds, duplicate keys, unknown fields, nulls or unsupported axes reject.
pub fn agent_plan_from_bytes(raw: &[u8]) -> Result<AgentPlanInput, Error> {
    v4::decode_typed(raw)
}
/// Decode an exact issued-plan binding; the request cannot establish consent.
/// # Errors
/// Invalid, ambiguous, malformed or out-of-bounds JSON rejects.
pub fn agent_approval_from_bytes(raw: &[u8]) -> Result<ApprovalRequest, Error> {
    v4::decode_typed(raw)
}

/// New-operation raw MCP guard, applied before tolerant legacy JSON-RPC decoding can discard
/// duplicate keys. Legacy query grammar/metadata/floating-point behavior remains unchanged.
pub fn agent_rpc_bytes_valid(raw: &[u8]) -> bool {
    let Ok(tree) = v4::parse_strict(raw) else {
        return false;
    };
    let Some(arguments) = tree.pointer("/params/arguments") else {
        return false;
    };
    let Ok(bytes) = v4::canonical_json(arguments) else {
        return false;
    };
    match tree.pointer("/params/name").and_then(Value::as_str) {
        Some("healthmd_export_plan") => agent_plan_from_bytes(&bytes).is_ok(),
        Some("healthmd_export_approval") => agent_approval_from_bytes(&bytes).is_ok(),
        _ => false,
    }
}

pub fn plan_input_schema() -> Value {
    let uuid = json!({"type":"string","pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"});
    let date = json!({"type":"string","pattern":"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"});
    let reference = |issuer: &str| {
        json!({"type":"object","additionalProperties":false,"required":["authority_id","issuer","grant_revision","grant_sha256"],"properties":{
        "authority_id":uuid,"issuer":{"const":issuer},"grant_revision":{"type":"integer","minimum":1,"maximum":2_147_483_647},"grant_sha256":{"type":"string","pattern":"^[0-9a-f]{64}$"}}})
    };
    json!({"type":"object","additionalProperties":false,
    "required":["dates","calendar_timezone","metric_ids","output_profile","subfolder","folder_template","filename_template","destination_binding_id"],
    "properties":{
        "dates":{"oneOf":[
            {"type":"object","additionalProperties":false,"required":["type","range"],"properties":{"type":{"const":"exact"},"range":{"type":"object","additionalProperties":false,"required":["start_date","end_date"],"properties":{"start_date":date,"end_date":date}}}},
            {"type":"object","additionalProperties":false,"required":["type"],"properties":{"type":{"const":"all_available"}}},
            {"type":"object","additionalProperties":false,"required":["type","anchor_date","days"],"properties":{"type":{"const":"past_complete_days"},"anchor_date":date,"days":{"type":"integer","minimum":1,"maximum":3650}}}
        ]},
        "calendar_timezone":{"type":"string","minLength":1,"maxLength":128},
        "metric_ids":{"type":"array","minItems":1,"maxItems":256,"uniqueItems":true,"items":{"type":"string","pattern":"^[a-z][a-z0-9_.-]{0,127}$"},"description":"Sorted exact reviewed semantic IDs; SDNN hrv and android.hrv_rmssd are distinct."},
        "output_profile":{"enum":["apple-v8","android-frozen-v4"]},
        "subfolder":{"type":"string","maxLength":4096},"folder_template":{"type":"string","maxLength":4096},"filename_template":{"type":"string","minLength":1,"maxLength":255},
        "destination_binding_id":uuid,"native_authority_reference":reference("native_source"),"host_authority_reference":reference("authorized_host")
    }})
}

pub fn approval_input_schema() -> Value {
    let uuid = json!({"type":"string","pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"});
    let digest = json!({"type":"string","pattern":"^[0-9a-f]{64}$"});
    let revision = json!({"type":"integer","minimum":1,"maximum":2_147_483_647});
    let reference = |issuer: &str| json!({"type":"object","additionalProperties":false,"required":["authority_id","issuer","grant_revision","grant_sha256"],"properties":{"authority_id":uuid,"issuer":{"const":issuer},"grant_revision":revision,"grant_sha256":digest}});
    json!({"type":"object","additionalProperties":false,"required":["schema","schema_version","request_id","plan_id","binding"],"properties":{
        "schema":{"const":"healthmd.agent_approval_request"},"schema_version":{"const":1},"request_id":uuid,"plan_id":uuid,
        "binding":{"type":"object","additionalProperties":false,"required":["authority_references","capability_sha256","destination","expires_at","peer","plan_sha256","revisions","scope_sha256","settings_sha256"],"properties":{
            "authority_references":{"type":"object","additionalProperties":false,"required":["host","native"],"properties":{"host":reference("authorized_host"),"native":reference("native_source")}},
            "capability_sha256":digest,"plan_sha256":digest,"scope_sha256":digest,"settings_sha256":digest,
            "destination":{"type":"object","additionalProperties":false,"required":["binding_id","host_installation_id","identity_sha256","revision"],"properties":{"binding_id":uuid,"host_installation_id":uuid,"identity_sha256":digest,"revision":revision}},
            "peer":{"type":"object","additionalProperties":false,"required":["source_installation_id","host_installation_id","platform"],"properties":{"source_installation_id":uuid,"host_installation_id":uuid,"platform":{"enum":["apple","android"]}}},
            "expires_at":{"type":"string","pattern":"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"},
            "revisions":{"type":"array","maxItems":16,"items":{"type":"object","additionalProperties":false,"required":["domain","object_id","revision","sha256"],"properties":{"domain":{"enum":["device_settings","native_profile","local_recipe","host_schedule","native_schedule","native_destination","native_credential_reference"]},"object_id":uuid,"revision":revision,"sha256":digest}}}
        }}
    }})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn arguments() -> Value {
        json!({"dates":{"type":"exact","range":{"start_date":"2026-01-01","end_date":"2026-01-02"}},"calendar_timezone":"UTC","metric_ids":["steps"],"output_profile":"apple-v8","subfolder":"","folder_template":"{year}","filename_template":"{date}","destination_binding_id":"00000000-0000-4000-8000-000000000003"})
    }
    #[test]
    fn strict_complete_dto_rejects_consent_unknowns_and_lossy_json() {
        let raw = serde_json::to_vec(&arguments()).unwrap();
        assert!(agent_plan_from_bytes(&raw).is_ok());
        let mut value = arguments();
        value["approve"] = json!(true);
        assert!(agent_plan_from_bytes(&serde_json::to_vec(&value).unwrap()).is_err());
        let mut duplicate = raw.clone();
        duplicate.pop();
        duplicate.extend_from_slice(b",\"metric_ids\":[\"steps\"]}");
        assert!(agent_plan_from_bytes(&duplicate).is_err());
        assert!(agent_plan_from_bytes(b"\xff").is_err());
        let mut value = arguments();
        value["metric_ids"] = json!([]);
        assert!(agent_plan_from_bytes(&serde_json::to_vec(&value).unwrap()).is_err());
        let mut value = arguments();
        value["output_profile"] = json!("android-analytical-v5");
        assert!(agent_plan_from_bytes(&serde_json::to_vec(&value).unwrap()).is_err());
        let mut value = arguments();
        value["filename_template"] = json!("../escape");
        assert!(agent_plan_from_bytes(&serde_json::to_vec(&value).unwrap()).is_err());
    }
}
