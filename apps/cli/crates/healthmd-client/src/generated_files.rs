//! Source-aware generated-file planning shared by CLI and MCP. No health capture happens here.

use std::{path::PathBuf, time::Duration};

use healthmd_protocol::{
    JOB_LIFETIME_SECONDS,
    models::{DateSelection, ExportRequest, ResponseMode, SettingsPolicy},
    v2,
};
use uuid::Uuid;

use crate::{
    ClientError,
    credentials::CredentialStore,
    direct::{AndroidExportResult, DirectClient, FileExportResult, SourceKind},
    file_receiver::GeneratedDestination,
};

/// Immutable source/destination plan. Construction pins the selected installation, never a
/// default that could select a different phone after a wake window.
#[derive(Clone, Debug)]
pub struct GeneratedFileExportPlan {
    source_id: Uuid,
    request: GeneratedFileRequest,
}

#[derive(Clone, Debug)]
enum GeneratedFileRequest {
    Ios(ExportRequest),
    Android(v2::ExportRequest, PathBuf),
}

pub enum GeneratedFileExportResult {
    Ios(FileExportResult),
    Android(AndroidExportResult),
}

impl GeneratedFileExportPlan {
    pub const fn source_id(&self) -> Uuid {
        self.source_id
    }
}

impl<C: CredentialStore> DirectClient<C> {
    /// Validate and bind a normalized generated-file request to exactly one trusted phone.
    ///
    /// `uses_source_default` is true only when the caller omitted a settings policy. Android's
    /// default is saved settings; an explicit iOS requested-dates policy cannot be downgraded.
    ///
    /// # Errors
    ///
    /// Rejects ambiguous trust, unsafe destinations, incompatible selectors or settings policies.
    pub async fn prepare_generated_files(
        &self,
        request: ExportRequest,
        uses_source_default: bool,
        device_id: Option<Uuid>,
    ) -> Result<GeneratedFileExportPlan, ClientError> {
        let selected = self.selected_source(device_id).await?;
        let source_id = selected.installation_id.0;
        let source = if selected.platform == Some(healthmd_protocol::wire::PeerPlatform::Android) {
            SourceKind::Android
        } else {
            SourceKind::Ios
        };
        plan_generated_files(request, uses_source_default, source_id, source)
    }

    /// Execute the pinned plan through the source's existing durable protocol and receiver.
    ///
    /// # Errors
    ///
    /// Returns the source-aware export's authentication, capability, transfer or lifecycle errors.
    pub async fn export_generated_files(
        &self,
        plan: GeneratedFileExportPlan,
        port: u16,
        timeout: Duration,
    ) -> Result<GeneratedFileExportResult, ClientError> {
        match plan.request {
            GeneratedFileRequest::Ios(request) => self
                .export_files(request, Some(plan.source_id), port, timeout)
                .await
                .map(GeneratedFileExportResult::Ios),
            GeneratedFileRequest::Android(request, destination) => self
                .export_android(
                    request,
                    Some(destination),
                    Some(plan.source_id),
                    port,
                    timeout,
                )
                .await
                .map(GeneratedFileExportResult::Android),
        }
    }
}

fn validate_generated_file_request(request: &ExportRequest) -> Result<(), ClientError> {
    if request.protocol_version != 1
        || request.response_mode != ResponseMode::WriteFiles
        || request.raw_profile.is_some()
        || (request.settings_policy == SettingsPolicy::Profile)
            != request.profile_reference.is_some()
    {
        return Err(ClientError::InvalidTransfer(
            "invalid generated-file settings".into(),
        ));
    }
    if let Some(reference) = &request.profile_reference {
        if request.canonical_selection.is_some()
            || reference.profile_id.len() != 36
            || Uuid::parse_str(&reference.profile_id).is_err()
            || ![8, 13, 18, 23]
                .iter()
                .all(|index| reference.profile_id.as_bytes()[*index] == b'-')
            || reference.name.as_ref().is_some_and(|name| {
                name.is_empty()
                    || name.trim() != name
                    || name.chars().count() > 128
                    || name.chars().any(char::is_control)
            })
        {
            return Err(ClientError::InvalidTransfer(
                "invalid profile reference or scope".into(),
            ));
        }
    }
    Ok(())
}

