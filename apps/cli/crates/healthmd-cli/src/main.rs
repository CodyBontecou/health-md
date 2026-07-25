#![forbid(unsafe_code)]

use std::{
    fs,
    io::{self, Write as _},
    path::{Path, PathBuf},
    process::ExitCode,
    time::Duration,
};

use chrono::{Duration as ChronoDuration, Local, SecondsFormat, Timelike as _, Utc};
use clap::{Args, Parser, Subcommand, ValueEnum, error::ErrorKind};
use healthmd_client::{
    ClientError,
    direct::{DirectClient, SourceStatus},
    file_receiver::GeneratedDestination,
    job::{JobRecord, JobState},
};
use healthmd_protocol::{
    encoding::SwiftUuid,
    models::{
        CanonicalSelection, DateSelection, DetailLevel, ExactDateSelection, ExportRequest,
        ResponseMode, SettingsPolicy,
    },
    v2,
    wire::RawProfile,
};
use serde_json::{Value, json};
use uuid::Uuid;

#[cfg(not(windows))]
use healthmd_protocol::models::ExportDestination;

#[derive(Debug, Parser)]
#[command(
    name = "healthmd",
    version,
    about = "Portable command-line access to Health.md",
    long_about = "Request health exports from an open, paired iOS or Android device running Health.md. Source health reads always occur on the mobile device."
)]
struct Cli {
    /// Backend to use. Direct is the portable mobile connection.
    #[arg(long, global = true, default_value = "direct")]
    backend: Backend,

    /// Explicit direct transport. Nearby is supported only by the legacy Apple client.
    #[arg(long, global = true, default_value = "manual-ip")]
    transport: Transport,

    /// Trusted mobile installation UUID when more than one source is paired.
    #[arg(long, global = true)]
    device: Option<Uuid>,

    /// Manual IP listener port used by the direct backend.
    #[arg(long, global = true, default_value_t = healthmd_protocol::DEFAULT_MANUAL_IP_PORT)]
    port: u16,

    #[command(subcommand)]
    command: Command,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, ValueEnum)]
enum Backend {
    #[value(name = "mac-app")]
    MacApp,
    #[default]
    Direct,
}

impl Backend {
    const fn wire_name(self) -> &'static str {
        match self {
            Self::MacApp => "mac-app",
            Self::Direct => "direct",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, ValueEnum)]
enum Transport {
    #[default]
    #[value(name = "manual-ip")]
    ManualIp,
    Nearby,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Inspect backend readiness or a durable direct job.
    Status(StatusArgs),
    /// Request platform-native raw data or generated files from the mobile source.
    Export(ExportArgs),
    /// Request a scoped canonical health-data projection (currently iOS only).
    Extract(ExtractArgs),
    /// Resume an interrupted durable direct job.
    Resume(ResumeArgs),
    /// Request cancellation of a durable direct job.
    Cancel(JobArgs),
    /// Pair and manage direct mobile trust.
    Direct(DirectArgs),
}

#[derive(Debug, Args)]
struct StatusArgs {
    /// Read a durable local job instead of contacting iPhone.
    #[arg(long)]
    job: Option<Uuid>,
}

#[derive(Debug, Args)]
struct ExportArgs {
    #[command(flatten)]
    dates: DateArgs,

    /// Return the source platform's native validated raw artifact instead of generated files.
    #[arg(long)]
    raw: bool,

    /// Atomic output path for raw JSON/NDJSON. Omit to stream the validated artifact to stdout.
    #[arg(long)]
    output: Option<PathBuf>,

    /// Existing absolute destination directory for generated files.
    #[arg(long)]
    destination: Option<PathBuf>,

    /// Use the paired mobile source's saved export settings.
    #[arg(long, visible_alias = "use-iphone-settings")]
    use_device_settings: bool,

    /// Provider-native Android raw source. Defaults to Health Connect.
    #[arg(long, default_value = "health_connect")]
    provider: String,

    /// Physical format for Android raw snapshots.
    #[arg(long, value_enum, default_value = "ndjson")]
    raw_format: RawArtifactFormat,

    /// Accept a validated partial result without a failure exit status.
    #[arg(long)]
    allow_partial: bool,

    #[arg(long, default_value_t = 300)]
    timeout: u64,

    #[command(flatten)]
    selection: SelectionArgs,
}

#[derive(Debug, Args)]
struct ExtractArgs {
    #[command(flatten)]
    dates: DateArgs,

    #[command(flatten)]
    selection: SelectionArgs,

    /// Atomic output path. Omit to stream validated JSON to stdout.
    #[arg(long)]
    output: Option<PathBuf>,

    /// Accept a validated partial result without a failure exit status.
    #[arg(long)]
    allow_partial: bool,

    #[arg(long, default_value_t = 300)]
    timeout: u64,

    #[arg(long, value_enum, default_value = "json")]
    format: ExtractionFormat,
}

#[derive(Debug, Args)]
struct DateArgs {
    #[arg(long, conflicts_with_all = ["last", "from", "to", "all"])]
    yesterday: bool,

    #[arg(long, value_name = "DAYS", conflicts_with_all = ["yesterday", "from", "to", "all"])]
    last: Option<u32>,

    #[arg(long, value_name = "YYYY-MM-DD", requires = "to", conflicts_with_all = ["yesterday", "last", "all"])]
    from: Option<String>,

    #[arg(long, value_name = "YYYY-MM-DD", requires = "from", conflicts_with_all = ["yesterday", "last", "all"])]
    to: Option<String>,

    #[arg(long, conflicts_with_all = ["yesterday", "last", "from", "to"])]
    all: bool,
}

#[derive(Debug, Args)]
struct SelectionArgs {
    #[arg(long = "metric")]
    metrics: Vec<String>,

    #[arg(long = "category")]
    categories: Vec<String>,

    #[arg(long, conflicts_with = "metrics")]
    all_metrics: bool,

    #[arg(long, value_enum, default_value = "summary")]
    detail: Detail,

    #[arg(long = "object")]
    objects: Vec<String>,

    #[arg(long = "field")]
    fields: Vec<String>,

    #[arg(long = "source")]
    sources: Vec<String>,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, ValueEnum)]
enum Detail {
    #[default]
    Summary,
    Lossless,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, ValueEnum)]
enum ExtractionFormat {
    #[default]
    Json,
    Jsonl,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, ValueEnum)]
enum RawArtifactFormat {
    Json,
    #[default]
    Ndjson,
}

#[derive(Debug, Args)]
struct ResumeArgs {
    job_id: Uuid,

    #[arg(long)]
    output: Option<PathBuf>,

    #[arg(long, value_enum)]
    format: Option<ExtractionFormat>,

    #[arg(long)]
    allow_partial: bool,

    #[arg(long, default_value_t = 300)]
    timeout: u64,
}

#[derive(Debug, Args)]
struct JobArgs {
    job_id: Uuid,
}

#[derive(Debug, Args)]
struct DirectArgs {
    #[command(subcommand)]
    command: DirectCommand,
}

