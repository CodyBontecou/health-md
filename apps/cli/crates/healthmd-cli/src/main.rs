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
use healthmd_cli::{
    mcp, onboarding,
    pairing::{LocalAddress, ios_pairing_link, local_ipv4_addresses, preferred_pairing_address},
};
use healthmd_client::{
    ClientError,
    direct::{DirectClient, SourceStatus},
    file_receiver::GeneratedDestination,
    job::{JobRecord, JobState},
};
use healthmd_operations::{
    DateOptions as OperationDateOptions, GeneratedFileExportInput, OperationInputError,
    SelectionDetail, SelectionOptions,
};
use healthmd_protocol::{
    encoding::SwiftUuid,
    models::{DateSelection, ExportRequest, ProfileReference, ResponseMode, SettingsPolicy},
    v2,
    wire::RawProfile,
};
use qrcode::{QrCode, render::unicode};
use serde_json::{Value, json};
#[cfg(feature = "streamable-http")]
use std::net::SocketAddr;
#[cfg(feature = "oauth-resource-server")]
use url::Url;
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(
    name = "healthmd",
    version,
    about = "Portable command-line access to Health.md",
    long_about = "Request health exports from an open, paired iOS or Android device running Health.md. Source health reads always occur on the mobile device.",
    after_help = "TYPED HEALTH QUERIES:\n  CLI and MCP use the same fixed operation registry and canonical query service.\n  For sleep, run `healthmd query healthmd_sleep_sessions --arguments <JSON>` or call\n  the MCP operation with the identical JSON object. `healthmd extract` remains a\n  different canonical projection and is not the sleep-session query API.\n  Example dates shape:\n    {\"dates\":{\"type\":\"exact\",\"range\":{\"start_date\":\"2026-07-22\",\"end_date\":\"2026-07-28\"}}}\n\n  Inspect complete JSON Schema and examples without contacting iPhone:\n    healthmd mcp schema healthmd_sleep_sessions\n    healthmd mcp schema healthmd_metric_chart\n    healthmd mcp schema                # complete fixed operation catalog"
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
    /// Run the same canonical typed operation exposed by local MCP.
    Query(QueryArgs),
    /// Resume an interrupted durable direct job.
    Resume(ResumeArgs),
    /// Request cancellation of a durable direct job.
    Cancel(JobArgs),
    /// Pair and manage direct mobile trust.
    Direct(DirectArgs),
    /// Serve Health.md's fixed Model Context Protocol surface.
    Mcp(McpArgs),
    /// Configure a supported local AI host and pair the iPhone when needed.
    Setup(SetupArgs),
}

#[derive(Debug, Args)]
struct McpArgs {
    #[command(subcommand)]
    command: McpCommand,
}

#[derive(Debug, Subcommand)]
enum McpCommand {
    /// Serve the complete local JSON-RPC surface over stdio.
    Serve(McpServeArgs),
    /// Serve only readiness and typed-query tools over local stdio, without pairing or exports.
    ServeReadOnly(McpServeArgs),
    /// Serve the read-only MCP surface over standard Streamable HTTP on loopback.
    #[cfg(feature = "streamable-http")]
    ServeHttp(Box<McpServeHttpArgs>),
    /// Print the complete supported MCP tool JSON Schema and examples without contacting iPhone.
    Schema(McpSchemaArgs),
}

#[derive(Debug, Args)]
#[command(
    after_help = "EXAMPLES:\n  healthmd mcp schema healthmd_sleep_sessions\n  healthmd mcp schema healthmd_metric_chart\n  healthmd mcp schema    # complete fixed tool catalog"
)]
struct McpSchemaArgs {
    /// Fixed MCP tool name. Omit to print the complete catalog.
    tool: Option<String>,
}

#[derive(Debug, Args)]
struct McpServeArgs {
    /// Default timeout for readiness and query operations.
    #[arg(long, default_value_t = 1_200)]
    timeout_seconds: u64,
}

#[cfg(feature = "streamable-http")]
#[derive(Debug, Args)]
struct McpServeHttpArgs {
    /// Loopback address for the Streamable HTTP listener.
    #[arg(long, default_value = "127.0.0.1:8787")]
    bind: SocketAddr,

    /// Accepted Host header. Repeat for a reverse-proxy hostname during local development.
    #[arg(long = "allowed-host")]
    allowed_hosts: Vec<String>,

    /// Accepted browser Origin. Repeat for each trusted browser-based MCP client.
    #[arg(long = "allowed-origin")]
    allowed_origins: Vec<String>,

    /// Canonical public MCP resource URL, including `/mcp`, for OAuth token audience binding.
    #[cfg(feature = "oauth-resource-server")]
    #[arg(long)]
    oauth_resource: Option<Url>,

    /// Exact OAuth authorization-server issuer URL.
    #[cfg(feature = "oauth-resource-server")]
    #[arg(long)]
    oauth_issuer: Option<Url>,

