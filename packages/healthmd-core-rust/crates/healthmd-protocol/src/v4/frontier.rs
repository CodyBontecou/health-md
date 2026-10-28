//! Pure frontier1 computation, not durable storage, authorization or host output commit proof.
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::{ControlUuid, Digest, Error, ValidateShape, document_digest, ensure, shape};

/// Neutral input for an exact generated-file partition. Consumers must independently validate
/// original base/v4 metadata, artifact membership, contiguous segments and actual commit evidence.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TransferFrontierPartition {
    pub partition_index: i64,
    pub transfer_id: ControlUuid,
    pub artifact_id: ControlUuid,
    pub artifact_offset: i64,
    pub byte_count: i64,
    pub chunk_count: i64,
    pub sha256: Digest,
}
impl ValidateShape for TransferFrontierPartition {
    fn validate_shape(&self) -> Result<(), Error> {
        shape((0..2_147_483_647).contains(&self.partition_index))?;
        shape((0..=67_108_864).contains(&self.byte_count))?;
        shape((0..=128).contains(&self.chunk_count))?;
        shape(
            self.artifact_offset >= 0
                && self.artifact_offset <= 1_099_511_627_776 - self.byte_count,
        )?;
        self.transfer_id.validate_shape()?;
        self.artifact_id.validate_shape()?;
        self.sha256.validate_shape()
    }
}

/// Empty post-manifest frontier1; accepted pre-capture receipts keep their separate zero digests.
/// # Errors
/// Returns a fixed shape/codec code, never an input value or authorization verdict.
pub(crate) fn transfer_frontier_seed(
    job_id: &ControlUuid,
    request_sha256: &Digest,
    manifest_sha256: &Digest,
    session_id: &ControlUuid,
) -> Result<Digest, Error> {
    job_id.validate_shape()?;
    session_id.validate_shape()?;
    request_sha256.validate_shape()?;
    manifest_sha256.validate_shape()?;
    document_digest(
        &json!({"schema": "healthmd.agent_transfer_frontier_seed", "schema_version": 1,
        "job_id": job_id, "request_sha256": request_sha256, "manifest_sha256": manifest_sha256, "session_id": session_id}),
    )
}

/// Extend the caller's trusted/recomputed prefix, never trust an incoming resume claim as state.
/// # Errors
/// Malformed bounds reject as `invalid_request`; skipped/repeated indices as `binding_changed`.
pub(crate) fn transfer_frontier_step(
    previous: &Digest,
    committed_partition_count: i64,
    partition: &TransferFrontierPartition,
) -> Result<Digest, Error> {
    previous.validate_shape()?;
    partition.validate_shape()?;
    shape((0..2_147_483_647).contains(&committed_partition_count))?;
    ensure(
        partition.partition_index == committed_partition_count,
        Error::BindingChanged,
    )?;
    document_digest(
        &json!({"schema": "healthmd.agent_transfer_frontier_step", "schema_version": 1,
        "previous_frontier_sha256": previous, "partition": partition}),
    )
}

/// Computed immutable prefix, not a journal/commit receipt. Recovery must recompute original
/// descriptors and compare trusted stored state; deserialized caller fields cannot construct it.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransferFrontier {
    committed_partition_count: i64,
    sha256: Digest,
}
impl TransferFrontier {
    /// Construct the original post-manifest empty prefix.
    /// # Errors
    /// Returns a fixed shape/codec code for invalid bindings.
    pub fn new(
        job_id: &ControlUuid,
        request_sha256: &Digest,
        manifest_sha256: &Digest,
        session_id: &ControlUuid,
    ) -> Result<Self, Error> {
        Ok(Self {
            committed_partition_count: 0,
            sha256: transfer_frontier_seed(job_id, request_sha256, manifest_sha256, session_id)?,
        })
    }
    /// Compute the next contiguous prefix; does not perform or attest a durable commit.
    /// # Errors
    /// Rejects malformed metadata or skipped/repeated partition indices.
    pub fn appending(&self, partition: &TransferFrontierPartition) -> Result<Self, Error> {
        let sha256 =
            transfer_frontier_step(&self.sha256, self.committed_partition_count, partition)?;
        Ok(Self {
            committed_partition_count: self.committed_partition_count + 1,
            sha256,
        })
    }
    #[must_use]
    pub const fn committed_partition_count(&self) -> i64 {
        self.committed_partition_count
    }
    #[must_use]
    pub const fn sha256(&self) -> &Digest {
        &self.sha256
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn internal_counter_bounds_cannot_overflow_public_receipt_count() {
        let row = TransferFrontierPartition {
            partition_index: 0,
            transfer_id: ControlUuid("00000000-0000-4000-8000-000000000003".into()),
            artifact_id: ControlUuid("00000000-0000-4000-8000-000000000004".into()),
            artifact_offset: 0,
            byte_count: 3,
            chunk_count: 1,
            sha256: Digest("1".repeat(64)),
        };
        for count in [-1, 2_147_483_647, i64::MAX] {
            assert_eq!(
                transfer_frontier_step(&Digest("2".repeat(64)), count, &row),
                Err(Error::InvalidRequest)
            );
        }
    }
}
