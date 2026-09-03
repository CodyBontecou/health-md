#![forbid(unsafe_code)]

mod guidance;
mod output;

use std::{
    fs,
    io::{self, IsTerminal as _, Write as _},
    path::{Path, PathBuf},
    process::ExitCode,
    time::Duration,
};

use chrono::{Duration as ChronoDuration, Local, SecondsFormat, Timelike as _, Utc};
use clap::{Args, Parser, Subcommand, ValueEnum, error::ErrorKind};
use healthmd_cli::{
    mcp, onboarding,
    pairing::{LocalAddress, local_ipv4_addresses, pairing_link, preferred_pairing_address},
};
use healthmd_client::{
    ClientError,
    direct::{
        DEFAULT_WAKE_TIMEOUT_SECONDS, DirectClient, MAXIMUM_WAKE_TIMEOUT_SECONDS, SourceStatus,
        WakeWindow,
    },
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

const WELCOME_TEXT: &str = concat!(
    "Health.md CLI ",
    env!("CARGO_PKG_VERSION"),
    "\n\n",
    "Secure, direct access to Health.md on your iPhone or Android device.\n\n",
    "Get started:\n",
    "  healthmd direct pair    Pair a mobile device\n",
    "  healthmd setup codex    Set up Codex and pair an iPhone\n",
    "  healthmd status         Check connection readiness\n\n",
    "Run `healthmd --help` to see all commands.\n",
);

#[derive(Debug, Parser)]
#[command(
    name = "healthmd",
    version,
    about = "Portable command-line access to Health.md",
    long_about = "Request health exports from an open, paired iOS or Android device running Health.md. Source health reads always occur on the mobile device.",
    after_help = "TYPED HEALTH QUERIES:\n  CLI and MCP use the same fixed operation registry and canonical query service.\n  Inspect sleep arguments locally with `healthmd query healthmd_sleep_sessions`, then\n  rerun it with `--arguments <JSON>`. `healthmd extract` remains a different canonical\n  projection and is not the sleep-session query API.\n  Example dates shape:\n    {\"dates\":{\"type\":\"exact\",\"range\":{\"start_date\":\"2026-07-22\",\"end_date\":\"2026-07-28\"}}}\n\n  Inspect arguments and examples without contacting iPhone; add --json for full schemas:\n    healthmd query healthmd_sleep_sessions\n    healthmd query healthmd_metric_chart\n    healthmd mcp schema                # fixed operation catalog"
)]
struct Cli {
    /// Execution backend. `direct` is the portable mobile connection; `mac-app` is reserved.
    #[arg(long, global = true, default_value = "direct")]
    backend: Backend,

    /// Direct transport. Use `manual-ip` for LAN or Tailscale; Nearby is legacy-only.
    #[arg(long, global = true, default_value = "manual-ip")]
    transport: Transport,

    /// Trusted mobile installation UUID from `healthmd direct devices`.
    /// Required only when more than one source is paired.
    #[arg(long, global = true)]
    device: Option<Uuid>,

    /// TCP listener port saved in the mobile app's Direct CLI settings.
    #[arg(long, global = true, default_value_t = healthmd_protocol::DEFAULT_MANUAL_IP_PORT)]
    port: u16,

    /// Always emit stable machine-readable JSON for structured command output.
    #[arg(long, global = true, conflicts_with = "human")]
    json: bool,

    /// Always emit readable terminal text, including when output is piped.
    #[arg(long, global = true, conflicts_with = "json")]
    human: bool,

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
#[command(
    after_help = "DISCOVERY:\n  Run `healthmd mcp` without a subcommand to list available MCP commands. Add --json\n  for the machine contract. No listener is started in discovery mode."
)]
struct McpArgs {
    #[command(subcommand)]
    command: Option<McpCommand>,
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
    /// Inspect supported MCP tool inputs and examples without contacting iPhone.
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
#[command(
    after_help = "DISCOVERY:\n  Run `healthmd setup` without a subcommand to list supported host integrations\n  without changing any configuration."
)]
struct SetupArgs {
    #[command(subcommand)]
    command: Option<SetupCommand>,
}

#[derive(Debug, Subcommand)]
enum SetupCommand {
    /// Configure Codex to use this executable, then pair an iPhone if none is trusted.
    Codex(SetupCodexArgs),
}

#[derive(Debug, Args)]
#[command(
    after_help = "EXAMPLES:\n  healthmd setup codex\n  healthmd setup codex --skip-pairing\n\nThe generated MCP entry launches this same `healthmd mcp serve` executable identity so\nnative pairing credentials are not split across binaries. Existing unrelated Codex settings\nare preserved."
)]
struct SetupCodexArgs {
    /// Configure Codex without opening a pairing listener.
    #[arg(long)]
    skip_pairing: bool,

    /// Maximum seconds to wait for iPhone pairing (30 through 600).
    #[arg(long, default_value_t = 180)]
    pairing_timeout: u64,
}

#[derive(Debug, Args)]
#[command(
    after_help = "EXAMPLES:\n  healthmd status\n  healthmd status --job <JOB_UUID>\n\nWithout --job, Health.md checks the paired foreground mobile source. With --job, it\nreads durable local state and does not contact the device."
)]
struct StatusArgs {
    /// Read one durable local job by UUID instead of contacting the mobile source.
    #[arg(long)]
    job: Option<Uuid>,
}