    /// HTTPS JSON Web Key Set endpoint for access-token verification.
    #[cfg(feature = "oauth-resource-server")]
    #[arg(long)]
    oauth_jwks_uri: Option<Url>,

    /// Default timeout for readiness and query operations.
    #[arg(long, default_value_t = 1_200)]
    timeout_seconds: u64,
}

#[derive(Debug, Args)]
struct SetupArgs {
    #[command(subcommand)]
    command: SetupCommand,
}

#[derive(Debug, Subcommand)]
enum SetupCommand {
    /// Configure Codex to use this executable, then pair an iPhone if none is trusted.
    Codex(SetupCodexArgs),

    /// Configure Claude to use this executable, then pair an iPhone if none is trusted.
    Claude(SetupClaudeArgs),
}

#[derive(Debug, Args)]
struct SetupCodexArgs {
    /// Configure Codex without opening a pairing listener.
    #[arg(long)]
    skip_pairing: bool,

    /// Maximum time to wait for iPhone pairing.
    #[arg(long, default_value_t = 180)]
    pairing_timeout: u64,
}

#[derive(Debug, Args)]
struct SetupClaudeArgs {
    /// Configure Claude without opening a pairing listener.
    #[arg(long)]
    skip_pairing: bool,

    /// Maximum time to wait for iPhone pairing.
    #[arg(long, default_value_t = 180)]
    pairing_timeout: u64,

    /// Write a Claude Code project `.mcp.json` under this absolute directory instead of the
    /// Claude Desktop configuration.
    #[arg(long)]
    project: Option<PathBuf>,
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

    /// Export profile UUID to resolve on the iPhone for this request.
    /// Cannot combine with --use-iphone-settings or selectors.
    #[arg(long = "profile", value_name = "PROFILE_ID")]
    profile_id: Option<String>,

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
#[command(
    after_help = "EXAMPLES:\n  healthmd query healthmd_sleep_sessions --arguments '{\"dates\":{\"type\":\"all_available\"},\"all_pages\":true}'\n  healthmd query healthmd_metric_chart --arguments '{\"dates\":{\"type\":\"exact\",\"range\":{\"start_date\":\"2026-07-01\",\"end_date\":\"2026-07-07\"}},\"metrics\":{\"type\":\"explicit\",\"metric_ids\":[\"sleep_total\"]}}'"
)]
struct QueryArgs {
    /// Fixed operation name from `healthmd mcp schema`.
    operation: String,

    /// Exact JSON object accepted by the corresponding MCP operation.
    #[arg(long, value_name = "JSON")]
    arguments: String,

