//! Deterministic, destination-independent artifact planning.

use std::collections::HashSet;

use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::{Serialize, ser::SerializeStruct};
use sha2::{Digest, Sha256};
use unicode_casefold::UnicodeCaseFold;
use unicode_normalization::UnicodeNormalization;

use super::{
    ARTIFACT_PLAN_VERSION, MAX_ARTIFACT_BYTES, MAX_ARTIFACTS, MAX_INLINE_OUTPUT_BYTES, RenderError,
    WriteMode,
};
use crate::semantic::SemanticProfile;

const ARTIFACT_ID_DOMAIN: &[u8] = b"healthmd.artifact_id.v1\0";

/// One immutable artifact to be committed by a native destination owner.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtifactPlanItem {
    /// Domain-separated SHA-256 identity of the complete planned artifact.
    pub artifact_id: String,
    /// Validated POSIX path relative to the caller-owned destination root.
    pub relative_path: String,
    /// Static IANA media type for the content.
    pub media_type: String,
    /// Destination operation requested for this artifact.
    pub write_mode: WriteMode,
    /// Exact bytes to pass to the native destination owner.
    pub content: Vec<u8>,
    /// Exact content byte count.
    pub byte_count: u64,
    /// SHA-256 of `content`.
    pub sha256: String,
}

impl Serialize for ArtifactPlanItem {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut item = serializer.serialize_struct("ArtifactPlanItem", 7)?;
        item.serialize_field("artifact_id", &self.artifact_id)?;
        item.serialize_field("relative_path", &self.relative_path)?;
        item.serialize_field("media_type", &self.media_type)?;
        item.serialize_field("write_mode", &self.write_mode)?;
        item.serialize_field("content_base64", &STANDARD.encode(&self.content))?;
        item.serialize_field("byte_count", &self.byte_count)?;
        item.serialize_field("sha256", &self.sha256)?;
        item.end()
    }
}

/// Completed `healthmd.artifact_plan` v1 result.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactPlan {
    /// Stable plan schema identifier.
    pub schema: String,
    /// Artifact-plan contract version.
    pub artifact_plan_version: u32,
    /// Caller-provided request identity.
    pub request_id: String,
    /// Semantic/render session identity.
    pub session_id: String,
    /// Explicit shipped profile.
    pub profile: SemanticProfile,
    /// Artifacts in deterministic render order.
    pub items: Vec<ArtifactPlanItem>,
    /// Sum of all inline content bytes.
    pub total_byte_count: u64,
}

#[derive(Clone, Debug)]
pub(crate) struct ArtifactPlanBuilder {
    request_id: String,
    session_id: String,
    profile: SemanticProfile,
    items: Vec<ArtifactPlanItem>,
    exact_paths: HashSet<String>,
    portable_paths: HashSet<String>,
    total_bytes: usize,
}

impl ArtifactPlanBuilder {
    pub(crate) fn new(request_id: &str, session_id: &str, profile: SemanticProfile) -> Self {
        Self {
            request_id: request_id.to_owned(),
            session_id: session_id.to_owned(),
            profile,
            items: Vec::new(),
            exact_paths: HashSet::new(),
            portable_paths: HashSet::new(),
            total_bytes: 0,
        }
    }

    pub(crate) fn add(
        &mut self,
        relative_path: String,
        media_type: &str,
        write_mode: WriteMode,
        content: Vec<u8>,
    ) -> Result<(), RenderError> {
        validate_relative_path(&relative_path)?;
        validate_media_type(media_type)?;
        let artifact_limit = if write_mode == WriteMode::ApiPost {
            MAX_INLINE_OUTPUT_BYTES
        } else {
            MAX_ARTIFACT_BYTES
        };
        if content.len() > artifact_limit {
            return Err(RenderError::ArtifactTooLarge);
        }
        if self.items.len() >= MAX_ARTIFACTS {
            return Err(RenderError::ArtifactLimitExceeded);
        }
        let next_total = self
            .total_bytes
            .checked_add(content.len())
            .ok_or(RenderError::InlineOutputTooLarge)?;
        if next_total > MAX_INLINE_OUTPUT_BYTES {
            return Err(RenderError::InlineOutputTooLarge);
        }

        let portable = portable_collision_key(&relative_path);
        if !self.exact_paths.insert(relative_path.clone()) || !self.portable_paths.insert(portable)
        {
            return Err(RenderError::PathCollision);
        }

        let sha256 = format!("{:x}", Sha256::digest(&content));
        let artifact_id = artifact_id(
            &self.request_id,
            &self.session_id,
            self.profile,
            &relative_path,
            media_type,
            write_mode,
            &sha256,
        );
        let byte_count = u64::try_from(content.len()).map_err(|_| RenderError::ArtifactTooLarge)?;
        self.items.push(ArtifactPlanItem {
            artifact_id,
            relative_path,
            media_type: media_type.to_owned(),
            write_mode,
            content,
            byte_count,
            sha256,
        });
        self.total_bytes = next_total;
        Ok(())
    }

    pub(crate) fn finish(self) -> Result<ArtifactPlan, RenderError> {
        Ok(ArtifactPlan {
            schema: "healthmd.artifact_plan".to_owned(),
            artifact_plan_version: ARTIFACT_PLAN_VERSION,
            request_id: self.request_id,
            session_id: self.session_id,
            profile: self.profile,
            items: self.items,
            total_byte_count: u64::try_from(self.total_bytes)
                .map_err(|_| RenderError::InlineOutputTooLarge)?,
        })
    }
}

