// Independent expectation authority. Written before operations/personal-slice.ts or its tests.
import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { OwnedPersonalRecord, TrustedPersonalCodecContext } from "../src/contracts/personal-slice.js";

export type SliceSlot = "health" | "location" | "usage";
export type SliceFailureCode = "unsupported_request" | "scope_not_authorized" | "scope_binding_mismatch" | "source_required" | "coverage_incomplete" | "aggregate_partial_overlap" | "candidate_limit_exceeded" | "record_identity_conflict" | "invalid_record" | "cleanup_unacknowledged" | "source_failed";
export interface SliceFailure { readonly _tag: "PersonalSliceFailure"; readonly code: SliceFailureCode }
export interface SliceInstant { readonly epoch_seconds: string; readonly nanoseconds: number }
export interface SliceSelector {
  readonly slot: SliceSlot; readonly domain: "health" | "location" | "device_usage";
  readonly source_id: string; readonly source_revision: string;
  readonly device_id: string; readonly installation_id: string;
  readonly payload_kind: "health_fact" | "location_point" | "usage_aggregate";
  readonly statistic: "observation" | "original_point" | "source_total_duration";
  readonly profile: string; readonly detail: "health_value" | "location_exact_point" | "usage_app_duration";
}
export interface SliceRequest {
  readonly schema: "candidate.personal_slice_request"; readonly revision: 1;
  readonly dataset_id: string; readonly dataset_revision: string; readonly snapshot_id: string;
  readonly purpose: string; readonly destination: string; readonly caller_binding: string;
  readonly grant_revision: string; readonly suppression_revision: string;
  readonly slots: readonly SliceSelector[];
  readonly time_scope: { readonly mode: "instant"; readonly epoch: "unix"; readonly start: SliceInstant; readonly end: SliceInstant; readonly boundaries: "half_open" };
  readonly strictness: "strict" | "allow_partial"; readonly require_complete: boolean;
}
export interface SliceCoverage {
  readonly slot: SliceSlot; readonly domain: SliceSelector["domain"];
  readonly status: "complete" | "partial" | "unavailable" | "unknown" | "denied" | "partial_overlap";
  readonly reason_codes: readonly string[];
}
export interface SliceAuthority {
  /** Host catalog/current external suppression and distinct source/detail/destination grants.
   * Caller fields are requested bindings, never proof. Receives inert deeply frozen metadata only.
   * Slot null means job/destination authority. No title/measurement payload enters descriptors. */
  readonly check: (request: SliceRequest, slot: SliceSelector | null, phase: "before_source" | "before_page" | "before_record" | "before_encode" | "before_commit") => {
    readonly permitted: boolean; readonly binding_matches: boolean;
    readonly availability: "available" | "unavailable" | "unknown";
    readonly coverage: "complete" | "partial" | "unknown";
  };
  readonly codec_context: TrustedPersonalCodecContext;
}
export interface SlicePage {
  readonly ordinal: number; readonly terminal: boolean;
  readonly dataset_revision: string; readonly snapshot_id: string;
  readonly source_binding: SliceSelector;
  /** Primitive raw JSON only after source-purpose/detail/current authorization.
   * Fake source accounts actual UTF-8 bytes; no trusted encodedBytes assertion. */
  readonly records_json: readonly string[];
}
export interface SliceSourceLease {
  readonly readPage: (ordinal: number) => Effect.Effect<SlicePage, SliceFailure>;
}
export interface SliceSources {
  /** Coarse scoped capability. Must register cleanup atomically with completed allocation.
   * Interruptible preparation may precede owned allocation; cancellation cannot strand it.
   * Scope closure waits real fake release acknowledgment, faults use only closed SliceFailure. */
  readonly open: (request: SliceRequest, selector: SliceSelector) => Effect.Effect<SliceSourceLease, SliceFailure, Scope.Scope>;
}
export interface SliceArtifactFile { readonly name: "manifest.json" | "records.ndjson"; readonly utf8: string }
export interface OwnedSliceArtifact {
  readonly files: readonly SliceArtifactFile[];
  readonly records: readonly OwnedPersonalRecord[];
  readonly __ownedSliceArtifact: unique symbol;
}
export type SliceCommitDecision = "committed" | "definitely_not_committed" | "ambiguous";
export interface SliceDeliveryLease {
  /** One job and one commit attempt. Owns indivisible fake commitment and current guard at its
   * linearization point. Cancellation/typed transport failure after possible commit resolves
   * to a terminal decision (ambiguous when acknowledgment cannot prove committed/not).
   * Operation masks the bounded owned handoff until this acknowledgment; no automatic retry.
   * Terminal decision lives in the trusted fake job ledger even if caller Fiber is interrupted.
   * This seam is no proof of real atomic grants, durable store/ledger, or authenticated delivery. */
  readonly commit: (artifact: OwnedSliceArtifact, currentGuard: () => boolean) => Effect.Effect<SliceCommitDecision>;
}
export interface SliceDelivery {
  readonly open: (request: SliceRequest) => Effect.Effect<SliceDeliveryLease, SliceFailure, Scope.Scope>;
}
export interface SliceDelivered {
  readonly _tag: "PersonalSliceCompleted"; readonly decision: SliceCommitDecision;
  readonly accounted_jobs: 1; readonly cleanup_acknowledged: true;
}
export interface PersonalSliceDependencies {
  readonly authority: SliceAuthority; readonly sources: SliceSources; readonly delivery: SliceDelivery;
}
export type PersonalSliceFactoryProposal = (dependencies: PersonalSliceDependencies) => PersonalSliceOperationProposal;
export interface PersonalSliceOperationProposal {
  /** Proposed private factory createPersonalSliceOperation({authority,sources,delivery}) returns
   * this single run operation. Unknown admitted only as primitive JSON string; same internal
   * codec factory owns decoded records and WeakMap artifact identity; foreign objects refused
   * before properties. Context services are trusted adapters, not caller JSON inputs. */
  readonly run: (input: unknown) => Effect.Effect<SliceDelivered, SliceFailure>;
}

