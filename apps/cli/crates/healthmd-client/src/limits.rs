use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{Read as _, Seek as _},
    path::{Path, PathBuf},
};

use fs2::FileExt as _;

use crate::ClientError;

pub(crate) const MAXIMUM_DATES_PER_JOB: usize = 36_600;
pub(crate) const MAXIMUM_GENERATED_FILES_PER_JOB: usize = 100_000;
pub(crate) const MAXIMUM_PARTITIONS_PER_JOB: u64 = 16_384;
pub(crate) const MAXIMUM_JOB_BYTES: u64 = 64 * 1_024 * 1_024 * 1_024;
pub(crate) const MAXIMUM_JOB_RECORD_BYTES: u64 = 1_024 * 1_024;
pub(crate) const MAXIMUM_DURABLE_JSON_BYTES: u64 = 64 * 1_024 * 1_024;
pub(crate) const MAXIMUM_RETAINED_JOBS: usize = 64;
pub(crate) const MAXIMUM_RETAINED_STORAGE_BYTES: u64 = 128 * 1_024 * 1_024 * 1_024;
const MAXIMUM_RETAINED_STORAGE_ENTRIES: usize = 1_000_000;
const FUTURE_MATERIALIZATION_COPIES: u64 = 3;
pub(crate) const MINIMUM_FREE_SPACE_RESERVE_BYTES: u64 = 512 * 1_024 * 1_024;

#[derive(Clone, Debug)]
enum ReservationClass {
    Ordinary,
    Input { job: String },
    Materialization { job: String },
}

pub(crate) struct StorageReservation {
    storage_root: PathBuf,
    quota_lock: Option<File>,
    reservation_file: Option<File>,
    reservation_path: Option<PathBuf>,
}

/// Cross-process lease that preserves the free-space floor while writing an explicit output.
#[doc(hidden)]
pub struct OutputStorageReservation {
    lock: File,
}

impl Drop for OutputStorageReservation {
    fn drop(&mut self) {
        let _ = fs2::FileExt::unlock(&self.lock);
    }
}

impl Drop for StorageReservation {
    fn drop(&mut self) {
        if let Some(file) = self.reservation_file.take() {
            let _ = fs2::FileExt::unlock(&file);
            drop(file);
        }
        let acquired_lock = if self.quota_lock.is_none() {
            lock_storage_quota(&self.storage_root).ok()
        } else {
            None
        };
        if let Some(path) = self.reservation_path.take() {
            let _ = fs::remove_file(path);
        }
        if let Some(file) = self.quota_lock.take().or(acquired_lock) {
            let _ = fs2::FileExt::unlock(&file);
        }
    }
}

pub(crate) fn ensure_job_bytes(total_bytes: u64) -> Result<(), ClientError> {
    if total_bytes > MAXIMUM_JOB_BYTES {
        return Err(invalid("direct transfer exceeds the per-job byte limit"));
    }
    Ok(())
}

pub(crate) fn reserve_partition_capacity(
    storage_root: &Path,
    directory: &Path,
    committed_bytes: u64,
    incoming_bytes: u64,
) -> Result<StorageReservation, ClientError> {
    let total = committed_bytes
        .checked_add(incoming_bytes)
        .ok_or_else(|| invalid("direct transfer byte total overflow"))?;
    ensure_job_bytes(total)?;
    let job = private_job_key(directory)?;
    reserve_private_storage_class(
        storage_root,
        directory,
        incoming_bytes,
        &ReservationClass::Input { job },
        false,
    )
}

pub(crate) fn reserve_materialization_storage(
    storage_root: &Path,
    volume_directory: &Path,
    additional_bytes: u64,
) -> Result<StorageReservation, ClientError> {
    let job = private_job_key(volume_directory)?;
    reserve_private_storage_class(
        storage_root,
        volume_directory,
        additional_bytes,
        &ReservationClass::Materialization { job },
        false,
    )
}

