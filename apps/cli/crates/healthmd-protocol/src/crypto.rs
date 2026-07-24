//! Exact v1 direct-pairing and secure-frame cryptography.

use chacha20poly1305::{
    ChaCha20Poly1305, Key, Nonce,
    aead::{Aead as _, KeyInit as _},
};
use hmac::{Hmac, Mac as _};
use sha2::{Digest as _, Sha256};
use subtle::ConstantTimeEq as _;
use thiserror::Error;
use uuid::Uuid;
use x25519_dalek::{PublicKey, StaticSecret};

use crate::wire::EncryptedFrame;

type HmacSha256 = Hmac<Sha256>;

const CODE_DOMAIN: &[u8] = b"HealthMd.DirectCLI.Code.";
const PAIRING_DOMAIN: &[u8] = b"HealthMd.DirectCLI.PairingVerifier.v1";
const SESSION_DOMAIN: &[u8] = b"HealthMd.DirectCLI.SessionKey.v1";
const TRUSTED_CLIENT_DOMAIN: &[u8] = b"HealthMd.DirectCLI.TrustedClient.v1";
const PAIRING_SERVER_DOMAIN: &[u8] = b"HealthMd.DirectCLI.PairingServer.v1";
const TRUSTED_SERVER_DOMAIN: &[u8] = b"HealthMd.DirectCLI.TrustedServer.v1";

#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("cryptographic random generation failed")]
    Random,
    #[error("the peer X25519 public key is invalid")]
    InvalidPublicKey,
    #[error("the encrypted frame is invalid")]
    InvalidEncryptedFrame,
    #[error("authenticated decryption failed")]
    AuthenticationFailed,
}

/// Generate an ephemeral X25519 private/public key pair.
///
/// # Errors
///
/// Returns an error when the operating system random source is unavailable.
pub fn ephemeral_key_pair() -> Result<(StaticSecret, [u8; 32]), CryptoError> {
    let mut private = [0_u8; 32];
    getrandom::fill(&mut private).map_err(|_| CryptoError::Random)?;
    let secret = StaticSecret::from(private);
    let public = PublicKey::from(&secret).to_bytes();
    Ok((secret, public))
}

/// Derive the raw X25519 shared secret.
///
/// # Errors
///
/// Returns an error when the peer key is not exactly 32 bytes or yields the all-zero secret.
pub fn x25519_shared_secret(
    private: &StaticSecret,
    peer_public: &[u8],
) -> Result<[u8; 32], CryptoError> {
    let peer_bytes: [u8; 32] = peer_public
        .try_into()
        .map_err(|_| CryptoError::InvalidPublicKey)?;
    let secret = private
        .diffie_hellman(&PublicKey::from(peer_bytes))
        .to_bytes();
    if bool::from(secret.ct_eq(&[0_u8; 32])) {
        return Err(CryptoError::InvalidPublicKey);
    }
    Ok(secret)
}

/// Generate cryptographically secure random bytes.
///
/// # Errors
///
/// Returns an error when the operating system random source is unavailable.
pub fn random_bytes<const N: usize>() -> Result<[u8; N], CryptoError> {
    let mut bytes = [0_u8; N];
    getrandom::fill(&mut bytes).map_err(|_| CryptoError::Random)?;
    Ok(bytes)
}

#[must_use]
pub fn pairing_verifier(
    pairing_code: &str,
    client_installation_id: Uuid,
    client_public_key: &[u8],
    client_nonce: &[u8],
) -> [u8; 32] {
    let mut transcript = PAIRING_DOMAIN.to_vec();
    append_field(
        &mut transcript,
        lowercase_uuid(client_installation_id).as_bytes(),
    );
    append_field(&mut transcript, client_public_key);
    append_field(&mut transcript, client_nonce);
    authentication_code(&pairing_code_key(pairing_code), &transcript)
}

