#![forbid(unsafe_code)]

//! Pure, deterministic Health.md shared-core primitives.
//!
//! This crate owns no platform APIs, I/O, networking, persistence, or `UniFFI` code. Its public
//! errors contain stable codes and static, health-free messages.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

pub mod registry;
pub mod render;
pub mod semantic;

/// Version of the coarse Rust/UniFFI API contract.
pub const CORE_API_VERSION: u32 = 4;
/// Core API value embedded in immutable semantic-result v1 bytes.
pub const SEMANTIC_RESULT_CORE_API_VERSION: u32 = 3;
/// Version of the semantic native-to-core input contract.
pub const SEMANTIC_INPUT_VERSION: u32 = 1;
/// Version of the internal normalized canonical result model.
pub const CANONICAL_MODEL_VERSION: u32 = 1;
/// Version of the core registry contract.
pub const REGISTRY_VERSION: u32 = 1;
/// SHA-256 of the exact embedded registry inventory for this build.
pub const REGISTRY_SHA256: &str =
    "1cc9aaf41cb92a2e903487756cf561f0ff44b9518f3ef66d1a45a997f770248d";
/// Source revision supplied by reproducible native packaging scripts.
pub const CORE_SOURCE_REVISION: &str = match option_env!("HEALTHMD_CORE_SOURCE_REVISION") {
    Some(revision) => revision,
    None => "development",
};
/// Version of the core-owned persisted-state contract.
pub const PERSISTED_STATE_VERSION: u32 = 1;
/// Version of the deterministic fixture envelope used by this milestone.
pub const FIXTURE_FORMAT_VERSION: u32 = 1;
/// Maximum fixture size accepted at the shared-core boundary.
pub const MAX_FIXTURE_BYTES: usize = 1_048_576;

const MAX_CASE_ID_BYTES: usize = 64;
const MAX_FIXTURE_RECORDS: usize = 4_096;
const SELF_TEST_FIXTURE: &[u8] = include_bytes!("../fixtures/m1-self-test.json");
const SELF_TEST_FIXTURE_SHA256: &str =
    "afb53fde32e77e4b8272f021c262a42b7f943f8604ca7fde4c6dbf7ed977a799";

/// Independently versioned build information for native compatibility checks.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BuildInfo {
    /// Rust package version. This does not imply a public schema version.
    pub crate_version: String,
    /// Git/source revision used by native packaging; `development` outside a stamped build.
    pub core_source_revision: String,
    /// Exact SHA-256 of the embedded metric/profile registry.
    pub registry_sha256: String,
    /// Coarse core API contract version.
    pub core_api_version: u32,
    /// Semantic native-to-core input contract version.
    pub semantic_input_version: u32,
    /// Internal normalized canonical result model version.
    pub canonical_model_version: u32,
    /// Registry contract version.
    pub registry_version: u32,
    /// Render native-to-core input contract version.
    pub render_input_version: u32,
    /// Destination-neutral artifact-plan contract version.
    pub artifact_plan_version: u32,
    /// Profile renderer implementation revision.
    pub render_profile_revision: u32,
    /// Persisted-state contract version.
    pub persisted_state_version: u32,
}

/// Health-free evidence that a deterministic fixture passed validation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FixtureValidation {
    /// Validated fixture-envelope version.
    pub fixture_format_version: u32,
    /// Validated byte count.
    pub byte_count: u64,
    /// SHA-256 of the exact validated bytes.
    pub sha256: String,
}

/// Health-free result of the embedded shared-core self-test.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SelfTestReport {
    /// True only after every embedded check completed.
    pub passed: bool,
    /// Version information exercised by the self-test.
    pub build_info: BuildInfo,
    /// Exact embedded fixture validation evidence.
    pub fixture: FixtureValidation,
}