#[derive(Debug, Subcommand)]
enum DirectCommand {
    /// Pair this CLI installation with an open iOS or Android app.
    Pair(PairArgs),
    /// List this installation and locally trusted devices without network access.
    Devices,
    /// Remove local trust for one mobile source.
    Unpair { device_id: Uuid },
    /// Explicitly discard all local direct trust after confirmation.
    ResetTrust {
        #[arg(long)]
        confirm: bool,
    },
}

#[derive(Debug, Args)]
struct PairArgs {
    /// Override the six-digit code used by iOS pairing.
    #[arg(long)]
    pairing_code: Option<String>,

    /// Override the high-entropy twenty-digit code used by Android pairing.
    #[arg(long)]
    android_pairing_code: Option<String>,

    #[arg(long, default_value_t = 120)]
    timeout: u64,
}

#[derive(Debug)]
struct CommandError {
    backend: &'static str,
    code: &'static str,
    message: String,
}

enum CommandOutput {
    Json(Value),
    Artifact {
        source: PathBuf,
        output: Option<PathBuf>,
    },
    JsonlArtifact {
        source: PathBuf,
        receipt: PathBuf,
        output: Option<PathBuf>,
    },
}

struct CommandSuccess {
    output: CommandOutput,
    exit_code: u8,
}

impl CommandSuccess {
    const fn json(value: Value) -> Self {
        Self {
            output: CommandOutput::Json(value),
            exit_code: 0,
        }
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error)
            if matches!(
                error.kind(),
                ErrorKind::DisplayHelp | ErrorKind::DisplayVersion
            ) =>
        {
            print!("{error}");
            return ExitCode::SUCCESS;
        }
        Err(error) => {
            let value = json!({
                "backend": "direct",
                "error": "invalid_request",
                "message": error.to_string(),
                "status": "failure"
            });
            println!(
                "{}",
                serde_json::to_string(&value).expect("JSON value encodes")
            );
            return ExitCode::from(2);
        }
    };
    match run(cli).await {
        Ok(success) => {
            if let Err(error) = emit_output(success.output) {
                let value = json!({
                    "backend": "direct",
                    "error": "output_write_failed",
                    "message": error.to_string(),
                    "status": "failure"
                });
                println!(
                    "{}",
                    serde_json::to_string(&value).expect("JSON value encodes")
                );
                return ExitCode::from(1);
            }
            ExitCode::from(success.exit_code)
        }
        Err(error) => {
            let value = json!({
                "backend": error.backend,
                "error": error.code,
                "message": error.message,
                "status": "failure"
            });
            println!(
                "{}",
                serde_json::to_string(&value).expect("JSON value encodes")
            );
            ExitCode::from(1)
        }
    }
}

async fn run(cli: Cli) -> Result<CommandSuccess, CommandError> {
    validate_platform_options(&cli)?;
    let backend = cli.backend;
    let device = cli.device;
    let port = cli.port;

    match cli.command {
        Command::Direct(DirectArgs {
            command: DirectCommand::Devices,
        }) => direct_devices().await.map(CommandSuccess::json),
        Command::Direct(DirectArgs {
            command: DirectCommand::Pair(options),
        }) => direct_pair(options, port).await.map(CommandSuccess::json),
        Command::Direct(DirectArgs {
            command: DirectCommand::Unpair { device_id },
        }) => direct_unpair(device_id).await.map(CommandSuccess::json),
        Command::Direct(DirectArgs {
            command: DirectCommand::ResetTrust { confirm },
        }) => direct_reset_trust(confirm).await.map(CommandSuccess::json),
        Command::Status(options) if backend == Backend::Direct => {
            direct_status(options, device, port)
                .await
                .map(CommandSuccess::json)
        }
        Command::Export(options) if backend == Backend::Direct => {
            direct_export(options, device, port).await
        }
        Command::Extract(options) if backend == Backend::Direct => {
            direct_extract(options, device, port).await
        }
        Command::Resume(options) if backend == Backend::Direct => {
            direct_resume(options, device, port).await
        }
        Command::Cancel(options) if backend == Backend::Direct => {
            direct_cancel(options, device, port)
                .await
                .map(CommandSuccess::json)
        }
        command => Err(CommandError {
            backend: backend.wire_name(),
            code: "not_implemented",
            message: format!(
                "{} with the {} backend is not implemented by this pre-release build",
                command_name(&command),
                backend.wire_name()
            ),
        }),
    }
}

fn validate_platform_options(cli: &Cli) -> Result<(), CommandError> {
    if cli.transport == Transport::Nearby {
        return Err(CommandError {
            backend: cli.backend.wire_name(),
            code: "transport_unsupported",
            message: "Nearby uses Apple MultipeerConnectivity; use --transport manual-ip on the portable CLI"
                .into(),
        });
    }

    if cli.backend != Backend::Direct
        && matches!(cli.command, Command::Resume(_) | Command::Cancel(_))
    {
        return Err(CommandError {
            backend: cli.backend.wire_name(),
            code: "invalid_request",
            message: "this command requires --backend direct".into(),
        });
    }
    Ok(())
}

async fn direct_devices() -> Result<Value, CommandError> {
    let client = DirectClient::open().map_err(client_error)?;
    let devices = client.paired_devices().await.map_err(client_error)?;
    Ok(json!({
        "schema": "healthmd.direct_devices",
        "schema_version": 1,
        "backend": "direct",
        "installation_id": client.identity.installation_id.0.to_string().to_lowercase(),
        "devices": devices.into_iter().map(|device| json!({
            "installation_id": device.installation_id.0.to_string().to_lowercase(),
            "name": device.display_name,
            "paired_at": device.paired_at.to_rfc3339_opts(SecondsFormat::Secs, true),
            "last_connected_at": device.last_connected_at.to_rfc3339_opts(SecondsFormat::Secs, true),
            "platform": device.platform.map(|platform| match platform {
                healthmd_protocol::wire::PeerPlatform::Ios => "ios",
                healthmd_protocol::wire::PeerPlatform::Android => "android",
                healthmd_protocol::wire::PeerPlatform::Cli => "cli"
            })
        })).collect::<Vec<_>>()
    }))
}

async fn direct_unpair(device_id: Uuid) -> Result<Value, CommandError> {
    let client = DirectClient::open().map_err(client_error)?;
    if !client.unpair(device_id).await.map_err(client_error)? {
        return Err(CommandError {
            backend: "direct",
            code: "direct_device_not_found",
            message: format!("No paired direct source has installation ID {device_id}"),
        });
    }
    Ok(json!({
        "status": "success",
        "backend": "direct",
        "device_id": device_id.to_string().to_lowercase(),
        "message": "Direct CLI source trust was removed from this computer. Forget it in the mobile app before pairing again."
    }))
}

async fn direct_reset_trust(confirm: bool) -> Result<Value, CommandError> {
    if !confirm {
        return Err(usage_error(
            "direct reset-trust requires --confirm because every local mobile pairing will be removed",
        ));
    }
    let client = DirectClient::open().map_err(client_error)?;
    client.reset_trust().await.map_err(client_error)?;
    Ok(json!({
        "status": "success",
        "backend": "direct",
        "message": "All local Direct CLI trust was removed. Forget the paired CLI in each mobile app before pairing again."
    }))
}