#[derive(Debug, Args)]
#[command(
    long_about = "Export either a validated platform-native raw artifact or production-generated Health.md files. Every execution requires exactly one date selection. Raw mode requires --raw; generated-file mode requires an existing absolute --destination directory. Running `healthmd export` with an incomplete request returns local guidance and never contacts a device.",
    after_help = "MODES:\n  Raw artifact:\n    healthmd export --last 7 --raw --output week.json\n    Omit --output to stream validated JSON/NDJSON to stdout.\n\n  Generated files:\n    healthmd export --yesterday --destination <EXISTING_ABSOLUTE_DIRECTORY>\n    The mobile app's production exporters create files; the host validates and binds\n    the destination before transfer.\n\nDATE SELECTION (choose exactly one):\n  --yesterday | --last DAYS | --from YYYY-MM-DD --to YYYY-MM-DD | --all\n\nDISCOVERY:\n  Run `healthmd export` without a complete mode/date selection to receive structured\n  requirements, platform constraints, and argv examples without contacting a device."
)]
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

    /// Maximum seconds to wait for export preparation and transfer (5 through 900).
    #[arg(long, default_value_t = 300)]
    timeout: u64,

    #[command(flatten)]
    wake: WakeArgs,

    #[command(flatten)]
    selection: SelectionArgs,
}

#[derive(Debug, Args)]
#[command(
    long_about = "Request a scoped canonical healthmd.health_data projection from a paired iOS source. Every execution requires exactly one date selection and at least one primary selector. This is distinct from typed sleep, workout, chart, and evidence queries.",
    after_help = "REQUIRED:\n  Date: --yesterday | --last DAYS | --from DATE --to DATE | --all\n  Scope: --metric ID | --category NAME | --object ALIAS | --all-metrics\n\nEXAMPLES:\n  healthmd extract --category Sleep --last 7 --output sleep.json\n  healthmd extract --metric workouts --last 14 --object workouts --detail lossless\n  healthmd extract --category Sleep --last 7 --format jsonl --output sleep.jsonl\n\nFor typed sleep questions, run `healthmd query healthmd_sleep_sessions` first to\ninspect its argument synopsis; add --json for the exact schema."
)]
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

    /// Maximum seconds to wait for export preparation and transfer (5 through 900).
    #[arg(long, default_value_t = 300)]
    timeout: u64,

    #[command(flatten)]
    wake: WakeArgs,

    /// Canonical output encoding. JSONL also emits a health-free receipt.
    #[arg(long, value_enum, default_value = "json")]
    format: ExtractionFormat,
}

#[derive(Debug, Args)]
#[command(
    long_about = "Run one fixed typed operation through the same registry and canonical evaluator used by MCP. Omit OPERATION to list all query operations. Supply OPERATION without --arguments to inspect its inputs and executable argv examples; add --json for the complete schema. Discovery never opens credentials or contacts iPhone.",
    after_help = "DISCOVERY:\n  healthmd query\n  healthmd query healthmd_sleep_sessions\n  healthmd mcp schema healthmd_sleep_sessions\n\nEXECUTION EXAMPLES:\n  healthmd query healthmd_sleep_sessions --arguments '{\"dates\":{\"type\":\"all_available\"},\"all_pages\":true}'\n  healthmd query healthmd_metric_chart --arguments '{\"dates\":{\"type\":\"exact\",\"range\":{\"start_date\":\"2026-07-01\",\"end_date\":\"2026-07-07\"}},\"metrics\":{\"type\":\"explicit\",\"metric_ids\":[\"sleep_total\"]}}'\n\nThe JSON examples above are illustrative. Resolve the user's actual dates before execution."
)]
struct QueryArgs {
    /// Fixed operation name. Omit it to list all typed query operations.
    operation: Option<String>,

    /// Exact JSON object accepted by the operation. Omit it to inspect that operation's schema.
    #[arg(long, value_name = "JSON")]
    arguments: Option<String>,

    /// Maximum seconds to wait for the foreground iPhone query (1 through 3600).
    #[arg(long, default_value_t = 1_200)]
    timeout: u64,

    #[command(flatten)]
    wake: WakeArgs,
}

#[derive(Clone, Copy, Debug, Args)]
struct WakeArgs {
    /// Seconds to wait for an unavailable paired phone to become active; 0 disables waiting.
    #[arg(long, default_value_t = DEFAULT_WAKE_TIMEOUT_SECONDS)]
    wake_timeout: u64,

    /// Skip the best-effort push-notification nudge for this command (RFC-0005 P2).
    #[arg(long)]
    no_wake: bool,
}

#[derive(Debug, Args)]
struct DateArgs {
    /// Select yesterday in this computer's local calendar.
    #[arg(long, conflicts_with_all = ["last", "from", "to", "all"])]
    yesterday: bool,

    /// Select the previous DAYS complete local-calendar days, ending yesterday.
    #[arg(long, value_name = "DAYS", conflicts_with_all = ["yesterday", "from", "to", "all"])]
    last: Option<u32>,

    /// Inclusive range start. Must be supplied with --to.
    #[arg(long, value_name = "YYYY-MM-DD", requires = "to", conflicts_with_all = ["yesterday", "last", "all"])]
    from: Option<String>,

