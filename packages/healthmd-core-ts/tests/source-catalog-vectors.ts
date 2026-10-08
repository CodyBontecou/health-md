/** Independently proposed Stage1 private metadata-only source catalog. No implementation. */
import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
declare const requestBrand: unique symbol;
declare const ticketBrand: unique symbol;
export interface OwnedCatalogRequest { readonly [requestBrand]: true }
export interface OwnedCatalogTicket { readonly [ticketBrand]: true }
export type FailureCode = "invalid_request" | "candidate_limit_exceeded" | "scope_not_authorized" | "scope_binding_mismatch" | "owned_handoff_closed" | "private_catalog_codec" | "private_catalog_busy";
export type CatalogFailure = { readonly code: FailureCode };
export type Domain = "health" | "location" | "device_usage";
export type PayloadKind = "health_fact" | "location_point" | "usage_aggregate" | "foreground_app_session";
export type TaggedIdentity = { readonly state: "known"; readonly value: string } | { readonly state: "unknown"; readonly reason: "not_reported" };
export type Availability = { readonly state: "available" } | { readonly state: "unavailable"; readonly reason: "not_authorized" | "unsupported" | "display_only" | "not_qualified" | "not_reported" } | { readonly state: "unknown"; readonly reason: "not_reported" } | { readonly state: "planned"; readonly reason: "not_qualified" };
export interface RequestedBinding {
 readonly source_id: string; readonly domain: Domain; readonly payload_kind: PayloadKind;
 readonly source_contract_revision: string; readonly source_purpose: "local_catalog";
 readonly destination: "local"; readonly grant_revision: string; readonly suppression_revision: string;
}
export interface CatalogMetadata {
 readonly source_id: string; readonly domain: Domain; readonly payload_kind: PayloadKind;
 readonly source_contract_revision: string;
 readonly device: TaggedIdentity; readonly installation: TaggedIdentity; readonly native_profile: TaggedIdentity;
 readonly authority_kind: "native_health_store" | "native_usage_aggregate" | "collector_metadata";
 readonly capabilities: { readonly capture: Availability; readonly display: Availability; readonly query: Availability; readonly export: Availability; readonly detail: Availability };
 readonly history: { readonly completeness: "complete" | "partial" | "unknown"; readonly range: "source_reported" | "not_reported"; readonly freshness: "source_reported" | "unknown"; readonly short_sessions: "not_applicable" | "historical_loss" | "all_observed_new_semantics" };
 readonly detail: { readonly granularity: "health_native" | "location_point" | "app_aggregate" | "observed_app_session"; readonly focused_title: "excluded" | "not_observed" | "separate_grant_required" };
 readonly eligibility: "native_authority" | "aggregate_display_only" | "unqualified";
}
export interface CatalogIssuer {
 /** Actual trusted source callback only; primitive preflight FIRST. Exact owned request,
  * current callback/factory/originalScope and matching source/domain/kind/revision bind issuance.
  * A callback may issue multiple tickets; only the returned exact ticket is consumed. */
 issue(primitiveClosedMetadataWire: unknown, request: unknown): OwnedCatalogTicket | null;
}
export interface MetadataSource {
 capture(request: OwnedCatalogRequest, requested: RequestedBinding, issuer: CatalogIssuer): Effect.Effect<OwnedCatalogTicket, CatalogFailure>;
}
export type Phase = "before_capture" | "after_capture" | "before_consume" | "before_metadata_read" | "after_consume" | "assert_current";
export interface CurrentAuthority {
 /** Captured host binds actual catalog/source classification/caller/purpose/detail/destination
  * and latest independent suppression/frontier. Request strings, revision, flags and caller JSON
  * request bindings only; no issuer or fake authenticates actual source grants. */
 check(request: OwnedCatalogRequest, requested: RequestedBinding, phase: Phase): Effect.Effect<void, CatalogFailure>;
}
export interface AuthorizedMetadataView {
 /** Lazy EACH execution; unknown/foreign request/ticket -> fixed invalid_request before
  * properties/check; exact returned ticket/request/callback membership is required.
  * Valid but escaped inactive callback -> null with zero callbacks/checks/materialization.
  * Own active read checks captured original current before_metadata_read on EACH run,
  * then originalScope/context/callback/exact ticket/request again AFTER await, and returns
  * primitive validated source metadata wire without an intervening yield. No payload read. */
 metadata(request: unknown, ticket: unknown): Effect.Effect<string | null, CatalogFailure>;
}
export interface MetadataConsumer {
 /** A trusted metadata-only sink, no real I/O or external delivery. */
 consume(request: OwnedCatalogRequest, ticket: OwnedCatalogTicket, view: AuthorizedMetadataView): Effect.Effect<void, CatalogFailure>;
}
export interface CapturedCatalogLifetime {
 isLive(): boolean;
 /** Replayable same constructor-owned Deferred signal; closes before any source/current callback,
  * no fresh Scope/Layer lookup, no join of the active callback, no resource ACK claim. */
 readonly closed: Effect.Effect<void>;
}
export interface SourceCatalog {
 request(primitiveBindingWire: unknown): Effect.Effect<OwnedCatalogRequest, CatalogFailure>;
 capture(request: unknown): Effect.Effect<OwnedCatalogTicket, CatalogFailure>;
 consume(request: unknown, ticket: unknown, consumer: MetadataConsumer): Effect.Effect<void, CatalogFailure>;
 assertCurrent(request: unknown, ticket: unknown): Effect.Effect<void, CatalogFailure>;
 readonly lifetime: CapturedCatalogLifetime;
}
export interface SourceCatalogFactory {
 create(services: { readonly source: MetadataSource; readonly current: CurrentAuthority }): Effect.Effect<SourceCatalog, CatalogFailure, Scope.Scope>;
}
/** CLOSED PROCEDURE BEFORE CODE:
 * Register captured originalScope sentinel+Deferred close signal BEFORE any trusted callback.
 * Capture source/current methods once. Actual consumer method captured once per consume, before
 * its invocation, not selected from caller JSON; consumer is a trusted capability argument.
 * WeakMaps own request/ticket exact binding/factory/callback. Unknown request/ticket membership
 * FIRST, no property inspection/coercion/Proxy traps. Constructor input is trusted host capability.
 * Preflight primitive raw UTF8/scalars/closed keys/types BEFORE decoding value strings. Unknown
 * record/title fields are rejected without decoding their payload. Decoded string512 is PER
 * INDIVIDUAL key/value, not aggregate. Key cap precedes unknown-key rejection; unknown-key
 * value is never decoded/materialized. JSON numeric tokens forbidden
 * in this private metadata/request grammar; decimal revisions remain exact bounded strings.
 * request is pure private grammar, no source/current call. One active capture/consume per factory;
 * busy guard BEFORE current/source/consumer callbacks, clears after actual effect terminal.
 * capture: before_capture -> actual source callback -> INNER ensuring expires issuer ->
 * exact returned own ticket binding/source metadata validation -> after_capture. Fixed source
 * unavailable error is scope_not_authorized; no exception/provider text in failures.
 * consume: before_consume -> actual consumer callback -> INNER ensuring expires view ->
 * after_consume. Each own lazy read adds before_metadata_read; exact raw validated metadata bytes
 * are returned (no new canonical serializer/numeric renderer), not an executable JSON authority.
 * assertCurrent: exact own pair -> captured assert_current. Capability available means metadata,
 * never grant; no consumer can observe records, title values or acquire capture from this seam.
 * Current denial -> scope_not_authorized; independent frontier/binding mismatch -> scope_binding_mismatch.
 * Scope closes inside/between trusted callbacks: owned_handoff_closed, no later noncleanup callback.
 * If source/consumer/current callback dies or fails with unknown/provider text: fixed phase error;
 * interrupted Fiber preserves interruption. Ordinary callback failure after originalScope close
 * is owned_handoff_closed (no provider echo), even if callback died. After callback normal return originalScope closure
 * precedes any postcurrent/publication success. Source issuer inactive ->null immediately.
 * Callback escaped read returnsnull before current even if reexecuted with fresh Scope/Layer.
 * Valid read pending current resumed after originalScope close must failclosed, no materialization.
 * Lifetime.closed awaits are replayable. Closing originalScope signals without joining operation.
 * Metadata-only: allocation/release/ACK/commit/record/title/output-I/O counters MUST ALWAYS0;
 * Scope-close signal acknowledgement is separate from resource ACK; no transaction/bracket added.
 */