async fn direct_pair(options: PairArgs, port: u16) -> Result<Value, CommandError> {
    if !(10..=600).contains(&options.timeout) {
        return Err(usage_error(
            "pair timeout must be between 10 and 600 seconds",
        ));
    }
    let ios_code = match options.pairing_code {
        Some(code) => code,
        None => generate_pairing_code(6)?,
    };
    let android_code = match options.android_pairing_code {
        Some(code) => code,
        None => generate_pairing_code(20)?,
    };
    let ios_code = healthmd_client::handshake::normalize_pairing_code(&ios_code);
    let android_code = healthmd_client::handshake::normalize_pairing_code(&android_code);
    if ios_code.len() != 6 || android_code.len() != 20 {
        return Err(usage_error(
            "iOS pairing requires 6 ASCII digits and Android pairing requires 20 ASCII digits",
        ));
    }
    let addresses = local_ipv4_addresses();
    let address_text = if addresses.is_empty() {
        "<this computer's IP>".into()
    } else {
        addresses
            .iter()
            .map(|address| address.address.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    };
    let client = DirectClient::open().map_err(client_error)?;
    let result = client
        .pair(
            &ios_code,
            &android_code,
            port,
            Duration::from_secs(options.timeout),
            |bound_port| {
                eprintln!(
                    "Open Health.md → Direct CLI. Enter computer address {address_text} and port {bound_port}. Use iOS code {ios_code} or Android code {android_code}."
                );
            },
        )
        .await
        .map_err(|error| direct_error("direct_pairing_failed", error))?;
    Ok(json!({
        "schema": "healthmd.direct_pairing_result",
        "schema_version": 1,
        "status": "success",
        "backend": "direct",
        "device": {
            "installation_id": result.device.installation_id.0.to_string().to_lowercase(),
            "name": result.device.display_name,
            "platform": result.source.wire_name()
        },
        "listener": {
            "transport": "manual-ip",
            "port": result.port,
            "service_type": Value::Null,
            "addresses": addresses.into_iter().map(|address| json!({
                "address": address.address,
                "interface": address.interface,
                "tailscale": address.tailscale
            })).collect::<Vec<_>>()
        }
    }))
}

async fn direct_status(
    options: StatusArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<Value, CommandError> {
    let client = DirectClient::open().map_err(client_error)?;
    if let Some(job_id) = options.job {
        return match client.job_record(job_id) {
            Ok(record) => Ok(direct_job_payload(&record)),
            Err(ClientError::JobNotFound) => client
                .v2_job_record(job_id)
                .map(|record| direct_v2_job_payload(&record))
                .map_err(map_direct_client_error),
            Err(error) => Err(map_direct_client_error(error)),
        };
    }
    if client
        .paired_devices()
        .await
        .map_err(client_error)?
        .is_empty()
    {
        return Err(CommandError {
            backend: "direct",
            code: "direct_not_paired",
            message:
                "Run `healthmd direct pair`, then enable Direct CLI Access on the open iPhone app."
                    .into(),
        });
    }
    let result = client
        .status(device, port, Duration::from_secs(20))
        .await
        .map_err(map_direct_client_error)?;
    let (source, legacy_iphone) = match result.status {
        SourceStatus::Ios(iphone) => {
            let source = json!({
                "connected": true,
                "platform": "ios",
                "name": iphone.name,
                "app_active": iphone.app_active,
                "protected_data_available": iphone.protected_data_available,
                "can_trigger_exports": iphone.can_trigger_file_exports,
                "can_trigger_raw_exports": iphone.can_trigger_raw_exports,
                "active_job_id": iphone.active_job_id.map(|id| id.0.to_string().to_lowercase()),
                "message": iphone.message
            });
            (source.clone(), source)
        }
        SourceStatus::Android(android) => {
            let products = android
                .available_products
                .iter()
                .map(|product| serde_json::to_value(product).unwrap_or(Value::Null))
                .collect::<Vec<_>>();
            (
                json!({
                    "connected": true,
                    "platform": "android",
                    "name": android.source.display_name,
                    "app_version": android.source.app_version,
                    "app_active": android.app_active,
                    "protected_data_available": android.protected_data_available,
                    "export_in_progress": android.export_in_progress,
                    "available_products": products,
                    "active_job_id": android.active_job_id.map(|id| id.to_string().to_lowercase()),
                    "message": android.message
                }),
                Value::Null,
            )
        }
    };
    Ok(json!({
        "backend": "direct",
        "mac_app": "bypassed",
        "source": source,
        "iphone": legacy_iphone,
        "destination": {
            "selected": false,
            "writable": false,
            "path": Value::Null,
            "display_name": Value::Null
        },
        "active_export": Value::Null,
        "direct_cli": {
            "paired": true,
            "transport": "manual-ip",
            "installation_id": client.identity.installation_id.0.to_string().to_lowercase(),
            "port": result.port,
            "service_type": Value::Null,
            "protocol_version": result.application_protocol_version
        }
    }))
}

async fn direct_export(
    options: ExportArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<CommandSuccess, CommandError> {
    if !(5..=900).contains(&options.timeout) {
        return Err(usage_error(
            "export timeout must be between 5 and 900 seconds",
        ));
    }
    let source_client = DirectClient::open().map_err(client_error)?;
    let selected_source = source_client
        .selected_source(device)
        .await
        .map_err(client_error)?;
    if selected_source.platform == Some(healthmd_protocol::wire::PeerPlatform::Android) {
        return direct_android_export(
            options,
            selected_source.installation_id.0,
            port,
            source_client,
        )
        .await;
    }
    if !options.raw {
        return direct_file_export(options, device, port).await;
    }
    if options.destination.is_some() {
        return Err(usage_error("--destination cannot be used with --raw"));
    }
    if options.use_device_settings
        || options.selection.all_metrics
        || !options.selection.metrics.is_empty()
        || !options.selection.categories.is_empty()
        || !options.selection.objects.is_empty()
        || !options.selection.fields.is_empty()
        || !options.selection.sources.is_empty()
    {
        return Err(usage_error(
            "strict iOS --raw export cannot be combined with selectors or --use-device-settings",
        ));
    }
    let request = ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(Uuid::new_v4()),
        created_at: whole_second_now(),
        date_selection: resolve_date_selection(&options.dates)?,
        settings_policy: SettingsPolicy::RequestedDatesOnly,
        response_mode: ResponseMode::RawJson,
        raw_profile: Some(RawProfile::CanonicalSourceRecordsV1),
        canonical_selection: None,
        destination: None,
    };
    let client = DirectClient::open().map_err(client_error)?;
    let result = client
        .export_raw(request, device, port, Duration::from_secs(options.timeout))
        .await
        .map_err(map_direct_client_error)?;
    let exit_code = u8::from(result.artifact.status == "partial_success" && !options.allow_partial);
    Ok(CommandSuccess {
        output: CommandOutput::Artifact {
            source: result.artifact.path,
            output: options.output,
        },
        exit_code,
    })
}

#[allow(clippy::too_many_lines)]
async fn direct_android_export(
    options: ExportArgs,
    source_id: Uuid,
    port: u16,
    client: DirectClient,
) -> Result<CommandSuccess, CommandError> {
    let date_selection = resolve_v2_date_selection(&options.dates)?;
    let created_at = whole_second_now();
    let expires_at = created_at + ChronoDuration::seconds(healthmd_protocol::JOB_LIFETIME_SECONDS);
    let timeout = Duration::from_secs(options.timeout);

    if options.raw {
        if options.destination.is_some() {
            return Err(usage_error("--destination cannot be used with --raw"));
        }
        if options.use_device_settings
            || !options.selection.categories.is_empty()
            || !options.selection.objects.is_empty()
            || !options.selection.fields.is_empty()
            || !options.selection.sources.is_empty()
        {
            return Err(usage_error(
                "Android --raw supports --metric/--all-metrics and --provider, but not generated-file settings or canonical selectors",
            ));
        }
        if options.selection.all_metrics && !options.selection.metrics.is_empty() {
            return Err(usage_error(
                "--all-metrics cannot be combined with --metric",
            ));
        }
        let provider = options.provider.trim().to_lowercase();
        if provider.is_empty() || provider == "all_connected" {
            return Err(usage_error(
                "Android direct raw export requires one explicit provider such as health_connect",
            ));
        }
        let mut metrics = options.selection.metrics;
        metrics.sort();
        metrics.dedup();
        let scope = if options.selection.all_metrics || metrics.is_empty() {
            v2::RawSnapshotScope::AllAuthorizedSupportedData
        } else {
            v2::RawSnapshotScope::SelectedRecordTypes {
                selected_metric_ids: metrics,
            }
        };
        let request = v2::ExportRequest {
            job_id: Uuid::new_v4(),
            created_at,
            expires_at,
            source_installation_id: source_id,
            date_selection,
            product: v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
                provider_id: provider,
                format: match options.raw_format {
                    RawArtifactFormat::Json => v2::RawSnapshotFormat::Json,
                    RawArtifactFormat::Ndjson => v2::RawSnapshotFormat::Ndjson,
                },
                scope,
                include_exercise_routes: false,
            },
            destination: None,
        };
        let result = client
            .export_android(request, None, Some(source_id), port, timeout)
            .await
            .map_err(map_direct_client_error)?;
        let exit_code =
            u8::from(result.receipt.status == "partial_success" && !options.allow_partial);
        return Ok(CommandSuccess {
            output: CommandOutput::Artifact {
                source: result.receipt.path,
                output: options.output,
            },
            exit_code,
        });
    }

    if options.output.is_some() {
        return Err(usage_error("--output requires --raw"));
    }
    if options.selection.all_metrics
        || !options.selection.metrics.is_empty()
        || !options.selection.categories.is_empty()
        || !options.selection.objects.is_empty()
        || !options.selection.fields.is_empty()
        || !options.selection.sources.is_empty()
    {
        return Err(usage_error(
            "Android generated-file direct export currently uses saved device selections; remove CLI selectors",
        ));
    }
    let destination_path = options
        .destination
        .ok_or_else(|| usage_error("direct generated-file export requires --destination"))?;
    let destination =
        GeneratedDestination::open(&destination_path).map_err(map_direct_file_error)?;
    let display_name = destination
        .root()
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("Health Exports")
        .to_owned();
    let request = v2::ExportRequest {
        job_id: Uuid::new_v4(),
        created_at,
        expires_at,
        source_installation_id: source_id,
        date_selection,
        product: v2::ExportProduct::GeneratedFilesV1 {
            settings_policy: v2::SettingsPolicy::SavedDeviceSettings,
        },
        destination: Some(v2::DestinationBinding {
            binding_sha256: destination
                .binding_sha256()
                .map_err(map_direct_file_error)?,
            display_name,
        }),
    };
    let result = client
        .export_android(
            request,
            Some(destination.root().to_path_buf()),
            Some(source_id),
            port,
            timeout,
        )
        .await
        .map_err(map_direct_file_error)?;
    Ok(CommandSuccess {
        output: CommandOutput::Artifact {
            source: result.receipt.path,
            output: None,
        },
        exit_code: 0,
    })
}

#[allow(clippy::too_many_lines)]
#[cfg_attr(windows, allow(unused_variables))]
async fn direct_file_export(
    options: ExportArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<CommandSuccess, CommandError> {
    #[cfg(windows)]
    return Err(CommandError {
        backend: "direct",
        code: "backend_unsupported",
        message: "generated-file export requires the v2 logical destination contract on Windows; use --raw or extract"
            .into(),
    });
    #[cfg(not(windows))]
    {
        if options.output.is_some() {
            return Err(usage_error("--output requires --raw"));
        }
        if !options.selection.objects.is_empty() || !options.selection.fields.is_empty() {
            return Err(usage_error(
                "--object and --field are available only with extract",
            ));
        }
        let destination = options
            .destination
            .ok_or_else(|| usage_error("direct generated-file export requires --destination"))?;
        let metadata = fs::symlink_metadata(&destination)
            .map_err(|_| usage_error("--destination must be an existing directory"))?;
        if !destination.is_absolute() || metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(usage_error(
                "--destination must be an existing absolute non-symlink directory",
            ));
        }
        let destination = fs::canonicalize(destination)
            .map_err(|_| usage_error("--destination could not be resolved"))?;
        let mut metrics = options.selection.metrics;
        let mut categories = options.selection.categories;
        metrics.sort();
        metrics.dedup();
        categories.sort();
        categories.dedup();
        if options.selection.all_metrics && (!metrics.is_empty() || !categories.is_empty()) {
            return Err(usage_error(
                "--all-metrics cannot be combined with --metric or --category",
            ));
        }
        let selection_requested = options.selection.all_metrics
            || !metrics.is_empty()
            || !categories.is_empty()
            || !options.selection.sources.is_empty();
        if options.use_device_settings && selection_requested {
            return Err(usage_error(
                "request-scoped selection cannot use --use-device-settings",
            ));
        }
        let sources = if options.selection.sources.is_empty() {
            vec!["apple_health".into()]
        } else {
            let mut sources = options.selection.sources;
            sources.sort();
            sources.dedup();
            if sources.len() != 1 || sources[0] != "apple_health" {
                return Err(usage_error(
                    "generated-file selection currently supports only --source apple_health",
                ));
            }
            sources
        };
        let canonical_selection = selection_requested.then_some(CanonicalSelection {
            metric_ids: metrics,
            categories,
            source_ids: sources,
            object_paths: Vec::new(),
            field_pointers: Vec::new(),
            all_metrics: options.selection.all_metrics,
            detail_level: match options.selection.detail {
                Detail::Summary => DetailLevel::Summary,
                Detail::Lossless => DetailLevel::Lossless,
            },
        });
        let request = ExportRequest {
            protocol_version: 1,
            job_id: SwiftUuid(Uuid::new_v4()),
            created_at: whole_second_now(),
            date_selection: resolve_date_selection(&options.dates)?,
            settings_policy: if options.use_device_settings {
                SettingsPolicy::CurrentIphoneSettings
            } else {
                SettingsPolicy::RequestedDatesOnly
            },
            response_mode: ResponseMode::WriteFiles,
            raw_profile: None,
            canonical_selection,
            destination: Some(ExportDestination {
                root_path: destination
                    .to_str()
                    .ok_or_else(|| usage_error("--destination must be valid UTF-8"))?
                    .into(),
            }),
        };
        let client = DirectClient::open().map_err(client_error)?;
        let result = client
            .export_files(request, device, port, Duration::from_secs(options.timeout))
            .await
            .map_err(map_direct_file_error)?;
        Ok(CommandSuccess {
            output: CommandOutput::Artifact {
                source: result.receipt.response_path,
                output: None,
            },
            exit_code: 0,
        })
    }
}

#[allow(clippy::too_many_lines)]
async fn direct_extract(
    options: ExtractArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<CommandSuccess, CommandError> {
    if !(5..=900).contains(&options.timeout) {
        return Err(usage_error(
            "extract timeout must be between 5 and 900 seconds",
        ));
    }
    let mut categories = options.selection.categories;
    let mut object_paths = Vec::new();
    let mut requires_lossless = options.selection.detail == Detail::Lossless;
    for object in &options.selection.objects {
        let resolved = canonical_object_path(object)?;
        object_paths.push(resolved.0);
        if let Some(category) = resolved.1 {
            categories.push(category);
        }
        requires_lossless |= resolved.2;
    }
    for pointer in &options.selection.fields {
        validate_canonical_pointer(pointer)?;
        requires_lossless |= pointer.starts_with("/healthkit_record_archive");
    }
    let mut metrics = options.selection.metrics;
    metrics.sort();
    metrics.dedup();
    categories.sort();
    categories.dedup();
    object_paths.sort();
    object_paths.dedup();
    let mut fields = options.selection.fields;
    fields.sort();
    fields.dedup();
    if options.selection.all_metrics && (!metrics.is_empty() || !categories.is_empty()) {
        return Err(usage_error(
            "--all-metrics cannot be combined with --metric or --category",
        ));
    }
    if !options.selection.all_metrics && metrics.is_empty() && categories.is_empty() {
        return Err(usage_error(
            "extract requires --metric, --category, a category object, or --all-metrics",
        ));
    }
    let sources = if options.selection.sources.is_empty() {
        vec!["apple_health".into()]
    } else {
        let mut sources = options.selection.sources;
        sources.sort();
        sources.dedup();
        if sources.len() != 1 || sources[0] != "apple_health" {
            return Err(usage_error(
                "canonical extraction currently supports only --source apple_health",
            ));
        }
        sources
    };
    let client = DirectClient::open().map_err(client_error)?;
    if client
        .selected_source_kind(device)
        .await
        .map_err(map_direct_client_error)?
        == healthmd_client::direct::SourceKind::Android
    {
        return Err(usage_error(
            "canonical extraction is currently available for iOS sources only",
        ));
    }
    let selection = CanonicalSelection {
        metric_ids: metrics,
        categories,
        source_ids: sources,
        object_paths: object_paths.clone(),
        field_pointers: fields.clone(),
        all_metrics: options.selection.all_metrics,
        detail_level: if requires_lossless {
            DetailLevel::Lossless
        } else {
            DetailLevel::Summary
        },
    };
    let job_id = Uuid::new_v4();
    let request = ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(job_id),
        created_at: whole_second_now(),
        date_selection: resolve_date_selection(&options.dates)?,
        settings_policy: SettingsPolicy::RequestedDatesOnly,
        response_mode: ResponseMode::RawJson,
        raw_profile: Some(RawProfile::HealthDataProjection),
        canonical_selection: Some(selection),
        destination: None,
    };
    let mut pointers = object_paths;
    pointers.extend(fields);
    pointers.sort();
    pointers.dedup();
    let transfer = client
        .export_raw(request, device, port, Duration::from_secs(options.timeout))
        .await
        .map_err(map_direct_client_error)?;
    if transfer.artifact.status == "partial_success" && !options.allow_partial {
        return Err(CommandError {
            backend: "direct",
            code: "partial_canonical_extraction",
            message:
                "Canonical extraction was incomplete; pass --allow-partial to emit retained data."
                    .into(),
        });
    }
    if options.format == ExtractionFormat::Jsonl {
        let artifact = client
            .extraction_jsonl(job_id, &pointers)
            .map_err(map_direct_client_error)?;
        return Ok(CommandSuccess {
            output: CommandOutput::JsonlArtifact {
                source: artifact.path,
                receipt: artifact.receipt_path,
                output: options.output,
            },
            exit_code: 0,
        });
    }
    let artifact = client
        .extraction(job_id, &pointers)
        .map_err(map_direct_client_error)?;
    let exit_code = 0;
    Ok(CommandSuccess {
        output: CommandOutput::Artifact {
            source: artifact.path,
            output: options.output,
        },
        exit_code,
    })
}

#[allow(clippy::too_many_lines)]
async fn direct_resume(
    options: ResumeArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<CommandSuccess, CommandError> {
    if !(5..=900).contains(&options.timeout) {
        return Err(usage_error(
            "resume timeout must be between 5 and 900 seconds",
        ));
    }
    let client = DirectClient::open().map_err(client_error)?;
    match client.v2_job_record(options.job_id) {
        Ok(record) => {
            match &record.request.product {
                v2::ExportProduct::AndroidProviderNativeSnapshotV1 { format, .. } => {
                    let matches_saved = options.format.is_none_or(|requested| {
                        matches!(
                            (requested, format),
                            (ExtractionFormat::Json, v2::RawSnapshotFormat::Json)
                                | (ExtractionFormat::Jsonl, v2::RawSnapshotFormat::Ndjson)
                        )
                    });
                    if !matches_saved {
                        return Err(usage_error(
                            "--format must match the immutable Android raw job format",
                        ));
                    }
                }
                _ if options.format == Some(ExtractionFormat::Jsonl) => {
                    return Err(usage_error(
                        "--format jsonl is available for Android raw snapshot jobs only",
                    ));
                }
                _ => {}
            }
            let result = client
                .resume_android(
                    options.job_id,
                    device,
                    port,
                    Duration::from_secs(options.timeout),
                )
                .await
                .map_err(map_direct_client_error)?;
            let exit_code =
                u8::from(result.receipt.status == "partial_success" && !options.allow_partial);
            return Ok(CommandSuccess {
                output: CommandOutput::Artifact {
                    source: result.receipt.path,
                    output: options.output,
                },
                exit_code,
            });
        }
        Err(ClientError::JobNotFound) => {}
        Err(error) => return Err(map_direct_client_error(error)),
    }
    let record = client
        .job_record(options.job_id)
        .map_err(map_direct_client_error)?;
    if record.request.response_mode == ResponseMode::WriteFiles {
        if options.format == Some(ExtractionFormat::Jsonl) {
            return Err(usage_error(
                "--format jsonl is available only when resuming canonical extract jobs",
            ));
        }
        let result = client
            .resume_files(
                options.job_id,
                device,
                port,
                Duration::from_secs(options.timeout),
            )
            .await
            .map_err(map_direct_file_error)?;
        return Ok(CommandSuccess {
            output: CommandOutput::Artifact {
                source: result.receipt.response_path,
                output: options.output,
            },
            exit_code: 0,
        });
    }
    let projection_pointers =
        (record.request.raw_profile == Some(RawProfile::HealthDataProjection)).then(|| {
            let selection = record.request.canonical_selection.as_ref();
            let mut pointers = selection
                .map(|value| value.object_paths.clone())
                .unwrap_or_default();
            if let Some(selection) = selection {
                pointers.extend(selection.field_pointers.clone());
            }
            pointers.sort();
            pointers.dedup();
            pointers
        });
    let result = client
        .resume_raw(
            options.job_id,
            device,
            port,
            Duration::from_secs(options.timeout),
        )
        .await
        .map_err(map_direct_client_error)?;
    if let Some(pointers) = projection_pointers {
        if result.artifact.status == "partial_success" && !options.allow_partial {
            return Err(CommandError {
                backend: "direct",
                code: "partial_canonical_extraction",
                message: "Canonical extraction was incomplete; rerun resume with --allow-partial to emit retained data."
                    .into(),
            });
        }
        if options.format == Some(ExtractionFormat::Jsonl) {
            let artifact = client
                .extraction_jsonl(options.job_id, &pointers)
                .map_err(map_direct_client_error)?;
            return Ok(CommandSuccess {
                output: CommandOutput::JsonlArtifact {
                    source: artifact.path,
                    receipt: artifact.receipt_path,
                    output: options.output,
                },
                exit_code: 0,
            });
        }
        let artifact = client
            .extraction(options.job_id, &pointers)
            .map_err(map_direct_client_error)?;
        return Ok(CommandSuccess {
            output: CommandOutput::Artifact {
                source: artifact.path,
                output: options.output,
            },
            exit_code: 0,
        });
    }
    if options.format == Some(ExtractionFormat::Jsonl) {
        return Err(usage_error(
            "--format jsonl is available only when resuming canonical extract jobs",
        ));
    }
    let exit_code = u8::from(result.artifact.status == "partial_success" && !options.allow_partial);
    Ok(CommandSuccess {
        output: CommandOutput::Artifact {
            source: result.artifact.path,
            output: options.output,
        },
        exit_code,
    })
}

async fn direct_cancel(
    options: JobArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<Value, CommandError> {
    let client = DirectClient::open().map_err(client_error)?;
    match client.v2_job_record(options.job_id) {
        Ok(record) => {
            let already_terminal = record.state.is_terminal();
            client
                .cancel_android_job(options.job_id, device, port, Duration::from_secs(20))
                .await
                .map_err(map_direct_client_error)?;
            let current = client
                .v2_job_record(options.job_id)
                .map_err(map_direct_client_error)?;
            let status = serde_json::to_value(current.state).unwrap_or_else(|_| json!("unknown"));
            Ok(json!({
                "backend": "direct",
                "job_id": options.job_id.to_string().to_lowercase(),
                "status": status,
                "cancellation_applied": !already_terminal
            }))
        }
        Err(ClientError::JobNotFound) => {
            client
                .cancel_job(options.job_id, device, port, Duration::from_secs(20))
                .await
                .map_err(map_direct_client_error)?;
            Ok(json!({
                "backend": "direct",
                "job_id": options.job_id.to_string().to_lowercase(),
                "status": "cancelled"
            }))
        }
        Err(error) => Err(map_direct_client_error(error)),
    }
}

fn canonical_object_path(value: &str) -> Result<(String, Option<String>, bool), CommandError> {
    if value.starts_with('/') {
        validate_canonical_pointer(value)?;
        return Ok((
            value.into(),
            None,
            value.starts_with("/healthkit_record_archive"),
        ));
    }
    let normalized = value.to_lowercase().replace('_', "-");
    let top_level = match normalized.as_str() {
        "sleep" => Some(("/sleep", "Sleep")),
        "activity" => Some(("/activity", "Activity")),
        "heart" => Some(("/heart", "Heart")),
        "vitals" => Some(("/vitals", "Vitals")),
        "body" => Some(("/body", "Body Measurements")),
        "nutrition" => Some(("/nutrition", "Nutrition")),
        "mindfulness" => Some(("/mindfulness", "Mindfulness")),
        "mobility" => Some(("/mobility", "Mobility")),
        "hearing" => Some(("/hearing", "Hearing")),
        "reproductive-health" => Some(("/reproductiveHealth", "Reproductive Health")),
        "cycling" => Some(("/cyclingPerformance", "Cycling")),
        "vitamins" => Some(("/vitamins", "Vitamins")),
        "minerals" => Some(("/minerals", "Minerals")),
        "symptoms" => Some(("/symptoms", "Symptoms")),
        "medications" => Some(("/medications", "Medications")),
        "other" => Some(("/other", "Other")),
        "workouts" => Some(("/workouts", "Workouts")),
        _ => None,
    };
    if let Some((path, category)) = top_level {
        return Ok((path.into(), Some(category.into()), false));
    }
    let archive = match normalized.as_str() {
        "archive" => Some("/healthkit_record_archive"),
        "records" => Some("/healthkit_record_archive/records"),
        "external-records" => Some("/healthkit_record_archive/external_records"),
        "query-results" => Some("/healthkit_record_archive/query_manifest/results"),
        "warnings" => Some("/healthkit_record_archive/integrity_warnings"),
        _ => None,
    };
    archive.map_or_else(
        || Err(usage_error("unknown canonical object or JSON Pointer")),
        |path| Ok((path.into(), None, true)),
    )
}

fn validate_canonical_pointer(pointer: &str) -> Result<(), CommandError> {
    if pointer.is_empty()
        || !pointer.starts_with('/')
        || pointer.len() > 1_024
        || pointer.bytes().any(|byte| byte.is_ascii_control())
    {
        return Err(usage_error(
            "canonical JSON Pointer must begin with / and contain no control characters",
        ));
    }
    let mut bytes = pointer.bytes();
    while let Some(byte) = bytes.next() {
        if byte == b'~' && !matches!(bytes.next(), Some(b'0' | b'1')) {
            return Err(usage_error(
                "canonical JSON Pointer contains an invalid ~ escape",
            ));
        }
    }
    Ok(())
}

fn resolve_date_selection(options: &DateArgs) -> Result<DateSelection, CommandError> {
    if options.from.is_some() != options.to.is_some() {
        return Err(usage_error("--from and --to must be provided together"));
    }
    let selected_ranges = usize::from(options.all)
        + usize::from(options.yesterday)
        + usize::from(options.last.is_some())
        + usize::from(options.from.is_some());
    if selected_ranges != 1 {
        return Err(usage_error(
            "choose exactly one date range: --yesterday, --last, --from/--to, or --all",
        ));
    }
    if options.all {
        return Ok(DateSelection::AllAvailable(
            healthmd_protocol::wire::Empty {},
        ));
    }
    let today = Local::now().date_naive();
    let (start, end) = if options.yesterday {
        let yesterday = today
            .checked_sub_signed(ChronoDuration::days(1))
            .ok_or_else(|| usage_error("date range is outside the supported calendar"))?;
        (yesterday, yesterday)
    } else if let Some(days) = options.last {
        if days == 0 {
            return Err(usage_error("--last must be greater than zero"));
        }
        let start = today
            .checked_sub_signed(ChronoDuration::days(i64::from(days)))
            .ok_or_else(|| usage_error("--last is outside the supported calendar"))?;
        let end = today
            .checked_sub_signed(ChronoDuration::days(1))
            .ok_or_else(|| usage_error("date range is outside the supported calendar"))?;
        (start, end)
    } else if let (Some(start), Some(end)) = (&options.from, &options.to) {
        let start = chrono::NaiveDate::parse_from_str(start, "%Y-%m-%d")
            .map_err(|_| usage_error("--from must be YYYY-MM-DD"))?;
        let end = chrono::NaiveDate::parse_from_str(end, "%Y-%m-%d")
            .map_err(|_| usage_error("--to must be YYYY-MM-DD"))?;
        if start > end {
            return Err(usage_error("--from must not be after --to"));
        }
        (start, end)
    } else {
        return Err(usage_error(
            "choose one date range: --yesterday, --last, --from/--to, or --all",
        ));
    };
    Ok(DateSelection::Exact(ExactDateSelection {
        start: start.format("%Y-%m-%d").to_string(),
        end: end.format("%Y-%m-%d").to_string(),
    }))
}

fn resolve_v2_date_selection(options: &DateArgs) -> Result<v2::DateSelection, CommandError> {
    match resolve_date_selection(options)? {
        DateSelection::Exact(exact) => Ok(v2::DateSelection::Exact {
            start_date: exact.start,
            end_date: exact.end,
        }),
        DateSelection::AllAvailable(_) => Ok(v2::DateSelection::AllAvailable),
    }
}

fn whole_second_now() -> chrono::DateTime<Utc> {
    Utc::now().with_nanosecond(0).unwrap_or_else(Utc::now)
}

fn direct_job_payload(record: &JobRecord) -> Value {
    let status = serde_json::to_value(record.state)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| "unknown".into());
    let mut payload = json!({
        "backend": "direct",
        "job_id": record.request.job_id.0.to_string().to_lowercase(),
        "status": status,
        "created_at": record.created_at.to_rfc3339_opts(SecondsFormat::Millis, true),
        "updated_at": record.updated_at.to_rfc3339_opts(SecondsFormat::Millis, true),
        "expires_at": record.expires_at.to_rfc3339_opts(SecondsFormat::Millis, true),
        "processed_days": record.processed_days,
        "committed_partitions": record.committed_partitions,
        "committed_bytes": record.committed_bytes,
        "message": record.message.clone().unwrap_or_default(),
        "resumable": !record.state.is_terminal() && record.state != JobState::CancellationPending
    });
    let object = payload.as_object_mut().expect("job payload is an object");
    if let Some(total) = record.total_days {
        object.insert("total_days".into(), json!(total));
    }
    if let Some(session) = record.session_id {
        object.insert(
            "session_id".into(),
            json!(session.0.to_string().to_lowercase()),
        );
    }
    if let Some(destination) = &record.request.destination {
        object.insert("destination_path".into(), json!(destination.root_path));
    }
    if let Some(failure) = &record.failure {
        object.insert(
            "failure".into(),
            json!({
                "reason": serde_json::to_value(failure.reason).unwrap_or(Value::Null),
                "message": failure.message
            }),
        );
    }
    payload
}

fn direct_v2_job_payload(record: &healthmd_client::v2_job::V2JobRecord) -> Value {
    let status = serde_json::to_value(record.state)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| "unknown".into());
    json!({
        "backend": "direct",
        "application_protocol_version": 2,
        "platform": "android",
        "job_id": record.request.job_id.to_string().to_lowercase(),
        "product_id": record.request.product.product_id(),
        "status": status,
        "created_at": record.request.created_at.to_rfc3339_opts(SecondsFormat::Secs, true),
        "updated_at": record.updated_at.to_rfc3339_opts(SecondsFormat::Secs, true),
        "expires_at": record.request.expires_at.to_rfc3339_opts(SecondsFormat::Secs, true),
        "committed_partitions": record.committed_partitions,
        "committed_bytes": record.committed_bytes,
        "message": record.message,
        "destination_path": record.destination_root,
        "failure": record.failure,
        "resumable": !record.state.is_terminal() && record.state != JobState::CancellationPending
    })
}

fn emit_output(output: CommandOutput) -> io::Result<()> {
    match output {
        CommandOutput::Json(value) => {
            println!("{}", serde_json::to_string_pretty(&value)?);
            Ok(())
        }
        CommandOutput::JsonlArtifact {
            source,
            receipt,
            output: Some(destination),
        } => {
            atomic_private_copy(&source, &destination)?;
            atomic_private_copy(&receipt, &receipt_output_path(&destination))
        }
        CommandOutput::JsonlArtifact {
            source,
            receipt,
            output: None,
        } => {
            let mut data = fs::File::open(source)?;
            let mut stdout = io::stdout().lock();
            io::copy(&mut data, &mut stdout)?;
            stdout.flush()?;
            let mut receipt = fs::File::open(receipt)?;
            let mut stderr = io::stderr().lock();
            io::copy(&mut receipt, &mut stderr)?;
            stderr.flush()
        }
        CommandOutput::Artifact {
            source,
            output: Some(destination),
        } => atomic_private_copy(&source, &destination),
        CommandOutput::Artifact {
            source,
            output: None,
        } => {
            let mut input = fs::File::open(source)?;
            let mut stdout = io::stdout().lock();
            io::copy(&mut input, &mut stdout)?;
            stdout.flush()
        }
    }
}

fn receipt_output_path(destination: &Path) -> PathBuf {
    let mut value = destination.as_os_str().to_owned();
    value.push(".receipt.json");
    PathBuf::from(value)
}

fn atomic_private_copy(source: &Path, destination: &Path) -> io::Result<()> {
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    let mut input = fs::File::open(source)?;
    io::copy(&mut input, &mut temporary)?;
    temporary.as_file().sync_all()?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        temporary
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o600))?;
    }
    temporary
        .persist(destination)
        .map_err(|error| error.error)?;
    Ok(())
}

