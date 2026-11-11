use super::*;
use crate::packet::PacketConnection;
use healthmd_protocol::wire::Empty;
use tokio::net::{TcpListener, TcpStream};
use uuid::Uuid;

fn negotiation(base: u16) -> v4::Negotiation {
    v4::Negotiation {
        base,
        iphone_query_v3: false,
        agent_v4: true,
    }
}
fn agent() -> v4::Envelope {
    v4::Envelope::new(v4::Message::Rejected(Box::new(v4::AgentError {
        code: v4::AgentErrorCode::UnsupportedCapability,
        request_id: v4::ControlUuid("00000000-0000-4000-8000-000000000001".into()),
        retryable: false,
        schema: v4::AgentErrorSchema::HealthmdAgentError,
        schema_version: 1,
    })))
}
fn base_bytes(base: u16) -> Vec<u8> {
    if base == 1 {
        serde_json::to_vec(&DirectMessage::Ping(Empty {})).unwrap()
    } else {
        serde_json::to_vec(&v2::Envelope::new(v2::Message::Ping(v2::Empty {}))).unwrap()
    }
}
async fn pair() -> (SecureChannel, SecureChannel) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let connection = tokio::spawn(TcpStream::connect(listener.local_addr().unwrap()));
    let (server, _) = listener.accept().await.unwrap();
    let client = connection.await.unwrap().unwrap();
    let id = Uuid::new_v4();
    (
        SecureChannel::new(
            PacketConnection::new(client),
            [7; 32],
            id,
            "synthetic".into(),
        ),
        SecureChannel::new(
            PacketConnection::new(server),
            [7; 32],
            id,
            "synthetic".into(),
        ),
    )
}

#[test]
fn mixed_channel_classifies_only_negotiated_source_and_agent_envelopes() {
    for base in [1, 2] {
        let n = negotiation(base);
        assert_eq!(
            classify(&serde_json::to_vec(&agent()).unwrap(), n).unwrap(),
            AgentPayload::Agent(Box::new(agent()))
        );
        let classified = classify(&base_bytes(base), n).unwrap();
        assert!(matches!(
            (base, classified),
            (1, AgentPayload::Apple(_)) | (2, AgentPayload::Android(_))
        ));
        assert!(classify(&base_bytes(3 - base), n).is_err());
        assert_eq!(
            classify(BINARY_FRAME_MAGIC, n).unwrap(),
            AgentPayload::BinaryTransferFrame(BINARY_FRAME_MAGIC.to_vec())
        );
    }
}

#[test]
fn mixed_channel_never_falls_back_after_ambiguous_or_invalid_versioned_input() {
    let bad = [
        r#"{"protocol_version":4,"type":"ping","payload":{}}"#,
        r#"{"protocol_version":4,"type":"rejected","payload":{},"ping":{}}"#,
        r#"{"protocol_version":4,"protocol_version":2,"type":"ping","payload":{}}"#,
        r#"{"protocol_version":2,"type":"ping","payload":{},"extra":true}"#,
        r#"{"protocol_version":3,"type":"ping","payload":{}}"#,
        r#"{"protocol_version":"4","type":"ping","payload":{}}"#,
        r#"{"protocol_version":null,"ping":{}}"#,
        r#"{"ping":{},"pong":{}}"#,
        r#"{"ping":{},"ping":{}}"#,
        r#"{"protocol_version":2,"type":"ping","payload":{"nested":{"x":1,"x":2}}}"#,
        r#"{"unknown":{}}"#,
        r"[]",
        r"null",
    ];
    for base in [1, 2] {
        for raw in bad {
            assert!(
                classify(raw.as_bytes(), negotiation(base)).is_err(),
                "accepted {base} {raw}"
            );
        }
        assert!(classify(&[0xff], negotiation(base)).is_err());
        assert!(classify(&vec![b' '; 2 * 1024 * 1024 + 1], negotiation(base)).is_err());
    }
}

#[tokio::test]
async fn mixed_channel_preserves_one_encrypted_sequence_across_agent_base_and_binary() {
    for base in [1, 2] {
        let n = negotiation(base);
        let (mut sender, mut receiver) = pair().await;
        for raw in [
            serde_json::to_vec(&agent()).unwrap(),
            base_bytes(base),
            BINARY_FRAME_MAGIC.to_vec(),
            serde_json::to_vec(&agent()).unwrap(),
        ] {
            sender.send_encrypted(&raw).await.unwrap();
            assert_eq!(
                receiver.receive_agent_payload(n).await.unwrap(),
                classify(&raw, n).unwrap()
            );
        }
        assert_eq!(receiver.next_receive_sequence, 4);
        sender.next_send_sequence = 0;
        sender.send_encrypted(&base_bytes(base)).await.unwrap();
        assert!(matches!(
            receiver.receive_agent_payload(n).await,
            Err(ClientError::ReplayedPacket)
        ));
    }
}

#[tokio::test]
async fn mixed_channel_rejects_unnegotiated_extension_before_consuming_any_packet() {
    let (mut sender, mut receiver) = pair().await;
    sender.send_encrypted(&base_bytes(1)).await.unwrap();
    for n in [
        v4::Negotiation {
            agent_v4: false,
            ..negotiation(1)
        },
        negotiation(3),
    ] {
        assert!(receiver.receive_agent_payload(n).await.is_err());
        assert_eq!(receiver.next_receive_sequence, 0);
    }
    assert!(matches!(
        receiver
            .receive_agent_payload(negotiation(1))
            .await
            .unwrap(),
        AgentPayload::Apple(_)
    ));
}

#[tokio::test]
async fn mixed_channel_authenticates_before_decoding() {
    let (mut sender, mut receiver) = pair().await;
    sender.session_key = [8; 32];
    sender.send_encrypted(&base_bytes(1)).await.unwrap();
    assert!(matches!(
        receiver.receive_agent_payload(negotiation(1)).await,
        Err(ClientError::Authentication(_))
    ));
    assert_eq!(receiver.next_receive_sequence, 0);
}
