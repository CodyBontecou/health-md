use std::{
    env,
    ffi::OsStr,
    fmt, fs,
    io::{Read as _, Write as _},
    path::{Path, PathBuf},
};

use directories::BaseDirs;
use fs2::FileExt as _;
use tempfile::NamedTempFile;
use toml_edit::{Array, DocumentMut, Item, Table, value};
use uuid::Uuid;

const MAXIMUM_CODEX_CONFIG_BYTES: usize = 2 * 1_024 * 1_024;
const DEFAULT_DIRECT_PORT: u16 = 17_647;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CodexSetupReceipt {
    pub config_path: PathBuf,
    pub command: PathBuf,
    pub args: Vec<String>,
    pub changed: bool,
}

#[derive(Debug)]
pub enum OnboardingError {
    HomeUnavailable,
    InvalidExecutable,
    InvalidConfig,
    ConfigTooLarge,
    ConfigChanged,
    Io,
}

impl fmt::Display for OnboardingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::HomeUnavailable => "the Codex configuration directory could not be resolved",
            Self::InvalidExecutable => "the healthmd executable path is invalid",
            Self::InvalidConfig => "the existing Codex configuration is not valid TOML",
            Self::ConfigTooLarge => "the existing Codex configuration exceeds the safety limit",
            Self::ConfigChanged => {
                "the Codex configuration changed during setup; no update was written, so rerun setup"
            }
            Self::Io => "the Codex configuration could not be updated safely",
        })
    }
}

impl std::error::Error for OnboardingError {}

/// Resolve the Codex configuration using `CODEX_HOME` or the current user's home directory.
///
/// # Errors
///
/// Returns [`OnboardingError::HomeUnavailable`] when no user configuration directory exists.
pub fn default_codex_config_path() -> Result<PathBuf, OnboardingError> {
    if let Some(home) = env::var_os("CODEX_HOME").filter(|value| !value.is_empty()) {
        return Ok(PathBuf::from(home).join("config.toml"));
    }
    BaseDirs::new()
        .map(|directories| directories.home_dir().join(".codex/config.toml"))
        .ok_or(OnboardingError::HomeUnavailable)
}

/// Resolve the stable path used to invoke the running executable without collapsing a package
/// manager's symlink into a removable versioned target.
///
/// # Errors
///
/// Returns [`OnboardingError::InvalidExecutable`] when the running executable cannot be resolved.
pub fn current_invocation_executable() -> Result<PathBuf, OnboardingError> {
    let current = env::current_exe().map_err(|_| OnboardingError::InvalidExecutable)?;
    let argument = env::args_os().next();
    let current_directory = env::current_dir().map_err(|_| OnboardingError::InvalidExecutable)?;
    resolve_invocation_executable(
        argument.as_deref(),
        &current,
        env::var_os("PATH").as_deref(),
        &current_directory,
    )
}

fn resolve_invocation_executable(
    argument: Option<&OsStr>,
    current_executable: &Path,
    path_environment: Option<&OsStr>,
    current_directory: &Path,
) -> Result<PathBuf, OnboardingError> {
    let current = current_executable
        .canonicalize()
        .map_err(|_| OnboardingError::InvalidExecutable)?;
    let mut candidates = Vec::new();
    if let Some(argument) = argument {
        let argument = Path::new(argument);
        if argument.is_absolute() {
            candidates.push(argument.to_owned());
        } else if argument.components().count() > 1 {
            candidates.push(current_directory.join(argument));
        } else if let Some(path_environment) = path_environment {
            for directory in env::split_paths(path_environment) {
                let directory = if directory.is_absolute() {
                    directory
                } else {
                    current_directory.join(directory)
                };
                candidates.push(directory.join(argument));
                #[cfg(windows)]
                if argument.extension().is_none() {
                    candidates.push(directory.join(argument).with_extension("exe"));
                }
            }
        }
    }
    for candidate in candidates {
        if candidate
            .canonicalize()
            .is_ok_and(|resolved| resolved == current)
        {
            return Ok(candidate);
        }
    }
    Ok(current)
}

