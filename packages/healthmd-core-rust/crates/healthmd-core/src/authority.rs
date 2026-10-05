//! Exact historical authorities. Registry v1 is not a wildcard compatibility promise.

use crate::{CoreError, REGISTRY_SHA256};

/// Shipped v3.4.2 authority, retained verbatim from 837687662aa2853d1872724c72a97e1526519bbc.
pub const HISTORICAL_REGISTRY_SHA256: &str =
    "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99";
const HISTORICAL_BYTES: &[u8] = include_bytes!("../registry/metric-registry-shipped-v3.4.2.json");
const CURRENT_BYTES: &[u8] = include_bytes!("../registry/metric-registry-v1.json");

pub(crate) fn registry_bytes(hash: &str, profile: &str) -> Result<&'static [u8], CoreError> {
    if !matches!(
        profile,
        "apple_health_data_v8" | "android_frozen_v4" | "android_analytical_v5"
    ) {
        return Err(CoreError::UnsupportedRegistryProfile);
    }
    if hash == REGISTRY_SHA256 {
        Ok(CURRENT_BYTES)
    } else if hash == HISTORICAL_REGISTRY_SHA256 {
        Ok(HISTORICAL_BYTES)
    } else {
        Err(CoreError::UnsupportedRegistryProfile)
    }
}

pub(crate) fn supports_semantic(hash: &str, profile: &str, revision: u32) -> bool {
    registry_bytes(hash, profile).is_ok()
        && (revision == 1 || (profile == "apple_health_data_v8" && revision == 2))
}

pub(crate) fn supports_render(hash: &str, profile: &str, revision: u32) -> bool {
    registry_bytes(hash, profile).is_ok() && revision == 2
}
