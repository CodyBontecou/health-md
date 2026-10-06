# Successor semantic input and canonical model v2

Status: owner-authorized implementation, not production-qualified.

This is a separate successor handoff for `apple_health_data_v10` and `android_sleep_v6`. Historical semantic input/canonical model v1, its closed profile set, schemas, fixture bytes and API-3 result declaration remain unchanged.

## Pins and authority

- `semantic_input_version: 2`, `canonical_model_version: 2`, registry v2.
- Registry SHA-256: `c1854454bee84b6d74cee1d7457d3fde1f484ef74963a656adba503c91cb9073`.
- Canonical results declare the current coarse core API 4. Legacy results still declare 3.
- Configuration selects an explicit native successor profile and a frozen IANA owner-date timezone. Native SDK capture owns wake-date session acquisition; Rust never rebuckets raw records or infers an owner from timestamps.
- Every result, including successful empty days, processing and cancellation, carries `sleep_capture_context`: `schema_profile`, `calendar_timezone`, `sleep_day_attribution: morning_ends`, `sleep_owner_day_rule: session_end_date`, and `sleep_interval_clipping: none`.
- The profile and atomic authority must agree. The renderer rejects a changed timezone or missing/contradictory authority rather than reinterpreting a completed capture.

Bounded exact timestamp/number/unit representations, source identity/ordering, filtering, native extensions, daily reducers, canonicalization and health-free error rules follow [v1](../v1/contract.md). They do not establish equivalence between Apple Core and Android Light: successor registry v2 uses distinct native IDs and Android v6 has no Core output alias.

## Current qualification limits

Daily successor semantics and metadata are exercised by the real core session/render interfaces in `crates/healthmd-core/tests/sleep_rendering.rs`. Calendar/range reductions for successor profiles remain unsupported until the independent Apple roll-up v11 implementation is verified. Native adapters, capture/output fixtures, durable resume, real consumers and physical-device checks are still required by the [feature qualification contract](../../sleep-attribution/v1/contract.md). Enum or helper acceptance is not production enablement.