/// Configure Codex to launch the same `healthmd` executable in MCP serve mode.
///
/// # Errors
///
/// Returns an [`OnboardingError`] when the executable or existing configuration is invalid, the
/// bounded configuration cannot be read, or the atomic update cannot be committed.
pub fn configure_codex(
    executable: &Path,
    device_id: Option<Uuid>,
    port: u16,
) -> Result<CodexSetupReceipt, OnboardingError> {
    configure_codex_at(&default_codex_config_path()?, executable, device_id, port)
}

/// Configure an explicit Codex configuration path. This is primarily useful for installers and
/// isolated verification; ordinary callers should use [`configure_codex`].
///
/// # Errors
///
/// Returns an [`OnboardingError`] under the same conditions as [`configure_codex`].
pub fn configure_codex_at(
    requested_config_path: &Path,
    executable: &Path,
    device_id: Option<Uuid>,
    port: u16,
) -> Result<CodexSetupReceipt, OnboardingError> {
    if !executable.is_absolute() {
        return Err(OnboardingError::InvalidExecutable);
    }
    let resolved_executable = executable
        .canonicalize()
        .map_err(|_| OnboardingError::InvalidExecutable)?;
    if !resolved_executable.is_file() {
        return Err(OnboardingError::InvalidExecutable);
    }
    let command = executable
        .to_str()
        .ok_or(OnboardingError::InvalidExecutable)?
        .to_owned();
    let args = mcp_arguments(device_id, port);

    let config_path = resolve_config_path(requested_config_path)?;
    let parent = config_path
        .parent()
        .filter(|value| !value.as_os_str().is_empty())
        .ok_or(OnboardingError::Io)?;
    fs::create_dir_all(parent).map_err(|_| OnboardingError::Io)?;

    let lock_path = parent.join(".healthmd-codex-config.lock");
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(lock_path)
        .map_err(|_| OnboardingError::Io)?;
    set_owner_only_permissions(&lock).map_err(|_| OnboardingError::Io)?;
    lock.lock_exclusive().map_err(|_| OnboardingError::Io)?;

    let result = update_locked_config(&config_path, parent, &command, &args);
    let _ = fs2::FileExt::unlock(&lock);
    result.map(|changed| CodexSetupReceipt {
        config_path,
        command: executable.to_owned(),
        args,
        changed,
    })
}

fn resolve_config_path(path: &Path) -> Result<PathBuf, OnboardingError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            path.canonicalize().map_err(|_| OnboardingError::Io)
        }
        Ok(metadata) if metadata.is_file() => Ok(path.to_owned()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(path.to_owned()),
        Ok(_) | Err(_) => Err(OnboardingError::Io),
    }
}

fn update_locked_config(
    config_path: &Path,
    parent: &Path,
    command: &str,
    args: &[String],
) -> Result<bool, OnboardingError> {
    let original = read_bounded(config_path)?;
    let mut document = if original.trim().is_empty() {
        DocumentMut::new()
    } else {
        original
            .parse::<DocumentMut>()
            .map_err(|_| OnboardingError::InvalidConfig)?
    };

    let servers = ensure_table(document.as_table_mut(), "mcp_servers")?;
    let healthmd = ensure_table(servers, "healthmd")?;
    healthmd["command"] = value(command);
    healthmd["args"] = value(string_array(args));
    healthmd["enabled"] = value(true);
    healthmd["startup_timeout_sec"] = value(10);
    healthmd["tool_timeout_sec"] = value(1_200);
    healthmd["default_tools_approval_mode"] = value("prompt");

    let tools = ensure_table(healthmd, "tools")?;
    for tool in [
        "healthmd_export_files",
        "healthmd_export_job_resume",
        "healthmd_export_job_cancel",
    ] {
        ensure_table(tools, tool)?["approval_mode"] = value("prompt");
    }

    let updated = document.to_string();
    if updated == original {
        return Ok(false);
    }
    write_atomic(config_path, parent, updated.as_bytes(), &original)?;
    Ok(true)
}