export const sourceCatalogFixture = {
  "task_id": "DATASTORE-SOURCE-CATALOG",
  "source_sha": "a0d2ab32357b69d6efeb7666b8ff4501605d2fbc",
  "proof_class": "portable_synthetic_metadata_only",
  "case_count": 96,
  "packet_minima": [
    {
      "case_id": "catalog-independent-capabilities",
      "input": {
        "action": "metadata",
        "synthetic_initial_state": {
          "source": "synthetic-ios-aggregate",
          "capture": "unavailable",
          "display": "available",
          "query": "unavailable",
          "export": "unavailable",
          "sourceKind": "usage_aggregate"
        },
        "trusted_fake_port_events": [],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "domain": "device_usage",
        "payload_kind": "usage_aggregate",
        "exact_session_capability": false,
        "query_available": false,
        "export_available": false,
        "payload_reads": 0,
        "store_acquisitions": 0
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-unknown-install",
      "input": {
        "action": "metadata",
        "synthetic_initial_state": {
          "source": "synthetic-source",
          "installation": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "trusted_fake_port_events": [],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "installation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "merge_other_installation": false,
        "mint_native_identity": false
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-health-boundary",
      "input": {
        "action": "metadata",
        "synthetic_initial_state": {
          "source": "native-health",
          "profile": "historical-native"
        },
        "trusted_fake_port_events": [],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "copy_health_corpus_to_collector": false,
        "replace_native_authority": false,
        "GPS_equals_health_distance": false
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-source-not-grant",
      "input": {
        "action": "metadata",
        "synthetic_initial_state": {
          "caller_sourceID": "synthetic-source",
          "caller_claim_captureGrant": true,
          "trusted_current": "deny"
        },
        "trusted_fake_port_events": [],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "safe_code": "scope_not_authorized",
        "payload_reads": 0,
        "provider_echo": false
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-foreign-Proxy-own-ticket",
      "input": {
        "action": "read",
        "synthetic_initial_state": {
          "originalScope": "live",
          "request": "throwing_Proxy",
          "ticket": "authentic_own"
        },
        "trusted_fake_port_events": [],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "safe_code": "invalid_request",
        "caller_traps": 0,
        "current_calls": 0,
        "materialized": 0,
        "commit_calls": 0,
        "ACKs": 0
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-Scopeclose-pending-current",
      "input": {
        "action": "read",
        "synthetic_initial_state": {
          "originalScope": "live",
          "request": "owned",
          "ticket": "owned"
        },
        "trusted_fake_port_events": [
          "captured current before_read waits on Deferred",
          "close ORIGINAL Scope externally",
          "resume current Deferred returning allow"
        ],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "safe_code": "owned_handoff_closed",
        "materialized": 0,
        "commit_calls": 0,
        "new_callbacks_after_close": 0
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-escaped-callback-dead",
      "input": {
        "action": "read",
        "synthetic_initial_state": {
          "originalScope": "live",
          "saved_lazy_read": "from finished actual callback"
        },
        "trusted_fake_port_events": [
          "callback exits; inner ensuring expires view",
          "run saved lazyEffect under fresh Scope with replacement current service"
        ],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "read": null,
        "current_calls": 0,
        "materialized": 0,
        "caller_traps": 0,
        "replacement_service_calls": 0
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-frontier-before-read",
      "input": {
        "action": "read",
        "synthetic_initial_state": {
          "current_external_suppression": "2",
          "requested_external_suppression": "1"
        },
        "trusted_fake_port_events": [
          "captured authority compares current external frontier before materialization"
        ],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "safe_code": "scope_binding_mismatch",
        "materialized": 0,
        "commit_calls": 0,
        "published": false
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    },
    {
      "case_id": "catalog-unavailable-source",
      "input": {
        "action": "metadata",
        "synthetic_initial_state": {
          "source_availability": "unavailable"
        },
        "trusted_fake_port_events": [
          "trusted port fails with private sentinel; output fixed error only"
        ],
        "caller_authority_claims_accepted": false
      },
      "expected": {
        "safe_code": "scope_not_authorized",
        "commit_calls": 0,
        "known_zero": false,
        "provider_echo": false
      },
      "proof": "independent planning literal before child Stage1/code; no executed store/native/durable claim"
    }
  ],
  "packet_minimum_mapping": [
    {
      "packet_case_id": "catalog-independent-capabilities",
      "full_scene_case_id": "catalog-independent-capabilities",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-unknown-install",
      "full_scene_case_id": "catalog-unknown-install",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-health-boundary",
      "full_scene_case_id": "catalog-health-boundary",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-source-not-grant",
      "full_scene_case_id": "catalog-source-not-grant",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-foreign-Proxy-own-ticket",
      "full_scene_case_id": "catalog-foreign-Proxy-own-ticket",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-Scopeclose-pending-current",
      "full_scene_case_id": "catalog-Scopeclose-pending-current",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-escaped-callback-dead",
      "full_scene_case_id": "catalog-escaped-callback-dead",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-frontier-before-read",
      "full_scene_case_id": "catalog-frontier-before-read",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    },
    {
      "packet_case_id": "catalog-unavailable-source",
      "full_scene_case_id": "catalog-unavailable-source",
      "retained_packet_input_expected": true,
      "counter_scope": "Overall fullscene unless escaped-read or foreign-read target counter window explicitly declared; packet payload_reads/materialized/ACKs map to record_payload_reads/metadata_materializations/resource_ACKs. Escaped case packet current/materialized/read map to escaped_current_calls/escaped_materializations/escaped_results, independently zero/null."
    }
  ],
  "private_grammar": {
    "private_unmeasured": true,
    "request_raw_UTF8_bytes": 4096,
    "metadata_raw_UTF8_bytes": 16384,
    "decoded_identity_UTF8_bytes": 128,
    "json_depth": 16,
    "json_value_nodes": 256,
    "depth_counting": "Root1; value nodes include root/arrayitems/objectvalues, not object key tokens",
    "decoded_string_UTF8_bytes": 512,
    "one_pending_capture_or_consume": 1,
    "canonical_revision_tokens": "source_contract_revision string [1-9][0-9]* 1..4294967295; grant/suppression decimalstring 0|[1-9][0-9]* u64; no numerical raw JSON allowed anywhere in these closed shapes",
    "strings": "Unicode scalars, no NUL/normalization/trimming/case folding; duplicate decoded keys reject before map construction; full consume; raw unknown records/title/payload are forbidden",
    "domain_kind_and_detail": "health/health_fact/health_native/native_health_store; location/location_point/location_point/collector_metadata; usage_aggregate/app_aggregate/native_usage_aggregate; foreground_app_session/observed_app_session/collector_metadata; never aggregate->session",
    "semantic_fields": "availability independent across all five statuses; unknown identity not guessed; detail/title states contain no titlevalue; history status carries no records/intervals/coverage reconstruction; actualhistory/ranges/producer gates remain separate",
    "decoded_string_UTF8_bytes_scope": "PER INDIVIDUAL decoded JSON key or value string, including object keys; never an aggregate budget. Raw whole-wire UTF8/depth/value-node budgets remain separate. The baseline metadata sums644 decoded key/value UTF8bytes while every individual string is<=31 bytes, therefore accepted.",
    "unknown_key_rejection_precedence": "First primitive type and complete raw UTF8/scalar byte preflight. In a recognized closed object context, lexically scan the key and count its decoded UTF8 without materializing its value: per-key512 cap FIRST; if over512 fixed candidate_limit_exceeded; otherwise check decoded key against this closed object key set and reject unknown key as invalid_request IMMEDIATELY BEFORE value token decoding/materialization. An excluded record/title value is not decoded, parsed into a semantic tree, copied or returned. Raw preflight may inspect UTF16 units for scalar validity/byte count but is not payload decoding. Keys at512 and513 are independently literal-tested below. Unsupported root arrays still undergo bounded lexical value-node/depth validation before unsupported-shape rejection, preserving original budget-scene dispositions. Accepted inputs fully consume raw JSON and known-field values obey per-string and field-specific limits."
  },
  "normal_counter_order": [
    "before_capture",
    "after_capture",
    "before_consume",
    "before_metadata_read",
    "after_consume",
    "assert_current"
  ],
  "snapshot_semantics": "One source per request; one current host-issued metadata ticket. No cross-source atomic snapshot, source payload, record serde/numbers/time transformations or durable backing. wire bytes preserved, not a new public canonical output profile.",
  "cases": [
    {
      "case_id": "catalog-independent-capabilities",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "domain": "device_usage",
        "payload_kind": "usage_aggregate",
        "exact_session_capability": false,
        "query_available": false,
        "export_available": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-unknown-install",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "installation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "merge_other_installation": false,
        "mint_native_identity": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-health-boundary",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"health\",\"grant_revision\":\"1\",\"payload_kind\":\"health_fact\",\"source_contract_revision\":\"1\",\"source_id\":\"native-health\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_health_store\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"health_native\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"health\",\"eligibility\":\"native_authority\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"not_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"historical-native\"},\"payload_kind\":\"health_fact\",\"source_contract_revision\":\"1\",\"source_id\":\"native-health\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_health_store\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"health_native\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"health\",\"eligibility\":\"native_authority\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"not_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"historical-native\"},\"payload_kind\":\"health_fact\",\"source_contract_revision\":\"1\",\"source_id\":\"native-health\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "copy_health_corpus_to_collector": false,
        "replace_native_authority": false,
        "GPS_equals_health_distance": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-source-not-grant",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_capture",
            "action": "deny_current"
          },
          {
            "at": "caller",
            "action": "claim_capture_grant",
            "value": true
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "caller_sourceID_is_grant": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-foreign-Proxy-own-ticket",
      "stimulus": {
        "procedure": "foreign_read",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "setup",
            "action": "capture_own_ticket_enter_consumer_then_reset_counters"
          },
          {
            "at": "read",
            "action": "foreign_throwing_request_own_ticket"
          }
        ],
        "caller_claims_accepted": false,
        "counter_window": "Inside actual own consumer callback after its before_consume check and entry; reset all counters immediately BEFORE the foreign read; fail terminates callback, so no after_consume check."
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-Scopeclose-pending-current",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_metadata_read",
            "action": "await_gate"
          },
          {
            "at": "controller",
            "action": "close_original_then_resume_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 4,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-escaped-callback-dead",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "save_read"
          },
          {
            "at": "after_consume",
            "action": "reenter_saved_read"
          },
          {
            "at": "after_terminal",
            "action": "replace_original_current_method_and_reprovide_fresh_scope"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "escaped_results": [
          null,
          null
        ],
        "escaped_current_calls": 0,
        "escaped_materializations": 0,
        "revival": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-frontier-before-read",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_metadata_read",
            "action": "frontier_mismatch",
            "current_frontier": "2",
            "requested_frontier": "1"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_binding_mismatch",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 4,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-unavailable-source",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "fail_unavailable_with_private_sentinel"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "location-planned-is-not-health-distance",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"location\",\"grant_revision\":\"1\",\"payload_kind\":\"location_point\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-location\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"collector_metadata\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"detail\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"display\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"export\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"query\":{\"reason\":\"not_qualified\",\"state\":\"planned\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"location_point\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"location\",\"eligibility\":\"unqualified\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"payload_kind\":\"location_point\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-location\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"collector_metadata\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"detail\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"display\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"export\":{\"reason\":\"not_qualified\",\"state\":\"planned\"},\"query\":{\"reason\":\"not_qualified\",\"state\":\"planned\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"location_point\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"location\",\"eligibility\":\"unqualified\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"payload_kind\":\"location_point\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-location\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "GPS_equals_health_distance": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "mac-historical-short-session-loss-not-repaired",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"foreground_app_session\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-mac\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"collector_metadata\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"separate_grant_required\",\"granularity\":\"observed_app_session\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"unqualified\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"historical_loss\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"foreground_app_session\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-mac\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"collector_metadata\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"separate_grant_required\",\"granularity\":\"observed_app_session\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"unqualified\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"historical_loss\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"foreground_app_session\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-mac\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "reconstruct_missing_sessions": false,
        "title_granted": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "mac-new-all-observed-retains-distinct-version",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"foreground_app_session\",\"source_contract_revision\":\"2\",\"source_id\":\"synthetic-mac\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"collector_metadata\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"separate_grant_required\",\"granularity\":\"observed_app_session\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"unqualified\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"all_observed_new_semantics\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"foreground_app_session\",\"source_contract_revision\":\"2\",\"source_id\":\"synthetic-mac\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"collector_metadata\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"separate_grant_required\",\"granularity\":\"observed_app_session\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"unqualified\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"all_observed_new_semantics\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"foreground_app_session\",\"source_contract_revision\":\"2\",\"source_id\":\"synthetic-mac\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "rewrite_historical_loss": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "known-device-unknown-install-stay-distinct",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-A\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-A\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "merge_other_installation": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "unknown-completeness-not-complete",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"not_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"not_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "completeness_claim": "unknown"
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close_original-before_capture",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_capture",
            "action": "close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-deny_current-before_capture",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_capture",
            "action": "deny_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close_original-after_capture",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "after_capture",
            "action": "close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 2,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-deny_current-after_capture",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "after_capture",
            "action": "deny_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 2,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close_original-before_consume",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_consume",
            "action": "close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 3,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-deny_current-before_consume",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_consume",
            "action": "deny_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 3,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close_original-before_metadata_read",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_metadata_read",
            "action": "close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 4,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-deny_current-before_metadata_read",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_metadata_read",
            "action": "deny_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 4,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close_original-after_consume",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "after_consume",
            "action": "close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 5,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-deny_current-after_consume",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "after_consume",
            "action": "deny_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 5,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close_original-assert_current",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "assert_current",
            "action": "close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-deny_current-assert_current",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "assert_current",
            "action": "deny_current"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close-inside-source-returning-own-ticket",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_ticket_close_original_then_return"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close-inside-consumer-before-read",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "close_original_before_own_read"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 3,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close-inside-consumer-after-read",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "read_then_close_original"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 4,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-revoke-between-same-read-executions",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "same_read_twice_revoke_between"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_not_authorized",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 5,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-same-lazy-read-twice-fresh-current",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "same_read_twice_allow"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 7,
        "consumer_calls": 1,
        "metadata_materializations": 2,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "read_results": [
          "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
          "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}"
        ]
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-issuer-dead-at-postsource",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "save_issuer"
          },
          {
            "at": "after_capture",
            "action": "reenter_saved_issuer"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "escaped_issue_result": null,
        "escaped_current_calls": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-view-dead-at-postconsumer",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "save_read"
          },
          {
            "at": "after_consume",
            "action": "reenter_saved_read"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "escaped_results": [
          null
        ],
        "escaped_current_calls": 0,
        "escaped_materializations": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close-signal-replayable-no-resource-ACK",
      "stimulus": {
        "procedure": "close_signal_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "controller",
            "action": "close_original_await_signal_twice"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1,
        "close_signal_results": [
          true,
          true
        ],
        "resource_cleanup_claimed": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-foreign-revoked-request-own-ticket",
      "stimulus": {
        "procedure": "foreign_read",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "setup",
            "action": "capture_own_ticket_enter_consumer_then_reset_counters"
          },
          {
            "at": "read",
            "action": "foreign_revoked_request_own_ticket"
          }
        ],
        "caller_claims_accepted": false,
        "counter_window": "Inside actual own consumer callback after its before_consume check and entry; reset all counters immediately BEFORE the foreign read; fail terminates callback, so no after_consume check."
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-foreign-own-request-revoked-ticket",
      "stimulus": {
        "procedure": "foreign_read",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "setup",
            "action": "capture_own_ticket_enter_consumer_then_reset_counters"
          },
          {
            "at": "read",
            "action": "own_request_revoked_ticket"
          }
        ],
        "caller_claims_accepted": false,
        "counter_window": "Inside actual own consumer callback after its before_consume check and entry; reset all counters immediately BEFORE the foreign read; fail terminates callback, so no after_consume check."
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-foreign-other-factory-ticket",
      "stimulus": {
        "procedure": "foreign_read",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "setup",
            "action": "capture_own_ticket_enter_consumer_then_reset_counters"
          },
          {
            "at": "read",
            "action": "own_request_other_factory_ticket"
          }
        ],
        "caller_claims_accepted": false,
        "counter_window": "Inside actual own consumer callback after its before_consume check and entry; reset all counters immediately BEFORE the foreign read; fail terminates callback, so no after_consume check."
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-foreign-other-request-same-factory-ticket",
      "stimulus": {
        "procedure": "foreign_read",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "setup",
            "action": "capture_own_ticket_enter_consumer_then_reset_counters"
          },
          {
            "at": "read",
            "action": "other_own_request_own_ticket"
          }
        ],
        "caller_claims_accepted": false,
        "counter_window": "Inside actual own consumer callback after its before_consume check and entry; reset all counters immediately BEFORE the foreign read; fail terminates callback, so no after_consume check."
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-foreign-source-return-token",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "return_other_factory_ticket"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-source-throwing-proxy-token",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "return_throwing_proxy_token"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-source-defect-fixed-no-echo",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "die_private_sentinel"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-consumer-defect-fixed-no-echo",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "consumer",
            "action": "die_private_sentinel_before_read"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 3,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-pending-source-interrupt-no-resources",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "await_gate"
          },
          {
            "at": "controller",
            "action": "interrupt_owned_fiber"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "interruption",
        "safe_code": null,
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-busy-before-second-capture",
      "stimulus": {
        "procedure": "busy_second_capture",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "await_gate"
          },
          {
            "at": "controller",
            "action": "second_capture_same_request_counter_window"
          },
          {
            "at": "cleanup",
            "action": "interrupt_first_and_join"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_busy",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-throwing-proxy",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "throwing_Proxy_all_traps"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-revoked-proxy",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "revoked_Proxy"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-coercion",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "coercion_hooks"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-number",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": 1
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-malformed",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-trailing",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"} null"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-escaped-duplicate",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\",\"source_\\u0069d\":\"duplicate\"}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-lone-raw-surrogate",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "UTF16_units",
          "units": [
            55296
          ]
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-lone-escape-surrogate",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"\\ud800\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-nul",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"\\u0000\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-grant_revision--0",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"-0\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-grant_revision-01",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"01\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-grant_revision-18446744073709551616",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"18446744073709551616\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-source_contract_revision-0",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"0\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-source_contract_revision-4294967296",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"4294967296\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-source_contract_revision-1",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":1,\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-source_purpose-export",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"export\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-destination-cloud",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"cloud\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-domain-location",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"location\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-invalid-source_id-",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-extra-caller_capture_grant",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"caller_capture_grant\":true,\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-extra-record_payload",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"record_payload\":{},\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-extra-title",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\",\"title\":\"SYNTHETIC_SECRET\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-source-id-byte-boundary-128",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-source-id-byte-boundary-129",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "candidate_limit_exceeded",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-UTF8-two-byte-limit",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-UTF8-two-byte-over",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "candidate_limit_exceeded",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-UTF8-wire-4096",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "
        }
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-UTF8-wire-4097",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "candidate_limit_exceeded",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-title-payload",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"window_title\":\"SYNTHETIC_SECRET\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-records-payload",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"records\":[],\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-unknown-install-with-value",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\",\"value\":\"fake\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-aggregate-session-detail",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"observed_app_session\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-wrong-source",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"other-source\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-wrong-revision",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"2\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-health-mapped-from-GPS",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"health\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"health_fact\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_rejected_metadata_then_fixed_codec_failure"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-UTF8-wire-16384",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "metadata_wire_override",
            "wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  "
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  ",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-metadata-UTF8-wire-16385",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "metadata_wire_override",
            "wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   "
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "private_catalog_codec",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-depth-over",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "[[[[[[[[[[[[[[[[null]]]]]]]]]]]]]]]]"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "candidate_limit_exceeded",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-nodes-over",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "candidate_limit_exceeded",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-depth-at",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "[[[[[[[[[[[[[[[null]]]]]]]]]]]]]]]"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-nodes-at",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-unreported-capability-never-known-zero",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"detail\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"display\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"export\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"query\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"not_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"detail\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"display\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"export\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"query\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"not_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "available_history_inferred": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-browser-title-excluded-not-detail-grant",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "observe_title": false,
        "title_granted": false
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-frontier-before-source",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_capture",
            "action": "frontier_mismatch",
            "current_frontier": "2",
            "requested_frontier": "1"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "scope_binding_mismatch",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-u32-source-revision-maximum",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"4294967295\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"4294967295\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"4294967295\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close-source-then-defect-fixedclosed",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "close_original_then_die_private_sentinel"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 1,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-close-current-then-defect-fixedclosed",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "before_metadata_read",
            "action": "close_original_then_die_private_sentinel"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "owned_handoff_closed",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 4,
        "consumer_calls": 1,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 1
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-unreturned-same-callback-ticket-never-consumable",
      "stimulus": {
        "procedure": "unreturned_ticket_consume",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_extra_ticket_return_only_first",
            "extra_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"unknown\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}"
          },
          {
            "at": "controller",
            "action": "reset_counters_then_consume_unreturned_ticket"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-issuer-foreign-Proxy-request-no-traps",
      "stimulus": {
        "procedure": "capture_consume_assert",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "source",
            "action": "issue_with_foreign_proxy_request_then_valid_own_request"
          }
        ],
        "caller_claims_accepted": false
      },
      "expected": {
        "kind": "completion",
        "safe_code": null,
        "metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 1,
        "current_calls": 6,
        "consumer_calls": 1,
        "metadata_materializations": 1,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "foreign_issue_result": null,
        "foreign_issue_current_calls": 0,
        "foreign_issue_traps": 0
      },
      "source_basis": "C14/C16/P01/O08/F15; accepted bounded PERSONAL-CONTRACT; new private metadata grammar/ownership policy before implementation, not native qualification"
    },
    {
      "case_id": "catalog-request-unknown-key-decoded-UTF8-512",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "key_scan",
            "action": "enforce_individual_key_UTF8_before_unknown_key_check",
            "decoded_key_UTF8_bytes": 512
          },
          {
            "at": "excluded_value",
            "action": "never_decode_or_materialize_unknown_value"
          }
        ],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\",\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\":{\"records\":[\"SYNTHETIC_SECRET_RECORD\"],\"window_title\":\"SYNTHETIC_SECRET_EXCLUDED_VALUE\"}}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "invalid_request",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "excluded_value_decoded": false,
        "unknown_key_echoed": false
      },
      "source_basis": "Independent BEFORE-code private grammar bound and rejection precedence: individual decoded unknown key 512 UTF8bytes; cap512 first, then closed-key membership. No candidate/source numeric or public parser equivalence."
    },
    {
      "case_id": "catalog-request-unknown-key-decoded-UTF8-513",
      "stimulus": {
        "procedure": "request_only",
        "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
        "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
        "actions": [
          {
            "at": "key_scan",
            "action": "enforce_individual_key_UTF8_before_unknown_key_check",
            "decoded_key_UTF8_bytes": 513
          },
          {
            "at": "excluded_value",
            "action": "never_decode_or_materialize_unknown_value"
          }
        ],
        "caller_claims_accepted": false,
        "input_override": {
          "kind": "primitive",
          "value": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\",\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\":{\"records\":[\"SYNTHETIC_SECRET_RECORD\"],\"window_title\":\"SYNTHETIC_SECRET_EXCLUDED_VALUE\"}}"
        }
      },
      "expected": {
        "kind": "private_failure",
        "safe_code": "candidate_limit_exceeded",
        "metadata_wire": null,
        "provider_echo": false,
        "known_zero_fabricated": false,
        "published_external": false,
        "source_calls": 0,
        "current_calls": 0,
        "consumer_calls": 0,
        "metadata_materializations": 0,
        "record_payload_reads": 0,
        "title_value_reads": 0,
        "store_acquisitions": 0,
        "allocation_calls": 0,
        "commit_calls": 0,
        "release_attempts": 0,
        "resource_ACKs": 0,
        "external_IO_calls": 0,
        "caller_traps": 0,
        "new_callbacks_after_close": 0,
        "replacement_service_calls": 0,
        "close_signal_completions": 0,
        "excluded_value_decoded": false,
        "unknown_key_echoed": false
      },
      "source_basis": "Independent BEFORE-code private grammar bound and rejection precedence: individual decoded unknown key 513 UTF8bytes; cap512 first, then closed-key membership. No candidate/source numeric or public parser equivalence."
    }
  ],
  "retained81_contract_case_mapping": [
    {
      "case_id": "combined-three-domains",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "combined-three-domains",
        "input": {
          "manifest_ref": "#/combined_manifest",
          "records": [
            "synthetic-health-1",
            "synthetic-location-1",
            "synthetic-usage-aggregate-1"
          ]
        },
        "expected": {
          "accept": true,
          "domains": [
            "health",
            "location",
            "device_usage"
          ],
          "record_count": 3,
          "completeness": "partial",
          "native_archive_complete": false
        },
        "evidence_refs": [
          "domain-lineage",
          "health-fixtures"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "health-scoped-same-dataset",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "health-scoped-same-dataset",
        "input": {
          "manifest_ref": "#/combined_manifest",
          "selection_override": {
            "domains": [
              "health"
            ]
          }
        },
        "expected": {
          "dataset_id": "synthetic-dataset-a",
          "record_ids": [
            "synthetic-health-1"
          ],
          "coverage_domains": [
            "health"
          ],
          "no_location_or_usage_detail": true
        },
        "evidence_refs": [
          "domain-lineage",
          "domain-grants"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "point-binary64-lossless",
      "source_authority": "accepted_draft",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "point-binary64-lossless",
        "input": {
          "record_ref": "#/records/1"
        },
        "expected": {
          "timestamp_bits": "3ff0000000000001",
          "epoch": "apple_reference_2001",
          "invented_nanoseconds": false,
          "latitude_bits": "3ff0000000000000",
          "altitude_state": "absent"
        },
        "evidence_refs": [
          "location-point"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "health-large-integer-lossless",
      "source_authority": "accepted_draft",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "health-large-integer-lossless",
        "input": {
          "record_ref": "#/records/0"
        },
        "expected": {
          "decimal": "9007199254740993",
          "number_coercion": false,
          "unit": "count"
        },
        "evidence_refs": [
          "health-precision"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "health-negativezero-preserve",
      "source_authority": "accepted_draft",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "health-negativezero-preserve",
        "input": {
          "value": {
            "representation": "binary64",
            "bits": "8000000000000000",
            "unit": "count"
          }
        },
        "expected": {
          "bits": "8000000000000000",
          "normalized_to_positive_zero": false
        },
        "evidence_refs": [
          "health-precision"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "mixed-epoch-selection-precision",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "mixed-epoch-selection-precision",
        "input": {
          "record_ref": "#/records/1",
          "selection_ref": "#/combined_manifest/selection"
        },
        "expected": {
          "inside_requested_interval": true,
          "point_bits_unchanged": "3ff0000000000001",
          "comparison": "exact_binary_rational_epoch_conversion_required",
          "round_timestamp_for_selection": false
        },
        "evidence_refs": [
          "location-point",
          "health-precision"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "timestamp-nanos-order",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "timestamp-nanos-order",
        "input": {
          "left": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "9007199254740993",
            "nanoseconds": 1,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "right": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "9007199254740993",
            "nanoseconds": 2,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          }
        },
        "expected": {
          "order": "left_before_right",
          "Date_or_Number_ordering": false
        },
        "evidence_refs": [
          "health-precision"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "native-calendar-not-inferred",
      "source_authority": "accepted_draft",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "native-calendar-not-inferred",
        "input": {
          "record_ref": "#/records/1"
        },
        "expected": {
          "owner_date": "unknown",
          "timezone": "unknown",
          "derive_from_current_host_zone": false
        },
        "evidence_refs": [
          "location-point",
          "mac-clock"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "aggregate-not-session",
      "source_authority": "accepted_draft",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "aggregate-not-session",
        "input": {
          "record_ref": "#/records/2"
        },
        "expected": {
          "kind": "usage_aggregate",
          "duration_seconds": 600,
          "bucket_seconds": 3600,
          "synthesized_session": false,
          "fill_whole_bucket": false
        },
        "evidence_refs": [
          "mobile-ios",
          "mobile-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "short-session-retained",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "short-session-retained",
        "input": {
          "record_ref": "#/records/3"
        },
        "expected": {
          "persist_future_observed": true,
          "duration_seconds": 1,
          "discard_below_two_seconds": false
        },
        "evidence_refs": [
          "mac-clock"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "historical-donor-short-tail-gap",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "historical-donor-short-tail-gap",
        "input": {
          "donor_gap": [
            "discarded_short",
            "crash_unflushed",
            "pre_collector"
          ]
        },
        "expected": {
          "reconstruct_exact_session": false,
          "coverage": "partial",
          "gap_retained": true
        },
        "evidence_refs": [
          "mac-clock",
          "mac-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "ios-exact-sessions-unestablished",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "ios-exact-sessions-unestablished",
        "input": {
          "source": "ios_historical_usage_aggregate",
          "requested_kind": "foreground_app_session"
        },
        "expected": {
          "fabricate": false,
          "outcome": "unavailable_for_this_source",
          "S06": "required_open",
          "aggregate_shipping_closes_S06": false
        },
        "evidence_refs": [
          "mobile-ios",
          "mobile-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "android-prototype-not-supported",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "android-prototype-not-supported",
        "input": {
          "source": "donor_android_event_prototype"
        },
        "expected": {
          "health_android_usage_state": "planned",
          "native_build_capture_coverage_proof": "pending",
          "claim_shared_support": false
        },
        "evidence_refs": [
          "mobile-android"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "unknown-empty-is-not-zero",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "unknown-empty-is-not-zero",
        "input": {
          "source_response": [],
          "coverage": "unknown"
        },
        "expected": {
          "known_usage_seconds": null,
          "coverage": "unknown"
        },
        "evidence_refs": [
          "mobile-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-SOURCE-COVERAGE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "unavailable-empty-is-not-zero",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "unavailable-empty-is-not-zero",
        "input": {
          "source_response": [],
          "coverage": "unavailable",
          "reason": "source_policy_unavailable"
        },
        "expected": {
          "known_usage_seconds": null,
          "coverage": "unavailable",
          "reason_preserved": true
        },
        "evidence_refs": [
          "mobile-ios"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-SOURCE-COVERAGE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "observed-zero-only-evidence",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "observed-zero-only-evidence",
        "input": {
          "source_value": {
            "representation": "unsigned_integer",
            "decimal": "0",
            "unit": "second"
          },
          "coverage": "complete",
          "completion_evidence": "synthetic_source_receipt",
          "scope": "synthetic_interval_only"
        },
        "expected": {
          "known_zero": true,
          "extend_to_other_period_device_detail": false
        },
        "evidence_refs": [
          "domain-lineage"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-SOURCE-COVERAGE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "no-fabricated-completeness",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "no-fabricated-completeness",
        "input": {
          "record_count": 0,
          "source_observedSources_flag": true,
          "source_receipt": null
        },
        "expected": {
          "complete": false,
          "coverage": "unknown"
        },
        "evidence_refs": [
          "mobile-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-SOURCE-COVERAGE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "hourly-daily-overlap",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "hourly-daily-overlap",
        "input": {
          "hourly_duration_seconds": "600",
          "daily_duration_seconds": "600",
          "same_source_device_scope": true,
          "same_overlap_group": "synthetic-hourly-daily-group"
        },
        "expected": {
          "sum_seconds": "600",
          "not_sum_seconds": "1200",
          "method": "explicit_reviewed_projection_precedence",
          "originals_retained": true
        },
        "evidence_refs": [
          "mobile-history",
          "domain-lineage"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "cross-device-overlap",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "cross-device-overlap",
        "input": {
          "source_a_total_seconds": "600",
          "source_b_total_seconds": "600",
          "identity_equivalence": "unknown"
        },
        "expected": {
          "automatic_person_total_seconds": null,
          "retain_separate_source_totals": true
        },
        "evidence_refs": [
          "mobile-ios",
          "domain-lineage"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-SOURCE-COVERAGE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "same-key-same-bytes-replay",
      "source_authority": "accepted_draft",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "same-key-same-bytes-replay",
        "input": {
          "lineage_key": "synthetic-key-a",
          "original_bytes_digest": [
            "synthetic-digest-a",
            "synthetic-digest-a"
          ]
        },
        "expected": {
          "logical_records": 1,
          "idempotent": true,
          "source_lineage_retained": true
        },
        "evidence_refs": [
          "domain-transfer"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "same-key-different-bytes-conflict",
      "source_authority": "accepted_draft",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "same-key-different-bytes-conflict",
        "input": {
          "lineage_key": "synthetic-key-a",
          "original_bytes_digest": [
            "synthetic-digest-a",
            "synthetic-digest-b"
          ]
        },
        "expected": {
          "accept": false,
          "safe_code": "record_identity_conflict",
          "silent_replace": false
        },
        "evidence_refs": [
          "domain-transfer"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "new-install-not-same-device-history",
      "source_authority": "accepted_draft",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "new-install-not-same-device-history",
        "input": {
          "device_id": "synthetic-device-a",
          "installation_ids": [
            "synthetic-install-a",
            "synthetic-install-c"
          ]
        },
        "expected": {
          "preserve_two_installations": true,
          "automatic_dedup": false
        },
        "evidence_refs": [
          "domain-lineage"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "missing-donor-lineage",
      "source_authority": "accepted_draft",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "missing-donor-lineage",
        "input": {
          "original_device": "missing",
          "source_record_id": "missing",
          "import_artifact_id": "synthetic-artifact-a",
          "partition": "synthetic-partition-a",
          "ordinal": "0"
        },
        "expected": {
          "original_identity": "unknown",
          "import_identity": "stable_artifact_partition_ordinal",
          "fabricated_device_or_session_link": false
        },
        "evidence_refs": [
          "location-point",
          "mobile-ios"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "correction-preserves-original",
      "source_authority": "accepted_draft",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "correction-preserves-original",
        "input": {
          "original_record_id": "synthetic-location-1",
          "correction_id": "synthetic-correction-a",
          "correction_timestamp": "not_reported"
        },
        "expected": {
          "original_immutable": true,
          "correction_linked": true,
          "timestamp_invented": false,
          "undo": "append_reversal_preserving_original"
        },
        "evidence_refs": [
          "location-visit",
          "domain-transfer"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-CORRECTION",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "visit-sentinel-not-observed",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "visit-sentinel-not-observed",
        "input": {
          "arrival": "distantPast",
          "departure": "distantFuture",
          "donor_default": "automatic"
        },
        "expected": {
          "sentinel_as_real_epoch": false,
          "certainty": "unknown",
          "default_proves_observation": false
        },
        "evidence_refs": [
          "location-visit"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "outing-not-recording",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "outing-not-recording",
        "input": {
          "source_kind": "inferred_outing",
          "summary_id": "synthetic-summary-a"
        },
        "expected": {
          "recording_session_uuid": null,
          "kind": "inferred_outing",
          "inference_revision_required": true
        },
        "evidence_refs": [
          "location-session"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "browser-app-duration-allowed",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "browser-app-duration-allowed",
        "input": {
          "record_ref": "#/records/2"
        },
        "expected": {
          "app_duration_allowed_under_own_grants": true,
          "window_title_or_domain_allowed": false,
          "missing_human_label_omits_app": false
        },
        "evidence_refs": [
          "mac-exclusions",
          "mobile-exclusions"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "browser-title-before-observation",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "browser-title-before-observation",
        "input": {
          "app_class": "browser",
          "requested_detail": "desktop_window_title",
          "title_grant": true
        },
        "expected": {
          "call_title_API": false,
          "persist_title": false,
          "queue_title": false,
          "export_or_log_title": false,
          "safe_code": "detail_excluded"
        },
        "evidence_refs": [
          "mac-exclusions",
          "mobile-exclusions"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "unknown-app-class-title-fails-closed",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "unknown-app-class-title-fails-closed",
        "input": {
          "app_class": "unknown",
          "requested_detail": "desktop_window_title"
        },
        "expected": {
          "call_title_API": false,
          "persist_title": false,
          "safe_code": "detail_unadmitted"
        },
        "evidence_refs": [
          "mac-exclusions"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "excluded-import-before-staging",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "excluded-import-before-staging",
        "input": {
          "incoming_fields": [
            "browser_url",
            "page_title",
            "typed_text",
            "mouse_coordinates"
          ],
          "migration_requested": true
        },
        "expected": {
          "observe_payload": false,
          "copy_to_staging_or_queue": false,
          "quarantine_payload_copy": false,
          "fixed_field_presence_report_only": true,
          "source_donor_unchanged": true
        },
        "evidence_refs": [
          "mac-exclusions",
          "mobile-exclusions",
          "domain-grants"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "capture-not-export-grant",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "capture-not-export-grant",
        "input": {
          "capture": "allowed",
          "display": "allowed",
          "query": "allowed",
          "export": "not_authorized",
          "destination": "synthetic-local-file"
        },
        "expected": {
          "export": false,
          "automatic_grant": false,
          "safe_code": "export_not_authorized"
        },
        "evidence_refs": [
          "domain-grants",
          "mobile-ios"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "report-view-not-record-export",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "report-view-not-record-export",
        "input": {
          "source": "standard_ios_report_sandbox",
          "display": "allowed",
          "export_request": true
        },
        "expected": {
          "export": false,
          "report_sandbox_escape": false,
          "capability": "display_only"
        },
        "evidence_refs": [
          "mobile-ios"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "future-uploads-not-auto-agent-grant",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "future-uploads-not-auto-agent-grant",
        "input": {
          "upload_enrollment": "allowed",
          "agent_current_snapshot": "allowed",
          "agent_future_uploads": "not_granted"
        },
        "expected": {
          "agent_new_upload_read": false,
          "grant_future_scope_inferred": false
        },
        "evidence_refs": [
          "domain-grants"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "title-query-not-agent-share",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "title-query-not-agent-share",
        "input": {
          "desktop_title_capture": "allowed",
          "desktop_title_local_query": "allowed",
          "agent_detail_grant": "absent"
        },
        "expected": {
          "agent_title": false,
          "upload_enrollment_implies_read": false
        },
        "evidence_refs": [
          "domain-grants"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "strict-scope-denied-no-leak",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "strict-scope-denied-no-leak",
        "input": {
          "selection_ref": "#/combined_manifest/selection",
          "denied_detail": "location_exact_point",
          "strictness": "strict"
        },
        "expected": {
          "publish_manifest_or_record": false,
          "partial_deliverable": false,
          "safe_code": "scope_not_authorized",
          "raw_record_id_or_coordinate_in_error": false
        },
        "evidence_refs": [
          "domain-grants"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "partial-scope-explicit",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "partial-scope-explicit",
        "input": {
          "selection_ref": "#/combined_manifest/selection",
          "denied_domain": "location",
          "strictness": "allow_partial"
        },
        "expected": {
          "deliverable_domains": [
            "health",
            "device_usage"
          ],
          "omitted_scope_status": "unavailable",
          "omitted_personal_payload": true,
          "manifest_complete": false
        },
        "evidence_refs": [
          "domain-grants",
          "domain-lineage"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "grant-revoked-during-page",
      "source_authority": "accepted_draft",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "grant-revoked-during-page",
        "input": {
          "grant_revision_before": "synthetic-grant1",
          "grant_revision_now": "synthetic-revoked2"
        },
        "expected": {
          "continue_page": false,
          "publish_staged_results": false,
          "recheck_source_purpose_destination": true
        },
        "evidence_refs": [
          "domain-grants"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "selector-cursor-crosswire",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "selector-cursor-crosswire",
        "input": {
          "requested_dataset": "synthetic-dataset-a",
          "cursor_dataset": "synthetic-dataset-b"
        },
        "expected": {
          "accept": false,
          "safe_code": "scope_binding_mismatch",
          "binding_required": [
            "caller",
            "dataset",
            "revision",
            "source",
            "purpose",
            "selection",
            "snapshot",
            "grant_revision",
            "expiry"
          ]
        },
        "evidence_refs": [
          "domain-lineage"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "geographic-health-distance-distinct",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "geographic-health-distance-distinct",
        "input": {
          "location_path_distance": "synthetic_location_distance",
          "health_distance": "distance_walking_running"
        },
        "expected": {
          "alias_semantic_id": false,
          "sum_as_same_statistic": false
        },
        "evidence_refs": [
          "health-precision",
          "location-point"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "frozen-health-profiles",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "frozen-health-profiles",
        "input": {
          "requested_profiles": [
            "apple_health_data_v8",
            "android_frozen_v4",
            "android_analytical_v5"
          ]
        },
        "expected": {
          "bytes_or_grammar_changed": false,
          "personal_candidate_admitted": false
        },
        "evidence_refs": [
          "health-fixtures"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "summary-not-complete-transfer",
      "source_authority": "accepted_draft",
      "classification": "separate_native_or_consumer",
      "unchanged_raw_contract": {
        "case_id": "summary-not-complete-transfer",
        "input": {
          "donor_artifacts": [
            "mac365daymirror",
            "mobile370snapshot",
            "location_formatted_export"
          ]
        },
        "expected": {
          "complete_native_archive": false,
          "required_full_retained_history": "all_available_permitted_native_state",
          "credentials_purchases_armed_schedules_adopted": false
        },
        "evidence_refs": [
          "domain-transfer",
          "mac-mirror",
          "location-transfer",
          "mobile-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "complete-history-no-dashboard-cap",
      "source_authority": "accepted_draft",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "complete-history-no-dashboard-cap",
        "input": {
          "available_history_days": "synthetic-more-than-370",
          "page_limit_records": 4096
        },
        "expected": {
          "iterate_all_available_authorized_pages": true,
          "global_history_cap_days": null,
          "invent_unavailable_history": false
        },
        "evidence_refs": [
          "mac-history",
          "mobile-history"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "nonfinite-or-overprecision",
      "source_authority": "accepted_draft",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "nonfinite-or-overprecision",
        "input": {
          "number_bits": "7ff0000000000000",
          "timestamp_nanos": 1000000000
        },
        "expected": {
          "accept": false,
          "safe_code": "invalid_exact_value",
          "coerce_or_round": false
        },
        "evidence_refs": [
          "health-precision"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "bounded-page-admission",
      "source_authority": "accepted_draft",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "bounded-page-admission",
        "input": {
          "candidate_record_raw_bytes": 65537,
          "candidate_page_record_count": 4097
        },
        "expected": {
          "accept": false,
          "safe_code": "candidate_limit_exceeded",
          "claim_production_budget": false
        },
        "evidence_refs": [
          "health-precision"
        ],
        "proof_class": "planning",
        "execution": "literal_expected_before_future_codec_not_executed"
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-coordinate-endpoints",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-coordinate-endpoints",
        "input": {
          "latitude": "4056800000000000",
          "longitude": "4066800000000000"
        },
        "expected": {
          "canonical_status": "valid",
          "latitude_degrees": 90,
          "longitude_degrees": 180,
          "wrap": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-coordinate-outside",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-coordinate-outside",
        "input": {
          "latitude": "4056c00000000000"
        },
        "expected": {
          "canonical_status": "outside_canonical",
          "reason": "coordinate_out_of_range",
          "retain_eligible_original_evidence": true
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-nonfinite-coordinate",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-nonfinite-coordinate",
        "input": {
          "latitude": "7ff8000000000000"
        },
        "expected": {
          "canonical_status": "outside_canonical",
          "canonical_value": null,
          "retain_eligible_original_evidence": true
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-negative-speed-sentinel",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-negative-speed-sentinel",
        "input": {
          "speed_bits": "bff0000000000000"
        },
        "expected": {
          "state": "unavailable",
          "reason": "native_invalid_speed",
          "original_bits_retained": "bff0000000000000",
          "complete_archive_silent_drop": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-negative-accuracy-sentinel",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-negative-accuracy-sentinel",
        "input": {
          "accuracy_bits": "bff0000000000000"
        },
        "expected": {
          "state": "unavailable",
          "reason": "native_invalid_accuracy",
          "coerce_zero": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-negativezero-speed",
      "source_authority": "accepted_resolution",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "resolution-negativezero-speed",
        "input": {
          "speed_bits": "8000000000000000"
        },
        "expected": {
          "canonical_status": "valid",
          "bits": "8000000000000000"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-reversed-session",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-reversed-session",
        "input": {
          "start_seconds": "2",
          "end_seconds": "1",
          "duration_bits": "bff0000000000000"
        },
        "expected": {
          "canonical_status": "outside_canonical",
          "reason": "clock_inconsistent",
          "invent_session": false,
          "retain_original": true
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-duration-disagreement",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-duration-disagreement",
        "input": {
          "start_seconds": "0",
          "end_seconds": "1",
          "duration_bits": "4000000000000000",
          "basis": "synthetic_observation"
        },
        "expected": {
          "canonical_status": "outside_canonical",
          "repair_duration": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-zero-session",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-zero-session",
        "input": {
          "start_seconds": "1",
          "end_seconds": "1",
          "duration_bits": "0000000000000000"
        },
        "expected": {
          "canonical_status": "valid",
          "retain": true,
          "membership": "point"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-original-record-equality",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-original-record-equality",
        "input": {
          "same_key": true,
          "same_lossless_field_vector": true,
          "artifact_whitespace_changed": true,
          "transport_page_changed": true
        },
        "expected": {
          "logical_originals": 1,
          "retain_two_import_evidence_links": true
        }
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-lossy-equality-conflict",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-lossy-equality-conflict",
        "input": {
          "same_key": true,
          "canonical_values_equal": true,
          "original_accuracy_bits_differ": true
        },
        "expected": {
          "accept": false,
          "safe_code": "record_identity_conflict"
        }
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-repartition-key",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-repartition-key",
        "input": {
          "original_artifact_id": "synthetic-artifact",
          "original_partition": "root",
          "ordinal": "7",
          "transport_pages": [
            "page-a",
            "page-b"
          ]
        },
        "expected": {
          "import_keys": 1,
          "native_original_identity": "unknown",
          "page_in_identity": false
        }
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-missing-stable-import-order",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-missing-stable-import-order",
        "input": {
          "native_id": "unknown",
          "stable_artifact_enumeration": false
        },
        "expected": {
          "automatic_merge": false,
          "import_identity": "unknown"
        }
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-apple-unix-equality",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-apple-unix-equality",
        "input": {
          "apple_bits": "0000000000000000",
          "unix_seconds": "978307200",
          "unix_nanos": 0
        },
        "expected": {
          "order": "equal",
          "stored_epoch_unchanged": true
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-dyadic-subnanosecond",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-dyadic-subnanosecond",
        "input": {
          "unix_bits": "3ff0000000000001",
          "query_start_seconds": "1",
          "query_start_nanos": 0,
          "query_end_seconds": "1",
          "query_end_nanos": 1
        },
        "expected": {
          "membership": true,
          "round_to_one_second": false,
          "source_nanos_invented": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-half-open-end",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-half-open-end",
        "input": {
          "point_seconds": "1",
          "start_seconds": "0",
          "end_seconds": "1"
        },
        "expected": {
          "membership": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-negative-floor-nanos",
      "source_authority": "accepted_resolution",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "resolution-negative-floor-nanos",
        "input": {
          "epoch_seconds": "-1",
          "nanoseconds": 999999999
        },
        "expected": {
          "exact_seconds": "-1/1000000000",
          "valid": true
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-aggregate-partial-strict",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-aggregate-partial-strict",
        "input": {
          "bucket": [
            "0",
            "3600"
          ],
          "query": [
            "1800",
            "3600"
          ],
          "duration_seconds": "600",
          "strictness": "strict"
        },
        "expected": {
          "deliverable": false,
          "safe_code": "aggregate_partial_overlap",
          "estimated_seconds": null
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-aggregate-partial-allowed",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-aggregate-partial-allowed",
        "input": {
          "bucket": [
            "0",
            "3600"
          ],
          "query": [
            "1800",
            "3600"
          ],
          "strictness": "allow_partial"
        },
        "expected": {
          "selected_aggregate_count": 0,
          "coverage": "partial",
          "complete": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-aggregate-whole-context",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-aggregate-whole-context",
        "input": {
          "bucket": [
            "0",
            "3600"
          ],
          "query": [
            "1800",
            "3600"
          ],
          "duration_seconds": "600",
          "projection": "whole_bucket_context",
          "whole_bucket_grant": true
        },
        "expected": {
          "duration_seconds": "600",
          "extends_beyond_selection": true,
          "requested_interval_total": null
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-aggregate-context-denied",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-aggregate-context-denied",
        "input": {
          "projection": "whole_bucket_context",
          "whole_bucket_grant": false
        },
        "expected": {
          "materialize": false,
          "safe_code": "scope_not_authorized"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-observed-session-clip",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-observed-session-clip",
        "input": {
          "original": [
            "0",
            "10"
          ],
          "query": [
            "3",
            "7"
          ],
          "consistent_observation": true
        },
        "expected": {
          "original": [
            "0",
            "10"
          ],
          "derived_interval": [
            "3",
            "7"
          ],
          "derived_duration_seconds": "4",
          "derived_not_original": true
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-tombstone-replay",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-tombstone-replay",
        "input": {
          "tombstone_revision": "2",
          "replay_original_revision": "1"
        },
        "expected": {
          "query_visible": false,
          "export_visible": false,
          "original_evidence_immutable": true
        }
      },
      "selected_child": "DATASTORE-LOCAL-TOMBSTONE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-correction-under-tombstone",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-correction-under-tombstone",
        "input": {
          "tombstone_current": true,
          "correction_new": true,
          "explicit_restore": false
        },
        "expected": {
          "current_projection_visible": false
        }
      },
      "selected_child": "DATASTORE-CORRECTION",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-delete-backup-regrant",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-delete-backup-regrant",
        "input": {
          "deletion_fence_current": true,
          "old_backup": true,
          "new_capture_grant": true
        },
        "expected": {
          "resurrect": false,
          "publish": false
        }
      },
      "selected_child": "DATASTORE-LOCAL-TOMBSTONE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-frontier-changes-before-commit",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-frontier-changes-before-commit",
        "input": {
          "page_frontier": "1",
          "current_frontier": "2"
        },
        "expected": {
          "commit": false,
          "staged_visible": false,
          "safe_code": "scope_binding_mismatch"
        }
      },
      "selected_child": "DATASTORE-BATCH-CHECKPOINT",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-recipient-copy-limit",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-recipient-copy-limit",
        "input": {
          "recipient_already_downloaded": true,
          "grant_now_revoked": true
        },
        "expected": {
          "new_reads": false,
          "recall_claim": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-schema-boolean-version",
      "source_authority": "accepted_resolution",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "resolution-schema-boolean-version",
        "input": {
          "payload_revision": true
        },
        "expected": {
          "accept": false,
          "safe_code": "unsupported_shape"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-unknown-source-field",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-unknown-source-field",
        "input": {
          "new_source_field": true,
          "same_canonical_projection": true
        },
        "expected": {
          "silently_discard": false,
          "admit_unreviewed_schema": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-archive-excluded-title",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-archive-excluded-title",
        "input": {
          "browser_title_present": true,
          "archive_grant": true
        },
        "expected": {
          "observe_or_stage_title": false,
          "complete_eligible_archive_includes_title": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-reasonless-sensor-absent",
      "source_authority": "accepted_resolution",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "resolution-reasonless-sensor-absent",
        "input": {
          "altitude": {
            "state": "absent"
          },
          "speed": {
            "state": "absent"
          }
        },
        "expected": {
          "accept": true,
          "reason_required": false
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-absent-sensor-wrong-value",
      "source_authority": "accepted_resolution",
      "classification": "codec",
      "unchanged_raw_contract": {
        "case_id": "resolution-absent-sensor-wrong-value",
        "input": {
          "speed": {
            "state": "absent",
            "value": 0
          }
        },
        "expected": {
          "accept": false,
          "safe_code": "unsupported_shape"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-native-source-rounded-subtraction",
      "source_authority": "accepted_resolution",
      "classification": "codec_subcase_and_later_gate",
      "unchanged_raw_contract": {
        "case_id": "resolution-native-source-rounded-subtraction",
        "input": {
          "start_bits": "3fb999999999999a",
          "end_bits": "3ff199999999999a",
          "duration_bits": "3ff0000000000000",
          "basis": "native_source_arithmetic"
        },
        "expected": {
          "exact_endpoint_difference": "36028797018963971/36028797018963968",
          "source_duration_bits_retained": "3ff0000000000000",
          "automatic_clock_inconsistent": false,
          "current_synthetic_admission": false,
          "future_source_semantic_qualification": "required"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-CODECS accepted bounded codec plus source/projection admission",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-delete-restore-denied",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-delete-restore-denied",
        "input": {
          "deletion_fence_current": true,
          "explicit_restore_event": true,
          "restore_revision_above_delete": true,
          "new_grant": true
        },
        "expected": {
          "restore": false,
          "query_or_export": false,
          "safe_code": "restoration_fenced"
        }
      },
      "selected_child": "DATASTORE-LOCAL-TOMBSTONE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-authoritative-frontier-restore-denied",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-authoritative-frontier-restore-denied",
        "input": {
          "current_external_suppression_journal": true,
          "local_restore_event": true,
          "backup_or_renamed_record": true
        },
        "expected": {
          "restore": false,
          "publish": false,
          "safe_code": "restoration_fenced"
        }
      },
      "selected_child": "DATASTORE-LOCAL-TOMBSTONE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-local-tombstone-reversible-only",
      "source_authority": "accepted_resolution",
      "classification": "separate_repository",
      "unchanged_raw_contract": {
        "case_id": "resolution-local-tombstone-reversible-only",
        "input": {
          "local_tombstone": true,
          "deletion_or_revocation_fence": false,
          "evidence_eligible": true,
          "reviewed_restore_intent_and_current_grants": true
        },
        "expected": {
          "candidate_local_reversal_permitted": true,
          "override_external_frontier": false,
          "durable_restoration_execution_qualified": false
        }
      },
      "selected_child": "DATASTORE-LOCAL-TOMBSTONE",
      "remaining_owner": null,
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    },
    {
      "case_id": "resolution-unrepresentable-clipped-duration",
      "source_authority": "accepted_resolution",
      "classification": "separate_query_or_projection",
      "unchanged_raw_contract": {
        "case_id": "resolution-unrepresentable-clipped-duration",
        "input": {
          "exact_duration": "36028797018963971/36028797018963968",
          "accepted_rational_or_ticks_derivation_schema": false
        },
        "expected": {
          "projection": false,
          "round_to_binary64": false,
          "safe_code": "exact_projection_unrepresentable"
        }
      },
      "selected_child": null,
      "remaining_owner": "PERSONAL-QUERY-PROJECTION or DATASTORE-SOURCE-ADMISSION-HISTORY",
      "closure": "Retained independent obligation; selected child exercises only private applicable edge, not whole public/native/source parity."
    }
  ],
  "original_four_records_and_combined59": "Unmodified prior rawvectors274b6dc8/2a877775 remain authorities, not copied source record payload into metadata.",
  "repository_baseline_mapping_17": [
    {
      "baseline_row": {
        "id": "DOMAIN-001",
        "outcome": "/native_history/storage",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/native_history/storage",
          "canonical_value_sha256": "546f6374513faa2b639a9f9537bb697a8edfb0d9fe0adccd8818cc77235975e1"
        },
        "leaf_pointers": [
          "/native_history/storage/source",
          "/native_history/storage/implementation",
          "/native_history/storage/history"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-BATCH-CHECKPOINT",
      "real_remainder_owner": "DATASTORE-DURABLE-HOSTS",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-006",
        "outcome": "/native_history/capture",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/native_history/capture",
          "canonical_value_sha256": "a902ce069569d90e5f24fc78d507916e68d3a42a673ad474315e446ab0a82d0a"
        },
        "leaf_pointers": [
          "/native_history/capture/source",
          "/native_history/capture/native",
          "/native_history/capture/restore",
          "/native_history/capture/quality_compatibility",
          "/native_history/capture/visit_matching_bounds/coordinate_match_meters",
          "/native_history/capture/visit_matching_bounds/arrival_tolerance_seconds",
          "/native_history/capture/visit_matching_bounds/duplicate_merge_meters",
          "/native_history/capture/visit_matching_bounds/duplicate_merge_gap_seconds",
          "/native_history/capture/boundary"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-COVERAGE",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-067",
        "outcome": "/successor_source_admission/status",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/successor_source_admission/status",
          "canonical_value_sha256": "ed4379147ce3430fa095da35ce65127239cd89e7445fd965b09d25d570cc720e"
        },
        "leaf_pointers": [
          "/successor_source_admission/status"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-CATALOG",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-068",
        "outcome": "/successor_source_admission/source",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/successor_source_admission/source",
          "canonical_value_sha256": "e846e47d15037bd16de47c2d410df287be9b6bd3dfe7fe78b1555d40bd4b725d"
        },
        "leaf_pointers": [
          "/successor_source_admission/source"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-CATALOG",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-069",
        "outcome": "/successor_source_admission/retention",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/successor_source_admission/retention",
          "canonical_value_sha256": "c940f012f023af12f5d81210a000d45cad7667d088e85591c601a680b510de4f"
        },
        "leaf_pointers": [
          "/successor_source_admission/retention"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-RETENTION",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-070",
        "outcome": "/successor_source_admission/health_boundary",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/successor_source_admission/health_boundary",
          "canonical_value_sha256": "15a6215c8aa0ba925a8108a87f558f16ec4792a12b68c949fd0cf10870a9e3f2"
        },
        "leaf_pointers": [
          "/successor_source_admission/health_boundary"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-CATALOG",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-071",
        "outcome": "/successor_source_admission/deferred",
        "route": "repository",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/successor_source_admission/deferred",
          "canonical_value_sha256": "d11c2fd441389bf10a7bee9c963ccd587d573add9e207d08df105372acc8fd02"
        },
        "leaf_pointers": [
          "/successor_source_admission/deferred"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-CATALOG",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-120",
        "outcome": "/history/primary",
        "route": "repository",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/history/primary",
          "canonical_value_sha256": "9350c299c38608fb23a938801dbb9ca439e257e21e10800cc41be7089aace71b"
        },
        "leaf_pointers": [
          "/history/primary/source",
          "/history/primary/source_defined_path",
          "/history/primary/table",
          "/history/primary/columns/0",
          "/history/primary/columns/1",
          "/history/primary/columns/2",
          "/history/primary/columns/3",
          "/history/primary/columns/4",
          "/history/primary/columns/5",
          "/history/primary/columns/6",
          "/history/primary/columns/7",
          "/history/primary/columns/8",
          "/history/primary/columns/9",
          "/history/primary/columns/10",
          "/history/primary/columns/11",
          "/history/primary/columns/12",
          "/history/primary/columns/13",
          "/history/primary/meaning"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-BATCH-CHECKPOINT",
      "real_remainder_owner": "DATASTORE-DURABLE-HOSTS",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-121",
        "outcome": "/history/mirror",
        "route": "repository",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/history/mirror",
          "canonical_value_sha256": "f2cba86e594a370d0353e6ce104a2eb1a86bbfca88c5811a8096e75bddf06dd2"
        },
        "leaf_pointers": [
          "/history/mirror/source",
          "/history/mirror/path",
          "/history/mirror/version",
          "/history/mirror/history_days",
          "/history/mirror/debounce_seconds",
          "/history/mirror/fields/0",
          "/history/mirror/fields/1",
          "/history/mirror/fields/2",
          "/history/mirror/fields/3",
          "/history/mirror/fields/4",
          "/history/mirror/fields/5",
          "/history/mirror/behavior",
          "/history/mirror/continuation_loss_evidence/0/path",
          "/history/mirror/continuation_loss_evidence/0/line",
          "/history/mirror/continuation_loss_evidence/0/literal",
          "/history/mirror/continuation_loss_evidence/0/meaning",
          "/history/mirror/continuation_loss_evidence/1/path",
          "/history/mirror/continuation_loss_evidence/1/line",
          "/history/mirror/continuation_loss_evidence/1/through_line",
          "/history/mirror/continuation_loss_evidence/1/meaning",
          "/history/mirror/continuation_loss_evidence/2/path",
          "/history/mirror/continuation_loss_evidence/2/line",
          "/history/mirror/continuation_loss_evidence/2/literal",
          "/history/mirror/continuation_loss_evidence/2/meaning"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": "Retained lossy summary compatibility only; raw source sessions are full-history authority. Preserve continuation-hour/cross-midnight filtering loss and three synthetic regression obligations."
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-COVERAGE",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-124",
        "outcome": "/history/identity",
        "route": "repository",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/history/identity",
          "canonical_value_sha256": "27679f8a9be60e88a45e90b882780db84d3d1fe7120dd5684d68dbd16750e177"
        },
        "leaf_pointers": [
          "/history/identity/sources/0",
          "/history/identity/sources/1",
          "/history/identity/sources/2",
          "/history/identity/tracker_device",
          "/history/identity/sync_installation",
          "/history/identity/record",
          "/history/identity/legacy"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-BATCH-CHECKPOINT",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-125",
        "outcome": "/history/dedup",
        "route": "repository",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/history/dedup",
          "canonical_value_sha256": "452afd4add5d17f1009d869ff26890257acbc86b516c935d714a8c14779590f0"
        },
        "leaf_pointers": [
          "/history/dedup/sources/0",
          "/history/dedup/sources/1",
          "/history/dedup/sources/2",
          "/history/dedup/local_unique/0",
          "/history/dedup/local_unique/1",
          "/history/dedup/local_unique/2",
          "/history/dedup/local_predicate",
          "/history/dedup/import_unique/0",
          "/history/dedup/import_unique/1",
          "/history/dedup/import_unique/2",
          "/history/dedup/import_predicate",
          "/history/dedup/order",
          "/history/dedup/rollups"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-BATCH-CHECKPOINT",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-224",
        "outcome": "/history_and_precision/source_paths",
        "route": "repository",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/history_and_precision/source_paths",
          "canonical_value_sha256": "5ca237e30ec99486f3ba05225948d15998a0308ebe2e57d401779c4dde71fb4d"
        },
        "leaf_pointers": [
          "/history_and_precision/source_paths/0",
          "/history_and_precision/source_paths/1",
          "/history_and_precision/source_paths/2"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-CATALOG",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-225",
        "outcome": "/history_and_precision/retained",
        "route": "repository",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/history_and_precision/retained",
          "canonical_value_sha256": "cb1a23d28a2e648c5de7972c2fdcce1effea424e9bb558b229f32e432daf9c7c"
        },
        "leaf_pointers": [
          "/history_and_precision/retained"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-COVERAGE",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-226",
        "outcome": "/history_and_precision/persistence",
        "route": "repository",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/history_and_precision/persistence",
          "canonical_value_sha256": "c128b384586b0e27d75a54476c7e99e6d2b97b84751862558358ccfab61935e3"
        },
        "leaf_pointers": [
          "/history_and_precision/persistence"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-BATCH-CHECKPOINT",
      "real_remainder_owner": "DATASTORE-DURABLE-HOSTS",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-227",
        "outcome": "/history_and_precision/gaps",
        "route": "repository",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/history_and_precision/gaps",
          "canonical_value_sha256": "41fe8b66e7b7ab838c5953d1c0bfdc5583bd1e115a7f185c6974735a7ee940b2"
        },
        "leaf_pointers": [
          "/history_and_precision/gaps"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-COVERAGE",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-228",
        "outcome": "/history_and_precision/retention",
        "route": "repository",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/history_and_precision/retention",
          "canonical_value_sha256": "9e4d4c01ddb874acfab75f3592625eeda9c01b46ae63c33af722942dde525c32"
        },
        "leaf_pointers": [
          "/history_and_precision/retention"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": null
      },
      "synthetic_boundary_child": "DATASTORE-RETENTION",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    },
    {
      "baseline_row": {
        "id": "DOMAIN-251",
        "outcome": "/exclusions/tokens",
        "route": "repository",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/exclusions/tokens",
          "canonical_value_sha256": "746087c9ea5f95643c073b4a5bbfdc32b6a8d42769341f5e10f750c4d8a3977e"
        },
        "leaf_pointers": [
          "/exclusions/tokens"
        ],
        "current_facts": "Source-derived only: resolve the pinned evidence value; all bounds, losses and unrun states remain normative evidence.",
        "successor_detail": "Missing identifiers/domains excluded; missing human label alone does not exclude an identified app. Opaque tokens do not acquire stable bundle identity or transferable grants; optional label resolution needs separate network purpose."
      },
      "synthetic_boundary_child": "DATASTORE-SOURCE-CATALOG",
      "real_remainder_owner": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "trigger": "Before actual source/backend/full-history admission; original baseline loss/retention/provenance/unsupported facts retained",
      "complete_source_obligation_closed": false
    }
  ],
  "full_transfer_obligations_13": {
    "original13_unchanged": [
      {
        "id": "TRANSFER-01",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Original points/visits/places/recording-session UUIDs; derived outings separate; original correction metadata/Undo and photo associations without asset bytes. Preserve unknown boundary certainty/device provenance.",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/native_history",
          "canonical_value_sha256": "369127c2afbb1a2ddb90278a9342f8c7ffafdfc1bc6fa731d4b3c2a1d8b8cda5"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-02",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Installation/sequence IDs, wirev1 pending/ack and all available session/visit/point queues; explicit retry/revoke/duplicate ordering. Do not reconstruct phone-discarded links.",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/watch_and_system_surfaces",
          "canonical_value_sha256": "8c9f283c1d75e3aca94cf657fc3a5f7f0f247b175f9290430f0d4d97851c664f"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-03",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Eight historical format profiles remain bounded compatibility routes; CSV includes outings and Markdown reader accepts md+markdown. Fresh-ID legacy import cannot satisfy full graph roundtrip.",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/formatted_exports",
          "canonical_value_sha256": "fa8afdc2eff9b29f8672bc186320c160eaa66caaea5e507c8c3b9255202a9613"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-04",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Supported inert units/capture/filter/templates/schedule preferences previewed; native bookmark/source/photo/destination grants rebound; old delivery never armed.",
        "evidence": {
          "input_id": "location",
          "json_pointer": "/export_and_schedule_policy",
          "canonical_value_sha256": "9ea686f643a17dc9c8ccf411d89f191069a254fcd0cce599ee011867b55a3c2c"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-05",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "All retained native usage rows beyond365day mirror including imported source facts; source epochs and civil text distinct. Under2sec discarded, missing crash tail, clock and precollector periods unrecoverable.",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/history",
          "canonical_value_sha256": "b8c8b80b382e7527363257fe3ad94e7ae8838560994092aed4089554e5c85a6d"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-06",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "All available app-category assignments with lineage; do not invent project entities or assignment revision history.",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/feature_map/1",
          "canonical_value_sha256": "6f22ae149c0d5d063b5cfe56bc77db877d5dfab435785ed65ad04ec201c07896"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-07",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Read-only full-state archive before destructive migration; excluded browser/input tables omitted before import, without executing donor dropping migrations on source.",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/storage_migrations",
          "canonical_value_sha256": "58a0546b5a63d805b0212da42db9e98e0cca42f41067b2dd8b244ddc80a062ef"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-08",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Preserve permitted imported snapshot provenance, per-source identity, day replacement/empty-day/deletion/overlap semantics and pending state; daily mirrors and200-record first page are not complete native transfer.",
        "evidence": {
          "input_id": "mac",
          "json_pointer": "/sync",
          "canonical_value_sha256": "e34dd7c793ce0ecb0fb6e74c9cf8e2c31c0e81b0661fd091eb687656c8132031"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-09",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "All retained settings/history/provider buckets and legacy daily keys beyond export-builder view;370key cap and rounded24h rows are source losses. Original raw precision when available; future full historical permitted buckets retained.",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/history_and_precision",
          "canonical_value_sha256": "bf03ac325fd5fc8c738deb13563a5ca95163de708440224a0fee31ffcfb4518e"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-10",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "usage-export.v3 selected file is not complete archive: raw today-only reads, legacy totals omission, coverage and provider/config fields require scoped validation/redaction.",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/exports",
          "canonical_value_sha256": "d099fb7eeaa30a4f8419d3197b60f1edd67ae1547e3cd74a9e5aad86e742ccc8"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-11",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Preserve original known source identity without inventing stable device IDs from names/model or default installation ID; source bucket times not exact per-app session boundaries.",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/ios",
          "canonical_value_sha256": "28a7f5e126404e3df96ab1019f5a9469f7a5874d18219510100b9268cb6b4a3a"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-12",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Prototype finite UsageEvents, pairing/open/prewindow/null/locked gaps and rounded snapshots remain distinct from observed exact sessions; future checkpoint/grant/OEM proof required.",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/android_prototype",
          "canonical_value_sha256": "0697298983a10b61db3c9434b6ccd764849f942362ebde83c1720bbf91c8dd0e"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      },
      {
        "id": "TRANSFER-13",
        "disposition": "successor",
        "target": "P03/C17 complete retained-state staging/import/Undo",
        "requirement": "Archive allowed data only; do not migrate provider credentials, plaintextlegacyWorker settings, encrypted relay pairing keys, commerce grants or armed endpoints. Re-enroll purposes/destinations explicitly.",
        "evidence": {
          "input_id": "mobile",
          "json_pointer": "/egress_and_services",
          "canonical_value_sha256": "99d2549a55c1abf133ef465e58b9dc7a3e748315d3612a8493178f725889f619"
        },
        "proof": "Required synthetic full archive/replay/crash/conflict/rollback and installed-user qualification; not executed here."
      }
    ],
    "owner": "DATASTORE-COMPLETE-ARCHIVE-IMPORT",
    "qualified": false
  },
  "remaining_family_work": [
    {
      "id": "DATASTORE-DURABLE-HOSTS",
      "owner": "personal_data native/storage/security coordinator",
      "trigger": "Before any actual local collector partition/inbox/checkpoint/correction/deletion/retention backend adoption",
      "requirements": [
        "Backend/encryption/protected-data/schema upgrade/rolling compatible reader choice",
        "Actual persisted transaction/replay/process kill/power loss/open-session recovery/ACK and retention at scale",
        "Independent suppression/deletion journal outside snapshots/backups; failclosed missing current journal; restore-after-later-delete/revoke negative matrix",
        "Measured physical live/version/index/key/backup erasure deadlines and durable recovery; no instant crypto-erasure claim"
      ],
      "proof_class": [
        "host_integration",
        "physical_device",
        "signed_distribution"
      ]
    },
    {
      "id": "DATASTORE-SOURCE-ADMISSION-HISTORY",
      "owner": "P01/L01/S01/S02 acquisition-contract coordinator",
      "trigger": "Before ingesting actual location/usage/health originals or claiming full available history",
      "requirements": [
        "Full original source field/evidence grammar/equality/collision-safe stable identity and imported artifact enumeration",
        "Native health remains source authority; no compulsory whole-corpus replication",
        "All observed short sessions plus all available donor history; unknown precollector/discarded/crash tails/gaps stay unknown",
        "Per-source clocks/precision/source arithmetic/source lookback/bucket reconciliation/unknown identity/source-purpose/channel/OS/protected eligibility",
        "Browser/input/title exclusions before observation, persistence, evidence staging, archive or transfer"
      ],
      "proof_class": [
        "planning",
        "host_integration",
        "physical_device",
        "signed_distribution"
      ]
    },
    {
      "id": "DATASTORE-CORRECTION-UNDO-AND-DERIVATION",
      "owner": "P01/L02/S03 domain algorithm coordinator",
      "trigger": "Before local reversal/visit/place/session/inference UI or persistent derivation admission",
      "requirements": [
        "Append reversal preserving original; explicit restore under current grants cannot override independent external fence",
        "Exact source-aware outlier/visit/outing/association/reducers/session clipping/unknown timing semantics, no invented timestamps",
        "Saved places/categories/device states/title observations and cross-domain association remain distinct"
      ],
      "proof_class": [
        "portable_synthetic",
        "host_integration"
      ]
    },
    {
      "id": "PERSONAL-QUERY-PROJECTION",
      "owner": "C16/O08/P02 common-operation coordinator",
      "trigger": "Before full source catalog/query/timeline/coverage UI/CLI/MCP/catalog/protocol promotion",
      "requirements": [
        "Whole source-aware snapshot/cursor/caller binding; mixed health-only peers; strict/partial selection and bucket partial overlap",
        "Daily/hourly replacement, source/device overlap never blind totals; semantic health/GPS/CLVisit/observed/inferred distinctions",
        "One common operation/accounting/cancel/commit/recovery; no permanent donor Swift CLI/location export engine",
        "Full retained history bounded paging; large exports/schedules/renderer/source-profile/Obsidian consumer gates"
      ],
      "proof_class": [
        "portable_synthetic",
        "host_integration",
        "external_client"
      ]
    },
    {
      "id": "DATASTORE-COMPLETE-ARCHIVE-IMPORT",
      "owner": "P03/C17/L05/S04 migration coordinator",
      "trigger": "Before donor adopted code/data or installed-user transition",
      "requirements": [
        "All13 baseline transfer obligations, originals/IDs/precision/settings/annotations/categories/queues evidence",
        "Archive/digest/version/partition/source schema validation, staging/conflict/commit/Undo/retry/crash/rollback matrix",
        "Q-DONOR-SOURCE/Q-DONOR-SUPPORT/license/AGPL and signed purpose/support decisions; no dirty source adoption or donor service/secret inheritance",
        "Original donor data/readers retained; no fake archive completeness or reconstructed missing historical facts"
      ],
      "proof_class": [
        "planning",
        "host_integration",
        "physical_device",
        "signed_distribution"
      ]
    },
    {
      "id": "DATASTORE-PACKAGE-CONSUMER-COHORT",
      "owner": "portable/core consumer-admission coordinator",
      "trigger": "Before exports/package/API/CLI/MCP/native bundle consumes these future new source modules",
      "requirements": [
        "Freeze complete source/generated set and exact export/cohort/current immutable prior receipts after each accepted producer delta",
        "Current43/26 remains historical accepted authority; numeric46/28/Values prospective inputs do not silently selfrefresh consumer guards",
        "One physical Effect/React where relevant/no Rust tool graph/source SDK isolated required host and public fixture gates"
      ],
      "proof_class": [
        "portable_synthetic",
        "host_integration"
      ]
    },
    {
      "id": "DATASTORE-CLOUD-AND-RETIREMENT",
      "owner": "H00-H09 operational and rollout/retirement coordinator",
      "trigger": "Before hosted transfer/backup/delete/restore or source engine production cutover/deletion",
      "requirements": [
        "Actual source-purpose/server-readable/device/owner/agent/destination/retention/key/current suppression semantics",
        "Two-tenant deployed recovery/deletion/revoke-after-backup qualification; external recipient copy limit",
        "Independent rollout/rollback/support matrix and full family closure; no Rust/reference/retained state deletion from syntheticchildren"
      ],
      "proof_class": [
        "deployed_operational",
        "signed_distribution",
        "external_client"
      ]
    }
  ],
  "native_health_accountfree_policy": "NativeHealth authority preserved; local/catalog is account-free. No cloud upload/source grant/client pairing activation/account creation.",
  "transaction_acceptance": "Catalog has no mutation/allocation/commit port; all resource ACK/commit/acquisition counters zero. Its closed signal is originalScope lifetime notification, not resourcecleanup or storage transaction ACK. DATASTORE-BATCH-CHECKPOINT/durablehost owners retain generic packet transaction obligations."
} as const;