fn generate_pairing_code(digit_count: usize) -> Result<String, CommandError> {
    let mut code = String::with_capacity(digit_count);
    while code.len() < digit_count {
        let bytes = healthmd_protocol::crypto::random_bytes::<32>().map_err(|_| CommandError {
            backend: "direct",
            code: "secure_random_unavailable",
            message: "the operating system could not generate a secure pairing code".into(),
        })?;
        for byte in bytes.into_iter().filter(|byte| *byte < 250) {
            code.push(char::from(b'0' + (byte % 10)));
            if code.len() == digit_count {
                break;
            }
        }
    }
    Ok(code)
}

struct LocalAddress {
    address: String,
    interface: String,
    tailscale: bool,
}

fn local_ipv4_addresses() -> Vec<LocalAddress> {
    let mut addresses: Vec<_> = if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|interface| {
            let std::net::IpAddr::V4(address) = interface.ip() else {
                return None;
            };
            if address.is_loopback()
                || address.is_unspecified()
                || address.is_multicast()
                || address.is_link_local()
            {
                return None;
            }
            let octets = address.octets();
            Some(LocalAddress {
                address: address.to_string(),
                interface: interface.name,
                tailscale: is_tailscale_ipv4(octets),
            })
        })
        .collect();
    addresses.sort_by(|left, right| {
        right
            .tailscale
            .cmp(&left.tailscale)
            .then_with(|| left.interface.cmp(&right.interface))
            .then_with(|| left.address.cmp(&right.address))
    });
    addresses.dedup_by(|left, right| left.address == right.address);
    addresses
}