export const combinedSliceRules = [
  "Expected artifact UTF8 fields are observed private fake commit arguments, not returned/published recipient bytes. Completed decision describes accounting outcome even when definitely_not_committed/ambiguous. No successful publication is asserted for those decisions.",
  "Private synthetic candidate only. No index/exports/locks/cohort/native/public profiles. Proposed source/profile labels distinguish three source slots even when health and location share original source-a. These labels do not admit a registry or native source. All four original records, input JSON and canonical bytes below are exact accepted originals; only indices 0,1,2 belong in this combined slice. Session index3 remains a preserved obligation, never inferred from aggregate index2.",
  "Run accepts primitive JSON strings only. Request closed maps, duplicate/escaped-equivalent duplicate rejection, scalar Unicode/NUL/unpaired-surrogate rejection, depth32/nodes4096/UTF8<=65536 before property traversal or any callback. Revision/nanos use exact canonical integer lexemes before Number; IDs scalar nonempty <=256 UTF8 bytes; grant/suppression revision canonical u64 strings. Exactly the three legal slot/domain/kind/statistic/detail pairs above; max3 duplicate-free slots. Set selector order canonical health,location,usage; empty means empty. Time i64 Unix seconds+nanos0..999999999 with start<end. Civil/session/clipping/context/title/field-subset requests unsupported for this private operation, with their 81 obligations retained for later operations.",
  "Every required request binding supplied: dataset/revision/snapshot, original source revision, device/install, purpose, caller/grant/suppression, statistic/profile, time and distinct destination/detail. Trusted catalog checks all scopes before source open, rejects missing/stale/wrong-lineage external suppression fail closed. Strict denied/unavailable/unknown fails before any source or delivery; allow_partial omits that slot and reports fixed requested slot/domain/status without denied source/device/record/detail identities. require_complete true rejects partial/unknown completeness independently of strictness. Exhausted page never upgrades source historical coverage.",
  "Authorize before source observation/read, every page/record, synchronous codec payload materialization/encode and delivery linearization. Host codec_context independently binds actual source/catalog/classification/current grants and suppression; caller metadata and browser flags never authority. Coarse source must not call title/browser/input APIs or return prohibited title material before authorization. This operation admits no title request. Browser application duration remains permitted; the accepted aggregate with missing label is retained. No observer/copy/quarantine/hash of excluded values. Regrant/old backup/renaming never overrules latest deletion/revocation fence.",
  "One internal createPersonalRecordCodec factory decodes and owns all records; canonical original strings remain byte exact. No arbitrary public caller record/Proxy access. Owned artifact weak registry rejects clones before properties. Full shape/profile/dataset/source/device/install/kind/statistic/snapshot bindings checked. Original source identity/equality proof is limited to complete closed accepted synthetic records: same record key and exact encoded vector replay once; different vector under same key conflict. No derived canonical byte hash establishes real native archive equality, imports, missing identity or full history.",
  "Exact point selection uses rational IEEE754 plus Apple offset978307200; no Number/Date/epsilon conversion. Health instant half-open and location bits retained. Aggregate included only entire bucket within query; partial strict fails, partial allowed omits/report fixed partial_overlap; no scaling/clipping/session fabrication/device totals/overlap sum. No implicit simultaneous cross-domain association.",
  "Bounded admission: request65536UTF8/depth32/nodes4096/max3slots; raw record65536UTF8; page actual sum raw-record UTF8 plus fixed metadata JSON bytes<=1048576 and<=8records; <=8pages total,<=32records total, one outstanding page,<=1048576 total delivered file UTF8 bytes (manifest+NDJSON), exactly2files even empty. Bounds inclusive. Guard original page record count before dedup, count total all read originals including replay. Bounds candidate synthetic, unmeasured not production budget. No all-history age cap silently inferred.",
  "Artifacts ordered manifest.json then records.ndjson. Manifest maps scalar-key sorted compact JSON with no extra whitespace; newline-free manifest. Canonical records scalar-key sorted accepted byte strings with exactly one trailing LF per row. Rows order by fixed slot health/location/usage, then scalar comparison of full canonical record strings within slot; exact replay dedup only after full key equality. Manifest selected_sources sorted authorized slots; coverage sorted all requested slots; fixed reason lists sorted. Original accepted tagged numbers/time/unknowns/absences untouched. No caller toJSON or native serializer parity claimed.",
  "Source scopes fully close/ack before delivery open; a source cleanup defect prevents commitment. Delivery one open/job, one commit, one release acknowledgment; no permanent independent domain jobs. Source/cleanup faults fixed SliceFailure and no provider/cause/request/record/value detail. Cancel before commit waits completed-allocation registration and every owned finalizer; completion cannot precede ack. Async preparation cancellation must really stop/wait its worker. No interruptible naked allocation under outer acquireRelease ownership gap.",
  "Commit decision committed/definitely_not_committed/ambiguous is distinct from caller interruption and cleanup status. Commit starts only after current guard. During possible commit interruption waits fake terminal acknowledgment and delivery release; terminal decision retained in trusted fake ledger, then interrupted Fiber emits no operation value. No cancel=rollback, no retry of ambiguous, no recall of recipient copies. Postcommit cleanup failure returns fixed cleanup_unacknowledged while preserving terminal ledger decision. Real cancellation cannot force a remote transaction rollback; fake seam not real durability/crypto/authority proof.",
  "Baseline trusted fake authority synthetic caller-a current grant1 external suppression1 independently supplied, purpose/detail/destination granted; aggregate actual authoritative browser class allowed duration with title_permitted false. Fake coverage partial reason synthetic_only_no_source_completeness_evidence for all3, snapshot-a, never fullhistory. Per-case scenario overrides are test harness behavior schedules, NOT public flags. Page bindings copied from exact trusted selectors table. Independent deterministic gates control cancellation; no wallclock/SDK/user/network/credentials.",
  "Literal boundary recipes use accepted input strings as source, independently specified counts and raw byte lengths; tests must construct exact inert strings/arrays from these recipes without candidate encoder. Source fault injected error includes synthetic secret marker, expected safe code only. Gate counts are contract expectations not measured until Stage2. Own immutable accepted 81 obligations imported exactly below, including native arithmetic vs synthetic exact duration, source evidence, restoration and clipping qualifications; broader profiles/combined archive/import/native/query/schedules/CLI/public/host/cohort remain separately scoped."
] as const;

export const combinedSliceSourcePins = [
  {
    "path": "AGENTS.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456"
  },
  {
    "path": "docs/architecture/javascript-unified-layer-research.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3"
  },
  {
    "path": "docs/architecture/javascript-unified-layer-design-reference.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd"
  },
  {
    "path": "packages/healthmd-core-ts/AGENTS.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67"
  },
  {
    "path": "packages/healthmd-core-ts/README.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606"
  },
  {
    "path": "docs/migration/effect-refactor/personal-data.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0"
  },
  {
    "path": "docs/migration/effect-refactor/templates.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e"
  },
  {
    "path": "docs/migration/effect-refactor/decisions/personal-contract-candidate.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "0c50c6d13e48026c9ed81f0325fea73050d52d7b1aa744eb905eae4884b0349d"
  },
  {
    "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c"
  },
  {
    "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df"
  },
  {
    "path": "docs/migration/effect-refactor/inventories/donors.json",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d"
  },
  {
    "path": "docs/migration/effect-refactor/receipts/BASE-DOMAINS.json",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "4ee85dc253932a6ac8c05becea89c3627d97c4e62ecedc8a0cadbcd87defdcd1"
  },
  {
    "path": "docs/migration/effect-refactor/receipts/PERSONAL-CODECS.json",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859"
  },
  {
    "path": "docs/migration/effect-refactor/receipts/SLICE-PARITY.json",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "c8f395b086606b685c3f539d105a74036a4f42608534a1eb80d11c2ecf67a4f4"
  },
  {
    "path": "docs/migration/effect-refactor/receipts/CLOUD-FAULT-MODEL.json",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "4a6b1ccbe61e33f3e2ae983a2d0172cd55144147bee9d6a533449792a38ca9fb"
  },
  {
    "path": "packages/healthmd-core-ts/src/contracts/personal-slice.ts",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5"
  },
  {
    "path": "packages/healthmd-core-ts/tests/personal-codecs-vectors.ts",
    "source_revision": "62a1547eb6c856c55ca5731e20de7f27cef27fe7",
    "raw_sha256": "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a"
  }
] as const;

export const combinedSliceSemanticEvidence = [
  {
    "id": "domain-lineage",
    "path": "docs/migration/effect-refactor/inventories/donors.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d",
    "json_pointer": "/common_contract_and_authority",
    "canonical_selected_value_sha256": "4222dc72cf198669bffe8b291b1abe1d2aa5f149ebb2e5af3f9bbecd944a059b",
    "meaning": "Separate source/purpose/detail/destination capability; one logical dataset."
  },
  {
    "id": "domain-transfer",
    "path": "docs/migration/effect-refactor/inventories/donors.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d",
    "json_pointer": "/complete_transfer_requirements",
    "canonical_selected_value_sha256": "3f8144234a6219c9bf98cb7d51860dd793dc4d685985c1f3d0644886f15b31c7",
    "meaning": "Complete retained-state transfer separate from summary/record slice."
  },
  {
    "id": "domain-grants",
    "path": "docs/migration/effect-refactor/inventories/donors.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d",
    "json_pointer": "/grant_handoff_sequence",
    "canonical_selected_value_sha256": "bca432135f9a6c0bbd821643a93b1106cfa473974f57a04dfa229f7d4bdc57c1",
    "meaning": "No automatic grant, schedule or credential handoff."
  },
  {
    "id": "domain-coverage",
    "path": "docs/migration/effect-refactor/inventories/donors.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d",
    "json_pointer": "/coverage",
    "canonical_selected_value_sha256": "25704cafb28483d05069b44bbda041177e5ed1d5e2ad27267005e673c8b04ca1",
    "meaning": "Accepted281route rows,1141semantic leaves; not repeated audit."
  },
  {
    "id": "location-point",
    "path": "docs/migration/effect-refactor/inventories/donor-location.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "51dd89a982ba18c072eae935220a626e456f3e4baab7fa17c6d7321ca940409f",
    "json_pointer": "/native_history/models/0",
    "canonical_selected_value_sha256": "5a3c5a8d15e24cd0189251ad7286520d5ec08f645a0ff972afcaf19fb48464f0",
    "meaning": "UUID/Date/Double and accuracy; absent original lineage cannot be invented."
  },
  {
    "id": "mac-clock",
    "path": "docs/migration/effect-refactor/inventories/donor-usage-mac.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "5847579b3a987ba49d41f572aeb105f98cbef730b4e2107fb6b29176443b089c",
    "json_pointer": "/history/collector",
    "canonical_selected_value_sha256": "47315115a2cb2690a09e1d9a1db731648161bb69d68378f6985072659f3f30b6",
    "meaning": "Double wall-clock/source_timestamp versus second text; sub2s/crash gaps not recoverable."
  },
  {
    "id": "mobile-history",
    "path": "docs/migration/effect-refactor/inventories/donor-usage-mobile.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "bbfef9fe1576085ed006cb05b74ec7336adee09ffa4f4ed1a8cca309403a105d",
    "json_pointer": "/history_and_precision",
    "canonical_selected_value_sha256": "bf03ac325fd5fc8c738deb13563a5ca95163de708440224a0fee31ffcfb4518e",
    "meaning": "370snapshots/rounding/source flags do not establish complete precise source history."
  },
  {
    "id": "health-precision",
    "path": "docs/migration/effect-refactor/inventories/core.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
    "json_pointer": "/exact_policies",
    "canonical_selected_value_sha256": "065e4579b93a31175865fbf16ff8339dad500861fa11559af51da332f7107a73",
    "meaning": "Native health exact units/owner dates/profile identity preserved."
  },
  {
    "id": "health-fixtures",
    "path": "docs/migration/effect-refactor/inventories/core.json",
    "source_revision": "56b0f6f892a8726f45ef5478d08262c8c2b04d03",
    "raw_file_sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
    "json_pointer": "/frozen_fixtures",
    "canonical_selected_value_sha256": "2769d77c553c95f17faa6619db50bcbf65fb441c913562702d1348593793e202",
    "meaning": "Frozen health/export differential bytes remain authority."
  }
] as const;

