use std::{collections::BTreeSet, sync::Arc, time::Duration};

use async_trait::async_trait;
use jsonwebtoken::{
    Algorithm, DecodingKey, Validation, decode, decode_header,
    jwk::{AlgorithmParameters, Jwk, JwkSet, KeyOperations, PublicKeyUse},
};
use secrecy::{ExposeSecret as _, SecretString};
use serde_json::Value;
use tokio::{sync::Mutex, time::Instant};
use url::Url;

use super::{
    AccessTokenVerifier, AuthorizationError, OAuthConfigurationError, OAuthPrincipal,
    validate_secure_url,
};

const MAXIMUM_TOKEN_BYTES: usize = 16 * 1_024;
const MAXIMUM_JWKS_BYTES: usize = 1_024 * 1_024;
const MAXIMUM_JWKS_KEYS: usize = 128;

#[derive(Clone, Debug)]
pub struct JwtJwksVerifierConfig {
    pub issuer: Url,
    pub resource: Url,
    pub jwks_uri: Url,
    pub algorithms: Vec<Algorithm>,
    pub cache_ttl: Duration,
    pub minimum_refresh_interval: Duration,
    pub tenant_claim: Option<String>,
}

impl JwtJwksVerifierConfig {
    /// Create a verifier configuration with bounded secure defaults.
    ///
    /// # Errors
    ///
    /// Returns an error when any configured URL is neither HTTPS nor loopback HTTP.
    pub fn new(issuer: Url, resource: Url, jwks_uri: Url) -> Result<Self, OAuthConfigurationError> {
        validate_secure_url(&issuer)?;
        validate_secure_url(&resource)?;
        validate_secure_url(&jwks_uri)?;
        Ok(Self {
            issuer,
            resource,
            jwks_uri,
            algorithms: vec![Algorithm::RS256, Algorithm::ES256, Algorithm::EdDSA],
            cache_ttl: Duration::from_secs(300),
            minimum_refresh_interval: Duration::from_secs(30),
            tenant_claim: None,
        })
    }
}

pub struct JwtJwksVerifier {
    configuration: JwtJwksVerifierConfig,
    client: reqwest::Client,
    cache: Mutex<JwksCache>,
}

#[derive(Default)]
struct JwksCache {
    current: Option<CachedJwks>,
    last_refresh_attempt: Option<Instant>,
    last_refresh_failed: bool,
}

struct CachedJwks {
    fetched_at: Instant,
    set: Arc<JwkSet>,
}

impl JwtJwksVerifier {
    /// Create the bounded JWKS verifier and its no-redirect HTTP client.
    ///
    /// # Errors
    ///
    /// Returns a stable authorization error for unsafe algorithms or HTTP-client setup failure.
    pub fn new(configuration: JwtJwksVerifierConfig) -> Result<Self, AuthorizationError> {
        if configuration.algorithms.is_empty()
            || configuration
                .algorithms
                .iter()
                .any(|algorithm| format!("{algorithm:?}").starts_with("HS"))
        {
            return Err(AuthorizationError::invalid_token());
        }
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(5))
            .build()
            .map_err(|_| AuthorizationError::temporarily_unavailable())?;
        Ok(Self {
            configuration,
            client,
            cache: Mutex::new(JwksCache::default()),
        })
    }

    async fn key(&self, key_id: &str, algorithm: Algorithm) -> Result<Jwk, AuthorizationError> {
        let mut cache = self.cache.lock().await;
        let mut cached_key_exists = false;
        if let Some(cached) = cache.current.as_ref() {
            let age = cached.fetched_at.elapsed();
            if let Some(key) = cached.set.find(key_id) {
                cached_key_exists = true;
                if age <= self.configuration.cache_ttl {
                    return validate_jwk(key, algorithm);
                }
            } else if age < self.configuration.minimum_refresh_interval {
                return Err(AuthorizationError::invalid_token());
            }
        }
        if cache
            .last_refresh_attempt
            .is_some_and(|attempt| attempt.elapsed() < self.configuration.minimum_refresh_interval)
        {
            return if cache.last_refresh_failed || cached_key_exists {
                Err(AuthorizationError::temporarily_unavailable())
            } else {
                Err(AuthorizationError::invalid_token())
            };
        }

        cache.last_refresh_attempt = Some(Instant::now());
        cache.last_refresh_failed = true;
        let set = Arc::new(self.fetch_jwks().await?);
        cache.last_refresh_failed = false;
        cache.current = Some(CachedJwks {
            fetched_at: Instant::now(),
            set: Arc::clone(&set),
        });
        set.find(key_id)
            .ok_or_else(AuthorizationError::invalid_token)
            .and_then(|key| validate_jwk(key, algorithm))
    }

    async fn fetch_jwks(&self) -> Result<JwkSet, AuthorizationError> {
        let mut response = self
            .client
            .get(self.configuration.jwks_uri.clone())
            .send()
            .await
            .map_err(|_| AuthorizationError::temporarily_unavailable())?;
        if !response.status().is_success() {
            return Err(AuthorizationError::temporarily_unavailable());
        }
        if response
            .content_length()
            .is_some_and(|length| length > MAXIMUM_JWKS_BYTES as u64)
        {
            return Err(AuthorizationError::temporarily_unavailable());
        }
        let mut bytes = Vec::with_capacity(
            response
                .content_length()
                .and_then(|length| usize::try_from(length).ok())
                .unwrap_or(0)
                .min(MAXIMUM_JWKS_BYTES),
        );
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|_| AuthorizationError::temporarily_unavailable())?
        {
            if chunk.len() > MAXIMUM_JWKS_BYTES.saturating_sub(bytes.len()) {
                return Err(AuthorizationError::temporarily_unavailable());
            }
            bytes.extend_from_slice(&chunk);
        }
        let set: JwkSet = serde_json::from_slice(&bytes)
            .map_err(|_| AuthorizationError::temporarily_unavailable())?;
        if set.keys.is_empty() || set.keys.len() > MAXIMUM_JWKS_KEYS {
            return Err(AuthorizationError::temporarily_unavailable());
        }
        let mut key_ids = BTreeSet::new();
        for key in &set.keys {
            let key_id = key
                .common
                .key_id
                .as_deref()
                .filter(|key_id| !key_id.is_empty())
                .ok_or_else(AuthorizationError::temporarily_unavailable)?;
            if !key_ids.insert(key_id) {
                return Err(AuthorizationError::temporarily_unavailable());
            }
        }
        Ok(set)
    }
}

