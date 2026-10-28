//! Handle-relative, read-only root inspection and private issuer-file hardening.
use std::{
    io::{Read as _, Seek as _, Write as _},
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

pub(crate) fn require_directory_identity(
    dir: &Dir,
    expected: &RootIdentity,
) -> Result<(), ClientError> {
    if identity(&dir.dir_metadata().map_err(unavailable)?)? != *expected {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(())
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
        // Reject substituted non-regular objects without blocking before fstat validation.
        options
            .custom_flags(i32::try_from(rustix::fs::OFlags::NONBLOCK.bits()).map_err(unavailable)?);
    }
    let file = dir.open_with(name, &options).map_err(unavailable)?;
    let metadata = file.metadata().map_err(unavailable)?;
    if !metadata.is_file() {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    #[cfg(unix)]
    {
        use cap_std::fs::MetadataExt as _;
        if metadata.nlink() != 1 || metadata.uid() != owner()? || metadata.mode() & 0o077 != 0 {
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

/// Stage and sync bounded private bytes, then check live authority immediately before linking
/// or replacing the published record. A rejected fence removes only this uncommitted temporary.
pub(crate) async fn publish<F: std::future::Future<Output = Result<(), ClientError>>>(
    dir: &Dir,
    name: &str,
    bytes: &[u8],
    new: bool,
    fence: impl FnOnce() -> F,
) -> Result<(), ClientError> {
    let temporary = format!(".issuer-{}.tmp", uuid::Uuid::new_v4());
    let mut staged = UnpublishedPrivateFile {
        dir,
        name: &temporary,
        file: open_private(dir, &temporary, true, true)?,
    };
    staged.file.write_all(bytes).map_err(unavailable)?;
    staged.file.sync_all().map_err(unavailable)?;
    fence().await?;
    require_named_file(dir, &temporary, &staged.file)?;
    staged.file.rewind().map_err(unavailable)?;
    let mut actual = Vec::new();
    (&mut staged.file)
        .take(bytes.len() as u64 + 1)
        .read_to_end(&mut actual)
        .map_err(unavailable)?;
    if actual != bytes {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    if new {
        dir.hard_link(&temporary, dir, name).map_err(unavailable)?;
        dir.remove_file(&temporary).map_err(unavailable)?;
    } else {
        dir.rename(&temporary, dir, name).map_err(unavailable)?;
    }
    // Linux capability directory handles may use O_PATH, which fsync rejects.
    dir.open(".")
        .map_err(unavailable)?
        .sync_all()
        .map_err(unavailable)
}

pub(crate) fn require_named_file(
    dir: &Dir,
    name: &str,
    held: &std::fs::File,
) -> Result<(), ClientError> {
    use cap_fs_ext::MetadataExt as _;
    let named = open_private(dir, name, false, false)?;
    let named = Metadata::from_file(&named).map_err(unavailable)?;
    let held = Metadata::from_file(held).map_err(unavailable)?;
    if named.dev() != held.dev() || named.ino() != held.ino() {
        return Err(ClientError::AgentAuthorityUnavailable);
    }
    Ok(())
}
struct UnpublishedPrivateFile<'a> {
    dir: &'a Dir,
    name: &'a str,
    file: std::fs::File,
}
impl Drop for UnpublishedPrivateFile<'_> {
    fn drop(&mut self) {
        if require_named_file(self.dir, self.name, &self.file).is_ok() {
            let _ = self.dir.remove_file(self.name);
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt as _;

    fn publication_fixture() -> (tempfile::TempDir, Dir) {
        let temporary = tempfile::tempdir().unwrap();
        let root = std::fs::canonicalize(temporary.path()).unwrap();
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
        let (dir, _) = inspect_root(&root).unwrap();
        (temporary, dir)
    }
    #[tokio::test]
    async fn dropped_private_publication_removes_only_its_unpublished_stage() {
        let (_temporary, dir) = publication_fixture();
        let entered = tokio::sync::Notify::new();
        let mut operation = Box::pin(publish(&dir, "issuer.json", b"original", true, || async {
            entered.notify_one();
            std::future::pending::<()>().await;
            Ok(())
        }));
        tokio::select! {
            biased;
            result=&mut operation=>panic!("unexpected completion: {result:?}"),
            ()=entered.notified()=>{}
        }
        drop(operation);
        assert_eq!(dir.entries().unwrap().count(), 0);
    }
    #[tokio::test]
    async fn private_publication_rejects_substitution_without_deleting_foreign_stage() {
        let (_temporary, dir) = publication_fixture();
        let result = publish(&dir, "issuer.json", b"original", true, || async {
            let name = dir.entries().unwrap().next().unwrap().unwrap().file_name();
            dir.rename(&name, &dir, "held-original").unwrap();
            let mut file = open_private(&dir, name.to_str().unwrap(), true, true).unwrap();
            file.write_all(b"foreign").unwrap();
            Ok(())
        })
        .await;
        assert!(result.is_err());
        assert!(dir.symlink_metadata("issuer.json").is_err());
        assert_eq!(dir.entries().unwrap().count(), 2);
        let foreign = dir
            .entries()
            .unwrap()
            .map(Result::unwrap)
            .find(|entry| entry.file_name() != "held-original")
            .unwrap();
        assert_eq!(
            read_private(&dir, foreign.file_name().to_str().unwrap(), 64).unwrap(),
            b"foreign"
        );
    }
    #[tokio::test]
    async fn private_publication_rechecks_bytes_after_awaited_fence() {
        let (_temporary, dir) = publication_fixture();
        let result = publish(&dir, "issuer.json", b"original", true, || async {
            let name = dir.entries().unwrap().next().unwrap().unwrap().file_name();
            let mut file = open_private(&dir, name.to_str().unwrap(), true, false).unwrap();
            file.write_all(b"tampered").unwrap();
            file.sync_all().unwrap();
            Ok(())
        })
        .await;
        assert!(result.is_err());
        assert_eq!(dir.entries().unwrap().count(), 0);
    }

    #[tokio::test]
    async fn private_publication_syncs_created_and_replaced_directory_entries() {
        let temporary = tempfile::tempdir().unwrap();
        let root = std::fs::canonicalize(temporary.path()).unwrap();
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
        let (dir, _) = inspect_root(&root).unwrap();
        private_directory(&dir).unwrap();
        publish(&dir, "issuer.json", b"first", true, || async { Ok(()) })
            .await
            .unwrap();
        assert_eq!(read_private(&dir, "issuer.json", 32).unwrap(), b"first");
        publish(&dir, "issuer.json", b"replacement", false, || async {
            Ok(())
        })
        .await
        .unwrap();
        assert_eq!(
            read_private(&dir, "issuer.json", 32).unwrap(),
            b"replacement"
        );
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 1);
    }
}