/// Validate a strict POSIX relative path without touching a filesystem.
///
/// # Errors
/// Returns [`RenderError::InvalidPath`] for absolute paths, backslashes, NULs, empty paths or
/// components, `.` components, and traversal components.
pub fn validate_relative_path(path: &str) -> Result<(), RenderError> {
    let windows_absolute = path.as_bytes().get(1) == Some(&b':')
        && path.as_bytes().first().is_some_and(u8::is_ascii_alphabetic);
    if path.is_empty()
        || path.len() > 4_096
        || path.starts_with('/')
        || path.ends_with('/')
        || windows_absolute
        || path.contains(['\\', '\0', '{', '}'])
        || path.chars().any(char::is_control)
        || path
            .split('/')
            .any(|part| part.is_empty() || matches!(part, "." | ".."))
    {
        return Err(RenderError::InvalidPath);
    }
    Ok(())
}

pub(crate) fn validate_media_type(value: &str) -> Result<(), RenderError> {
    if value.is_empty()
        || value.len() > 128
        || !value.contains('/')
        || !value.bytes().all(|byte| {
            byte.is_ascii_alphanumeric()
                || matches!(byte, b'/' | b'+' | b'-' | b'.' | b';' | b'=' | b' ')
        })
    {
        return Err(RenderError::InvalidArtifact);
    }
    Ok(())
}

fn portable_collision_key(path: &str) -> String {
    path.nfkc().case_fold().nfkc().collect()
}

pub(crate) fn artifact_id(
    request_id: &str,
    session_id: &str,
    profile: SemanticProfile,
    relative_path: &str,
    media_type: &str,
    write_mode: WriteMode,
    content_sha256: &str,
) -> String {
    let mut digest = Sha256::new();
    digest.update(ARTIFACT_ID_DOMAIN);
    for value in [
        request_id,
        session_id,
        super::profile_id(profile),
        relative_path,
        media_type,
        write_mode.id(),
        content_sha256,
    ] {
        digest.update(u64::try_from(value.len()).unwrap_or(u64::MAX).to_be_bytes());
        digest.update(value.as_bytes());
    }
    format!("{:x}", digest.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unsafe_posix_paths() {
        for path in [
            "",
            "/a",
            "C:/a",
            "a/",
            "a//b",
            ".",
            "a/./b",
            "..",
            "a/../b",
            "a\\b",
            "a\0b",
            "a\nb",
            "{date}.md",
        ] {
            assert_eq!(validate_relative_path(path), Err(RenderError::InvalidPath));
        }
        assert_eq!(validate_relative_path("Health/2026-07-25.md"), Ok(()));
    }

    #[test]
    fn detects_exact_case_and_unicode_collisions() {
        let mut exact =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AppleHealthDataV8);
        exact
            .add(
                "Health/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                b"a".to_vec(),
            )
            .unwrap();
        assert_eq!(
            exact.add(
                "Health/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                b"b".to_vec(),
            ),
            Err(RenderError::PathCollision)
        );

        let mut case =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AppleHealthDataV8);
        case.add(
            "Health/Day.md".to_owned(),
            "text/markdown",
            WriteMode::Overwrite,
            Vec::new(),
        )
        .unwrap();
        assert_eq!(
            case.add(
                "health/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                Vec::new(),
            ),
            Err(RenderError::PathCollision)
        );

        let mut unicode =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AppleHealthDataV8);
        unicode
            .add(
                "Caf\u{00e9}/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                Vec::new(),
            )
            .unwrap();
        assert_eq!(
            unicode.add(
                "Cafe\u{0301}/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                Vec::new(),
            ),
            Err(RenderError::PathCollision)
        );

        let mut casefold =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AppleHealthDataV8);
        casefold
            .add(
                "Straße/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                Vec::new(),
            )
            .unwrap();
        assert_eq!(
            casefold.add(
                "STRASSE/day.md".to_owned(),
                "text/markdown",
                WriteMode::Overwrite,
                Vec::new(),
            ),
            Err(RenderError::PathCollision)
        );
    }

    #[test]
    fn indivisible_api_envelope_may_exceed_the_ordinary_artifact_limit() {
        let bytes = vec![0_u8; MAX_ARTIFACT_BYTES + 1];
        let mut ordinary =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AndroidFrozenV4);
        assert_eq!(
            ordinary.add(
                "Health/day.json".to_owned(),
                "application/json",
                WriteMode::Overwrite,
                bytes.clone(),
            ),
            Err(RenderError::ArtifactTooLarge)
        );
        let mut api =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AndroidFrozenV4);
        assert!(
            api.add(
                "api/request-0000.json".to_owned(),
                "application/json",
                WriteMode::ApiPost,
                bytes,
            )
            .is_ok()
        );
    }

    #[test]
    fn artifact_identity_is_domain_separated_and_content_bound() {
        let mut first =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AndroidFrozenV4);
        first
            .add(
                "Health/day.json".to_owned(),
                "application/json",
                WriteMode::Overwrite,
                b"{}".to_vec(),
            )
            .unwrap();
        let first = first.finish().unwrap();
        let item = &first.items[0];
        assert_eq!(item.byte_count, 2);
        assert_eq!(
            item.sha256,
            "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
        );
        assert_eq!(item.artifact_id.len(), 64);
        let serialized = serde_json::to_value(&first).unwrap();
        assert_eq!(serialized["schema"], "healthmd.artifact_plan");
        assert_eq!(serialized["items"][0]["content_base64"], "e30=");
        assert!(serialized["items"][0].get("content").is_none());

        let mut second =
            ArtifactPlanBuilder::new("request", "session", SemanticProfile::AndroidFrozenV4);
        second
            .add(
                "Health/day.json".to_owned(),
                "application/json",
                WriteMode::Overwrite,
                b"[]".to_vec(),
            )
            .unwrap();
        assert_ne!(
            item.artifact_id,
            second.finish().unwrap().items[0].artifact_id
        );
    }
}