/// Stable shared-core failures. Messages never include fixture or health values.
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum CoreError {
    /// The expected digest was not 64 lowercase hexadecimal characters.
    #[error("fixture digest must be lowercase SHA-256")]
    InvalidFixtureDigest,
    /// The fixture exceeded the public boundary limit.
    #[error("fixture exceeds the size limit")]
    FixtureTooLarge,
    /// The exact bytes did not match the caller-provided digest.
    #[error("fixture digest does not match")]
    FixtureDigestMismatch,
    /// The fixture was not a valid bounded M1 fixture envelope.
    #[error("fixture envelope is invalid")]
    InvalidFixture,
    /// The fixture used non-canonical JSON bytes.
    #[error("fixture bytes are not canonical")]
    NonCanonicalFixture,
    /// The fixture envelope version is unsupported.
    #[error("fixture format version is unsupported")]
    UnsupportedFixtureFormatVersion,
    /// The semantic input version is unsupported.
    #[error("semantic input version is unsupported")]
    UnsupportedSemanticInputVersion,
    /// The registry version is unsupported.
    #[error("registry version is unsupported")]
    UnsupportedRegistryVersion,
    /// The persisted-state version is unsupported.
    #[error("persisted-state version is unsupported")]
    UnsupportedPersistedStateVersion,
    /// The embedded metric/profile registry failed validation.
    #[error("metric registry is invalid")]
    InvalidRegistry,
    /// The requested registry profile is unsupported by this core.
    #[error("metric registry profile is unsupported")]
    UnsupportedRegistryProfile,
    /// Semantic configuration exceeded its bounded input limit.
    #[error("semantic configuration exceeds the size limit")]
    SemanticConfigTooLarge,
    /// Semantic configuration was malformed or internally inconsistent.
    #[error("semantic configuration is invalid")]
    InvalidSemanticConfig,
    /// One semantic batch exceeded its bounded input limit.
    #[error("semantic batch exceeds the size limit")]
    SemanticBatchTooLarge,
    /// One semantic batch was malformed or violated the semantic contract.
    #[error("semantic batch is invalid")]
    InvalidSemanticBatch,
    /// A bounded semantic session limit was exceeded.
    #[error("semantic session exceeds a limit")]
    SemanticLimitExceeded,
    /// Batch, owner-date, source-ordinal, or record identity ordering was invalid.
    #[error("semantic input sequence is invalid")]
    SemanticSequenceInvalid,
    /// The semantic session had already completed or observed cancellation.
    #[error("semantic session is terminal")]
    SemanticSessionTerminal,
    /// The requested operation is not supported by the explicit profile.
    #[error("semantic operation is unsupported for the profile")]
    UnsupportedSemanticOperation,
}

