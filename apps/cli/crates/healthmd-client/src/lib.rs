#![forbid(unsafe_code)]

//! Cross-platform transport, storage, and durable receivers for Health.md.

pub mod credentials;
pub mod direct;
pub mod file_receiver;
mod generated_path;
pub mod handshake;
pub mod job;
mod limits;
pub mod markdown;
pub mod packet;
pub mod raw_receiver;
pub mod secure_channel;
pub mod storage;
pub mod trust;
pub mod v2_job;
pub mod v2_receiver;
pub mod wake;

#[doc(hidden)]
pub use limits::{OutputStorageReservation, reserve_output_capacity};

use thiserror::Error;

#[derive(Debug, Error)]
#[non_exhaustive]
pub enum ClientError {
    #[error("direct client storage is unavailable: {0}")]
    Storage(String),
    #[error("the direct client installation identity is invalid")]
    InvalidIdentity,
    #[error("the saved direct mobile trust state is invalid")]
    InvalidTrustState,
    #[error("the direct mobile connection failed: {0}")]
    Connection(String),
    #[error("the direct mobile packet is malformed")]
    MalformedPacket,
    #[error("the direct mobile packet exceeded the bounded limit")]
    FrameTooLarge,
    #[error("the direct mobile authentication failed: {0}")]
    Authentication(String),
    #[error("the direct secure channel rejected a replayed or out-of-order packet")]
    ReplayedPacket,
    #[error("the direct mobile source sent an unexpected message")]
    UnexpectedMessage,
    #[error("more than one mobile source is paired; select one of: {0:?}")]
    DeviceSelectionRequired(Vec<uuid::Uuid>),
    #[error("the requested direct mobile source is not paired: {0}")]
    DeviceNotPaired(uuid::Uuid),
    #[error("first-device pairing cannot add trust while another mobile source is paired")]
    PairingConflict,
    #[error("the direct mobile operation timed out")]
    TimedOut,
    #[error("the local direct mobile waiter was cancelled")]
    WaitCancelled,
    #[error("the direct iPhone does not support bounded query protocol v3")]
    QueryUnsupported,
    #[error("the direct iPhone query was rejected ({code}): {message}")]
    QueryRejected {
        code: String,
        message: String,
        retryable: bool,
    },
    #[error("the durable direct job does not exist")]
    JobNotFound,
    #[error("the durable direct job expired after seven days")]
    JobExpired,
    #[error("the durable direct job record is invalid")]
    InvalidJob,
    #[error("direct export {0} is already active in another process")]
    JobBusy(uuid::Uuid),
    #[error("the direct transfer is invalid: {0}")]
    InvalidTransfer(String),
    #[error("the direct export was cancelled")]
    Cancelled,
    #[error("direct export {0} paused before completion")]
    ExportPaused(uuid::Uuid),
    #[error("direct export {0} cannot resume from state {1}")]
    JobNotResumable(uuid::Uuid, String),
    #[error("cancellation for direct export {0} is pending")]
    CancellationPending(uuid::Uuid),
    #[error("the operating system credential store is unavailable: {0}")]
    CredentialStore(String),
    #[error("the native credential mutation may have completed; inspect trust before retrying")]
    CredentialMutationOutcomeUnknown,
}