#[async_trait]
impl AccessTokenVerifier for JwtJwksVerifier {
    async fn verify(&self, token: SecretString) -> Result<OAuthPrincipal, AuthorizationError> {
        let token = token.expose_secret();
        if token.is_empty() || token.len() > MAXIMUM_TOKEN_BYTES {
            return Err(AuthorizationError::invalid_token());
        }
        let header = decode_header(token).map_err(|_| AuthorizationError::invalid_token())?;
        if !self.configuration.algorithms.contains(&header.alg) {
            return Err(AuthorizationError::invalid_token());
        }
        let key_id = header
            .kid
            .as_deref()
            .filter(|key_id| !key_id.is_empty())
            .ok_or_else(AuthorizationError::invalid_token)?;
        let jwk = self.key(key_id, header.alg).await?;
        let decoding_key =
            DecodingKey::from_jwk(&jwk).map_err(|_| AuthorizationError::invalid_token())?;
        let mut validation = Validation::new(header.alg);
        // The header was already checked against our explicit allowlist. `jsonwebtoken` requires
        // every entry to use the decoding key's family, so validate only the exact header
        // algorithm instead of mixing RSA, EC, and EdDSA families.
        validation.algorithms = vec![header.alg];
        validation.set_audience(&[self.configuration.resource.as_str()]);
        validation.set_issuer(&[self.configuration.issuer.as_str()]);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        validation.validate_nbf = true;
        validation.leeway = 30;
        let data = decode::<Value>(token, &decoding_key, &validation)
            .map_err(|_| AuthorizationError::invalid_token())?;
        let subject = data
            .claims
            .get("sub")
            .and_then(Value::as_str)
            .filter(|subject| !subject.is_empty())
            .ok_or_else(AuthorizationError::invalid_token)?
            .to_owned();
        let scopes = token_scopes(&data.claims)?;
        let tenant = self
            .configuration
            .tenant_claim
            .as_ref()
            .map(|claim| {
                data.claims
                    .get(claim)
                    .and_then(Value::as_str)
                    .filter(|tenant| !tenant.is_empty())
                    .map(str::to_owned)
                    .ok_or_else(AuthorizationError::invalid_token)
            })
            .transpose()?;
        Ok(OAuthPrincipal {
            subject,
            tenant,
            issuer: self.configuration.issuer.as_str().to_owned(),
            audience: self.configuration.resource.as_str().to_owned(),
            scopes,
        })
    }
}

