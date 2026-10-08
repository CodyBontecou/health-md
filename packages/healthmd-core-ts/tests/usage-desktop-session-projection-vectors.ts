import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { OwnedPersonalRecord, createPersonalRecordCodec } from "../src/contracts/personal-slice.js";
export type SessionCode="invalid_request"|"invalid_source"|"scope_not_authorized"|"owned_handoff_closed"|"cleanup_failed"|"source_failed"|"candidate_limit_exceeded";
export interface SessionFailure {readonly code:SessionCode}
declare const originalBrand:unique symbol; declare const projectionBrand:unique symbol;
export interface OwnedOriginal {readonly [originalBrand]:true}
export interface OwnedSessionProjection {readonly [projectionBrand]:true}
export interface OriginalLifetime {isLive():boolean; readonly closed:Effect.Effect<void>}
export type ProjectionPhase="before_allocation"|"before_original"|"before_decode"|"before_publication"|"before_read";
export interface TrustedSessionBinding {readonly dataset_id:string;readonly source_id:string;readonly source_revision:string;readonly purpose:string;readonly clock_profile:"synthetic-v1"|"native-evidence-v1"}
export interface CurrentSessionAuthority {check(binding:TrustedSessionBinding,phase:ProjectionPhase):Effect.Effect<void,SessionFailure>}
export interface SessionSourceDescriptor {
 readonly dataset_id:string;readonly source_id:string;readonly source_revision:string;
 readonly source_evidence_ref:{readonly state:"known";readonly value:string}|{readonly state:"unknown";readonly reason:"not_reported"};
 readonly app_identity:string;readonly authoritative_app_class:"browser"|"non_browser"|"unknown";
 readonly declared_projection_app_class:"browser"|"non_browser"|"unknown";
 readonly admitted_fields:readonly ["record","original_end","clock_basis","native_algorithm","local_start_text","source_utc_offset"];
 readonly forbidden_detail_present:readonly ("browser_title"|"browser_url"|"browser_history"|"input_telemetry"|"nonbrowser_title"|"archive_auxiliary")[];
}
export interface SourceDescriptorCapability {describe(binding:TrustedSessionBinding):Effect.Effect<SessionSourceDescriptor,SessionFailure>}
export interface OriginalView {read(ticket:unknown):Effect.Effect<string|null,SessionFailure>}
export interface OriginalIssuer {commit():OwnedOriginal|null}
export interface EligibleOriginalSource {
 withOriginal<A>(originalScope:OriginalLifetime,issuer:OriginalIssuer,use:(ticket:OwnedOriginal,view:OriginalView)=>Effect.Effect<A,SessionFailure>):Effect.Effect<A,SessionFailure>;
}
export interface ProjectionMetadata {readonly status:"canonical_session"|"outside_clock_profile"|"unknown_original_end"|"clock_inconsistent"|"duration_disagreement";readonly canonical:boolean;readonly original_end:"present"|"unknown";readonly fabricated_observed_end:false;readonly discard_under_two:false;readonly cleanup_ACK:true}
export interface SourceEvidenceReference {readonly state:"known";readonly value:string}
export interface SessionStatusWrapper {readonly record_ref:string;readonly canonical_status:"valid"|"unavailable"|"outside_canonical";readonly reason_codes:readonly string[];readonly source_evidence_ref:SourceEvidenceReference}
export interface ProjectionView {read(projection:unknown):Effect.Effect<{readonly metadata:ProjectionMetadata;readonly record:OwnedPersonalRecord|null;readonly status:SessionStatusWrapper}|null,SessionFailure>}
export interface SessionProjector {project(request:unknown):Effect.Effect<OwnedSessionProjection,SessionFailure>;readonly view:ProjectionView}
export interface SessionProjectorFactory {create(trusted:{readonly binding:TrustedSessionBinding;readonly current:CurrentSessionAuthority;readonly source:EligibleOriginalSource;readonly descriptor:SourceDescriptorCapability;readonly codec:ReturnType<typeof createPersonalRecordCodec>}):Effect.Effect<SessionProjector,SessionFailure,Scope.Scope>}

