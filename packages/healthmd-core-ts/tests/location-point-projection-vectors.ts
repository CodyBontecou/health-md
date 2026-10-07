// Stage1 independently source-backed literal proposals; no projection implementation or test executed.
import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { OwnedPersonalRecord, PersonalAuthorizationDescriptor, TrustedPersonalCodecContext } from "../src/contracts/personal-slice.js";

export type LocationPointProjectionFailureCode = "unsupported_request" | "source_profile_unadmitted" | "scope_not_authorized" | "source_binding_mismatch" | "candidate_limit_exceeded" | "invalid_source_shape" | "invalid_exact_value" | "coordinate_out_of_range" | "source_unavailable";
export interface LocationPointProjectionFailure { readonly _tag: "LocationPointProjectionFailure"; readonly code: LocationPointProjectionFailureCode }
export interface LocationPointDescriptor { readonly profile: "synthetic.location.point.v1"; readonly dataset_id: string; readonly source_id: string; readonly source_revision: string; readonly purpose: string; readonly record_id: string }
export interface LocationPointLease { readonly materializeOriginalJSON: () => Effect.Effect<string, LocationPointProjectionFailure>; readonly authorize: TrustedPersonalCodecContext["authorize"] }
export interface LocationPointAuthority { readonly acquire: (descriptor: LocationPointDescriptor) => Effect.Effect<LocationPointLease, LocationPointProjectionFailure, Scope.Scope> }
export interface ProjectedLocationPoint { readonly _tag: "ProjectedLocationPoint"; readonly record: OwnedPersonalRecord; readonly canonical_json: string; readonly eligible_evidence_ref: string }
export interface LocationPointProjector { readonly project: (input: unknown) => Effect.Effect<ProjectedLocationPoint, LocationPointProjectionFailure> }
export type LocationPointAuthorizationDescriptor = PersonalAuthorizationDescriptor;