export const combinedSliceAcceptedManifest = {
  "schema": "candidate.personal_manifest",
  "revision": 1,
  "public_admission": "unselected",
  "dataset_id": "synthetic-dataset-a",
  "dataset_revision": "synthetic-revision-a",
  "selection": {
    "dataset_id": "synthetic-dataset-a",
    "dataset_revision": "synthetic-revision-a",
    "domains": [
      "health",
      "location",
      "device_usage"
    ],
    "source_ids": [
      "synthetic-source-a",
      "synthetic-source-b"
    ],
    "device_installation_pairs": [
      {
        "device_id": "synthetic-device-a",
        "installation_id": "synthetic-install-a"
      },
      {
        "device_id": "synthetic-device-b",
        "installation_id": "synthetic-install-b"
      }
    ],
    "payload_kinds": [
      "health_fact",
      "location_point",
      "usage_aggregate"
    ],
    "time_scope": {
      "start": {
        "representation": "seconds_nanos",
        "epoch": "unix",
        "epoch_seconds": "0",
        "nanoseconds": 0,
        "source_resolution": "nanosecond_representation_not_accuracy",
        "uncertainty": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "end": {
        "representation": "seconds_nanos",
        "epoch": "unix",
        "epoch_seconds": "1000000000",
        "nanoseconds": 0,
        "source_resolution": "nanosecond_representation_not_accuracy",
        "uncertainty": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "boundaries": "half_open"
    },
    "details": [
      "health_value",
      "location_exact_point",
      "usage_app_duration"
    ],
    "destination": "synthetic-local-file",
    "strictness": "strict",
    "snapshot_id": "synthetic-snapshot-a"
  },
  "record_ids": [
    "synthetic-health-1",
    "synthetic-location-1",
    "synthetic-usage-aggregate-1"
  ],
  "coverage": [
    {
      "domain": "health",
      "source_id": "synthetic-source-a",
      "device_scope": {
        "state": "known",
        "value": "synthetic-device-a"
      },
      "installation_scope": {
        "state": "known",
        "value": "synthetic-install-a"
      },
      "payload_kind": "health_fact",
      "interval": {
        "start": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "end": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "1000000000",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "boundaries": "half_open"
      },
      "status": "partial",
      "reason_codes": [
        "synthetic_only_no_source_completeness_evidence"
      ],
      "known_intervals": [],
      "queried_scope": "fixture_scope_only_no_source_completion_proof",
      "gaps": [],
      "unaccounted_intervals": "not_established_no_gap_boundaries_invented",
      "detail_status": "unknown",
      "snapshot_id": "synthetic-snapshot-a",
      "source_updated_at": {
        "state": "unknown",
        "reason": "not_reported"
      }
    },
    {
      "domain": "location",
      "source_id": "synthetic-source-a",
      "device_scope": {
        "state": "known",
        "value": "synthetic-device-a"
      },
      "installation_scope": {
        "state": "known",
        "value": "synthetic-install-a"
      },
      "payload_kind": "location_point",
      "interval": {
        "start": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "end": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "1000000000",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "boundaries": "half_open"
      },
      "status": "partial",
      "reason_codes": [
        "synthetic_only_no_source_completeness_evidence"
      ],
      "known_intervals": [],
      "queried_scope": "fixture_scope_only_no_source_completion_proof",
      "gaps": [],
      "unaccounted_intervals": "not_established_no_gap_boundaries_invented",
      "detail_status": "unknown",
      "snapshot_id": "synthetic-snapshot-a",
      "source_updated_at": {
        "state": "unknown",
        "reason": "not_reported"
      }
    },
    {
      "domain": "device_usage",
      "source_id": "synthetic-source-b",
      "device_scope": {
        "state": "known",
        "value": "synthetic-device-b"
      },
      "installation_scope": {
        "state": "known",
        "value": "synthetic-install-b"
      },
      "payload_kind": "usage_aggregate",
      "interval": {
        "start": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "end": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "1000000000",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "boundaries": "half_open"
      },
      "status": "partial",
      "reason_codes": [
        "synthetic_only_no_source_completeness_evidence"
      ],
      "known_intervals": [],
      "queried_scope": "fixture_scope_only_no_source_completion_proof",
      "gaps": [],
      "unaccounted_intervals": "not_established_no_gap_boundaries_invented",
      "detail_status": "unknown",
      "snapshot_id": "synthetic-snapshot-a",
      "source_updated_at": {
        "state": "unknown",
        "reason": "not_reported"
      }
    }
  ],
  "source_snapshot_ids": [
    "synthetic-snapshot-a"
  ],
  "lossless_record_partition": {
    "status": "candidate_fixture_only",
    "record_count": 3,
    "precision": "original_tagged_values",
    "omitted_details": [
      "desktop_window_title",
      "browser_history",
      "input_events"
    ]
  },
  "completeness": "partial",
  "summary_vs_archive": "selected_records_not_complete_native_archive",
  "projection_policy_revision": "synthetic-projection-a",
  "authority": "synthetic_planning_fixture_not_grant"
} as const;

export const combinedSliceAcceptedObligations = [
  {
    "case_id": "combined-three-domains",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "health-scoped-same-dataset",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "point-binary64-lossless",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "health-large-integer-lossless",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "health-negativezero-preserve",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "mixed-epoch-selection-precision",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "timestamp-nanos-order",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "native-calendar-not-inferred",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "aggregate-not-session",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "short-session-retained",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "historical-donor-short-tail-gap",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "ios-exact-sessions-unestablished",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "android-prototype-not-supported",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "unknown-empty-is-not-zero",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "unavailable-empty-is-not-zero",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "observed-zero-only-evidence",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "no-fabricated-completeness",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "hourly-daily-overlap",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "cross-device-overlap",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "same-key-same-bytes-replay",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "same-key-different-bytes-conflict",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "new-install-not-same-device-history",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "missing-donor-lineage",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "correction-preserves-original",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "visit-sentinel-not-observed",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "outing-not-recording",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "browser-app-duration-allowed",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "browser-title-before-observation",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "unknown-app-class-title-fails-closed",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "excluded-import-before-staging",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "capture-not-export-grant",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "report-view-not-record-export",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "future-uploads-not-auto-agent-grant",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "title-query-not-agent-share",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "strict-scope-denied-no-leak",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "partial-scope-explicit",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "grant-revoked-during-page",
    "authority": "accepted_draft",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "selector-cursor-crosswire",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "geographic-health-distance-distinct",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "frozen-health-profiles",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "summary-not-complete-transfer",
    "authority": "accepted_draft",
    "classification": "separate_native_or_consumer",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "complete-history-no-dashboard-cap",
    "authority": "accepted_draft",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "nonfinite-or-overprecision",
    "authority": "accepted_draft",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "bounded-page-admission",
    "authority": "accepted_draft",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-coordinate-endpoints",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-coordinate-outside",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-coordinate-outside",
      "input": {
        "latitude": "4056c00000000000"
      },
      "expected": {
        "canonical_status": "outside_canonical",
        "reason": "coordinate_out_of_range",
        "retain_eligible_original_evidence": true
      }
    }
  },
  {
    "case_id": "resolution-nonfinite-coordinate",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-nonfinite-coordinate",
      "input": {
        "latitude": "7ff8000000000000"
      },
      "expected": {
        "canonical_status": "outside_canonical",
        "canonical_value": null,
        "retain_eligible_original_evidence": true
      }
    }
  },
  {
    "case_id": "resolution-negative-speed-sentinel",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-negative-accuracy-sentinel",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-negative-accuracy-sentinel",
      "input": {
        "accuracy_bits": "bff0000000000000"
      },
      "expected": {
        "state": "unavailable",
        "reason": "native_invalid_accuracy",
        "coerce_zero": false
      }
    }
  },
  {
    "case_id": "resolution-negativezero-speed",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-negativezero-speed",
      "input": {
        "speed_bits": "8000000000000000"
      },
      "expected": {
        "canonical_status": "valid",
        "bits": "8000000000000000"
      }
    }
  },
  {
    "case_id": "resolution-reversed-session",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-duration-disagreement",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-zero-session",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-original-record-equality",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-lossy-equality-conflict",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-repartition-key",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-missing-stable-import-order",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-missing-stable-import-order",
      "input": {
        "native_id": "unknown",
        "stable_artifact_enumeration": false
      },
      "expected": {
        "automatic_merge": false,
        "import_identity": "unknown"
      }
    }
  },
  {
    "case_id": "resolution-apple-unix-equality",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-dyadic-subnanosecond",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-half-open-end",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-half-open-end",
      "input": {
        "point_seconds": "1",
        "start_seconds": "0",
        "end_seconds": "1"
      },
      "expected": {
        "membership": false
      }
    }
  },
  {
    "case_id": "resolution-negative-floor-nanos",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-negative-floor-nanos",
      "input": {
        "epoch_seconds": "-1",
        "nanoseconds": 999999999
      },
      "expected": {
        "exact_seconds": "-1/1000000000",
        "valid": true
      }
    }
  },
  {
    "case_id": "resolution-aggregate-partial-strict",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-aggregate-partial-allowed",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-aggregate-whole-context",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-aggregate-context-denied",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-aggregate-context-denied",
      "input": {
        "projection": "whole_bucket_context",
        "whole_bucket_grant": false
      },
      "expected": {
        "materialize": false,
        "safe_code": "scope_not_authorized"
      }
    }
  },
  {
    "case_id": "resolution-observed-session-clip",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-tombstone-replay",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-correction-under-tombstone",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
      "case_id": "resolution-correction-under-tombstone",
      "input": {
        "tombstone_current": true,
        "correction_new": true,
        "explicit_restore": false
      },
      "expected": {
        "current_projection_visible": false
      }
    }
  },
  {
    "case_id": "resolution-delete-backup-regrant",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-frontier-changes-before-commit",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-recipient-copy-limit",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
      "case_id": "resolution-recipient-copy-limit",
      "input": {
        "recipient_already_downloaded": true,
        "grant_now_revoked": true
      },
      "expected": {
        "new_reads": false,
        "recall_claim": false
      }
    }
  },
  {
    "case_id": "resolution-schema-boolean-version",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
      "case_id": "resolution-schema-boolean-version",
      "input": {
        "payload_revision": true
      },
      "expected": {
        "accept": false,
        "safe_code": "unsupported_shape"
      }
    }
  },
  {
    "case_id": "resolution-unknown-source-field",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-unknown-source-field",
      "input": {
        "new_source_field": true,
        "same_canonical_projection": true
      },
      "expected": {
        "silently_discard": false,
        "admit_unreviewed_schema": false
      }
    }
  },
  {
    "case_id": "resolution-archive-excluded-title",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
      "case_id": "resolution-archive-excluded-title",
      "input": {
        "browser_title_present": true,
        "archive_grant": true
      },
      "expected": {
        "observe_or_stage_title": false,
        "complete_eligible_archive_includes_title": false
      }
    }
  },
  {
    "case_id": "resolution-reasonless-sensor-absent",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-absent-sensor-wrong-value",
    "authority": "accepted_resolution",
    "classification": "codec",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-native-source-rounded-subtraction",
    "authority": "accepted_resolution",
    "classification": "codec_subcase_and_later_gate",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-delete-restore-denied",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-authoritative-frontier-restore-denied",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-local-tombstone-reversible-only",
    "authority": "accepted_resolution",
    "classification": "separate_repository",
    "raw_contract": {
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
    }
  },
  {
    "case_id": "resolution-unrepresentable-clipped-duration",
    "authority": "accepted_resolution",
    "classification": "separate_query_or_projection",
    "raw_contract": {
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
    }
  }
] as const;

