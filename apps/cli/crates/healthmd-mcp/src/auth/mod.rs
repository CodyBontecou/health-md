mod jwt;

use std::{
    collections::BTreeSet,
    fmt::{self, Write as _},
};

use async_trait::async_trait;
use secrecy::SecretString;
use serde_json::{Value, json};
use url::Url;

pub use jwt::{JwtJwksVerifier, JwtJwksVerifierConfig};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OAuthPrincipal {
    pub subject: String,
    pub tenant: Option<String>,
    pub issuer: String,
    pub audience: String,
    pub scopes: BTreeSet<String>,
}

impl OAuthPrincipal {
    pub fn caller_identity(&self) -> crate::CallerIdentity {
        crate::CallerIdentity {
            subject: self.subject.clone(),
            tenant: self.tenant.clone(),
            issuer: Some(self.issuer.clone()),
            scopes: self.scopes.clone(),
            mode: crate::CallerMode::OAuth,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthorizationErrorKind {
    InvalidToken,
    TemporarilyUnavailable,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthorizationError {
    pub kind: AuthorizationErrorKind,
    pub message: &'static str,
}

impl AuthorizationError {
    pub const fn invalid_token() -> Self {
        Self {
            kind: AuthorizationErrorKind::InvalidToken,
            message: "The bearer token is invalid or expired.",
        }
    }

    pub const fn temporarily_unavailable() -> Self {
        Self {
            kind: AuthorizationErrorKind::TemporarilyUnavailable,
            message: "Token verification is temporarily unavailable.",
        }
    }
}

impl fmt::Display for AuthorizationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message)
    }
}

impl std::error::Error for AuthorizationError {}

#[async_trait]
pub trait AccessTokenVerifier: Send + Sync {
    async fn verify(&self, token: SecretString) -> Result<OAuthPrincipal, AuthorizationError>;
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OAuthResourceServerConfig {
    pub resource: Url,
    pub authorization_servers: Vec<Url>,
    /// Scopes advertised through protected-resource metadata.
    pub scopes_supported: BTreeSet<String>,
    /// Scopes required for every route. Hosted services normally leave this empty and enforce
    /// least-privilege scopes at the MCP backend or data-plane endpoint instead.
    pub required_scopes: BTreeSet<String>,
    pub owner_subject: Option<String>,
}

impl OAuthResourceServerConfig {
    /// Create protected-resource metadata and request policy.
    ///
    /// # Errors
    ///
    /// Returns an error for an empty authorization-server list or a non-HTTPS, non-loopback URL.
    pub fn new(
        resource: Url,
        authorization_servers: Vec<Url>,
        required_scopes: impl IntoIterator<Item = impl Into<String>>,
    ) -> Result<Self, OAuthConfigurationError> {
        validate_secure_url(&resource)?;
        if authorization_servers.is_empty() {
            return Err(OAuthConfigurationError::MissingAuthorizationServer);
        }
        for server in &authorization_servers {
            validate_secure_url(server)?;
        }
        let scopes_supported: BTreeSet<String> =
            required_scopes.into_iter().map(Into::into).collect();
        Ok(Self {
            resource,
            authorization_servers,
            required_scopes: scopes_supported.clone(),
            scopes_supported,
            owner_subject: None,
        })
    }

    /// Override the scopes required on every protected route. This can be empty when individual
    /// MCP calls and HTTP endpoints enforce narrower scopes themselves.
    #[must_use]
    pub fn with_required_scopes(
        mut self,
        scopes: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        self.required_scopes = scopes.into_iter().map(Into::into).collect();
        self
    }

    #[must_use]
    pub fn with_owner_subject(mut self, subject: impl Into<String>) -> Self {
        self.owner_subject = Some(subject.into());
        self
    }

    pub fn protected_resource_metadata_path(&self) -> String {
        let suffix = self.resource.path().trim_start_matches('/');
        if suffix.is_empty() {
            "/.well-known/oauth-protected-resource".to_owned()
        } else {
            format!("/.well-known/oauth-protected-resource/{suffix}")
        }
    }

    pub fn protected_resource_metadata_url(&self) -> Url {
        let mut url = self.resource.clone();
        url.set_path(&self.protected_resource_metadata_path());
        url.set_query(None);
        url.set_fragment(None);
        url
    }

    pub fn metadata(&self) -> Value {
        json!({
            "resource": self.resource.as_str(),
            "authorization_servers": self
                .authorization_servers
                .iter()
                .map(Url::as_str)
                .collect::<Vec<_>>(),
            "scopes_supported": self.scopes_supported.iter().collect::<Vec<_>>(),
            "bearer_methods_supported": ["header"],
            "resource_documentation": "https://health.md/docs/mcp"
        })
    }

