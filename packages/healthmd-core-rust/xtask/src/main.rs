#![forbid(unsafe_code)]

use std::env;
use std::ffi::{OsStr, OsString};
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus};

#[derive(Clone, Copy)]
enum Language {
    Swift,
    Kotlin,
}

impl Language {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Swift => "swift",
            Self::Kotlin => "kotlin",
        }
    }
}

fn main() -> io::Result<()> {
    let arguments = env::args_os().skip(1).collect::<Vec<_>>();
    if arguments.len() < 2 || arguments.len() > 3 || arguments[0] != "bindings" {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "usage: cargo run -p xtask -- bindings <swift|kotlin> [out-dir]",
        ));
    }

    let language = match arguments[1].to_str() {
        Some("swift") => Language::Swift,
        Some("kotlin") => Language::Kotlin,
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "binding language must be swift or kotlin",
            ));
        }
    };

    let workspace_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .ok_or_else(|| io::Error::other("xtask must be inside its workspace"))?
        .to_owned();
    let out_dir = arguments.get(2).map_or_else(
        || {
            workspace_root
                .join("target/generated-bindings")
                .join(language.as_str())
        },
        PathBuf::from,
    );

    generate_bindings(&workspace_root, language, &out_dir)
}

fn generate_bindings(workspace_root: &Path, language: Language, out_dir: &Path) -> io::Result<()> {
    let cargo = env::var_os("CARGO").unwrap_or_else(|| OsString::from("cargo"));
    ensure_success(
        Command::new(&cargo)
            .current_dir(workspace_root)
            .args([
                OsStr::new("build"),
                OsStr::new("--locked"),
                OsStr::new("-p"),
                OsStr::new("healthmd-core-uniffi"),
            ])
            .status()?,
        "building the host UniFFI library",
    )?;

    let library_path = host_library_path(workspace_root)?;
    if !library_path.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!(
                "host UniFFI library was not produced at {}",
                library_path.display()
            ),
        ));
    }
    std::fs::create_dir_all(out_dir)?;

    ensure_success(
        Command::new(cargo)
            .current_dir(workspace_root)
            .args([
                OsStr::new("run"),
                OsStr::new("--locked"),
                OsStr::new("--quiet"),
                OsStr::new("-p"),
                OsStr::new("xtask"),
                OsStr::new("--bin"),
                OsStr::new("uniffi-bindgen"),
                OsStr::new("--"),
                OsStr::new("generate"),
                OsStr::new("--library"),
                OsStr::new("--crate"),
                OsStr::new("healthmd_core_uniffi"),
                OsStr::new("--language"),
                OsStr::new(language.as_str()),
                OsStr::new("--out-dir"),
                out_dir.as_os_str(),
                OsStr::new("--no-format"),
                library_path.as_os_str(),
            ])
            .status()?,
        "generating UniFFI bindings",
    )?;

    println!(
        "generated {} bindings in {}",
        language.as_str(),
        out_dir.display()
    );
    Ok(())
}

fn host_library_path(workspace_root: &Path) -> io::Result<PathBuf> {
    let target_dir = env::var_os("CARGO_TARGET_DIR").map_or_else(
        || workspace_root.join("target"),
        |configured| {
            let configured = PathBuf::from(configured);
            if configured.is_absolute() {
                configured
            } else {
                workspace_root.join(configured)
            }
        },
    );
    let filename = match env::consts::OS {
        "macos" => "libhealthmd_core_uniffi.dylib",
        "linux" => "libhealthmd_core_uniffi.so",
        "windows" => "healthmd_core_uniffi.dll",
        platform => {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                format!("host binding generation is unsupported on {platform}"),
            ));
        }
    };
    Ok(target_dir.join("debug").join(filename))
}

fn ensure_success(status: ExitStatus, action: &str) -> io::Result<()> {
    if status.success() {
        Ok(())
    } else {
        Err(io::Error::other(format!(
            "{action} failed with status {status}"
        )))
    }
}
