//! RFC-0005 P2 wake requests to the consumer notifications worker.
//!
//! Best-effort only: every failure — missing configuration, unreachable worker, rejected request —
//! degrades silently to the P1 wait-only window. The request carries no health data, no dates, no
//! metric identity, and no request contents; only the opaque `wakeId`, a nonce, a timestamp, the
//! domain-separated HMAC, and this computer's display name.

use std::time::Duration;

use base64::Engine as _;
use hmac::{Hmac, Mac as _};
use serde_json::json;
use sha2::Sha256;

/// Domain separation label for wake HMACs. Must match the worker specification exactly.
pub const WAKE_HMAC_DOMAIN: &str = "healthmd.wake.v1";

const WAKE_REQUEST_TIMEOUT: Duration = Duration::from_secs(5);

/// The configured worker base URL, or `None` when wake requests are unconfigured.
#[must_use]
pub fn worker_base_url() -> Option<String> {
    base_url_from(std::env::var("HEALTHMD_WAKE_WORKER_URL").ok().as_deref())
}

#[must_use]
pub(crate) fn base_url_from(value: Option<&str>) -> Option<String> {
    let url = value?;
    let trimmed = url.trim().trim_end_matches('/');
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().fold(
        String::with_capacity(bytes.len() * 2),
        |mut output, byte| {
            use std::fmt::Write as _;
            let _ = write!(output, "{byte:02x}");
            output
        },
    )
}

fn request_hmac_hex(wake_key: &[u8], nonce_hex: &str, timestamp: &str) -> Result<String, String> {
    let mut mac = Hmac::<Sha256>::new_from_slice(wake_key)
        .map_err(|error| format!("wake key rejected: {error}"))?;
    mac.update(WAKE_HMAC_DOMAIN.as_bytes());
    mac.update(nonce_hex.as_bytes());
    mac.update(timestamp.as_bytes());
    Ok(hex(&mac.finalize().into_bytes()))
}

/// Send one wake request. Errors describe why the nudge was skipped; callers degrade to P1.
///
/// # Errors
///
/// Returns an error for key, encoding, or transport failures. HTTP error statuses are reported
/// but are equally non-fatal on the data path.
pub async fn request_wake(
    base_url: &str,
    wake_id: &str,
    wake_key: &[u8],
    peer_label: &str,
) -> Result<(), String> {
    let nonce = healthmd_protocol::crypto::random_bytes::<32>()
        .map(|bytes| hex(&bytes))
        .map_err(|error| format!("wake nonce: {error}"))?;
    let timestamp = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
    let hmac = request_hmac_hex(wake_key, &nonce, &timestamp)?;
    let client = reqwest::Client::builder()
        .timeout(WAKE_REQUEST_TIMEOUT)
        .build()
        .map_err(|error| format!("wake http client: {error}"))?;
    let response = client
        .post(format!("{base_url}/wake/request"))
        .json(&json!({
            "wakeId": wake_id,
            "nonce": nonce,
            "timestamp": timestamp,
            "hmac": hmac,
            "peerLabel": peer_label,
        }))
        .send()
        .await
        .map_err(|error| format!("wake request transport: {error}"))?;
    if !response.status().is_success() {
        return Err(format!(
            "wake request rejected with {}",
            response.status().as_u16()
        ));
    }
    Ok(())
}

/// Decode a base64 `wakeKey` enrollment payload to exactly 32 raw bytes.
pub(crate) fn decode_wake_key(encoded: &str) -> Option<Vec<u8>> {
    base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .ok()
        .filter(|bytes| bytes.len() == 32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_is_domain_separated_and_deterministic() {
        let key = [7_u8; 32];
        let first = request_hmac_hex(&key, "aa", "2026-09-03T00:00:00Z").unwrap();
        let second = request_hmac_hex(&key, "aa", "2026-09-03T00:00:00Z").unwrap();
        assert_eq!(first, second);
        assert_eq!(first.len(), 64);
        let other_nonce = request_hmac_hex(&key, "bb", "2026-09-03T00:00:00Z").unwrap();
        assert_ne!(first, other_nonce);
        let wrong_key = request_hmac_hex(&[8_u8; 32], "aa", "2026-09-03T00:00:00Z").unwrap();
        assert_ne!(first, wrong_key);
        // A manually computed vector pins the exact construction.
        let mut mac = Hmac::<Sha256>::new_from_slice(&key).unwrap();
        mac.update(b"healthmd.wake.v1");
        mac.update(b"aa");
        mac.update(b"2026-09-03T00:00:00Z");
        assert_eq!(first, hex(&mac.finalize().into_bytes()));
    }

    #[test]
    fn wake_key_decoding_rejects_wrong_lengths() {
        assert_eq!(
            decode_wake_key(&base64::engine::general_purpose::STANDARD.encode([1_u8; 32]))
                .unwrap()
                .len(),
            32
        );
        assert!(
            decode_wake_key(&base64::engine::general_purpose::STANDARD.encode([1_u8; 31]))
                .is_none()
        );
        assert!(decode_wake_key("not base64 !!").is_none());
    }

    #[test]
    fn worker_base_url_is_trimmed_and_optional() {
        assert_eq!(base_url_from(None), None);
        assert_eq!(base_url_from(Some("")), None);
        assert_eq!(base_url_from(Some("   ")), None);
        assert_eq!(
            base_url_from(Some(" https://worker.example/ ")),
            Some("https://worker.example".to_owned())
        );
    }

    #[tokio::test]
    async fn wake_request_carries_the_domain_separated_hmac_and_degrades_on_rejection() {
        use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};

        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let key = [3_u8; 32];
        let server = async {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut buffer = Vec::new();
            let mut chunk = [0_u8; 4096];
            loop {
                let read = stream.read(&mut chunk).await.unwrap();
                buffer.extend_from_slice(&chunk[..read]);
                let text = String::from_utf8_lossy(&buffer);
                if let Some(headers_end) = text.find("\r\n\r\n") {
                    let length = text
                        .lines()
                        .find_map(|line| line.strip_prefix("content-length: "))
                        .and_then(|value| value.trim().parse::<usize>().ok())
                        .unwrap();
                    if buffer.len() >= headers_end + 4 + length {
                        break;
                    }
                }
            }
            let request = String::from_utf8_lossy(&buffer).to_string();
            let body = request.split("\r\n\r\n").nth(1).unwrap().to_owned();
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 19\r\n\r\n{\"status\":\"queued\"}";
            stream.write_all(response.as_bytes()).await.unwrap();
            body
        };

        let base_url = format!("http://127.0.0.1:{port}");
        let request = request_wake(&base_url, "wake-opaque", &key, "Hermetic test CLI");
        let (result, body) = tokio::join!(request, server);
        result.expect("queued wake request succeeds");

        let payload: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(payload["wakeId"], "wake-opaque");
        assert_eq!(payload["peerLabel"], "Hermetic test CLI");
        let nonce = payload["nonce"].as_str().unwrap();
        let timestamp = payload["timestamp"].as_str().unwrap();
        assert_eq!(nonce.len(), 64);
        assert_eq!(
            payload["hmac"].as_str().unwrap(),
            request_hmac_hex(&key, nonce, timestamp).unwrap()
        );
        assert!(!body.contains("date"));
        assert!(!body.contains("metric"));

        // An unreachable worker is a silent transport error, never a data-path failure.
        let closed = request_wake(
            "http://127.0.0.1:1",
            "wake-opaque",
            &key,
            "Hermetic test CLI",
        )
        .await;
        assert!(closed.is_err());
    }
}
