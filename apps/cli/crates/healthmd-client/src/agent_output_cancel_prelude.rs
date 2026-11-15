//! Validate the bounded metadata a native producer may queue before it reads Stop.
//! No disposition, data acknowledgement, spool or transfer checkpoint is created.
use super::super::transfer::{
    self,
    wire::{Incoming, Session},
};
use super::{Artifact, ClientError, ControlUuid, Error, NativeBinding, ValidateShape, private, v4};
use healthmd_protocol::v4::TransferFrontierPartition;

#[derive(Default)]
pub(super) struct Prelude {
    session: Option<Session>,
    manifests: usize,
    ended: bool,
}
impl Prelude {
    pub(super) fn accept(
        &mut self,
        binding: &NativeBinding,
        message: Incoming,
    ) -> Result<(), ClientError> {
        if self.ended {
            return Err(ClientError::UnexpectedMessage);
        }
        let Some(session) = &self.session else {
            let Incoming::Session(session) = message else {
                return Err(ClientError::UnexpectedMessage);
            };
            transfer::validate_retained_session(binding, &session)?;
            self.session = Some(session);
            return Ok(());
        };
        if self.manifests < binding.manifest.artifacts.len() {
            let Artifact::Branch1(item) = &binding.manifest.artifacts[self.manifests] else {
                return Err(Error::BindingChanged.into());
            };
            transfer::validate_base_manifest_message(item, message)?;
            self.manifests += 1;
            return Ok(());
        }
        if let Some(Artifact::Branch1(item)) = binding.manifest.artifacts.first() {
            let Incoming::Open {
                session: opened,
                partition,
                apple_segment,
            } = message
            else {
                return Err(ClientError::UnexpectedMessage);
            };
            if opened != *session
                || partition.index != 0
                || partition.artifact_id.to_string() != item.artifact_id.0
                || partition.artifact_offset != 0
                || partition.byte_count > 67_108_864
                || partition.byte_count > item.byte_count
                || partition.previous_sha256.is_some()
                || partition.chunk_count
                    != partition
                        .byte_count
                        .div_ceil(healthmd_protocol::TRANSFER_FRAME_BYTES as u64)
                || (partition.byte_count == 0 && item.byte_count != 0)
                || (partition.byte_count == item.byte_count && partition.sha256 != item.sha256.0)
            {
                return Err(Error::BindingChanged.into());
            }
            TransferFrontierPartition {
                partition_index: 0,
                transfer_id: ControlUuid(partition.transfer_id.to_string()),
                artifact_id: item.artifact_id.clone(),
                artifact_offset: 0,
                byte_count: i64::try_from(partition.byte_count).map_err(private::unavailable)?,
                chunk_count: i64::try_from(partition.chunk_count).map_err(private::unavailable)?,
                sha256: v4::Digest(partition.sha256),
            }
            .validate_shape()?;
            if let Some(segment) = apple_segment {
                if segment.item_byte_count
                    != i64::try_from(item.byte_count).map_err(private::unavailable)?
                    || segment.is_final_segment != (partition.byte_count == item.byte_count)
                {
                    return Err(Error::BindingChanged.into());
                }
            }
        } else {
            let Incoming::Finalize(finalize) = message else {
                return Err(ClientError::UnexpectedMessage);
            };
            if finalize.session_id != session.0.session_id
                || finalize.job_id != session.0.job_id
                || finalize.request_fingerprint != session.0.request_fingerprint
                || finalize.total_partitions != 0
                || finalize.total_bytes != 0
                || finalize.final_partition_sha256.is_some()
            {
                return Err(Error::BindingChanged.into());
            }
        }
        self.ended = true;
        Ok(())
    }
}