#[must_use]
pub fn trusted_client_verifier(
    reconnect_secret: &[u8],
    client_installation_id: Uuid,
    client_public_key: &[u8],
    client_nonce: &[u8],
) -> [u8; 32] {
    let mut transcript = TRUSTED_CLIENT_DOMAIN.to_vec();
    append_field(
        &mut transcript,
        lowercase_uuid(client_installation_id).as_bytes(),
    );
    append_field(&mut transcript, client_public_key);
    append_field(&mut transcript, client_nonce);
    authentication_code(reconnect_secret, &transcript)
}

#[must_use]
pub fn session_key(shared_secret: &[u8; 32], client_nonce: &[u8], server_nonce: &[u8]) -> [u8; 32] {
    let mut transcript = SESSION_DOMAIN.to_vec();
    transcript.extend_from_slice(shared_secret);
    append_field(&mut transcript, client_nonce);
    append_field(&mut transcript, server_nonce);
    Sha256::digest(transcript).into()
}

#[allow(clippy::too_many_arguments)]
#[must_use]
pub fn pairing_server_verifier(
    pairing_code: &str,
    client_installation_id: Uuid,
    client_public_key: &[u8],
    client_nonce: &[u8],
    server_installation_id: Uuid,
    server_public_key: &[u8],
    server_nonce: &[u8],
    sealed_reconnect_secret: &EncryptedFrame,
) -> [u8; 32] {
    server_verifier(
        PAIRING_SERVER_DOMAIN,
        &pairing_code_key(pairing_code),
        client_installation_id,
        client_public_key,
        client_nonce,
        server_installation_id,
        server_public_key,
        server_nonce,
        Some(sealed_reconnect_secret),
    )
}

#[allow(clippy::too_many_arguments)]
#[must_use]
pub fn trusted_server_verifier(
    reconnect_secret: &[u8],
    client_installation_id: Uuid,
    client_public_key: &[u8],
    client_nonce: &[u8],
    server_installation_id: Uuid,
    server_public_key: &[u8],
    server_nonce: &[u8],
) -> [u8; 32] {
    server_verifier(
        TRUSTED_SERVER_DOMAIN,
        reconnect_secret,
        client_installation_id,
        client_public_key,
        client_nonce,
        server_installation_id,
        server_public_key,
        server_nonce,
        None,
    )
}

/// Seal plaintext using IETF ChaCha20-Poly1305 with empty associated data.
///
/// # Errors
///
/// Returns an error when secure nonce generation or encryption fails.
pub fn seal(plaintext: &[u8], key: &[u8; 32]) -> Result<EncryptedFrame, CryptoError> {
    let nonce = random_bytes::<12>()?;
    seal_with_nonce(plaintext, key, nonce)
}

/// Seal with an explicit nonce for cross-language conformance vectors.
///
/// # Errors
///
/// Returns an error when authenticated encryption fails.
pub fn seal_with_nonce(
    plaintext: &[u8],
    key: &[u8; 32],
    nonce: [u8; 12],
) -> Result<EncryptedFrame, CryptoError> {
    let combined = ChaCha20Poly1305::new(Key::from_slice(key))
        .encrypt(Nonce::from_slice(&nonce), plaintext)
        .map_err(|_| CryptoError::AuthenticationFailed)?;
    let split = combined
        .len()
        .checked_sub(16)
        .ok_or(CryptoError::InvalidEncryptedFrame)?;
    Ok(EncryptedFrame {
        nonce: nonce.to_vec(),
        ciphertext: combined[..split].to_vec(),
        tag: combined[split..].to_vec(),
    })
}

/// Open a Swift-compatible separated nonce/ciphertext/tag frame.
///
/// # Errors
///
/// Returns an error for malformed sizes or failed authentication.
pub fn open(frame: &EncryptedFrame, key: &[u8; 32]) -> Result<Vec<u8>, CryptoError> {
    let nonce: [u8; 12] = frame
        .nonce
        .as_slice()
        .try_into()
        .map_err(|_| CryptoError::InvalidEncryptedFrame)?;
    if frame.tag.len() != 16 {
        return Err(CryptoError::InvalidEncryptedFrame);
    }
    let mut combined = frame.ciphertext.clone();
    combined.extend_from_slice(&frame.tag);
    ChaCha20Poly1305::new(Key::from_slice(key))
        .decrypt(Nonce::from_slice(&nonce), combined.as_ref())
        .map_err(|_| CryptoError::AuthenticationFailed)
}

