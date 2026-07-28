#![forbid(unsafe_code)]

use std::{path::PathBuf, process::Command};

use clap::Parser;
use healthmd_cli::mcp::ServeOptions;

#[derive(Debug, Parser)]
#[command(
    name = "healthmd-mcp",
    version,
    about = "Compatibility launcher for `healthmd mcp serve`"
)]
struct Arguments {
    #[command(flatten)]
    serve: ServeOptions,
}

fn main() {
    let arguments = Arguments::parse();
    let Some(healthmd) = sibling_healthmd() else {
        eprintln!("healthmd-mcp: the sibling healthmd executable is missing");
        std::process::exit(1);
    };
    let mut command = Command::new(healthmd);
    if let Some(device_id) = arguments.serve.device_id {
        command.args(["--device", &device_id.to_string()]);
    }
    command.args(["--port", &arguments.serve.port.to_string(), "mcp", "serve"]);
    command.args([
        "--timeout-seconds",
        &arguments.serve.timeout_seconds.to_string(),
    ]);

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt as _;
        let error = command.exec();
        eprintln!("healthmd-mcp: failed to launch healthmd: {error}");
        std::process::exit(1);
    }
    #[cfg(not(unix))]
    {
        match command.status() {
            Ok(status) => std::process::exit(status.code().unwrap_or(1)),
            Err(error) => {
                eprintln!("healthmd-mcp: failed to launch healthmd: {error}");
                std::process::exit(1);
            }
        }
    }
}

fn sibling_healthmd() -> Option<PathBuf> {
    let executable = std::env::current_exe().ok()?;
    let directory = executable.parent()?;
    #[cfg(windows)]
    let candidate = directory.join("healthmd.exe");
    #[cfg(not(windows))]
    let candidate = directory.join("healthmd");
    candidate.is_file().then_some(candidate)
}