export const combinedSliceOriginalRecords = [
  {
    "case_id": "literal-record-0",
    "input_json": "{\"domain\":\"health\",\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"semantic_id\":\"synthetic.health.exact_count\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"statistic\":\"observation\",\"value\":{\"representation\":\"unsigned_integer\",\"decimal\":\"9007199254740993\",\"unit\":\"count\"},\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"extensions\":[]}}",
    "expected_record": {
      "domain": "health",
      "payload_kind": "health_fact",
      "payload_revision": 1,
      "record_id": "synthetic-health-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-a"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-a"
        },
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-health-original"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 1,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "semantic_id": "synthetic.health.exact_count",
        "native_semantic_id": {
          "state": "known",
          "value": "synthetic.health.exact_count"
        },
        "statistic": "observation",
        "value": {
          "representation": "unsigned_integer",
          "decimal": "9007199254740993",
          "unit": "count"
        },
        "native_profile": "synthetic_only_not_metric_registry_admission",
        "extensions": []
      }
    },
    "expected_encoded": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  },
  {
    "case_id": "literal-record-1",
    "input_json": "{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}",
    "expected_record": {
      "domain": "location",
      "payload_kind": "location_point",
      "payload_revision": 1,
      "record_id": "synthetic-location-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-a"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-a"
        },
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-location-uuid"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "binary64_epoch_seconds",
          "epoch": "apple_reference_2001",
          "bits": "3ff0000000000001",
          "source_resolution": "binary64_storage",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "latitude": {
          "representation": "binary64",
          "bits": "3ff0000000000000",
          "unit": "degree"
        },
        "longitude": {
          "representation": "binary64",
          "bits": "c000000000000000",
          "unit": "degree"
        },
        "horizontal_accuracy": {
          "representation": "binary64",
          "bits": "4000000000000000",
          "unit": "meter"
        },
        "altitude": {
          "state": "absent"
        },
        "speed": {
          "state": "absent"
        },
        "quality": {
          "source_is_outlier": false,
          "certainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "recording_session": {
          "state": "unknown",
          "reason": "not_reported"
        }
      }
    },
    "expected_encoded": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  },
  {
    "case_id": "literal-record-2",
    "input_json": "{\"domain\":\"device_usage\",\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"app\":{\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\",\"app_class\":\"browser\",\"display_label\":{\"state\":\"unknown\",\"reason\":\"withheld\"}},\"bucket\":{\"start\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"end\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"boundaries\":\"half_open\",\"calendar\":{\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"},\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\"}},\"statistic\":\"source_total_duration\",\"duration\":{\"representation\":\"binary64\",\"bits\":\"4082c00000000000\",\"unit\":\"second\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"observed_session_count\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"derived\":false}}",
    "expected_record": {
      "domain": "device_usage",
      "payload_kind": "usage_aggregate",
      "payload_revision": 1,
      "record_id": "synthetic-usage-aggregate-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-b"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-b"
        },
        "source_id": "synthetic-source-b",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-bucket-id"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 0,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "app": {
          "identity": {
            "state": "known",
            "value": "synthetic-browser-app"
          },
          "identity_kind": "synthetic_application_id",
          "app_class": "browser",
          "display_label": {
            "state": "unknown",
            "reason": "withheld"
          }
        },
        "bucket": {
          "start": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "0",
            "nanoseconds": 0,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "end": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "3600",
            "nanoseconds": 0,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "boundaries": "half_open",
          "calendar": {
            "time_zone": {
              "state": "known",
              "value": "Etc/UTC"
            },
            "owner_date": {
              "state": "known",
              "value": "1970-01-01"
            },
            "owner_rule": "synthetic_source_bucket"
          }
        },
        "statistic": "source_total_duration",
        "duration": {
          "representation": "binary64",
          "bits": "4082c00000000000",
          "unit": "second"
        },
        "resolution": "hourly_bucket",
        "source_device_scope": "one_synthetic_device",
        "observed_session_count": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "original_source_precision": {
          "state": "known",
          "value": "binary64_seconds"
        },
        "overlap_group": {
          "state": "known",
          "value": "synthetic-hourly-daily-group"
        },
        "derived": false
      }
    },
    "expected_encoded": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  },
  {
    "case_id": "literal-record-3",
    "input_json": "{\"domain\":\"device_usage\",\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"app\":{\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\",\"app_class\":\"non_browser\",\"display_label\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"start\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"certainty\":\"observed\"},\"end\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":1,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"certainty\":\"observed\"},\"duration\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"observation_intervals\":[],\"title\":{\"state\":\"not_observed\",\"reason\":\"no_title_grant\"},\"device_state\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}",
    "expected_record": {
      "domain": "device_usage",
      "payload_kind": "foreground_app_session",
      "payload_revision": 1,
      "record_id": "synthetic-usage-session-1",
      "lineage": {
        "dataset_id": "synthetic-dataset-a",
        "device": {
          "state": "known",
          "value": "synthetic-device-a"
        },
        "installation": {
          "state": "known",
          "value": "synthetic-install-a"
        },
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "purpose": "synthetic_local_collection",
        "original_record": {
          "state": "known",
          "value": "synthetic-session-original"
        },
        "record_revision": "1",
        "acquisition": "synthetic_fixture",
        "source_observation": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "integrity_binding": "fixture_only_not_authentication"
      },
      "time": {
        "instant": {
          "representation": "seconds_nanos",
          "epoch": "unix",
          "epoch_seconds": "0",
          "nanoseconds": 1,
          "source_resolution": "nanosecond_representation_not_accuracy",
          "uncertainty": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "source_utc_offset_seconds": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "calendar": {
          "time_zone": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_date": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "owner_rule": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "observed_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "captured_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "imported_at": {
          "state": "unknown",
          "reason": "not_reported"
        },
        "uploaded_at": {
          "state": "unknown",
          "reason": "not_reported"
        }
      },
      "payload": {
        "app": {
          "identity": {
            "state": "known",
            "value": "synthetic-nonbrowser-app"
          },
          "identity_kind": "synthetic_application_id",
          "app_class": "non_browser",
          "display_label": {
            "state": "unknown",
            "reason": "not_reported"
          }
        },
        "start": {
          "instant": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "0",
            "nanoseconds": 1,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "certainty": "observed"
        },
        "end": {
          "instant": {
            "representation": "seconds_nanos",
            "epoch": "unix",
            "epoch_seconds": "1",
            "nanoseconds": 1,
            "source_resolution": "nanosecond_representation_not_accuracy",
            "uncertainty": {
              "state": "unknown",
              "reason": "not_reported"
            }
          },
          "certainty": "observed"
        },
        "duration": {
          "representation": "binary64",
          "bits": "3ff0000000000000",
          "unit": "second"
        },
        "duration_basis": "synthetic_observation",
        "observation_intervals": [],
        "title": {
          "state": "not_observed",
          "reason": "no_title_grant"
        },
        "device_state": {
          "state": "unknown",
          "reason": "not_reported"
        }
      }
    },
    "expected_encoded": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}"
  }
] as const;