#[must_use]
pub fn constant_time_equal(left: &[u8], right: &[u8]) -> bool {
    left.len() == right.len() && bool::from(left.ct_eq(right))
}

#[allow(clippy::too_many_arguments)]
fn server_verifier(
    domain: &[u8],
    key: &[u8],
    client_installation_id: Uuid,
    client_public_key: &[u8],
    client_nonce: &[u8],
    server_installation_id: Uuid,
    server_public_key: &[u8],
    server_nonce: &[u8],
    sealed_reconnect_secret: Option<&EncryptedFrame>,
) -> [u8; 32] {
    let mut transcript = domain.to_vec();
    append_field(
        &mut transcript,
        lowercase_uuid(client_installation_id).as_bytes(),
    );
    append_field(&mut transcript, client_public_key);
    append_field(&mut transcript, client_nonce);
    append_field(
        &mut transcript,
        lowercase_uuid(server_installation_id).as_bytes(),
    );
    append_field(&mut transcript, server_public_key);
    append_field(&mut transcript, server_nonce);
    if let Some(frame) = sealed_reconnect_secret {
        transcript.push(1);
        append_field(&mut transcript, &frame.nonce);
        append_field(&mut transcript, &frame.ciphertext);
        append_field(&mut transcript, &frame.tag);
    } else {
        transcript.push(0);
    }
    authentication_code(key, &transcript)
}

fn pairing_code_key(pairing_code: &str) -> [u8; 32] {
    let normalized: String = pairing_code.chars().filter(char::is_ascii_digit).collect();
    let mut value = CODE_DOMAIN.to_vec();
    value.extend_from_slice(normalized.as_bytes());
    Sha256::digest(value).into()
}

fn authentication_code(key: &[u8], payload: &[u8]) -> [u8; 32] {
    let mut hmac =
        <HmacSha256 as hmac::Mac>::new_from_slice(key).expect("HMAC accepts arbitrary key lengths");
    hmac.update(payload);
    hmac.finalize().into_bytes().into()
}

fn append_field(payload: &mut Vec<u8>, field: &[u8]) {
    payload.extend_from_slice(&(field.len() as u64).to_be_bytes());
    payload.extend_from_slice(field);
}