export const locationPointProjectionInterfaceProposal = "Private revision1 proposal only. createLocationPointProjector(authority: LocationPointAuthority) returns project(input: unknown): Effect<ProjectedLocationPoint, LocationPointProjectionFailure>. Request admits only a primitive JSON string, exactly {profile,dataset_id,source_id,source_revision,purpose,record_id}, no coordinates/title/payload; all strings nonempty scalar Unicode/no NUL, duplicates including escaped equivalents reject. Raw UTF8<=4096, depth<=8,nodes<=64 before host calls. Sole profile synthetic.location.point.v1; caller profile/purpose/source claims are requests, not authority. Unknown object/Proxy/accessor/coercion arguments rejected with zero traps/host calls. Authority.acquire(descriptor): Effect<LocationPointLease,LocationPointProjectionFailure,Scope> is one coarse trusted scoped capability. It independently binds descriptor to actual source/profile/purpose/current location-detail grants and latest external deletion/revocation authority BEFORE source field observation/materialization; unreviewed native profile or absent/stale/wrong-lineage/denied frontier cannot acquire/materialize. Descriptor deeply frozen, no personal payload values. An acquired lease is bound to this descriptor and holds materializeOriginalJSON(): Effect<string,LocationPointProjectionFailure>, plus synchronous authorize(PersonalAuthorizationDescriptor) returning the accepted TrustedPersonalCodecContext authorization tuple. The latter independently verifies full source/device/install/original-record lineage/time/detail/catalog and latest suppression; no caller boolean authorizes. Its callbacks are current authority at invocation, not cached acquire approval. Scope acquisition contract: preparatory work interruptible, completed allocation/finalizer registration atomic; failed/partial acquisition cleans itself, release acknowledged before project completion (including canceled materialization). No arbitrary caller can supply a lease to project. Source JSON exactly {source_profile,eligible_evidence_ref,point}; point is the accepted closed revision1 location_point Personal record grammar, except known finite negative horizontalAccuracy or known finite negative speed are admitted as original source sentinel evidence. Original absent altitude/speed remains exactly {state:absent}; horizontal accuracy admits finite scalar or {state:unavailable,reason:native_invalid_accuracy}, never absent; unavailable speed reason native_invalid_speed. No raw original sentinel is a valid canonical sensor: project it to fixed unavailable only under this eligible synthetic source profile. eligible_evidence_ref is a nonempty opaque host-bound reference independently authorized by acquire to retained original exact fields; it proves no archive/storage/hash/authentication and is not a caller authenticity assertion. No extra original source fields/UUID fabrication/implicit profile allowed. Source raw UTF8<=65536/depth<=32/nodes<=4096; duplicate keys/scalar Unicode/NUL/closed raw integer revision1/nanos0..999999999/offset+-86400 grammar checked BEFORE any general numeric parse/Number conversion, matching accepted Personal private grammar. Preserve original epoch bits/i64 nanos/source strings/units/device/install/source original IDs; no Date/epsilon or calendar inference. Compare finite exact binary64 coordinates to [-90,90]/[-180,180], no wrap or donor<=100m rule. No health-distance/CLVisit/session/aggregate equivalence. After sentinel projection reuse accepted createPersonalRecordCodec bound to lease.authorize: decode canonical point rechecks full current authority before canonical payload materialization. Complete scoped release and its acknowledgment BEFORE final encode/publication; then codec.encode synchronously rechecks latest authority and only afterward constructs returned owned result. lease.authorize is an independently host-owned current-authority function, valid after the lease resource closes, not a stale lease snapshot or native handle access. If revoke/delete occurs during asynchronous cleanup, final encode denies and no point/reference publishes. Normal release failure supplies fixed source_unavailable and no published result; cancellation never claims a successful cleanup acknowledgment that failed. Codec faults map only fixed closed projection failure codes. ProjectedLocationPoint is deeply frozen {_tag:ProjectedLocationPoint, record:OwnedPersonalRecord, canonical_json:string, eligible_evidence_ref:string}; module creates records with private same-factory codec, no foreign object encoding path; reference and returned bytes publish only after latest authority permits. Original invalid coordinates/nonfinite/time/malformed source returns fixed error only and no valid point/no movement zero/no payload/reference; raw archive retention remains separate host responsibility. No callbacks between final authorization and synchronous owned result construction. Authority callback reentry cannot mutate inert descriptors or frozen records. Fixed errors {_tag:LocationPointProjectionFailure,code} only: unsupported_request,source_profile_unadmitted,scope_not_authorized,source_binding_mismatch,candidate_limit_exceeded,invalid_source_shape,invalid_exact_value,coordinate_out_of_range,source_unavailable. Cause/provider exceptions sanitize; interruption remains interruption, mixed defect reasons never leak. Owned Effect scope cleanup acknowledged; no storage/SDK/global source admission/public exports/locks/native runtime qualification. Independent review freezes this full interface and all literal fixtures before code; no implementation expectations used. Host materializeOriginalJSON contract includes only independently eligible point/evidence fields, excludes browser/input/other-domain detail before observation and delivery; projection rejects extra supplied fields without returning/hash-binding/logging them but cannot prove native host exclusion. Named request_argument_kind values throwing_proxy/revoked_proxy are test harness input constructors, not accepted request JSON. Synthetic malformed source fixtures intentionally violate host grammar to verify fixed refusal, not permitted native acquisition. Accepted source unavailable arms already projected by a host preserve unknown original sentinel via evidence reference; this module never invents those bits." as const;