export const combinedSliceBaselineRequest = {
  "schema": "candidate.personal_slice_request",
  "revision": 1,
  "dataset_id": "synthetic-dataset-a",
  "dataset_revision": "synthetic-revision-a",
  "snapshot_id": "synthetic-snapshot-a",
  "purpose": "synthetic_local_collection",
  "destination": "synthetic-local-file",
  "caller_binding": "synthetic-caller-a",
  "grant_revision": "1",
  "suppression_revision": "1",
  "slots": [
    {
      "slot": "health",
      "domain": "health",
      "source_id": "synthetic-source-a",
      "source_revision": "synthetic-source-contract1",
      "device_id": "synthetic-device-a",
      "installation_id": "synthetic-install-a",
      "payload_kind": "health_fact",
      "statistic": "observation",
      "profile": "synthetic_only_not_metric_registry_admission",
      "detail": "health_value"
    },
    {
      "slot": "location",
      "domain": "location",
      "source_id": "synthetic-source-a",
      "source_revision": "synthetic-source-contract1",
      "device_id": "synthetic-device-a",
      "installation_id": "synthetic-install-a",
      "payload_kind": "location_point",
      "statistic": "original_point",
      "profile": "candidate.synthetic_location_point_v1",
      "detail": "location_exact_point"
    },
    {
      "slot": "usage",
      "domain": "device_usage",
      "source_id": "synthetic-source-b",
      "source_revision": "synthetic-source-contract1",
      "device_id": "synthetic-device-b",
      "installation_id": "synthetic-install-b",
      "payload_kind": "usage_aggregate",
      "statistic": "source_total_duration",
      "profile": "candidate.synthetic_usage_bucket_v1",
      "detail": "usage_app_duration"
    }
  ],
  "time_scope": {
    "mode": "instant",
    "epoch": "unix",
    "start": {
      "epoch_seconds": "0",
      "nanoseconds": 0
    },
    "end": {
      "epoch_seconds": "1000000000",
      "nanoseconds": 0
    },
    "boundaries": "half_open"
  },
  "strictness": "strict",
  "require_complete": false
} as const;