fn plan_generated_files(
    request: ExportRequest,
    uses_source_default: bool,
    source_id: Uuid,
    source: SourceKind,
) -> Result<GeneratedFileExportPlan, ClientError> {
    validate_generated_file_request(&request)?;
    // Apple has no explicit profile-policy advertisement in the current hello contract. Do not
    // infer it from marketing versions, query v3, or canonical-extraction support. Central
    // protocol/Apple work must add a reviewed capability before this lane can enable profiles.
    if source == SourceKind::Ios && request.settings_policy == SettingsPolicy::Profile {
        return Err(ClientError::ExportUnsupported);
    }
    if source == SourceKind::Android
        && (request.canonical_selection.is_some()
            || (request.settings_policy == SettingsPolicy::RequestedDatesOnly
                && !uses_source_default))
    {
        return Err(ClientError::ExportUnsupported);
    }
    let root = &request
        .destination
        .as_ref()
        .ok_or_else(|| {
            ClientError::InvalidTransfer("generated-file destination is missing".into())
        })?
        .root_path;
    let destination = GeneratedDestination::open(std::path::Path::new(root))?;
    let planned = match source {
        SourceKind::Ios => GeneratedFileRequest::Ios(request),
        SourceKind::Android => {
            let date_selection = match request.date_selection {
                DateSelection::Exact(range) => v2::DateSelection::Exact {
                    start_date: range.start,
                    end_date: range.end,
                },
                DateSelection::AllAvailable(_) => v2::DateSelection::AllAvailable,
            };
            let profile_reference =
                request
                    .profile_reference
                    .map(|reference| v2::ProfileReference {
                        profile_id: reference.profile_id,
                        name: reference.name,
                    });
            let display_name = destination
                .root()
                .file_name()
                .and_then(|name| name.to_str())
                .filter(|name| !name.is_empty())
                .unwrap_or("Health Exports")
                .to_owned();
            let expires_at = request
                .created_at
                .checked_add_signed(chrono::Duration::seconds(JOB_LIFETIME_SECONDS))
                .ok_or_else(|| {
                    ClientError::InvalidTransfer("invalid generated-file lifetime".into())
                })?;
            let wire_request = v2::ExportRequest {
                job_id: request.job_id.0,
                created_at: request.created_at,
                expires_at,
                source_installation_id: source_id,
                date_selection,
                product: v2::ExportProduct::GeneratedFilesV1 {
                    settings_policy: if profile_reference.is_some() {
                        v2::SettingsPolicy::Profile
                    } else {
                        v2::SettingsPolicy::SavedDeviceSettings
                    },
                    profile_reference,
                },
                destination: Some(v2::DestinationBinding {
                    binding_sha256: destination.binding_sha256()?,
                    display_name,
                }),
            };
            GeneratedFileRequest::Android(wire_request, destination.root().to_path_buf())
        }
    };
    Ok(GeneratedFileExportPlan {
        source_id,
        request: planned,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use healthmd_protocol::{
        encoding::SwiftUuid,
        models::{ExportDestination, ProfileReference},
    };

    fn request(root: &std::path::Path) -> ExportRequest {
        ExportRequest {
            protocol_version: 1,
            job_id: SwiftUuid(Uuid::new_v4()),
            created_at: chrono::Utc::now(),
            date_selection: DateSelection::AllAvailable(healthmd_protocol::wire::Empty {}),
            settings_policy: SettingsPolicy::RequestedDatesOnly,
            profile_reference: None,
            response_mode: ResponseMode::WriteFiles,
            raw_profile: None,
            canonical_selection: None,
            destination: Some(ExportDestination {
                root_path: root.to_str().unwrap().into(),
            }),
        }
    }

    #[test]
    fn both_platforms_keep_exact_policy_source_and_destination() {
        let temporary = tempfile::TempDir::new().unwrap();
        let root = temporary.path().join("exports");
        std::fs::create_dir(&root).unwrap();
        let input = request(&root);
        let source_id = Uuid::new_v4();
        let ios = plan_generated_files(input.clone(), true, source_id, SourceKind::Ios).unwrap();
        assert_eq!(ios.source_id(), source_id);
        let GeneratedFileRequest::Ios(ios_request) = ios.request else {
            panic!("wrong adapter")
        };
        assert_eq!(ios_request, input);
        let android =
            plan_generated_files(input.clone(), true, source_id, SourceKind::Android).unwrap();
        let GeneratedFileRequest::Android(wire, path) = android.request else {
            panic!("wrong adapter")
        };
        assert_eq!(path, std::fs::canonicalize(&root).unwrap());
        assert_eq!(wire.source_installation_id, source_id);
        assert!(matches!(
            wire.product,
            v2::ExportProduct::GeneratedFilesV1 {
                settings_policy: v2::SettingsPolicy::SavedDeviceSettings,
                profile_reference: None
            }
        ));
        let encoded =
            String::from_utf8(healthmd_protocol::encoding::canonical_json(&wire).unwrap()).unwrap();
        assert!(!encoded.contains(temporary.path().to_str().unwrap()));
        assert_eq!(
            wire.destination.unwrap().binding_sha256,
            GeneratedDestination::open(&root)
                .unwrap()
                .binding_sha256()
                .unwrap()
        );
        assert!(matches!(
            plan_generated_files(input, false, source_id, SourceKind::Android),
            Err(ClientError::ExportUnsupported)
        ));
    }

    #[test]
    fn profiles_are_exact_and_apple_fails_closed_without_an_advertisement() {
        let temporary = tempfile::TempDir::new().unwrap();
        let mut input = request(temporary.path());
        input.settings_policy = SettingsPolicy::Profile;
        let reference = ProfileReference {
            profile_id: "11111111-2222-4333-8444-555555555555".into(),
            name: Some("Weekly Sleep".into()),
        };
        input.profile_reference = Some(reference.clone());
        let source_id = Uuid::new_v4();
        assert!(matches!(
            plan_generated_files(input.clone(), false, source_id, SourceKind::Ios),
            Err(ClientError::ExportUnsupported)
        ));
        let android = plan_generated_files(input, false, source_id, SourceKind::Android).unwrap();
        let GeneratedFileRequest::Android(wire, _) = android.request else {
            panic!("wrong adapter")
        };
        assert_eq!(
            wire.product.profile_reference().unwrap().profile_id,
            reference.profile_id
        );
        assert_eq!(
            wire.product.profile_reference().unwrap().name,
            reference.name
        );
    }
}