    /// Inclusive range end. Must be supplied with --from and must not precede it.
    #[arg(long, value_name = "YYYY-MM-DD", requires = "from", conflicts_with_all = ["yesterday", "last", "all"])]
    to: Option<String>,

    /// Select the source's complete available date scope. This may produce a large job.
    #[arg(long, conflicts_with_all = ["yesterday", "last", "from", "to"])]
    all: bool,
}

#[derive(Debug, Args)]
struct SelectionArgs {
    /// Canonical metric ID. Repeat to select multiple metrics.
    #[arg(long = "metric", value_name = "METRIC_ID")]
    metrics: Vec<String>,

    /// Canonical category name. Repeat to select multiple categories.
    #[arg(long = "category", value_name = "CATEGORY")]
    categories: Vec<String>,

    /// Select all supported metrics; cannot combine with --metric or --category.
    #[arg(long, conflicts_with_all = ["metrics", "categories"])]
    all_metrics: bool,

    /// Summary values or lossless source-record detail.
    #[arg(long, value_enum, default_value = "summary")]
    detail: Detail,

    /// Canonical object alias or absolute JSON Pointer for extract (for example sleep or archive).
    #[arg(long = "object", value_name = "ALIAS")]
    objects: Vec<String>,

    /// RFC 6901 JSON Pointer to retain during extract. Repeat for multiple fields.
    #[arg(long = "field", value_name = "JSON_POINTER")]
    fields: Vec<String>,

    /// Canonical source ID. Repeat to select multiple sources.
    #[arg(long = "source", value_name = "SOURCE_ID")]
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
#[command(
    long_about = "Resume the exact immutable request and destination bound to an interrupted durable direct job. Omit JOB_ID to receive identifier and option guidance without contacting a device.",
    after_help = "EXAMPLES:\n  healthmd resume <JOB_UUID>\n  healthmd resume <JOB_UUID> --output resumed.json\n  healthmd status --job <JOB_UUID>\n\nResume never changes the saved peer, dates, selection, destination, or artifact format."
)]
struct ResumeArgs {
    /// Durable job UUID from an export receipt or `healthmd status --job`.
    job_id: Option<Uuid>,

    /// Atomic output path for a resumed raw/extract artifact.
    #[arg(long)]
    output: Option<PathBuf>,

    /// Output encoding when the immutable job type permits it.
    #[arg(long, value_enum)]
    format: Option<ExtractionFormat>,

    /// Accept a validated partial result without a failure exit status.
    #[arg(long)]
    allow_partial: bool,

    /// Maximum seconds to wait for resumed work (5 through 900).
    #[arg(long, default_value_t = 300)]
    timeout: u64,

    #[command(flatten)]
    wake: WakeArgs,
}

#[derive(Debug, Args)]
#[command(
    long_about = "Request explicit cancellation of one durable direct job. Omit JOB_ID to inspect the required identifier. Timeouts, disconnections, Ctrl-C, and process exit do not imply cancellation.",
    after_help = "EXAMPLE:\n  healthmd cancel <JOB_UUID>\n\nCancellation becomes terminal only after acknowledgement from the authenticated mobile source.\nUse `healthmd status --job <JOB_UUID>` to inspect pending acknowledgement."
)]
struct JobArgs {
    /// Durable job UUID from an export receipt or status response.
    job_id: Option<Uuid>,

    #[command(flatten)]
    wake: WakeArgs,
}

#[derive(Debug, Args)]
#[command(
    after_help = "DISCOVERY:\n  Run `healthmd direct` without a subcommand to list pairing and trust-management\n  commands. Add --json for the machine contract. No listener or mutation is started."
)]
struct DirectArgs {
    #[command(subcommand)]
    command: Option<DirectCommand>,
}

#[derive(Debug, Subcommand)]
enum DirectCommand {
    /// Pair this CLI installation with an open iOS or Android app.
    Pair(PairArgs),
    /// List this installation and locally trusted devices without network access.
    Devices,
    /// Remove local trust for one mobile source. Omit `DEVICE_ID` to inspect requirements.
    Unpair {
        /// Trusted installation UUID from `healthmd direct devices`.
        device_id: Option<Uuid>,
    },
    /// Explicitly discard all local direct trust after confirmation.
    ResetTrust {
        #[arg(long)]
        confirm: bool,
    },
}

#[derive(Debug, Args)]
#[command(
    long_about = "Open a bounded Manual IP listener and pair this CLI installation with one foreground Health.md mobile app. Current iOS and Android releases share one high-entropy 20-digit QR/code; a six-digit Apple-v1 code remains only for legacy compatibility. Generated codes and health-free progress are printed to stderr; the final structured result follows the global human/JSON output selection.",
    after_help = "EXAMPLE:\n  healthmd direct pair\n\nKeep the command running. In Health.md on iOS or Android, open Direct CLI Access and\nscan the universal QR (or enter its 20-digit code manually). A six-digit legacy Apple\ncode remains available for older iOS releases. Pairing trust is stored only in the\nplatform-native credential service."
)]
struct PairArgs {
    /// Override the generated six-digit legacy Apple-v1 pairing code.
    #[arg(long)]
    pairing_code: Option<String>,

    /// Deprecated compatibility override for the shared twenty-digit pairing code.
    #[arg(long, conflicts_with = "shared_pairing_code")]
    android_pairing_code: Option<String>,