pub(crate) fn reserve_private_storage(
    storage_root: &Path,
    volume_directory: &Path,
    additional_bytes: u64,
) -> Result<StorageReservation, ClientError> {
    reserve_private_storage_class(
        storage_root,
        volume_directory,
        additional_bytes,
        &ReservationClass::Ordinary,
        false,
    )
}

/// Reserve private storage while retaining the cross-process quota lock for a short atomic
/// publication sequence.
pub(crate) fn reserve_private_storage_exclusive(
    storage_root: &Path,
    volume_directory: &Path,
    additional_bytes: u64,
) -> Result<StorageReservation, ClientError> {
    reserve_private_storage_class(
        storage_root,
        volume_directory,
        additional_bytes,
        &ReservationClass::Ordinary,
        true,
    )
}

fn reserve_private_storage_class(
    storage_root: &Path,
    volume_directory: &Path,
    additional_bytes: u64,
    class: &ReservationClass,
    retain_quota_lock: bool,
) -> Result<StorageReservation, ClientError> {
    let quota_lock = lock_storage_quota(storage_root)?;
    reserve_private_storage_locked(
        storage_root,
        volume_directory,
        additional_bytes,
        class,
        quota_lock,
        retain_quota_lock,
    )
}

fn reserve_private_storage_locked(
    storage_root: &Path,
    volume_directory: &Path,
    additional_bytes: u64,
    class: &ReservationClass,
    quota_lock: File,
    retain_quota_lock: bool,
) -> Result<StorageReservation, ClientError> {
    let reservations = storage_root.join(".storage-reservations");
    prepare_reservations_directory(&reservations)?;
    remove_inactive_reservations(&reservations)?;
    let mut usage = quota_usage(storage_root)?;
    usage.add_reservation(class, additional_bytes)?;
    if usage.effective_bytes()? > MAXIMUM_RETAINED_STORAGE_BYTES {
        return Err(ClientError::Storage(
            "private direct storage exceeds the retained lifecycle byte limit".into(),
        ));
    }
    let required_free = usage
        .active_reservation_bytes
        .checked_add(usage.future_materialization_bytes()?)
        .and_then(|bytes| bytes.checked_add(MINIMUM_FREE_SPACE_RESERVE_BYTES))
        .ok_or_else(|| invalid("direct transfer disk requirement overflow"))?;
    let available = fs2::available_space(volume_directory).map_err(storage_error)?;
    if available < required_free {
        return Err(ClientError::Storage(
            "insufficient private disk space for the bounded direct transfer lifecycle".into(),
        ));
    }

    let path = reservations.join(reservation_name(class));
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&path)
        .map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        file.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(storage_error)?;
    }
    file.set_len(additional_bytes).map_err(storage_error)?;
    file.lock_exclusive().map_err(storage_error)?;
    let quota_lock = if retain_quota_lock {
        Some(quota_lock)
    } else {
        let _ = fs2::FileExt::unlock(&quota_lock);
        None
    };
    Ok(StorageReservation {
        storage_root: storage_root.to_owned(),
        quota_lock,
        reservation_file: Some(file),
        reservation_path: Some(path),
    })
}

pub(crate) fn reserve_new_job(
    storage_root: &Path,
    record_bytes: u64,
) -> Result<StorageReservation, ClientError> {
    let quota_lock = lock_storage_quota(storage_root)?;
    let mut jobs = 0_usize;
    for directory in [storage_root.join("jobs"), storage_root.join("jobs-v2")] {
        for entry in fs::read_dir(directory).map_err(storage_error)? {
            let entry = entry.map_err(storage_error)?;
            let metadata = fs::symlink_metadata(entry.path()).map_err(storage_error)?;
            if unsafe_metadata(&metadata) {
                return Err(ClientError::Storage(
                    "private direct job storage contains an unsafe entry".into(),
                ));
            }
            if metadata.is_dir() && valid_job_record_directory(&entry.path())? {
                jobs = jobs
                    .checked_add(1)
                    .ok_or_else(|| invalid("retained direct job count overflow"))?;
            }
        }
    }
    if jobs >= MAXIMUM_RETAINED_JOBS {
        return Err(ClientError::Storage(
            "private direct storage exceeds the retained job limit".into(),
        ));
    }
    reserve_private_storage_locked(
        storage_root,
        storage_root,
        record_bytes,
        &ReservationClass::Ordinary,
        quota_lock,
        true,
    )
}