fn read_bounded(path: &Path) -> Result<String, OnboardingError> {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(String::new()),
        Err(_) => return Err(OnboardingError::Io),
    };
    if file.metadata().map_err(|_| OnboardingError::Io)?.len()
        > u64::try_from(MAXIMUM_CODEX_CONFIG_BYTES).map_err(|_| OnboardingError::ConfigTooLarge)?
    {
        return Err(OnboardingError::ConfigTooLarge);
    }
    let mut bytes = Vec::new();
    file.take(
        u64::try_from(MAXIMUM_CODEX_CONFIG_BYTES + 1)
            .map_err(|_| OnboardingError::ConfigTooLarge)?,
    )
    .read_to_end(&mut bytes)
    .map_err(|_| OnboardingError::Io)?;
    if bytes.len() > MAXIMUM_CODEX_CONFIG_BYTES {
        return Err(OnboardingError::ConfigTooLarge);
    }
    String::from_utf8(bytes).map_err(|_| OnboardingError::InvalidConfig)
}

fn ensure_table<'a>(table: &'a mut Table, key: &str) -> Result<&'a mut Table, OnboardingError> {
    if !table.contains_key(key) {
        table.insert(key, Item::Table(Table::new()));
    }
    let item = table.get_mut(key).ok_or(OnboardingError::InvalidConfig)?;
    if item.as_table_mut().is_none() {
        let owned = std::mem::replace(item, Item::None);
        *item = Item::Table(
            owned
                .into_table()
                .map_err(|_| OnboardingError::InvalidConfig)?,
        );
    }
    item.as_table_mut().ok_or(OnboardingError::InvalidConfig)
}

fn string_array(values: &[String]) -> Array {
    let mut result = Array::new();
    for value in values {
        result.push(value.as_str());
    }
    result
}

fn mcp_arguments(device_id: Option<Uuid>, port: u16) -> Vec<String> {
    let mut arguments = Vec::new();
    if let Some(device_id) = device_id {
        arguments.extend(["--device".into(), device_id.to_string().to_lowercase()]);
    }
    if port != DEFAULT_DIRECT_PORT {
        arguments.extend(["--port".into(), port.to_string()]);
    }
    arguments.extend(["mcp".into(), "serve".into()]);
    arguments
}

fn write_atomic(
    path: &Path,
    parent: &Path,
    bytes: &[u8],
    expected_original: &str,
) -> Result<(), OnboardingError> {
    let mut temporary = NamedTempFile::new_in(parent).map_err(|_| OnboardingError::Io)?;
    set_owner_only_permissions(temporary.as_file()).map_err(|_| OnboardingError::Io)?;
    temporary
        .write_all(bytes)
        .and_then(|()| temporary.as_file().sync_all())
        .map_err(|_| OnboardingError::Io)?;
    if read_bounded(path)? != expected_original {
        return Err(OnboardingError::ConfigChanged);
    }
    temporary.persist(path).map_err(|_| OnboardingError::Io)?;
    sync_directory(parent).map_err(|_| OnboardingError::Io)
}

#[cfg(unix)]
fn set_owner_only_permissions(file: &fs::File) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt as _;
    file.set_permissions(fs::Permissions::from_mode(0o600))
}

// Keep the fallible signature aligned with the Unix implementation so the atomic-write
// transaction has one cross-platform control flow.
#[cfg(not(unix))]
#[allow(clippy::unnecessary_wraps)]
fn set_owner_only_permissions(_file: &fs::File) -> std::io::Result<()> {
    Ok(())
}

#[cfg(unix)]
fn sync_directory(path: &Path) -> std::io::Result<()> {
    fs::File::open(path)?.sync_all()
}