    /// Override the shared twenty-digit iOS/Android pairing code encoded in the QR.
    #[arg(long, conflicts_with = "android_pairing_code")]
    shared_pairing_code: Option<String>,

    /// Seconds to keep the pairing listener open (10 through 600).
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
    std::panic::set_hook(Box::new(|_| {
        eprintln!(
            "healthmd: internal error; no reliable result was produced. Preserve any durable job ID, run `healthmd status --job <JOB_UUID>` when applicable, and retry with the same installed version."
        );
    }));
    if let Some(exit_code) = healthmd_client::credentials::run_credential_helper_if_requested() {
        return ExitCode::from(exit_code);
    }
    let raw_arguments = std::env::args_os().collect::<Vec<_>>();
    if raw_arguments.len() == 1 {
        return if write_text_stdout(WELCOME_TEXT).is_ok() {
            ExitCode::SUCCESS
        } else {
            ExitCode::from(1)
        };
    }
    #[cfg(debug_assertions)]
    if raw_arguments.len() == 2
        && raw_arguments[1].as_os_str() == "__credential-supervision-probe-v1"
    {
        let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        else {
            return ExitCode::from(1);
        };
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
    let output_mode = requested_output_mode(&raw_arguments);
    let cli = match Cli::try_parse_from(raw_arguments.clone()) {
        Ok(cli) => cli,
        Err(error)
            if matches!(
                error.kind(),
                ErrorKind::DisplayHelp
                    | ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand
                    | ErrorKind::DisplayVersion
            ) =>
        {
            return if write_text_stdout(&error.to_string()).is_ok() {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            };
        }
        Err(error) => {
            let value = guidance::parser_error(&error, &raw_arguments[1..]);
            let _ = write_value_stdout(&value, output_mode);
            return ExitCode::from(2);
        }
    };
    let output_mode = output::OutputMode::resolve(cli.json, cli.human, io::stdout().is_terminal());
    let error_context = guidance::ErrorContext::from_cli(&cli);
    if let Some(value) = incomplete_command_guidance(&cli) {
        return if write_value_stdout(&value, output_mode).is_ok() {
            ExitCode::SUCCESS
        } else {
            ExitCode::from(1)
        };
    }
    if let Command::Mcp(McpArgs {
        command: Some(McpCommand::Schema(options)),
    }) = &cli.command
    {
        return match mcp_schema(options) {
            Ok(value) if write_value_stdout(&value, output_mode).is_ok() => ExitCode::SUCCESS,
            Ok(_) => ExitCode::from(1),
            Err(error) => {
                let value = guidance::command_error(&error, &error_context);
                let _ = write_value_stdout(&value, output_mode);
                ExitCode::from(1)
            }
        };
    }
    let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    else {
        let error = CommandError {
            backend: cli.backend.wire_name(),
            code: "runtime_unavailable",
            message: "The local asynchronous runtime could not start; no command was executed."
                .into(),
        };
        let value = guidance::command_error(&error, &error_context);
        let _ = write_value_stdout(&value, output_mode);
        return ExitCode::from(1);
    };
    let exit_code = runtime.block_on(async_main(cli, output_mode));
    runtime.shutdown_timeout(Duration::from_secs(2));
    exit_code
}

fn requested_output_mode(arguments: &[std::ffi::OsString]) -> output::OutputMode {
    output::OutputMode::resolve(
        arguments.iter().any(|argument| argument == "--json"),
        arguments.iter().any(|argument| argument == "--human"),
        io::stdout().is_terminal(),
    )
}

#[allow(clippy::too_many_lines)]
async fn async_main(cli: Cli, output_mode: output::OutputMode) -> ExitCode {
    let stdio_mcp = match &cli.command {
        Command::Mcp(McpArgs {
            command: Some(McpCommand::Serve(options)),
        }) => Some((options, false)),
        Command::Mcp(McpArgs {
            command: Some(McpCommand::ServeReadOnly(options)),
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
            wake_timeout_seconds: None,
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
        command: Some(McpCommand::ServeHttp(options)),
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
            wake_timeout_seconds: None,
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
    let error_context = guidance::ErrorContext::from_cli(&cli);
    match run(cli).await {
        Ok(success) => {
            if emit_output(success.output, output_mode).is_err() {
                let error = CommandError {
                    backend: "direct",
                    code: "output_write_failed",
                    message: "The command result could not be written to stdout or the requested output destination."
                        .into(),
                };
                let value = guidance::command_error(&error, &error_context);
                let _ = write_value_stdout(&value, output_mode);
                return ExitCode::from(1);
            }
            ExitCode::from(success.exit_code)
        }
        Err(error) => {
            let value = guidance::command_error(&error, &error_context);
            let _ = write_value_stdout(&value, output_mode);
            ExitCode::from(1)
        }
    }
}

async fn run(cli: Cli) -> Result<CommandSuccess, CommandError> {
    if let Some(value) = incomplete_command_guidance(&cli) {
        return Ok(CommandSuccess::json(value));
    }
    if let Command::Mcp(McpArgs {
        command: Some(McpCommand::Schema(options)),
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
            command: Some(DirectCommand::Devices),
        }) => direct_devices().await.map(CommandSuccess::json),
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::Pair(options)),
        }) => direct_pair(options, port).await.map(CommandSuccess::json),
        Command::Direct(DirectArgs {
            command:
                Some(DirectCommand::Unpair {
                    device_id: Some(device_id),
                }),
        }) => direct_unpair(device_id).await.map(CommandSuccess::json),
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::ResetTrust { confirm }),
        }) => direct_reset_trust(confirm).await.map(CommandSuccess::json),
        Command::Setup(SetupArgs {
            command: Some(SetupCommand::Codex(options)),
        }) if backend == Backend::Direct => setup_codex(options, device, port)
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