/// Serialize explicit-output allocation across Health.md processes and check the target volume
/// while the lease is held.
///
/// # Errors
///
/// Returns a storage error when the private lock or output volume is unavailable.
#[doc(hidden)]
pub fn reserve_output_capacity(
    storage_root: &Path,
    volume_directory: &Path,
    additional_bytes: u64,
) -> Result<OutputStorageReservation, ClientError> {
    prepare_private_directory(storage_root)?;
    let lock = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(storage_root.join(".output-storage.lock"))
        .map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        lock.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(storage_error)?;
    }
    lock.lock_exclusive().map_err(storage_error)?;
    if let Err(error) = ensure_available_space(volume_directory, additional_bytes) {
        let _ = fs2::FileExt::unlock(&lock);
        return Err(error);
    }
    Ok(OutputStorageReservation { lock })
}

pub(crate) fn prepare_private_directory(path: &Path) -> Result<(), ClientError> {
    fs::create_dir_all(path).map_err(storage_error)?;
    let metadata = fs::symlink_metadata(path).map_err(storage_error)?;
    if unsafe_metadata(&metadata) || !metadata.is_dir() {
        return Err(ClientError::Storage(
            "private direct storage directory is unsafe".into(),
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(storage_error)?;
    }
    Ok(())
}

pub(crate) fn ensure_available_space(
    directory: &Path,
    additional_bytes: u64,
) -> Result<(), ClientError> {
    let required = additional_bytes
        .checked_add(MINIMUM_FREE_SPACE_RESERVE_BYTES)
        .ok_or_else(|| invalid("direct transfer disk requirement overflow"))?;
    let available = fs2::available_space(directory).map_err(storage_error)?;
    if available < required {
        return Err(ClientError::Storage(
            "insufficient private disk space for the bounded direct transfer".into(),
        ));
    }
    Ok(())
}

fn lock_storage_quota(storage_root: &Path) -> Result<File, ClientError> {
    prepare_private_directory(storage_root)?;
    let lock = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(storage_root.join(".storage-quota.lock"))
        .map_err(storage_error)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        lock.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(storage_error)?;
    }
    lock.lock_exclusive().map_err(storage_error)?;
    Ok(lock)
}

fn prepare_reservations_directory(path: &Path) -> Result<(), ClientError> {
    prepare_private_directory(path)
}

fn remove_inactive_reservations(directory: &Path) -> Result<(), ClientError> {
    for entry in fs::read_dir(directory).map_err(storage_error)? {
        let entry = entry.map_err(storage_error)?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path).map_err(storage_error)?;
        if unsafe_metadata(&metadata) || !metadata.is_file() {
            return Err(ClientError::Storage(
                "private storage reservation entry is unsafe".into(),
            ));
        }
        let file = match fs::OpenOptions::new().read(true).write(true).open(&path) {
            Ok(file) => file,
            // Windows can reject opening an actively locked reservation before `try_lock_exclusive`
            // gets a chance to report `WouldBlock`. In either case the reservation is live.
            Err(error) if reservation_is_active_error(&error) => continue,
            Err(error) => return Err(storage_error(error)),
        };
        match file.try_lock_exclusive() {
            Ok(()) => {
                let _ = fs2::FileExt::unlock(&file);
                drop(file);
                fs::remove_file(path).map_err(storage_error)?;
            }
            Err(error) if reservation_is_active_error(&error) => {}
            Err(error) => return Err(storage_error(error)),
        }
    }
    Ok(())
}

fn reservation_is_active_error(error: &std::io::Error) -> bool {
    if error.kind() == std::io::ErrorKind::WouldBlock {
        return true;
    }
    #[cfg(windows)]
    {
        // ERROR_LOCK_VIOLATION: another process owns a byte-range lock on the file.
        error.raw_os_error() == Some(33)
    }
    #[cfg(not(windows))]
    false
}