export const combinedSliceSourceRecipes = {
  "baseline": [
    {
      "slot": "health",
      "binding": {
        "slot": "health",
        "domain": "health",
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "device_id": "synthetic-device-a",
        "installation_id": "synthetic-install-a",
        "payload_kind": "health_fact",
        "statistic": "observation",
        "profile": "synthetic_only_not_metric_registry_admission",
        "detail": "health_value"
      },
      "dataset_revision": "synthetic-revision-a",
      "snapshot_id": "synthetic-snapshot-a",
      "coverage": {
        "status": "partial",
        "reason_codes": [
          "synthetic_only_no_source_completeness_evidence"
        ]
      },
      "pages": [
        {
          "ordinal": 0,
          "terminal": true,
          "record_indices": [
            0
          ]
        }
      ]
    },
    {
      "slot": "location",
      "binding": {
        "slot": "location",
        "domain": "location",
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "device_id": "synthetic-device-a",
        "installation_id": "synthetic-install-a",
        "payload_kind": "location_point",
        "statistic": "original_point",
        "profile": "candidate.synthetic_location_point_v1",
        "detail": "location_exact_point"
      },
      "dataset_revision": "synthetic-revision-a",
      "snapshot_id": "synthetic-snapshot-a",
      "coverage": {
        "status": "partial",
        "reason_codes": [
          "synthetic_only_no_source_completeness_evidence"
        ]
      },
      "pages": [
        {
          "ordinal": 0,
          "terminal": true,
          "record_indices": [
            1
          ]
        }
      ]
    },
    {
      "slot": "usage",
      "binding": {
        "slot": "usage",
        "domain": "device_usage",
        "source_id": "synthetic-source-b",
        "source_revision": "synthetic-source-contract1",
        "device_id": "synthetic-device-b",
        "installation_id": "synthetic-install-b",
        "payload_kind": "usage_aggregate",
        "statistic": "source_total_duration",
        "profile": "candidate.synthetic_usage_bucket_v1",
        "detail": "usage_app_duration"
      },
      "dataset_revision": "synthetic-revision-a",
      "snapshot_id": "synthetic-snapshot-a",
      "coverage": {
        "status": "partial",
        "reason_codes": [
          "synthetic_only_no_source_completeness_evidence"
        ]
      },
      "pages": [
        {
          "ordinal": 0,
          "terminal": true,
          "record_indices": [
            2
          ]
        }
      ]
    }
  ],
  "old_backup": [
    {
      "slot": "health",
      "binding": {
        "slot": "health",
        "domain": "health",
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "device_id": "synthetic-device-a",
        "installation_id": "synthetic-install-a",
        "payload_kind": "health_fact",
        "statistic": "observation",
        "profile": "synthetic_only_not_metric_registry_admission",
        "detail": "health_value"
      },
      "dataset_revision": "synthetic-revision-a",
      "snapshot_id": "synthetic-snapshot-a",
      "coverage": {
        "status": "partial",
        "reason_codes": [
          "synthetic_only_no_source_completeness_evidence"
        ]
      },
      "pages": [
        {
          "ordinal": 0,
          "terminal": true,
          "record_indices": [
            0
          ]
        }
      ]
    },
    {
      "slot": "location",
      "binding": {
        "slot": "location",
        "domain": "location",
        "source_id": "synthetic-source-a",
        "source_revision": "synthetic-source-contract1",
        "device_id": "synthetic-device-a",
        "installation_id": "synthetic-install-a",
        "payload_kind": "location_point",
        "statistic": "original_point",
        "profile": "candidate.synthetic_location_point_v1",
        "detail": "location_exact_point"
      },
      "dataset_revision": "synthetic-revision-a",
      "snapshot_id": "synthetic-snapshot-a",
      "coverage": {
        "status": "partial",
        "reason_codes": [
          "synthetic_only_no_source_completeness_evidence"
        ]
      },
      "pages": [
        {
          "ordinal": 0,
          "terminal": true,
          "record_indices": [
            1
          ]
        }
      ]
    },
    {
      "slot": "usage",
      "binding": {
        "slot": "usage",
        "domain": "device_usage",
        "source_id": "synthetic-source-b",
        "source_revision": "synthetic-source-contract1",
        "device_id": "synthetic-device-b",
        "installation_id": "synthetic-install-b",
        "payload_kind": "usage_aggregate",
        "statistic": "source_total_duration",
        "profile": "candidate.synthetic_usage_bucket_v1",
        "detail": "usage_app_duration"
      },
      "dataset_revision": "synthetic-revision-a",
      "snapshot_id": "synthetic-snapshot-a",
      "coverage": {
        "status": "partial",
        "reason_codes": [
          "synthetic_only_no_source_completeness_evidence"
        ]
      },
      "pages": [
        {
          "ordinal": 0,
          "terminal": true,
          "record_indices": [
            2
          ]
        }
      ]
    }
  ],
  "same_original_twice": {
    "base": "baseline",
    "append_to_page": {
      "slot": "health",
      "ordinal": 0,
      "record_index": 0
    }
  },
  "same_key_changed_bytes": {
    "base": "baseline",
    "append_to_page": {
      "slot": "health",
      "ordinal": 0,
      "record_index": 0,
      "replace_json_pointer": "/payload/value/decimal",
      "literal": "9007199254740994"
    }
  },
  "nine_pages": {
    "slot": "health",
    "pages": [
      {
        "ordinal": 0,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 1,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 2,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 3,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 4,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 5,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 6,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 7,
        "terminal": false,
        "record_indices": []
      },
      {
        "ordinal": 8,
        "terminal": true,
        "record_indices": []
      }
    ]
  },
  "thirty_three_records": {
    "slot": "health",
    "pages": [
      {
        "ordinal": 0,
        "terminal": false,
        "record_indices": [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0
        ]
      },
      {
        "ordinal": 1,
        "terminal": false,
        "record_indices": [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0
        ]
      },
      {
        "ordinal": 2,
        "terminal": false,
        "record_indices": [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0
        ]
      },
      {
        "ordinal": 3,
        "terminal": false,
        "record_indices": [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0
        ]
      },
      {
        "ordinal": 4,
        "terminal": true,
        "record_indices": [
          0
        ]
      }
    ]
  },
  "page_1048577_utf8": {
    "slot": "health",
    "ordinal": 0,
    "terminal": true,
    "record_indices": [],
    "source_binding": {
      "slot": "health",
      "domain": "health",
      "source_id": "synthetic-source-a",
      "source_revision": "synthetic-source-contract1",
      "device_id": "synthetic-device-a",
      "installation_id": "synthetic-install-a",
      "payload_kind": "health_fact",
      "statistic": "observation",
      "profile": "synthetic_only_not_metric_registry_admission",
      "detail": "health_value",
      "profile_pad_ascii": "x",
      "profile_total_utf8_bytes": 1048577
    },
    "expect": "actual metadata byte guard before binding/materialization"
  },
  "record_65537_utf8": {
    "slot": "health",
    "record_index": 0,
    "pad_raw_json_to_utf8_bytes": 65537,
    "padding": "ASCII space after full JSON"
  },
  "snapshot_crosswire": {
    "base": "baseline",
    "slot": "location",
    "literal_snapshot_id": "synthetic-snapshot-other"
  },
  "browser_title_capability": {
    "base": "baseline",
    "source_attempt": "title",
    "authoritative_class": "browser",
    "observe_callback_expected_count": 0
  },
  "source_cleanup_defect": {
    "base": "baseline",
    "release_fault": "SYNTHETIC_PROVIDER_SECRET",
    "acknowledged": false
  },
  "output_over_limit": {
    "base": "baseline",
    "slot": "health",
    "record_template_index": 0,
    "records": [
      {
        "record_id_prefix": "synthetic-large-0-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-0"
      },
      {
        "record_id_prefix": "synthetic-large-1-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-1"
      },
      {
        "record_id_prefix": "synthetic-large-2-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-2"
      },
      {
        "record_id_prefix": "synthetic-large-3-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-3"
      },
      {
        "record_id_prefix": "synthetic-large-4-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-4"
      },
      {
        "record_id_prefix": "synthetic-large-5-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-5"
      },
      {
        "record_id_prefix": "synthetic-large-6-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-6"
      },
      {
        "record_id_prefix": "synthetic-large-7-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-7"
      },
      {
        "record_id_prefix": "synthetic-large-8-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-8"
      },
      {
        "record_id_prefix": "synthetic-large-9-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-9"
      },
      {
        "record_id_prefix": "synthetic-large-10-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-10"
      },
      {
        "record_id_prefix": "synthetic-large-11-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-11"
      },
      {
        "record_id_prefix": "synthetic-large-12-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-12"
      },
      {
        "record_id_prefix": "synthetic-large-13-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-13"
      },
      {
        "record_id_prefix": "synthetic-large-14-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-14"
      },
      {
        "record_id_prefix": "synthetic-large-15-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-15"
      },
      {
        "record_id_prefix": "synthetic-large-16-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-16"
      },
      {
        "record_id_prefix": "synthetic-large-17-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-17"
      },
      {
        "record_id_prefix": "synthetic-large-18-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-18"
      },
      {
        "record_id_prefix": "synthetic-large-19-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-19"
      },
      {
        "record_id_prefix": "synthetic-large-20-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-20"
      },
      {
        "record_id_prefix": "synthetic-large-21-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-21"
      },
      {
        "record_id_prefix": "synthetic-large-22-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-22"
      },
      {
        "record_id_prefix": "synthetic-large-23-",
        "record_id_pad_ascii": "x",
        "record_id_total_scalar_count": 60000,
        "original_record_value": "synthetic-large-original-23"
      }
    ],
    "pages": [
      {
        "ordinal": 0,
        "terminal": false,
        "recipe_record_ordinals": [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7
        ]
      },
      {
        "ordinal": 1,
        "terminal": false,
        "recipe_record_ordinals": [
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15
        ]
      },
      {
        "ordinal": 2,
        "terminal": true,
        "recipe_record_ordinals": [
          16,
          17,
          18,
          19,
          20,
          21,
          22,
          23
        ]
      }
    ],
    "expected_raw_record_each_below": 65536,
    "expected_each_page_below": 1048576,
    "expected_record_count": 26,
    "expected_output_total_exceeds": 1048576
  }
} as const;

