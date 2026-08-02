#![forbid(unsafe_code)]

#[cfg(windows)]
use std::time::Duration;
#[cfg(not(windows))]
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
    std::panic::set_hook(Box::new(|_| eprintln!("healthmd-mcp: internal error")));
    // Unix replaces this process with the sibling `healthmd`, so the main executable remains the
    // only native-credential principal. Windows has no exec(2): serve in-process there and supervise
    // a same-healthmd-mcp helper instead of creating a healthmd child whose immediate parent would
    // fail the helper's same-file authentication.
    #[cfg(windows)]
    if let Some(exit_code) = healthmd_client::credentials::run_credential_helper_if_requested() {
        std::process::exit(i32::from(exit_code));
    }

    #[cfg(all(windows, debug_assertions))]
    {
        let mut arguments = std::env::args_os();
        let _executable = arguments.next();
        if arguments.next().as_deref() == Some("__credential-supervision-probe-v1".as_ref())
            && arguments.next().is_none()
        {
            let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
            else {
                std::process::exit(1);
            };
            let succeeded = runtime
                .block_on(healthmd_client::credentials::OsCredentialStore::supervision_probe())
                .is_ok();
            runtime.shutdown_timeout(Duration::from_secs(2));
            std::process::exit(i32::from(!succeeded));
        }
    }

    let arguments = Arguments::parse();

    #[cfg(windows)]
    {
        let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        else {
            eprintln!("healthmd-mcp: the asynchronous runtime is unavailable");
            std::process::exit(1);
        };
        let succeeded = runtime
            .block_on(healthmd_cli::mcp::serve(arguments.serve))
            .is_ok();
        runtime.shutdown_timeout(Duration::from_secs(2));
        if !succeeded {
            eprintln!("healthmd-mcp: direct client initialization failed");
            std::process::exit(1);
        }
    }

    #[cfg(not(windows))]
    delegate_to_sibling(&arguments);
}

#[cfg(not(windows))]
fn delegate_to_sibling(arguments: &Arguments) {
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

#[cfg(not(windows))]
fn sibling_healthmd() -> Option<PathBuf> {
    let executable = std::env::current_exe().ok()?;
    let directory = executable.parent()?;
    let candidate = directory.join("healthmd");
    candidate.is_file().then_some(candidate)
}