fn incomplete_command_guidance(cli: &Cli) -> Option<Value> {
    let backend = cli.backend.wire_name();
    match &cli.command {
        Command::Export(options) => {
            let missing_dates = !date_selection_is_present(&options.dates);
            let missing_mode = !options.raw && options.destination.is_none();
            (missing_dates || missing_mode)
                .then(|| guidance::export(backend, missing_dates, missing_mode))
        }
        Command::Extract(options) => {
            let missing_dates = !date_selection_is_present(&options.dates);
            let missing_scope = !extract_scope_is_present(&options.selection);
            (missing_dates || missing_scope)
                .then(|| guidance::extract(backend, missing_dates, missing_scope))
        }
        Command::Query(options) if options.operation.is_none() => {
            Some(guidance::query(backend, None))
        }
        Command::Query(options) if options.arguments.is_none() => {
            Some(guidance::query(backend, options.operation.as_deref()))
        }
        Command::Resume(options) if options.job_id.is_none() => Some(guidance::resume(backend)),
        Command::Cancel(options) if options.job_id.is_none() => Some(guidance::cancel(backend)),
        Command::Direct(DirectArgs { command: None }) => Some(guidance::group(backend, "direct")),
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::Unpair { device_id: None }),
        }) => Some(guidance::unpair(backend)),
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::ResetTrust { confirm: false }),
        }) => Some(guidance::reset_trust(backend)),
        Command::Mcp(McpArgs { command: None }) => Some(guidance::group(backend, "mcp")),
        Command::Setup(SetupArgs { command: None }) => Some(guidance::group(backend, "setup")),
        _ => None,
    }
}

const fn date_selection_is_present(options: &DateArgs) -> bool {
    options.yesterday
        || options.last.is_some()
        || options.from.is_some()
        || options.to.is_some()
        || options.all
}

fn extract_scope_is_present(options: &SelectionArgs) -> bool {
    options.all_metrics
        || !options.metrics.is_empty()
        || !options.categories.is_empty()
        || !options.objects.is_empty()
}

