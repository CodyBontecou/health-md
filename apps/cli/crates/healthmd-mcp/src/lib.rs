#![forbid(unsafe_code)]

pub mod application;
pub mod apps;
#[cfg(feature = "oauth-resource-server")]
pub mod auth;
pub mod backend;
mod catalog;
mod chart;
pub mod jsonrpc;
mod result;

#[cfg(feature = "streamable-http")]
pub mod transport;

pub use application::{ApplicationLimits, HealthMdApplication, HealthMdSession};
pub use backend::{
    BackendCapabilities, BackendError, CallContext, CallerIdentity, CallerMode, HealthDataBackend,
    PairingStartResult, QueryDetailLevel, QueryPageRequest,
};
pub use catalog::tool_catalog;
pub use healthmd_operations::SurfaceProfile;
pub use jsonrpc::JsonRpcSession;