export const usageDesktopSessionProjectionFixture = {
  "task_id": "USAGE-DESKTOP-SESSION-PROJECTION",
  "assigned_source": "32f38da439c0489648e99933c99d88805b76ca7b",
  "status": "stage1_literals_pending_independent_review",
  "case_count": 45,
  "input_pins": [
    {
      "path": "AGENTS.md",
      "current_sha256": "830901de59e2afe2023a35bddaa6a1b620d8b40f14bad33d9675ccdadda75f0d",
      "assigned_git_sha256": "830901de59e2afe2023a35bddaa6a1b620d8b40f14bad33d9675ccdadda75f0d",
      "bytes": 6509,
      "current_equals_assigned": true
    },
    {
      "path": "GLOSSARY.md",
      "current_sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "assigned_git_sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "bytes": 3868,
      "current_equals_assigned": true
    },
    {
      "path": "docs/architecture/javascript-unified-layer-research.md",
      "current_sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "assigned_git_sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "bytes": 13361,
      "current_equals_assigned": true
    },
    {
      "path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "current_sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "assigned_git_sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "bytes": 284562,
      "current_equals_assigned": true
    },
    {
      "path": "docs/architecture/cross-platform-unification-policy.md",
      "current_sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc",
      "assigned_git_sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc",
      "bytes": 9482,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/personal-data.md",
      "current_sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0",
      "assigned_git_sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0",
      "bytes": 5582,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/templates.md",
      "current_sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "assigned_git_sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "bytes": 10054,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/AGENTS.md",
      "current_sha256": "043f8c654e9de3489a654f3caba9ba448f4fe1e8704dea923310fc4d10520d13",
      "assigned_git_sha256": "043f8c654e9de3489a654f3caba9ba448f4fe1e8704dea923310fc4d10520d13",
      "bytes": 5233,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/AGENTS.md",
      "current_sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "assigned_git_sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "bytes": 860,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/README.md",
      "current_sha256": "2185850836e6660f5ed41876d72737aad80e00997c71b91984c982615b409cc1",
      "assigned_git_sha256": "2185850836e6660f5ed41876d72737aad80e00997c71b91984c982615b409cc1",
      "bytes": 4123,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/donor-usage-mac.json",
      "current_sha256": "5847579b3a987ba49d41f572aeb105f98cbef730b4e2107fb6b29176443b089c",
      "assigned_git_sha256": "5847579b3a987ba49d41f572aeb105f98cbef730b4e2107fb6b29176443b089c",
      "bytes": 187239,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-DONOR-USAGE-MAC.json",
      "current_sha256": "f3e30d3c0fc5cc760e8e9aaed337e129eeadd5cbb7bab5dd79f91ba456924601",
      "assigned_git_sha256": "f3e30d3c0fc5cc760e8e9aaed337e129eeadd5cbb7bab5dd79f91ba456924601",
      "bytes": 14220,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/hosts.json",
      "current_sha256": "d1b3248adc0b60fa6a4498ddeae0e9e00ff5129189825a837fbd51bd5e3f597c",
      "assigned_git_sha256": "d1b3248adc0b60fa6a4498ddeae0e9e00ff5129189825a837fbd51bd5e3f597c",
      "bytes": 78215,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-HOST.json",
      "current_sha256": "f2104634a018a5e94d834f71a040c5872d1540996fef2ed545b4964c77b24a94",
      "assigned_git_sha256": "f2104634a018a5e94d834f71a040c5872d1540996fef2ed545b4964c77b24a94",
      "bytes": 10062,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-candidate.md",
      "current_sha256": "0c50c6d13e48026c9ed81f0325fea73050d52d7b1aa744eb905eae4884b0349d",
      "assigned_git_sha256": "0c50c6d13e48026c9ed81f0325fea73050d52d7b1aa744eb905eae4884b0349d",
      "bytes": 13492,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "current_sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c",
      "assigned_git_sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c",
      "bytes": 68436,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "current_sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df",
      "assigned_git_sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df",
      "bytes": 34193,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-DRAFT.json",
      "current_sha256": "2325ad12401e52963f00c622f3e81fb8210e7b6396604516595a7610cb3a8643",
      "assigned_git_sha256": "2325ad12401e52963f00c622f3e81fb8210e7b6396604516595a7610cb3a8643",
      "bytes": 11380,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-REVIEW.json",
      "current_sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae",
      "assigned_git_sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae",
      "bytes": 18284,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CODECS.json",
      "current_sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859",
      "assigned_git_sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859",
      "bytes": 24593,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/DATASTORE-SOURCE-CATALOG.json",
      "current_sha256": "40aae1e46eaaa42a5d9220473b13ebe90af3453a5a6f33e2b947ca6f783752c5",
      "assigned_git_sha256": "40aae1e46eaaa42a5d9220473b13ebe90af3453a5a6f33e2b947ca6f783752c5",
      "bytes": 133600,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/cohorts/core-ts-source-catalog-v1.json",
      "current_sha256": "67828453f4fefc1b4c689507af9064ef1ab48672537a9360dc617da80964343d",
      "assigned_git_sha256": "67828453f4fefc1b4c689507af9064ef1ab48672537a9360dc617da80964343d",
      "bytes": 856230,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-SOURCE-CATALOG.json",
      "current_sha256": "b84312bd653e32045e3a19c4b1d0d057b39fd274050e8339016f6197f8f24fce",
      "assigned_git_sha256": "b84312bd653e32045e3a19c4b1d0d057b39fd274050e8339016f6197f8f24fce",
      "bytes": 67630,
      "current_equals_assigned": true
    },
    {
      "path": "scripts/typescript-dev/README.md",
      "current_sha256": "f2b2b79b75edaf87b09927d31c0c345b9e9c4549ae5362655e4ab704da7c6da9",
      "assigned_git_sha256": "f2b2b79b75edaf87b09927d31c0c345b9e9c4549ae5362655e4ab704da7c6da9",
      "bytes": 5329,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/src/contracts/personal-slice.ts",
      "current_sha256": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5",
      "assigned_git_sha256": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5",
      "bytes": 25746,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-usage-desktop.json",
      "current_sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f",
      "assigned_git_sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f",
      "bytes": 139864,
      "current_equals_assigned": true
    }
  ],
  "historical_donor_source_pins": [
    {
      "repository": "time.md",
      "revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "time.md/Data/ActiveAppTracker.swift",
      "sha256": "a816e35377bdf90f4d2615593aebb715c0b5c2a355e510594ef55f429d8967ad",
      "bytes": 11012,
      "literal_ranges": [
        [
          19,
          24
        ],
        [
          53,
          54
        ],
        [
          201,
          234
        ],
        [
          263,
          315
        ]
      ]
    },
    {
      "repository": "time.md",
      "revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "time.md/Data/HistoryStore.swift",
      "sha256": "5d686fe1779f7efb4cb825b1975c04c1a7e7aebb366295245dbbb273c0ed05d4",
      "bytes": 54797,
      "literal_ranges": [
        [
          82,
          111
        ]
      ]
    },
    {
      "repository": "time.md",
      "revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "LICENSE",
      "sha256": "0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0",
      "bytes": 34523,
      "literal_ranges": [
        [
          1,
          10
        ]
      ]
    }
  ],
  "packet_minima": {
    "introduced_path": "packages/healthmd-core-ts/tests/usage-desktop-session-projection-vectors.ts",
    "introduced_case_ids": [
      "session-one-second",
      "session-native-rounded-basis",
      "session-donor-end-absent",
      "session-negative-synthetic-clock",
      "session-zero-observed"
    ],
    "literal_expected_vectors": [
      {
        "case_id": "session-one-second",
        "input": {
          "basis": "synthetic_observation",
          "start_seconds": "0",
          "end_seconds": "1",
          "duration_bits": "3ff0000000000000"
        },
        "expected": {
          "canonical": true,
          "discard_under_two": false
        },
        "status": "proposed literal; independent approval before code"
      },
      {
        "case_id": "session-native-rounded-basis",
        "input": {
          "basis": "native_source_arithmetic",
          "start_bits": "3fb999999999999a",
          "end_bits": "3ff199999999999a",
          "duration_bits": "3ff0000000000000"
        },
        "expected": {
          "current_canonical": false,
          "fixed_status": "outside_clock_profile",
          "automatic_clock_inconsistent": false,
          "original_bits_preserved": true
        },
        "status": "proposed literal; independent approval before code"
      },
      {
        "case_id": "session-donor-end-absent",
        "input": {
          "source_start_present": true,
          "source_duration_present": true,
          "original_end_present": false
        },
        "expected": {
          "original_end": "unknown",
          "fabricated_observed_end": false
        },
        "status": "proposed literal; independent approval before code"
      },
      {
        "case_id": "session-negative-synthetic-clock",
        "input": {
          "basis": "synthetic_observation",
          "start_seconds": "2",
          "end_seconds": "1"
        },
        "expected": {
          "canonical": false,
          "fixed_status": "clock_inconsistent",
          "repair": false
        },
        "status": "proposed literal; independent approval before code"
      },
      {
        "case_id": "session-zero-observed",
        "input": {
          "basis": "synthetic_observation",
          "start_seconds": "0",
          "end_seconds": "0",
          "duration_bits": "0000000000000000"
        },
        "expected": {
          "canonical": true,
          "discard_under_two": false
        },
        "status": "proposed literal; independent approval before code"
      }
    ],
    "draft_case_refs": [
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
        "pointer": "/cases/9",
        "case_id": "short-session-retained"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
        "pointer": "/cases/10",
        "case_id": "historical-donor-short-tail-gap"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
        "pointer": "/cases/11",
        "case_id": "ios-exact-sessions-unestablished"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
        "pointer": "/cases/22",
        "case_id": "missing-donor-lineage"
      }
    ],
    "resolution_case_refs": [
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/6",
        "case_id": "resolution-reversed-session"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/7",
        "case_id": "resolution-duration-disagreement"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/8",
        "case_id": "resolution-zero-session"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/12",
        "case_id": "resolution-missing-stable-import-order"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/13",
        "case_id": "resolution-apple-unix-equality"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/14",
        "case_id": "resolution-dyadic-subnanosecond"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/16",
        "case_id": "resolution-negative-floor-nanos"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/32",
        "case_id": "resolution-native-source-rounded-subtraction"
      },
      {
        "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
        "embedded_json_pointer": "/36",
        "case_id": "resolution-unrepresentable-clipped-duration"
      }
    ],
    "independence": "Literal synthetic expectations before code; historical native test execution/SDK admission not inferred."
  },
  "personal_original81": {
    "draft": [
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
    ],
    "resolution": [
      {
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
      {
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
      {
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
      {
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
      {
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
      {
        "case_id": "resolution-negativezero-speed",
        "input": {
          "speed_bits": "8000000000000000"
        },
        "expected": {
          "canonical_status": "valid",
          "bits": "8000000000000000"
        }
      },
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
        "case_id": "resolution-schema-boolean-version",
        "input": {
          "payload_revision": true
        },
        "expected": {
          "accept": false,
          "safe_code": "unsupported_shape"
        }
      },
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
      {
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
    ]
  },
  "original_personal_session_record": {
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
  "clock_witness": {
    "start_bits": "3fb999999999999a",
    "end_bits": "3ff199999999999a",
    "duration_bits": "3ff0000000000000",
    "exact_endpoint_difference": "36028797018963971/36028797018963968",
    "native_subtraction_expected_rounding": "3ff0000000000000",
    "native_Date_bit_equivalence": "Finite accepted ROOT observations now separately pinned in finite_native_date_witness; pureDouble0.1/1.1 minimum remains distinct/unadmitted."
  },
  "closed_grammar": {
    "request": {
      "synthetic": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
      "native_evidence": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"native-evidence-v1\"}"
    },
    "original_fields": {
      "record": {
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
              "nanoseconds": 0,
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
              "nanoseconds": 0,
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
      "original_end": "present",
      "clock_basis": "synthetic_observation",
      "native_algorithm": {
        "state": "absent"
      },
      "local_start_text": {
        "state": "unknown",
        "reason": "not_reported"
      },
      "source_utc_offset": {
        "state": "unknown",
        "reason": "not_reported"
      }
    },
    "one_pending_original": 1,
    "maximum_raw_utf8": 65536,
    "depth": 32,
    "nodes": 4096,
    "strings": "Unicode scalar, no NUL/unpaired; closed fields/duplicate escaped keys rejected; canonical raw integer lexical bounds before Number",
    "native_basis": "outside clock profile, exact original evidence only; absent end unknown, not derived",
    "classification": "host-issued bound metadata and independently current purpose/detail/destination/frontier; caller strings never grants",
    "title": "No title observation in this projection. Browser URL/domain/path/visit/tab/windowtitle and all input excluded before source callback. Nonbrowser title successor separate; URL-looking nonbrowser title text is not heuristically filtered.",
    "auxiliary": "Projection callback must never return categories/comment/title/browser/input values. Inert retained archive fixture is held at authorized source behind immutable ref and is never passed to candidate or ordinary read. No archive read port is admitted. If adversarial callback violates whitelist after raw read, acknowledge whole-string materialization, reject fixed invalid_source with no codec/publication; this negative is not privacy qualification.",
    "identity": "Original row/device/install/source tuple immutable; unknown install retained, no similarity merge; stable import order missing remains unknown.",
    "ownership": "Capture original Scope/current/codec/source exactly once; watcher subscribes before trusted callback; live replayable closed Effect. Interruptible zero-resource preparation then finite masked allocation+originalScope registration; protected ACK waits, stop and join all owned watcher/phase fibers, no self-finalizer joins; cleanup failure > external interruption > closed > use.",
    "reads": "WeakMap same factory membership before properties; every lazy read rechecks original lifetime, current job/source/detail/destination/frontier before/after actual callback; immediate callback expiry before postcurrent/release ACK; no replay after closure or reprovide under fresh Scope.",
    "publication": "After source protected successful cleanup and current binding checks, final synchronous owned Personal decode/encode under captured trusted codec; no store/commit side effects, no false durability rollback.",
    "source_evidence": "Factory-captured trusted immutable source-evidence reference binds complete eligible source representation/schema/revision/field presence. Ordinary/status reads expose only exact Personal wrapper; no inline raw evidence, no categories/comments payload echo. Archival original access explicitly deferred to separately qualified archive-purpose/detail/destination/current/lifetime capability; no string-purpose shortcut or complete transfer claim.",
    "projection_input_whitelist": [
      "record",
      "original_end",
      "clock_basis",
      "native_algorithm",
      "local_start_text",
      "source_utc_offset"
    ],
    "source_descriptor_protocol": "Capture descriptor.describe and all other ports exactly once at factory construction. Within acknowledged registered OriginalSource lease: Current before_original (source+detail+destination and post-callback destination recheck), then trusted describe(binding), protected originalScope/current recheck after await, validate immutable bounded closed descriptor dataset/source/revision/app identity+authoritative class against source declaration and whitelist BEFORE raw read. A bounded known evidence ref must be actually supplied by this capability, never constant/caller purpose or payload-derived. Descriptor capture is trusted host authority only, not authenticated source admission. Metadata mismatch/detail exclusion refuses before raw fields callback. Parse actual projection payload afterward and bind all fields again before codec/publication. Distinct binding errors: a captured descriptor with missing/wrong bound evidence metadata is invalid_source before read; parsed projection lineage/app differing from the accepted descriptor is scope_not_authorized before codec. Registered-wait interruption occurs before describe, therefore descriptor_calls0."
  },
  "expected_observation_contract": {
    "counts": "Actual fake adapter calls/ACKs, no heap or native proof. Each closed action executes actual phase, not expected/case-ID selection. Interruption code is observation classification; no user/provider cause echo.",
    "record_json": "Exact independently compact canonical fixture JSON; for outside evidence no Personal decode/encode.",
    "original_evidence_json": "Always null ordinary projection/status observation; original evidence is reference-only. Fixture source raw strings are inert synthetic input, not normal query output or archive authority.",
    "cleanup_ACK": "Return owned projection only after one successful aggregate source-release acknowledgment.",
    "status_wrapper": "Exactly {record_ref,canonical_status,reason_codes,source_evidence_ref}; bounded immutable references, no raw JSON.",
    "raw_counter_semantics": {
      "original_materializations": "Actual successful owned callback primitive string receipt/materialization, including strings subsequently rejected by semantic validation. This is observed fixture boundary activity, not private heap/native proof.",
      "admitted_projection_materializations": "Actual whitelist-shaped projection primitive string materialization without prohibited auxiliary fields, independent of duration/binding validation or canonical success. This counter cannot be tied to successful publication.",
      "normal_raw_evidence_materializations": "Prohibited auxiliary/full evidence callback materialization as explicitly accounted by adversarial case43; remains0 for these three projection-only strings."
    }
  },
  "cases": [
    {
      "case_id": "session-one-second",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-zero-observed",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"0000000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"0000000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-negative-synthetic-clock",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"bff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"2\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"2\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "clock_inconsistent",
          "canonical": false,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": true,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "outside_canonical",
          "reason_codes": [
            "clock_inconsistent"
          ],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-synthetic-duration-disagreement",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"4000000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "duration_disagreement",
          "canonical": false,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "outside_canonical",
          "reason_codes": [
            "invalid_exact_value"
          ],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-native-rounded-basis",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"native-evidence-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"native_source_arithmetic\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"known\",\"value\":\"Foundation.Date.timeIntervalSince;source_revision=2955ed07db9c649c77a128db59aed2ac0fef0bc5\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"native_source_arithmetic\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3ff199999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "native-evidence-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "outside_clock_profile",
          "canonical": false,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "outside_canonical",
          "reason_codes": [
            "unsupported_shape"
          ],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-donor-end-absent",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"native-evidence-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"native_source_arithmetic\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"absent\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"native_source_arithmetic\",\"end\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "native-evidence-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "unknown_original_end",
          "canonical": false,
          "original_end": "unknown",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "unavailable",
          "reason_codes": [
            "unsupported_shape"
          ],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-unknown-installation",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-original-identity-retained",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"sqlite:usage:42\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"sqlite:usage:42\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-local-whole-second-text-no-offset-inference",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"state\":\"known\",\"value\":\"2001-01-01T00:00:00\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-allowed-category-comment-evidence-separate",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [
            "synthetic_category"
          ],
          "comment": {
            "state": "known",
            "value": "synthetic note"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-browser-app-duration-allowed",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "browser",
          "declared_projection_app_class": "browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-half-second-retained",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3fe0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":500000000,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3fe0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":500000000,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-mixed-apple-unix-exact-one-second",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"978307201\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"0000000000000000\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"0000000000000000\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"978307201\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"0000000000000000\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"0000000000000000\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-subnanosecond-no-rounded-nanos",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"0000000000000001\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"0000000000000001\",\"epoch\":\"unix\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"0000000000000001\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"0000000000000001\",\"epoch\":\"unix\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-negative-floor-nanos-exact",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":999999999,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"-1\",\"nanoseconds\":999999999,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"-1\",\"nanoseconds\":999999999,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":999999999,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"-1\",\"nanoseconds\":999999999,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"-1\",\"nanoseconds\":999999999,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-invalid-duration-nonfinite",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"7ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_source",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-invalid-duration-bit-grammar",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3FF0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_source",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-source-crosswire-rejected-before-codec",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-other\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-request-not-a-primitive",
      "stimulus": {
        "request": {
          "version": 1
        },
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_request",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 0,
          "source_release_attempts": 0,
          "source_release_ACKs": 0,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-request-proxy-before-properties",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "request",
            "op": "throwing_Proxy",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_request",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 0,
          "source_release_attempts": 0,
          "source_release_ACKs": 0,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-current-source-denied-before-acquire",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "current.before_allocation",
            "op": "deny",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 0,
          "source_release_attempts": 0,
          "source_release_ACKs": 0,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-destination-only-revoke-before-original",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "current.before_original",
            "op": "revoke_destination",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-source-current-callback-revokes-destination",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "current.before_original",
            "op": "revoke_destination_return_source_permitted",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-source-read-revoke-before-return",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.read",
            "op": "revoke_then_return",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-latest-delete-before-decode",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "current.before_decode",
            "op": "accept_delete",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-regrant-cannot-resurrect-deletion",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "current.before_decode",
            "op": "restore_backup_and_regrant_after_delete",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-revocation-before-publication",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "current.before_publication",
            "op": "revoke",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-foreign-original-before-properties",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.read",
            "op": "foreign_ticket_Proxy",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_source",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-original-scope-closed-before-acquire",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "controller.before_project",
            "op": "close_original",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "owned_handoff_closed",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 0,
          "source_release_attempts": 0,
          "source_release_ACKs": 0,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-interrupt-pending-preparation-zero-allocation",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.prepare",
            "op": "suspend_then_external_interrupt",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "interruption",
        "failure": null,
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 0,
          "source_release_attempts": 0,
          "source_release_ACKs": 0,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-completed-allocation-interrupt-waits-ACK",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.registered_wait",
            "op": "suspend_then_external_interrupt",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "interruption",
        "failure": null,
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 0
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-cleanup-failure-never-publish",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.cleanup",
            "op": "fail_fixed",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "cleanup_failed",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 0,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-native-provider-secret-fixed",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.read",
            "op": "provider_defect",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "source_failed",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-browser-title-not-observed",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.metadata",
            "op": "browser_title_present",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": [
            "browser_title"
          ]
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-unknown-app-title-fail-closed",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.metadata",
            "op": "unknown_class_title_present",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "unknown",
          "declared_projection_app_class": "unknown",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": [
            "nonbrowser_title"
          ]
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-forbidden-input-route",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "source.metadata",
            "op": "input_telemetry_present",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": [
            "input_telemetry"
          ]
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-foreign-projection-proxy",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "after_project",
            "op": "foreign_projection_Proxy",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "probe": {
          "read_result": null,
          "extra_current_calls": 0,
          "extra_property_traps": 0
        },
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-saved-view-after-original-close",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "after_project",
            "op": "close_then_read",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "probe": {
          "read_result": null,
          "extra_current_calls": 0
        },
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-same-lazy-read-rechecks-revoke",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "after_project",
            "op": "read_success_revoke_reexecute",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "probe": {
          "first_read_record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
          "second_read_failure": "scope_not_authorized",
          "second_text_materializations": 0
        },
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-expired-original-callback",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [
          {
            "at": "after_project",
            "op": "saved_original_read_after_callback",
            "ordinal": 1
          }
        ],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "probe": {
          "read_result": null,
          "extra_current_calls": 0
        },
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-missing-source-evidence-reference",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "unknown",
            "reason": "not_reported"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_source",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-source-evidence-descriptor-crosswire",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-other",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_source",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-trusted-classification-declaration-mismatch-before-read",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "scope_not_authorized",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 0,
          "original_materializations": 0,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    },
    {
      "case_id": "session-prohibited-auxiliary-callback-after-real-read",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"categories\":[\"synthetic_category\"],\"clock_basis\":\"synthetic_observation\",\"comment\":{\"state\":\"known\",\"value\":\"synthetic note\"},\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "fixed_failure",
        "failure": "invalid_source",
        "metadata": null,
        "record_json": null,
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 0,
          "codec_encodes": 0,
          "title_observations": 0,
          "publication_returns": 0,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": false,
        "return_after_cleanup_ACK": false,
        "status_wrapper": null,
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 1,
        "admitted_projection_materializations": 0,
        "auxiliary_value_observations": 2,
        "auxiliary_value_materializations": 2
      }
    },
    {
      "case_id": "session-actual-captured-source-evidence-reference",
      "stimulus": {
        "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
        "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
        "trusted_clock_profile": "synthetic-v1",
        "trusted_app_class": "non_browser",
        "actions": [],
        "inert_retained_archive_fixture": {
          "categories": [],
          "comment": {
            "state": "absent"
          }
        },
        "trusted_descriptor": {
          "dataset_id": "synthetic-dataset-a",
          "source_id": "synthetic-source-a",
          "source_revision": "synthetic-source-contract1",
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-b"
          },
          "app_identity": "synthetic-nonbrowser-app",
          "authoritative_app_class": "non_browser",
          "declared_projection_app_class": "non_browser",
          "admitted_fields": [
            "record",
            "original_end",
            "clock_basis",
            "native_algorithm",
            "local_start_text",
            "source_utc_offset"
          ],
          "forbidden_detail_present": []
        }
      },
      "expected": {
        "kind": "owned_projection",
        "failure": null,
        "metadata": {
          "status": "canonical_session",
          "canonical": true,
          "original_end": "present",
          "fabricated_observed_end": false,
          "discard_under_two": false,
          "cleanup_ACK": true
        },
        "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
        "original_evidence_json": null,
        "counts": {
          "source_allocations": 1,
          "source_release_attempts": 1,
          "source_release_ACKs": 1,
          "source_reads": 1,
          "original_materializations": 1,
          "codec_decodes": 1,
          "codec_encodes": 1,
          "title_observations": 0,
          "publication_returns": 1,
          "property_traps": 0,
          "descriptor_calls": 1
        },
        "native_date_algorithm_qualified": false,
        "native_capture_qualified": false,
        "automatic_clock_inconsistent": false,
        "original_bits_preserved": true,
        "return_after_cleanup_ACK": true,
        "status_wrapper": {
          "record_ref": "synthetic-usage-session-1",
          "canonical_status": "valid",
          "reason_codes": [],
          "source_evidence_ref": {
            "state": "known",
            "value": "synthetic-source-evidence-b"
          }
        },
        "archive_read_calls": 0,
        "normal_raw_evidence_materializations": 0,
        "admitted_projection_materializations": 1,
        "auxiliary_value_observations": 0,
        "auxiliary_value_materializations": 0
      }
    }
  ],
  "remaining": [
    "Native Foundation bits and Date/timeIntervalSince/Unixconversion admission",
    "Actual host/classification race/privacy/API/signing/durablecollector proof",
    "Title/device-state/checkpoint/fullSQLarchives/categorycomments migrations",
    "Full historical sessions beyond365-day mirror; short already-discarded/precollector/crash gaps not reconstructed",
    "WindowsLinux later and required iOS exact-session S06; aggregate boundaries never sessions",
    "No donorAGPLsource adoption/public schema/sourcepurpose/grantauth/codec successor cohort admission",
    "Archive original evidence access is explicitly deferred; source-evidence reference is not payload quarantine or automatic archive grant."
  ],
  "finite_native_date_witness": {
    "accepted_independent_review": {
      "path": "/private/tmp/healthmd-native-query-source-witness-effect-baseline-review.json",
      "sha256": "ab2a8220f0bbced1d8ea27da90e81d31988f5bf322da5d6e06d9ab16f1b5a034",
      "bytes": 4668
    },
    "manifest": {
      "path": "/private/tmp/healthmd-native-query-source-witness/pre-execution-manifest.json",
      "sha256": "e411167f6dd945cd5215509fcba021bf04281da39f28061ab373fdcd93e2dcf0",
      "bytes": 3591
    },
    "execution_report": {
      "path": "/private/tmp/healthmd-native-query-source-witness/execution-report.json",
      "sha256": "17c71d7b67f902369656fa42d742228ad4a488b245cca0d667bb3744744dc92e",
      "bytes": 4054
    },
    "native_output": {
      "path": "/private/tmp/healthmd-native-query-source-witness/native-output.json",
      "sha256": "af7aab0daeaf88bd381900fb915dc1a9c11d28ee1480aaef169ea91a669b960e",
      "bytes": 11656
    },
    "exact_date_rows": [
      {
        "canonical": "1970-01-01T00:00:00.100000024Z",
        "input_bits": "3fb999999999999a",
        "input_decimal": "0.1",
        "reference_bits": "c1cd27e43ff33333",
        "unix_bits": "3fb9999a00000000"
      },
      {
        "canonical": "1970-01-01T00:00:01.100000024Z",
        "input_bits": "3ff199999999999a",
        "input_decimal": "1.1",
        "reference_bits": "c1cd27e43f733333",
        "unix_bits": "3ff19999a0000000"
      },
      {
        "canonical": "2023-11-14T22:13:20.123456717Z",
        "input_bits": "41d954fc4007e6b7",
        "input_decimal": "1700000000.123456789",
        "reference_bits": "41c58214400fcd6e",
        "unix_bits": "41d954fc4007e6b7"
      },
      {
        "canonical": "2023-11-14T22:13:20.000000238Z",
        "input_bits": "41d954fc40000001",
        "input_decimal": "1700000000.0000002",
        "reference_bits": "41c5821440000002",
        "unix_bits": "41d954fc40000001"
      },
      {
        "canonical": "1969-12-31T23:59:59.876543164Z",
        "input_bits": "bfbf9add3739635f",
        "input_decimal": "-0.123456789",
        "reference_bits": "c1cd27e4400fcd6f",
        "unix_bits": "bfbf9ade00000000"
      },
      {
        "canonical": "2023-11-14T22:13:20.999999762Z",
        "input_bits": "41d954fc403fffff",
        "input_decimal": "1700000000.9999998",
        "reference_bits": "41c58214407ffffe",
        "unix_bits": "41d954fc403fffff"
      }
    ],
    "exact_subtraction": {
      "end_reference_bits": "c1cd27e43f733333",
      "end_unix_bits": "3ff19999a0000000",
      "exposed_unix_subtraction_bits": "3ff0000000000000",
      "input_end_bits": "3ff199999999999a",
      "input_start_bits": "3fb999999999999a",
      "start_reference_bits": "c1cd27e43ff33333",
      "start_unix_bits": "3fb9999a00000000",
      "timeIntervalSince_bits": "3ff0000000000000"
    },
    "profile": "ROOT-observed macOS26.5.1/SDK26.5/Swift6.3.3 only; source/native Date witness, not app/collector/iOS qualification or current Personal admission",
    "construction_vs_source_storage": "InputDouble0.1→Date→exposedUnix3fb9999a00000000. Never replace donor-persisted sourceTimestamp with original constructor bits; original donor SQL end absent stays unknown."
  },
  "reviewed_precode_amendment": {
    "reason": "Exact Personal resolution line31 reference-only status wrapper; remove raw quarantine echo before implementation",
    "prior_vector_sha256": "8be45aeb345aead07c49b4c619a53c561eb7cb37cde303f56fbbf81281ca3858",
    "raw_ordinary_access_removed": true,
    "archive_access": "deferred",
    "native_witness": "bounded exact observed source profile only; current codec unadmitted",
    "review": "pending independent re-review"
  },
  "whitelist_amendment_history": {
    "prior_vector_sha256": "f960cdbb7b47f9a47a323c0d2e9cebc26cab53d37c708c33e041d20c2e63dcee",
    "independent_report": "/private/tmp/healthmd-desktop-session-stage1-reference-wrapper-effect-baseline-review.json",
    "independent_sha256": "468e432904590350d5d45d38d2bacef179df71b00bdc80b13f714c3dd95ac47a",
    "historical40": "Only approved source whitelist+captured descriptor+explicit observation expansions; entire immutable81 preserved.",
    "new_cases": 5,
    "archive_access": "deferred, no raw port"
  },
  "approved_three_raw_counter_amendment": {
    "independent_review_sha256": "9b68ecd659fec3a9a59866442a72ae8fe1ef6304e082bcaa9ab3c3071f2aedea",
    "changes": "Exactly six scalars across three cases, before any execution; source-derived actual callback receipt semantics",
    "all45_stimuli_and42_other_expected_records_unchanged": true,
    "immutable81_unchanged": true
  },
  "stage2_review_supplement": {
    "status": "supplemental_literals_pending_independent_review_before_code",
    "review_source": {
      "path": "/private/tmp/healthmd-desktop-session-stage2-source-effect-baseline-review.json",
      "sha256": "71b95e701ba516e348176c396948afb7fd6fd4034aea1f8d1816eacbdd553c4a"
    },
    "case_count": 6,
    "preservation_observer_case_count": 4,
    "closed_strategy": [
      "Factory holds one protected slot. Validate primitive request and original lifetime first; atomically reserve slot before any Current/descriptor/source preparation callback. Contending live valid call fails candidate_limit_exceeded with zero trusted callbacks. No public busy API or internal counter inspector.",
      "Reservation includes interruptible preparation, registered waits, use and protected cleanup ACK, child/watcher stop+join, final current/codec/publication and terminal cause mapping. Protected finally frees slot on unallocated source failure or acknowledged terminal cancellation/success. Actual owned cleanup failure poisons factory; later calls fail cleanup_failed before source callbacks.",
      "withOriginal unknown Fail/Die maps source_failed, never manufacturing cleanup_failed from fallback. Only own sealed cleanup_failed returned by positively registered cleanup contract yields cleanup precedence/poison; test cleanup fails from an actual registered acquireRelease finalizer after release_attempt increment. External cancellation is real Fiber interruption, not a fabricated interruption flag.",
      "Concurrency driver readiness is actual owned Deferred registration / actual commit / actual cleanup latch signal. Join real child and cancellation controller; no yieldNow or sleep assumption. Active source-callback and lease counters increment at actual entry/commit and decrement only after terminal cleanup; track observed maxima, not constants. No candidate decision keyed by scenario ID or expected.",
      "original_bits_preserved is derived after an actual owned result read. Host synthetic immutable evidence map is captured before callback and bound to the actual descriptor reference; callback records exact delivered primitive projection string. Compare the delivered record/time/duration/end/clock/source-revision representation to the retained projection under the actual returned status evidence reference. For canonical results additionally compare actual returned owned record exact time/payload/lineage/record fields to delivered record. Failed/no-return outcomes remain false; success alone never determines the flag.",
      "For native outside-profile results, record remains null; compare actual status reference to captured source reference and exact delivered source representation to immutable retained source representation. This is synthetic source-evidence trace observability only, not an archive read capability, native storage durability or inline raw product output. Corrupted-return and wrong-ref observer fixtures are independent negative tests of the observation function, not candidate mutation.",
      "Existing 45 whole literal objects and 81 Personal obligations remain byte-for-byte canonical objects. No implementation/test repair before independent supplemental approval. Existing native clock basis remains unadmitted; title/archive/browser fields are excluded before source observation under the accepted whitelist."
    ],
    "scenes": [
      {
        "case_id": "session-slot-pending-preparation-busy-then-recovery",
        "stimulus": {
          "same_factory": true,
          "calls": [
            {
              "label": "A",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [
                  {
                    "at": "source.prepare",
                    "op": "hold_on_owned_latch",
                    "ordinal": 1
                  }
                ],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "B",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "C",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            }
          ],
          "controller_schedule": [
            "fork A; await actual preparation latch registration",
            "run B to terminal while A suspended",
            "release A preparation latch; join A and ACK",
            "run C to terminal"
          ]
        },
        "expected": {
          "calls": [
            {
              "label": "A",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "B",
              "observation": {
                "kind": "fixed_failure",
                "failure": "candidate_limit_exceeded",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 0,
                  "source_release_attempts": 0,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "C",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            }
          ],
          "ownership_trace": {
            "maximum_active_source_callbacks": 1,
            "maximum_owned_leases": 1,
            "source_callback_entries": 2,
            "B_trusted_callbacks": 0,
            "B_allocations": 0,
            "B_terminal_before_A_resumed": true,
            "C_admitted_after_A_terminal": true
          },
          "secret_cause_exposed": false,
          "archive_read_calls": 0,
          "title_observations": 0
        }
      },
      {
        "case_id": "session-slot-registered-lease-busy-then-recovery",
        "stimulus": {
          "same_factory": true,
          "calls": [
            {
              "label": "A",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [
                  {
                    "at": "source.registered_wait",
                    "op": "hold_on_owned_latch",
                    "ordinal": 1
                  }
                ],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "B",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "C",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            }
          ],
          "controller_schedule": [
            "fork A; await actual registered lease and registered wait latch",
            "run B to terminal",
            "release A registered wait; join A and ACK",
            "run C to terminal"
          ]
        },
        "expected": {
          "calls": [
            {
              "label": "A",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "B",
              "observation": {
                "kind": "fixed_failure",
                "failure": "candidate_limit_exceeded",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 0,
                  "source_release_attempts": 0,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "C",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            }
          ],
          "ownership_trace": {
            "maximum_active_source_callbacks": 1,
            "maximum_owned_leases": 1,
            "source_callback_entries": 2,
            "B_trusted_callbacks": 0,
            "B_allocations": 0,
            "B_terminal_before_A_resumed": true,
            "C_admitted_after_A_terminal": true
          },
          "secret_cause_exposed": false,
          "archive_read_calls": 0,
          "title_observations": 0
        }
      },
      {
        "case_id": "session-slot-cancellation-protected-cleanup-holds",
        "stimulus": {
          "same_factory": true,
          "calls": [
            {
              "label": "A",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [
                  {
                    "at": "source.registered_wait",
                    "op": "hold_until_external_interrupt",
                    "ordinal": 1
                  },
                  {
                    "at": "source.cleanup",
                    "op": "hold_ACK_on_owned_latch",
                    "ordinal": 1
                  }
                ],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "B",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "C",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            }
          ],
          "controller_schedule": [
            "fork A; await actual lease wait registration",
            "fork Fiber.interrupt(A); await cleanup attempt and protected ACK latch registration",
            "run B to terminal with cleanup still pending",
            "assert A and interrupt controller still pending; release ACK latch",
            "join A and cancellation controller; run C"
          ]
        },
        "expected": {
          "calls": [
            {
              "label": "A",
              "observation": {
                "kind": "interruption",
                "failure": null,
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "B",
              "observation": {
                "kind": "fixed_failure",
                "failure": "candidate_limit_exceeded",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 0,
                  "source_release_attempts": 0,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "C",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            }
          ],
          "ownership_trace": {
            "maximum_active_source_callbacks": 1,
            "maximum_owned_leases": 1,
            "source_callback_entries": 2,
            "B_trusted_callbacks": 0,
            "B_allocations": 0,
            "ACKs_before_latch_release": 0,
            "A_terminal_before_ACK": false,
            "interrupt_controller_terminal_before_ACK": false,
            "C_admitted_after_A_terminal": true
          },
          "secret_cause_exposed": false,
          "archive_read_calls": 0,
          "title_observations": 0
        }
      },
      {
        "case_id": "session-preallocation-unknown_fail-source-failed-no-poison",
        "stimulus": {
          "same_factory": true,
          "calls": [
            {
              "label": "A",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [
                  {
                    "at": "source.prepare",
                    "op": "unknown_Fail",
                    "ordinal": 1
                  }
                ],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "B",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            }
          ],
          "controller_schedule": [
            "run A to terminal before issuer.commit",
            "run B on same factory with healthy source"
          ]
        },
        "expected": {
          "calls": [
            {
              "label": "A",
              "observation": {
                "kind": "fixed_failure",
                "failure": "source_failed",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 0,
                  "source_release_attempts": 0,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "B",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            }
          ],
          "ownership_trace": {
            "maximum_active_source_callbacks": 1,
            "maximum_owned_leases": 1,
            "source_callback_entries": 2,
            "A_allocations": 0,
            "A_cleanup_attempts": 0,
            "A_cleanup_ACKs": 0,
            "A_descriptor_calls": 0,
            "A_raw_reads": 0,
            "B_admitted_after_A_terminal": true,
            "factory_poisoned_after_A": false
          },
          "secret_cause_exposed": false,
          "archive_read_calls": 0,
          "title_observations": 0
        }
      },
      {
        "case_id": "session-preallocation-unknown_die-source-failed-no-poison",
        "stimulus": {
          "same_factory": true,
          "calls": [
            {
              "label": "A",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [
                  {
                    "at": "source.prepare",
                    "op": "unknown_Die",
                    "ordinal": 1
                  }
                ],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "B",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            }
          ],
          "controller_schedule": [
            "run A to terminal before issuer.commit",
            "run B on same factory with healthy source"
          ]
        },
        "expected": {
          "calls": [
            {
              "label": "A",
              "observation": {
                "kind": "fixed_failure",
                "failure": "source_failed",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 0,
                  "source_release_attempts": 0,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "B",
              "observation": {
                "kind": "owned_projection",
                "failure": null,
                "metadata": {
                  "status": "canonical_session",
                  "canonical": true,
                  "original_end": "present",
                  "fabricated_observed_end": false,
                  "discard_under_two": false,
                  "cleanup_ACK": true
                },
                "record_json": "{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}}",
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 1,
                  "source_reads": 1,
                  "original_materializations": 1,
                  "codec_decodes": 1,
                  "codec_encodes": 1,
                  "title_observations": 0,
                  "publication_returns": 1,
                  "property_traps": 0,
                  "descriptor_calls": 1
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": true,
                "return_after_cleanup_ACK": true,
                "status_wrapper": {
                  "record_ref": "synthetic-usage-session-1",
                  "canonical_status": "valid",
                  "reason_codes": [],
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  }
                },
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 1,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            }
          ],
          "ownership_trace": {
            "maximum_active_source_callbacks": 1,
            "maximum_owned_leases": 1,
            "source_callback_entries": 2,
            "A_allocations": 0,
            "A_cleanup_attempts": 0,
            "A_cleanup_ACKs": 0,
            "A_descriptor_calls": 0,
            "A_raw_reads": 0,
            "B_admitted_after_A_terminal": true,
            "factory_poisoned_after_A": false
          },
          "secret_cause_exposed": false,
          "archive_read_calls": 0,
          "title_observations": 0
        }
      },
      {
        "case_id": "session-owned-cleanup-failure-dominates-real-interruption",
        "stimulus": {
          "same_factory": true,
          "calls": [
            {
              "label": "A",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [
                  {
                    "at": "source.registered_wait",
                    "op": "hold_until_external_interrupt",
                    "ordinal": 1
                  },
                  {
                    "at": "source.cleanup",
                    "op": "fail_fixed_after_actual_release_attempt",
                    "ordinal": 1
                  }
                ],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            },
            {
              "label": "B",
              "stimulus": {
                "request": "{\"version\":1,\"source_binding\":\"synthetic-source-a\",\"clock_profile\":\"synthetic-v1\"}",
                "original_fields_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
                "trusted_clock_profile": "synthetic-v1",
                "trusted_app_class": "non_browser",
                "actions": [],
                "inert_retained_archive_fixture": {
                  "categories": [],
                  "comment": {
                    "state": "absent"
                  }
                },
                "trusted_descriptor": {
                  "dataset_id": "synthetic-dataset-a",
                  "source_id": "synthetic-source-a",
                  "source_revision": "synthetic-source-contract1",
                  "source_evidence_ref": {
                    "state": "known",
                    "value": "synthetic-source-evidence-a"
                  },
                  "app_identity": "synthetic-nonbrowser-app",
                  "authoritative_app_class": "non_browser",
                  "declared_projection_app_class": "non_browser",
                  "admitted_fields": [
                    "record",
                    "original_end",
                    "clock_basis",
                    "native_algorithm",
                    "local_start_text",
                    "source_utc_offset"
                  ],
                  "forbidden_detail_present": []
                }
              }
            }
          ],
          "controller_schedule": [
            "fork A; await registered lease wait",
            "request actual Fiber.interrupt(A); wait until child joined and failed release observed",
            "run B on same factory"
          ]
        },
        "expected": {
          "calls": [
            {
              "label": "A",
              "observation": {
                "kind": "fixed_failure",
                "failure": "cleanup_failed",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 1,
                  "source_release_attempts": 1,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            },
            {
              "label": "B",
              "observation": {
                "kind": "fixed_failure",
                "failure": "cleanup_failed",
                "metadata": null,
                "record_json": null,
                "original_evidence_json": null,
                "counts": {
                  "source_allocations": 0,
                  "source_release_attempts": 0,
                  "source_release_ACKs": 0,
                  "source_reads": 0,
                  "original_materializations": 0,
                  "codec_decodes": 0,
                  "codec_encodes": 0,
                  "title_observations": 0,
                  "publication_returns": 0,
                  "property_traps": 0,
                  "descriptor_calls": 0
                },
                "native_date_algorithm_qualified": false,
                "native_capture_qualified": false,
                "automatic_clock_inconsistent": false,
                "original_bits_preserved": false,
                "return_after_cleanup_ACK": false,
                "status_wrapper": null,
                "archive_read_calls": 0,
                "normal_raw_evidence_materializations": 0,
                "admitted_projection_materializations": 0,
                "auxiliary_value_observations": 0,
                "auxiliary_value_materializations": 0
              }
            }
          ],
          "ownership_trace": {
            "maximum_active_source_callbacks": 1,
            "maximum_owned_leases": 1,
            "source_callback_entries": 1,
            "A_external_interrupt_requested": true,
            "A_release_attempts": 1,
            "A_release_ACKs": 0,
            "A_raw_reads": 0,
            "A_terminal_after_release_attempt": true,
            "B_trusted_callbacks": 0,
            "B_allocations": 0,
            "factory_poisoned_after_A": true
          },
          "secret_cause_exposed": false,
          "archive_read_calls": 0,
          "title_observations": 0
        }
      }
    ],
    "preservation_observer_scenes": [
      {
        "case_id": "session-preservation-canonical-actual-field-comparison",
        "stimulus": {
          "delivered_projection_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "captured_source_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "retained_projection_at_reference": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "observed_owned_canonical_record": {
            "domain": "device_usage",
            "lineage": {
              "acquisition": "synthetic_fixture",
              "dataset_id": "synthetic-dataset-a",
              "device": {
                "state": "known",
                "value": "synthetic-device-a"
              },
              "installation": {
                "state": "known",
                "value": "synthetic-install-a"
              },
              "integrity_binding": "fixture_only_not_authentication",
              "original_record": {
                "state": "known",
                "value": "synthetic-session-original"
              },
              "purpose": "synthetic_local_collection",
              "record_revision": "1",
              "source_id": "synthetic-source-a",
              "source_observation": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "source_revision": "synthetic-source-contract1"
            },
            "payload": {
              "app": {
                "app_class": "non_browser",
                "display_label": {
                  "reason": "not_reported",
                  "state": "unknown"
                },
                "identity": {
                  "state": "known",
                  "value": "synthetic-nonbrowser-app"
                },
                "identity_kind": "synthetic_application_id"
              },
              "device_state": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "duration": {
                "bits": "3ff0000000000000",
                "representation": "binary64",
                "unit": "second"
              },
              "duration_basis": "synthetic_observation",
              "end": {
                "certainty": "observed",
                "instant": {
                  "epoch": "unix",
                  "epoch_seconds": "1",
                  "nanoseconds": 0,
                  "representation": "seconds_nanos",
                  "source_resolution": "nanosecond_representation_not_accuracy",
                  "uncertainty": {
                    "reason": "not_reported",
                    "state": "unknown"
                  }
                }
              },
              "observation_intervals": [],
              "start": {
                "certainty": "observed",
                "instant": {
                  "epoch": "unix",
                  "epoch_seconds": "0",
                  "nanoseconds": 0,
                  "representation": "seconds_nanos",
                  "source_resolution": "nanosecond_representation_not_accuracy",
                  "uncertainty": {
                    "reason": "not_reported",
                    "state": "unknown"
                  }
                }
              },
              "title": {
                "reason": "no_title_grant",
                "state": "not_observed"
              }
            },
            "payload_kind": "foreground_app_session",
            "payload_revision": 1,
            "record_id": "synthetic-usage-session-1",
            "time": {
              "calendar": {
                "owner_date": {
                  "reason": "not_reported",
                  "state": "unknown"
                },
                "owner_rule": {
                  "reason": "not_reported",
                  "state": "unknown"
                },
                "time_zone": {
                  "reason": "not_reported",
                  "state": "unknown"
                }
              },
              "captured_at": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "imported_at": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "instant": {
                "epoch": "unix",
                "epoch_seconds": "0",
                "nanoseconds": 0,
                "representation": "seconds_nanos",
                "source_resolution": "nanosecond_representation_not_accuracy",
                "uncertainty": {
                  "reason": "not_reported",
                  "state": "unknown"
                }
              },
              "observed_at": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "source_utc_offset_seconds": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "uploaded_at": {
                "reason": "not_reported",
                "state": "unknown"
              }
            }
          },
          "observed_status_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "expected": {
          "original_bits_preserved": true,
          "archive_read_calls": 0,
          "product_raw_evidence_returns": 0,
          "source_reference_lookup_count": 1,
          "canonical_record_comparisons": 1
        }
      },
      {
        "case_id": "session-preservation-rejects-success-with-altered-duration",
        "stimulus": {
          "delivered_projection_json": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "captured_source_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "retained_projection_at_reference": "{\"clock_basis\":\"synthetic_observation\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"absent\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"synthetic_observation\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"1\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"epoch\":\"unix\",\"epoch_seconds\":\"0\",\"nanoseconds\":0,\"representation\":\"seconds_nanos\",\"source_resolution\":\"nanosecond_representation_not_accuracy\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "observed_owned_canonical_record": {
            "domain": "device_usage",
            "lineage": {
              "acquisition": "synthetic_fixture",
              "dataset_id": "synthetic-dataset-a",
              "device": {
                "state": "known",
                "value": "synthetic-device-a"
              },
              "installation": {
                "state": "known",
                "value": "synthetic-install-a"
              },
              "integrity_binding": "fixture_only_not_authentication",
              "original_record": {
                "state": "known",
                "value": "synthetic-session-original"
              },
              "purpose": "synthetic_local_collection",
              "record_revision": "1",
              "source_id": "synthetic-source-a",
              "source_observation": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "source_revision": "synthetic-source-contract1"
            },
            "payload": {
              "app": {
                "app_class": "non_browser",
                "display_label": {
                  "reason": "not_reported",
                  "state": "unknown"
                },
                "identity": {
                  "state": "known",
                  "value": "synthetic-nonbrowser-app"
                },
                "identity_kind": "synthetic_application_id"
              },
              "device_state": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "duration": {
                "bits": "4000000000000000",
                "representation": "binary64",
                "unit": "second"
              },
              "duration_basis": "synthetic_observation",
              "end": {
                "certainty": "observed",
                "instant": {
                  "epoch": "unix",
                  "epoch_seconds": "1",
                  "nanoseconds": 0,
                  "representation": "seconds_nanos",
                  "source_resolution": "nanosecond_representation_not_accuracy",
                  "uncertainty": {
                    "reason": "not_reported",
                    "state": "unknown"
                  }
                }
              },
              "observation_intervals": [],
              "start": {
                "certainty": "observed",
                "instant": {
                  "epoch": "unix",
                  "epoch_seconds": "0",
                  "nanoseconds": 0,
                  "representation": "seconds_nanos",
                  "source_resolution": "nanosecond_representation_not_accuracy",
                  "uncertainty": {
                    "reason": "not_reported",
                    "state": "unknown"
                  }
                }
              },
              "title": {
                "reason": "no_title_grant",
                "state": "not_observed"
              }
            },
            "payload_kind": "foreground_app_session",
            "payload_revision": 1,
            "record_id": "synthetic-usage-session-1",
            "time": {
              "calendar": {
                "owner_date": {
                  "reason": "not_reported",
                  "state": "unknown"
                },
                "owner_rule": {
                  "reason": "not_reported",
                  "state": "unknown"
                },
                "time_zone": {
                  "reason": "not_reported",
                  "state": "unknown"
                }
              },
              "captured_at": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "imported_at": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "instant": {
                "epoch": "unix",
                "epoch_seconds": "0",
                "nanoseconds": 0,
                "representation": "seconds_nanos",
                "source_resolution": "nanosecond_representation_not_accuracy",
                "uncertainty": {
                  "reason": "not_reported",
                  "state": "unknown"
                }
              },
              "observed_at": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "source_utc_offset_seconds": {
                "reason": "not_reported",
                "state": "unknown"
              },
              "uploaded_at": {
                "reason": "not_reported",
                "state": "unknown"
              }
            }
          },
          "observed_status_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "expected": {
          "original_bits_preserved": false,
          "archive_read_calls": 0,
          "product_raw_evidence_returns": 0,
          "source_reference_lookup_count": 1,
          "canonical_record_comparisons": 1
        }
      },
      {
        "case_id": "session-preservation-native-reference-retained-without-inline-archive",
        "stimulus": {
          "delivered_projection_json": "{\"clock_basis\":\"native_source_arithmetic\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"known\",\"value\":\"Foundation.Date.timeIntervalSince;source_revision=2955ed07db9c649c77a128db59aed2ac0fef0bc5\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"native_source_arithmetic\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3ff199999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "captured_source_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "retained_projection_at_reference": "{\"clock_basis\":\"native_source_arithmetic\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"known\",\"value\":\"Foundation.Date.timeIntervalSince;source_revision=2955ed07db9c649c77a128db59aed2ac0fef0bc5\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"native_source_arithmetic\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3ff199999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "observed_owned_canonical_record": null,
          "observed_status_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          }
        },
        "expected": {
          "original_bits_preserved": true,
          "archive_read_calls": 0,
          "product_raw_evidence_returns": 0,
          "source_reference_lookup_count": 1,
          "canonical_record_comparisons": 0
        }
      },
      {
        "case_id": "session-preservation-native-reference-crosswire-is-false",
        "stimulus": {
          "delivered_projection_json": "{\"clock_basis\":\"native_source_arithmetic\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"known\",\"value\":\"Foundation.Date.timeIntervalSince;source_revision=2955ed07db9c649c77a128db59aed2ac0fef0bc5\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"native_source_arithmetic\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3ff199999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "captured_source_reference": {
            "state": "known",
            "value": "synthetic-source-evidence-a"
          },
          "retained_projection_at_reference": "{\"clock_basis\":\"native_source_arithmetic\",\"local_start_text\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_algorithm\":{\"state\":\"known\",\"value\":\"Foundation.Date.timeIntervalSince;source_revision=2955ed07db9c649c77a128db59aed2ac0fef0bc5\"},\"original_end\":\"present\",\"record\":{\"domain\":\"device_usage\",\"lineage\":{\"acquisition\":\"synthetic_fixture\",\"dataset_id\":\"synthetic-dataset-a\",\"device\":{\"state\":\"known\",\"value\":\"synthetic-device-a\"},\"installation\":{\"state\":\"known\",\"value\":\"synthetic-install-a\"},\"integrity_binding\":\"fixture_only_not_authentication\",\"original_record\":{\"state\":\"known\",\"value\":\"synthetic-session-original\"},\"purpose\":\"synthetic_local_collection\",\"record_revision\":\"1\",\"source_id\":\"synthetic-source-a\",\"source_observation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_revision\":\"synthetic-source-contract1\"},\"payload\":{\"app\":{\"app_class\":\"non_browser\",\"display_label\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"identity\":{\"state\":\"known\",\"value\":\"synthetic-nonbrowser-app\"},\"identity_kind\":\"synthetic_application_id\"},\"device_state\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"duration\":{\"bits\":\"3ff0000000000000\",\"representation\":\"binary64\",\"unit\":\"second\"},\"duration_basis\":\"native_source_arithmetic\",\"end\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3ff199999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"observation_intervals\":[],\"start\":{\"certainty\":\"observed\",\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"title\":{\"reason\":\"no_title_grant\",\"state\":\"not_observed\"}},\"payload_kind\":\"foreground_app_session\",\"payload_revision\":1,\"record_id\":\"synthetic-usage-session-1\",\"time\":{\"calendar\":{\"owner_date\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"owner_rule\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"time_zone\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"captured_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"imported_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"instant\":{\"bits\":\"3fb999999999999a\",\"epoch\":\"apple_reference_2001\",\"representation\":\"binary64_epoch_seconds\",\"source_resolution\":\"binary64_storage\",\"uncertainty\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}},\"observed_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"source_utc_offset_seconds\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"uploaded_at\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}},\"source_utc_offset\":{\"reason\":\"not_reported\",\"state\":\"unknown\"}}",
          "observed_owned_canonical_record": null,
          "observed_status_reference": {
            "state": "known",
            "value": "synthetic-other-evidence"
          }
        },
        "expected": {
          "original_bits_preserved": false,
          "archive_read_calls": 0,
          "product_raw_evidence_returns": 0,
          "source_reference_lookup_count": 1,
          "canonical_record_comparisons": 0
        }
      }
    ],
    "failure_priority": [
      "actual_owned_cleanup_failed",
      "external_interruption",
      "original_scope_closed",
      "ordinary_use_or_source_failure"
    ],
    "ownership_bounds": {
      "same_factory_pending_slot": 1,
      "maximum_owned_original_lease": 1,
      "current_callback_capture_once": true,
      "archive_read_port": false,
      "native_basis_admission": false
    }
  }
} as const;
