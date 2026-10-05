//! Handle-relative, read-only root inspection and private issuer-file hardening.
use std::{
    io::{Read as _, Write as _},
    path::{Component, Path},
};

use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _};
use cap_std::{
    ambient_authority,
    fs::{Dir, Metadata, OpenOptions},
};
use healthmd_protocol::v4::{self, Digest};
use serde::{Deserialize, Serialize};

use crate::ClientError;

#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RootIdentity {
    device: u64,
    inode: u64,
}

pub(crate) fn unavailable<T>(_: T) -> ClientError {
    ClientError::AgentAuthorityUnavailable
}

pub(crate) fn inspect_root(path: &Path) -> Result<(Dir, RootIdentity), ClientError> {
    if !path.is_absolute() {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    let mut anchor = std::path::PathBuf::new();
    let mut dir = None;
    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir if dir.is_none() => {
                anchor.push(component.as_os_str());
                if matches!(component, Component::RootDir) {
                    dir = Some(
                        Dir::open_ambient_dir(&anchor, ambient_authority()).map_err(unavailable)?,
                    );
                }
            }
            Component::Normal(segment) => {
                let parent = dir.take().ok_or(ClientError::AgentAuthorityUnavailable)?;
                dir = Some(parent.open_dir_nofollow(segment).map_err(unavailable)?);
            }
            _ => return Err(ClientError::AgentAuthorityUnavailable),
        }
    }
    let dir = dir.ok_or(ClientError::AgentAuthorityUnavailable)?;
    let identity = identity(&dir.dir_metadata().map_err(unavailable)?)?;
    Ok((dir, identity))
}

// Result is required by the deliberately unavailable Windows implementation.
#[allow(clippy::unnecessary_wraps)]
fn identity(metadata: &Metadata) -> Result<RootIdentity, ClientError> {
    #[cfg(unix)]
    {
        use cap_std::fs::MetadataExt as _;
        Ok(RootIdentity {
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }
    #[cfg(windows)]
    {
        // Native ACL/owner verification is required before enabling this private store on Windows.
        let _ = metadata;
        Err(ClientError::AgentAuthorityUnavailable)
    }
}

pub(crate) fn identity_digest(identity: &RootIdentity) -> Result<Digest, ClientError> {
    v4::document_digest(identity).map_err(Into::into)
}

#[cfg(unix)]
fn owner() -> Result<u32, ClientError> {
    let pid = sysinfo::get_current_pid().map_err(unavailable)?;
    let mut system = sysinfo::System::new();
    system.refresh_processes_specifics(
        sysinfo::ProcessesToUpdate::Some(&[pid]),
        true,
        sysinfo::ProcessRefreshKind::nothing().with_user(sysinfo::UpdateKind::Always),
    );
    system
        .process(pid)
        .and_then(|p| p.effective_user_id())
        .map(|uid| **uid)
        .ok_or(ClientError::AgentAuthorityUnavailable)
}

// Keep explicit Unix group/other mode bits auditable instead of a trailing-zero trick.
#[allow(clippy::verbose_bit_mask)]
pub(crate) fn private_directory(dir: &Dir) -> Result<(), ClientError> {
    let metadata = dir.dir_metadata().map_err(unavailable)?;
    #[cfg(unix)]
    {
        use cap_std::fs::MetadataExt as _;
        if metadata.uid() == owner()? && metadata.mode() & 0o077 == 0 && metadata.is_dir() {
            return Ok(());
        }
    }
    let _ = metadata;
    Err(ClientError::AgentAuthorityUnavailable)
}

pub(crate) fn open_private(
    dir: &Dir,
    name: &str,
    write: bool,
    create_new: bool,
) -> Result<std::fs::File, ClientError> {
    let mut options = OpenOptions::new();
    options
        .read(true)
        .write(write)
        .create_new(create_new)
        .follow(FollowSymlinks::No);
    #[cfg(unix)]
    {
        use cap_std::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    let file = dir.open_with(name, &options).map_err(unavailable)?;
    let metadata = file.metadata().map_err(unavailable)?;
    #[cfg(unix)]
    {
        use cap_std::fs::MetadataExt as _;
        if !metadata.is_file()
            || metadata.nlink() != 1
            || metadata.uid() != owner()?
            || metadata.mode() & 0o077 != 0
        {
            return Err(ClientError::AgentAuthorityUnavailable);
        }
    }
    Ok(file.into_std())
}

pub(crate) fn read_private(dir: &Dir, name: &str, bound: usize) -> Result<Vec<u8>, ClientError> {
    let mut file = open_private(dir, name, false, false)?;
    if file.metadata().map_err(unavailable)?.len() > bound as u64 {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    let mut bytes = Vec::new();
    (&mut file)
        .take(bound as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(unavailable)?;
    if bytes.len() > bound {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(bytes)
}

pub(crate) fn publish(dir: &Dir, name: &str, bytes: &[u8], new: bool) -> Result<(), ClientError> {
    let temporary = format!(".issuer-{}.tmp", uuid::Uuid::new_v4());
    let result = (|| {
        let mut file = open_private(dir, &temporary, true, true)?;
        file.write_all(bytes).map_err(unavailable)?;
        file.sync_all().map_err(unavailable)?;
        if new {
            dir.hard_link(&temporary, dir, name).map_err(unavailable)?;
            dir.remove_file(&temporary).map_err(unavailable)?;
        } else {
            dir.rename(&temporary, dir, name).map_err(unavailable)?;
        }
        dir.try_clone()
            .map_err(unavailable)?
            .into_std_file()
            .sync_all()
            .map_err(unavailable)
    })();
    if result.is_err() {
        let _ = dir.remove_file(&temporary);
    }
    result
}
