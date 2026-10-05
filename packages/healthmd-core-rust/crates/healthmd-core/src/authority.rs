//! Exact historical authorities. Registry v1 is not a wildcard compatibility promise.

use crate::{CoreError, REGISTRY_SHA256};

/// Original pre-v8 authority, retained verbatim from c77024b87170260531f8df8fc5b604ad35375466.
pub const HISTORICAL_REGISTRY_SHA256: &str =
    "b988fa9a0fea4cf3a0768ee6ad89251a15386c87eb929ce1e46b136fd33b1f4b";
const HISTORICAL_BYTES: &[u8] = include_bytes!("../registry/metric-registry-pre-v8-c77024b.json");
const CURRENT_BYTES: &[u8] = include_bytes!("../registry/metric-registry-v1.json");

pub(crate) fn registry_bytes(hash: &str, profile: &str) -> Result<&'static [u8], CoreError> {
    if hash == REGISTRY_SHA256
        && matches!(
            profile,
            "apple_health_data_v8" | "android_frozen_v4" | "android_analytical_v5"
        )
    {
        Ok(CURRENT_BYTES)
    } else if hash == HISTORICAL_REGISTRY_SHA256
        && matches!(
            profile,
            "apple_health_data_v7" | "android_frozen_v4" | "android_analytical_v5"
        )
    {
        Ok(HISTORICAL_BYTES)
    } else {
        Err(CoreError::UnsupportedRegistryProfile)
    }
}

pub(crate) fn supports_semantic(hash: &str, profile: &str, revision: u32) -> bool {
    registry_bytes(hash, profile).is_ok()
        && (revision == 1
            || (hash == REGISTRY_SHA256 && profile == "apple_health_data_v8" && revision == 2))
}

pub(crate) fn supports_render(hash: &str, profile: &str, revision: u32) -> bool {
    registry_bytes(hash, profile).is_ok()
        && revision
            == if hash == HISTORICAL_REGISTRY_SHA256 {
                1
            } else {
                2
            }
}