fn validate_jwk(key: &Jwk, algorithm: Algorithm) -> Result<Jwk, AuthorizationError> {
    if matches!(key.algorithm, AlgorithmParameters::OctetKey(_)) {
        return Err(AuthorizationError::invalid_token());
    }
    if key.common.public_key_use == Some(PublicKeyUse::Encryption) {
        return Err(AuthorizationError::invalid_token());
    }
    if key
        .common
        .key_operations
        .as_ref()
        .is_some_and(|operations| !operations.contains(&KeyOperations::Verify))
    {
        return Err(AuthorizationError::invalid_token());
    }
    if key
        .common
        .key_algorithm
        .is_some_and(|key_algorithm| key_algorithm.to_string() != format!("{algorithm:?}"))
    {
        return Err(AuthorizationError::invalid_token());
    }
    Ok(key.clone())
}

fn token_scopes(claims: &Value) -> Result<BTreeSet<String>, AuthorizationError> {
    let mut scopes = BTreeSet::new();
    if let Some(scope) = claims.get("scope") {
        let scope = scope
            .as_str()
            .ok_or_else(AuthorizationError::invalid_token)?;
        scopes.extend(scope.split_ascii_whitespace().map(str::to_owned));
    }
    if let Some(scope) = claims.get("scp") {
        match scope {
            Value::String(scope) => {
                scopes.extend(scope.split_ascii_whitespace().map(str::to_owned));
            }
            Value::Array(values) => {
                for value in values {
                    let value = value
                        .as_str()
                        .filter(|value| !value.is_empty())
                        .ok_or_else(AuthorizationError::invalid_token)?;
                    scopes.insert(value.to_owned());
                }
            }
            _ => return Err(AuthorizationError::invalid_token()),
        }
    }
    Ok(scopes)
}

#[cfg(test)]
mod tests {
    use std::sync::{
        OnceLock,
        atomic::{AtomicUsize, Ordering},
    };