    /// Maximum time to wait for the foreground iPhone query.
    #[arg(long, default_value_t = 1_200)]
    timeout: u64,
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

fn main() -> ExitCode {
    std::panic::set_hook(Box::new(|_| eprintln!("healthmd: internal error")));
    if let Some(exit_code) = healthmd_client::credentials::run_credential_helper_if_requested() {
        return ExitCode::from(exit_code);
    }
    let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    else {
        eprintln!("healthmd: the asynchronous runtime is unavailable");
        return ExitCode::from(1);
    };
    #[cfg(debug_assertions)]
    {
        let mut arguments = std::env::args_os();
        let _executable = arguments.next();
        if arguments.next().as_deref() == Some("__credential-supervision-probe-v1".as_ref())
            && arguments.next().is_none()
        {
            let exit_code = if runtime
                .block_on(healthmd_client::credentials::OsCredentialStore::supervision_probe())
                .is_ok()
            {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            };
            runtime.shutdown_timeout(Duration::from_secs(2));
            return exit_code;
        }
    }
    let exit_code = runtime.block_on(async_main());
    runtime.shutdown_timeout(Duration::from_secs(2));
    exit_code
}

#[allow(clippy::too_many_lines)]
async fn async_main() -> ExitCode {
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
    let stdio_mcp = match &cli.command {
        Command::Mcp(McpArgs {
            command: McpCommand::Serve(options),
        }) => Some((options, false)),
        Command::Mcp(McpArgs {
            command: McpCommand::ServeReadOnly(options),
        }) => Some((options, true)),
        _ => None,
    };
    if let Some((options, read_only)) = stdio_mcp {
        if cli.backend != Backend::Direct || cli.transport != Transport::ManualIp {
            eprintln!("healthmd: MCP requires the direct Manual IP transport");
            return ExitCode::from(1);
        }
        let options = mcp::ServeOptions {
            device_id: cli.device,
            port: cli.port,
            timeout_seconds: options.timeout_seconds,
        };
        let result = if read_only {
            mcp::serve_read_only(options).await
        } else {
            mcp::serve(options).await
        };
        if let Err(error) = result {
            eprintln!("healthmd: {error}");
            return ExitCode::from(1);
        }
        return ExitCode::SUCCESS;
    }
    #[cfg(feature = "streamable-http")]
    if let Command::Mcp(McpArgs {
        command: McpCommand::ServeHttp(options),
    }) = &cli.command
    {
        if cli.backend != Backend::Direct || cli.transport != Transport::ManualIp {
            eprintln!("healthmd: direct-backed MCP HTTP requires the Manual IP transport");
            return ExitCode::from(1);
        }
        let serve_options = mcp::ServeOptions {
            device_id: cli.device,
            port: cli.port,
            timeout_seconds: options.timeout_seconds,
        };
        let http_options = mcp::HttpServerOptions {
            bind: options.bind,
            allowed_hosts: options.allowed_hosts.clone(),
            allowed_origins: options.allowed_origins.clone(),
        };
        #[cfg(feature = "oauth-resource-server")]
        let result = {
            let owner_subject = std::env::var("HEALTHMD_MCP_OAUTH_OWNER_SUBJECT")
                .ok()
                .filter(|subject| !subject.is_empty());
            let oauth = match (
                &options.oauth_resource,
                &options.oauth_issuer,
                &options.oauth_jwks_uri,
                owner_subject,
            ) {
                (None, None, None, None) => None,
                (Some(resource), Some(issuer), Some(jwks_uri), Some(owner_subject)) => {
                    Some(mcp::HttpOAuthOptions {
                        resource: resource.clone(),
                        issuer: issuer.clone(),
                        jwks_uri: jwks_uri.clone(),
                        owner_subject,
                    })
                }
                _ => {
                    eprintln!(
                        "healthmd: --oauth-resource, --oauth-issuer, --oauth-jwks-uri, and HEALTHMD_MCP_OAUTH_OWNER_SUBJECT must be provided together"
                    );
                    return ExitCode::from(2);
                }
            };
            mcp::serve_http(serve_options, http_options, oauth).await
        };
        #[cfg(not(feature = "oauth-resource-server"))]
        let result = mcp::serve_http(serve_options, http_options).await;
        if let Err(error) = result {
            eprintln!("healthmd: {error}");
            return ExitCode::from(1);
        }
        return ExitCode::SUCCESS;
    }
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
    if let Command::Mcp(McpArgs {
        command: McpCommand::Schema(options),
    }) = &cli.command
    {
        return mcp_schema(options).map(CommandSuccess::json);
    }
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
        Command::Setup(SetupArgs {
            command: SetupCommand::Codex(options),
        }) if backend == Backend::Direct => setup_codex(options, device, port)
            .await
            .map(CommandSuccess::json),
        Command::Setup(SetupArgs {
            command: SetupCommand::Claude(options),
        }) if backend == Backend::Direct => setup_claude(options, device, port)
            .await
            .map(CommandSuccess::json),
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
        Command::Query(options) if backend == Backend::Direct => {
            direct_query(options, device, port)
                .await
                .map(CommandSuccess::json)
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

fn mcp_schema(options: &McpSchemaArgs) -> Result<Value, CommandError> {
    mcp::tool_catalog(options.tool.as_deref()).map_err(|message| CommandError {
        backend: "direct",
        code: "invalid_request",
        message,
    })
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

async fn direct_query(
    options: QueryArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<Value, CommandError> {
    if options.timeout == 0 || options.timeout > 3_600 {
        return Err(usage_error(
            "query timeout must be between 1 and 3600 seconds",
        ));
    }
    let arguments: Value = serde_json::from_str(&options.arguments)
        .map_err(|_| usage_error("--arguments must be one valid JSON object"))?;
    if !arguments.is_object() {
        return Err(usage_error("--arguments must be one valid JSON object"));
    }
    mcp::query(
        mcp::ServeOptions {
            device_id: device,
            port,
            timeout_seconds: options.timeout,
        },
        &options.operation,
        arguments,
        tokio_util::sync::CancellationToken::new(),
    )
    .await
    .map_err(|error| match error {
        mcp::QueryError::InvalidArguments => usage_error("invalid typed query arguments"),
        mcp::QueryError::DirectInitialization => CommandError {
            backend: "direct",
            code: "direct_initialization_failed",
            message: "The direct client could not initialize native trust state.".to_owned(),
        },
        mcp::QueryError::Backend(error) => CommandError {
            backend: "direct",
            code: "healthmd_query_failed",
            message: error.message,
        },
    })
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
                    "Open Health.md on iPhone → Settings → Mac Sync → Direct CLI Access. Enable Manual IP, enter computer address {address_text}, port {bound_port}, and iOS code {ios_code}. Android code: {android_code}."
                );
                print_ios_pairing_qr(&addresses, bound_port, &ios_code);
            },
        )
        .await
        .map_err(map_direct_pair_error)?;
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

struct SetupPairing {
    device_id: Option<Uuid>,
    status: &'static str,
    receipt: Value,
}

async fn setup_codex_pairing(
    host: &'static str,
    skip_pairing: bool,
    pairing_timeout: u64,
    requested_device: Option<Uuid>,
    port: u16,
) -> Result<SetupPairing, CommandError> {
    if skip_pairing {
        return Ok(SetupPairing {
            device_id: requested_device,
            status: "skipped",
            receipt: Value::Null,
        });
    }
    let client = DirectClient::open().map_err(client_error)?;
    let paired_devices = client.paired_devices().await.map_err(client_error)?;
    let iphone_devices = paired_devices
        .iter()
        .filter(|device| {
            device.platform.is_none()
                || device.platform == Some(healthmd_protocol::wire::PeerPlatform::Ios)
        })
        .collect::<Vec<_>>();
    if let Some(device_id) = requested_device {
        if !iphone_devices
            .iter()
            .any(|device| device.installation_id.0 == device_id)
        {
            return Err(CommandError {
                backend: "direct",
                code: "direct_device_not_found",
                message: format!(
                    "No paired iPhone has installation ID {}",
                    device_id.to_string().to_lowercase()
                ),
            });
        }
        return Ok(SetupPairing {
            device_id: Some(device_id),
            status: "already_paired",
            receipt: Value::Null,
        });
    }
    if iphone_devices.len() == 1 {
        return Ok(SetupPairing {
            device_id: Some(iphone_devices[0].installation_id.0),
            status: "already_paired",
            receipt: Value::Null,
        });
    }
    if iphone_devices.len() > 1 {
        return Err(CommandError {
            backend: "direct",
            code: "direct_device_selection_required",
            message: "More than one iPhone is paired; rerun setup with --device UUID".into(),
        });
    }
    drop(client);
    let result = direct_pair(
        PairArgs {
            pairing_code: None,
            android_pairing_code: None,
            timeout: pairing_timeout,
        },
        port,
    )
    .await?;
    if result.pointer("/device/platform").and_then(Value::as_str) != Some("ios") {
        return Err(CommandError {
            backend: "direct",
            code: "direct_source_unsupported",
            message: format!("{host} health analysis requires a paired iPhone"),
        });
    }
    let device_id = result
        .pointer("/device/installation_id")
        .and_then(Value::as_str)
        .and_then(|value| Uuid::parse_str(value).ok())
        .ok_or_else(|| CommandError {
            backend: "direct",
            code: "invalid_direct_response",
            message: "The pairing receipt did not identify the paired iPhone".into(),
        })?;
    Ok(SetupPairing {
        device_id: Some(device_id),
        status: "paired",
        receipt: result,
    })
}

async fn setup_codex(
    options: SetupCodexArgs,
    requested_device: Option<Uuid>,
    port: u16,
) -> Result<Value, CommandError> {
    if !(10..=600).contains(&options.pairing_timeout) {
        return Err(usage_error(
            "setup pairing timeout must be between 10 and 600 seconds",
        ));
    }
    let pairing = setup_codex_pairing(
        "Codex",
        options.skip_pairing,
        options.pairing_timeout,
        requested_device,
        port,
    )
    .await?;

    let executable = onboarding::current_invocation_executable().map_err(|_| CommandError {
        backend: "direct",
        code: "codex_configuration_failed",
        message: "The installed healthmd executable path could not be resolved".into(),
    })?;
    let receipt =
        onboarding::configure_codex(&executable, pairing.device_id, port).map_err(|error| {
            CommandError {
                backend: "direct",
                code: "codex_configuration_failed",
                message: error.to_string(),
            }
        })?;

    Ok(json!({
        "schema": "healthmd.codex_setup",
        "schema_version": 1,
        "status": "success",
        "backend": "direct",
        "configuration": {
            "host": "codex",
            "path": receipt.config_path,
            "changed": receipt.changed,
            "command": receipt.command,
            "args": receipt.args,
            "same_executable_identity": true,
            "export_approval_mode": "prompt"
        },
        "pairing": {
            "status": pairing.status,
            "device_id": pairing.device_id.map(|value| value.to_string().to_lowercase()),
            "receipt": pairing.receipt
        },
        "restart_codex": receipt.changed,
        "message": if options.skip_pairing {
            "Codex is configured. Run `healthmd setup codex` with Health.md open on iPhone to pair."
        } else {
            "Codex is configured for the paired iPhone. Restart Codex, keep Health.md foreground, and call healthmd_doctor."
        }
    }))
}

async fn setup_claude(
    options: SetupClaudeArgs,
    requested_device: Option<Uuid>,
    port: u16,
) -> Result<Value, CommandError> {
    if !(10..=600).contains(&options.pairing_timeout) {
        return Err(usage_error(
            "setup pairing timeout must be between 10 and 600 seconds",
        ));
    }
    let pairing = setup_codex_pairing(
        "Claude",
        options.skip_pairing,
        options.pairing_timeout,
        requested_device,
        port,
    )
    .await?;

    let executable = onboarding::current_invocation_executable().map_err(|_| CommandError {
        backend: "direct",
        code: "claude_configuration_failed",
        message: "The installed healthmd executable path could not be resolved".into(),
    })?;
    let (receipt, target) = match &options.project {
        Some(project) => (
            onboarding::configure_claude_project(project, &executable, pairing.device_id, port)
                .map_err(|error| claude_configuration_error(&error))?,
            "project",
        ),
        None => (
            onboarding::configure_claude_desktop(&executable, pairing.device_id, port)
                .map_err(|error| claude_configuration_error(&error))?,
            "desktop",
        ),
    };

    Ok(json!({
        "schema": "healthmd.claude_setup",
        "schema_version": 1,
        "status": "success",
        "backend": "direct",
        "configuration": {
            "host": "claude",
            "target": target,
            "path": receipt.config_path,
            "changed": receipt.changed,
            "command": receipt.command,
            "args": receipt.args,
            "same_executable_identity": true
        },
        "pairing": {
            "status": pairing.status,
            "device_id": pairing.device_id.map(|value| value.to_string().to_lowercase()),
            "receipt": pairing.receipt
        },
        "restart_claude": receipt.changed,
        "message": match (target, options.skip_pairing) {
            ("project", true) => "Claude Code is configured for the project. Run `healthmd setup claude` with Health.md open on iPhone to pair.",
            ("project", false) => "Claude Code is configured for the project. Trust the workspace, approve the healthmd server, keep Health.md foreground, and call healthmd_doctor.",
            (_, true) => "Claude Desktop is configured. Run `healthmd setup claude` with Health.md open on iPhone to pair.",
            (_, false) => "Claude Desktop is configured for the paired iPhone. Restart Claude Desktop, keep Health.md foreground, and call healthmd_doctor."
        }
    }))
}

fn claude_configuration_error(error: &onboarding::OnboardingError) -> CommandError {
    CommandError {
        backend: "direct",
        code: "claude_configuration_failed",
        message: error.to_string(),
    }
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
            message: "Run `healthmd direct pair`, then scan its QR from Sync > Direct CLI Access > Scan Pairing QR in the open iPhone app."
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
        profile_reference: None,
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
            "Android generated-file direct export uses saved device selections or a profile; remove CLI selectors",
        ));
    }
    let profile_reference = options
        .profile_id
        .as_deref()
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .map(|profile_id| v2::ProfileReference {
            profile_id: profile_id.to_owned(),
            name: None,
        });
    if options
        .profile_id
        .as_deref()
        .is_some_and(|id| id.trim().is_empty())
    {
        return Err(usage_error("--profile requires a non-empty profile ID"));
    }
    if profile_reference.is_some() && options.use_device_settings {
        return Err(usage_error(
            "--profile cannot combine with --use-device-settings; the profile owns the settings scope",
        ));
    }
    let (settings_policy, profile_reference) = match profile_reference {
        Some(reference) => (v2::SettingsPolicy::Profile, Some(reference)),
        None => (v2::SettingsPolicy::SavedDeviceSettings, None),
    };
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
            settings_policy,
            profile_reference,
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
async fn direct_file_export(
    options: ExportArgs,
    device: Option<Uuid>,
    port: u16,
) -> Result<CommandSuccess, CommandError> {
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
    let destination = GeneratedDestination::open(&destination)
        .map_err(map_direct_file_error)?
        .root()
        .to_str()
        .ok_or_else(|| usage_error("--destination must be valid UTF-8"))?
        .to_owned();
    let profile = options
        .profile_id
        .as_deref()
        .map(|profile_id| ProfileReference {
            profile_id: profile_id.trim().to_owned(),
            name: None,
        });
    let invocation = GeneratedFileExportInput {
        dates: operation_date_options(&options.dates),
        selection: operation_selection_options(&options.selection),
        use_device_settings: options.use_device_settings,
        profile,
        destination,
        timeout: Duration::from_secs(options.timeout),
    }
    .build(
        Uuid::new_v4(),
        whole_second_now(),
        Local::now().date_naive(),
    )
    .map_err(operation_input_error)?;
    let client = DirectClient::open().map_err(client_error)?;
    let result = client
        .export_files(invocation.request, device, port, invocation.timeout)
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
    let normalized = operation_selection_options(&options.selection)
        .extract()
        .map_err(operation_input_error)?;
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
    let job_id = Uuid::new_v4();
    let request = ExportRequest {
        protocol_version: 1,
        job_id: SwiftUuid(job_id),
        created_at: whole_second_now(),
        date_selection: resolve_date_selection(&options.dates)?,
        settings_policy: SettingsPolicy::RequestedDatesOnly,
        profile_reference: None,
        response_mode: ResponseMode::RawJson,
        raw_profile: Some(RawProfile::HealthDataProjection),
        canonical_selection: Some(normalized.selection),
        destination: None,
    };
    let pointers = normalized.projection_pointers;
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

fn operation_date_options(options: &DateArgs) -> OperationDateOptions {
    OperationDateOptions {
        yesterday: options.yesterday,
        last: options.last,
        from: options.from.clone(),
        to: options.to.clone(),
        all: options.all,
    }
}

fn operation_selection_options(options: &SelectionArgs) -> SelectionOptions {
    SelectionOptions {
        metric_ids: options.metrics.clone(),
        categories: options.categories.clone(),
        all_metrics: options.all_metrics,
        detail: match options.detail {
            Detail::Summary => SelectionDetail::Summary,
            Detail::Lossless => SelectionDetail::Lossless,
        },
        object_paths: options.objects.clone(),
        field_pointers: options.fields.clone(),
        source_ids: options.sources.clone(),
    }
}

fn operation_input_error(OperationInputError { message, .. }: OperationInputError) -> CommandError {
    usage_error(message)
}

fn resolve_date_selection(options: &DateArgs) -> Result<DateSelection, CommandError> {
    operation_date_options(options)
        .resolve(Local::now().date_naive())
        .map_err(operation_input_error)
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
        "message": direct_job_status_message(record.state),
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
                "message": "The iPhone export failed."
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
        "message": direct_job_status_message(record.state),
        "destination_path": record.destination_root,
        "failure": record.failure.as_ref().map(|failure| json!({
            "job_id": failure.job_id,
            "code": failure.code,
            "phase": failure.phase,
            "retryable": failure.retryable,
            "public_message": "The Android export failed.",
            "details": {}
        })),
        "resumable": !record.state.is_terminal() && record.state != JobState::CancellationPending
    })
}