const fn is_tailscale_ipv4(octets: [u8; 4]) -> bool {
    octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127
}

fn usage_error(message: &str) -> CommandError {
    CommandError {
        backend: "direct",
        code: "invalid_request",
        message: message.into(),
    }
}

#[allow(clippy::needless_pass_by_value)]
fn client_error(error: ClientError) -> CommandError {
    let code = if matches!(error, ClientError::InvalidTrustState) {
        "direct_trust_invalid"
    } else {
        "direct_storage_unavailable"
    };
    direct_error(code, error)
}

#[allow(clippy::needless_pass_by_value)]
fn map_direct_file_error(error: ClientError) -> CommandError {
    if matches!(error, ClientError::InvalidTransfer(_)) {
        return direct_error("invalid_direct_file_receipt", error);
    }
    map_direct_client_error(error)
}

#[allow(clippy::needless_pass_by_value)]
fn map_direct_client_error(error: ClientError) -> CommandError {
    let code = match error {
        ClientError::JobNotFound => "job_not_found",
        ClientError::JobExpired => "job_expired",
        ClientError::JobBusy(_) => "direct_job_busy",
        ClientError::InvalidTrustState => "direct_trust_invalid",
        ClientError::CredentialStore(_) => "direct_storage_unavailable",
        ClientError::DeviceSelectionRequired(_) => "direct_device_selection_required",
        ClientError::DeviceNotPaired(_) => "direct_device_not_paired",
        ClientError::ExportPaused(_) => "direct_export_paused",
        ClientError::CancellationPending(_) => "direct_cancellation_pending",
        ClientError::JobNotResumable(_, _) => "direct_job_not_resumable",
        ClientError::InvalidTransfer(_) => "invalid_direct_response",
        ClientError::Cancelled => "cancelled",
        _ => "direct_source_unavailable",
    };
    direct_error(code, error)
}

