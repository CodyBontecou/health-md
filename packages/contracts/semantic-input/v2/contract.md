# Successor semantic input and canonical model v2

Status: owner-authorized implementation, not production-qualified.

This is a separate successor handoff for `apple_health_data_v11` and `android_sleep_v6`. Historical semantic input/canonical model v1, its closed profile set, schemas, fixture bytes and API-3 result declaration remain unchanged.

## Pins and authority

- `semantic_input_version: 2`, `canonical_model_version: 2`, registry v2.
- Registry SHA-256: `709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78`.
- Canonical results declare the current coarse core API 4. Legacy results still declare 3.
- Configuration selects an explicit native successor profile and a frozen IANA owner-date timezone. Native SDK capture owns wake-date session acquisition; Rust never rebuckets raw records or infers an owner from timestamps.
- Every result, including successful empty days, processing and cancellation, carries `sleep_capture_context`: `schema_profile`, `calendar_timezone`, `sleep_day_attribution: morning_ends`, `sleep_owner_day_rule: session_end_date`, and `sleep_interval_clipping: none`.
- The profile and atomic authority must agree. The renderer rejects a changed timezone or missing/contradictory authority rather than reinterpreting a completed capture.

Bounded exact timestamp/number/unit representations, source identity/ordering, filtering, native extensions, daily reducers, canonicalization and health-free error rules follow [v1](../v1/contract.md). They do not establish equivalence between Apple Core and Android Light: successor registry v2 uses distinct native IDs and Android v6 has no Core output alias.

## Selection independent of availability

New successor results carry `selected_output_keys`, sorted and unique, derived from the frozen session's selected registry IDs after disabled-output filtering. This is selection authority, not a declaration that summaries exist. Missing quantities remain absent; details must not manufacture zero aggregates. Historical v1 results omit this field and retain exact bytes. Earlier draft v2 results without the field retain aggregate-bound detail validation; they cannot authorize details whose summaries are unavailable.

Render validation rejects unknown/duplicate selected outputs, a selection narrower than the supplied semantic values, and any historical result carrying this successor authority. Native detail output owners must belong to either accepted summaries or this explicit frozen selection. This internal draft-result addition changes no public daily schema or direct wire protocol.

## Current qualification limits

Daily successor semantics and metadata are exercised by the real core session/render interfaces in `crates/healthmd-core/tests/sleep_rendering.rs`. Calendar/range reductions for successor profiles remain unsupported until the independent Apple roll-up v11 implementation is verified. Native adapters, capture/output fixtures, durable resume, real consumers and physical-device checks are still required by the [feature qualification contract](../../sleep-attribution/v1/contract.md). Enum or helper acceptance is not production enablement.