export const locationPointProjectionProvenance = {
  "assigned_source": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
  "input_pins": [
    {
      "path": "AGENTS.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456",
      "bytes": 6129
    },
    {
      "path": "GLOSSARY.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "bytes": 3868
    },
    {
      "path": "docs/architecture/javascript-unified-layer-research.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "bytes": 13361
    },
    {
      "path": "docs/architecture/cross-platform-unification-policy.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc",
      "bytes": 9482
    },
    {
      "path": "docs/migration/effect-refactor/personal-data.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0",
      "bytes": 5582
    },
    {
      "path": "docs/migration/effect-refactor/templates.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "bytes": 10054
    },
    {
      "path": "apps/apple/AGENTS.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "043f8c654e9de3489a654f3caba9ba448f4fe1e8704dea923310fc4d10520d13",
      "bytes": 5233
    },
    {
      "path": "apps/android/AGENTS.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "cde6428339645524077ae5395b3d45a8787a9374d5568412e8dccd240f47770c",
      "bytes": 2502
    },
    {
      "path": "packages/healthmd-core-ts/AGENTS.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "bytes": 860
    },
    {
      "path": "packages/healthmd-core-ts/README.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606",
      "bytes": 2988
    },
    {
      "path": "docs/migration/effect-refactor/inventories/donor-location.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "51dd89a982ba18c072eae935220a626e456f3e4baab7fa17c6d7321ca940409f",
      "bytes": 198804
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-DONOR-LOCATION.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "2e6708b405208f923a9347cbba6f0758b92039fee011127c16ac93a2d74f67b8",
      "bytes": 14732
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-DRAFT.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "2325ad12401e52963f00c622f3e81fb8210e7b6396604516595a7610cb3a8643",
      "bytes": 11380
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-REVIEW.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae",
      "bytes": 18284
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-candidate.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "0c50c6d13e48026c9ed81f0325fea73050d52d7b1aa744eb905eae4884b0349d",
      "bytes": 13492
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c",
      "bytes": 68436
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df",
      "bytes": 34193
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-location.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "62276918cdfa9180a5ccc84c0eb4b0bdef8751103e59723dc16389b9b39cc1a7",
      "bytes": 109222
    },
    {
      "path": "packages/healthmd-core-ts/src/contracts/personal-slice.ts",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5",
      "bytes": 25746
    },
    {
      "path": "packages/healthmd-core-ts/tests/personal-codecs-vectors.ts",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a",
      "bytes": 120095
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CODECS.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859",
      "bytes": 24593
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-PERSONAL.json",
      "source_revision": "061afd67a77dca0316a5b3bbd6d5649d078d8186",
      "sha256": "2b0eff4a2e4cd2e190353c8f88ea4eaa6b4325b856f403981aa77df0b3ed9a19",
      "bytes": 43671
    }
  ],
  "donor_source_pins": [
    {
      "path": "IsoMe/Models/LocationPoint.swift",
      "source_revision": "08029281f2e30df83e83d06ba08617ce79ed76bd",
      "sha256": "82ea5202c8f686455c47472e1b380f8596e2107c723351a590aeb33573896c24",
      "bytes": 2795,
      "scope": "immutable source evidence; AGPL donor not adopted"
    },
    {
      "path": "IsoMe/Services/LocationManager.swift",
      "source_revision": "08029281f2e30df83e83d06ba08617ce79ed76bd",
      "sha256": "7ab7c9eeb6f16ea69b17a138dc04bf6359f98f2d9e3cbc83ff79e529c20cb653",
      "bytes": 38037,
      "scope": "immutable source evidence; AGPL donor not adopted"
    }
  ],
  "immutable_obligations": 81,
  "literal_contract_refs": [
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/2",
      "case_id": "point-binary64-lossless",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/5",
      "case_id": "mixed-epoch-selection-precision",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/13",
      "case_id": "unknown-empty-is-not-zero",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/38",
      "case_id": "geographic-health-distance-distinct",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "profile": "accepted bounded synthetic resolution",
      "embedded_json_pointer": "/0",
      "case_id": "resolution-coordinate-endpoints",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "profile": "accepted bounded synthetic resolution",
      "embedded_json_pointer": "/3",
      "case_id": "resolution-negative-speed-sentinel",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "profile": "accepted bounded synthetic resolution",
      "embedded_json_pointer": "/4",
      "case_id": "resolution-negative-accuracy-sentinel",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "profile": "accepted bounded synthetic resolution",
      "embedded_json_pointer": "/30",
      "case_id": "resolution-reasonless-sensor-absent",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "profile": "accepted bounded synthetic resolution",
      "embedded_json_pointer": "/13",
      "case_id": "resolution-apple-unix-equality",
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
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "profile": "accepted bounded synthetic resolution",
      "embedded_json_pointer": "/14",
      "case_id": "resolution-dyadic-subnanosecond",
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
    }
  ],
  "qualification": "synthetic only; source admission/native/archive/store/health-distance/CLVisit/query gates remain separate"
} as const;

