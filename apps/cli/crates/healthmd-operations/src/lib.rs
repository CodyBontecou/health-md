#![forbid(unsafe_code)]

pub mod backend;
pub mod data;
pub mod limits;
pub mod model;
pub mod normalize;
pub mod receipt;
pub mod registry;
pub mod service;

pub use backend::{
    ArtifactStore, ArtifactStoreBackend, BackendCapabilities, BackendError, CallContext,
    CallerIdentity, CallerMode, HealthDataBackend, PairingStartResult, ProgressUpdate,
    QueryDetailLevel, QueryPageRequest,
};
pub use data::{
    AGENT_DATA_GRANT_SCHEMA, AGENT_DATA_QUERY_SCHEMA, AGENT_DATA_SCHEMA_VERSION,
    AGENT_QUERY_RESPONSE_SCHEMA, AgentDataDateSelection, AgentDataDetailLevel, AgentDataGrant,
    AgentDataMetricSelection, AgentDataOperation, AgentDataPage, AgentDataQueryRequest,
    AgentDataRecordScope, AgentDataSourceSelection, AgentDataTimeSelection,
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