const fn direct_job_status_message(state: JobState) -> &'static str {
    match state {
        JobState::Queued => "Direct export is queued.",
        JobState::Connecting => "Waiting for the paired source to connect.",
        JobState::Sent => "The direct export request was sent.",
        JobState::Accepted => "The paired source accepted the direct export.",
        JobState::Preparing => "The paired source is preparing the direct export.",
        JobState::Transferring => "Direct export transfer is in progress.",
        JobState::Paused => "Direct export is paused and can be resumed.",
        JobState::AwaitingPeerAcknowledgement => {
            "Direct export is awaiting source acknowledgement."
        }
        JobState::CancellationPending => "Direct export cancellation is pending acknowledgement.",
        JobState::Completed => "Direct export completed.",
        JobState::Failed => "Direct export failed.",
        JobState::Cancelled => "Direct export was cancelled.",
    }
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
    let expected_bytes = fs::metadata(source)?.len();
    let layout = healthmd_client::storage::StorageLayout::discover()
        .map_err(|_| io::Error::other("output storage reservation failed"))?;
    let _output_reservation =
        healthmd_client::reserve_output_capacity(&layout.root, parent, expected_bytes)
            .map_err(|_| io::Error::other("output storage reservation failed"))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    fs2::FileExt::allocate(temporary.as_file(), expected_bytes)?;
    let mut input = fs::File::open(source)?;
    let copied = io::copy(&mut input, &mut temporary)?;
    if copied != expected_bytes {
        return Err(io::Error::other("output source changed during copy"));
    }
    temporary.as_file().set_len(expected_bytes)?;
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
    healthmd_cli::pairing::generate_numeric_code(digit_count).map_err(|_| CommandError {
        backend: "direct",
        code: "secure_random_unavailable",
        message: "the operating system could not generate a secure pairing code".into(),
    })
}