fn lowercase_uuid(id: Uuid) -> String {
    id.hyphenated().to_string().to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direct_pairing_is_domain_separated_and_deterministic() {
        let id = Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap();
        let verifier = pairing_verifier("123 456", id, &[7; 32], &[9; 32]);
        assert_eq!(
            hex(&verifier),
            "23c462858ee1999603dd5fc2062eb264d4292b9f1f7a1f0907680c9f46e06064"
        );
    }

    #[test]
    #[allow(clippy::cast_possible_truncation)]
    fn full_direct_crypto_transcript_matches_cross_language_vector() {
        let client_id = Uuid::parse_str("abcdefab-cdef-4abc-8def-abcdefabcdef").unwrap();
        let server_id = Uuid::parse_str("01234567-89ab-4cde-8fab-0123456789ab").unwrap();
        let client_private = StaticSecret::from(std::array::from_fn(|index| index as u8));
        let server_private = StaticSecret::from(std::array::from_fn(|index| 0x20_u8 + index as u8));
        let client_public = PublicKey::from(&client_private).to_bytes();
        let server_public = PublicKey::from(&server_private).to_bytes();
        let client_nonce: [u8; 32] = std::array::from_fn(|index| 0x40_u8 + index as u8);
        let server_nonce: [u8; 32] = std::array::from_fn(|index| 0x60_u8 + index as u8);
        let reconnect_secret: [u8; 32] = std::array::from_fn(|index| 0x80_u8 + index as u8);

        assert_eq!(
            hex(&client_public),
            "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f"
        );
        assert_eq!(
            hex(&server_public),
            "358072d6365880d1aeea329adf9121383851ed21a28e3b75e965d0d2cd166254"
        );
        let shared = x25519_shared_secret(&client_private, &server_public).unwrap();
        assert_eq!(
            hex(&shared),
            "9663aa1da97e848a914a436d04163dfbb89178f107f1b5b77ed3854203382854"
        );
        assert_eq!(
            hex(&pairing_code_key("123456")),
            "658f6348a2d3447618f6cb5fb2a74782a814701c5698ce4d0ed9c9e2ba048389"
        );
        assert_eq!(
            hex(&pairing_verifier(
                "123456",
                client_id,
                &client_public,
                &client_nonce
            )),
            "9dadfaf54d6729b004aa0a6344f7df42b4de0093cbf5cca6fe62376acbad00df"
        );
        let key = session_key(&shared, &client_nonce, &server_nonce);
        assert_eq!(
            hex(&key),
            "47cea6b163b799c16e44a750893eab311521060a7266a59ec054d53f71b698e9"
        );
        let sealed = seal_with_nonce(
            &reconnect_secret,
            &key,
            std::array::from_fn(|index| 0xa0_u8 + index as u8),
        )
        .unwrap();
        assert_eq!(
            hex(&sealed.ciphertext),
            "4798e04752b793b6a368cdf50a84733ac50a881e0e0518ee1a951a2ec9f874bc"
        );
        assert_eq!(hex(&sealed.tag), "16a9167d55402161d3f1794b4e10a26c");
        assert_eq!(
            hex(&pairing_server_verifier(
                "123456",
                client_id,
                &client_public,
                &client_nonce,
                server_id,
                &server_public,
                &server_nonce,
                &sealed
            )),
            "736b8a07a3d7b30ce719c6c7e20bcd25276d800548218409465161560fe51abc"
        );
        assert_eq!(
            hex(&trusted_client_verifier(
                &reconnect_secret,
                client_id,
                &client_public,
                &client_nonce
            )),
            "6fb78dd56d1a7eaebbf22d2ce5d4b153c61c46771d38a3685c37cb57780625ec"
        );
        assert_eq!(
            hex(&trusted_server_verifier(
                &reconnect_secret,
                client_id,
                &client_public,
                &client_nonce,
                server_id,
                &server_public,
                &server_nonce
            )),
            "17a39d5598ec4586b96f8a51c1f16778a62edf17bfe77a96267729944e3537d0"
        );
        let secure_plaintext = [b"HMDSC001".as_slice(), &[0_u8; 8], br#"{"ping":{}}"#].concat();
        let secure_frame = seal_with_nonce(
            &secure_plaintext,
            &key,
            std::array::from_fn(|index| 0xb0_u8 + index as u8),
        )
        .unwrap();
        assert_eq!(
            hex(&secure_frame.ciphertext),
            "819e3a9ebc272b8b43406321a5578a98f4397b2b901fc4dc5b2090"
        );
        assert_eq!(hex(&secure_frame.tag), "67096280627ec949ee122d0bc2e621e4");
    }

    #[test]
    fn sealed_frame_round_trips_and_rejects_mutation() {
        let key = [0x42; 32];
        let nonce = [0x24; 12];
        let mut frame = seal_with_nonce(b"healthmd", &key, nonce).unwrap();
        assert_eq!(open(&frame, &key).unwrap(), b"healthmd");
        frame.tag[0] ^= 1;
        assert!(matches!(
            open(&frame, &key),
            Err(CryptoError::AuthenticationFailed)
        ));
    }

    fn hex(bytes: &[u8]) -> String {
        use std::fmt::Write as _;
        bytes.iter().fold(String::new(), |mut output, byte| {
            write!(output, "{byte:02x}").expect("writing to a string succeeds");
            output
        })
    }
}