export const locationPointProjectionVectors = [
  {
    "case_id": "location-accuracy101-not-universal-reject",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "bits": "4059400000000000",
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4059400000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "location-missing-original-installation",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "state": "unknown",
            "reason": "not_reported"
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "location-profile-not-admitted",
    "request_json": "{\"profile\":\"unreviewed_native\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 0,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "source_profile_unadmitted"
    }
  },
  {
    "case_id": "point-binary64-source-time-and-absent-sensors",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "coordinate-positive-endpoints",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"4056800000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"4066800000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "bits": "4056800000000000",
            "unit": "degree"
          },
          "longitude": {
            "representation": "binary64",
            "bits": "4066800000000000",
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"4056800000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"4066800000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "coordinate-negative-endpoints",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"c056800000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c066800000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "bits": "c056800000000000",
            "unit": "degree"
          },
          "longitude": {
            "representation": "binary64",
            "bits": "c066800000000000",
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"c056800000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c066800000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "coordinate-outside",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"4056c00000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "coordinate_out_of_range"
    }
  },
  {
    "case_id": "nonfinite-coordinate",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"7ff8000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_exact_value"
    }
  },
  {
    "case_id": "negativezero-speed-preserved",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"known\",\"value\":{\"representation\":\"binary64\",\"bits\":\"8000000000000000\",\"unit\":\"meter_per_second\"}},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "state": "known",
            "value": {
              "representation": "binary64",
              "bits": "8000000000000000",
              "unit": "meter_per_second"
            }
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"known\",\"value\":{\"bits\":\"8000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter_per_second\"}}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "negative-speed-source-sentinel",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"known\",\"value\":{\"representation\":\"binary64\",\"bits\":\"bff0000000000000\",\"unit\":\"meter_per_second\"}},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "state": "unavailable",
            "reason": "native_invalid_speed"
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"reason\":\"native_invalid_speed\",\"state\":\"unavailable\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true,
      "retained_original_bits_via_eligible_evidence_ref": "bff0000000000000"
    }
  },
  {
    "case_id": "negative-accuracy-source-sentinel",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"bff0000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "state": "unavailable",
            "reason": "native_invalid_accuracy"
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"reason\":\"native_invalid_accuracy\",\"state\":\"unavailable\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true,
      "retained_original_bits_via_eligible_evidence_ref": "bff0000000000000"
    }
  },
  {
    "case_id": "accuracy-absent-unadmitted",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"state\":\"absent\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_source_shape"
    }
  },
  {
    "case_id": "speed-absent-extra-value",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\",\"value\":0},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_source_shape"
    }
  },
  {
    "case_id": "speed-unavailable-wrong-reason",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"unavailable\",\"reason\":\"unknown\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_source_shape"
    }
  },
  {
    "case_id": "mixed-epoch-unix-original",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"unix\",\"bits\":\"41cd27e440800000\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "epoch": "unix",
            "bits": "41cd27e440800000",
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"41cd27e440800000\",\"epoch\":\"unix\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "dyadic-subnanosecond-original",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"unix\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "projected",
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
            "epoch": "unix",
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
      "expected_canonical_json": "{\"domain\":\"location\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"altitude\":{\"state\":\"absent\"},\"horizontal_accuracy\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"meter\"},\"latitude\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"longitude\":{\"bits\":\"c000000000000000\",\"representation\":\"binary64\",\"unit\":\"degree\"},\"quality\":{\"certainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_is_outlier\":false},\"recording_session\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"speed\":{\"state\":\"absent\"}},\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3ff0000000000001\",\"epoch\":\"unix\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
      "eligible_evidence_ref": "synthetic-original-evidence-a",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "published": true,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "initial-purpose-denied",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "deny_purpose",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "initial-detail-denied",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "deny_location_detail",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "suppression-authority-absent",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "absent_frontier",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "suppression-authority-stale",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "stale_frontier",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "deleted-backup-regrant",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "accepted_delete_with_later_grant",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "current-revoke-before-canonical-materialization",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "deny_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 1,
      "cleanup_acknowledged": true,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "current-delete-before-publication",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "deny_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "cleanup_acknowledged": true,
      "failure_code": "scope_not_authorized"
    }
  },
  {
    "case_id": "source-lineage-crosswire",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"crosswired-source\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "source_binding_mismatch"
    }
  },
  {
    "case_id": "acquire-provider-fault-fixed",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "throw_synthetic_private_provider",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false,
      "failure_code": "source_unavailable"
    }
  },
  {
    "case_id": "materialize-provider-fault-fixed",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "throw_synthetic_private_provider",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "source_unavailable"
    }
  },
  {
    "case_id": "cancel-owned-materialization-ack",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "wait_until_interrupted",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "interrupted",
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "published": false,
      "cleanup_acknowledged": true,
      "returned_reference": false
    }
  },
  {
    "case_id": "raw-revision-fraction",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1.0000000000000001,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_source_shape"
    }
  },
  {
    "case_id": "raw-nanos-exponent",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":1e0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_source_shape"
    }
  },
  {
    "case_id": "source-duplicate-escaped-key",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"\\u0073ource_profile\":\"synthetic.location.point.v1\",\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true,
      "failure_code": "invalid_source_shape"
    }
  },
  {
    "case_id": "raw-nanos-negativezero",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"seconds_nanos\",\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":-0,\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4000000000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "invalid_source_shape",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "request-escaped-duplicate",
    "request_json": "{\"\\u0070rofile\":\"synthetic.location.point.v1\",\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "unsupported_request",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 0,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false
    }
  },
  {
    "case_id": "request-proxy-zero-traps",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "unsupported_request",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 0,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false
    },
    "request_argument_kind": "throwing_proxy"
  },
  {
    "case_id": "request-revoked-proxy-zero-traps",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "unsupported_request",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 0,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false
    },
    "request_argument_kind": "revoked_proxy"
  },
  {
    "case_id": "source-over65536-before-canonical-parse",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ",
    "expected": {
      "outcome": "failure",
      "failure_code": "candidate_limit_exceeded",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "source-escaped-NUL",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"\\u0000\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "invalid_source_shape",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "source-unknown-browser-field",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"browser_url\":\"synthetic-excluded-no-egress\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "invalid_source_shape",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "acquire-interruption-before-allocation",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "interrupt_preparation",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "interrupted",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": false
    }
  },
  {
    "case_id": "acquire-completed-allocation-registration-cancel",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "complete_allocation_then_interrupt_registered_scope",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "interrupted",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 0,
      "codec_authorize_calls": 0,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "current-authorization-provider-fault-fixed",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "throw_synthetic_private_provider"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "scope_not_authorized",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 1,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "revoke-during-release-before-publication",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "deny_current"
      ],
      "materialize": "return_literal",
      "cleanup": "acknowledged_then_revoke_current"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "scope_not_authorized",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 2,
      "cleanup_acknowledged": true
    }
  },
  {
    "case_id": "ordinary-release-failure-no-publication",
    "request_json": "{\"profile\":\"synthetic.location.point.v1\",\"dataset_id\":\"synthetic-dataset-a\",\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"record_id\":\"synthetic-location-1\"}",
    "host_fixture": {
      "acquire": "allow_current",
      "codec_authorize": [
        "allow_current",
        "allow_current"
      ],
      "materialize": "return_literal",
      "cleanup": "fail_synthetic_private_provider"
    },
    "source_json": "{\"source_profile\":\"synthetic.location.point.v1\",\"eligible_evidence_ref\":\"synthetic-original-evidence-a\",\"point\":{\"domain\":\"location\",\"payload_kind\":\"location_point\",\"payload_revision\":1,\"record_id\":\"synthetic-location-1\",\"lineage\":{\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"source_id\":\"synthetic-source-a\",\"source_revision\":\"synthetic-source-contract1\",\"purpose\":\"synthetic_local_collection\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-location-uuid\"},\"record_revision\":\"1\",\"acquisition\":\"synthetic_fixture\",\"source_observation\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"integrity_binding\":\"fixture_only_not_authentication\"},\"time\":{\"instant\":{\"representation\":\"binary64_epoch_seconds\",\"epoch\":\"apple_reference_2001\",\"bits\":\"3ff0000000000001\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"source_utc_offset_seconds\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"calendar\":{\"time_zone\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_date\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"owner_rule\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"observed_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"captured_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"imported_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"},\"uploaded_at\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"payload\":{\"latitude\":{\"representation\":\"binary64\",\"bits\":\"3ff0000000000000\",\"unit\":\"degree\"},\"longitude\":{\"representation\":\"binary64\",\"bits\":\"c000000000000000\",\"unit\":\"degree\"},\"horizontal_accuracy\":{\"representation\":\"binary64\",\"bits\":\"4059400000000000\",\"unit\":\"meter\"},\"altitude\":{\"state\":\"absent\"},\"speed\":{\"state\":\"absent\"},\"quality\":{\"source_is_outlier\":false,\"certainty\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}},\"recording_session\":{\"state\":\"unknown\",\"reason\":\"not_reported\"}}}}",
    "expected": {
      "outcome": "failure",
      "failure_code": "source_unavailable",
      "published": false,
      "returned_reference": false,
      "acquire_calls": 1,
      "materialize_calls": 1,
      "codec_authorize_calls": 1,
      "cleanup_acknowledged": false
    }
  }
] as const;