fn mcp_schema(options: &McpSchemaArgs) -> Result<Value, CommandError> {
    mcp::tool_catalog(options.tool.as_deref()).map_err(|_| CommandError {
        backend: "direct",
        code: "invalid_request",
        message: "The requested fixed MCP tool is unavailable. Run `healthmd mcp schema` to list every supported tool."
            .into(),
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
    validate_wake_timeout(options.wake)?;
    let Some(operation) = options.operation else {
        return Ok(guidance::query("direct", None));
    };
    let Some(argument_text) = options.arguments else {
        return Ok(guidance::query("direct", Some(&operation)));
    };
    let arguments: Value = serde_json::from_str(&argument_text)
        .map_err(|_| usage_error("--arguments must be one valid JSON object"))?;
    if !arguments.is_object() {
        return Err(usage_error("--arguments must be one valid JSON object"));
    }
    healthmd_operations::query_invocation(&operation, &arguments).map_err(usage_error)?;
    mcp::query(
        mcp::ServeOptions {
            device_id: device,
            port,
            timeout_seconds: options.timeout,
            wake_timeout_seconds: Some(options.wake.wake_timeout),
        },
        &operation,
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
        mcp::QueryError::Backend(error) if error.code == "direct_source_unavailable" => {
            direct_error("direct_wake_window_expired", error.message)
        }
        mcp::QueryError::Backend(error) if error.code == "healthmd_request_cancelled" => {
            direct_error("direct_wait_cancelled", error.message)
        }
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
    let legacy_apple_code = match options.pairing_code {
        Some(code) => code,
        None => generate_pairing_code(6)?,
    };
    let shared_code = match options.shared_pairing_code.or(options.android_pairing_code) {
        Some(code) => code,
        None => generate_pairing_code(20)?,
    };
    let legacy_apple_code = healthmd_client::handshake::normalize_pairing_code(&legacy_apple_code);
    let shared_code = healthmd_client::handshake::normalize_pairing_code(&shared_code);
    if legacy_apple_code.len() != 6 || shared_code.len() != 20 {
        return Err(usage_error(
            "shared pairing requires 20 ASCII digits; legacy Apple v1 requires 6 ASCII digits",
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
            &legacy_apple_code,
            &shared_code,
            port,
            Duration::from_secs(options.timeout),
            |bound_port| {
                eprintln!(
                    "Open Health.md → Direct CLI Access and scan the universal QR, or enter computer address {address_text}, port {bound_port}, and shared 20-digit code {shared_code}. Legacy iOS code: {legacy_apple_code}."
                );
                print_pairing_qr(&addresses, bound_port, &shared_code);
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
            shared_pairing_code: None,
            timeout: pairing_timeout,
        },
        port,
    )
    .await?;
    if result.pointer("/device/platform").and_then(Value::as_str) != Some("ios") {
        return Err(CommandError {
            backend: "direct",
            code: "direct_source_unsupported",
            message: "Codex health analysis requires a paired iPhone".into(),
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

fn validate_wake_timeout(options: WakeArgs) -> Result<(), CommandError> {
    if options.wake_timeout > MAXIMUM_WAKE_TIMEOUT_SECONDS {
        return Err(usage_error(
            "wake timeout must be between 0 and 3600 seconds",
        ));
    }
    Ok(())
}

async fn wait_for_wake_window(
    client: &DirectClient,
    device: Option<Uuid>,
    port: u16,
    options: WakeArgs,
) -> Result<(), CommandError> {
    validate_wake_timeout(options)?;
    client
        .wait_for_active_source(
            device,
            port,
            WakeWindow::from_seconds(options.wake_timeout),
            !options.no_wake,
            &tokio_util::sync::CancellationToken::new(),
            |progress: healthmd_client::direct::WakeProgress| eprintln!("{}", progress.message),
        )
        .await
        .map_err(|error| match error {
            ClientError::TimedOut => direct_error("direct_wake_window_expired", error),
            ClientError::WaitCancelled => direct_error("direct_wait_cancelled", error),
            other => map_direct_client_error(other),
        })
}

fn pinned_wake_device(requested: Option<Uuid>, pinned: Uuid) -> Result<Uuid, CommandError> {
    if let Some(requested) = requested {
        if requested != pinned {
            return Err(map_direct_client_error(ClientError::DeviceNotPaired(
                requested,
            )));
        }
    }
    Ok(pinned)
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
        "wake_window": WakeWindow::default().status_value(),
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
    validate_wake_timeout(options.wake)?;
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
    wait_for_wake_window(&client, device, port, options.wake).await?;
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
        wait_for_wake_window(&client, Some(source_id), port, options.wake).await?;
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
    wait_for_wake_window(&client, Some(source_id), port, options.wake).await?;
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
    wait_for_wake_window(&client, device, port, options.wake).await?;
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
    validate_wake_timeout(options.wake)?;
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
    wait_for_wake_window(&client, device, port, options.wake).await?;
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
    validate_wake_timeout(options.wake)?;
    let Some(job_id) = options.job_id else {
        return Ok(CommandSuccess::json(guidance::resume("direct")));
    };
    let client = DirectClient::open().map_err(client_error)?;
    match client.v2_job_record(job_id) {
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
            if record.state.resume_requires_source() {
                let wake_device =
                    pinned_wake_device(device, record.request.source_installation_id)?;
                wait_for_wake_window(&client, Some(wake_device), port, options.wake).await?;
            }
            let result = client
                .resume_android(job_id, device, port, Duration::from_secs(options.timeout))
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
    let record = client.job_record(job_id).map_err(map_direct_client_error)?;
    if record.state.resume_requires_source() {
        // An unbound job (crash window before its first connection) keeps the caller's device
        // selection; a bound job pins the wake preflight to its exact source.
        let wake_device = match record
            .peer_binding
            .as_ref()
            .map(|binding| binding.source_installation_id.0)
        {
            Some(pinned) => Some(pinned_wake_device(device, pinned)?),
            None => device,
        };
        wait_for_wake_window(&client, wake_device, port, options.wake).await?;
    }
    if record.request.response_mode == ResponseMode::WriteFiles {
        if options.format == Some(ExtractionFormat::Jsonl) {
            return Err(usage_error(
                "--format jsonl is available only when resuming canonical extract jobs",
            ));
        }
        let result = client
            .resume_files(job_id, device, port, Duration::from_secs(options.timeout))
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
        .resume_raw(job_id, device, port, Duration::from_secs(options.timeout))
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
    validate_wake_timeout(options.wake)?;
    let Some(job_id) = options.job_id else {
        return Ok(guidance::cancel("direct"));
    };
    let client = DirectClient::open().map_err(client_error)?;
    match client.v2_job_record(job_id) {
        Ok(record) => {
            let wake_device = pinned_wake_device(device, record.request.source_installation_id)?;
            let already_terminal = record.state.is_terminal();
            if !already_terminal {
                // Preserve the existing cross-process contract: persist the explicit cancellation
                // before opening a second listener, so an active export that owns the port can
                // deliver it.
                client
                    .request_android_job_cancellation(job_id, Some(wake_device))
                    .map_err(map_direct_client_error)?;
                if let Err(error) =
                    wait_for_wake_window(&client, Some(wake_device), port, options.wake).await
                {
                    // The durable marker is already persisted, so local wait expiry or
                    // interruption reports the truthful pending state, never terminal cancellation.
                    if matches!(
                        error.code,
                        "direct_wake_window_expired" | "direct_wait_cancelled"
                    ) {
                        return Err(map_direct_client_error(ClientError::CancellationPending(
                            job_id,
                        )));
                    }
                    return Err(error);
                }
            }
            client
                .cancel_android_job(job_id, Some(wake_device), port, Duration::from_secs(20))
                .await
                .map_err(map_direct_client_error)?;
            let current = client
                .v2_job_record(job_id)
                .map_err(map_direct_client_error)?;
            let status = serde_json::to_value(current.state).unwrap_or_else(|_| json!("unknown"));
            Ok(json!({
                "backend": "direct",
                "job_id": job_id.to_string().to_lowercase(),
                "status": status,
                "cancellation_applied": !already_terminal
            }))
        }
        Err(ClientError::JobNotFound) => {
            let record = client.job_record(job_id).map_err(map_direct_client_error)?;
            let delivery_device = if record.state.is_terminal() {
                device
            } else {
                let pinned_device = record
                    .peer_binding
                    .as_ref()
                    .map(|binding| binding.source_installation_id.0)
                    .ok_or_else(|| {
                        map_direct_client_error(ClientError::JobNotResumable(
                            job_id,
                            "unbound".into(),
                        ))
                    })?;
                let wake_device = pinned_wake_device(device, pinned_device)?;
                client
                    .request_job_cancellation(job_id, Some(wake_device))
                    .map_err(map_direct_client_error)?;
                if let Err(error) =
                    wait_for_wake_window(&client, Some(wake_device), port, options.wake).await
                {
                    // The durable marker is already persisted, so local wait expiry or
                    // interruption reports the truthful pending state, never terminal cancellation.
                    if matches!(
                        error.code,
                        "direct_wake_window_expired" | "direct_wait_cancelled"
                    ) {
                        return Err(map_direct_client_error(ClientError::CancellationPending(
                            job_id,
                        )));
                    }
                    return Err(error);
                }
                Some(wake_device)
            };
            client
                .cancel_job(job_id, delivery_device, port, Duration::from_secs(20))
                .await
                .map_err(map_direct_client_error)?;
            Ok(json!({
                "backend": "direct",
                "job_id": job_id.to_string().to_lowercase(),
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
    if let Some(object) = payload.as_object_mut() {
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

fn write_text_stdout(text: &str) -> io::Result<()> {
    let mut stdout = io::stdout().lock();
    stdout.write_all(text.as_bytes())?;
    stdout.flush()
}

fn write_json_stdout(value: &Value) -> io::Result<()> {
    let mut stdout = io::stdout().lock();
    serde_json::to_writer_pretty(&mut stdout, value).map_err(io::Error::other)?;
    stdout.write_all(b"\n")?;
    stdout.flush()
}

fn write_value_stdout(value: &Value, output_mode: output::OutputMode) -> io::Result<()> {
    match output_mode {
        output::OutputMode::Human => write_text_stdout(&output::render(
            value,
            output::color_enabled(io::stdout().is_terminal()),
        )),
        output::OutputMode::Json => write_json_stdout(value),
    }
}

fn emit_output(output: CommandOutput, output_mode: output::OutputMode) -> io::Result<()> {
    match output {
        CommandOutput::Json(value) => write_value_stdout(&value, output_mode),
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

fn print_pairing_qr(addresses: &[LocalAddress], port: u16, pairing_code: &str) {
    let Some(address) = preferred_pairing_address(addresses) else {
        return;
    };
    let link = pairing_link(&address.address, port, pairing_code);
    let Ok(code) = QrCode::new(link.as_bytes()) else {
        return;
    };
    let rendered = code.render::<unicode::Dense1x2>().quiet_zone(true).build();
    eprintln!(
        "In foreground Health.md on iOS or Android, open Direct CLI Access, tap Scan Pairing QR, and scan this image:\n{rendered}"
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
        "direct_wait_cancelled" => "The local direct mobile wait was cancelled.",
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
            command: Some(DirectCommand::Pair(_)),
        }) => "direct pair",
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::Devices),
        }) => "direct devices",
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::Unpair { .. }),
        }) => "direct unpair",
        Command::Direct(DirectArgs {
            command: Some(DirectCommand::ResetTrust { .. }),
        }) => "direct reset-trust",
        Command::Direct(DirectArgs { command: None }) => "direct",
        Command::Mcp(McpArgs {
            command: Some(McpCommand::Serve(_)),
        }) => "mcp serve",
        Command::Mcp(McpArgs {
            command: Some(McpCommand::ServeReadOnly(_)),
        }) => "mcp serve-read-only",
        #[cfg(feature = "streamable-http")]
        Command::Mcp(McpArgs {
            command: Some(McpCommand::ServeHttp(_)),
        }) => "mcp serve-http",
        Command::Mcp(McpArgs {
            command: Some(McpCommand::Schema(_)),
        }) => "mcp schema",
        Command::Mcp(McpArgs { command: None }) => "mcp",
        Command::Setup(SetupArgs {
            command: Some(SetupCommand::Codex(_)),
        }) => "setup codex",
        Command::Setup(SetupArgs { command: None }) => "setup",
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
    fn shared_pairing_link_is_exact_and_ephemeral() {
        assert_eq!(
            pairing_link("192.168.1.42", 17_647, "12345678901234567890"),
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=12345678901234567890"
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
    fn shared_and_legacy_pairing_code_overrides_parse() {
        let parsed = Cli::try_parse_from([
            "healthmd",
            "direct",
            "pair",
            "--pairing-code",
            "123456",
            "--shared-pairing-code",
            "12345678901234567890",
        ])
        .unwrap();
        let Command::Direct(DirectArgs {
            command: Some(DirectCommand::Pair(options)),
        }) = parsed.command
        else {
            panic!("expected direct pair command");
        };
        assert_eq!(options.pairing_code.as_deref(), Some("123456"));
        assert_eq!(
            options.shared_pairing_code.as_deref(),
            Some("12345678901234567890")
        );
        assert!(options.android_pairing_code.is_none());
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
    fn fresh_install_welcome_is_concise_and_actionable() {
        assert!(WELCOME_TEXT.starts_with("Health.md CLI "));
        assert!(WELCOME_TEXT.contains("healthmd direct pair"));
        assert!(WELCOME_TEXT.contains("healthmd setup codex"));
        assert!(WELCOME_TEXT.contains("healthmd status"));
        assert!(WELCOME_TEXT.contains("healthmd --help"));
        assert!(!WELCOME_TEXT.contains("Usage:"));
        assert!(!WELCOME_TEXT.contains("invalid_request"));
    }

    #[test]
    fn generic_help_routes_typed_queries_and_shows_the_sleep_shape() {
        use clap::CommandFactory as _;

        let mut command = Cli::command();
        let help = command.render_long_help().to_string();
        assert!(help.contains("healthmd_sleep_sessions"));
        assert!(help.contains("start_date"));
        assert!(help.contains("healthmd query healthmd_sleep_sessions"));
        assert!(help.contains("healthmd mcp schema"));
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
        assert_eq!(
            options.operation.as_deref(),
            Some("healthmd_sleep_sessions")
        );
        assert!(options.arguments.is_some());
        assert_eq!(options.timeout, 1_200);
        assert_eq!(options.wake.wake_timeout, DEFAULT_WAKE_TIMEOUT_SECONDS);

        let disabled = Cli::try_parse_from([
            "healthmd",
            "query",
            "healthmd_sleep_sessions",
            "--arguments",
            r#"{"dates":{"type":"all_available"}}"#,
            "--wake-timeout",
            "0",
        ])
        .unwrap();
        let Command::Query(options) = disabled.command else {
            panic!("expected query command");
        };
        assert_eq!(options.wake.wake_timeout, 0);
    }

    #[test]
    fn durable_wake_uses_the_job_pinned_device() {
        let pinned = Uuid::new_v4();
        assert_eq!(pinned_wake_device(None, pinned).unwrap(), pinned);
        assert_eq!(pinned_wake_device(Some(pinned), pinned).unwrap(), pinned);

        let other = Uuid::new_v4();
        let error = pinned_wake_device(Some(other), pinned).unwrap_err();
        assert_eq!(error.code, "direct_device_not_paired");
    }

    #[test]
    fn incomplete_commands_enter_non_network_guidance_mode() {
        let export = Cli::try_parse_from(["healthmd", "export"]).unwrap();
        let export = incomplete_command_guidance(&export).expect("export should guide");
        assert_eq!(export["status"], "guidance");
        assert_eq!(export["request_sent"], false);
        assert_eq!(export["missing"].as_array().map(Vec::len), Some(2));

        let query = Cli::try_parse_from(["healthmd", "query", "healthmd_sleep_sessions"]).unwrap();
        let query = incomplete_command_guidance(&query).expect("query should expose schema");
        assert_eq!(
            query.pointer("/input_schema/required/0"),
            Some(&json!("dates"))
        );

        let resume = Cli::try_parse_from(["healthmd", "resume"]).unwrap();
        let resume = incomplete_command_guidance(&resume).expect("resume should guide");
        assert_eq!(
            resume.pointer("/required/0/argument"),
            Some(&json!("JOB_ID"))
        );
    }

    #[test]
    fn complete_requests_do_not_enter_guidance_mode() {
        let export = Cli::try_parse_from(["healthmd", "export", "--yesterday", "--raw"]).unwrap();
        assert!(incomplete_command_guidance(&export).is_none());

        let query = Cli::try_parse_from([
            "healthmd",
            "query",
            "healthmd_sleep_sessions",
            "--arguments",
            r#"{"dates":{"type":"all_available"}}"#,
        ])
        .unwrap();
        assert!(incomplete_command_guidance(&query).is_none());
    }

    #[test]
    fn destructive_reset_requires_discovery_before_confirmation() {
        let inspect = Cli::try_parse_from(["healthmd", "direct", "reset-trust"]).unwrap();
        let guidance = incomplete_command_guidance(&inspect).expect("reset should guide");
        assert_eq!(guidance["request_sent"], false);
        assert_eq!(
            guidance.pointer("/required/0/argument"),
            Some(&json!("--confirm"))
        );

        let confirmed =
            Cli::try_parse_from(["healthmd", "direct", "reset-trust", "--confirm"]).unwrap();
        assert!(incomplete_command_guidance(&confirmed).is_none());
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
            command: Some(McpCommand::Serve(options)),
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
            command: Some(McpCommand::ServeReadOnly(options)),
        }) = read_only.command
        else {
            panic!("expected read-only MCP serve command");
        };
        assert_eq!(options.timeout_seconds, 600);

        let schema =
            Cli::try_parse_from(["healthmd", "mcp", "schema", "healthmd_sleep_sessions"]).unwrap();
        let Command::Mcp(McpArgs {
            command: Some(McpCommand::Schema(options)),
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
            command: Some(SetupCommand::Codex(options)),
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
            command: Some(McpCommand::ServeHttp(options)),
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
            command: Some(McpCommand::ServeHttp(options)),
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
