use healthmd_protocol::{crypto, wire::EncryptedFrame};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
struct SharedPairingVectors {
    pairing_protocol_version: u16,
    pairing_code: String,
    client_installation_id: String,
    client_public_key_hex: String,
    client_nonce_hex: String,
    server_installation_id: String,
    server_public_key_hex: String,
    server_nonce_hex: String,
    sealed_nonce_hex: String,
    sealed_ciphertext_hex: String,
    sealed_tag_hex: String,
    pairing_client_verifier_hex: String,
    pairing_server_verifier_hex: String,
    qr_payload: String,
}

fn vectors() -> SharedPairingVectors {
    serde_json::from_str(include_str!("fixtures/shared-pairing-v3.json")).unwrap()
}

fn decode_hex(value: &str) -> Vec<u8> {
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}

#[test]
fn shared_pairing_v3_matches_canonical_fixture() {
    let fixture = vectors();
    assert_eq!(
        fixture.pairing_protocol_version,
        healthmd_protocol::SHARED_PAIRING_PROTOCOL_VERSION
    );
    let client_id = Uuid::parse_str(&fixture.client_installation_id).unwrap();
    let server_id = Uuid::parse_str(&fixture.server_installation_id).unwrap();
    let client_public = decode_hex(&fixture.client_public_key_hex);
    let client_nonce = decode_hex(&fixture.client_nonce_hex);
    let server_public = decode_hex(&fixture.server_public_key_hex);
    let server_nonce = decode_hex(&fixture.server_nonce_hex);
    let sealed = EncryptedFrame {
        nonce: decode_hex(&fixture.sealed_nonce_hex),
        ciphertext: decode_hex(&fixture.sealed_ciphertext_hex),
        tag: decode_hex(&fixture.sealed_tag_hex),
    };

    let expected_client_verifier = decode_hex(&fixture.pairing_client_verifier_hex);
    assert_eq!(
        crypto::shared_pairing_verifier(
            &fixture.pairing_code,
            client_id,
            &client_public,
            &client_nonce,
        )
        .as_slice(),
        expected_client_verifier
    );
    assert!(
        healthmd_protocol::foundation::verify_pairing_client_transcript(
            healthmd_protocol::foundation::PairingProfile::SharedV3,
            &fixture.pairing_code,
            &fixture.client_installation_id,
            &client_public,
            &client_nonce,
            &expected_client_verifier,
        )
        .unwrap()
    );
    assert_eq!(
        crypto::shared_pairing_server_verifier(
            &fixture.pairing_code,
            client_id,
            &client_public,
            &client_nonce,
            server_id,
            &server_public,
            &server_nonce,
            &sealed,
        )
        .as_slice(),
        decode_hex(&fixture.pairing_server_verifier_hex)
    );
    assert_eq!(
        fixture.qr_payload,
        "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=12345678901234567890"
    );
}