#[derive(Default)]
struct QuotaUsage {
    retained_bytes: u64,
    active_reservation_bytes: u64,
    inputs: BTreeMap<String, u64>,
    materializations: BTreeMap<String, u64>,
}

impl QuotaUsage {
    fn checked_add(target: &mut u64, value: u64) -> Result<(), ClientError> {
        *target = target
            .checked_add(value)
            .ok_or_else(|| invalid("retained direct storage byte total overflow"))?;
        Ok(())
    }

    fn add_job_bytes(
        map: &mut BTreeMap<String, u64>,
        job: String,
        bytes: u64,
    ) -> Result<(), ClientError> {
        let value = map.entry(job).or_default();
        Self::checked_add(value, bytes)
    }

    fn add_reservation(&mut self, class: &ReservationClass, bytes: u64) -> Result<(), ClientError> {
        Self::checked_add(&mut self.retained_bytes, bytes)?;
        Self::checked_add(&mut self.active_reservation_bytes, bytes)?;
        match class {
            ReservationClass::Ordinary => Ok(()),
            ReservationClass::Input { job } => {
                Self::add_job_bytes(&mut self.inputs, job.clone(), bytes)
            }
            ReservationClass::Materialization { job } => {
                Self::add_job_bytes(&mut self.materializations, job.clone(), bytes)
            }
        }
    }

    fn future_materialization_bytes(&self) -> Result<u64, ClientError> {
        self.inputs.iter().try_fold(0_u64, |total, (job, input)| {
            let required = input
                .checked_mul(FUTURE_MATERIALIZATION_COPIES)
                .ok_or_else(|| invalid("future materialization byte total overflow"))?;
            let materialized = self.materializations.get(job).copied().unwrap_or(0);
            total
                .checked_add(required.saturating_sub(materialized))
                .ok_or_else(|| invalid("future materialization byte total overflow"))
        })
    }

    fn effective_bytes(&self) -> Result<u64, ClientError> {
        self.retained_bytes
            .checked_add(self.future_materialization_bytes()?)
            .ok_or_else(|| invalid("retained lifecycle byte total overflow"))
    }
}

fn quota_usage(storage_root: &Path) -> Result<QuotaUsage, ClientError> {
    let mut usage = QuotaUsage::default();
    let mut entries = 0_usize;
    let mut pending = vec![PathBuf::from(storage_root)];
    while let Some(path) = pending.pop() {
        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(storage_error(error)),
        };
        if unsafe_metadata(&metadata) {
            return Err(ClientError::Storage(
                "private direct storage contains an unsafe link or reparse point".into(),
            ));
        }
        entries = entries
            .checked_add(1)
            .ok_or_else(|| invalid("retained direct storage entry count overflow"))?;
        if entries > MAXIMUM_RETAINED_STORAGE_ENTRIES {
            return Err(ClientError::Storage(
                "private direct storage exceeds the retained entry limit".into(),
            ));
        }
        if metadata.is_dir() {
            for entry in fs::read_dir(path).map_err(storage_error)? {
                pending.push(entry.map_err(storage_error)?.path());
            }
            continue;
        }
        QuotaUsage::checked_add(&mut usage.retained_bytes, metadata.len())?;
        if let Some((class, job)) = reservation_class_from_path(&path) {
            QuotaUsage::checked_add(&mut usage.active_reservation_bytes, metadata.len())?;
            match class {
                "input" => {
                    QuotaUsage::add_job_bytes(&mut usage.inputs, job.to_owned(), metadata.len())?;
                }
                "materialization" => {
                    QuotaUsage::add_job_bytes(
                        &mut usage.materializations,
                        job.to_owned(),
                        metadata.len(),
                    )?;
                }
                _ => {}
            }
        } else if let Some(job) = private_file_job_key(&path) {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("");
            if is_transfer_input_name(name) {
                QuotaUsage::add_job_bytes(&mut usage.inputs, job, metadata.len())?;
            } else if is_materialization_name(name) {
                QuotaUsage::add_job_bytes(&mut usage.materializations, job, metadata.len())?;
            }
        }
    }
    Ok(usage)
}