    pub fn challenge(&self, error: Option<&str>, description: Option<&str>) -> String {
        self.challenge_for_scopes(&self.required_scopes, error, description)
    }

    pub fn challenge_for_scopes(
        &self,
        scopes: &BTreeSet<String>,
        error: Option<&str>,
        description: Option<&str>,
    ) -> String {
        let scopes = scopes.iter().cloned().collect::<Vec<_>>().join(" ");
        let mut challenge = format!(
            "Bearer resource_metadata=\"{}\"",
            self.protected_resource_metadata_url()
        );
        if !scopes.is_empty() {
            let _ = write!(challenge, ", scope=\"{scopes}\"");
        }
        if let Some(error) = error {
            let _ = write!(challenge, ", error=\"{error}\"");
        }
        if let Some(description) = description {
            let sanitized: String = description
                .chars()
                .filter(|character| character.is_ascii_graphic() || *character == ' ')
                .filter(|character| !matches!(character, '"' | '\\'))
                .collect();
            let _ = write!(challenge, ", error_description=\"{sanitized}\"");
        }
        challenge
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OAuthConfigurationError {
    InsecureUrl,
    MissingAuthorizationServer,
}

impl fmt::Display for OAuthConfigurationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InsecureUrl => formatter.write_str(
                "OAuth resource and authorization-server URLs must use HTTPS or loopback HTTP",
            ),
            Self::MissingAuthorizationServer => {
                formatter.write_str("at least one OAuth authorization server is required")
            }
        }
    }
}

impl std::error::Error for OAuthConfigurationError {}

fn validate_secure_url(url: &Url) -> Result<(), OAuthConfigurationError> {
    if url.scheme() == "https" {
        return Ok(());
    }
    let loopback_http = url.scheme() == "http"
        && url
            .host_str()
            .is_some_and(|host| matches!(host, "localhost" | "127.0.0.1" | "::1"));
    if loopback_http {
        Ok(())
    } else {
        Err(OAuthConfigurationError::InsecureUrl)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protected_resource_metadata_is_path_specific_and_scope_minimal() {
        let config = OAuthResourceServerConfig::new(
            Url::parse("https://mcp.health.md/mcp").unwrap(),
            vec![Url::parse("https://auth.health.md").unwrap()],
            ["healthmd:read"],
        )
        .unwrap();
        assert_eq!(
            config.protected_resource_metadata_path(),
            "/.well-known/oauth-protected-resource/mcp"
        );
        assert_eq!(
            config.protected_resource_metadata_url().as_str(),
            "https://mcp.health.md/.well-known/oauth-protected-resource/mcp"
        );
        assert_eq!(config.metadata()["resource"], "https://mcp.health.md/mcp");
        assert_eq!(
            config.metadata()["scopes_supported"],
            json!(["healthmd:read"])
        );
        let challenge = config.challenge(Some("invalid_token"), Some("Login required"));
        assert!(challenge.contains(
            "resource_metadata=\"https://mcp.health.md/.well-known/oauth-protected-resource/mcp\""
        ));
        assert!(challenge.contains("scope=\"healthmd:read\""));
    }

    #[test]
    fn hosted_metadata_can_advertise_scopes_without_requiring_all_of_them_globally() {
        let config = OAuthResourceServerConfig::new(
            Url::parse("https://mcp.health.md/mcp").unwrap(),
            vec![Url::parse("https://auth.health.md").unwrap()],
            [
                "health.summary.read",
                "health.detail.read",
                "health.account.manage",
            ],
        )
        .unwrap()
        .with_required_scopes(std::iter::empty::<&str>());
        assert!(config.required_scopes.is_empty());
        assert_eq!(
            config.metadata()["scopes_supported"],
            json!([
                "health.account.manage",
                "health.detail.read",
                "health.summary.read"
            ])
        );
        assert!(!config.challenge(None, None).contains("scope="));
    }

    #[test]
    fn oauth_urls_reject_cleartext_non_loopback_origins() {
        assert!(
            OAuthResourceServerConfig::new(
                Url::parse("http://mcp.example.com/mcp").unwrap(),
                vec![Url::parse("https://auth.example.com").unwrap()],
                ["healthmd:read"],
            )
            .is_err()
        );
        assert!(
            OAuthResourceServerConfig::new(
                Url::parse("http://127.0.0.1:8787/mcp").unwrap(),
                vec![Url::parse("http://127.0.0.1:8788").unwrap()],
                ["healthmd:read"],
            )
            .is_ok()
        );
    }
}