    use axum::{Json, Router, http::StatusCode, routing::get};
    use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
    use jsonwebtoken::{EncodingKey, Header, encode};
    use rsa::{
        RsaPrivateKey, pkcs1::EncodeRsaPrivateKey as _, rand_core::OsRng,
        traits::PublicKeyParts as _,
    };
    use serde_json::json;
    use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};

    use super::*;
    use crate::auth::AuthorizationErrorKind;

    struct TestRsaKey {
        private_der: Vec<u8>,
        modulus: String,
        exponent: String,
    }

    fn test_rsa_key() -> &'static TestRsaKey {
        static KEY: OnceLock<TestRsaKey> = OnceLock::new();
        KEY.get_or_init(|| {
            let private_key = RsaPrivateKey::new(&mut OsRng, 2_048).unwrap();
            let public_key = private_key.to_public_key();
            TestRsaKey {
                private_der: private_key.to_pkcs1_der().unwrap().as_bytes().to_vec(),
                modulus: URL_SAFE_NO_PAD.encode(public_key.n().to_bytes_be()),
                exponent: URL_SAFE_NO_PAD.encode(public_key.e().to_bytes_be()),
            }
        })
    }

    async fn verifier_fixture() -> (
        JwtJwksVerifier,
        tokio::task::JoinHandle<()>,
        String,
        String,
        Arc<AtomicUsize>,
    ) {
        let key = test_rsa_key();
        let jwks = json!({
            "keys": [{
                "kty": "RSA",
                "n": key.modulus,
                "e": key.exponent,
                "kid": "healthmd-test-key",
                "alg": "RS256",
                "use": "sig"
            }]
        });
        let requests = Arc::new(AtomicUsize::new(0));
        let counted_requests = Arc::clone(&requests);
        let router = Router::new().route(
            "/jwks",
            get(move || {
                counted_requests.fetch_add(1, Ordering::Relaxed);
                let jwks = jwks.clone();
                async move { Json(jwks) }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let _ = axum::serve(listener, router).await;
        });
        let issuer_base = format!("http://{address}");
        let issuer = format!("{issuer_base}/");
        let resource = "http://127.0.0.1:8787/mcp".to_owned();
        let configuration = JwtJwksVerifierConfig::new(
            Url::parse(&issuer).unwrap(),
            Url::parse(&resource).unwrap(),
            Url::parse(&format!("{issuer_base}/jwks")).unwrap(),
        )
        .unwrap();
        (
            JwtJwksVerifier::new(configuration).unwrap(),
            task,
            issuer,
            resource,
            requests,
        )
    }

    fn token(issuer: &str, audience: &str, expiration: u64) -> String {
        let mut header = Header::new(Algorithm::RS256);
        header.kid = Some("healthmd-test-key".to_owned());
        encode(
            &header,
            &json!({
                "iss": issuer,
                "aud": audience,
                "sub": "healthmd-user",
                "exp": expiration,
                "nbf": expiration.saturating_sub(600),
                "scope": "healthmd:read profile"
            }),
            &EncodingKey::from_rsa_der(&test_rsa_key().private_der),
        )
        .unwrap()
    }

    #[tokio::test]
    async fn jwks_verifier_enforces_signature_issuer_audience_expiry_and_scopes() {
        let (verifier, task, issuer, resource, _requests) = verifier_fixture().await;
        let now = jsonwebtoken::get_current_timestamp();
        let principal = verifier
            .verify(SecretString::from(token(&issuer, &resource, now + 300)))
            .await
            .unwrap();
        assert_eq!(principal.subject, "healthmd-user");
        assert_eq!(principal.audience, resource);
        assert!(principal.scopes.contains("healthmd:read"));

        assert!(
            verifier
                .verify(SecretString::from(token(
                    &issuer,
                    "http://127.0.0.1:8787/other",
                    now + 300,
                )))
                .await
                .is_err()
        );
        assert!(
            verifier
                .verify(SecretString::from(token(&issuer, &resource, now - 120)))
                .await
                .is_err()
        );
        task.abort();
    }

    #[tokio::test]
    async fn unknown_key_ids_share_one_throttled_successful_jwks_refresh() {
        let (verifier, task, _issuer, _resource, requests) = verifier_fixture().await;
        assert!(verifier.key("unknown-one", Algorithm::RS256).await.is_err());
        assert!(verifier.key("unknown-two", Algorithm::RS256).await.is_err());
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        task.abort();
    }

    #[tokio::test]
    async fn failed_jwks_refresh_attempts_are_throttled() {
        let requests = Arc::new(AtomicUsize::new(0));
        let counted_requests = Arc::clone(&requests);
        let router = Router::new().route(
            "/jwks",
            get(move || {
                counted_requests.fetch_add(1, Ordering::Relaxed);
                async { StatusCode::SERVICE_UNAVAILABLE }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let _ = axum::serve(listener, router).await;
        });
        let base = format!("http://{address}");
        let configuration = JwtJwksVerifierConfig::new(
            Url::parse(&base).unwrap(),
            Url::parse("http://127.0.0.1:8787/mcp").unwrap(),
            Url::parse(&format!("{base}/jwks")).unwrap(),
        )
        .unwrap();
        let verifier = JwtJwksVerifier::new(configuration).unwrap();
        assert_eq!(
            verifier
                .key("unknown-one", Algorithm::RS256)
                .await
                .unwrap_err()
                .kind,
            AuthorizationErrorKind::TemporarilyUnavailable
        );
        assert_eq!(
            verifier
                .key("unknown-two", Algorithm::RS256)
                .await
                .unwrap_err()
                .kind,
            AuthorizationErrorKind::TemporarilyUnavailable
        );
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        task.abort();
    }

    #[tokio::test]
    async fn chunked_jwks_responses_are_rejected_at_the_incremental_byte_limit() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0_u8; 4_096];
            let _ = stream.read(&mut request).await;
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n")
                .await
                .unwrap();
            let chunk = vec![b'x'; 16 * 1_024];
            for _ in 0..65 {
                if stream
                    .write_all(format!("{:x}\r\n", chunk.len()).as_bytes())
                    .await
                    .is_err()
                {
                    return;
                }
                if stream.write_all(&chunk).await.is_err()
                    || stream.write_all(b"\r\n").await.is_err()
                {
                    return;
                }
            }
            let _ = stream.write_all(b"0\r\n\r\n").await;
        });
        let base = format!("http://{address}");
        let configuration = JwtJwksVerifierConfig::new(
            Url::parse(&base).unwrap(),
            Url::parse("http://127.0.0.1:8787/mcp").unwrap(),
            Url::parse(&format!("{base}/jwks")).unwrap(),
        )
        .unwrap();
        let verifier = JwtJwksVerifier::new(configuration).unwrap();
        assert!(verifier.fetch_jwks().await.is_err());
        task.abort();
    }

    #[test]
    fn scope_claims_are_normalized_and_malformed_values_fail_closed() {
        assert_eq!(
            token_scopes(&serde_json::json!({
                "scope": "healthmd:read profile",
                "scp": ["healthmd:export", "healthmd:read"]
            }))
            .unwrap(),
            BTreeSet::from([
                "healthmd:export".to_owned(),
                "healthmd:read".to_owned(),
                "profile".to_owned()
            ])
        );
        assert!(token_scopes(&serde_json::json!({"scope": ["healthmd:read"]})).is_err());
    }

    #[test]
    fn jwt_configuration_rejects_insecure_jwks_origins() {
        assert!(
            JwtJwksVerifierConfig::new(
                Url::parse("https://auth.example.com").unwrap(),
                Url::parse("https://mcp.example.com/mcp").unwrap(),
                Url::parse("http://auth.example.com/jwks").unwrap(),
            )
            .is_err()
        );
    }
}