fn reservation_name(class: &ReservationClass) -> String {
    let id = uuid::Uuid::new_v4().to_string().to_lowercase();
    match class {
        ReservationClass::Ordinary => format!("{id}--global--ordinary"),
        ReservationClass::Input { job } => format!("{id}--{job}--input"),
        ReservationClass::Materialization { job } => {
            format!("{id}--{job}--materialization")
        }
    }
}

fn reservation_class_from_path(path: &Path) -> Option<(&str, &str)> {
    if path.parent()?.file_name()?.to_str()? != ".storage-reservations" {
        return None;
    }
    let mut fields = path.file_name()?.to_str()?.rsplitn(3, "--");
    let class = fields.next()?;
    let job = fields.next()?;
    let _id = fields.next()?;
    Some((class, job))
}

fn private_job_key(directory: &Path) -> Result<String, ClientError> {
    directory
        .file_name()
        .and_then(|value| value.to_str())
        .and_then(|value| uuid::Uuid::parse_str(value).ok().map(|id| id.to_string()))
        .ok_or_else(|| invalid("private job directory has no valid job identifier"))
}

fn private_file_job_key(path: &Path) -> Option<String> {
    path.ancestors().skip(1).find_map(|directory| {
        directory
            .file_name()
            .and_then(|value| value.to_str())
            .and_then(|value| uuid::Uuid::parse_str(value).ok())
            .map(|id| id.to_string())
    })
}

fn has_extension(name: &str, expected: &str) -> bool {
    Path::new(name)
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case(expected))
}

fn is_transfer_input_name(name: &str) -> bool {
    (name.starts_with("partition-") || name.starts_with("file-partition-"))
        && has_extension(name, "bin")
}

fn is_materialization_name(name: &str) -> bool {
    name == "response.json"
        || name.starts_with("extraction.")
        || name.starts_with("android-raw-snapshot.")
        || (name.starts_with("artifact-") && has_extension(name, "bin"))
        || (name.starts_with("file-source-") && has_extension(name, "bin"))
        || ((name.starts_with("commit-") || name.starts_with("file-output-"))
            && has_extension(name, "stage"))
}

fn valid_job_record_directory(directory: &Path) -> Result<bool, ClientError> {
    let Some(job_id) = directory
        .file_name()
        .and_then(|value| value.to_str())
        .and_then(|value| uuid::Uuid::parse_str(value).ok())
    else {
        return Ok(false);
    };
    let path = directory.join("record.json");
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(storage_error(error)),
    };
    if unsafe_metadata(&metadata)
        || !metadata.is_file()
        || metadata.len() == 0
        || metadata.len() > MAXIMUM_JOB_RECORD_BYTES
    {
        return Ok(false);
    }
    let bytes = read_bounded(&path, MAXIMUM_JOB_RECORD_BYTES, "invalid job record")?;
    match directory
        .parent()
        .and_then(Path::file_name)
        .and_then(|value| value.to_str())
    {
        Some("jobs") => Ok(serde_json::from_slice::<crate::job::JobRecord>(&bytes)
            .is_ok_and(|record| record.request.job_id.0 == job_id && record.validate().is_ok())),
        Some("jobs-v2") => Ok(serde_json::from_slice::<crate::v2_job::V2JobRecord>(&bytes)
            .is_ok_and(|record| record.request.job_id == job_id && record.validate().is_ok())),
        _ => Ok(false),
    }
}

fn unsafe_metadata(metadata: &fs::Metadata) -> bool {
    metadata.file_type().is_symlink() || metadata_is_reparse_point(metadata)
}

#[cfg(windows)]
fn metadata_is_reparse_point(metadata: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt as _;
    const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
    metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
}

#[cfg(not(windows))]
fn metadata_is_reparse_point(_metadata: &fs::Metadata) -> bool {
    false
}

