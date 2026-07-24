use healthmd_protocol::{
    crypto,
    encoding::canonical_json,
    wire::{DirectMessage, SyncPacket, Unlabeled},
};
use uuid::Uuid;

use crate::{ClientError, packet::PacketConnection};

const ENVELOPE_MAGIC: &[u8; 8] = b"HMDSC001";
const BINARY_FRAME_MAGIC: &[u8; 8] = b"HMDDIRCT";

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SecurePayload {
    Message(Box<DirectMessage>),
    BinaryTransferFrame(Vec<u8>),
}

pub struct SecureChannel {
    packet: PacketConnection,
    session_key: [u8; 32],
    pub peer_installation_id: Uuid,
    pub peer_display_name: String,
    next_send_sequence: u64,
    next_receive_sequence: u64,
}

impl SecureChannel {
    #[must_use]
    pub fn new(
        packet: PacketConnection,
        session_key: [u8; 32],
        peer_installation_id: Uuid,
        peer_display_name: String,
    ) -> Self {
        Self {
            packet,
            session_key,
            peer_installation_id,
            peer_display_name,
            next_send_sequence: 0,
            next_receive_sequence: 0,
        }
    }

    /// Send a canonical Swift direct message in the authenticated channel.
    ///
    /// # Errors
    ///
    /// Returns an error if JSON encoding, encryption, or TCP writing fails.
    pub async fn send(&mut self, message: &DirectMessage) -> Result<(), ClientError> {
        let plaintext = canonical_json(message).map_err(|_| ClientError::MalformedPacket)?;
        self.send_encrypted(&plaintext).await
    }

    /// Send an encoded binary transfer frame in the authenticated channel.
    ///
    /// # Errors
    ///
    /// Returns an error for an invalid frame magic or encryption/TCP failure.
    pub async fn send_binary_transfer_frame(&mut self, frame: &[u8]) -> Result<(), ClientError> {
        if !frame.starts_with(BINARY_FRAME_MAGIC) {
            return Err(ClientError::MalformedPacket);
        }
        self.send_encrypted(frame).await
    }

    /// Receive, authenticate, sequence-check, and classify one direct payload.
    ///
    /// # Errors
    ///
    /// Returns an error for unauthenticated packets, replay/order violations, malformed JSON,
    /// failed decryption, or TCP failure.
    pub async fn receive(&mut self) -> Result<SecurePayload, ClientError> {
        let SyncPacket::Encrypted(Unlabeled { value: frame }) = self.packet.receive().await? else {
            return Err(ClientError::Authentication(
                "received an unauthenticated packet after pairing".into(),
            ));
        };
        let envelope = crypto::open(&frame, &self.session_key).map_err(crypto_error)?;
        let plaintext = self.open_envelope(&envelope)?;
        if plaintext.starts_with(BINARY_FRAME_MAGIC) {
            return Ok(SecurePayload::BinaryTransferFrame(plaintext.to_vec()));
        }
        let message =
            serde_json::from_slice(plaintext).map_err(|_| ClientError::MalformedPacket)?;
        Ok(SecurePayload::Message(Box::new(message)))
    }

    async fn send_encrypted(&mut self, plaintext: &[u8]) -> Result<(), ClientError> {
        let sequence = self.next_send_sequence;
        self.next_send_sequence = self.next_send_sequence.wrapping_add(1);
        let mut envelope = Vec::with_capacity(16 + plaintext.len());
        envelope.extend_from_slice(ENVELOPE_MAGIC);
        envelope.extend_from_slice(&sequence.to_be_bytes());
        envelope.extend_from_slice(plaintext);
        let frame = crypto::seal(&envelope, &self.session_key).map_err(crypto_error)?;
        self.packet
            .send(&SyncPacket::Encrypted(Unlabeled::from(frame)))
            .await
    }

    fn open_envelope<'a>(&mut self, envelope: &'a [u8]) -> Result<&'a [u8], ClientError> {
        if envelope.len() < 16 || &envelope[..8] != ENVELOPE_MAGIC {
            return Err(ClientError::MalformedPacket);
        }
        let sequence = u64::from_be_bytes(
            envelope[8..16]
                .try_into()
                .map_err(|_| ClientError::MalformedPacket)?,
        );
        if sequence != self.next_receive_sequence {
            return Err(ClientError::ReplayedPacket);
        }
        self.next_receive_sequence = self.next_receive_sequence.wrapping_add(1);
        Ok(&envelope[16..])
    }
}

#[allow(clippy::needless_pass_by_value)]
fn crypto_error(error: crypto::CryptoError) -> ClientError {
    ClientError::Authentication(error.to_string())
}

#[cfg(test)]
mod tests {
    use tokio::net::{TcpListener, TcpStream};

    use super::*;
    use healthmd_protocol::wire::{DirectMessage, Empty};

    #[tokio::test]
    async fn secure_channels_exchange_sequenced_messages() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = tokio::spawn(TcpStream::connect(address));
        let (server, _) = listener.accept().await.unwrap();
        let client = client.await.unwrap().unwrap();
        let id = Uuid::new_v4();
        let mut sender = SecureChannel::new(PacketConnection::new(client), [7; 32], id, "a".into());
        let mut receiver =
            SecureChannel::new(PacketConnection::new(server), [7; 32], id, "b".into());

        sender.send(&DirectMessage::Ping(Empty {})).await.unwrap();
        assert_eq!(
            receiver.receive().await.unwrap(),
            SecurePayload::Message(Box::new(DirectMessage::Ping(Empty {})))
        );
    }
}
