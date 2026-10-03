use std::time::Duration;

use healthmd_protocol::{MAXIMUM_PACKET_BYTES, wire::SyncPacket};
use socket2::{SockRef, TcpKeepalive};
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::TcpStream;

use crate::ClientError;

/// Idle time before the first TCP keepalive probe on a direct socket.
const TCP_KEEPALIVE_IDLE: Duration = Duration::from_secs(10);
/// Delay between keepalive probes once the idle threshold passes.
const TCP_KEEPALIVE_INTERVAL: Duration = Duration::from_secs(5);
/// Keepalive probes lost before the kernel declares the connection dead (Unix).
#[cfg(unix)]
const TCP_KEEPALIVE_RETRIES: u32 = 3;

pub struct PacketConnection {
    stream: TcpStream,
    maximum_packet_bytes: usize,
}

impl PacketConnection {
    #[must_use]
    pub fn new(stream: TcpStream) -> Self {
        // Hardening only: a mobile source that silently disappears (sleep, Wi-Fi/Tailscale
        // roam, process death without a clean close) leaves the accepted socket half-open.
        // Kernel keepalives bound that state so command listeners do not wait on a peer
        // that will never speak again. Failures degrade to the deployed no-keepalive
        // behavior instead of breaking an otherwise usable connection.
        let _ = stream.set_nodelay(true);
        let keepalive = TcpKeepalive::new()
            .with_time(TCP_KEEPALIVE_IDLE)
            .with_interval(TCP_KEEPALIVE_INTERVAL);
        #[cfg(unix)]
        let keepalive = keepalive.with_retries(TCP_KEEPALIVE_RETRIES);
        let _ = SockRef::from(&stream).set_tcp_keepalive(&keepalive);
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
    async fn new_applies_transport_hardening_socket_options() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = tokio::spawn(TcpStream::connect(address));
        let (server, _) = listener.accept().await.unwrap();
        let hardened = PacketConnection::new(server);

        assert!(hardened.stream.nodelay().unwrap());
        let socket = SockRef::from(&hardened.stream);
        assert!(
            socket.keepalive().unwrap(),
            "accepted direct sockets must probe silent peers"
        );
        #[cfg(unix)]
        {
            assert_eq!(socket.tcp_keepalive_time().unwrap(), TCP_KEEPALIVE_IDLE);
            assert_eq!(
                socket.tcp_keepalive_interval().unwrap(),
                TCP_KEEPALIVE_INTERVAL
            );
            assert_eq!(
                socket.tcp_keepalive_retries().unwrap(),
                TCP_KEEPALIVE_RETRIES
            );
        }
        drop(hardened);
        drop(client.await.unwrap().unwrap());
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