pub(crate) fn read_bounded(
    path: &Path,
    maximum_bytes: u64,
    invalid_message: &'static str,
) -> Result<Vec<u8>, ClientError> {
    let mut file = File::open(path).map_err(storage_error)?;
    let metadata_bytes = file.metadata().map_err(storage_error)?.len();
    if metadata_bytes > maximum_bytes {
        return Err(invalid(invalid_message));
    }
    file.rewind().map_err(storage_error)?;
    let mut bytes = Vec::with_capacity(usize::try_from(metadata_bytes).unwrap_or(0));
    file.take(maximum_bytes + 1)
        .read_to_end(&mut bytes)
        .map_err(storage_error)?;
    if u64::try_from(bytes.len()).unwrap_or(u64::MAX) > maximum_bytes {
        return Err(invalid(invalid_message));
    }
    Ok(bytes)
}

fn invalid(message: &str) -> ClientError {
    ClientError::InvalidTransfer(message.into())
}

#[allow(clippy::needless_pass_by_value)]
fn storage_error(error: std::io::Error) -> ClientError {
    ClientError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use tempfile::{NamedTempFile, TempDir};

    use super::*;

    #[test]
    fn aggregate_job_limit_and_bounded_read_fail_closed() {
        assert!(ensure_job_bytes(MAXIMUM_JOB_BYTES).is_ok());
        assert!(ensure_job_bytes(MAXIMUM_JOB_BYTES + 1).is_err());

        let mut file = NamedTempFile::new().unwrap();
        std::io::Write::write_all(&mut file, b"12345").unwrap();
        assert_eq!(read_bounded(file.path(), 5, "oversized").unwrap(), b"12345");
        assert!(read_bounded(file.path(), 4, "oversized").is_err());
    }

    #[test]
    fn retained_storage_reservations_are_bounded_and_removed_on_drop() {
        let temporary = TempDir::new().unwrap();
        let root = temporary.path();
        let reservation = reserve_private_storage(root, root, 4_096).unwrap();
        let reservations = root.join(".storage-reservations");
        assert_eq!(fs::read_dir(&reservations).unwrap().count(), 1);
        drop(reservation);
        assert_eq!(fs::read_dir(reservations).unwrap().count(), 0);

        assert!(reserve_private_storage(root, root, MAXIMUM_RETAINED_STORAGE_BYTES + 1).is_err());
    }

    #[test]
    fn lifecycle_accounting_reserves_four_bounded_copies_per_input_job() {
        let job = uuid::Uuid::new_v4().to_string();
        let mut usage = QuotaUsage::default();
        usage
            .add_reservation(&ReservationClass::Input { job: job.clone() }, 100)
            .unwrap();
        assert_eq!(usage.effective_bytes().unwrap(), 400);
        usage
            .add_reservation(&ReservationClass::Materialization { job: job.clone() }, 100)
            .unwrap();
        assert_eq!(usage.effective_bytes().unwrap(), 400);
        usage
            .add_reservation(&ReservationClass::Materialization { job }, 200)
            .unwrap();
        assert_eq!(usage.effective_bytes().unwrap(), 400);
    }

    #[test]
    fn explicit_output_capacity_is_serialized_across_process_leases() {
        let temporary = TempDir::new().unwrap();
        let root = temporary.path().join("state");
        let output = temporary.path().join("output");
        fs::create_dir(&output).unwrap();
        let first = reserve_output_capacity(&root, &output, 1).unwrap();
        let (sender, receiver) = std::sync::mpsc::channel();
        let second_root = root.clone();
        let second_output = output.clone();
        let task = std::thread::spawn(move || {
            let second = reserve_output_capacity(&second_root, &second_output, 1).unwrap();
            sender.send(()).unwrap();
            drop(second);
        });
        assert!(
            receiver
                .recv_timeout(std::time::Duration::from_millis(50))
                .is_err()
        );
        drop(first);
        receiver
            .recv_timeout(std::time::Duration::from_secs(2))
            .unwrap();
        task.join().unwrap();
    }

    #[test]
    fn crashed_unlocked_reservations_are_reaped_immediately() {
        let temporary = TempDir::new().unwrap();
        let root = temporary.path();
        let initial = reserve_private_storage(root, root, 1).unwrap();
        drop(initial);
        let reservations = root.join(".storage-reservations");
        let crashed = reservations.join(format!(
            "{}--{}--input",
            uuid::Uuid::new_v4(),
            uuid::Uuid::new_v4()
        ));
        File::create(&crashed).unwrap().set_len(4_096).unwrap();
        let replacement = reserve_private_storage(root, root, 1).unwrap();
        assert!(!crashed.exists());
        drop(replacement);
    }

    #[test]
    fn empty_crash_directories_do_not_consume_job_slots() {
        let temporary = TempDir::new().unwrap();
        let root = temporary.path();
        fs::create_dir(root.join("jobs")).unwrap();
        fs::create_dir(root.join("jobs-v2")).unwrap();
        for _ in 0..MAXIMUM_RETAINED_JOBS {
            fs::create_dir(root.join("jobs").join(uuid::Uuid::new_v4().to_string())).unwrap();
        }
        let reservation = reserve_new_job(root, 1).unwrap();
        drop(reservation);
    }

    #[test]
    fn retained_job_count_is_shared_across_protocol_versions() {
        let temporary = TempDir::new().unwrap();
        let root = temporary.path();
        fs::create_dir(root.join("jobs")).unwrap();
        fs::create_dir(root.join("jobs-v2")).unwrap();
        for index in 0..MAXIMUM_RETAINED_JOBS {
            let parent = if index % 2 == 0 { "jobs" } else { "jobs-v2" };
            let job_id = uuid::Uuid::new_v4();
            let directory = root.join(parent).join(job_id.to_string());
            fs::create_dir(&directory).unwrap();
            let bytes = if parent == "jobs" {
                let record = crate::job::JobRecord::new(healthmd_protocol::models::ExportRequest {
                    protocol_version: 1,
                    job_id: healthmd_protocol::encoding::SwiftUuid(job_id),
                    created_at: chrono::Utc::now(),
                    date_selection: healthmd_protocol::models::DateSelection::Exact(
                        healthmd_protocol::models::ExactDateSelection {
                            start: "2026-07-01".into(),
                            end: "2026-07-01".into(),
                        },
                    ),
                    settings_policy: healthmd_protocol::models::SettingsPolicy::RequestedDatesOnly,
                    profile_reference: None,
                    response_mode: healthmd_protocol::models::ResponseMode::RawJson,
                    raw_profile: Some(healthmd_protocol::wire::RawProfile::HealthDataProjection),
                    canonical_selection: None,
                    destination: None,
                });
                healthmd_protocol::encoding::canonical_json(&record).unwrap()
            } else {
                let created_at = chrono::Utc::now();
                let record = crate::v2_job::V2JobRecord::new(
                    healthmd_protocol::v2::ExportRequest {
                        job_id,
                        created_at,
                        expires_at: created_at
                            + chrono::Duration::seconds(
                                healthmd_protocol::JOB_LIFETIME_SECONDS,
                            ),
                        source_installation_id: uuid::Uuid::new_v4(),
                        date_selection: healthmd_protocol::v2::DateSelection::Exact {
                            start_date: "2026-07-01".into(),
                            end_date: "2026-07-01".into(),
                        },
                        product: healthmd_protocol::v2::ExportProduct::AndroidProviderNativeSnapshotV1 {
                            provider_id: "health_connect".into(),
                            format: healthmd_protocol::v2::RawSnapshotFormat::Json,
                            scope: healthmd_protocol::v2::RawSnapshotScope::AllAuthorizedSupportedData,
                            include_exercise_routes: false,
                        },
                        destination: None,
                    },
                    None,
                );
                healthmd_protocol::encoding::canonical_json(&record).unwrap()
            };
            fs::write(directory.join("record.json"), bytes).unwrap();
        }
        assert!(reserve_new_job(root, 1).is_err());
    }
}