export const combinedSliceVectors = [
  {
    "case_id": "combined-original-three",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":3,\"utf8_bytes\":6108}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":3,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        1,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 3,
      "source_releases": 3,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "health-only-same-dataset",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":1,\"utf8_bytes\":1677}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":1,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "location-only-same-dataset",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":1,\"utf8_bytes\":1831}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":1,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        1
      ],
      "coverage": [
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "usage-only-same-dataset",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":1,\"utf8_bytes\":2600}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":1,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        2
      ],
      "coverage": [
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "selector-order-canonical",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":3,\"utf8_bytes\":6108}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":3,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        1,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 3,
      "source_releases": 3,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "empty-selector-selects-nothing",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":0,\"utf8_bytes\":0}],\"completeness\":\"partial\",\"coverage\":[],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":0,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": ""
        }
      ],
      "record_indices": [],
      "coverage": [],
      "source_acquisitions": 0,
      "source_releases": 0,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "location-denied-strict",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_denied",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "materialized_slots": [],
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "source_acquisitions": 0
    }
  },
  {
    "case_id": "location-unavailable-strict",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_unavailable",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "source_required"
      },
      "artifacts": null,
      "materialized_slots": [],
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "source_acquisitions": 0
    }
  },
  {
    "case_id": "location-unknown-strict",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_unknown",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "source_required"
      },
      "artifacts": null,
      "materialized_slots": [],
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "source_acquisitions": 0
    }
  },
  {
    "case_id": "location-denied-allow_partial",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"allow_partial\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_denied",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":2,\"utf8_bytes\":4277}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"scope_not_authorized\"],\"slot\":\"location\",\"status\":\"denied\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":2,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "denied",
          "reason_codes": [
            "scope_not_authorized"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 2,
      "source_releases": 2,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "location-unavailable-allow_partial",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"allow_partial\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_unavailable",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":2,\"utf8_bytes\":4277}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"source_unavailable\"],\"slot\":\"location\",\"status\":\"unavailable\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":2,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "unavailable",
          "reason_codes": [
            "source_unavailable"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 2,
      "source_releases": 2,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "location-unknown-allow_partial",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"allow_partial\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_unknown",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":2,\"utf8_bytes\":4277}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"source_unknown\"],\"slot\":\"location\",\"status\":\"unknown\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":2,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "unknown",
          "reason_codes": [
            "source_unknown"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 2,
      "source_releases": 2,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "strict-requires-complete-evidence",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":true,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "coverage_incomplete"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "partial-bucket-strict",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"3600\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"1800\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "aggregate_partial_overlap"
      },
      "artifacts": null,
      "estimated_duration": null,
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "partial-bucket-allow_partial",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"allow_partial\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"3600\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"1800\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":0,\"utf8_bytes\":0}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"device_usage\",\"reason_codes\":[\"aggregate_partial_overlap\"],\"slot\":\"usage\",\"status\":\"partial_overlap\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":0,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"3600\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"1800\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": ""
        }
      ],
      "record_indices": [],
      "coverage": [
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial_overlap",
          "reason_codes": [
            "aggregate_partial_overlap"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0,
      "estimated_duration": null
    }
  },
  {
    "case_id": "whole-bucket-original-600-seconds",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"3600\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":1,\"utf8_bytes\":2600}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":1,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"3600\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        2
      ],
      "coverage": [
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "half-open-health-at-end-excluded",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"0\",\"nanoseconds\":1},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":0,\"utf8_bytes\":0}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":0,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"0\",\"nanoseconds\":1},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": ""
        }
      ],
      "record_indices": [],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "mixed-epoch-point-between-two-nanos",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"978307201\",\"nanoseconds\":1},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"978307201\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":1,\"utf8_bytes\":1831}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":1,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"978307201\",\"nanoseconds\":1},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"978307201\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        1
      ],
      "coverage": [
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 1,
      "source_releases": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "destination-denied",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "destination_denied",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "unauthorized_materializations": 0
    }
  },
  {
    "case_id": "detail-denied-before-source",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "location_detail_denied",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "unauthorized_materializations": 0
    }
  },
  {
    "case_id": "external-frontier-absent",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "frontier_absent",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "unauthorized_materializations": 0
    }
  },
  {
    "case_id": "external-frontier-stale",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "frontier_stale",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_binding_mismatch"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "unauthorized_materializations": 0
    }
  },
  {
    "case_id": "source-purpose-denied",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "purpose_denied",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "unauthorized_materializations": 0
    }
  },
  {
    "case_id": "source-binding-crosswire",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "crosswire",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_binding_mismatch"
      },
      "artifacts": null,
      "delivery_acquisitions": 0,
      "commit_calls": 0,
      "unauthorized_materializations": 0
    }
  },
  {
    "case_id": "revoke-before-page",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "initial_permitted_then_suppressed",
      "change_at": "before_page",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "commit_calls": 0,
      "resurrect": false
    }
  },
  {
    "case_id": "delete-before-commit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "initial_permitted_then_suppressed",
      "change_at": "before_commit",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "commit_calls": 0,
      "resurrect": false
    }
  },
  {
    "case_id": "backup-regrant-does-not-resurrect",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "old_backup",
      "authority": "initial_permitted_then_suppressed",
      "change_at": "before_page",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "commit_calls": 0,
      "resurrect": false
    }
  },
  {
    "case_id": "delivery-definitely_not_committed",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "definitely_not_committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "definitely_not_committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":3,\"utf8_bytes\":6108}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":3,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        1,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 3,
      "source_releases": 3,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0,
      "automatic_retry": false,
      "rollback_claim": false,
      "recipient_publication_proven": false
    }
  },
  {
    "case_id": "delivery-ambiguous",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "ambiguous"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "ambiguous",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":3,\"utf8_bytes\":6108}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":3,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        1,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 3,
      "source_releases": 3,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0,
      "automatic_retry": false,
      "rollback_claim": false,
      "recipient_publication_proven": false
    }
  },
  {
    "case_id": "cancel-before-source",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "before_source"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": null,
      "source_acquisitions": 0,
      "source_releases": 0,
      "commit_calls": 0,
      "delivery_acquisitions": 0,
      "delivery_releases": 0,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-completed-allocation-handoff",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "allocation_completed_before_registration"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": null,
      "source_acquisitions": 1,
      "source_releases": 1,
      "commit_calls": 0,
      "delivery_acquisitions": 0,
      "delivery_releases": 0,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-during-page",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "page_pending"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": null,
      "source_acquisitions": 1,
      "source_releases": 1,
      "commit_calls": 0,
      "delivery_acquisitions": 0,
      "delivery_releases": 0,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-during-source-release",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "source_release_pending"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": null,
      "source_acquisitions": 1,
      "source_releases": 1,
      "commit_calls": 0,
      "delivery_acquisitions": 0,
      "delivery_releases": 0,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-before-commit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "before_commit"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": null,
      "source_acquisitions": 3,
      "source_releases": 3,
      "commit_calls": 0,
      "delivery_acquisitions": 0,
      "delivery_releases": 0,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-during-commit-committed",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "commit_pending"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": "committed",
      "source_acquisitions": 3,
      "source_releases": 3,
      "commit_calls": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-during-commit-ambiguous",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "ambiguous",
      "cancel_at": "commit_pending"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": "ambiguous",
      "source_acquisitions": 3,
      "source_releases": 3,
      "commit_calls": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "cancel-during-delivery-release",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "cancel_at": "delivery_release_pending"
    },
    "expected": {
      "exit": "interrupted_after_owned_ack",
      "operation_value": null,
      "job_terminal_decision": "committed",
      "source_acquisitions": 3,
      "source_releases": 3,
      "commit_calls": 1,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "completion_before_finalizer_ack": false,
      "rollback_claim": false,
      "automatic_retry": false,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "source-cleanup-defect",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "source_cleanup_defect",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "cleanup_unacknowledged"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "record-conflict",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "same_key_changed_bytes",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "record_identity_conflict"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "page-limit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "nine_pages",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "candidate_limit_exceeded"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "record-limit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "thirty_three_records",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "candidate_limit_exceeded"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "page-byte-limit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "page_1048577_utf8",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "candidate_limit_exceeded"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "record-byte-limit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "record_65537_utf8",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "candidate_limit_exceeded"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "wrong-snapshot",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "snapshot_crosswire",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_binding_mismatch"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "title-source-denied-before-observation",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "browser_title_capability",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "scope_not_authorized"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false,
      "excluded_title_observations": 0
    }
  },
  {
    "case_id": "record-identical-replay-once",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "same_original_twice",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "result": {
        "_tag": "PersonalSliceCompleted",
        "decision": "committed",
        "accounted_jobs": 1,
        "cleanup_acknowledged": true
      },
      "artifacts": [
        {
          "name": "manifest.json",
          "utf8": "{\"artifacts\":[{\"name\":\"records.ndjson\",\"record_count\":3,\"utf8_bytes\":6108}],\"completeness\":\"partial\",\"coverage\":[{\"domain\":\"health\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"health\",\"status\":\"partial\"},{\"domain\":\"location\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"location\",\"status\":\"partial\"},{\"domain\":\"device_usage\",\"reason_codes\":[\"synthetic_only_no_source_completeness_evidence\"],\"slot\":\"usage\",\"status\":\"partial\"}],\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"native_archive_complete\":false,\"record_count\":3,\"revision\":1,\"schema\":\"candidate.personal_slice_manifest\",\"selected_sources\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}"
        },
        {
          "name": "records.ndjson",
          "utf8": "{\"domain\":\"health\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-health-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"extensions\":[],\"native_profile\":\"synthetic_only_not_metric_registry_admission\",\"native_semantic_id\":{\"state\":\"known\",\"value\":\"synthetic.health.exact_count\"},\"semantic_id\":\"synthetic.health.exact_count\",\"statistic\":\"observation\",\"value\":{\"decimal\":\"9007199254740993\",\"representation\":\"unsigned_integer\",\"unit\":\"count\"}},\"payload_kind\":\"health_fact\",\"payload_revision\":1,\"record_id\":\"synthetic-health-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-b\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-b\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-bucket-id\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-b\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"withheld\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-browser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"bucket\":{\"boundaries\":\"half_open\",\"calendar\":{\"owner_date\":{\"state\":\"known\",\"value\":\"1970-01-01\"},\"owner_rule\":\"synthetic_source_bucket\",\"time_zone\":{\"state\":\"known\",\"value\":\"Etc/UTC\"}},\"end\":{\"epoch\":\"unix\",\"epoch_seconds\":\"3600\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"start\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"derived\":false,\"duration\":{\"bits\":\"4082c00000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"observed_session_count\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"original_source_precision\":{\"state\":\"known\",\"value\":\"binary64_seconds\"},\"overlap_group\":{\"state\":\"known\",\"value\":\"synthetic-hourly-daily-group\"},\"resolution\":\"hourly_bucket\",\"source_device_scope\":\"one_synthetic_device\",\"statistic\":\"source_total_duration\"},\"payload_kind\":\"usage_aggregate\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-aggregate-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}\n"
        }
      ],
      "record_indices": [
        0,
        1,
        2
      ],
      "coverage": [
        {
          "slot": "health",
          "domain": "health",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "location",
          "domain": "location",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        },
        {
          "slot": "usage",
          "domain": "device_usage",
          "status": "partial",
          "reason_codes": [
            "synthetic_only_no_source_completeness_evidence"
          ]
        }
      ],
      "source_acquisitions": 3,
      "source_releases": 3,
      "delivery_acquisitions": 1,
      "delivery_releases": 1,
      "commit_calls": 1,
      "native_reads": 0,
      "credential_reads": 0,
      "network_calls": 0
    }
  },
  {
    "case_id": "request-duplicate-key",
    "request_json": "{\"schema\":\"candidate.personal_slice_request\",\"schema\":\"candidate.personal_slice_request\"}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "artifacts": null,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "request-noncanonical-revision",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1.0,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "artifacts": null,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "request-unknown-field",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant\":true,\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "artifacts": null,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "request-empty-interval",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "artifacts": null,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "request-duplicate-selector",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "artifacts": null,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "request-title-detail",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"desktop_window_title\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "artifacts": null,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "delivery_acquisitions": 0,
      "commit_calls": 0
    }
  },
  {
    "case_id": "primitive-request-rejects-object",
    "input_kind": "object",
    "request_json": null,
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "property_or_proxy_traps": 0,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "commit_calls": 0,
      "artifacts": null
    }
  },
  {
    "case_id": "primitive-request-rejects-array",
    "input_kind": "array",
    "request_json": null,
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "property_or_proxy_traps": 0,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "commit_calls": 0,
      "artifacts": null
    }
  },
  {
    "case_id": "primitive-request-rejects-proxy",
    "input_kind": "proxy",
    "request_json": null,
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "property_or_proxy_traps": 0,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "commit_calls": 0,
      "artifacts": null
    }
  },
  {
    "case_id": "primitive-request-rejects-accessor",
    "input_kind": "accessor",
    "request_json": null,
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "property_or_proxy_traps": 0,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "commit_calls": 0,
      "artifacts": null
    }
  },
  {
    "case_id": "primitive-request-rejects-foreign_owned_record",
    "input_kind": "foreign_owned_record",
    "request_json": null,
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "unsupported_request"
      },
      "property_or_proxy_traps": 0,
      "authority_calls": 0,
      "source_acquisitions": 0,
      "commit_calls": 0,
      "artifacts": null
    }
  },
  {
    "case_id": "output-byte-limit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "output_over_limit",
      "authority": "current_all_permitted",
      "delivery": "committed"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "candidate_limit_exceeded"
      },
      "artifacts": null,
      "commit_calls": 0,
      "raw_cause_leak": false
    }
  },
  {
    "case_id": "delivery-cleanup-defect-after-commit",
    "request_json": "{\"caller_binding\":\"synthetic-caller-a\",\"dataset_id\":\"synthetic-dataset-a\",\"dataset_revision\":\"synthetic-revision-a\",\"destination\":\"synthetic-local-file\",\"grant_revision\":\"1\",\"purpose\":\"synthetic_local_collection\",\"require_complete\":false,\"revision\":1,\"schema\":\"candidate.personal_slice_request\",\"slots\":[{\"detail\":\"health_value\",\"device_id\":\"synthetic-device-a\",\"domain\":\"health\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"health_fact\",\"profile\":\"synthetic_only_not_metric_registry_admission\",\"slot\":\"health\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"observation\"},{\"detail\":\"location_exact_point\",\"device_id\":\"synthetic-device-a\",\"domain\":\"location\",\"installation_id\":\"synthetic-install-a\",\"payload_kind\":\"location_point\",\"profile\":\"candidate.synthetic_location_point_v1\",\"slot\":\"location\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"original_point\"},{\"detail\":\"usage_app_duration\",\"device_id\":\"synthetic-device-b\",\"domain\":\"device_usage\",\"installation_id\":\"synthetic-install-b\",\"payload_kind\":\"usage_aggregate\",\"profile\":\"candidate.synthetic_usage_bucket_v1\",\"slot\":\"usage\",\"source_id\":\"synthetic-source-b\",\"source_revision\":\"synthetic-source-contract1\",\"statistic\":\"source_total_duration\"}],\"snapshot_id\":\"synthetic-snapshot-a\",\"strictness\":\"strict\",\"suppression_revision\":\"1\",\"time_scope\":{\"boundaries\":\"half_open\",\"end\":{\"epoch_seconds\":\"1000000000\",\"nanoseconds\":0},\"epoch\":\"unix\",\"mode\":\"instant\",\"start\":{\"epoch_seconds\":\"0\",\"nanoseconds\":0}}}",
    "scenario": {
      "source_fixture": "baseline",
      "authority": "current_all_permitted",
      "delivery": "committed",
      "release_fault": "SYNTHETIC_PROVIDER_SECRET"
    },
    "expected": {
      "failure": {
        "_tag": "PersonalSliceFailure",
        "code": "cleanup_unacknowledged"
      },
      "operation_value": null,
      "job_terminal_decision": "committed",
      "commit_calls": 1,
      "rollback_claim": false,
      "cleanup_acknowledged": false,
      "raw_cause_leak": false
    }
  }
] as const;