// Windows has no portable directory fsync equivalent, but callers still require the same
// fallible transaction boundary used by Unix.
#[cfg(not(unix))]
#[allow(clippy::unnecessary_wraps)]
fn sync_directory(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn codex_configuration_is_idempotent_and_preserves_unrelated_values() {
        let temporary = TempDir::new().unwrap();
        let executable = temporary.path().join("healthmd");
        fs::write(&executable, b"test").unwrap();
        let config = temporary.path().join("codex/config.toml");
        fs::create_dir_all(config.parent().unwrap()).unwrap();
        fs::write(
            &config,
            "model = \"gpt-test\"\n[mcp_servers.other]\ncommand = \"other\"\n",
        )
        .unwrap();

        let first = configure_codex_at(&config, &executable, None, DEFAULT_DIRECT_PORT).unwrap();
        assert!(first.changed);
        let first_bytes = fs::read_to_string(&config).unwrap();
        assert!(first_bytes.contains("model = \"gpt-test\""));
        assert!(first_bytes.contains("[mcp_servers.other]"));
        assert!(first_bytes.contains("[mcp_servers.healthmd]"));
        assert!(first_bytes.contains("args = [\"mcp\", \"serve\"]"));
        assert!(first_bytes.contains("default_tools_approval_mode = \"prompt\""));

        let second = configure_codex_at(&config, &executable, None, DEFAULT_DIRECT_PORT).unwrap();
        assert!(!second.changed);
        assert_eq!(first_bytes, fs::read_to_string(&config).unwrap());
    }

    #[test]
    fn codex_configuration_pins_explicit_device_and_nondefault_port() {
        let temporary = TempDir::new().unwrap();
        let executable = temporary.path().join("healthmd");
        fs::write(&executable, b"test").unwrap();
        let config = temporary.path().join("config.toml");
        let device_id = Uuid::parse_str("01234567-89ab-4cde-8fab-0123456789ab").unwrap();

        let receipt = configure_codex_at(&config, &executable, Some(device_id), 18_647).unwrap();
        assert_eq!(
            receipt.args,
            [
                "--device",
                "01234567-89ab-4cde-8fab-0123456789ab",
                "--port",
                "18647",
                "mcp",
                "serve"
            ]
        );
    }

    #[test]
    fn inline_codex_tables_are_preserved_and_extended() {
        let temporary = TempDir::new().unwrap();
        let executable = temporary.path().join("healthmd");
        fs::write(&executable, b"test").unwrap();
        let config = temporary.path().join("config.toml");
        fs::write(
            &config,
            "mcp_servers = { other = { command = \"other\", args = [] } }\n",
        )
        .unwrap();

        configure_codex_at(&config, &executable, None, DEFAULT_DIRECT_PORT).unwrap();
        let document = fs::read_to_string(&config)
            .unwrap()
            .parse::<DocumentMut>()
            .unwrap();
        assert_eq!(
            document["mcp_servers"]["other"]["command"].as_str(),
            Some("other")
        );
        assert_eq!(
            document["mcp_servers"]["healthmd"]["command"].as_str(),
            executable.to_str()
        );
    }

    #[test]
    fn concurrent_config_change_fails_without_overwrite() {
        let temporary = TempDir::new().unwrap();
        let config = temporary.path().join("config.toml");
        fs::write(&config, "concurrent = true\n").unwrap();
        let error = write_atomic(
            &config,
            temporary.path(),
            b"healthmd = true\n",
            "original = true\n",
        )
        .unwrap_err();
        assert!(matches!(error, OnboardingError::ConfigChanged));
        assert_eq!(fs::read_to_string(config).unwrap(), "concurrent = true\n");
    }

    #[cfg(unix)]
    #[test]
    fn stable_invocation_symlink_is_not_collapsed_to_versioned_target() {
        use std::os::unix::fs::symlink;

        let temporary = TempDir::new().unwrap();
        let versioned = temporary.path().join("Cellar/healthmd/1.0/bin/healthmd");
        fs::create_dir_all(versioned.parent().unwrap()).unwrap();
        fs::write(&versioned, b"test").unwrap();
        let stable = temporary.path().join("bin/healthmd");
        fs::create_dir_all(stable.parent().unwrap()).unwrap();
        symlink(&versioned, &stable).unwrap();

        assert_eq!(
            resolve_invocation_executable(
                Some(stable.as_os_str()),
                &versioned,
                None,
                temporary.path(),
            )
            .unwrap(),
            stable
        );
    }

    #[test]
    fn malformed_or_oversized_config_fails_without_replacement() {
        let temporary = TempDir::new().unwrap();
        let executable = temporary.path().join("healthmd");
        fs::write(&executable, b"test").unwrap();
        let config = temporary.path().join("config.toml");
        fs::write(&config, b"[not valid").unwrap();
        assert!(matches!(
            configure_codex_at(&config, &executable, None, DEFAULT_DIRECT_PORT),
            Err(OnboardingError::InvalidConfig)
        ));
        assert_eq!(fs::read(&config).unwrap(), b"[not valid");

        fs::write(&config, vec![b'x'; MAXIMUM_CODEX_CONFIG_BYTES + 1]).unwrap();
        assert!(matches!(
            configure_codex_at(&config, &executable, None, DEFAULT_DIRECT_PORT),
            Err(OnboardingError::ConfigTooLarge)
        ));
    }
}