impl CoreError {
    /// Stable machine-readable error code.
    pub const fn code(self) -> &'static str {
        match self {
            Self::InvalidFixtureDigest => "invalid_fixture_digest",
            Self::FixtureTooLarge => "fixture_too_large",
            Self::FixtureDigestMismatch => "fixture_digest_mismatch",
            Self::InvalidFixture => "invalid_fixture",
            Self::NonCanonicalFixture => "non_canonical_fixture",
            Self::UnsupportedFixtureFormatVersion => "unsupported_fixture_format_version",
            Self::UnsupportedSemanticInputVersion => "unsupported_semantic_input_version",
            Self::UnsupportedRegistryVersion => "unsupported_registry_version",
            Self::UnsupportedPersistedStateVersion => "unsupported_persisted_state_version",
            Self::InvalidRegistry => "invalid_registry",
            Self::UnsupportedRegistryProfile => "unsupported_registry_profile",
            Self::SemanticConfigTooLarge => "semantic_config_too_large",
            Self::InvalidSemanticConfig => "invalid_semantic_config",
            Self::SemanticBatchTooLarge => "semantic_batch_too_large",
            Self::InvalidSemanticBatch => "invalid_semantic_batch",
            Self::SemanticLimitExceeded => "semantic_limit_exceeded",
            Self::SemanticSequenceInvalid => "semantic_sequence_invalid",
            Self::SemanticSessionTerminal => "semantic_session_terminal",
            Self::UnsupportedSemanticOperation => "unsupported_semantic_operation",
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct FixtureEnvelope {
    fixture_format_version: u32,
    case_id: String,
    semantic_input_version: u32,
    registry_version: u32,
    persisted_state_version: u32,
    records: Vec<serde_json::Value>,
}

/// Return independently versioned build information.
pub fn build_info() -> BuildInfo {
    BuildInfo {
        crate_version: env!("CARGO_PKG_VERSION").to_owned(),
        core_source_revision: CORE_SOURCE_REVISION.to_owned(),
        registry_sha256: REGISTRY_SHA256.to_owned(),
        core_api_version: CORE_API_VERSION,
        semantic_input_version: SEMANTIC_INPUT_VERSION,
        canonical_model_version: CANONICAL_MODEL_VERSION,
        registry_version: REGISTRY_VERSION,
        render_input_version: render::RENDER_INPUT_VERSION,
        artifact_plan_version: render::ARTIFACT_PLAN_VERSION,
        render_profile_revision: render::RENDER_PROFILE_REVISION,
        persisted_state_version: PERSISTED_STATE_VERSION,
    }
}

/// Run the embedded deterministic, synthetic, health-free fixture check.
///
/// # Errors
///
/// Returns a stable fixture-validation error if the compile-time fixture is inconsistent with the
/// current core contracts.
pub fn self_test() -> Result<SelfTestReport, CoreError> {
    let fixture = validate_fixture(SELF_TEST_FIXTURE, SELF_TEST_FIXTURE_SHA256)?;
    registry::validate_embedded_registry()?;
    Ok(SelfTestReport {
        passed: true,
        build_info: build_info(),
        fixture,
    })
}

/// Validate a bounded canonical fixture against its exact lowercase SHA-256 digest.
///
/// Validation is deterministic and returns no fixture content, paths, record values, or parser
/// diagnostics. M1 fixtures are synthetic host-generation evidence, not production health input.
///
/// # Errors
///
/// Returns a stable [`CoreError`] when the digest is malformed or mismatched, the fixture is too
/// large or malformed, its JSON is non-canonical, or one of its explicit versions is unsupported.
pub fn validate_fixture(
    fixture_bytes: &[u8],
    expected_sha256: &str,
) -> Result<FixtureValidation, CoreError> {
    if fixture_bytes.len() > MAX_FIXTURE_BYTES {
        return Err(CoreError::FixtureTooLarge);
    }
    if !is_lowercase_sha256(expected_sha256) {
        return Err(CoreError::InvalidFixtureDigest);
    }

    let actual_sha256 = format!("{:x}", Sha256::digest(fixture_bytes));
    if actual_sha256 != expected_sha256 {
        return Err(CoreError::FixtureDigestMismatch);
    }

    let fixture: FixtureEnvelope =
        serde_json::from_slice(fixture_bytes).map_err(|_| CoreError::InvalidFixture)?;
    validate_envelope(&fixture)?;

    let mut canonical = serde_json::to_vec(&fixture).map_err(|_| CoreError::InvalidFixture)?;
    canonical.push(b'\n');
    if canonical != fixture_bytes {
        return Err(CoreError::NonCanonicalFixture);
    }

    let byte_count = u64::try_from(fixture_bytes.len()).map_err(|_| CoreError::FixtureTooLarge)?;
    Ok(FixtureValidation {
        fixture_format_version: fixture.fixture_format_version,
        byte_count,
        sha256: actual_sha256,
    })
}

fn validate_envelope(fixture: &FixtureEnvelope) -> Result<(), CoreError> {
    if fixture.fixture_format_version != FIXTURE_FORMAT_VERSION {
        return Err(CoreError::UnsupportedFixtureFormatVersion);
    }
    if fixture.semantic_input_version != SEMANTIC_INPUT_VERSION {
        return Err(CoreError::UnsupportedSemanticInputVersion);
    }
    if fixture.registry_version != REGISTRY_VERSION {
        return Err(CoreError::UnsupportedRegistryVersion);
    }
    if fixture.persisted_state_version != PERSISTED_STATE_VERSION {
        return Err(CoreError::UnsupportedPersistedStateVersion);
    }
    if fixture.case_id.is_empty()
        || fixture.case_id.len() > MAX_CASE_ID_BYTES
        || !fixture
            .case_id
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        || fixture.records.len() > MAX_FIXTURE_RECORDS
    {
        return Err(CoreError::InvalidFixture);
    }
    Ok(())
}

fn is_lowercase_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn digest(bytes: &[u8]) -> String {
        format!("{:x}", Sha256::digest(bytes))
    }

    fn fixture_with_versions(
        fixture_format_version: u32,
        semantic_input_version: u32,
        registry_version: u32,
        persisted_state_version: u32,
    ) -> Vec<u8> {
        format!(
            concat!(
                "{{\"fixture_format_version\":{},",
                "\"case_id\":\"version-test\",",
                "\"semantic_input_version\":{},",
                "\"registry_version\":{},",
                "\"persisted_state_version\":{},",
                "\"records\":[]}}\n"
            ),
            fixture_format_version,
            semantic_input_version,
            registry_version,
            persisted_state_version
        )
        .into_bytes()
    }

    #[test]
    fn versions_are_independent_and_explicit() {
        assert_eq!(
            build_info(),
            BuildInfo {
                crate_version: "0.1.0-alpha.1".to_owned(),
                core_source_revision: "development".to_owned(),
                registry_sha256: REGISTRY_SHA256.to_owned(),
                core_api_version: 4,
                semantic_input_version: 1,
                canonical_model_version: 1,
                registry_version: 1,
                render_input_version: 1,
                artifact_plan_version: 1,
                render_profile_revision: 1,
                persisted_state_version: 1,
            }
        );
    }

    #[test]
    fn self_test_is_exact_and_repeatable() {
        let first = self_test().expect("embedded fixture should validate");
        let second = self_test().expect("embedded fixture should validate repeatedly");

        assert!(first.passed);
        assert_eq!(first, second);
        assert_eq!(first.fixture.byte_count, 152);
        assert_eq!(first.fixture.sha256, SELF_TEST_FIXTURE_SHA256);
    }

    #[test]
    fn validates_exact_canonical_fixture_bytes() {
        let result = validate_fixture(SELF_TEST_FIXTURE, SELF_TEST_FIXTURE_SHA256)
            .expect("canonical fixture should validate");

        assert_eq!(result.fixture_format_version, FIXTURE_FORMAT_VERSION);
        assert_eq!(result.sha256, digest(SELF_TEST_FIXTURE));
    }

    #[test]
    fn rejects_each_unsupported_version_independently() {
        let cases = [
            (
                fixture_with_versions(2, 1, 1, 1),
                CoreError::UnsupportedFixtureFormatVersion,
            ),
            (
                fixture_with_versions(1, 2, 1, 1),
                CoreError::UnsupportedSemanticInputVersion,
            ),
            (
                fixture_with_versions(1, 1, 2, 1),
                CoreError::UnsupportedRegistryVersion,
            ),
            (
                fixture_with_versions(1, 1, 1, 2),
                CoreError::UnsupportedPersistedStateVersion,
            ),
        ];

        for (bytes, expected) in cases {
            assert_eq!(validate_fixture(&bytes, &digest(&bytes)), Err(expected));
        }
    }

    #[test]
    fn rejects_non_canonical_or_mismatched_bytes() {
        let non_canonical = SELF_TEST_FIXTURE
            .strip_suffix(b"\n")
            .expect("fixture newline");
        assert_eq!(
            validate_fixture(non_canonical, &digest(non_canonical)),
            Err(CoreError::NonCanonicalFixture)
        );
        assert_eq!(
            validate_fixture(SELF_TEST_FIXTURE, &"0".repeat(64)),
            Err(CoreError::FixtureDigestMismatch)
        );
        assert_eq!(
            validate_fixture(SELF_TEST_FIXTURE, "NOT-A-DIGEST"),
            Err(CoreError::InvalidFixtureDigest)
        );
    }

    #[test]
    fn errors_are_stable_and_health_free() {
        let private_value = b"private-health-value";
        let error = validate_fixture(private_value, &digest(private_value))
            .expect_err("non-JSON fixture should fail");

        assert_eq!(error, CoreError::InvalidFixture);
        assert_eq!(error.code(), "invalid_fixture");
        assert_eq!(error.to_string(), "fixture envelope is invalid");
        assert!(!error.to_string().contains("private-health-value"));
    }

    #[test]
    fn enforces_fixture_size_limit_before_parsing() {
        let oversized = vec![b'x'; MAX_FIXTURE_BYTES + 1];
        assert_eq!(
            validate_fixture(&oversized, &"0".repeat(64)),
            Err(CoreError::FixtureTooLarge)
        );
    }
}
