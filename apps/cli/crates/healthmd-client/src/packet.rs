use healthmd_protocol::{MAXIMUM_PACKET_BYTES, wire::SyncPacket};
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::TcpStream;

use crate::ClientError;

pub struct PacketConnection {
    stream: TcpStream,
    maximum_packet_bytes: usize,
}

impl PacketConnection {
    #[must_use]
    pub const fn new(stream: TcpStream) -> Self {
        Self {
            stream,
            maximum_packet_bytes: MAXIMUM_PACKET_BYTES,
        }
    }

    #[cfg(test)]
    const fn with_maximum(stream: TcpStream, maximum_packet_bytes: usize) -> Self {
        Self {
            stream,
            maximum_packet_bytes,
        }
    }

    /// Send one eight-byte-length-prefixed Swift JSON packet.
    ///
    /// # Errors
    ///
    /// Returns an error if encoding fails, the packet is oversized, or TCP writing fails.
    pub async fn send(&mut self, packet: &SyncPacket) -> Result<(), ClientError> {
        let payload = serde_json::to_vec(packet).map_err(|_| ClientError::MalformedPacket)?;
        if payload.is_empty() || payload.len() > self.maximum_packet_bytes {
            return Err(ClientError::FrameTooLarge);
        }
        let length = u64::try_from(payload.len()).map_err(|_| ClientError::FrameTooLarge)?;
        self.stream
            .write_all(&length.to_be_bytes())
            .await
            .map_err(connection_error)?;
        self.stream
            .write_all(&payload)
            .await
            .map_err(connection_error)?;
        self.stream.flush().await.map_err(connection_error)
    }

    /// Receive one bounded eight-byte-length-prefixed Swift JSON packet.
    ///
    /// # Errors
    ///
    /// Returns an error for EOF, malformed/oversized framing, invalid JSON, or TCP failure.
    pub async fn receive(&mut self) -> Result<SyncPacket, ClientError> {
        let mut prefix = [0_u8; 8];
        self.stream
            .read_exact(&mut prefix)
            .await
            .map_err(connection_error)?;
        let length =
            usize::try_from(u64::from_be_bytes(prefix)).map_err(|_| ClientError::FrameTooLarge)?;
        if length == 0 || length > self.maximum_packet_bytes {
            return Err(ClientError::FrameTooLarge);
        }
        let mut payload = vec![0_u8; length];
        self.stream
            .read_exact(&mut payload)
            .await
            .map_err(connection_error)?;
        serde_json::from_slice(&payload).map_err(|_| ClientError::MalformedPacket)
    }
}

#[allow(clippy::needless_pass_by_value)]
fn connection_error(error: std::io::Error) -> ClientError {
    ClientError::Connection(error.to_string())
}

#[cfg(test)]
mod tests {
    use healthmd_protocol::wire::SyncPacket;
    use tokio::net::TcpListener;

    use super::*;

    #[tokio::test]
    async fn packet_round_trips_across_split_tcp_stream() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = tokio::spawn(TcpStream::connect(address));
        let (server, _) = listener.accept().await.unwrap();
        let client = client.await.unwrap().unwrap();
        let mut sender = PacketConnection::new(client);
        let mut receiver = PacketConnection::new(server);
        let packet = SyncPacket::PairingRejected(
            healthmd_protocol::wire::PairingRejected {
                reason: "test".into(),
            }
            .into(),
        );

        sender.send(&packet).await.unwrap();
        assert_eq!(receiver.receive().await.unwrap(), packet);
    }

    #[tokio::test]
    async fn zero_length_packet_fails_before_allocation() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = tokio::spawn(TcpStream::connect(address));
        let (server, _) = listener.accept().await.unwrap();
        let mut client = client.await.unwrap().unwrap();
        client.write_all(&0_u64.to_be_bytes()).await.unwrap();
        let mut receiver = PacketConnection::with_maximum(server, 64);

        assert!(matches!(
            receiver.receive().await,
            Err(ClientError::FrameTooLarge)
        ));
    }
}