fn direct_error(code: &'static str, error: impl std::fmt::Display) -> CommandError {
    CommandError {
        backend: "direct",
        code,
        message: error.to_string(),
    }
}

const fn command_name(command: &Command) -> &'static str {
    match command {
        Command::Status(_) => "status",
        Command::Export(_) => "export",
        Command::Extract(_) => "extract",
        Command::Resume(_) => "resume",
        Command::Cancel(_) => "cancel",
        Command::Direct(DirectArgs {
            command: DirectCommand::Pair(_),
        }) => "direct pair",
        Command::Direct(DirectArgs {
            command: DirectCommand::Devices,
        }) => "direct devices",
        Command::Direct(DirectArgs {
            command: DirectCommand::Unpair { .. },
        }) => "direct unpair",
        Command::Direct(DirectArgs {
            command: DirectCommand::ResetTrust { .. },
        }) => "direct reset-trust",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_dates() -> DateArgs {
        DateArgs {
            yesterday: false,
            last: None,
            from: None,
            to: None,
            all: false,
        }
    }

    #[test]
    fn date_ranges_are_exclusive_and_bounded() {
        assert!(resolve_date_selection(&empty_dates()).is_err());
        let mut conflicting = empty_dates();
        conflicting.all = true;
        conflicting.yesterday = true;
        assert!(resolve_date_selection(&conflicting).is_err());
        let mut incomplete = empty_dates();
        incomplete.from = Some("2026-07-01".into());
        assert!(resolve_date_selection(&incomplete).is_err());
        let mut zero = empty_dates();
        zero.last = Some(0);
        assert!(resolve_date_selection(&zero).is_err());
        let exact = DateArgs {
            from: Some("2026-07-01".into()),
            to: Some("2026-07-24".into()),
            ..empty_dates()
        };
        assert_eq!(
            resolve_date_selection(&exact).unwrap(),
            DateSelection::Exact(ExactDateSelection {
                start: "2026-07-01".into(),
                end: "2026-07-24".into(),
            })
        );
    }

    #[test]
    fn canonical_pointer_validation_rejects_ambiguous_escapes() {
        assert!(validate_canonical_pointer("/sleep/samples/0").is_ok());
        assert!(validate_canonical_pointer("/a~1b/~0key").is_ok());
        assert!(validate_canonical_pointer("sleep").is_err());
        assert!(validate_canonical_pointer("/bad~2escape").is_err());
        assert!(validate_canonical_pointer("/bad~").is_err());
    }

    #[test]
    fn jsonl_receipt_path_is_appended_without_replacing_extension() {
        assert_eq!(
            receipt_output_path(Path::new("health.jsonl")),
            PathBuf::from("health.jsonl.receipt.json")
        );
    }

    #[test]
    fn tailscale_carrier_grade_nat_range_is_detected() {
        assert!(is_tailscale_ipv4([100, 64, 0, 1]));
        assert!(is_tailscale_ipv4([100, 127, 255, 254]));
        assert!(!is_tailscale_ipv4([100, 128, 0, 1]));
        assert!(!is_tailscale_ipv4([192, 168, 1, 2]));
    }

    #[test]
    fn android_raw_options_and_generic_settings_alias_parse() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "export",
            "--raw",
            "--yesterday",
            "--provider",
            "health_connect",
            "--raw-format",
            "ndjson",
        ])
        .unwrap();
        let Command::Export(options) = parsed.command else {
            panic!("expected export command");
        };
        assert!(options.raw);
        assert_eq!(options.provider, "health_connect");
        assert_eq!(options.raw_format, RawArtifactFormat::Ndjson);

        let alias = Cli::try_parse_from([
            "healthmd",
            "export",
            "--yesterday",
            "--destination",
            "/tmp",
            "--use-iphone-settings",
        ])
        .unwrap();
        let Command::Export(options) = alias.command else {
            panic!("expected export command");
        };
        assert!(options.use_device_settings);
    }

    #[test]
    fn platform_specific_pairing_code_overrides_parse() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "direct",
            "pair",
            "--pairing-code",
            "123456",
            "--android-pairing-code",
            "12345678901234567890",
        ])
        .unwrap();
        let Command::Direct(DirectArgs {
            command: DirectCommand::Pair(options),
        }) = parsed.command
        else {
            panic!("expected direct pair command");
        };
        assert_eq!(options.pairing_code.as_deref(), Some("123456"));
        assert_eq!(
            options.android_pairing_code.as_deref(),
            Some("12345678901234567890")
        );
    }

    #[test]
    fn v2_dates_use_explicit_platform_neutral_shape() {
        let exact = DateArgs {
            from: Some("2026-07-01".into()),
            to: Some("2026-07-24".into()),
            ..empty_dates()
        };
        assert_eq!(
            resolve_v2_date_selection(&exact).unwrap(),
            v2::DateSelection::Exact {
                start_date: "2026-07-01".into(),
                end_date: "2026-07-24".into(),
            }
        );
    }

    #[test]
    fn archive_alias_requests_lossless_detail() {
        let (pointer, category, lossless) = canonical_object_path("archive").unwrap();
        assert_eq!(pointer, "/healthkit_record_archive");
        assert_eq!(category, None);
        assert!(lossless);
    }
}
