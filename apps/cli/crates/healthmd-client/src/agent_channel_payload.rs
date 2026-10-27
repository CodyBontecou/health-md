//! One authenticated sequence for independently negotiated agent and deployed base controls.
use super::*;
use healthmd_protocol::v4;

#[derive(Debug, Eq, PartialEq)]
pub(crate) enum AgentPayload {
    Agent(Box<v4::Envelope>),
    Apple(Box<DirectMessage>),
    Android(Box<v2::Envelope>),
    BinaryTransferFrame(Vec<u8>),
}

impl SecureChannel {
    pub(crate) async fn receive_agent_payload(
        &mut self,
        negotiation: v4::Negotiation,
    ) -> Result<AgentPayload, ClientError> {
        require_negotiation(negotiation)?;
        let plaintext = self.receive_plaintext().await?;
        classify(&plaintext, negotiation)
    }
}

fn require_negotiation(negotiation: v4::Negotiation) -> Result<(), ClientError> {
    if !negotiation.agent_v4 || !matches!(negotiation.base, 1 | 2) {
        return Err(v4::Error::UnsupportedCapability.into());
    }
    Ok(())
}

fn classify(raw: &[u8], negotiation: v4::Negotiation) -> Result<AgentPayload, ClientError> {
    require_negotiation(negotiation)?;
    if raw.starts_with(BINARY_FRAME_MAGIC) {
        // The transfer state machine still validates framing, identity, digests and bounds.
        // Stop must reject this variant, never acknowledge or persist it.
        return Ok(AgentPayload::BinaryTransferFrame(raw.to_vec()));
    }
    // Reject duplicate keys, excessive depth/size and invalid UTF-8 before classification.
    // A malformed agent envelope must never fall back to a permissive base decoder.
    let value = v4::parse_strict(raw)?;
    let object = value.as_object().ok_or(ClientError::MalformedPacket)?;
    match object.get("protocol_version") {
        Some(version) if version.as_u64() == Some(4) => Ok(AgentPayload::Agent(Box::new(
            v4::decode_envelope(raw, negotiation)?,
        ))),
        Some(version) if negotiation.base == 2 && version.as_u64() == Some(2) => {
            if object.len() != 3 || !object.contains_key("type") || !object.contains_key("payload")
            {
                return Err(ClientError::MalformedPacket);
            }
            let message: v2::Envelope =
                serde_json::from_value(value).map_err(|_| ClientError::MalformedPacket)?;
            message
                .validate_version()
                .map_err(|_| ClientError::MalformedPacket)?;
            Ok(AgentPayload::Android(Box::new(message)))
        }
        None if negotiation.base == 1 && object.len() == 1 => {
            let message =
                serde_json::from_value(value).map_err(|_| ClientError::MalformedPacket)?;
            Ok(AgentPayload::Apple(Box::new(message)))
        }
        _ => Err(ClientError::MalformedPacket),
    }
}

#[cfg(test)]
#[path = "agent_channel_payload_tests.rs"]
mod tests;
