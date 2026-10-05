//! Pure, opt-in direct v4 foundation. This namespace does not advertise or dispatch v4.
//!
//! Only the generated-file export/discovery boundary is implemented here. Source query,
//! projection execution and configuration-control envelopes fail closed. DTO/codec and
//! pure consistency checks are **not** grant issuance, storage, capture or filesystem safety.
//! Issuer-owned records and installed runtime checks remain native/host adapter obligations.

mod codec;
mod contexts;
mod integers;
mod models;
mod paths;
mod semantics;
mod source;

pub use crate::transfer::sha256_hex;
pub use codec::{canonical_json, parse_strict};
pub use contexts::*;
pub use models::*;
pub use paths::{predicted_paths, validate_path_collisions, validate_relative_path};
pub use semantics::*;
pub use source::{binary64_nanosecond_view, validate_exact_time, validate_native_identity};

use serde::{Serialize, de::DeserializeOwned};

/// Stable health-free errors. Never retain rejected input or parser errors.
#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum Error {
    #[error("invalid_request")]
    InvalidRequest,
    #[error("unsupported_capability")]
    UnsupportedCapability,
    #[error("unsupported_metric")]
    UnsupportedMetric,
    #[error("binding_changed")]
    BindingChanged,
    #[error("revision_conflict")]
    RevisionConflict,
    #[error("plan_expired")]
    PlanExpired,
    #[error("approval_required")]
    ApprovalRequired,
    #[error("unsafe_path")]
    UnsafePath,
    #[error("path_collision")]
    PathCollision,
    #[error("query_budget_exceeded")]
    QueryBudgetExceeded,
    #[error("native_rebind_required")]
    NativeRebindRequired,
    #[error("permission_required")]
    PermissionRequired,
    #[error("entitlement_required")]
    EntitlementRequired,
}

/// Schema-shape checks only; not a private-store/semantic authorization verdict.
pub trait ValidateShape {
    /// Check closed DTO bounds after raw parsing (and before use).
    ///
    /// # Errors
    /// Returns a fixed code for malformed or out-of-bounds fields.
    fn validate_shape(&self) -> Result<(), Error>;
}

/// Parse raw bytes before serde can discard duplicate keys; check DTO bounds.
/// Optional nulls are rejected except the required nullable source offset.
/// This does not perform contextual authorization or semantic checks.
///
/// # Errors
/// Returns `invalid_request` for malformed bytes or schema-shape violations.
pub fn decode_typed<T: DeserializeOwned + ValidateShape>(raw: &[u8]) -> Result<T, Error> {
    let value = parse_strict(raw)?;
    reject_nulls(&value, None)?;
    let dto: T = serde_json::from_value(value).map_err(|_| Error::InvalidRequest)?;
    dto.validate_shape()?;
    Ok(dto)
}

fn reject_nulls(value: &serde_json::Value, key: Option<&str>) -> Result<(), Error> {
    match value {
        serde_json::Value::Null if key != Some("source_offset_seconds") => {
            Err(Error::InvalidRequest)
        }
        serde_json::Value::Object(object) => {
            if object.contains_key("epoch_second") && object.contains_key("precision") {
                shape(object.contains_key("source_offset_seconds"))?;
            }
            for (key, child) in object {
                reject_nulls(child, Some(key))?;
            }
            Ok(())
        }
        serde_json::Value::Array(array) => {
            for child in array {
                reject_nulls(child, None)?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

fn ensure(condition: bool, error: Error) -> Result<(), Error> {
    if condition { Ok(()) } else { Err(error) }
}

fn shape(condition: bool) -> Result<(), Error> {
    ensure(condition, Error::InvalidRequest)
}

fn unique<T: PartialEq>(items: &[T]) -> bool {
    items
        .iter()
        .enumerate()
        .all(|(i, item)| !items[..i].contains(item))
}

fn sorted<T: Serialize + PartialEq>(items: &[T]) -> Result<(), Error> {
    shape(unique(items))?;
    let strings: Vec<String> = items
        .iter()
        .map(|item| {
            serde_json::to_value(item)
                .ok()
                .and_then(|value| value.as_str().map(str::to_owned))
                .ok_or(Error::InvalidRequest)
        })
        .collect::<Result<_, _>>()?;
    shape(strings.windows(2).all(|pair| pair[0] < pair[1]))
}