fn print_ios_pairing_qr(addresses: &[LocalAddress], port: u16, pairing_code: &str) {
    let Some(address) = preferred_pairing_address(addresses) else {
        return;
    };
    let link = ios_pairing_link(&address.address, port, pairing_code);
    let Ok(code) = QrCode::new(link.as_bytes()) else {
        return;
    };
    let rendered = code.render::<unicode::Dense1x2>().quiet_zone(true).build();
    eprintln!(
        "In foreground Health.md, open Sync > Direct CLI Access, tap Scan Pairing QR, and scan this image:\n{rendered}"
    );
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
    let code = match error {
        ClientError::InvalidTrustState => "direct_trust_invalid",
        ClientError::CredentialMutationOutcomeUnknown => "direct_storage_outcome_unknown",
        _ => "direct_storage_unavailable",
    };
    direct_error(code, error)
}

#[allow(clippy::needless_pass_by_value)]
fn map_direct_pair_error(error: ClientError) -> CommandError {
    let code = match error {
        ClientError::InvalidTrustState => "direct_trust_invalid",
        ClientError::CredentialStore(_) => "direct_storage_unavailable",
        ClientError::CredentialMutationOutcomeUnknown => "direct_storage_outcome_unknown",
        _ => "direct_pairing_failed",
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
        ClientError::CredentialMutationOutcomeUnknown => "direct_storage_outcome_unknown",
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

fn direct_error(code: &'static str, _error: impl std::fmt::Display) -> CommandError {
    let message = match code {
        "direct_pairing_failed" => {
            "Direct pairing failed. Verify the one-time code and source app."
        }
        "direct_trust_invalid" => {
            "The saved direct trust state is invalid. Reset trust explicitly before pairing again."
        }
        "direct_storage_unavailable" => {
            "The native credential or private state store is unavailable."
        }
        "direct_storage_outcome_unknown" => {
            "A native credential mutation may have completed. Inspect pairing state before retrying."
        }
        "direct_job_busy" => "Another process is using this durable direct job.",
        "direct_device_selection_required" => {
            "More than one mobile source is paired. Select one explicitly."
        }
        "direct_device_not_paired" => "The selected mobile source is not paired.",
        "direct_export_paused" => "The durable direct export paused and can be resumed.",
        "direct_cancellation_pending" => {
            "Cancellation is pending delivery to the authenticated mobile source."
        }
        "direct_job_not_resumable" => {
            "The durable direct job cannot resume from its current state."
        }
        "invalid_direct_file_receipt" => "The generated-file receipt failed integrity validation.",
        "invalid_direct_response" => {
            "The mobile source returned an invalid or rejected direct response."
        }
        "job_not_found" => "The durable direct job was not found.",
        "job_expired" => "The durable direct job expired after seven days.",
        "cancelled" => "The direct export was cancelled.",
        _ => "The direct mobile source is unavailable.",
    };
    CommandError {
        backend: "direct",
        code,
        message: message.into(),
    }
}

const fn command_name(command: &Command) -> &'static str {
    match command {
        Command::Status(_) => "status",
        Command::Export(_) => "export",
        Command::Extract(_) => "extract",
        Command::Query(_) => "query",
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
        Command::Mcp(McpArgs {
            command: McpCommand::Serve(_),
        }) => "mcp serve",
        Command::Mcp(McpArgs {
            command: McpCommand::ServeReadOnly(_),
        }) => "mcp serve-read-only",
        #[cfg(feature = "streamable-http")]
        Command::Mcp(McpArgs {
            command: McpCommand::ServeHttp(_),
        }) => "mcp serve-http",
        Command::Mcp(McpArgs {
            command: McpCommand::Schema(_),
        }) => "mcp schema",
        Command::Setup(SetupArgs {
            command: SetupCommand::Codex(_),
        }) => "setup codex",
        Command::Setup(SetupArgs {
            command: SetupCommand::Claude(_),
        }) => "setup claude",
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
            DateSelection::Exact(healthmd_protocol::models::ExactDateSelection {
                start: "2026-07-01".into(),
                end: "2026-07-24".into(),
            })
        );
    }

    #[test]
    fn canonical_pointer_validation_rejects_ambiguous_escapes() {
        assert!(healthmd_operations::validate_canonical_pointer("/sleep/samples/0").is_ok());
        assert!(healthmd_operations::validate_canonical_pointer("/a~1b/~0key").is_ok());
        assert!(healthmd_operations::validate_canonical_pointer("sleep").is_err());
        assert!(healthmd_operations::validate_canonical_pointer("/bad~2escape").is_err());
        assert!(healthmd_operations::validate_canonical_pointer("/bad~").is_err());
    }

    #[test]
    fn jsonl_receipt_path_is_appended_without_replacing_extension() {
        assert_eq!(
            receipt_output_path(Path::new("health.jsonl")),
            PathBuf::from("health.jsonl.receipt.json")
        );
    }

    #[test]
    fn ios_pairing_link_is_exact_and_ephemeral() {
        assert_eq!(
            ios_pairing_link("192.168.1.42", 17_647, "123456"),
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=123456"
        );
    }

    #[test]
    fn tailscale_carrier_grade_nat_range_is_detected() {
        assert!(healthmd_cli::pairing::is_tailscale_ipv4([100, 64, 0, 1]));
        assert!(healthmd_cli::pairing::is_tailscale_ipv4([
            100, 127, 255, 254
        ]));
        assert!(!healthmd_cli::pairing::is_tailscale_ipv4([100, 128, 0, 1]));
        assert!(!healthmd_cli::pairing::is_tailscale_ipv4([192, 168, 1, 2]));
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
        let (pointer, category, lossless) =
            healthmd_operations::canonical_object_path("archive").unwrap();
        assert_eq!(pointer, "/healthkit_record_archive");
        assert_eq!(category, None);
        assert!(lossless);
    }

    #[test]
    fn generic_help_routes_typed_queries_and_shows_the_sleep_shape() {
        use clap::CommandFactory as _;

        let mut command = Cli::command();
        let help = command.render_long_help().to_string();
        assert!(help.contains("healthmd_sleep_sessions"));
        assert!(help.contains("start_date"));
        assert!(help.contains("healthmd mcp schema healthmd_sleep_sessions"));
        assert!(help.contains("is not the sleep-session query API"));
    }

    #[test]
    fn typed_query_command_uses_fixed_operation_and_json_arguments() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "query",
            "healthmd_sleep_sessions",
            "--arguments",
            r#"{"dates":{"type":"all_available"},"all_pages":true}"#,
        ])
        .unwrap();
        let Command::Query(options) = parsed.command else {
            panic!("expected query command");
        };
        assert_eq!(options.operation, "healthmd_sleep_sessions");
        assert_eq!(options.timeout, 1_200);
    }

    #[test]
    fn same_binary_mcp_and_codex_setup_commands_parse() {
        let mcp = Cli::try_parse_from([
            "healthmd",
            "--device",
            "01234567-89ab-4cde-8fab-0123456789ab",
            "mcp",
            "serve",
            "--timeout-seconds",
            "900",
        ])
        .unwrap();
        assert_eq!(
            mcp.device,
            Some(Uuid::parse_str("01234567-89ab-4cde-8fab-0123456789ab").unwrap())
        );
        let Command::Mcp(McpArgs {
            command: McpCommand::Serve(options),
        }) = mcp.command
        else {
            panic!("expected MCP serve command");
        };
        assert_eq!(options.timeout_seconds, 900);

        let read_only = Cli::try_parse_from([
            "healthmd",
            "--device",
            "01234567-89ab-4cde-8fab-0123456789ab",
            "mcp",
            "serve-read-only",
            "--timeout-seconds",
            "600",
        ])
        .unwrap();
        let Command::Mcp(McpArgs {
            command: McpCommand::ServeReadOnly(options),
        }) = read_only.command
        else {
            panic!("expected read-only MCP serve command");
        };
        assert_eq!(options.timeout_seconds, 600);

        let schema =
            Cli::try_parse_from(["healthmd", "mcp", "schema", "healthmd_sleep_sessions"]).unwrap();
        let Command::Mcp(McpArgs {
            command: McpCommand::Schema(options),
        }) = schema.command
        else {
            panic!("expected MCP schema command");
        };
        assert_eq!(options.tool.as_deref(), Some("healthmd_sleep_sessions"));

        let setup = Cli::try_parse_from([
            "healthmd",
            "setup",
            "codex",
            "--skip-pairing",
            "--pairing-timeout",
            "240",
        ])
        .unwrap();
        let Command::Setup(SetupArgs {
            command: SetupCommand::Codex(options),
        }) = setup.command
        else {
            panic!("expected Codex setup command");
        };
        assert!(options.skip_pairing);
        assert_eq!(options.pairing_timeout, 240);
    }

    #[cfg(not(feature = "streamable-http"))]
    #[test]
    fn default_build_exposes_only_local_mcp_commands() {
        assert!(Cli::try_parse_from(["healthmd", "mcp", "serve-http"]).is_err());
        assert!(Cli::try_parse_from(["healthmd", "mcp", "serve-hosted"]).is_err());
        assert!(Cli::try_parse_from(["healthmd", "mcp", "serve"]).is_ok());
        assert!(Cli::try_parse_from(["healthmd", "mcp", "serve-read-only"]).is_ok());
        assert!(Cli::try_parse_from(["healthmd", "mcp", "schema"]).is_ok());
    }

    #[cfg(feature = "streamable-http")]
    #[test]
    fn streamable_http_feature_exposes_loopback_server() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "mcp",
            "serve-http",
            "--bind",
            "127.0.0.1:8787",
            "--allowed-host",
            "localhost:8787",
        ])
        .unwrap();
        let Command::Mcp(McpArgs {
            command: McpCommand::ServeHttp(options),
        }) = parsed.command
        else {
            panic!("expected MCP Streamable HTTP command");
        };
        assert_eq!(options.bind, "127.0.0.1:8787".parse().unwrap());
        assert_eq!(options.allowed_hosts, ["localhost:8787"]);
    }

    #[test]
    fn removed_hosted_server_command_is_rejected() {
        assert!(Cli::try_parse_from(["healthmd", "mcp", "serve-hosted"]).is_err());
    }

    #[cfg(feature = "oauth-resource-server")]
    #[test]
    fn remote_mcp_http_oauth_configuration_parses_without_a_vendor_specific_client() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "mcp",
            "serve-http",
            "--bind",
            "127.0.0.1:8787",
            "--allowed-host",
            "mcp.health.md",
            "--oauth-resource",
            "https://mcp.health.md/mcp",
            "--oauth-issuer",
            "https://auth.health.md/",
            "--oauth-jwks-uri",
            "https://auth.health.md/.well-known/jwks.json",
        ])
        .unwrap();
        let Command::Mcp(McpArgs {
            command: McpCommand::ServeHttp(options),
        }) = parsed.command
        else {
            panic!("expected MCP Streamable HTTP command");
        };
        assert_eq!(options.bind, "127.0.0.1:8787".parse().unwrap());
        assert_eq!(options.allowed_hosts, ["mcp.health.md"]);
        assert_eq!(
            options.oauth_resource.unwrap().as_str(),
            "https://mcp.health.md/mcp"
        );
        assert_eq!(
            options.oauth_issuer.unwrap().as_str(),
            "https://auth.health.md/"
        );
    }

    #[test]
    fn internal_and_peer_error_text_never_reaches_public_json_messages() {
        let private = "synthetic-private-health-value";
        let mapped = map_direct_client_error(ClientError::InvalidTransfer(private.into()));
        assert_eq!(mapped.code, "invalid_direct_response");
        assert!(!mapped.message.contains(private));

        let pairing = direct_error("direct_pairing_failed", private);
        assert!(!pairing.message.contains(private));

        let unknown = map_direct_pair_error(ClientError::CredentialMutationOutcomeUnknown);
        assert_eq!(unknown.code, "direct_storage_outcome_unknown");
    }
}
