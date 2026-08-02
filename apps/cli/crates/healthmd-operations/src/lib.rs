#![forbid(unsafe_code)]

pub mod backend;
pub mod limits;
pub mod model;
pub mod normalize;
pub mod receipt;
pub mod registry;
pub mod service;

pub use backend::{
    BackendCapabilities, BackendError, CallContext, CallerIdentity, CallerMode, HealthDataBackend,
    QueryDetailLevel, QueryPageRequest,
};
pub use limits::OperationLimits;
pub use model::SurfaceProfile;
pub use normalize::{
    DateOptions, ExtractSelection, GeneratedFileExportInput, GeneratedFileExportInvocation,
    OperationInputError, SelectionDetail, SelectionOptions, canonical_destination,
    canonical_object_path, generated_file_export_from_value, validate_canonical_pointer,
};
pub use receipt::{
    OperationOutcome, OperationReceipt, backend_error_value, cancellation_value,
    valid_export_receipt, valid_query_receipt,
};
pub use registry::{
    OperationDefinition, OperationKind, QueryInvocation, definition, definitions, job_id,
    query_invocation, tool_catalog,
};
pub use service::HealthOperations;
